# Thyme — tenancy model

Status: **Phase 1 live.** Server migration applied 2026-09-10
(`pocketbase/migrate_tenancy.py`, verified by `pocketbase/verify_tenancy.py`);
the Flutter app switched over 2026-10-20. Member management (invite / create
user / reset password, needs `users.manageRule`) is not built yet. See
`CHANGELOG.md`. Supersedes the half-finished `workspace` structure. Applies to the whole platform (PocketBase backend, the Nuxt admin
console, and the Flutter app `thutter`).

## Goal

Every business ("tenant") using Thyme sees only its own data. A person can
belong to more than one tenant (you own **Kalmark** and **Natura**) and switches
between them in the app.

## Non-goals for this phase

- Separate PocketBase instances per client. This design keeps **one shared
  PocketBase instance**, but structures the data so any single tenant can later
  be lifted into its own instance with a mechanical export/import (see
  [Phase 2](#phase-2--extraction-to-db-per-client)).
- The master-directory / billing / analytics platform layer. Those build *on
  top of* this model later, and this instance becomes the master directory
  naturally (it already holds `tenants` and `memberships`).

---

## The model

### `tenants` (replaces `workspace`)

| field | type | notes |
|---|---|---|
| `name` | text, required | display name ("Kalmark Integrated Systems Ltd") |
| `slug` | text, required, unique | url-safe id ("kalmark") |
| `plan` | select | `trial` / `active` / `suspended` |
| `archived_at` | date | soft delete |
| `instance_url` | text | **null = data lives in this shared instance.** Set when the tenant is extracted (Phase 2). |
| `schema_version` | number | last migration applied to this tenant's data |
| `billing_email` | email | |

### `memberships` (new — the join table the current model lacks)

| field | type | notes |
|---|---|---|
| `user` | relation → users, required | |
| `tenant` | relation → tenants, required | |
| `role` | select, required | `owner` / `admin` / `manager` / `staff` |
| `status` | select | `active` / `invited` / `suspended` |

Unique index on `(user, tenant)`.

Roles:
- **owner** — billing, can delete the tenant, manage all memberships
- **admin** — manage memberships (except owners), all data
- **manager** — all data, no membership management
- **staff** — scoped data only (their own timesheet, assigned tasks); exact
  scope TBD per collection

### `users` — changes

- **Drop** the global `type` (`admin`/`manager`/…) and `level` fields — role is
  now per-tenant via `memberships`. (`level` = `retail`/`contractor`/`wholesale`
  looks like a *customer* classification anyway; if it's needed it belongs on a
  contact/company record, not the user.)
- `users.employee` (relation → employees) stays — it's how a `staff` login maps
  to their operational employee record for timesheet scoping.
- **`manageRule`** (see [member management](#member-management)) lets tenant
  owners/admins manage co-members' auth records.

No `tenants` cache field in Phase 1 — the rules use a correlated `memberships`
join directly (see below). If that ever becomes a perf concern at scale, add a
hook-maintained `users.tenants` multi-relation then and simplify the rules to
read it.

### Every operational collection — add `tenant`

`tenant` — relation → tenants, **required**, `cascadeDelete: false`.

Consistent name everywhere (the current schema mixes `workspace` and
`workspace_id`).

Collections that get it (~37): `contactss`, `companies`, `leads`, `timelogs`,
`property`, `workorders`, `equipment`, `tasks`, `employees`, `contracts`,
`accounts`, `account_notes`, `contact_notes`, `project_notes`, `deliveries` +
`delivery_*`, `invoice_est`, `lineitems`, `orders`, `payroll`, `payouts`,
`odometer`, `loading`, `notifications`, `chat`, `dimensions`, `sod`, `soil`,
`service_builds`, `service_line`, `service_questions`, `items`, `tags`,
`categories`, `articles`, `article_tag`.

**Open question — shared reference data.** `categories`, `tags`, `items`
(product catalog?), `articles`, `service_line` *could* be platform-global
instead of per-tenant. Default assumption: **per-tenant** (each landscape
business runs its own service catalog and tags). Revisit if a global taxonomy is
actually wanted.

### Cross-tenant relations — forbidden

`contactss.referred`, `contactss.relation`, and any other record→record relation
must point within the same tenant. Enforced in the create/update rule
(`referred.tenant ?= tenant`) or a hook. This is what keeps Phase 2 extraction
clean.

---

## API rules

A reusable "am I a member of this record's tenant" predicate (PocketBase
correlates the two conditions to the same joined `memberships` row):

```
@request.auth.id != ""
  && @collection.memberships.user ?= @request.auth.id
  && @collection.memberships.tenant ?= tenant
  && @collection.memberships.status ?= "active"
```

Call that `MEMBER(tenant)`. Every standard per-tenant collection:

```
list / view / update / delete : MEMBER(tenant)
create                        : MEMBER(@request.data.tenant)
```

**Role-gated collections** (`memberships`, `tenants`, `payroll`, `invoice_est`,
`payouts`) swap the last two conditions for a role check —
`... && @collection.memberships.role ?~ "owner|admin"` (or `|manager`).

**`memberships`:**
- list / view: `MEMBER(tenant)` — see co-members of your tenants
- create / update / delete: owner/admin of that tenant

**`tenants`:**
- list / view: `@collection.memberships.tenant ?= id && @collection.memberships.user ?= @request.auth.id`
- update: owner only · create / delete: superuser only (Phase 1)

**`users`:** tighten from public `""` to
`id = @request.auth.id
  || (@collection.memberships.user ?= id
      && @collection.memberships.user ?= @request.auth.id)` —
hmm, that's wrong (can't correlate "target is a member" with "I'm a member of
the same tenant" without naming the tenant). Practical version: **view/list** =
any authenticated user (`@request.auth.id != ""`) — user records hold no
sensitive data once `type`/`level` are dropped; the app needs to resolve
assignee/author names. **update** = `id = @request.auth.id` (self) OR
`manageRule` (admins, below).

### `staff` role — narrower rules on two collections

`timelogs`:
```
list/view/create/update/delete :
  MEMBER(tenant) && (
    @collection.memberships.role ?~ "owner|admin|manager"
    || employee = @request.auth.employee            // staff: only their own
  )
```

`tasks`:
```
list/view :
  MEMBER(tenant) && (
    @collection.memberships.role ?~ "owner|admin|manager"
    || assigned_to.id ?= @request.auth.id            // staff: only assigned
  )
update : same predicate
create/delete : manager+ only
```

Supporting records a staff member's task/timelog points at (`property`,
`contactss`, `workorders`, `equipment`) keep the plain `MEMBER(tenant)` read
rule — a staff member is still a tenant member, so they can read those; they
just can't list contacts/leads/etc. freely. If tighter is wanted later, add
`|| id ?= @request.auth.<...>` branches, but that's fiddly and low-value now.

### member management

`users.manageRule` — lets a tenant owner/admin create co-members and reset their
passwords (PocketBase's `manageRule` bypasses the `oldPassword` requirement):

```
@request.auth.id != ""
  && @collection.memberships.user ?= id                 // target is a member of…
  && @collection.memberships.tenant ?= @collection.memberships.tenant  // …a tenant where…
  && @collection.m2.tenant ?= @collection.memberships.tenant
  && @collection.m2.user ?= @request.auth.id
  && @collection.m2.role ?~ "owner|admin"               // …I'm owner/admin
```

(Two `@collection.memberships` aliases — `memberships` for the target, `m2` for
the requester — joined on the same `tenant`. Verify this compiles on the live PB
version; if not, fall back to a `pb_hooks` check on the update request.)

`users` **create** rule: `@request.auth.id != ""` — but the *membership* the
admin creates alongside is what grants access, and `manageRule` is what lets
them set the password. An admin creating a user they then can't administer is
harmless.

---

## The membership → `users.tenants` hook

`pb_hooks/tenants_cache.pb.js` (hook names are for PB ~0.22 — adjust if the
instance is newer):

```js
function recompute(userId) {
  const dao = $app.dao();
  const rows = dao.findRecordsByFilter(
    "memberships", "user = {:u} && status = 'active'", "", 0, 0, { u: userId }
  );
  const tenantIds = rows.map((r) => r.getString("tenant"));
  const user = dao.findRecordById("users", userId);
  user.set("tenants", tenantIds);
  dao.saveRecord(user);
}

onRecordAfterCreateRequest((e) => recompute(e.record.getString("user")), "memberships");
onRecordAfterUpdateRequest((e) => recompute(e.record.getString("user")), "memberships");
onRecordAfterDeleteRequest((e) => recompute(e.record.getString("user")), "memberships");
```

Plus a nightly reconcile job (cron hook) that rebuilds every user's cache, so a
missed hook self-heals.

---

## Migration & backfill

Order matters — each step leaves the system working.

1. **Create `tenants`.** For each existing `workspace` row, create a `tenants`
   row **keeping the same id** (so any existing `workspace_id` FKs still
   resolve). Map `tenant_name`→`name`, generate `slug`, `plan = active`,
   `instance_url = null`.
2. **Create `memberships`.** One `owner` membership per `tenants` row from
   `workspace.owner_id`. Add yourself as `owner` of both Kalmark and Natura.
3. **Add `users.tenants`** + install the hook + run the reconcile once.
4. **Add the `tenant` field** (nullable *for now*) to every operational
   collection.
5. **Backfill.** All current operational data is filler → **assign every
   existing operational row to the Natura tenant.** Kalmark starts empty.
   - Script: `for coll in [...]: for rec in all: rec.tenant = NATURA_ID; save`
6. **Make `tenant` required** once backfill is verified (no null `tenant` rows).
7. **Flip the API rules** from `@request.auth.id != ""` to the tenant-scoped
   versions above. Keep the backup (`docs/pocketbase/rules_backup.json` style).
8. **Delete** `workspace`, `users.type`, `users.level`, and the old
   `companies.workspace_id` / `employees.workspace` / `tasks.workspace` /
   `contacts.workspace_id` fields (replaced by `tenant`).

A reversible migration file goes in `docs/pocketbase/pb_migrations/`.

---

## Flutter app (`thutter`) changes

- `activeTenantProvider` replaces `activeWorkspaceProvider`. The tenant list
  comes from the signed-in user's `tenants` (already in the auth record) joined
  to the local `tenants` collection.
- **Sync** pulls every tenant the user belongs to (data volumes are small; a
  manager wants all their tenants available offline). Each collection filter
  becomes `tenant ?= "<t1>" || tenant ?= "<t2>" ... && updated > cursor`. The
  sync registry gains an optional per-collection tenant filter for when a
  collection grows large.
- Every list/query provider filters by `activeTenant.id` (the lenient
  "null tenant = everywhere" fallback is removed — every row now has a tenant).
- New records get `'tenant': activeTenant.id` in their create body.
- The workspace picker UI already exists; it just points at real data.
- Local DB stays single-file with a `tenant` column filter — no per-tenant DB
  files needed while data is shared.

---

## Phase 2 — extraction to DB-per-client

When a client needs their own instance (isolation, scale, compliance, or
they're leaving):

1. Provision a fresh PocketBase instance, apply the current Thyme schema at
   `schema_version`.
2. Export every row where `tenant = X` from the shared instance. IDs are random
   15-char, so they import without collision. Keep or drop the `tenant` field
   (a single-tenant instance doesn't need it, but keeping it eases re-merge).
3. Copy that tenant's files (`pb_data/storage`).
4. Set `tenants.instance_url` (+ an encrypted per-tenant integration token) in
   the shared instance, which is now the **master directory**.
5. Delete the tenant's rows from the shared instance.
6. The app/console reads `tenant.instance_url`: null → shared instance; set →
   connect there. `thutter`'s `SyncService(db, pb)` already takes the client as
   a parameter, so this is a connection-selection change, not a sync rewrite.

The master directory then also grows `billing_snapshots` and a
`schema_version` check per tenant (drift detection). The analytics aggregator is
a scheduled service running the same incremental-pull logic against every
`instance_url` + the shared instance.

### Phase-2 open problem — cross-instance auth

Once a tenant is on its own instance, its users still need to sign in.
PocketBase has no federated auth, so this needs one of:

- **(a) Master as identity provider.** Users always authenticate against the
  shared/master instance; it returns the user's tenants + each `instance_url` +
  a short-lived token the target instance accepts (custom endpoint/hook that
  mints a record token for that instance's `users` collection).
- **(b) Mirrored users.** Each extracted instance keeps a copy of its tenant's
  `users` (synced from master); the app resolves the instance first (lookup by
  email against master), then authenticates directly there. Simpler, but
  password changes must propagate.
- **(c) Shared-secret JWT.** Master issues a JWT signed with a secret every
  instance trusts; a custom auth hook on each instance validates it. The proper
  SaaS answer, most to build.

**Not needed for Phase 1** — while every tenant lives in the shared instance,
all users authenticate against that one instance and `instance_url` is always
null. Decide this when the first extraction is actually on the table.

---

## Decisions — resolved 2026-09-10

1. **Reference data is per-tenant.** `categories`, `tags`, `items`,
   `service_line`, `service_builds`, `service_questions`, `articles` all get a
   `tenant` FK. Rationale: tenants aren't in the same industry — Kalmark is a
   manufacturer, Natura is landscape supply, so service "recipes", catalogs and
   taxonomies differ. A cross-tenant global taxonomy can be layered on later if
   analytics needs it.

2. **`staff` role = own timesheet + assigned tasks only.** A `staff` member can:
   - **read/write** `timelogs` where `employee` = their own linked employee
     record (`users.employee`)
   - **read/write** `tasks` where `assigned_to` contains their user id
   - **read** the supporting records those reference (the `property`, `contact`,
     `workorder`, `equipment` on their tasks/timelogs) — read-only
   - **not** see contacts, companies, leads, payroll, other people's time, etc.
   Enforced with per-collection rule branches (staff vs manager+). See
   `pocketbase/RULES.md`.

3. **Backfill target is Natura.** All current operational data (filler content)
   → the Natura tenant. Kalmark starts empty.

4. **Full member management in the app now.** Owners/admins can:
   - **invite** a user by email (creates a membership in `invited` status)
   - **create the account outright** — set email + password directly, no
     invite/acceptance step, membership `active` immediately
   - **reset any co-member's password** at any time
   Mechanism: `users.manageRule` lets a tenant owner/admin fully manage the auth
   records of users who are members of a tenant they administer (PocketBase's
   `manageRule` permits password changes without `oldPassword`). Security note:
   this means a tenant admin can set a co-member's password and therefore act as
   them — acceptable per the product decision, logged for audit.
