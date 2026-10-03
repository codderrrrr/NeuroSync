# NeuroSync

NeuroSync is a longitudinal Parkinson's motor-monitoring and care-coordination platform.

## Quick Start

### Prerequisites

- Python 3.13+
- [uv](https://docs.astral.sh/uv/) for dependency management
- Docker and Docker Compose (for PostgreSQL)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd neurosync

# Install dependencies
uv sync --all-extras

# Copy environment configuration
cp .env.example .env
# Edit .env with your settings if needed
```

### Running Locally

```bash
# Start PostgreSQL
docker compose up -d

# Run database migrations
uv run alembic upgrade head

# Start the development server
uv run uvicorn neurosync.main:app --reload --host 0.0.0.0 --port 8000
```

The API will be available at:
- **API**: http://localhost:8000
- **Health Check**: http://localhost:8000/health
- **Database Health**: http://localhost:8000/health/db
- **API Docs** (dev only): http://localhost:8000/docs

### Running Tests

Tests run against the database configured by `DATABASE_URL`, so start PostgreSQL
and apply migrations (`docker compose up -d && uv run alembic upgrade head`) first.
The Flutter applications have their own suites; see their sections below.

```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov=src/neurosync --cov-report=term-missing

# Run only unit tests
uv run pytest tests/unit

# Run only integration tests
uv run pytest tests/integration
```

### Code Quality

```bash
# Run linter (Ruff)
uv run ruff check .

# Fix linting issues
uv run ruff check --fix .

# Format code
uv run ruff format .

# Type check (mypy)
uv run mypy src/neurosync
```

### Database Migrations

```bash
# Create a new migration
uv run alembic revision --autogenerate -m "description"

# Apply migrations
uv run alembic upgrade head

# Rollback last migration
uv run alembic downgrade -1

# Show migration history
uv run alembic history
```

## Project Structure

```
src/neurosync/
├── config/          # Configuration (settings, logging)
├── db/              # Database layer (SQLAlchemy, sessions)
├── api/             # App-wide routes (health)
├── modules/         # Business feature modules (domain, persistence, API)
│   ├── auth/            # Patient signup, login, sessions
│   ├── check_ins/       # Patient-reported symptom check-ins
│   ├── doctor/          # Doctor portal auth + patient roster
│   ├── doctor_linking/  # Doctor codes and patient link requests
│   └── monitoring/      # Assessment catalog, plans, sessions, quality
├── scripts/         # Development-only helper scripts
└── main.py          # FastAPI application entry point

alembic/             # Database migrations
tests/               # Test suite
  ├── unit/          # Unit tests
  └── integration/   # Integration tests
apps/
├── patient_app/     # Flutter patient application (mobile)
└── doctor_app/      # Flutter doctor portal (web + mobile)
```

## Architecture

NeuroSync follows a **modular monolith** architecture:

- Code organized around business capabilities
- Each module contains domain logic, persistence, and its API layer; tests live
  in the top-level `tests/` tree, split into `unit/` and `integration/`
- Clean separation between configuration, database, API, and modules
- PostgreSQL as the single source of truth
- Every schema change requires an Alembic migration

## API (patient phase)

Patient-scoped endpoints always derive the patient from the authenticated
session; no endpoint accepts a patient identifier from the request.

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/auth/signup` | Create a patient account (name, email, password) and start a session |
| `POST` | `/auth/login` | Sign in and start a session |
| `POST` | `/auth/logout` | Revoke the current session (idempotent) |
| `GET` | `/auth/me` | Return the authenticated patient |
| `POST` | `/doctor-links` | Request a link using a doctor code; creates a `pending` link |
| `GET` | `/doctor-links` | List the authenticated patient's doctor links |
| `POST` | `/check-ins` | Record a symptom check-in (severity 0-4 per symptom) |
| `GET` | `/check-ins` | List the patient's check-ins, newest first (`limit` 1-100) |
| `GET` | `/check-ins/{check_in_id}` | Return one check-in owned by the patient |
| `GET` | `/assessments` | List the assessment catalog with availability |
| `GET` | `/monitoring/plan` | Return the patient's active monitoring plan (404 when none) |
| `POST` | `/monitoring/sessions` | Start a session for a plan item |
| `POST` | `/monitoring/sessions/{id}/complete` | Submit raw events and complete a session |
| `GET` | `/monitoring/sessions` | List the patient's sessions, newest first (`limit` 1-100) |
| `GET` | `/monitoring/sessions/{id}` | Return one session owned by the patient |
| `POST` | `/doctor/auth/signup` | Create a doctor account, generate a link code and start a session |
| `POST` | `/doctor/auth/login` | Sign a doctor in to the portal |
| `POST` | `/doctor/auth/logout` | Revoke the doctor's portal session (idempotent) |
| `GET` | `/doctor/auth/me` | Return the authenticated doctor |
| `GET` | `/doctor/patients` | List the doctor's accepted patients |
| `GET` | `/doctor/patient-links/pending` | List pending patient requests, longest-waiting first |
| `POST` | `/doctor/patient-links/{link_id}/accept` | Accept a pending patient request |
| `GET` | `/doctor/patients/{patient_id}/assignments` | List the exercises this doctor assigned to one patient |
| `POST` | `/doctor/patients/{patient_id}/assignments` | Assign a finger-tapping exercise (10-600s duration) |
| `GET` | `/health` | Liveness probe |
| `GET` | `/health/db` | Database connectivity probe |

Check-ins store patient-reported motor symptom severity (tremor, stiffness,
slowness, balance, each 0-4) with an optional note. Ratings are stored exactly
as reported; the API performs no scoring, interpretation, or diagnosis.

### Monitoring assessments

The assessment catalog is NeuroSync-owned reference data (seeded by migration
`0004`): only `finger_tapping` is executable today. `spiral_drawing`,
`line_tracing` and `handwriting` exist in the catalog with
`is_supported=false` and are surfaced as "Not available yet"; launching one is
rejected with `409 Conflict`.

A monitoring plan assigns catalog items to a patient with a daily cadence. The
patient app starts a session, captures **raw tap events** (offsets in
milliseconds from recording start), and submits them on completion. The server
then derives descriptive statistics (tap count, mean interval, variability,
longest pause, tapping rate) and a recording quality of `valid`,
`borderline`, `incomplete` (too short/too few taps) or `invalid` (ran too
long). These numbers describe the recording only — there is no scoring, no
comparison against norms, and no clinical interpretation.

A monitoring session is an ordinary row in `monitoring_sessions`, identified by
its integer id and scoped to the patient who owns it — it carries no token of
its own. Authentication sessions are the opaque ones: their random token is
returned in the response body for bearer use and is also set as an `HttpOnly`
cookie (`Secure` only in production) so browser clients work without exposing
it to scripts, and only a SHA-256 digest of it is stored, so a database leak
does not expose usable tokens.

A doctor assigns a recording length per exercise. `MonitoringPlanItem.duration_seconds`
holds that override; when it is null the assessment's catalog default is used.
That resolved duration is both what the patient app is shown and what the
quality of the returned recording is judged against, so a compliant recording
is never marked `invalid` for running past the catalog default. The patient app
always shows the newest active plan, so the latest assignment is the one a
patient sees.

The Flutter patient application lives in `apps/patient_app` — see its
`README.md` for setup and run instructions. Checks: `flutter analyze`,
`dart format --output=none --set-exit-if-changed lib test` and `flutter test`.

### Development doctor

Doctors cannot be created through the API in this phase. Provision one for local
testing:

```bash
uv run python -m neurosync.scripts.seed_doctor "Dr. Development" ABC123
```

The script refuses to run when `ENVIRONMENT=production`.

### Development monitoring data

Give an existing patient the default "Daily motor check-in" plan (finger
tapping, one item). Without arguments the script seeds every patient; pass one
or more emails to restrict it:

```bash
uv run python -m neurosync.scripts.seed_monitoring
uv run python -m neurosync.scripts.seed_monitoring patient@example.com
```

The script is idempotent (a patient with an active plan is skipped) and refuses
to run when `ENVIRONMENT=production`.

## Doctor Portal

The doctor-facing client is a Flutter application in `apps/doctor_app`, sharing
the backend with the patient app. It runs as a **web portal** on desktop and as
a mobile app on Android and iOS from the same codebase.

```bash
# Run the backend
uv run uvicorn neurosync.main:app --reload --port 8000

# As a web portal
cd apps/doctor_app
flutter run -d chrome --dart-define=NEUROSYNC_API_BASE_URL=http://127.0.0.1:8000

# As a mobile app (a phone cannot reach `localhost`)
flutter run --dart-define=NEUROSYNC_API_BASE_URL=http://<your-lan-ip>:8000
```

The portal adapts by width rather than shrinking: a fixed sidebar at 900px and
above, a compact icon bar below it, and a roster that is a table at 720px and
above and a list below that.

Checks: `flutter analyze`, `dart format --output=none --set-exit-if-changed lib test`,
`flutter test` and `flutter build web --release` inside `apps/doctor_app`.

To provision the demo scenario locally (doctor + link code + patient + pending
link request):

```bash
uv run python -m neurosync.scripts.seed_doctor_portal
```

The seeded doctor signs in with `doctor@example.com` / `portal-dev-password`
(development only). A doctor who signs up in the app gets a generated link code
immediately; patients type that code in the patient app to request a link.

What the doctor slice implements:

- **Doctor authentication** at `/doctor/auth/*` with the same security
  principles as patient auth: scrypt password hashes only, opaque session
  tokens persisted as SHA-256 digests, 7-day expiry, revocable sessions, and
  a separate `doctor_sessions` table plus a separate session cookie, so a
  patient token can never authenticate a doctor endpoint and vice versa.
- **Link codes.** Signup generates a unique 7-character code from an alphabet
  with no ambiguous characters (`I`/`L`/`O`/`0`/`1`), like a classroom join
  code. The doctor's profile sheet is the only place it is shown, with a
  copy-to-clipboard action.
- **Pending patient requests.** When a patient links with a doctor code, the
  request stays `pending`. The doctor sees it under *Pending requests* with
  the patient identity and request date.
- **Accept patient.** Accepting moves the link to `active` and records
  `accepted_at`. Accepting is idempotent; another doctor's request (or an
  unknown link) returns `404`, indistinguishable from a missing link.
- **Active patient roster.** Accepted patients appear with their link status
  and acceptance date.
- **Assign an exercise.** A doctor opens a linked patient and assigns a
  finger-tapping exercise with a recording length of their choosing (10-600
  seconds). This creates an active monitoring plan owned by that doctor, which
  the patient sees on their next check-in.

Scope notes:

- Doctor linking controls the care-team relationship only.
- Only assessments with a runner (`finger_tapping`) can be assigned; anything
  else returns `409 Conflict`.
- Reviewing monitoring results and check-ins in the doctor app is **not**
  implemented yet; the patient detail screen says so explicitly rather than
  showing placeholder data.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_NAME` | Application name | `NeuroSync` |
| `APP_VERSION` | Application version | `0.1.0` |
| `ENVIRONMENT` | Environment (development/production) | `development` |
| `DEBUG` | Debug mode | `false` |
| `HOST` | Server host | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `DATABASE_URL` | PostgreSQL connection URL | `postgresql+asyncpg://neurosync:neurosync@localhost:5432/neurosync` |
| `LOG_LEVEL` | Logging level | `INFO` |
| `LOG_FORMAT` | Log format (json/console) | `json` |
| `CORS_ORIGINS` | Allowed CORS origins | `["http://localhost"]` |

## Clinical Safety

NeuroSync is **observational clinical decision support** and must NOT:
- Diagnose disease
- Stage disease
- Prescribe medication
- Recommend medication dosage
- Autonomously recommend treatment

Clinical interpretation must expose:
- Supporting evidence
- Data quality
- Medication context
- Evidence/confidence level
- Limitations