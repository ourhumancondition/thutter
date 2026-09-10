# Thutter

The Flutter build of **Thyme** — an offline-first client for the Thyme business
management system. The on-device SQLite database is the source of truth; a
background service syncs with the Thyme PocketBase backend when online.

- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- PocketBase rules this app needs: [docs/pocketbase/API_RULES.md](docs/pocketbase/API_RULES.md)

## Run

```sh
flutter pub get
dart run build_runner build          # generates lib/src/data/db/database.g.dart
flutter run -d macos --dart-define=PB_URL=https://landscape.pockethost.io
```

The PocketBase URL defaults to `https://landscape.pockethost.io` if the
`--dart-define` is omitted.

## Status (v1)

| Area | State |
|------|-------|
| Offline-first local DB + generic sync engine | ✅ |
| Auth: online first sign-in, offline thereafter | ✅ |
| Screens: contacts, companies, properties, leads, work orders, tasks, employees, equipment, time logs | ✅ |
| Workspace picker | ✅ |
| Live sync with PocketBase | ✅ API rules applied; pull verified against the live server |
| Time tracking: live employee status, on-site / in-vehicle, timesheets | ✅ |
| File upload/download (avatars, photos) | ✅ picker + multipart upload wired (contacts); download = in-memory cache only |
| Real per-workspace data isolation | ⛔ needs a backend schema change (`workspace_members`) |

Debug builds have a **"Continue with demo data"** button on the sign-in screen
and a **"Load demo data"** item in the account menu — fully synthetic records so
the UI can be used before live sync is wired up.

## Tests

```sh
flutter test
```
