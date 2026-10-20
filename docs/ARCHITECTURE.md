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

`sync_meta(collection, lastSynced)` holds the per-collection pull cursor. One
extra key, `_tenants`, remembers which tenants the local data was pulled for
(see [Tenancy](#tenancy)).

Typed model classes (`Tenant`, `Membership`, `AppUser`, `Contact`, `Company`,
`Lead`, `Task`, `Employee`, `Timelog`, `Property`, `WorkOrder`, `Equipment`)
wrap the `data` map with getters; `PbRecord.tenantId` reads the `tenant`
relation. Repositories
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
  pull-to-refresh, and a periodic timer while foregrounded
  (`SyncCoordinator`, `lib/src/data/sync/sync_coordinator.dart`).
- **timeouts**: every server call has a 60 s limit. `syncAll` no-ops while a
  cycle is in flight, so before this one request that never answered froze
  sync until the app restarted.
- Server **deletes are not pulled** — a record deleted on the server stays on
  the device until the next sign-in (which wipes the local db). Known gap.

## Tenancy

The backend is multi-tenant (design: `docs/TENANCY.md`). Every operational
collection has a required `tenant` relation → `tenants`; `memberships` holds
each user's role per tenant (`owner` / `admin` / `manager` / `staff`).

What's live on the server (Phase 1, 2026-09-10):

- API rules read **cache fields on the user record**, not `memberships`:
  `users.tenants` (all active tenants), `users.staff_tenants`,
  `users.admin_tenants`. e.g. `@request.auth.tenants.id ?= tenant`.
- **There is no hook keeping those caches current.** Whatever changes a
  membership must also recompute that user's caches (see
  `recompute_user_caches()` in `docs/pocketbase/migrate_tenancy.py`), or the
  user's access won't change.
- `timelogs` / `tasks` narrow `staff` to their own rows; `payroll`, `payouts`,
  `invoice_est` are manager+; `memberships` writes are admin+.
- The old `workspace` collection is still there but unused.

In the app:

- `activeTenantProvider` is the business the user is working in, chosen in the
  top-bar switcher (`features/tenant/tenant_switcher.dart`) and saved in
  `shared_preferences` (`active_tenant_id`). Each business has a colour
  (`tenants.color` if an owner/admin picked one, else assigned by
  `assignTenantColors`), shown on its badge and a stripe under the top bar.
  After a switch, the first "New …" asks the user to confirm the business
  (`confirmTenantThen`). `myTenantsProvider` lists the
  tenants the user can switch to; `activeMembershipProvider` gives their role.
- `Config.tenantScoped` lists the tenant-owned collections. Their repositories
  stamp `tenant: <active tenant>` on every create (and refuse to create with no
  tenant chosen, since the server would reject it). Their list providers show
  only the active tenant's rows.
- Sync pulls **every** tenant the user belongs to (the server rules do the
  filtering). Pull cursors only fetch rows changed since the last sync, so when
  the user's set of tenants changes, `SyncService` drops synced rows from
  tenants they left and resets the cursors to re-pull everything.

## Sync errors & connectivity

`SyncService.describeError` turns a failure into a `SyncProblem`
(`unreachable`, `signedOut`, `rejected`, `unknown`), a plain-language message
naming the step that failed ("while downloading contacts"), and a technical
detail (HTTP code, server message, field errors). `SyncStatus` carries these
plus `lastSuccess`.

"Online" from `connectivity_plus` only means a network interface is up. The real
check is `connectionProvider` (`lib/src/data/net/connection_check.dart`):

1. no interface → `noNetwork`
2. `GET {PB_URL}/api/health` answers → `online`
3. else `https://www.gstatic.com/generate_204` answers → `serverDown`
4. else → `noInternet`

It runs when the sign-out dialog opens, when Wi-Fi changes, when a sync fails to
reach the server, and from Retry / "Check connection". While the result isn't
`online` the coordinator re-checks every 30 s and syncs as soon as it is.

UI (`lib/src/common/widgets.dart`):

| What you see | Meaning |
|---|---|
| Orange banner + Wi-Fi-off chip, "No internet" | `noNetwork` / `noInternet` — the device's connection |
| Red banner, "Server down" chip | internet works, Thyme server doesn't answer |
| Red banner, "Can't reach server" / "Sync refused" / "Sign-in expired" | `SyncProblem` from the last sync |
| Chip "Synced 2m ago" | all good |

The banner's **Details** opens a sheet with the connection result, last
successful sync, pending uploads and the technical error — the first thing to
ask a user for when debugging sync.

## Scope

Collections synced: `tenants`, `memberships`, `users`, `contactss` (canonical
"contacts"), `companies`, `property`, `employees`, `leads`, `workorders`,
`tasks`, `equipment`, `timelogs`.

Screens: login, business (tenant) picker, and list + edit (+ detail where useful) for
contacts, companies, properties, leads, work orders, tasks, employees,
equipment, time logs. Narrow layout uses a navigation drawer; wide uses a rail.

The **pull** side of sync is verified end-to-end against the live server
(`test/live_sync_test.dart`, run with `flutter test --tags live --run-skipped`):
anonymous pulls get nothing, and an admin token can read every collection.

## PocketBase-side dependency

Thutter authenticates as the **user**, so everything depends on the API rules.
`docs/pocketbase/API_RULES.md` records the first (pre-tenancy) rules and
`rules_backup.json` the rules before that; the current tenant-scoped rules are
described under [Tenancy](#tenancy) and were applied by
`docs/pocketbase/migrate_tenancy.py`. Admin credentials for those scripts live
in `~/.thyme-pb-admin` (KEY=VALUE, outside the repo) — never commit them.

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

Sign out **wipes the local database**, including changes that haven't synced.
So it asks first ("Trying to escape work?"), checks the connection while the
dialog is open (getting back in needs the server), and when there are unsynced
changes says how many will be lost and relabels the button "Escape anyway".

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
