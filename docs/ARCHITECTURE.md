# Thutter — offline-first architecture

Thutter is the Flutter build of **Thyme**. It is **local-first**: the on-device
SQLite database is the source of truth for the UI. A background sync service
reconciles with the Thyme PocketBase backend (`https://landscape.pockethost.io`)
whenever the device is online.

## Principles

1. **The UI never talks to the network directly.** Screens read/write the local
   database through repositories. Every local write marks the row `dirty`.
2. **Auth is online-once.** The first login must reach PocketBase. After that the
   auth token is cached and the app runs fully offline; the token is refreshed
   opportunistically when a connection is available and only a hard rejection
   from the server forces a re-login.
3. **Sync is push-then-pull, last-write-wins** by the PocketBase `updated`
   timestamp. Simultaneous edits to one record can lose the older change — this
   is acceptable for the single-user-per-account model. A conflict log can be
   added later.

## Storage model

Rather than one Drift table per PocketBase collection (44 of them, most empty and
inconsistently typed), Thutter uses a **single generic `records` table**:

| column     | meaning                                             |
|------------|-----------------------------------------------------|
| `collection` | PocketBase collection name                         |
| `id`         | PocketBase record id (or `local_<uuid>` before first sync) |
| `data`       | full record JSON (all PB fields)                   |
| `updated`    | copy of `data.updated`, for cursor + sort          |
| `dirty`      | 1 = has local changes not yet pushed              |
| `deleted`    | 1 = deleted locally, pending push                 |
| `syncedAt`   | last time this row was reconciled with the server |

`sync_meta(collection, lastSynced)` holds the per-collection pull cursor.

Typed model classes (`Contact`, `Company`, `Lead`, `Task`, `Employee`,
`Timelog`, `Workspace`, `AppUser`) wrap the `data` map with getters. Repositories
query `records` by collection and map to models.

Trade-off: no SQL-level relational queries or column type-safety. Fine at current
data volumes (<100 rows/collection). If the app grows into heavy reporting,
promote hot collections to real typed Drift tables.

## Sync service

- **push**: every `dirty` row. `deleted` + server id → `DELETE` then drop local;
  `local_` id → `CREATE` then swap in the real id; otherwise `PATCH`.
- **pull**: per collection, `getFullList(filter: 'updated > "<lastSynced>"')`.
  Upsert unless the local row is `dirty` and at least as new as the server copy.
- **triggers**: successful login, app resume, connectivity regained,
  pull-to-refresh, and a periodic timer while foregrounded.

## Scope

Collections synced: `workspace`, `users`, `contactss` (canonical "contacts"),
`companies`, `property`, `employees`, `leads`, `workorders`, `tasks`,
`equipment`, `timelogs`.

Screens: login, workspace picker, and list + edit (+ detail where useful) for
contacts, companies, properties, leads, work orders, tasks, employees,
equipment, time logs. Narrow layout uses a navigation drawer; wide uses a rail.

The **pull** side of sync is verified end-to-end against the live server
(`test/live_sync_test.dart`, run with `flutter test --tags live --run-skipped`)
using the public `workspace` collection. Push and the auth-gated collections
need the API rules below before they can be tested live.

## PocketBase-side dependency

Every synced collection except `users` and `workspace` currently has
`listRule`/`viewRule`/… = `null` (superuser only). The Nuxt app works around this
with server-side admin auth. Thutter authenticates as the **user**, so those
collections must get API rules before live sync works. See
`docs/pocketbase/API_RULES.md`. Until then the app runs offline against
seed data imported from the backup.

## Sessions & "remember me"

The PocketBase auth token is persisted by `token_store.dart` — keychain/keystore
on iOS/Android, `shared_preferences` on desktop (secure storage silently fails
on ad-hoc-signed macOS builds). This alone keeps the user signed in across
restarts until the token expires.

The sign-in form's **Remember me** checkbox additionally stashes the
email + password via `credential_store.dart` (same platform split; the desktop
copy is only base64-obscured, not encrypted). On the next visit to the login
screen the fields pre-fill. An explicit **Sign out** clears both the token and
the saved credentials; a token that merely expires leaves them in place so
re-login is one tap.

## File fields

`avatar`, `image`, `photo` — displayed via `PbImage` (builds
`{base}/api/files/{collection}/{recordId}/{filename}?thumb=...`, falls back to an
icon offline / before first sync). Upload: `CollectionRepository.attachFile`
stashes the picked local path under `_pendingFiles` in the record JSON; the sync
push sends it as `multipart/form-data` and clears the stash on success. Wired
into the contact editor; the same `PhotoField` widget drops into any other
editor. Download caching beyond Flutter's in-memory image cache is still TODO.

## Time tracking

`timelogs` rows are raw clock **events** (`Start Day`, `Site In`, `Site Out`,
`Start Break`, `Shop`, `Travel`, `End Day`), each optionally naming a `site`
(property), `vehicle` (equipment) or `job` (work order).

`lib/src/data/status/employee_status.dart` derives the useful views:

- **`employeeStatusProvider`** → `{employeeId: EmployeeStatus}` — each
  employee's *current* state from their newest event, carrying the site/vehicle
  forward from the latest event that named one within the current shift. `Site
  Out` / `End Day` clear the site.
- **`employeesOnSiteProvider(siteId)`** / **`employeesInVehicleProvider(equipmentId)`**
  — the reverse lookup, used to highlight "on site now" / "in use by" on the
  property, equipment and employee lists and detail pages.
- **`segmentsFrom(events)`** → `[ShiftSegment]` — pairs consecutive events into
  intervals with a duration and a `kind`; the timesheet screen sums these into
  "worked" vs "on site" vs "break" per day.

The Time logs screen has three tabs: **People** (live status per employee →
timesheet), **Sites** (who's where, → site activity log), **Log** (the raw
event stream).

## macOS

Needs `com.apple.security.network.client` (PocketBase) and
`com.apple.security.files.user-selected.read-only` (file picker) — both are in
`macos/Runner/*.entitlements`.
