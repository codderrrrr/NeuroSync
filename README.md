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
├── api/             # API routes (health, etc.)
├── modules/         # Business feature modules (domain, persistence, API, tests)
└── main.py          # FastAPI application entry point

alembic/             # Database migrations
tests/               # Test suite
  ├── unit/          # Unit tests
  └── integration/   # Integration tests
```

## Architecture

NeuroSync follows a **modular monolith** architecture:

- Code organized around business capabilities
- Each module contains domain logic, persistence, API layer, and tests
- Clean separation between configuration, database, API, and modules
- PostgreSQL as the single source of truth
- Every schema change requires an Alembic migration

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