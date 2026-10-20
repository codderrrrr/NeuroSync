# NeuroSync — Agent Instructions

## Project

Read `docs/PROJECT.md` before implementing product functionality.

NeuroSync is a modular monolith for longitudinal Parkinson's motor monitoring and care coordination.

## Stack

Backend:
- Python 3.13+
- FastAPI
- PostgreSQL
- SQLAlchemy 2.0 (async)
- Alembic
- Pydantic 2
- pytest / pytest-asyncio / httpx
- Ruff (lint + format)
- mypy

Frontend:
- Flutter (patient app + doctor app web/mobile)

Use `uv` for Python dependency management.

Do not introduce microservices, Kubernetes, event buses, or distributed infrastructure unless explicitly requested.

## Key Commands

### Setup
```bash
uv sync --all-extras              # install deps (incl. dev)
cp .env.example .env              # configure env
docker compose up -d              # start PostgreSQL
uv run alembic upgrade head       # apply migrations
```

### Development Server
```bash
uv run uvicorn neurosync.main:app --reload --host 0.0.0.0 --port 8000
# API: http://localhost:8000
# Docs: http://localhost:8000/docs (dev only)
```

### Testing
```bash
uv run pytest                     # all tests (needs DB + migrations)
uv run pytest tests/unit          # unit tests only
uv run pytest tests/integration   # integration tests only
uv run pytest -k "test_name"      # single test filter
uv run pytest --cov=src/neurosync --cov-report=term-missing  # with coverage
```

Tests require PostgreSQL running and migrations applied. The test suite:
- Uses `NullPool` so no connection outlives its test
- Runs `alembic upgrade head` once per session (`migrated_database` fixture)
- Truncates domain tables before each test (`clean_database` fixture)
- `assessment_definitions` table is NOT truncated (seeded reference data)

### Code Quality (run in order)
```bash
uv run ruff check .               # lint
uv run ruff format --check .      # format check
uv run ruff check --fix .         # auto-fix lint
uv run ruff format .              # auto-format
uv run mypy src/neurosync         # type check
```

CI runs: `lint -> typecheck -> test -> build`

### Database Migrations
```bash
uv run alembic revision --autogenerate -m "description"  # create migration
uv run alembic upgrade head                                # apply
uv run alembic downgrade -1                                # rollback
uv run alembic history                                     # show history
```
Every schema change requires a migration. Never use `create_all`.

### Development Scripts
```bash
# Seed a dev doctor (refuses in production)
uv run python -m neurosync.scripts.seed_doctor "Dr. Name" ABC123

# Seed monitoring plan for patient(s) (idempotent, refuses in production)
uv run python -m neurosync.scripts.seed_monitoring
uv run python -m neurosync.scripts.seed_monitoring patient@example.com

# Seed full doctor portal scenario (doctor + code + patient + pending link)
uv run python -m neurosync.scripts.seed_doctor_portal
```

### Flutter Apps
```bash
cd apps/patient_app || cd apps/doctor_app
flutter pub get --enforce-lockfile
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
flutter build bundle --debug         # verify compiles
flutter build web --release          # doctor_app only (web portal)
```

## Architecture

Modular monolith organized around business capabilities:

```
src/neurosync/
├── config/          # settings, logging
├── db/              # SQLAlchemy engine, session, base
├── api/             # app-wide routes (health)
├── modules/         # feature modules (domain + persistence + API)
│   ├── auth/              # patient signup, login, sessions
│   ├── check_ins/         # symptom check-ins
│   ├── doctor/            # doctor portal auth + patient roster
│   ├── doctor_linking/    # doctor codes + patient link requests
│   ├── medication/        # medication context for sessions
│   └── monitoring/        # catalog, plans, sessions, quality, features
└── scripts/         # dev-only helpers
```

Each module typically contains: `models.py`, `schemas.py`, `service.py`, `router.py`, `dependencies.py`, `__init__.py`

Tests live in top-level `tests/`:
- `tests/unit/` — domain logic, pure functions
- `tests/integration/` — API endpoints, DB interactions

## Database

- PostgreSQL is the source of truth
- Every schema change requires an Alembic migration
- Never modify production schema implicitly from application startup
- Use transactions deliberately
- Enforce important invariants at the database or domain boundary
- Do not store derived data as authoritative source data unless explicitly required
- Test engine uses `NullPool`; production uses pooled engine

## API Conventions

- Use typed Pydantic schemas for all request/response bodies
- Validate inputs at boundaries
- Enforce authorization at the application boundary
- Do not expose internal database models directly as public API contracts
- Return explicit errors for invalid operations
- Patient-scoped endpoints derive patient from authenticated session; no patient ID in requests
- Doctor endpoints use separate session cookie/table; patient tokens cannot auth doctor routes

## Clinical Safety (Hard Constraints)

NeuroSync must NOT:
- diagnose disease
- stage disease
- prescribe medication
- recommend medication dosage
- autonomously recommend treatment

Clinical interpretation must expose:
- supporting evidence
- data quality
- medication context
- evidence/confidence level
- limitations

Poor-quality or insufficient data must not silently generate clinical conclusions.

## Monitoring Assessment Catalog

- Catalog is reference data seeded by migration `0004`, re-synced by `0010` and `0011`
- Four tests defined: `finger_tapping`, `spiral_drawing`, `line_tracing`, `handwriting`
- Only `finger_tapping` and `line_tracing` are `is_supported=true` (handed out today)
- `is_supported` is the single guard: checked at assignment, plan listing, session start, edit
- `ParameterSpec` in `assessment_catalog.py` is the only source of truth for settings keys, bounds, defaults
- Execution type (`tap` vs `canvas`) decided by catalog `execution_type`, never by client

## Agent Workflow

For every non-trivial task:

1. Inspect the relevant repository files.
2. Identify the existing pattern.
3. State a short implementation plan.
4. Implement only the requested capability.
5. Add/update tests.
6. Run relevant verification (lint -> typecheck -> narrow tests -> full suite).
7. Review the diff.
8. Report changed files and verification results.

Do not implement unrelated work.
Do not rewrite working code without a concrete reason.
Do not claim tests passed unless they were actually run.
Do not invent files, APIs, dependencies, results, or requirements.
If requirements conflict or are materially ambiguous, stop and ask.

## Scope Control

Implement one vertical slice at a time.

A vertical slice delivers observable behavior across necessary layers.

Example:
- "Doctor can enroll a patient" ✓
- "Create the patient database model" ✗

Do not implement an entire module when one capability is requested.

## Git

- Keep commits small and coherent
- Use conventional commit messages
- Never force-push
- Never rewrite history unless explicitly requested
- Do not commit secrets, credentials, tokens, local databases, generated artifacts, or environment files containing secrets

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_NAME` | Application name | `NeuroSync` |
| `APP_VERSION` | Application version | `0.1.0` |
| `ENVIRONMENT` | Environment (development/production/test) | `development` |
| `DEBUG` | Debug mode | `false` |
| `HOST` | Server host | `0.0.0.0` |
| `PORT` | Server port | `8000` |
| `DATABASE_URL` | PostgreSQL connection URL | `postgresql+asyncpg://neurosync:neurosync@localhost:5432/neurosync` |
| `LOG_LEVEL` | Logging level | `INFO` |
| `LOG_FORMAT` | Log format (json/console) | `json` |
| `CORS_ORIGINS` | Allowed CORS origins | `["http://localhost"]` |

Development `.env` overrides: `DEBUG=true`, `LOG_LEVEL=DEBUG`, `LOG_FORMAT=console`