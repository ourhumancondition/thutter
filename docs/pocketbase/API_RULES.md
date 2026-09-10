# PocketBase API rules Thutter needs

> **Status: APPLIED 2026-09-09** to `landscape.pockethost.io`. The 9 data
> collections got `@request.auth.id != ""` on all five rules; `workspace` got
> auth for read/create and `owner_id = @request.auth.id` for update/delete
> (it was previously fully public). Previous values are in
> `docs/pocketbase/rules_backup.json`. Verified with `flutter test --tags live`.


The Nuxt app reaches PocketBase through server routes authenticated as a
**superuser**, so its collections mostly have every API rule set to `null`
(= superuser only). Thutter talks to PocketBase **directly, as the signed-in
user**, so each collection it syncs needs rules that allow a normal auth token.

Set these in the PocketBase admin UI: **Collections → (collection) → API Rules**.
An empty field = "anyone"; `@request.auth.id != ""` = "any signed-in user".

| Collection   | List / Search | View | Create | Update | Delete |
|--------------|---------------|------|--------|--------|--------|
| `users`      | *(currently public — tighten to)* `id = @request.auth.id \|\| @request.auth.type = "admin"` | same | `@request.auth.id != ""` | `id = @request.auth.id` | `@request.auth.type = "admin"` |
| `workspace`  | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `owner_id = @request.auth.id` | `owner_id = @request.auth.id` |
| `contactss`  | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `companies`  | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `leads`      | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `tasks`      | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `employees`  | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `timelogs`   | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `property`   | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `workorders` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |
| `equipment`  | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` | `@request.auth.id != ""` |

`property` is included because `contactss`, `leads` and `timelogs` all relate to
it and the detail screens resolve those names.

## Notes / decisions to make

- **These rules give every signed-in user access to every contact, company,
  lead, task, employee and time log in the database.** The Thyme data model has
  no real per-workspace membership (`workspace.owner_id` is a single relation),
  so proper multi-tenant isolation needs a schema change first — e.g. a
  `workspace_members` join, then rules like
  `workspace_id.members_via_workspace.user ?~ @request.auth.id`.
- `users` and `workspace` are currently **fully public** (rules = `""`). Anyone
  who finds the URL can list every user record. Worth tightening regardless of
  Thutter.
- After changing rules, also confirm the Nuxt app still works — it uses admin
  auth so it is unaffected, but double-check.

## Applying via migration (optional)

`pb_migrations/1700000000_thutter_api_rules.js` in this folder sets the
`@request.auth.id != ""` rules for the data collections. Drop it into your
PocketBase `pb_migrations/` directory and restart, or run
`./pocketbase migrate up`. Adjust the syntax if your PocketBase is newer than
v0.22 (the newer API is `app.findCollectionByNameOrId` / `app.save`).
