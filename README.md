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
│   └── doctor_linking/  # Doctor codes and patient link requests
├── scripts/         # Development-only helper scripts
└── main.py          # FastAPI application entry point

alembic/             # Database migrations
tests/               # Test suite
  ├── unit/          # Unit tests
  └── integration/   # Integration tests
apps/
└── patient_app/     # Flutter patient application
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
| `GET` | `/health` | Liveness probe |
| `GET` | `/health/db` | Database connectivity probe |

Check-ins store patient-reported motor symptom severity (tremor, stiffness,
slowness, balance, each 0-4) with an optional note. Ratings are stored exactly
as reported; the API performs no scoring, interpretation, or diagnosis.

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