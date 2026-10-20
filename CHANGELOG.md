# Changelog

What changed in Thutter **and on the Thyme PocketBase server**, newest first.
Each entry says what changed, why, and anything a developer needs to know to
work with it or debug it. Server changes aren't in git history, so they are
recorded here too, marked **Server**.

Commit hashes are on `offline-first-sync` unless noted.

## 2026-10-20

### Sync errors you can actually read — `e50383f`
- Sync failures are classified (`SyncProblem`: can't reach server, sign-in
  expired, server refused a change, unknown) with a plain-language message that
  names the step that failed, e.g. "while uploading a change to tasks", plus the
  technical detail (HTTP code, server message, field errors).
- A banner under the app bar appears whenever you're offline or sync is
  failing, with **Details** and **Retry**. The status chip names the problem
  instead of a generic "Sync error"; tapping it while something is wrong opens
  the details sheet (connection result, last successful sync, pending uploads,
  technical error, **Check connection**, **Sync now**).
- **Why:** previously the chip only said "Sync error" and tapping it silently
  retried, so a stuck or failing sync was invisible and undiagnosable.

### Real internet check (`connectionProvider`) — `e50383f`
- `connectivity_plus` only reports whether Wi-Fi/Ethernet is up. The new check
  (`lib/src/data/net/connection_check.dart`) asks the Thyme server's
  `/api/health`, and if that fails, `gstatic.com/generate_204`, to tell
  **no network**, **no internet** and **Thyme server down** apart.
- Used by the sign-out dialog, the sync banner and chip (orange Wi-Fi-off "No
  internet" signal vs red "Server down"), Retry, and automatically whenever a
  sync can't reach the server. While not online it re-checks every 30 s and
  syncs as soon as the connection is back.

### Sign-out confirmation ("Trying to escape work?") — `e50383f`
- Sign out now asks first, with "Back to work" as the default button. Signing
  out wipes the local database, so the dialog says how many unsynced changes
  would be lost ("Escape anyway"), and shows a live connection check warning
  that getting back in needs the internet.
- **Why:** sign-out was easy to hit by accident and silently threw away
  unsynced work.

### Sync request timeout — `8df610b`
- Every server call during sync now times out after 60 s.
- **Why:** `syncAll` ignores new calls while a cycle is running. One request
  that never answered left the cycle "running" forever, so the app showed
  "Syncing…" and never synced again until restarted (seen on a copy that had
  been open for ~24 h).
- Small known risk: a create that times out but succeeds server-side could be
  sent again on retry and duplicated.

### App switched from `workspace` to tenants — `c9a0da8`
- Syncs `tenants` + `memberships` instead of the legacy `workspace`.
- `activeTenantProvider` replaces `activeWorkspaceProvider`; the picker is now
  "Business" and shows your role in each.
- Repositories for `Config.tenantScoped` collections add `tenant` to every
  create and refuse to create when no business is chosen.
- Lists show only the active business's rows.
- When your set of businesses changes, sync drops rows from businesses you
  left and resets pull cursors so a newly joined business's older data arrives.
- Demo mode creates a demo business with the demo user as owner.
- **Why:** after the server migration below, `tenant` is required, so every
  create from the old app was rejected (HTTP 400).

### Docs — `a8042d9`, `afd4c9f`
- Added this changelog; brought `README.md` and `docs/ARCHITECTURE.md` up to
  date; committed `docs/TENANCY.md` and the migration/verification scripts
  (personal details removed; owner now comes from `PB_OWNER_EMAIL`).

## 2026-09-10

### **Server:** multi-tenant migration (Phase 1)
- Applied with `docs/pocketbase/migrate_tenancy.py` (7 stages, admin API),
  verified with `docs/pocketbase/verify_tenancy.py`. A full backup
  (`thyme_pretenancy_*.zip`) was taken first.
- New `tenants` collection: **Natura** (`zhshe5z3ncdvyy0`) and **Kalmark**
  (`uct1nxsasv3j378`). New `memberships` (user, tenant, role, status).
- Required `tenant` relation added to ~40 operational collections. All 78
  existing (sample) rows were assigned to **Natura**; Kalmark started empty.
- Cache fields on users the rules read: `users.tenants`,
  `users.staff_tenants`, `users.admin_tenants`. **No hook maintains them** —
  anything that changes a membership must recompute them
  (`recompute_user_caches()` in the migration script).
- API rules: `@request.auth.tenants.id ?= tenant` everywhere; `timelogs` /
  `tasks` limit `staff` to their own rows; `payroll` / `payouts` /
  `invoice_est` manager+; `memberships` writes admin+; `tenants` readable by
  members. Verified: anonymous sees nothing, a Natura member doesn't see
  Kalmark rows, creating into another tenant is blocked.
- Legacy `workspace` collection left in place, unused.

## 2026-09-09 → 2026-09-10

### Offline-first sync and live PocketBase — `be68f67`
- Drift local database (single generic `records` table + `sync_meta`
  cursors), push-then-pull last-write-wins `SyncService`, `SyncCoordinator`.
- Riverpod state, PocketBase auth cached for offline use, "remember me".
- Screens for contacts, companies, properties, leads, work orders, tasks,
  employees, equipment, time logs; time tracking with live employee status and
  timesheets; photo upload.

### **Server:** first API rules (2026-09-09)
- The 9 data collections got `@request.auth.id != ""` rules (they were
  superuser-only), so the app can sync as a normal user. Previous rules saved in
  `docs/pocketbase/rules_backup.json`; details in
  `docs/pocketbase/API_RULES.md`. Superseded by the tenant rules above.

## 2025-11-08

- `6974586` Initial Flutter scaffold.
