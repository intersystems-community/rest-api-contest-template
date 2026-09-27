#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${IRIS_CONTAINER:-iris-anvil-iris}"
BASE_URL="${IRIS_ANVIL_URL:-http://127.0.0.1:52773}"

for _ in $(seq 1 90); do
  health=$(docker inspect --format "{{.State.Health.Status}}" "$CONTAINER" 2>/dev/null || true)
  if [ "$health" = "healthy" ]; then break; fi
  sleep 1
done

health=$(docker inspect --format "{{.State.Health.Status}}" "$CONTAINER" 2>/dev/null || true)
if [ "$health" != "healthy" ]; then
  echo "IRIS container did not become healthy" >&2
  exit 1
fi

docker exec -i "$CONTAINER" iris session IRIS < "$ROOT/scripts/bootstrap_iris.scr"

for _ in $(seq 1 30); do
  if curl -fsS "$BASE_URL/anvil/api/overview" >/dev/null 2>&1; then
    echo "IRIS Anvil bootstrap complete: $BASE_URL/anvil/index.html"
    exit 0
  fi
  sleep 1
done

echo "IRIS Anvil web application did not become ready" >&2
exit 1
