#!/usr/bin/env python3
"""End-to-end check of the tenancy rules against the live server.

Creates a throwaway user + Natura membership, signs in AS that user, checks it
sees only Natura data, then cleans up. Also checks anon access is empty.
"""
import json
import os
import time
import urllib.error
import urllib.request

_c = {}
p = os.path.expanduser("~/.thyme-pb-admin")
if os.path.exists(p):
    for line in open(p):
        if "=" in line and not line.startswith("#"):
            k, v = line.strip().split("=", 1)
            _c[k] = v
BASE = _c["PB_URL"].rstrip("/")
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")


def req(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method)
    r.add_header("Content-Type", "application/json")
    r.add_header("User-Agent", UA)
    if token:
        r.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(r, timeout=40) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"_raw": raw.decode(errors="replace")[:300]}


admin = req("POST", "/api/admins/auth-with-password",
            {"identity": _c["PB_ADMIN"], "password": _c["PB_ADMIN_PW"]})[1]["token"]


def A(m, pth, b=None):
    return req(m, pth, b, admin)


tenants = {t["slug"]: t["id"] for t in A("GET", "/api/collections/tenants/records")[1]["items"]}
natura = tenants["natura"]
print("natura tenant:", natura)

# --- anon sees nothing ---
for coll in ("contactss", "companies", "timelogs"):
    code, body = req("GET", f"/api/collections/{coll}/records?perPage=1")
    print(f"anon {coll}: {code} items={body.get('totalItems')}")

# --- throwaway member ---
email = f"tenancy-check-{int(time.time())}@example.com"
pw = "verify-pw-12345"
code, u = A("POST", "/api/collections/users/records",
            {"email": email, "password": pw, "passwordConfirm": pw,
             "first_name": "Tenancy", "last_name": "Check"})
print("create user:", code, u.get("id"))
uid = u["id"]
code, m = A("POST", "/api/collections/memberships/records",
            {"user": uid, "tenant": natura, "role": "manager", "status": "active"})
print("create membership:", code, m.get("id"))
mid = m.get("id")

time.sleep(1)
code, auth = req("POST", "/api/collections/users/auth-with-password",
                 {"identity": email, "password": pw})
utok = auth.get("token")
print("member auth:", code)


def U(m, pth, b=None):
    return req(m, pth, b, utok)


for coll in ("contactss", "companies", "leads", "timelogs", "property"):
    code, body = U("GET", f"/api/collections/{coll}/records?perPage=1")
    print(f"member {coll}: {code} items={body.get('totalItems')}")

# create without tenant should fail; with tenant should work
code, body = U("POST", "/api/collections/companies/records", {"company": "NoTenantCo"})
print(f"member create w/o tenant: {code} (expect 400)")
code, body = U("POST", "/api/collections/companies/records",
               {"company": "VerifyCo", "tenant": natura})
print(f"member create w/ tenant: {code} (expect 200)")
made = body.get("id")

# --- cleanup ---
if made:
    A("DELETE", f"/api/collections/companies/records/{made}")
if mid:
    A("DELETE", f"/api/collections/memberships/records/{mid}")
A("DELETE", f"/api/collections/users/records/{uid}")
print("cleaned up")
