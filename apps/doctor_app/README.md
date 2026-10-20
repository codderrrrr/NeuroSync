# NeuroSync — Doctor Portal (Flutter)

The doctor-facing application for NeuroSync. It runs as a **web portal** on
desktop and as a mobile app on Android and iOS from the same codebase: sign up
or sign in, share your personal link code, accept patient link requests and
assign finger-tapping exercises with a recording length of your choosing.

## Running

As a web portal:

```bash
flutter pub get
flutter run -d chrome --dart-define=NEUROSYNC_API_BASE_URL=http://127.0.0.1:8000
```

As a mobile app, or as a portal opened on another device:

```bash
uv run python scripts/dev_api_address.py
flutter run --dart-define=NEUROSYNC_API_BASE_URL=http://192.168.3.111:8000
```

Start the backend first:

```bash
uv run uvicorn neurosync.main:app --reload --host 0.0.0.0 --port 8000
```

**Use the helper script.** A laptop's address is assigned by DHCP and changes
whenever the machine rejoins a network. An app still carrying the old one will
hang until it times out, because the request is going somewhere that does not
answer - which looks like the server being slow rather than the address
being wrong. `scripts/dev_api_address.py` prints the current address and
whether the backend is answering on it.

The backend serves the portal on the local network in development only, so a
browser on a phone or tablet can load it from the machine's address.

To produce a deployable portal:

```bash
flutter build web --release
```

## Layout

The portal adapts rather than shrinking:

- **900px and wider** — a fixed sidebar beside the content.
- **Below 900px** — the sidebar becomes a compact bar of icon destinations with
  the wordmark reduced to its mark.
- **720px and wider** — the roster renders as a table, because the useful
  comparison is across rows.
- **Below 720px** — the roster becomes a list, because a sideways-scrolling
  table hides the patient name behind the scroll.

Navigation never moves as content changes: the rail and the compact bar are the
same destinations in two sizes.

## Structure

```text
lib/
├── app.dart                  # Root: splash → login → portal
├── app_scope.dart            # InheritedWidget providing the controllers
├── app/
│   ├── portal_shell.dart     # Sidebar / compact bar, destinations, account
│   └── portal_widgets.dart   # Page frame, nav item, status tag, empty state
├── core/
│   ├── config/               # API base URL and request timeout
│   ├── network/              # JSON client + ApiException
│   ├── storage/              # Session token: secure store, in-memory, cache
│   ├── theme/                # The shared dark theme
│   └── widgets/              # Shared buttons, cards and text styles
└── features/
    ├── auth/                 # Signup, login, session restore
    ├── patients/             # Patient detail + assignment page
    └── roster/               # Overview, patients, requests, profile sheet
```

Controllers are plain `ChangeNotifier`s. Widgets read them from `AppScope` and
rebuild through `ListenableBuilder`, so rebuilds stay scoped to the screen that
actually changed. `main.dart` creates them once and shares a single
`SessionTokenCache` between the API client and the auth controller.

## Checks

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
flutter build bundle --debug
flutter build web --release
```

These run in CI on every push and pull request. The tests cover the shell, the
roster, requests, the detail and assignment pages, and every layout at seven
viewport widths; a layout overflow fails the suite.

## Notes

- The doctor's link code is generated at signup from an alphabet with no
  ambiguous characters, like a classroom join code. It is shown only in the
  profile sheet, reachable from the account row.
- Only `finger_tapping` can be assigned; other catalog assessments are not yet
  executable. Assigning an unsupported one returns `409`.
- Monitoring results are not shown in this app yet, and the patient detail page
  does not list sections for them, rather than showing placeholder data.

