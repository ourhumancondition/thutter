# Thutter

The Flutter build of **Thyme** — an offline-first client for the Thyme business
management system. The on-device SQLite database is the source of truth; a
background service syncs with the Thyme PocketBase backend when online.

- What changed and why: [CHANGELOG.md](CHANGELOG.md)
- Architecture (sync, tenancy, sync errors): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Multi-tenant design + server migration: [docs/TENANCY.md](docs/TENANCY.md),
  [docs/pocketbase/](docs/pocketbase/)

## Run

```sh
flutter pub get
flutter run -d macos
```

`lib/src/data/db/database.g.dart` is checked in; after changing the Drift
schema regenerate it with `dart run build_runner build`.

On this project's Macs CocoaPods comes from Apple-silicon Homebrew, so run
`eval "$(/opt/homebrew/bin/brew shellenv)"` first if the macOS build fails at
`pod install`. Close any older copy of the app before launching another — two
copies share one local database.

The PocketBase URL defaults to `https://landscape.pockethost.io` if the
`--dart-define` is omitted.

## Status

| Area | State |
|------|-------|
| Offline-first local DB + generic sync engine | ✅ |
| Auth: online first sign-in, offline thereafter | ✅ |
| Screens: contacts, companies, properties, leads, work orders, tasks, employees, equipment, time logs | ✅ |
| Live sync with PocketBase | ✅ |
| Multi-tenant: top-bar business switcher with colours, per-business data, `tenant` stamped on creates, confirm on first add after switching | ✅ |
| Sync errors + real internet check (banner, status chip, details sheet) | ✅ |
| Sign-out confirmation with connection check | ✅ |
| Time tracking: live employee status, on-site / in-vehicle, timesheets | ✅ |
| File upload/download (avatars, photos) | ✅ picker + multipart upload wired (contacts); download = in-memory cache only |
| Member management (invite, create user, reset password) | ⛔ needs `users.manageRule` on the server |
| Server-side deletes reaching the device | ⛔ not pulled yet — see ARCHITECTURE.md |

Debug builds have a **"Continue with demo data"** button on the sign-in screen
and a **"Load demo data"** item in the account menu — fully synthetic records so
the UI can be used before live sync is wired up.

## Tests

```sh
flutter test
```

Live tests against the real server are tagged `live` and skipped by default:
`flutter test --tags live --run-skipped` (add
`--dart-define=PB_ADMIN=… --dart-define=PB_ADMIN_PW=…` for the authed one).

## Troubleshooting sync

Tap the sync chip (top right) or the banner's **Details**: it shows whether the
device can reach the internet and the Thyme server, when sync last succeeded,
how many changes are waiting, and the server's exact error. What each banner
means is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#sync-errors--connectivity).
