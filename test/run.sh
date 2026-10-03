#!/usr/bin/env bash
# test/run.sh — prove the offline build on a clean RHEL9 (UBI9) container.
# The image only gets the toolchain RPMs; build + smoke test run with
# --network=none and the repo mounted read-only.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=kreatos-ide-rhel9-test

docker build -q -t "$IMAGE" -f "$ROOT/test/Containerfile" "$ROOT/test" >/dev/null
docker run --rm --network=none -v "$ROOT:/src:ro" -e KIDE_SRC=/src "$IMAGE" bash -euc '
  /src/build.sh /opt/kide
  echo "==> smoke test"
  /opt/kide/bin/kide --headless "+lua dofile(\"/src/test/smoke.lua\")"
'
