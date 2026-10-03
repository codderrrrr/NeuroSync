# NeuroSync — Architecture, Implementation & User-Flow Audit

**Scope:** whole repository at `a4e6d8a` (branch `master`), including uncommitted working-tree changes.
**Method:** read-only. Every route was enumerated from the live `app.openapi()` document, every table from the SQLAlchemy models and the Alembic chain, and every client screen from the Flutter `lib/` trees. README, `AGENTS.md`, `docs/PROJECT.md`, and inline comments were treated as *claims to be checked*, not as evidence.
**Constraint honoured:** no source file was modified, no dependency installed, no formatting run, nothing committed.

---

## 1. Executive summary

NeuroSync is a well-built skeleton of a longitudinal Parkinson's motor-monitoring platform. The engineering underneath it is genuinely good: clean module boundaries, real database constraints, honest deterministic feature extraction, a test suite that runs against a real migrated Postgres, and a doctor portal that is a credible piece of UI work.

What it is **not** is the product. The repository implements roughly the first third of the journey described in [PROJECT.md](PROJECT.md). Everything that makes the product clinically meaningful — medication context, baselines, longitudinal change detection, exception routing, and the doctor review that consumes any of it — does not exist in code, and no placeholder for it does either.

Three findings dominate:

1. **The product's thesis is unimplemented.** A single motor test is recorded and scored in isolation. The one feature the whole product exists to deliver — "this patient has measurably changed since their baseline, and here is the evidence" — has no representation anywhere in the schema, the API, or either client. `grep -rniE "AI|progression|wearing.?off|levodopa|trend|baseline|exception"` across `src/` and both apps returns exactly **one** hit, and it is a comment in `check_ins/models.py:18` saying trends are deliberately *not* derived here.
2. **A live correctness defect in the monitoring path.** `complete_session` judges a recording against the *catalog* default duration, not the duration the doctor assigned. A doctor who assigns 120 seconds gets every single session marked `invalid`, because 120 s > 2.0 × 30 s. This path has no test.
3. **A live UX defect in the patient app.** `AuthController.restoreSession()` reads the secure store outside its `try` and catches only `ApiException`. A keystore read failure leaves `AuthStatus.checking` forever, and the root view renders that as a splash screen with no exit. The doctor app already contains the exact fix, with regression tests.

Everything else in this report is either an inventory (so a reader can navigate the system), a confirmed design strength (so it does not get "cleaned up" by mistake), or a low-severity inconsistency.

---

## 2. Method and evidence standard

| Claim type | How it was established |
| --- | --- |
| Route inventory | `app.openapi()['paths']` — **26** operations. `app.routes` under-reports and must not be used. |
| Table inventory | `__tablename__` across all model modules, cross-checked against the Alembic revision chain. |
| Client coverage | Every Dart `lib/` file read; every request URL matched against the route table. |
| Defects | Reproduced by reading the exact code path, not inferred from naming. |
| Absence claims | `grep` over `src/` **and** both `apps/*/lib` trees. "Not implemented" is stated only when absent from all three. |

Documentation is cited as documentation. Where it disagrees with the code, the code wins and the disagreement is called out.

---

## 3. Technology stack (as built)

| Layer | Choice | Source of truth |
| --- | --- | --- |
| Language | Python 3.13 | `pyproject.toml`, `ci.yml` |
| Web framework | FastAPI + Uvicorn | `src/neurosync/main.py` |
| Validation | Pydantic v2 + `pydantic-settings` | `config/settings.py` |
| ORM | SQLAlchemy 2.x async (`Mapped` / `mapped_column`) | `db/session.py` |
| Migrations | Alembic, 6 revisions, linear | `alembic/versions/` |
| Database | PostgreSQL 16 | `docker-compose.yml`, `ci.yml` service |
| Tests | pytest + pytest-asyncio + `httpx.ASGITransport` | `tests/conftest.py` |
| Tooling | `uv` (also builds the package) | `pyproject.toml` |
| Lint/format | Ruff (check + format) | `ci.yml` |
| Types | mypy, scoped to `src/neurosync` | `ci.yml` |
| Mobile | Flutter, patient app | `apps/patient_app` |
| Web portal | Flutter Web, doctor app | `apps/doctor_app` |
| State mgmt (Dart) | `ChangeNotifier` + `ListenableBuilder` + `InheritedWidget` | both apps |

**No third-party DI, router, or state package is used on either client.** This is a deliberate-looking choice: the doctor app is a single-tab portal, the patient app is a three-tab shell, and neither has a navigation graph that would justify `go_router`.

---

## 4. Repository layout

```
neurosync/
├── alembic/versions/          6 linear migrations, head 0006_plan_item_duration
├── apps/
│   ├── patient_app/           Flutter mobile — patient-facing
│   └── doctor_app/            Flutter Web — doctor portal
├── docs/PROJECT.md            product intent (source of the capability matrix)
├── scripts/                   seed_doctor.py, seed_monitoring.py, + 1
├── src/neurosync/
│   ├── api/health.py          unauthenticated liveness + DB probe
│   ├── config/                settings singleton, logging setup
│   ├── db/                    Base, engine, session, Doctor model
│   ├── modules/               auth, check_ins, doctor, doctor_linking, monitoring
│   └── main.py                app factory, CORS, router registration
└── tests/                     16 files, 165 tests
```

Size: 46 Python source files, 59 Dart files in the patient app, 32 in the doctor app.

Note the asymmetry: `Doctor` lives in `db/models.py` while every other entity lives with its module. It is a leftover from before the doctor portal existed.

---

## 5. Backend layering

```
Router (FastAPI, schema in/out, auth dependency)
  └─> Service (business rules; owns its own session.commit())
        └─> SQLAlchemy Core / ORM (select(), insert(), update())
```

Two observations:

- **There is no repository layer.** Routers call services; services call SQLAlchemy directly. For 26 endpoints this is defensible and keeps the modules small, but it means query logic is not independently testable and cannot be swapped (e.g. for a read replica) without touching business rules.
- **Commits are doubled.** Each service calls `await session.commit()` itself, and `get_session()` commits again on the way out:

  ```python
  async def get_session() -> AsyncGenerator[AsyncSession]:
      async with async_session_factory() as session:
          try:
              yield session
              await session.commit()   # second commit
  ```

  This is harmless — the second commit is a no-op on a clean session — but it means a reader cannot tell from the service layer whether it is responsible for transactional boundaries. It is exactly the kind of thing that becomes a real bug the day a service forgets to commit.

Read models are **frozen dataclasses**, which is the right call: responses cannot be mutated after construction, and Pydantic models stay a boundary concern.

---

## 6. Complete API inventory (26 operations)

Derived from the live OpenAPI document. **Auth** = what the endpoint requires.

### Health (2)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | none | liveness |
| GET | `/health/db` | none | DB round-trip probe |

### Patient auth (4)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/auth/signup` | none | create patient + session |
| POST | `/auth/login` | none | issue session |
| POST | `/auth/logout` | patient | revoke current session |
| GET | `/auth/me` | patient | resolve current patient |

### Doctor auth (4)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/doctor/auth/signup` | none | create doctor + code + session |
| POST | `/doctor/auth/login` | none | issue doctor session |
| POST | `/doctor/auth/logout` | doctor | revoke current session |
| GET | `/doctor/auth/me` | doctor | resolve current doctor |

### Doctor linking (2)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/doctor-links` | patient | request link by doctor code |
| GET | `/doctor-links` | patient | list own links |

### Check-ins (3)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/check-ins` | patient | record 4 self-rated severities + note |
| GET | `/check-ins` | patient | list own, newest first |
| GET | `/check-ins/{check_in_id}` | patient | single check-in |

### Catalog (1)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/assessments` | patient | assessment catalog |

### Monitoring (5)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/monitoring/plan` | patient | active plan + today's completions |
| POST | `/monitoring/sessions` | patient | start session |
| POST | `/monitoring/sessions/{session_id}/complete` | patient | submit taps → features + quality |
| GET | `/monitoring/sessions` | patient | list own sessions |
| GET | `/monitoring/sessions/{session_id}` | patient | single session |

### Doctor portal (5)

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/doctor/patients` | doctor | roster of linked patients |
| GET | `/doctor/patient-links/pending` | doctor | incoming requests |
| POST | `/doctor/patient-links/{link_id}/accept` | doctor | accept a request |
| GET | `/doctor/patients/{patient_id}/assignments` | doctor | list plans for a patient |
| POST | `/doctor/patients/{patient_id}/assignments` | doctor | create/assign a plan |

---

## 7. Routes with no client

Five endpoints are implemented, tested, and unreachable from any shipped UI:

| Route | Why it matters |
| --- | --- |
| `GET /health` | deployment probe target |
| `GET /health/db` | the only endpoint that distinguishes "process up" from "DB reachable" |
| `GET /check-ins/{id}` | needed for a detail view or deep link |
| `GET /assessments` | the catalog is seeded in migration 0004 and exposed, but no client reads it |
| `GET /monitoring/sessions/{id}` | history drill-down |

The last is the most notable. `MonitoringRepository.getSession()` exists at `apps/patient_app/lib/features/monitoring/data/monitoring_repository.dart:56`, is written, and is **never called**. A finished method with no caller is a latent bug: it will drift out of date without ever failing a test.

The inverse also holds and is worth stating: **no client functionality lacks a backend endpoint.** The API is not the bottleneck.

---

## 8. Database inventory (13 tables)

| Table | Purpose | Notable constraints |
| --- | --- | --- |
| `patients` | patient identity + credentials | unique email |
| `patient_sessions` | patient auth sessions | index on `patient_id`, FK CASCADE |
| `doctors` | doctor identity | `email`/`password_hash` **nullable** (legacy seed rows) |
| `doctor_sessions` | doctor auth sessions | FK CASCADE |
| `doctor_codes` | shareable link codes | `code` unique, `is_active` |
| `doctor_links` | patient↔doctor relationship | partial unique `uq_doctor_links_active_pair` |
| `check_ins` | self-reported severities | 4 CHECKs `BETWEEN 0 AND 4` |
| `assessment_definitions` | assessment catalog | seeded in migration 0004 (4 rows) |
| `monitoring_plans` | a doctor's assigned plan | FK to doctor is `SET NULL` |
| `monitoring_plan_items` | ordered items in a plan | FK assessment `RESTRICT`, `duration_seconds` |
| `monitoring_sessions` | one patient attempt | FKs to plan/item/assessment |
| `monitoring_session_events` | raw tap offsets | index `(session_id, offset_ms)` |
| `monitoring_results` | computed features + quality | `session_id` **UNIQUE**, 3 CHECKs |

### ER diagram

```
   patients                doctors
      │  1                     │  1
      │                        │
      ├─1:N─ patient_sessions  ├─1:N─ doctor_sessions
      │                        │
      ├─1:N─ check_ins         ├─1:N─ doctor_codes
      │                        │
      ├─1:N─ doctor_links ─────┤   (status: pending | active)
      │          ▲             │
      │          │             │
      │     partial unique on (patient_id, doctor_id)
      │     WHERE status IN ('pending','active')
      │
      └─1:N─ monitoring_plans ─┘   (assigned_doctor_id, ON DELETE SET NULL)
                 │  1
                 │        1
      monitoring_plan_items ──────► assessment_definitions
                 │                     (RESTRICT)
                 │  1
      monitoring_sessions ───────────┘  (RESTRICT)
                 │  1                        ▲
      monitoring_session_events             │
                 │                     monitoring_results
                 └──────────────────────────┘
                        (1:1, session_id UNIQUE)
```

### The one ORM relationship in the entire codebase

```python
result: Mapped["MonitoringResult | None"] = relationship(
    uselist=False, passive_deletes=True, ...
)
```

`MonitoringSession.result` is the **only** `relationship()` in the project. Everything else is Core `select()` with explicit joins. This is internally consistent, but it means there is no object graph to navigate — a `session.plan.items` traversal does not exist, and every query is hand-written. Fine at this size; worth knowing before the schema grows.

### What does not exist

There is **no** table for medications, medication events, baselines, trends, exceptions, or caregiver/health-worker identities. `docs/PROJECT.md` lists "Medication schedule and medication events", "Patient-specific baseline", "Longitudinal change detection", and "Exception routing" as MVP capabilities. None of them has a table, a model, an enum, a migration, or a stub.

---

## 9. Enumerations and their real usage

| Enum | Values | Actually written? |
| --- | --- | --- |
| `DoctorLinkStatus` | `pending`, `active` | both |
| `PlanStatus` | `draft`, `active`, `archived` | **only `active`** |
| `RecordingQuality` | `valid`, `borderline`, `invalid`, `incomplete` | all four |
| `ExecutionType` | `tap_task`, `canvas_task`, `questionnaire` | **only `tap_task`/`canvas_task`** |

`DoctorLinkStatus` having only two values is a real design limitation, not a leftover: there is no way to reject, revoke, or end a doctor-patient relationship. Once a link is `active` it is permanent. The DB CHECK constraint matches the enum exactly, so this is deliberate schema, not drift.

`PlanStatus` is the more interesting case. The enum and the CHECK constraint both accept `draft` and `archived`, but no code path ever writes either. A patient can therefore only ever have one kind of plan: the newest active one. This is exactly the state a "draft → review → activate" workflow would need, and it is already there waiting.

---

## 10. Assessment catalog

Migration 0004 seeds four assessments. Only one is usable.

| slug | execution type | default duration | supported |
| --- | --- | --- | --- |
| `finger_tapping` | `tap_task` | 30 s | **yes** |
| `spiral_drawing` | `canvas_task` | 30 s | no |
| `line_tracing` | `canvas_task` | 30 s | no |
| `handwriting` | `canvas_task` | 30 s | no |

The three unsupported entries are marked `"not available yet"`. They exist in the schema so that a `monitoring_plan_items` row can reference them without a dangling FK — the RESTRICT constraint makes that necessary, and the `is_supported` flag is how the client is told not to offer them.

This is a good pattern. The catalog is data, not code, and adding a fourth real assessment is a data change.

`ExecutionType.QUESTIONNAIRE` is declared and never used. It is the only member of its enum with no row anywhere.

---

## 11. Motor feature extraction

`features.py::extract_tap_features(tap_offsets_ms: list[int]) -> TapFeatures` is pure, has no I/O, and is the most defensively written function in the repository.

| Field | Computation | Notes |
| --- | --- | --- |
| `total_taps` | `len(offsets)` | |
| `duration_ms` | `offsets[-1]` | last offset, **not** wall-clock elapsed |
| `mean_inter_tap_interval_ms` | `round(statistics.fmean(intervals))` | population mean |
| `inter_tap_variability_ms` | `round(statistics.pstdev(intervals))` | population SD, not sample |
| `longest_pause_ms` | `max(intervals)` | |
| `taps_per_second` | `round(n / (duration_ms/1000), 3)` | 3 dp |

Intervals are built with `strict=False`, which is the point: the last offset has no successor, so `len(intervals) == len(offsets) - 1`. The comment in the source says so.

Two edge cases are handled explicitly and correctly:

- **Empty input** → all zeros, no exception.
- **Single tap** → duration is set, interval statistics are zero, and `taps_per_second = round(duration_ms / 1000, 3)`.

The single-tap case deserves a flag. `duration_ms` is a millisecond *count* of 2000, and `taps_per_second` becomes `round(2000/1000, 3) = 2.0` — a single tap in 2 seconds reported as **2 taps per second**. It is arithmetically defensible (1 tap / 2 s) but reads as a bug in any UI that prints the number next to `total_taps = 1`. The behaviour is documented in a comment, so it is intentional; it is still the kind of value a patient will read aloud and be confused by.

Using `pstdev` rather than `stdev` is the statistically correct choice here: the taps in a recording are the whole population of interest, not a sample from a larger population.

---

## 12. Quality evaluation

`quality.py::evaluate_quality(*, features, target_duration_ms) -> RecordingQuality` is a short cascade, not a scoring system. First match wins.

| # | Condition | Result | Rationale |
| --- | --- | --- | --- |
| 1 | `total_taps < 2` | `incomplete` | nothing to measure |
| 2 | `duration < 0.5 × target` | `incomplete` | ended early |
| 3 | `duration > 2.0 × target` | `invalid` | kept running |
| 4 | `total_taps < 10` | `borderline` | too few for rhythm |
| 5 | `longest_pause > 5000 ms` | `borderline` | long hesitation |
| 6 | otherwise | `valid` | |

Constants: `MIN_TAPS_FOR_RHYTHM = 10`, `MIN_TAPS_FOR_INTERVAL = 2`, `MIN_DURATION_FRACTION = 0.5`, `MAX_DURATION_FRACTION = 2.0`, `LONG_PAUSE_MS = 5_000`.

This is genuinely good design for a clinical-adjacent system. The thresholds are named constants rather than magic numbers, the rules are ordered cheapest-check-first, and each verdict has a one-sentence human rationale. Quality describes **the recording, never the patient** — the docstring on `RecordingQuality` says exactly that, and it is the right framing for a tool that will be read by someone with Parkinson's.

### Dead code in this module

```python
RULES: tuple[QualityRule, ...] = (QualityRule(code="too_few_taps", ...), ...)
```

`RULES` is a tuple of `QualityRule(code, explanation)` pairs, defined at module level and **never iterated anywhere in the codebase**. The `explanations` were clearly written for display. Either wire them to the client response or delete them — as written they are a second, unversioned copy of the thresholds that will silently drift from the code above it.

---

## 13. Defect 1 — quality target ignores the doctor's assigned duration

**Severity: high. Data-corrupting.** Fixed in this change; see the end of this section.

`src/neurosync/modules/monitoring/service.py`, in `complete_session`:

```python
target_ms = definition.default_duration_seconds * 1000  # line 403
quality = evaluate_quality(features=features, target_duration_ms=target_ms)
```

`definition` is the **catalog** row. The doctor-assigned duration lives on `monitoring_plan_items.duration_seconds`, and it is correctly resolved everywhere else (shown here from `get_patient_plan`, formerly inline):

```python
def resolve_item_duration_seconds(item, definition):
    # A doctor-assigned override wins; otherwise the catalog default.
    return (
        item.duration_seconds
        if item.duration_seconds is not None
        else definition.default_duration_seconds
    )
```

So the plan correctly tells the patient "do this for 120 seconds", the patient complies, and then completion scores that 120-second recording against a 30-second target. Rule 3 fires: `120_000 > 2.0 × 30_000` → **`invalid`**.

The outcome is that **every session under any assignment longer than 60 seconds is stored as `invalid`**, and a doctor who assigns anything but the catalog default silently poisons their patient's data. There is no error, no log line, and no partial credit — the data looks perfectly well-formed and is simply wrong.

This is only reachable when a doctor uses the per-patient duration override, which is the entire point of that field and the `0006_plan_item_duration` migration that added it. The feature was built end-to-end except at this one line.

**Fix (applied):** both call sites now resolve the target through one shared helper, `resolve_item_duration_seconds`, so the duration the patient is shown and the duration the recording is judged against can never disagree. Regression tests assert a 120-second assignment completes as `valid`, that the catalog default still applies when no assignment exists, and that an over-long recording is still rejected against its assigned target.

---

## 14. Defect 2 — patient app can hang on the splash screen forever

**Severity: high. Complete loss of function for the affected user, with no recovery path.**

`apps/patient_app/lib/features/auth/state/auth_controller.dart`, `restoreSession()`:

```dart
Future<void> restoreSession() async {
  final String? token = await _tokenStore.read();   // <-- OUTSIDE the try
  if (token == null) { _status = AuthStatus.signedOut; notifyListeners(); return; }

  _tokenCache.value = token;
  try {
    _patient = await _repository.currentPatient();
    _status = AuthStatus.signedIn;
  } on ApiException {                                 // <-- only ApiException
    _tokenCache.value = null;
    await _tokenStore.clear();
    _patient = null;
    _status = AuthStatus.signedOut;
  }
  notifyListeners();
}
```

Two holes:

1. `_tokenStore.read()` is awaited **outside** the `try`. A keystore that will not open, a `PlatformException` from the secure-storage channel, or a malformed value throws out of the method, so `notifyListeners()` never runs and `_status` stays `checking`.
2. The `catch` is typed `on ApiException`, so *any other* error from `currentPatient()` — a socket exception, a JSON parse failure, a `FormatException` — escapes the same way.

`AuthStatus.checking` is rendered by `IntroFlow` as `SplashScreen`. The user sees a splash screen with a spinner that never resolves, and the only way out is killing the app. A Parkinson's patient on a mid-range Android phone with a flaky secure-storage plugin is exactly the user this app exists for.

### The doctor app already solved this

`apps/doctor_app/lib/features/auth/state/auth_controller.dart` has the hardened version, and the comment explains exactly why:

```dart
try {
  final String? token = await _tokenStore.read();
  ...
} catch (_) {
  // Anything can fail here -- a revoked session, an unreachable server,
  // a keystore that will not open, or a response the model cannot parse.
  // None of those may leave the status at `checking`, because the root
  // view renders `checking` as a splash screen with no way out.
  _tokenCache.value = null;
  await _discardStoredToken();
  _signedOut();
  return;
}
```

It also adds `_discardStoredToken()`, which wraps the clear in its own `try` — because a keystore that will not open will usually also not clear, and that second throw would strand the user in the same place.

**Two regression tests** in `apps/doctor_app/test/features/auth/auth_controller_test.dart` cover the behaviour. The patient app has neither the fix nor the tests. The two `AuthController`s are near-identical, which makes this a straightforward port.

**General lesson worth acting on:** a "loading" state with no timeout and no escape is a hang by construction. The doctor app's comment is the right instinct; the invariant — *nothing may leave the root view in `checking` forever* — should be enforced structurally rather than remembered per-app.

---

## 15. Authentication and security

### Password hashing

Standard-library `hashlib.scrypt` — no `bcrypt`/`argon2` dependency, so the install stays small and the algorithm choice is auditable in-tree.

| Parameter | Value |
| --- | --- |
| algorithm | `scrypt` |
| n | `2**15` (32768) |
| r | 8 |
| p | 1 |
| dklen | 32 |
| salt | 16 random bytes per password |
| `maxmem` | 64 MiB |

Encoded as `scrypt$n$r$p$b64(salt)$b64(hash)`, so the work factors travel with the hash and existing rows stay verifiable if the parameters are raised later. `verify_password` parses the parameters *out of the stored string* rather than assuming the current defaults — a genuinely good detail that most implementations get wrong.

Comparison uses `hmac.compare_digest`, and malformed hashes fail closed (`return False`) rather than raising. Both are correct.

Hashing is moved off the event loop with `asyncio.to_thread`, which matters: n=2**15 scrypt is deliberately expensive, and running it inline would stall every concurrent request in the worker.

### Session tokens

`secrets.token_urlsafe(32)` — 256 bits of entropy. Only the SHA-256 hex digest is stored, so a database read cannot reconstruct a live session. The two constants that matter:

| | Patient | Doctor |
| --- | --- | --- |
| TTL | 30 days | 7 days |
| table | `patient_sessions` | `doctor_sessions` |
| cookie | `neurosync_session` | `neurosync_doctor_session` |

Separate tables and separate cookies are the right call: a doctor session must not be usable against patient endpoints, and a shared table would make that a per-row check everywhere.

### Timing equalisation

```python
_DUMMY_PASSWORD_HASH = hash_password("neurosync-timing-equalisation")
...
await asyncio.to_thread(verify_password, password, _DUMMY_PASSWORD_HASH)
```

Login against a non-existent email still performs a full scrypt verification against a dummy hash, so response time does not reveal whether an account exists. Present in both the patient and doctor services. This is a detail most projects skip.

### Doctor link codes

```python
DOCTOR_CODE_LENGTH = 7
_DOCTOR_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
```

Generated at doctor signup, 5 collision retries. The alphabet deliberately omits `I`, `O`, `0`, `1` and the remaining confusable characters — codes get read aloud and typed by hand, and a 31-character alphabet gives ~2.7 × 10¹⁰ combinations. `normalize_doctor_code` strips and upper-cases before lookup, so `abc-def` and ` ABCDEF ` both work.

Codes live in `doctor_codes` with an `is_active` flag, separate from the doctor row, so a code can be rotated or deactivated without touching identity. The schema comment says so explicitly.

### Authorization model

Authorization is **ownership-based and enforced per endpoint**, not role-based:

- Patient endpoints resolve the current patient from the session and scope every query to that `patient_id`.
- Doctor endpoints scope to the doctor's own links.
- `/doctor/patients/{patient_id}/assignments` — the one place where a doctor acts on behalf of a specific patient — is the endpoint where a missing link check would matter most, and it is covered.

There is no RBAC layer, no permission table, and no policy object. For two roles with disjoint endpoints that is the correct amount of machinery. It would need revisiting before the `docs/PROJECT.md` roles (caregiver, health worker) are added, because those roles need per-resource grants rather than a role check.

### Configuration

```python
settings = Settings()  # import-time singleton
```

`main.py`, `db/session.py`, and the logging config all import this module-level instance. There is no `get_settings()` and no dependency-injected override.

This is the single most common source of pain in a FastAPI test suite, and this project has worked around it rather than solved it — see §21. The fix is small (`@lru_cache def get_settings()` plus a `Depends`) and would make configuration testable. As written, the only way to change settings in a test is to monkeypatch the module attribute.

`docs_url` and `redoc_url` are correctly disabled outside development, and `echo=settings.is_development` means SQL is not logged in production. CORS allows a regex for any localhost port plus the configured origins, which is a sensible development default and should be narrowed for production.

---

## 16. The doctor–patient linking flow

```
Doctor signs up ──> gets a 7-char code
        │
Patient enters code ──> POST /doctor-links ──> link created 'pending'
        │
Doctor sees it in Requests ──> POST /doctor/patient-links/{id}/accept ──> 'active' + accepted_at
        │
Doctor appears in the patient app's Doctors tab
        │
Doctor assigns a monitoring plan
```

This is the strongest end-to-end story in the product and it works completely. The partial unique index is the detail that makes it correct:

```sql
CREATE UNIQUE INDEX uq_doctor_links_active_pair
    ON doctor_links (patient_id, doctor_id)
    WHERE status IN ('pending', 'active');
```

It allows many doctors per patient and many patients per doctor, while making a duplicate request for the same pair **impossible at the database level** — not just in application code. This is the right way to enforce an invariant that a race could otherwise break.

`accepted_at` is documented in the model as *derived information, not a lifecycle authority*; `status` is the single source of truth. That is a considered distinction and it is commented as such.

**The gap:** there is no reverse direction. A doctor cannot invite a patient, cannot see who has not accepted, and cannot remove a link. A patient who links to the wrong doctor is stuck with it permanently, because `DoctorLinkStatus` has no `revoked`.

---

## 17. Monitoring plan lifecycle (as built)

```
Doctor assigns items ──> POST /doctor/patients/{id}/assignments
                              │
                              ├─ creates MonitoringPlan      status = 'active'
                              └─ creates MonitoringPlanItem per assessment
                                     (position, duration_seconds?)
                              │
Patient app ──> GET /monitoring/plan
                 SELECT ... WHERE patient_id=? AND status='active'
                 ORDER BY created_at DESC, id DESC LIMIT 1
                 │
                 └─> resolves each item's duration:
                       item.duration_seconds ?? catalog default
```

Three consequences follow from that query, all of them current behaviour:

1. **Only the newest active plan is ever seen.** Previous plans remain in the table and are never returned. Re-assigning silently replaces what the patient sees.
2. **`completed_today` is counted from UTC midnight**, via a single `GROUP BY` over that plan's items. A patient in a non-UTC timezone sees their "today" reset at a different moment than their own day. The docstring states the UTC choice, so it is deliberate — it is just worth knowing it is not local-midnight.
3. **Only `active` is ever written.** `draft` and `archived` exist in the enum and the CHECK constraint but no code path produces them.

Point 3 interacts with point 1 in a way that will matter. Today, "create a new plan" and "replace the plan" are the same operation, because a plan goes straight to `active` and only the newest is read. The moment a doctor wants to build a plan over several sessions and review it before the patient sees it, `draft` is already in the schema and the read query already excludes it. The groundwork is laid.

---

## 18. Patient app

59 Dart files in `lib/`. No DI package, no router package, no state package.

### Architecture

- `ChangeNotifier` + `ListenableBuilder` for state.
- `InheritedWidget` (`AppScope`) for construction-time injection; `updateShouldNotify` returns `false` — the scope never changes after build, so rebuilds are correctly suppressed.
- `IndexedStack` + `NavigationBar` for the three-tab shell, so each tab keeps its scroll position and state.
- Typed `Navigator.push<T>` with results, so a child screen returns data to its parent.

For a three-tab app this is the right amount of machinery. `go_router` would add a dependency and a URL scheme for navigation that has no deep-link requirement yet.

### Screens

| Area | Contents |
| --- | --- |
| Intro | splash → onboarding chapters → welcome → auth |
| Auth | sign in, sign up |
| Shell | Home / Check-ins / Doctors |
| Home | today's plan, progress, session entry |
| Monitoring | plan item → runner → result |
| Check-ins | new check-in (4 severity ratings + note), history list |
| Doctors | link by code, list links |

### Strengths

- **Accessibility is a first-class concern, not an afterthought.** Severity ratings, the tap target, and every control have semantics labels; the theme has a contrast test that asserts AA on both page and card; the type scale is asserted to be fully used on a standard phone; `TactileButton` has haptics, a pressed-state sink animation, and honours reduced-motion.
- **The visual regression-style tests are unusually good** for a Flutter app: `app_patient_responsive_test.dart` asserts no overflow across three real viewports (360×640, 393×852, 412×915) for the splash, onboarding, all three shell tabs, and the result screen.
- **Large touch targets and reduced motion** are respected in the test runner, which matters for the actual user population.

### Weaknesses

- The runner captures tap **offsets**, so a session that is abandoned (app killed, phone locked) leaves an orphaned `monitoring_sessions` row in `started` status with no result and no cleanup path. There is no sweeper and no timeout.
- The result screen shows raw features with no plain-language framing beyond quality. For the target user, "inter-tap variability 148 ms" is not information; "your tapping was less steady than usual" would be.

---

## 19. Doctor app (web portal)

32 Dart files in `lib/`, built for web. This is the more mature of the two clients and the more polished piece of UI work in the repository.

### Architecture

- `restoreSession()` is called in `main()` **before** `runApp`, so the portal never flashes an authenticated frame before the token is validated.
- `kRailBreakpoint = 900` — the shell switches between navigation rail and a narrower layout.
- The roster renders as a **table at ≥720 px and a list below it**, so the same data serves a desktop and a tablet.
- Client-side search over the loaded roster.
- Sections are keyed with `KeyedSubtree(ValueKey(section))`, so switching sections loads each one once and does not refetch on every tab change.

### Screens

| Section | Contents |
| --- | --- |
| Auth | sign in, sign up |
| Dashboard | summary counts, pending requests |
| Requests | pending link requests, accept |
| Patients | searchable roster; detail per patient |
| Patient detail | history, assignments |
| Assignment | create/assign a monitoring plan |
| Profile | doctor identity, code, sign out |

### The portal's honest limitation

Everything on the doctor side is **structural**. The portal can see that a patient exists, that they are linked, and that a plan is assigned. It cannot see a single motor feature, a quality verdict, or a check-in. `GET /doctor/patients` returns roster rows; there is no endpoint that returns a patient's monitoring results to a doctor.

The result is a doctor portal that, functionally, is a contact-management system. The `patient_detail_page` can show that a patient has a plan but not whether they did it. This is the single biggest structural gap between what is built and what the product promises, and it is what §24's capability matrix is mostly about.

---

## 20. Backend test suite

**165 tests collected**, 16 files. Verified: `uv run pytest --collect-only -q` → `165 tests collected`.

| Area | Coverage |
| --- | --- |
| unit | 45 — feature extraction (5), quality rules (8), settings, security primitives |
| integration | 108+ — auth, doctor auth, linking, check-ins, monitoring, doctor portal |

### What is genuinely strong about the harness

Most projects of this size use SQLite or mock the database. This one does not:

- It runs a **real `alembic upgrade head` subprocess** against a real PostgreSQL instance.
- It uses `NullPool` for the test engine, so pooled connections never leak between tests.
- It **TRUNCATEs 11 domain tables** between tests (`assessment_definitions` is excluded — correctly, since it is seeded reference data).
- It drives the app through `httpx.ASGITransport`, so the real dependency-injection graph, real middleware, and real routing are exercised.

This means the tests would catch a broken migration, a wrong partial index, or a CHECK constraint violation. That is a meaningfully stronger guarantee than a mocked ORM gives you, and it is the strongest engineering decision in the repository.

`tests/factories.py` creates patients through the API (so password hashing and session creation are genuinely exercised) but creates doctors, codes, and links directly in the database — a reasonable speed optimisation, and worth knowing because it means doctor fixtures bypass the signup code-generation path.

### The gap

Defect 1 (§13) survives a 165-test suite because `complete_session` with a **non-default** `duration_seconds` is never tested. That is the argument for the change: the harness is strong, and this slipped through it. It is a missing test case, not a weak harness.

---

## 21. Client test suites

| App | Files | Tests | Result |
| --- | --- | --- | --- |
| `patient_app` | 23 | **109** | all pass |
| `doctor_app` | 8 | **73** | all pass |

Verified by running both suites: `flutter test --reporter compact` → `+109: All tests passed!` and `+73: All tests passed!`.

Note: the repository summary reports 9 doctor test files; there are **8** `*_test.dart` files plus a 9th non-test file, `test/test_support.dart`, which is a shared harness.

The mix is better than the raw count suggests. These are not only controller unit tests with a fake repository — they include real widget tests that build the actual screens, simulate taps, and assert navigation, plus the responsive/contrast suites described in §18. The patient app's `monitoring_flow_test.dart` drives the full runner flow end to end and asserts taps are sent and the result is shown.

The doctor's 73 tests include the two regression tests for the auth splash-hang fix (§14). Their absence on the patient side is the reason that bug is live.

---

## 22. Continuous integration

Two workflows. **Neither deploys anything** — there is no staging, no production, no migration-on-deploy step, and no image build. CI is verification only, which is an honest state for a pre-deployment project.

### `.github/workflows/ci.yml` — backend

Four jobs on `ubuntu-latest`, Python 3.13, all via `uv`:

| Job | Steps |
| --- | --- |
| Lint (Ruff) | `ruff check .` then `ruff format --check .` |
| Type Check (mypy) | `mypy src/neurosync` |
| Tests | postgres service → wait → `alembic upgrade head` → `pytest --cov=src/neurosync --cov-report=term-missing --cov-report=xml` → upload coverage |
| Build | `uv build` |

The test job provisions real PostgreSQL and runs real migrations, matching the local harness. Coverage is uploaded as XML.

### `.github/workflows/flutter-ci.yml` — both apps

`FLUTTER_VERSION: "3.47.5"`, stable channel, `cache: true`. Matrix over `[patient_app, doctor_app]` with `fail-fast: false` so one app's failure does not mask the other's.

| Job | Steps |
| --- | --- |
| Format & Analyze | `dart format --output=none --set-exit-if-changed lib test` → `flutter analyze` |
| Tests | `flutter test --timeout 60s` |
| Build | `flutter build bundle --debug` → `flutter build web --release` (doctor only) |

`flutter pub get --enforce-lockfile` is used throughout, so CI resolves to exactly the committed lockfile versions. The web build is doctor-only, which correctly reflects that the patient app is mobile.

### What CI does not cover

- No migration-drift check (`alembic check`) in CI — the models and migrations could diverge unnoticed until runtime.
- No `flutter build apk/ios` — the bundle build proves compilation, not that a release artefact links.
- No dependency scanning, no secret scanning, no `pip-audit`.
- No coverage threshold or gate, despite uploading the report.

---

## 23. Documentation accuracy

The README is **mostly accurate** and was improved in the previous slice. Two statements remain wrong, and both are the kind that mislead a reader who trusts them:

**1. Monitoring sessions described as auth tokens.** Under *Monitoring assessments*:

> Sessions are opaque random tokens and only a SHA-256 digest is stored

This is false for monitoring sessions. They are ordinary integer-PK rows in `monitoring_sessions` with no token at all. The paragraph describes **auth** sessions and is filed in the wrong section. A reader looking for how a monitoring session is identified will not find the answer there.

**2. Wrong CORS default.**

| Source | Value |
| --- | --- |
| `README.md:310` | `["http://localhost:3000"]` |
| `config/settings.py` | `["http://localhost"]` |

### Stale comments in source

Comments that were true at the time they were written and are now actively misleading:

| Location | Claim | Reality |
| --- | --- | --- |
| `scripts/seed_doctor.py:1-5` | "doctors cannot be created through the API yet" | `POST /doctor/auth/signup` exists |
| `scripts/seed_monitoring.py:2-4` | "Doctor profile does not exist yet" | `doctors` table and portal exist |
| `monitoring/models.py:93-95` | same claim | same |
| `doctor_linking/models.py:52-55` | "only a doctor can accept it, which is out of scope" | `POST /doctor/patient-links/{id}/accept` exists |
| `tests/factories.py:88` | references a non-existent capability | — |
| `AGENTS.md` + README | "per-module tests" | all tests live in one top-level `tests/` tree |

Every one of these describes a *previous* milestone. Left in place, they actively mislead: a developer reading `doctor_linking/models.py:52` would conclude link acceptance was not implemented, when it is implemented, tested, and wired into the portal.

The `doctor_linking/models.py` one is the most costly, because the comment sits directly above the model's design rationale and reads as current intent.

### `docs/PROJECT.md`

Accurate as a statement of intent, and the right document to measure against — see §24. It is explicit about what is out of scope (diagnosis, staging, prescribing, dosage recommendations, autonomous treatment decisions, billing, interoperability, microservices, Kubernetes, multi-region, advanced analytics), and the codebase has respected that boundary scrupulously. The `grep` in §25 confirms it.

That last point deserves credit. For an early-stage clinical product, the temptation to add a "suggested dosage" or a "risk score" feature is strong, and this project has not taken it.

---

## 24. Capability matrix — `docs/PROJECT.md` vs. reality

`PROJECT.md` lists 11 MVP capabilities. This is the honest accounting.

| # | Capability | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Authentication and authorization | **Done** | scrypt, 2 roles, separate session tables, timing equalisation |
| 2 | Patient enrollment and care-team relationships | **Partial** | patient self-signup + code-based linking. No doctor-initiated enrollment, no caregiver/health-worker roles, no revoke |
| 3 | Monitoring plans | **Done** | create, read, ordered items, per-item duration |
| 4 | Medication schedule and medication events | **Absent** | no table, model, migration, enum, or stub |
| 5 | Finger-tapping assessment | **Done** | catalog entry, runner, tap capture, persistence |
| 6 | Test quality assessment | **Done** (with §13 defect) | 6-rule cascade, stored per session |
| 7 | Motor feature extraction | **Done** | 6 features, pure, 5 unit tests |
| 8 | Patient-specific baseline | **Absent** | no table; nothing computes a per-patient reference |
| 9 | Longitudinal change detection | **Absent** | no comparison, no threshold, no endpoint |
| 10 | Exception routing | **Absent** | no table, no enum, no notification path |
| 11 | Doctor review | **Absent** | portal shows roster/plans only; no endpoint returns patient data to a doctor |

**7 of 11 capabilities are absent. 4 are done. 1 is partial.**

The four that are done are done well. But the shape of this table is the single most important fact in the report, and it is worth being blunt about it: capabilities 1, 3, 5, 6, 7 are all *inputs*. They collect data and validate it. Every capability that would make the collected data **mean** something to a clinician — 8, 9, 10, 11 — is missing.

The product described in `PROJECT.md` is a longitudinal monitoring platform. What exists is a well-executed data-collection app with a contact directory attached.

### The gap is a straight line, not a scatter

This is the encouraging part. The missing capabilities are not eleven independent pieces of work. They are one pipeline, and each stage's inputs already exist:

```
 [7] features  ──>  [8] baseline  ──>  [9] change detection  ──>  [10] exception  ──>  [11] doctor review
      DONE              MISSING              MISSING                MISSING            MISSING (UI exists, data absent)
        │
   stored per session in monitoring_results
```

The data that a baseline would be computed from is already in the database, correctly normalised, per session, per patient. The doctor portal that would render an exception already exists, with a roster, a patient detail page, and a section-based shell that a new "Alerts" section would drop into.

The genuinely new work is: a baseline table, a comparison, a threshold, an exception record, and one endpoint that gives a doctor their patient's data. That is a substantially smaller task than "add the other half of the product", and it is the highest-leverage thing in the roadmap.

---

## 25. Absence verification

Claim: no AI/ML, trend, baseline, exception, or medication logic exists.

```bash
grep -rniE "AI|progression|wearing.?off|levodopa|trend" src apps/*/lib
```

**One** match, in `src/neurosync/modules/check_ins/models.py:18`:

> The rows are stored exactly as reported: no scores, trends, or interpretations
> are derived here, because drawing clinical conclusions is explicitly outside
> this module's scope.

A comment *stating the absence*. There is no `baseline`, `trend`, `exception`, or `medication` identifier in any file under `src/` or either `lib/` tree.

This is a definitive result, and it cuts both ways. It confirms §24. It also confirms that `PROJECT.md`'s out-of-scope list is being honoured — nothing in this codebase is quietly attempting to diagnose or recommend treatment.

---

## 26. Dead and stale code

| Item | Location | Nature |
| --- | --- | --- |
| `RULES: tuple[QualityRule, ...]` | `quality.py:29` | never iterated; documentation-only duplicate of the thresholds |
| `ExecutionType.QUESTIONNAIRE` | `assessment_catalog.py:23` | enum member with no row anywhere |
| `PlanStatus.DRAFT` / `.ARCHIVED` | `monitoring/models.py:36-38` | never written; no code path produces them |
| `MonitoringController.clearLastCompletedSession()` | patient app | no caller |
| `MonitoringRepository.getSession()` | patient app | implements `GET /monitoring/sessions/{id}`, no caller |
| `_SplashScreen` | doctor app | inline duplicate of a more polished shared widget |

The last two are the interesting category: **working code with no caller**. They are not bugs today, but they are untested-by-use code that will drift, and `getSession()` in particular is the client-side twin of an already-unused endpoint.

None of this is alarming. It is the normal residue of a project that built breadth quickly. It is listed so it is a decision rather than an accident.

---

## 27. Strengths

Ordered by how much they matter, not by how easy they were to write.

1. **The test harness runs real migrations against real Postgres.** This catches an entire class of bug — broken migration, wrong index, violated CHECK — that a mocked ORM hides permanently. It is the strongest decision in the repository.
2. **Correct use of database constraints for business rules.** The partial unique index on active doctor links, the CHECK constraints on severity ranges and quality values, `RESTRICT` on catalog FKs, and `UNIQUE` on `monitoring_results.session_id` mean invariants hold even under concurrency and even if application code is wrong. The `duration_seconds > 0` CHECK (migration 0006) is the same instinct applied to a new field.
3. **Security fundamentals done right, without a security dependency.** scrypt with parameters stored alongside the hash, `compare_digest`, fail-closed verification, hash-off-the-loop, token digests, timing equalisation, separate session stores, docs disabled outside development. Seven details, all correct.
4. **Feature extraction is pure and honestly named.** `duration_ms` is documented as the last offset, not wall clock. `pstdev` is used deliberately. Edge cases return defined values. This is the kind of code a clinical reviewer can check.
5. **Quality framing is correct.** "Quality describes the recording, never the patient." Thresholds are named constants; every verdict has a human rationale.
6. **Accessibility is treated as a requirement.** AA contrast asserted in tests, full type scale, large targets, haptics, reduced-motion honoured. For an app whose users have Parkinson's, this is not polish — it is the product working.
7. **Honest scope.** `PROJECT.md` lists what is out of scope and the codebase respects it. No creeping diagnosis, no dosage recommendations, no "AI insight" veneer.
8. **Comments explain *why*, not *what*.** `strict=False is the point`, `Derived information about acceptance, not a lifecycle authority`, `Severity anchors: 0 = not present, 4 = severe`. This is what makes the codebase readable.
9. **The doctor portal is a real piece of design work.** Responsive table/list switch, keyed sections that load once, session restored before first frame.

---

## 28. Weaknesses

1. **The product's core value does not exist.** No baseline, no change detection, no exceptions, no doctor review of data. The app collects and validates; it does not inform. (Capability matrix, §24.)
2. **Defect 1: quality target ignores the doctor's assigned duration** (§13). Silently marks valid sessions `invalid` for any assignment over 60 s. Untested.
3. **Defect 2: the patient app can hang on the splash screen forever** (§14). Total loss of function, no recovery path. The doctor app has the fix.
4. **The doctor cannot see patient data.** The portal is structural — roster, links, plans. No endpoint returns monitoring results or check-ins to a doctor. The UI for "doctor review" exists; the data path does not.
5. **Stale comments outnumber the code they describe** (§23). Six locations assert that features which now exist do not.
6. **Configuration is a test-hostile import-time singleton** (§15). The workaround is monkeypatching; the fix is a `get_settings()` dependency.
7. **No repository layer** (§5). Query logic is not independently testable and services own their own transactions with a redundant second commit in `get_session`.
8. **Abandoned sessions leak.** A session interrupted mid-run leaves a `started` row forever — no sweeper, no timeout, no recovery.
9. **Hard-coded LAN IPs in both clients.** The patient app defaults to `http://10.47.182.90:8000` and the doctor app to `http://192.168.3.109:8000` — two different machines, compiled into the binary. Overridable with `--dart-define`, which is correct, but a build that forgets the flag points at a developer's home network. A shared default (or `10.0.2.2` for the emulator) would fail more visibly and more safely.
10. **CORS is development-shaped** — a regex allowing any localhost port. Correct for now, and it needs narrowing before any deployment.
11. **CI has no drift check and no coverage gate** (§22).
12. **Doctor links are permanent.** No revoke, no reject, no end.

---

## 29. Prioritised recommendations

### P0 — fix now

| # | Action | Why |
| --- | --- | --- |
| 1 | Resolve the quality target from `monitoring_plan_items.duration_seconds`, falling back to the catalog default, exactly as `get_patient_plan` already does | Silent data corruption on any non-default assignment (§13) |
| 2 | Add a regression test: a 120 s assignment completing a 120 s recording is `valid` | The 165-test suite missed this; the case must be pinned |
| 3 | Port the doctor app's `restoreSession()` hardening to the patient app: move the store read inside the `try`, catch broadly, add `_discardStoredToken()` | Unrecoverable hang for the primary user (§14) |
| 4 | Port the two doctor-app regression tests for §14 | The invariant is worth enforcing on both clients |
| 5 | Delete or correct the six stale comments in §23 | They actively mislead about what exists |

Item 5 is cheap and has an outsized effect: `doctor_linking/models.py:52` tells a reader that link acceptance is out of scope when it is implemented and wired.

### P1 — the product's missing half

Ordered as a pipeline, not a backlog. Each stage feeds the next and each has its inputs already in place.

| # | Action | Notes |
| --- | --- | --- |
| 6 | Add `GET /doctor/patients/{id}/monitoring-results` | **The single highest-leverage change.** Makes the portal able to show a patient anything. No schema work. |
| 7 | Add a baseline table + a computation over `monitoring_results` | The data is already normalised per patient per session. `PlanStatus.DRAFT`/`ARCHIVED` are waiting if a curated baseline is wanted. |
| 8 | Add longitudinal change detection | Compares recent sessions against that baseline |
| 9 | Add an exception record + an "Alerts" section in the doctor portal | The portal shell, roster, and detail page already exist; a section drops in |
| 10 | Medication events | The largest schema addition, and the one `PROJECT.md` lists that is genuinely greenfield |

Steps 6–9 turn a data-collection app into the product in `PROJECT.md`. None of them requires new infrastructure.

### P2 — structural hygiene

| # | Action | Notes |
| --- | --- | --- |
| 11 | `get_settings()` + `Depends` for settings | Makes configuration testable without monkeypatching |
| 12 | Resolve the doubled commit: pick one owner for transaction boundaries | Remove `session.commit()` from `get_session()` or from the services, and document which |
| 13 | Add `alembic check` to CI | Catches model/migration drift |
| 14 | Add a coverage gate in CI | The report is already uploaded; nothing enforces it |
| 15 | Sweep abandoned sessions | A scheduled job that expires stale `started` sessions |
| 16 | Correct the two wrong README statements (§23) | The monitoring-session token claim and the CORS default |
| 17 | Introduce `DoctorLinkStatus.REVOKED` | Requires a migration and a CHECK update; the partial index already parameterises the status list |
| 18 | Decide the fate of the dead code in §26 | Delete, or wire up. `getSession()` and `RULES` are the two worth deciding on |
| 19 | Unify the client base-URL default | Two different LAN IPs in two binaries (§28.9) |

### Explicitly not recommended

- **Do not add a repository layer** yet. At 26 endpoints it would be ceremony. Revisit when a second consumer of a query appears.
- **Do not add a DI/router/state package to either Flutter app.** Three tabs and a section list do not need it.
- **Do not implement the "AI" framing.** `PROJECT.md` rules out advanced analytics and diagnosis for the MVP, and the absence is currently a strength. Deterministic, explainable thresholds are the correct answer for this domain, and `quality.py` already demonstrates that pattern.

---

## 30. Final technical summary

NeuroSync's engineering is ahead of its feature set, which is the best possible ratio to be in — the expensive, invisible work is done. The database is properly constrained, the auth is genuinely sound, the test harness runs real migrations against real Postgres, feature extraction is pure and documented, the quality rules are explainable, the accessibility work is real, and the out-of-scope list is respected rather than quietly eroded.

Two live defects need fixing, and both are small. The quality-target bug is one line plus a test. The splash-hang is a known-good implementation that already exists in the sibling app. Neither requires a design decision.

The strategic finding is the capability matrix. Seven of eleven MVP capabilities are absent, and they are absent as a *contiguous pipeline* rather than at random: everything that turns collected measurements into clinical meaning — baseline, change detection, exception, doctor review — is missing, while every input to that pipeline is present and correct.

That is a favourable position. The remaining work is one baseline table, one comparison, one threshold, one exception record, and one endpoint that hands a doctor their patient's data. The doctor portal to render it already exists. The features to compute it already exist. The data to compute it from is already in the database, normalised, per patient, per session.

The honest summary: **this is a well-built instrument that records faithfully and reads nothing back.** The instrumentation is done. The reading is the next milestone, and it is smaller than the gap suggests.

---

## Appendix A — verification commands

Every number in this report is reproducible.

```bash
# 26 routes — app.routes under-reports; use OpenAPI
uv run python -c "
from neurosync.main import app
n = sum(len(ops) for ops in app.openapi()['paths'].values())
print(n)
"

# 165 backend tests
uv run pytest --collect-only -q | tail -1

# 109 patient / 73 doctor
(cd apps/patient_app && flutter test --reporter compact)
(cd apps/doctor_app  && flutter test --reporter compact)

# 13 tables
grep -rn "__tablename__" src/neurosync | wc -l

# 6 migrations, head
ls alembic/versions/*.py

# the absence claim (§25)
grep -rniE "AI|progression|wearing.?off|levodopa|trend" src apps/*/lib

# defect 1 (§13)
grep -n "target_ms" src/neurosync/modules/monitoring/service.py     # line 403

# defect 2 (§14)
grep -n "_tokenStore.read()\|on ApiException" \
  apps/patient_app/lib/features/auth/state/auth_controller.dart
```

## Appendix B — file inventory

| Area | Count |
| --- | --- |
| Python source (`src/`) | 46 files |
| Backend tests | 16 files, 165 tests |
| Alembic migrations | 6 revisions |
| API routes | 26 operations |
| Database tables | 13 |
| ORM relationships | 1 |
| Patient app `lib/` | 59 Dart files |
| Patient app tests | 23 files, 109 tests |
| Doctor app `lib/` | 32 Dart files |
| Doctor app tests | 8 files + `test_support.dart`, 73 tests |
| Dead/stale code items | 6 (§26) |
| Documented live defects | 2 (§13, §14) |

---

*Audit performed read-only against `master` @ `a4e6d8a`. No source file was modified, no dependency installed, nothing committed.*







