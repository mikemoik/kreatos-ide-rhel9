#!/usr/bin/env bash
# test/run.sh — prove the offline build on a clean RHEL9 (UBI9) container.
# The image only gets the toolchain RPMs; build + smoke test run with
# --network=none and the repo mounted read-only.
#
# It builds from the files git tracks (as in the working tree), copied to a
# temp dir: what install.sh downloads. Untracked or git-ignored files and empty
# directories are left out, as they are in the GitHub tarball.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=kreatos-ide-rhel9-test
SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT
git -C "$ROOT" ls-files -z | tar -C "$ROOT" --null -T - -cf - | tar -C "$SRC" -xf -

docker build -q -t "$IMAGE" -f "$ROOT/test/Containerfile" "$ROOT/test" >/dev/null
docker run --rm --network=none -v "$SRC:/src:ro" -e KIDE_SRC=/src "$IMAGE" bash -euc '
  /src/build.sh /opt/kide
  echo "==> smoke test"
  /opt/kide/bin/kide --headless "+lua dofile(\"/src/test/smoke.lua\")"
  echo "==> fish smoke test"
  /opt/kide/bin/fish -i -c "
    source /opt/kide/share/kreatos-ide/fish/config.fish
    test \$PATH[1] = /opt/kide/bin; or exit 1
    test \$YAZI_CONFIG_HOME = /opt/kide/share/kreatos-ide/yazi; or exit 1
    functions -q vi lg y ll ff ffex tm; or exit 1
    command -q lazygit; or exit 1
    command -q tmux; or exit 1
    echo fish ok: (fish --version)
  "
  echo "==> C/C++ libraries (cmake 4, onnxruntime, ACE+TAO, OpenDDS)"
  export PATH=/opt/kide/bin:$PATH
  cmake --version | grep -q "^cmake version 4\\."
  cmake -S /src/test/devlibs -B /tmp/devlibs -D CMAKE_BUILD_TYPE=Release >/tmp/devlibs.log ||
    { cat /tmp/devlibs.log; exit 1; }
  cmake --build /tmp/devlibs -j "$(nproc)" >>/tmp/devlibs.log || { tail -40 /tmp/devlibs.log; exit 1; }
  /tmp/devlibs/devlibs
  # the installed tools run from PREFIX alone ($ORIGIN-relative RPATH)
  rm -rf "${KIDE_BUILD_DIR:-/tmp/kide-build}/dds"
  tao_idl -V 2>&1 | grep -m1 "TAO_IDL_FE"
  opendds_idl --version 2>&1 | head -1
'
