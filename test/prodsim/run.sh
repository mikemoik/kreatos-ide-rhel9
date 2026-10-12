#!/usr/bin/env bash
# test/prodsim/run.sh [--show] — the prod workflow end to end, with prodsim
# standing in for the prod software:
#   1. kide container (image $KIDE_IMAGE, default kide): build-dist.sh into
#      /workspace/kide-dist (skipped when already there), then, with
#      kide-dist-env.fish sourced, build prodsim and install it to /workspace
#   2. prodsim-host container (test/prodsim/host/Containerfile: runtime RPMs
#      only, no compiler, no dist/ libraries): prodsim-demo from /workspace/bin,
#      no LD_LIBRARY_PATH, viewer under Xvfb, 120 frames + screenshot
#   3. here: the report has tracks, the screenshot shows the pyramid
# Both containers mount the same workspace, $PRODSIM_WORKSPACE (default
# ~/.cache/prodsim-workspace; not ~/workspace), on /workspace.
# --show: step 2 opens the viewer on your display instead (X11/XWayland,
# DISPLAY and /tmp/.X11-unix), until you close the window.
# Needs the kide image built from this checkout (with /opt/kide/dist).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
KIDE_IMAGE=${KIDE_IMAGE:-kide}
WS=${PRODSIM_WORKSPACE:-$HOME/.cache/prodsim-workspace}
SHOW=0
[ "${1:-}" = --show ] && SHOW=1

uid=$(sed -n 's/^KIDE_UID=//p' "$ROOT/podman/base.conf")
gid=$(sed -n 's/^KIDE_GID=//p' "$ROOT/podman/base.conf")
mkdir -p "$WS"
run=(podman run --rm --http-proxy=false --userns="keep-id:uid=$uid,gid=$gid" -v "$WS:/workspace:Z")

echo "==> 1. kide: build-dist.sh + prodsim into $WS"
# kide-dist-env.fish: TAO_ROOT, CMAKE_PREFIX_PATH, CPLUS_INCLUDE_PATH and
# LIBRARY_PATH (prodsim-idlc links plain -lACE as prod does). Sourced
# explicitly: the fish config only does so when it exists at shell start.
"${run[@]}" -v "$ROOT/test/prodsim:/src/prodsim:ro,Z" --entrypoint fish "$KIDE_IMAGE" -c '
  if not test -e /workspace/kide-dist/lib/libOpenDDS_Dcps.so
    build-dist.sh; or exit 1
  else
    echo "build-dist.sh: already in /workspace/kide-dist (rm -rf it to redo)"
  end
  source /workspace/kide-dist/bin/kide-dist-env.fish; or exit 1
  cmake -S /src/prodsim -B /tmp/prodsim-build -D CMAKE_INSTALL_PREFIX=/workspace; or exit 1
  cmake --build /tmp/prodsim-build -j (nproc); or exit 1
  cmake --install /tmp/prodsim-build; or exit 1
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
