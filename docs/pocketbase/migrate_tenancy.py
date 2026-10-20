#!/usr/bin/env python3
"""
Thyme tenancy migration — see docs/TENANCY.md.

Turns the half-built `workspace` model into `tenants` + `memberships` + a
`tenant` FK on every operational collection, backfills all existing (filler)
data to the Natura tenant, and applies tenant-scoped API rules.

Runs against the live PocketBase over the admin API. Idempotent per stage.

    export PB_URL=https://landscape.pockethost.io
    export PB_ADMIN=admin@example.com
    export PB_OWNER_EMAIL=owner@example.com   # user made owner of every tenant
    export PB_ADMIN_PW=...

    python3 migrate_tenancy.py                 # dry run, all stages
    python3 migrate_tenancy.py --stage 0 --apply   # backup only
    python3 migrate_tenancy.py --stage 1-4 --apply # schema + backfill
    python3 migrate_tenancy.py --stage 6 --apply   # rules only
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

def _load_creds():
    """Env vars win; otherwise read ~/.thyme-pb-admin (KEY=VALUE lines).
    That file lives outside any repo — never commit credentials."""
    creds = {}
    path = os.path.expanduser("~/.thyme-pb-admin")
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                creds[k.strip()] = v.strip()
    return creds


_c = _load_creds()
BASE = (os.environ.get("PB_URL") or _c.get("PB_URL")
        or "https://landscape.pockethost.io").rstrip("/")
IDENT = os.environ.get("PB_ADMIN") or _c.get("PB_ADMIN") or ""
PW = os.environ.get("PB_ADMIN_PW") or _c.get("PB_ADMIN_PW") or ""
if not IDENT or not PW:
    raise SystemExit("set PB_ADMIN / PB_ADMIN_PW (env) or ~/.thyme-pb-admin")

# Collections that get a `tenant` relation + standard MEMBER(tenant) rules.
OPERATIONAL = [
    "contactss", "companies", "leads", "property", "workorders", "tasks",
    "employees", "equipment", "timelogs", "contracts", "accounts",
    "account_notes", "contact_notes", "project_notes", "delivery",
    "delivery_items", "delivery_notes", "delivery_records", "dimensions",
    "invoice_est", "invoice_update_records", "items", "lineitems", "loading",
    "notifications", "chat", "odometer", "orders", "payroll", "payouts",
    "sod", "soil", "service_builds", "service_line", "service_questions",
    "tags", "categories", "articles", "article_tag", "contacts_users",
]
# Legacy near-duplicates we are NOT carrying forward.
DROP_LATER = ["workspace_id_fields", "companies_sample", "contacts"]

TENANT_SLUGS = {"Natura": "natura", "Kalmark Integrated Systems Ltd": "kalmark"}
BACKFILL_TENANT_SLUG = "natura"

# Correlated to the requesting user via the hook-free `users.tenants` cache
# (list of tenant ids the user has an active membership in).
MEMBER = '@request.auth.id != "" && @request.auth.tenants.id ?= tenant'
MEMBER_CREATE = '@request.auth.id != "" && @request.auth.tenants.id ?= @request.data.tenant'
# `users.staff_tenants` = tenants where the user's role is exactly "staff".
NOT_STAFF_HERE = '@request.auth.staff_tenants.id ?!= tenant'
NOT_STAFF_HERE_CREATE = '@request.auth.staff_tenants.id ?!= @request.data.tenant'
# `users.admin_tenants` = tenants where the user is owner or admin.
ADMIN_HERE = '@request.auth.admin_tenants.id ?= tenant'
ADMIN_HERE_CREATE = '@request.auth.admin_tenants.id ?= @request.data.tenant'

# ---------------------------------------------------------------- http ----

_token = None


_SENTINEL = object()


def req(method, path, body=None, _tries=4, token=_SENTINEL):
    data = json.dumps(body).encode() if body is not None else None
    tok = _token if token is _SENTINEL else token
    for attempt in range(_tries):
        r = urllib.request.Request(BASE + path, data=data, method=method)
        r.add_header("Content-Type", "application/json")
        # Cloudflare fronting PocketHost blocks the default urllib UA (1010).
        r.add_header("User-Agent",
                     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                     "AppleWebKit/537.36 (KHTML, like Gecko) "
                     "Chrome/124.0 Safari/537.36")
        if tok:
            r.add_header("Authorization", tok)
        try:
            with urllib.request.urlopen(r, timeout=40) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except Exception:
                return e.code, {"_raw": raw.decode(errors="replace")[:400]}
        except Exception as e:  # timeout, chunked-read, conn reset
            if attempt == _tries - 1:
                return 0, {"_err": str(e)}
            time.sleep(2 * (attempt + 1))


def auth():
    global _token
    for p in ("/api/collections/_superusers/auth-with-password",
              "/api/admins/auth-with-password"):
        code, body = req("POST", p, {"identity": IDENT, "password": PW})
        if code == 200 and body.get("token"):
            _token = body["token"]
            return
        print(f"  auth {p} -> {code} {str(body)[:160]}")
    sys.exit(f"auth failed (ident={IDENT!r}, url={BASE})")


def collections():
    code, body = req("GET", "/api/collections?perPage=200")
    if code != 200:
        sys.exit(f"list collections: {code} {body}")
    return {c["name"]: c for c in body["items"]}


def all_records(name):
    out, page = [], 1
    while True:
        code, body = req(
            "GET", f"/api/collections/{name}/records?perPage=500&page={page}")
        if code != 200:
            sys.exit(f"list {name}: {code} {body}")
        out += body["items"]
        if page >= body["totalPages"] or not body["items"]:
            return out
        page += 1


# ---------------------------------------------------------------- stages ----

def stage0_backup(apply):
    name = f"thyme_pretenancy_{time.strftime('%Y%m%d_%H%M%S')}.zip"
    print(f"[0] backup -> {name}")
    if not apply:
        return
    code, body = req("POST", "/api/backups", {"name": name})
    print("    ", code, "ok" if code in (200, 204) else body)


def _field(name, options, required=False):
    return {"name": name, "type": "relation", "required": required,
            "presentable": False, "unique": False, "options": options}


def stage1_core(apply, cols):
    print("[1] create `tenants` + `memberships` (leaving legacy `workspace`)")
    uid = cols["users"]["id"]

    if "tenants" in cols:
        print("    tenants already exists")
        tid = cols["tenants"]["id"]
    else:
        tenants = {
            "name": "tenants", "type": "base",
            "schema": [
                {"name": "name", "type": "text", "required": True,
                 "presentable": True, "unique": False,
                 "options": {"min": None, "max": None, "pattern": ""}},
                {"name": "slug", "type": "text", "required": True,
                 "presentable": False, "unique": True,
                 "options": {"min": None, "max": None, "pattern": "^[a-z0-9-]+$"}},
                {"name": "plan", "type": "select", "required": False,
                 "presentable": False, "unique": False,
                 "options": {"maxSelect": 1,
                             "values": ["trial", "active", "suspended"]}},
                {"name": "instance_url", "type": "url", "required": False,
                 "presentable": False, "unique": False,
                 "options": {"exceptDomains": None, "onlyDomains": None}},
                {"name": "schema_version", "type": "number", "required": False,
                 "presentable": False, "unique": False,
                 "options": {"min": None, "max": None, "noDecimal": True}},
                {"name": "billing_email", "type": "email", "required": False,
                 "presentable": False, "unique": False,
                 "options": {"exceptDomains": None, "onlyDomains": None}},
            ],
            "indexes": ["CREATE UNIQUE INDEX idx_tenant_slug ON tenants (slug)"],
            "listRule": None, "viewRule": None, "createRule": None,
            "updateRule": None, "deleteRule": None,
        }
        if apply:
            code, body = req("POST", "/api/collections", tenants)
            print("    create tenants:", code, "ok" if code == 200 else body)
            tid = body.get("id")
        else:
            print("    would create `tenants` (name, slug, plan, instance_url, "
                  "schema_version, billing_email)")
            tid = None

    _add_user_cache_fields(apply, tid)

    if "memberships" in cols:
        print("    memberships already exists")
        return
    membership = {
        "name": "memberships", "type": "base",
        "schema": [
            _field("user", {"collectionId": uid, "cascadeDelete": True,
                            "minSelect": None, "maxSelect": 1}, True),
            _field("tenant", {"collectionId": tid, "cascadeDelete": True,
                              "minSelect": None, "maxSelect": 1}, True),
            {"name": "role", "type": "select", "required": True,
             "presentable": False, "unique": False,
             "options": {"maxSelect": 1,
                         "values": ["owner", "admin", "manager", "staff"]}},
            {"name": "status", "type": "select", "required": False,
             "presentable": False, "unique": False,
             "options": {"maxSelect": 1,
                         "values": ["active", "invited", "suspended"]}},
        ],
        "indexes": [
            "CREATE UNIQUE INDEX idx_membership_user_tenant "
            "ON memberships (user, tenant)"
        ],
        "listRule": None, "viewRule": None, "createRule": None,
        "updateRule": None, "deleteRule": None,
    }
    if apply:
        code, body = req("POST", "/api/collections", membership)
        print("    create memberships:", code, "ok" if code == 200 else body)
    else:
        print("    would create `memberships` (user, tenant, role, status)")


def _add_user_cache_fields(apply, tid):
    """users.tenants / staff_tenants / admin_tenants — hook-free membership
    caches the API rules read."""
    ucol = collections().get("users")
    if not ucol:
        return
    have = {f["name"] for f in ucol["schema"]}
    want = ["tenants", "staff_tenants", "admin_tenants"]
    rid = collections().get("tenants", {}).get("id") or tid
    add = [{"name": n, "type": "relation", "required": False,
            "presentable": False, "unique": False,
            "options": {"collectionId": rid, "cascadeDelete": False,
                        "minSelect": None, "maxSelect": None}}
           for n in want if n not in have]
    if not add:
        print("    users cache fields already present")
    elif apply:
        code, body = req("PATCH", f"/api/collections/{ucol['id']}",
                         {"schema": ucol["schema"] + add})
        print("    users cache fields:", code, "" if code == 200 else body)
    else:
        print(f"    would add users.{{{','.join(n for n in want)}}} (multi-rel)")


def stage2_seed(apply, cols):
    print("[2] seed tenant rows + owner memberships")
    now = collections()
    coll = "tenants" if "tenants" in now else "workspace"
    if coll not in now:
        print("    (stage 1 not applied yet — skipping in dry run)")
        return {}
    tenants = all_records(coll)
    by_name = {t.get("name") or t.get("tenant_name"): t for t in tenants}
    ids = {}
    for tname, slug in TENANT_SLUGS.items():
        t = by_name.get(tname)
        if t:
            ids[slug] = t["id"]
            if apply and not t.get("slug"):
                req("PATCH", f"/api/collections/{coll}/records/{t['id']}",
                    {"slug": slug, "plan": "active"})
            print(f"    {tname}: {t['id']} (slug={slug})")
        elif apply:
            code, body = req("POST", f"/api/collections/{coll}/records",
                             {"name": tname, "slug": slug, "plan": "active"})
            ids[slug] = body.get("id")
            print(f"    created {tname}: {ids[slug]}")
        else:
            print(f"    would create tenant {tname}")

    # The platform owner (PB_OWNER_EMAIL, else the admin login) owns every tenant
    me = None
    for u in all_records("users"):
        if u.get("email") in (IDENT, os.environ.get("PB_OWNER_EMAIL")):
            me = u["id"]
    print(f"    owner user: {me}")
    if "memberships" in collections():
        existing = {(m["user"], m["tenant"]) for m in all_records("memberships")}
        for slug, tid in ids.items():
            if me and (me, tid) not in existing:
                if apply:
                    code, body = req("POST",
                                     "/api/collections/memberships/records",
                                     {"user": me, "tenant": tid,
                                      "role": "owner", "status": "active"})
                    print(f"    membership {slug}:", code)
                else:
                    print(f"    would add owner membership for {slug}")
        recompute_user_caches(apply)
    return ids


def recompute_user_caches(apply):
    """Rebuild users.tenants / staff_tenants / admin_tenants from memberships.
    The app must do the equivalent whenever a membership changes."""
    if "memberships" not in collections():
        return
    per_user = {}
    for m in all_records("memberships"):
        if m.get("status") != "active":
            continue
        d = per_user.setdefault(m["user"], {"tenants": set(), "staff": set(),
                                            "admin": set()})
        d["tenants"].add(m["tenant"])
        if m.get("role") == "staff":
            d["staff"].add(m["tenant"])
        if m.get("role") in ("owner", "admin"):
            d["admin"].add(m["tenant"])
    print(f"    recompute caches for {len(per_user)} user(s)"
          f"{'' if apply else ' (dry run)'}")
    if not apply:
        return
    for uid, d in per_user.items():
        req("PATCH", f"/api/collections/users/records/{uid}",
            {"tenants": sorted(d["tenants"]),
             "staff_tenants": sorted(d["staff"]),
             "admin_tenants": sorted(d["admin"])})


def stage3_add_tenant_field(apply, cols):
    print("[3] add nullable `tenant` field to operational collections")
    now = collections()
    tid = now.get("tenants", {}).get("id")
    if not tid:
        print("    (tenants collection not created yet — skipping in dry run)")
        return
    for name in OPERATIONAL:
        c = cols.get(name)
        if not c:
            print(f"    - {name}: MISSING, skip")
            continue
        if any(f["name"] == "tenant" for f in c["schema"]):
            print(f"    = {name}: already has tenant")
            continue
        schema = c["schema"] + [_field(
            "tenant", {"collectionId": tid, "cascadeDelete": False,
                       "minSelect": None, "maxSelect": 1}, False)]
        if apply:
            code, body = req("PATCH", f"/api/collections/{c['id']}",
                             {"schema": schema})
            print(f"    + {name}:", code, "" if code == 200 else body)
        else:
            print(f"    + {name}: would add tenant (nullable)")


def stage4_backfill(apply, cols):
    print(f"[4] backfill tenant = {BACKFILL_TENANT_SLUG} on existing rows")
    now = collections()
    tid = None
    if "tenants" in now:
        for t in all_records("tenants"):
            if t.get("slug") == BACKFILL_TENANT_SLUG or t.get("name") == "Natura":
                tid = t["id"]
    if not tid:
        print(f"    (no '{BACKFILL_TENANT_SLUG}' tenant yet — dry run estimate only)")
    total = 0
    for name in OPERATIONAL:
        if name not in now:
            continue
        rows = all_records(name)
        todo = [r for r in rows if not r.get("tenant")]
        total += len(todo)
        if not todo:
            continue
        print(f"    {name}: {len(todo)}/{len(rows)} rows")
        if apply and tid:
            for r in todo:
                code, _ = req(
                    "PATCH", f"/api/collections/{name}/records/{r['id']}",
                    {"tenant": tid})
                if code != 200:
                    print(f"      !! {r['id']} -> {code}")
    print(f"    {'set' if apply else 'would set'} tenant on {total} rows")


def stage5_require(apply, cols):
    print("[5] make `tenant` required")
    now = collections()
    for name in OPERATIONAL:
        c = now.get(name)
        if not c:
            continue
        changed = False
        for f in c["schema"]:
            if f["name"] == "tenant" and not f["required"]:
                f["required"] = True
                changed = True
        if not changed:
            continue
        if apply:
            code, body = req("PATCH", f"/api/collections/{c['id']}",
                             {"schema": c["schema"]})
            print(f"    {name}:", code, "" if code == 200 else body)
        else:
            print(f"    {name}: would set tenant required")


def stage6_rules(apply, cols):
    print("[6] apply tenant-scoped API rules")
    # timelogs: managers+ see all in the tenant; staff see only their own.
    TL = f'{MEMBER} && ({NOT_STAFF_HERE} || employee = @request.auth.employee)'
    TL_CREATE = (f'{MEMBER_CREATE} && ({NOT_STAFF_HERE_CREATE} '
                 '|| @request.data.employee = @request.auth.employee)')
    # tasks: managers+ see all; staff see only tasks assigned to them.
    TK = f'{MEMBER} && ({NOT_STAFF_HERE} || assigned_to.id ?= @request.auth.id)'

    plan = {}
    for name in OPERATIONAL:
        plan[name] = dict(listRule=MEMBER, viewRule=MEMBER,
                          createRule=MEMBER_CREATE, updateRule=MEMBER,
                          deleteRule=MEMBER)
    plan["timelogs"] = dict(listRule=TL, viewRule=TL, createRule=TL_CREATE,
                            updateRule=TL, deleteRule=TL)
    plan["tasks"] = dict(
        listRule=TK, viewRule=TK, updateRule=TK,
        createRule=f'{MEMBER_CREATE} && {NOT_STAFF_HERE_CREATE}',
        deleteRule=f'{MEMBER} && {NOT_STAFF_HERE}')
    # payroll / payouts: managers+ only.
    for name in ("payroll", "payouts", "invoice_est"):
        plan[name] = dict(
            listRule=f'{MEMBER} && {NOT_STAFF_HERE}',
            viewRule=f'{MEMBER} && {NOT_STAFF_HERE}',
            createRule=f'{MEMBER_CREATE} && {NOT_STAFF_HERE_CREATE}',
            updateRule=f'{MEMBER} && {NOT_STAFF_HERE}',
            deleteRule=f'{MEMBER} && {NOT_STAFF_HERE}')
    plan["memberships"] = dict(
        listRule=MEMBER, viewRule=MEMBER,
        createRule=ADMIN_HERE_CREATE,
        updateRule=ADMIN_HERE, deleteRule=ADMIN_HERE)
    plan["tenants"] = dict(
        listRule='@request.auth.tenants.id ?= id',
        viewRule='@request.auth.tenants.id ?= id',
        createRule=None,
        updateRule='@request.auth.admin_tenants.id ?= id',
        deleteRule=None)
    plan["users"] = dict(listRule='@request.auth.id != ""',
                         viewRule='@request.auth.id != ""',
                         updateRule='id = @request.auth.id')

    now = collections()
    for name, rules in plan.items():
        c = now.get(name)
        if not c:
            print(f"    - {name}: missing")
            continue
        if apply:
            code, body = req("PATCH", f"/api/collections/{c['id']}", rules)
            print(f"    {name}:", code, "" if code == 200 else str(body)[:200])
        else:
            print(f"    {name}: list = {rules['listRule'][:70]}...")


def stage7_verify(apply, cols):
    """End-to-end: anon sees nothing; a throwaway member sees only Natura;
    `tenant` is required. Cleans up after itself."""
    print("[7] verify rules (creates + deletes a throwaway user)")
    ten = {t["slug"]: t["id"]
           for t in all_records("tenants")}
    natura = ten.get("natura")
    print(f"    natura = {natura}")

    kalmark = ten.get("kalmark")

    for coll in ("contactss", "companies", "timelogs"):
        code, body = req("GET", f"/api/collections/{coll}/records?perPage=1",
                         token=None)
        n = body.get("totalItems")
        print(f"    anon {coll}: {code} items={n}  {'OK' if not n else 'LEAK!'}")

    if not apply:
        print("    (pass --apply to run the member check)")
        return

    made, kco, uid, mid = None, None, None, None
    try:
        # a company that belongs to Kalmark, for the cross-tenant check
        _, b = req("POST", "/api/collections/companies/records",
                   {"company": "KalmarkOnlyCo", "tenant": kalmark})
        kco = b.get("id")

        email = f"tenancy-check-{int(time.time())}@example.com"
        pw = "verify-pw-12345"
        _, u = req("POST", "/api/collections/users/records",
                   {"email": email, "password": pw, "passwordConfirm": pw})
        uid = u.get("id")
        _, m = req("POST", "/api/collections/memberships/records",
                   {"user": uid, "tenant": natura, "role": "manager",
                    "status": "active"})
        mid = m.get("id")
        recompute_user_caches(True)
        time.sleep(1)
        _, auth = req("POST", "/api/collections/users/auth-with-password",
                      {"identity": email, "password": pw})
        ut = auth.get("token")

        for coll in ("contactss", "companies", "leads", "timelogs", "property"):
            code, body = req("GET", f"/api/collections/{coll}/records?perPage=1",
                             token=ut)
            print(f"    natura-member {coll}: {code} items={body.get('totalItems')}")
        code, body = req("GET",
                         f'/api/collections/companies/records?filter=(id="{kco}")',
                         token=ut)
        print(f"    natura-member sees Kalmark co: items={body.get('totalItems')}"
              f"  {'OK' if not body.get('totalItems') else 'LEAK!'}")

        c1, _ = req("POST", "/api/collections/companies/records",
                    {"company": "NoTenantCo"}, token=ut)
        print(f"    member create w/o tenant: {c1} (expect 400)")
        c2, b2 = req("POST", "/api/collections/companies/records",
                     {"company": "VerifyCo", "tenant": natura}, token=ut)
        print(f"    member create in own tenant:  {c2} (expect 200)")
        made = b2.get("id")
        c3, _ = req("POST", "/api/collections/companies/records",
                    {"company": "CrossCo", "tenant": kalmark}, token=ut)
        print(f"    member create in other tenant: {c3} (expect 400)")
    finally:
        for coll, rid in (("companies", made), ("companies", kco),
                          ("memberships", mid), ("users", uid)):
            if rid:
                req("DELETE", f"/api/collections/{coll}/records/{rid}")
        print("    cleaned up")


STAGES = {
    0: stage0_backup, 1: stage1_core, 2: stage2_seed,
    3: stage3_add_tenant_field, 4: stage4_backfill,
    5: stage5_require, 6: stage6_rules, 7: stage7_verify,
}


def parse_stages(s):
    if not s:
        return sorted(STAGES)
    out = set()
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out.update(range(int(a), int(b) + 1))
        else:
            out.add(int(part))
    return sorted(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default="")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    auth()
    print(f"{'APPLYING' if args.apply else 'DRY RUN'} against {BASE}\n")
    for n in parse_stages(args.stage):
        cols = collections()
        fn = STAGES[n]
        if fn is stage0_backup:
            fn(args.apply)
        else:
            fn(args.apply, cols)
        print()


if __name__ == "__main__":
    main()
