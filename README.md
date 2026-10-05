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
| `GET` | `/doctor/assessments` | List the tests this doctor can assign, with each test's settings and their bounds |
| `GET` | `/doctor/patients/{patient_id}/assignments` | List the exercises this doctor assigned to one patient |
| `POST` | `/doctor/patients/{patient_id}/assignments` | Assign an exercise: choose the test, the recording length (10-600s) and its settings |
| `PATCH` | `/doctor/patients/{patient_id}/assignments/{plan_id}` | Change the title, recording length or settings of an assigned exercise |
| `DELETE` | `/doctor/patients/{patient_id}/assignments/{plan_id}` | Remove an exercise from a patient, keeping what they already recorded |
| `GET` | `/health` | Liveness probe |
| `GET` | `/health/db` | Database connectivity probe |

Check-ins store patient-reported motor symptom severity (tremor, stiffness,
slowness, balance, each 0-4) with an optional note. Ratings are stored exactly
as reported; the API performs no scoring, interpretation, or diagnosis.

### Monitoring assessments

The assessment catalog is NeuroSync-owned reference data (seeded by migration
`0004`, re-synced by `0010` and `0011`). It describes four tests —
`finger_tapping` (tap task) plus `spiral_drawing`, `line_tracing` and
`handwriting` (canvas tasks) — but only **two are handed out today**:
`finger_tapping` and `line_tracing`. Spiral drawing and handwriting have
runners and are held back until their guides are good enough to ask a patient
to use; migration `0011` clears their `is_supported` flag.

`is_supported` is the single guard for both reasons a test may be unavailable
(no runner yet, or deliberately paused), and it is enforced at every step:

* the doctor app lists the entry with a `COMING SOON` tag and will not let it be
  picked;
* assigning it returns `409 Conflict`;
* it is filtered out of `GET /monitoring/plan`, so a patient who was assigned
  one before it was held back stops seeing it — the plan row and anything
  recorded against it stay in the database;
* starting a session for it by id returns `409 Conflict`;
* editing an exercise built on it returns `409 Conflict`, for the same reason as
  the plan filter: the patient will never be asked to do that exercise, so an
  edit would report success and change nothing anyone ever sees. **Removing it
  still works**, and that is how a doctor clears one out — the doctor app opens
  the editor on what is stored, explains that the test is not being handed out
  and leaves the save button disabled.

Held back is not hidden: the catalog keeps describing every entry, so enabling
one later is a flag change rather than a new assessment.

Each catalog entry also declares the **settings a doctor may change** about
that test — `ParameterSpec` in `assessment_catalog.py` is the only place those
keys, bounds and defaults exist. Every test lets the doctor choose a speed
(`pacing`: slow / comfortable / fast), and each adds the settings that shape
its own task:

| Test | Settings beyond the recording length |
| --- | --- |
| `finger_tapping` | which `hand`, which `finger` |
| `line_tracing` | `repetitions` (1–10), `line_length_percent` (30–100) |
| `spiral_drawing` (coming soon) | `turns` (1–6), `size_percent` (40–100) |
| `handwriting` (coming soon) | the `phrase` to write (≤ 60 chars), `repetitions` (1–5) |

The API validates a doctor's values against those specs, the doctor app renders
an editor from them (`GET /doctor/assessments`), and the patient app renders
the resulting test settings from the plan item — so the three can never disagree
about what a parameter means. A value outside its bounds is rejected with
`422`, never quietly corrected: the test the patient is given has to be the
test the doctor thinks they assigned.

A monitoring plan assigns catalog items to a patient with a daily cadence. The
patient app starts a session, captures **raw events**, and submits them on
completion. The server then derives descriptive statistics and a recording
quality of `valid`, `borderline`, `incomplete` or `invalid`. These numbers
describe the recording only — there is no scoring, no comparison against norms,
and no clinical interpretation.

Which runner interprets the stream is decided by the assessment's catalog
`execution_type`, never by what the client sent:

- **Tap task** — `tap` events carrying a millisecond offset. Derived features:
  tap count, mean interval, variability, longest pause, tapping rate.
- **Canvas task** — `stroke_start` / `stroke_point` / `stroke_end` events
  carrying a sampled `x`/`y`. Strokes must nest; a stream that does not is
  rejected rather than repaired, because guessing where one movement ended
  would change the pass count quality depends on. Derived features: point and
  stroke counts, path length, mean and peak speed, path efficiency. A stroke
  where the finger never moved does not count as a completed pass, so
  "draw the line three times" is not satisfied by tapping the screen three
  times.

One `monitoring_results` row holds one execution type's features; a check
constraint keeps the tap and canvas column sets mutually exclusive so a row can
never claim to be both or neither.

A monitoring session is an ordinary row in `monitoring_sessions`, identified by
its integer id and scoped to the patient who owns it — it carries no token of
its own. Authentication sessions are the opaque ones: their random token is
returned in the response body for bearer use and is also set as an `HttpOnly`
cookie (`Secure` only in production) so browser clients work without exposing
it to scripts, and only a SHA-256 digest of it is stored, so a database leak
does not expose usable tokens.

A doctor assigns a recording length and a set of settings per exercise.
`MonitoringPlanItem.duration_seconds` holds the length override and
`MonitoringPlanItem.parameters` the validated settings; when either is null the
catalog default applies. That resolved duration is both what the patient app is
shown and what the quality of the returned recording is judged against, so a
compliant recording is never marked `invalid` for running past the catalog
default. The patient app always shows the newest active plan, so the latest
assignment is the one a patient sees.

An assigned exercise can be **edited** (`PATCH`, applying only the fields sent)
and **removed** (`DELETE`). Removing archives the plan rather than deleting it:
a recording is a clinical record, and the cascade from a deleted plan would take
the sessions, their raw events and their results with it. A removed exercise
stays visible to its doctor as archived, and removing one twice succeeds.
Editing a removed exercise reports it as not found rather than succeeding,
because the patient will never be asked to do it again and an edit that reported
success would be a change the patient never sees. The
test itself is not editable in place — switching which test a patient performs
is a different instruction, so that is a remove plus an assign, which keeps the
recordings already taken attached to the test they were taken for.

### Keeping the patient's app current

Nothing is pushed from the server. A doctor assigns an exercise, edits one, or
accepts a link request on their own machine, and the patient's app finds out by
re-reading: `MainShell` refreshes `GET /monitoring/plan` and `GET /doctor-links`
on a 20-second timer, whenever the app returns to the foreground, and whenever
the patient switches tab. Both screens also offer pull-to-refresh. A refresh
that fails is silent — the controllers keep the last good data rather than
replacing a plan the patient can still do with an error.

The tracing runner draws the patient's own marks back onto the canvas as they
move, from the same points the session submits, with the guide underneath. A
finished pass and the pass still under the finger are drawn in different
weights, and a pill per requested pass shows how many are done, so "how much is
left" is legible mid-movement. Once every requested pass is drawn the runner
says so and offers to send immediately rather than making the patient wait out
the recording window.

### What canvas recordings do not do yet

A canvas recording is described and quality-checked, but it is **not** compared
against a baseline. The longitudinal layer is defined over finger-tapping
features, and building a second comparison per canvas assessment is separate
work. Until that exists a canvas session reports no longitudinal state, and the
medication-timing step is not offered for it — dose timing is supporting
context for a comparison, and there is no comparison for it to support. It is
rejected rather than accepted-and-dropped, which would read as the patient
declining to give their medication.

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