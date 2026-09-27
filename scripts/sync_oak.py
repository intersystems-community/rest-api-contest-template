#!/usr/bin/env python3
import base64, datetime, json, os, pathlib, sys, urllib.error, urllib.parse, urllib.request

IRIS = os.environ.get("IRIS_URL", "http://127.0.0.1:52773/anvil/api")
SLING = os.environ.get("SLING_URL", "http://127.0.0.1:8082")
USER = os.environ.get("SLING_USER")
PASSWORD = os.environ.get("SLING_PASS")
if not USER or not PASSWORD:
    raise SystemExit("SLING_USER and SLING_PASS are required")

AUTH = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()

def request(url, method="GET", data=None, sling=False):
    headers = {"Accept": "application/json"}
    if sling:
        headers["Authorization"] = AUTH
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

def get_json(url, sling=False):
    code, body = request(url, sling=sling)
    if code != 200:
        raise RuntimeError(f"GET {url}: HTTP {code}")
    return json.loads(body)

def ensure_child(parent, name):
    code, _ = request(f"{SLING}{parent}/{name}.json", sling=True)
    if code == 200:
        return
    code, _ = request(
        f"{SLING}{parent}/*", "POST",
        {":name": name, "jcr:primaryType": "nt:unstructured"},
        sling=True,
    )
    if code not in (200, 201):
        raise RuntimeError(f"create {parent}/{name}: HTTP {code}")

ensure_child("/content", "iris-anvil")
ensure_child("/content/iris-anvil", "receipts")

ledger = get_json(f"{IRIS}/ledger")
mirrored = []
last = None
for item in ledger.get("items", []):
    rid = str(item["id"])
    verify = get_json(f"{IRIS}/proposals/{rid}/verify")
    if not verify.get("verified"):
        print(f"SKIP #{rid}: digest mismatch", file=sys.stderr)
        continue

    path = f"/content/iris-anvil/receipts/{rid}"
    exists, _ = request(f"{SLING}{path}.json", sling=True)
    fields = {
        "state": item["state"],
        "action": item["action"],
        "target": item["target"],
        "digest": item["digest"],
        "receipt": item.get("receipt", ""),
        "verified": "true",
        "source": "IRIS",
    }
    if exists == 200:
        code, _ = request(f"{SLING}{path}", "POST", fields, sling=True)
    else:
        fields[":name"] = rid
        code, _ = request(
            f"{SLING}/content/iris-anvil/receipts/*", "POST", fields, sling=True
        )
    if code not in (200, 201):
        raise RuntimeError(f"mirror #{rid}: HTTP {code}")
    mirrored.append(rid)
    last = {"id": rid, "digest": item["digest"], "receipt": item.get("receipt", "")}

status = {
    "status": "MIRRORED" if mirrored else "EMPTY",
    "count": len(mirrored),
    "mirrored": mirrored,
    "last": last,
    "updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
status_path = pathlib.Path(__file__).resolve().parent.parent / "web" / "oak-status.json"
status_path.write_text(json.dumps(status, separators=(",", ":")) + "\n")
print(json.dumps(status))
