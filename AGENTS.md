# NeuroSync — Agent Instructions

## Project

Read `docs/PROJECT.md` before implementing product functionality.

NeuroSync is a modular monolith for longitudinal Parkinson's motor monitoring and care coordination.

## Stack

Backend:
- Python
- FastAPI
- PostgreSQL
- SQLAlchemy
- Alembic
- Pydantic
- pytest
- Ruff
- mypy

Use `uv` for Python dependency management.

Do not introduce microservices, Kubernetes, event buses, or distributed infrastructure unless explicitly requested.

## Engineering principles

- Prefer the simplest correct implementation.
- Do not build speculative abstractions.
- Do not implement future features "for extensibility".
- Reuse existing project patterns.
- Keep functions and modules focused.
- Prefer explicit code over clever code.
- Do not duplicate business rules.
- Do not put business logic in API routes.
- Keep persistence concerns separate from domain logic.
- Validate external input at system boundaries.
- Fail explicitly rather than silently recovering from invalid state.
- Do not add dependencies without justification.

## Architecture

Use a modular monolith.

Organize code around business capabilities rather than technical layers alone.

A feature should normally contain:
- domain logic
- persistence
- API/application layer
- tests

Keep module boundaries explicit.

Do not create a separate service for every module.

## Database

- PostgreSQL is the source of truth.
- Every schema change requires an Alembic migration.
- Never modify production schema implicitly from application startup.
- Use transactions deliberately.
- Enforce important invariants at the database or domain boundary.
- Do not store derived data as authoritative source data unless explicitly required.

## API

- Use typed Pydantic schemas.
- Validate inputs.
- Enforce authorization at the application boundary.
- Do not expose internal database models directly as public API contracts.
- Return explicit errors for invalid operations.

## Testing

Every feature requires tests.

Prefer:
1. domain/unit tests
2. API/integration tests
3. end-to-end tests for important user journeys

Tests must verify behavior, not merely implementation details.

After changes, run the narrowest relevant tests first, then the full suite when appropriate.

## Clinical safety

NeuroSync must not:
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

## Agent workflow

For every non-trivial task:

1. Inspect the relevant repository files.
2. Identify the existing pattern.
3. State a short implementation plan.
4. Implement only the requested capability.
5. Add/update tests.
6. Run relevant verification.
7. Review the diff.
8. Report changed files and verification results.

Do not implement unrelated work.

Do not rewrite working code without a concrete reason.

Do not claim tests passed unless they were actually run.

Do not invent files, APIs, dependencies, results, or requirements.

If requirements conflict or are materially ambiguous, stop and ask.

## Scope control

Implement one vertical slice at a time.

A vertical slice should deliver observable behavior across the necessary layers.

Example:

"Doctor can enroll a patient"

is preferable to:

"Create the patient database model."

Do not implement an entire module when one capability is requested.

## Git

Keep commits small and coherent.

Use conventional commit messages.

Never force-push.

Never rewrite history unless explicitly requested.

Do not commit secrets, credentials, tokens, local databases, generated artifacts, or environment files containing secrets.
