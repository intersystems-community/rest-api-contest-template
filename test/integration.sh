#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${IRIS_ANVIL_URL:-http://127.0.0.1:52773}"

wait_for() {
  local url="$1"
  for _ in $(seq 1 60); do
    if curl --fail --silent --show-error "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for $url" >&2
  return 1
}

status() {
  curl --silent --output /dev/null --write-out '%{http_code}' "$@"
}

wait_for "$BASE_URL/csp/sys/UtilHome.csp"

./scripts/bootstrap.sh >/tmp/iris-anvil-bootstrap.log
docker exec -i iris-anvil-iris iris session IRIS < scripts/deploy_demo.scr >/tmp/iris-anvil-deploy.log

test "$(status "$BASE_URL/anvil/api/overview")" = "200"
test "$(status "$BASE_URL/anvil/api/reactor/plan")" = "200"
test "$(status -X POST "$BASE_URL/anvil/api/proposals")" = "404"
test "$(status "$BASE_URL/anvil/admin/overview")" = "401"
test "$(status "$BASE_URL/anvil-demo/overview")" = "200"

python3 - "$BASE_URL" <<'PY'
import json
import sys
import urllib.request

base = sys.argv[1]
with urllib.request.urlopen(base + "/anvil/api/reactor/plan", timeout=5) as response:
    plan = json.load(response)

assert plan["id"] == "deploy-webapp"
assert plan["label"] == "Deploy IRIS Web Application"
assert [node["id"] for node in plan["nodes"]] == [
    "validate", "resolve", "plan", "execute", "verify", "receipt"
]

with urllib.request.urlopen(base + "/anvil-demo/overview", timeout=5) as response:
    deployed = json.load(response)

assert deployed["runtime"] == "IRIS"
assert deployed["cartridge"] == "management"
print("IRIS Anvil integration: PASS")
PY
