#!/usr/bin/env bash
# test/prodsim/run.sh [--show] — the prod workflow end to end, with prodsim
# standing in for the prod software:
#   1. build container (image $IBN_DEV_IMAGE, default ibn-dev; kide, built on
#      top of it, works too): build-dist.sh into /workspace/ibn-dist (skipped
#      when already there), then, with ibn-dist-env.sh sourced, build prodsim
#      and install it to /workspace
#   2. prodsim-host container (test/prodsim/host/Containerfile: runtime RPMs
#      only, no compiler, no dist/ libraries): prodsim-demo from /workspace/bin,
#      no LD_LIBRARY_PATH, viewer under Xvfb, 120 frames + screenshot
#   3. here: the report has tracks, the screenshot shows the pyramid
# Both containers mount the same workspace, $PRODSIM_WORKSPACE (default
# ~/.cache/prodsim-workspace; not ~/workspace), on /workspace.
# --show: step 2 opens the viewer on your display instead (X11/XWayland,
# DISPLAY and /tmp/.X11-unix), until you close the window.
# Needs the ibn-dev image built from this checkout (podman/Containerfile.ibn-dev).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
IBN_DEV_IMAGE=${IBN_DEV_IMAGE:-ibn-dev}
WS=${PRODSIM_WORKSPACE:-$HOME/.cache/prodsim-workspace}
SHOW=0
[ "${1:-}" = --show ] && SHOW=1

uid=$(sed -n 's/^KIDE_UID=//p' "$ROOT/podman/base.conf")
gid=$(sed -n 's/^KIDE_GID=//p' "$ROOT/podman/base.conf")
mkdir -p "$WS"
run=(podman run --rm --http-proxy=false --userns="keep-id:uid=$uid,gid=$gid" -v "$WS:/workspace:Z")

echo "==> 1. $IBN_DEV_IMAGE: build-dist.sh + prodsim into $WS"
# ibn-dist-env.sh: TAO_ROOT, CMAKE_PREFIX_PATH, CPLUS_INCLUDE_PATH and
# LIBRARY_PATH (prodsim-idlc links plain -lACE as prod does)
"${run[@]}" -v "$ROOT/test/prodsim:/src/prodsim:ro,Z" --entrypoint bash "$IBN_DEV_IMAGE" -euc '
  if [ ! -e /workspace/ibn-dist/lib/libOpenDDS_Dcps.so ] || [ ! -e /workspace/ibn-dist/lib64/libgdal.so ]; then
    build-dist.sh
  else
    echo "build-dist.sh: already in /workspace/ibn-dist (rm -rf it to redo)"
  fi
  . /workspace/ibn-dist/bin/ibn-dist-env.sh
  cmake -S /src/prodsim -B /tmp/prodsim-build -D CMAKE_INSTALL_PREFIX=/workspace
  cmake --build /tmp/prodsim-build -j "$(nproc)"
  cmake --install /tmp/prodsim-build
'

echo "==> 2. prodsim-host: build the image"
podman build -q --build-arg-file "$ROOT/podman/base.conf" -t prodsim-host \
  -f "$ROOT/test/prodsim/host/Containerfile" "$ROOT" >/dev/null

if [ "$SHOW" = 1 ]; then
  echo "==> 2. prodsim-host: prodsim-demo on $DISPLAY (close the window to stop)"
  tty=()
  [ -t 0 ] && tty=(-it)  # -it only from a terminal
  "${run[@]}" "${tty[@]}" -e DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix --device /dev/dri \
    --security-opt label=disable prodsim-host /workspace/bin/prodsim-demo
  exit
fi

echo "==> 2. prodsim-host: libraries resolve without LD_LIBRARY_PATH, prodsim-demo under Xvfb"
"${run[@]}" prodsim-host bash -euc '
  test -z "${LD_LIBRARY_PATH:-}"
  ! command -v gcc
  for f in /workspace/bin/prodsim-{idlc,control,sensor,tracker,viewer}; do
    if ldd "$f" | grep "not found"; then echo "unresolved libraries in $f" >&2; exit 1; fi
  done
  # the dist GDAL (GTiff), not gdal-libs of the host (same soname, no GTiff)
  ldd /workspace/bin/prodsim-sensor | grep -q "libgdal.so.36 => .*/ibn-dist/lib64/libgdal" ||
    { echo "prodsim-sensor does not load the dist GDAL" >&2; exit 1; }
  Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
  sleep 1
  DISPLAY=:99 PRODSIM_RUN_DIR=/workspace/prodsim-run \
    /workspace/bin/prodsim-demo --frames 120 --screenshot /workspace/prodsim-run/pyramid.ppm
'

echo "==> 3. results"
python3 -I - "$WS/prodsim-run" <<'PY'
import json, sys
run = sys.argv[1]
report = json.load(open(f"{run}/prodsim-report.json"))
tracks = report["tracks"]
assert report["detections"] > 0 and tracks, "no detections/tracks in the report"
print(f"report: {report['detections']} detections, {len(tracks)} tracks, participant {report['participant']}")

data = open(f"{run}/pyramid.ppm", "rb").read()
w, h = map(int, data.split(b"\n")[1].split())
px = data[-w * h * 3:]
bg = px[:3]  # corner: clear colour
centre = (h // 2 * w + w // 2) * 3
lit = sum(1 for i in range(0, len(px), 3) if px[i:i + 3] != bg)
assert px[centre:centre + 3] != bg, "screenshot centre is background: no pyramid"
assert lit > w * h // 20, f"only {lit} non-background pixels"
print(f"screenshot: {w}x{h}, {lit} pyramid pixels, centre RGB {tuple(px[centre:centre + 3])}")
PY
echo "prodsim: ok"
