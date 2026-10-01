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
├── modules/         # Business feature modules (domain, persistence, API, tests)
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
├── patient_app/     # Flutter patient application
└── doctor_web/      # Doctor web portal (Vite + React + TypeScript)
```

## Architecture

NeuroSync follows a **modular monolith** architecture:

- Code organized around business capabilities
- Each module contains domain logic, persistence, API layer, and tests
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
| `POST` | `/doctor/auth/login` | Sign a doctor in to the portal |
| `POST` | `/doctor/auth/logout` | Revoke the doctor's portal session (idempotent) |
| `GET` | `/doctor/auth/me` | Return the authenticated doctor |
| `GET` | `/doctor/patients` | List the doctor's accepted patients |
| `GET` | `/doctor/patient-links/pending` | List pending patient requests, longest-waiting first |
| `POST` | `/doctor/patient-links/{link_id}/accept` | Accept a pending patient request |
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

Sessions are opaque random tokens and only a SHA-256 digest is stored, so a
database leak does not expose usable tokens. The raw token is returned in the
response body for bearer use and is also set as an `HttpOnly` cookie (`Secure`
only in production) so browser clients work without exposing it to scripts.
Doctor acceptance is not implemented yet, so links remain `pending`.

The Flutter patient application lives in `apps/patient_app` — see its
`README.md` for setup and run instructions.

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

## Doctor Web Portal

The doctor-facing web client lives in `apps/doctor_web` (Vite + React + Type
Script; no other runtime dependencies). It is a desktop clinical workspace:
login → dashboard → patient detail.

```bash
# Provision the demo scenario (doctor + code + patient + pending link)
uv run python -m neurosync.scripts.seed_doctor_portal

# Run the backend
uv run uvicorn neurosync.main:app --reload --port 8000

# Run the portal (proxies /api to localhost:8000)
cd apps/doctor_web && npm install && npm run dev
```

The seeded doctor signs in with `doctor@example.com` / `portal-dev-password`
(development only).

What the first doctor slice implements:

- **Doctor authentication** at `/doctor/auth/*` with the same security
  principles as patient auth: scrypt password hashes only, opaque session
  tokens persisted as SHA-256 digests, 7-day expiry, revocable sessions, and
  a separate `doctor_sessions` table plus a separate session cookie, so a
  patient token can never authenticate a doctor endpoint and vice versa.
- **Pending patient requests.** When a patient links with a doctor code, the
  request stays `pending`. The doctor sees it under *Pending requests* with
  the patient identity and request date.
- **Accept patient.** Accepting moves the link to `active` and records
  `accepted_at`. Accepting is idempotent; another doctor's request (or an
  unknown link) returns `404`, indistinguishable from a missing link.
- **Active patient roster.** Accepted patients appear with their link status
  and acceptance date. Clicking one opens a basic patient detail page with
  explicit *Coming in the next phase* sections for monitoring, check-ins and
  assessments — no clinical data is shown or fabricated.

Scope notes:

- Doctor linking controls the care-team relationship only.
- Monitoring plans remain independent of doctor linking in the current
  patient MVP; the plan's `doctor_id` column is reserved for later use.
- Doctor plan creation is **not** implemented yet. Monitoring-plan creation,
  assessment assignment and review of monitoring results arrive in later
  doctor workflow slices.
- The Flutter patient application is unchanged by this slice.

Portal checks: `npm run build`, `npm run lint`, `npm test` (Vitest +
Testing Library) inside `apps/doctor_web`.

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
| `CORS_ORIGINS` | Allowed CORS origins | `["http://localhost:3000"]` |

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