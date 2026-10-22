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
# The shared package (design system, networking, sign-in lifecycle)
cd packages/neurosync_core
flutter pub get --enforce-lockfile
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test

# The two applications
cd apps/patient_app || cd apps/doctor_app
flutter pub get --enforce-lockfile
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
flutter build bundle --debug         # verify compiles
flutter build web --release          # doctor_app only (web portal)
```

**`packages/neurosync_core` is a path dependency of both apps.** Anything
shared between them (theme, API client, session store, sign-in controller,
common widgets, `ApiStateController`) belongs there, not in one app. Each app
keeps only what is its own: its screens, its endpoints, and the user model.
Both apps' `pubspec.lock` files must be regenerated and committed when the
package's dependencies change, or CI's `--enforce-lockfile` fails.

### The design system

The palette is a `ThemeExtension`, not a set of constants, because the same
token has to mean two things: ink on cool near-white in the light, ink on slate
in the dark.

```dart
final AppColors colors = AppColors.of(context);
Text('Hello', style: TextStyle(color: colors.label))
```

- `AppColors.light` / `AppColors.dark` — the two moods, both measured for
  WCAG AA (body text clears AAA). The neutrals are **blue-grey, not warm**:
  a warm ivory reads as yellow once it is a whole screen, and a patient who
  finds it unpleasant finds it on every page.
- `AppTheme.light()` / `AppTheme.dark()` — install a mood's colours
- `AppMetrics.comfortable` / `AppMetrics.compact` — how big the controls and
  the headings are. The patient app asks for `compact`; the portal asks for
  `comfortable`. Body text is never scaled: a phone in one hand wants tighter
  headings, not smaller words.
- `AppTheme.bodyLineHeight` (1.5) — body text never goes tighter
- `ThemeController` + `ThemePrefs` — the patient's choice of mood, persisted
  with the secure store, read before the first frame

**Never hardcode a colour.** A token that is not in `AppColors` will not
follow the mood, and one of the two moods will be wrong.

The typefaces are **bundled, not fetched**: Plus Jakarta Sans carries the
display text, Inter the body. A runtime fetch would mean the layout reflows
once the download lands, and that a patient's data has already left the
device to get a typeface.

**Tactile controls.** A primary control in the patient app passes
`tactile: true`. The press sinks 4% and springs back, and the haptic waits
50ms so a tremor that grazes the control stays silent — the button still
activates, because the haptic is feedback and swallowing a deliberate press
would be worse than a stray tick.

**A recording is not a test.** The runners show a ring that fills, not a
counting number. A large changing digit makes the last seconds arrive as
pressure.

**A press leaves a mark.** An `InkWell` prints its splash into the ink layer
of the nearest `Material` above it. If that material sits behind an opaque
`Container` — a card, a panel, a bar, a track — the splash is painted over
and the press leaves nothing to see. So every surface here is a `Material`,
and the `InkWell` is **inside** it rather than around it. Where a sliding
capsule covers the chosen side, that side carries its own `Material` so the
mark prints above the capsule. A patient with a tremor is already unsure
whether the press landed; the app does not answer by staying silent.

### The patient app's own widgets

The patient app has its own small vocabulary, in
`apps/patient_app/lib/core/widgets/`:

- `FloatingTabBar` — the navigation bar. A floating panel with a soft shadow
  and a sliding capsule. Every destination keeps its label: five unlabelled
  icons would be a puzzle for the person using this app.
- `SoftPanel`, `StatePill` — the surfaces the patient's information sits on.
- `StatStrip` — one panel holding a row of figures, not a row of panels.
- `SegmentedToggle` — a two-way choice with both answers visible.

These are bespoke rather than Material's, because the stock controls were
built for a different person: they assume a steady hand and a screen that is
not being read at arm's length.

The shared package also carries the pieces both applications need:
`ThemeChoiceBar` (a bar of moods with a sliding thumb), `CalmLoader` (three
dots that breathe, rather than a spinner that spins), `Reveal` (content that
arrives rather than appearing) and `EmptyNote` (an empty state that says what
is missing and what to do about it).

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
│   ├── exceptions/        # specialist review queue
│   ├── medication/        # medication context for sessions
│   └── monitoring/        # catalog, plans, sessions, quality, features
└── scripts/         # dev-only helpers
```

Each module typically contains: `models.py`, `schemas.py`, `service.py`, `router.py`, `dependencies.py`, `__init__.py`

Tests live in top-level `tests/`:
- `tests/unit/` — domain logic, pure functions
- `tests/integration/` — API endpoints, DB interactions

### The patient app's five destinations

`MainShell` holds the five tabs the patient moves between, and each one is a
question they actually have when they open the app:

| Tab | Answers |
|---|---|
| **Home** | how am I doing, and what is the one thing to do next |
| **Medicine** | what am I taking |
| **Tests** | what did my recordings show, and what have I noticed |
| **Doctors** | who is looking after me |
| **Account** | who am I, how does it look, and how do I sign out |

A tab screen is a **body, not a page**: it must not bring its own
`Scaffold`, because two Scaffolds stacked on each other double the system
insets. The shell provides the one `Scaffold` and the `SafeArea`.

### The monitoring module is split by responsibility

`monitoring/service.py` is a **facade** that re-exports the names below.
Callers keep importing from it; the implementation lives in focused services:

| Module | Owns |
|---|---|
| `monitoring/errors.py` | every domain error and its message |
| `monitoring/catalog_service.py` | the assessment definitions and their rendering |
| `monitoring/plan_service.py` | what a patient was asked to do, and for how long |
| `monitoring/session_service.py` | one execution of one plan item, start to close |
| `monitoring/longitudinal_service.py` | baselines, observations, what a recording means |
| `monitoring/longitudinal.py` | the **pure** comparison rules — no I/O, no database |

The dependency order is a DAG: `errors` ← `catalog` ← `plan` ← `session` ←
`longitudinal`. Never import a service from a service it depends on.

### Patient and doctor sessions share a mechanism, not a boundary

`auth/session_support.py` holds how a session is carried, checked and handed
back. What stays separate is the boundary: the session tables, the cookie
names, the lifetimes and the error types. A doctor token must never
authenticate a patient request, and that is a property of the schema.

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

**Display metadata lives in the catalog too.** `ParameterSpec` carries
`choice_labels` (how to name a choice value) and `value_format` (how to render
a number, e.g. `"{value} time(s)"`). The API ships both, and the Flutter apps
render from them. Never hardcode a label or a format in an app: a label added
to the catalog would otherwise appear in one app and not the other.

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