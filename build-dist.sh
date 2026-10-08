#!/usr/bin/env bash
# build-dist.sh [PREFIX] — offline build of the C/C++ libraries from dist/
# (manifest/dist.tsv) into PREFIX (default ~/.local/kreatos-ide), no network:
#   PREFIX/bin/{cmake,ctest,cpack}    CMake 4 (upstream's prebuilt)
#   PREFIX/{include,lib64}            onnxruntime (upstream's prebuilt)
#   PREFIX/{bin,include,lib,share}    ACE+TAO 8 + OpenDDS 3.34 built from source
# Separate from build-ide.sh (the IDE): install.sh and test/run.sh run both,
# podman/Containerfile runs them as separate layers, devcontainer/Containerfile
# only this one. Needs gcc/g++, make, perl, perl-Dumpvalue and bzip2. Intermediate
# files go to $KIDE_BUILD_DIR (default: $TMPDIR/kide-build); JOBS (default
# nproc) parallel make jobs.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
PREFIX=$(realpath -m "${1:-$HOME/.local/kreatos-ide}")
BUILD=$(realpath -m "${KIDE_BUILD_DIR:-${TMPDIR:-/tmp}/kide-build}")
JOBS=${JOBS:-$(nproc)}

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

for tool in cc c++ make perl bzip2 tar sha256sum; do
  command -v "$tool" >/dev/null || { echo "missing build tool: $tool" >&2; exit 1; }
done
mkdir -p "$PREFIX" "$BUILD"

# upstream release tarballs (manifest/dist.tsv), sha256-checked first. cmake
# and onnxruntime are upstream's own Linux x86_64 builds, unpacked as shipped;
# ACE+TAO, OpenDDS and RapidJSON are source and compiled here.
log "dist: checking tarballs"
awk -F'\t' '!/^#/ && NF { print $6 "  " $4 }' "$ROOT/manifest/dist.tsv" |
  (cd "$ROOT/dist" && sha256sum -c --quiet -)
dist() { echo "$ROOT/dist/$(awk -F'\t' -v n="$1" '$1 == n { print $4 }' "$ROOT/manifest/dist.tsv")"; }

log "cmake (prebuilt)"
# without the docs and the Qt GUI (cmake-gui and its desktop files)
rm -rf "$PREFIX"/share/cmake-[0-9]*
tar -xzf "$(dist cmake)" -C "$PREFIX" --strip-components=1 \
  --exclude='cmake-*/doc' --exclude='cmake-*/bin/cmake-gui' --exclude='cmake-*/share/applications' \
  --exclude='cmake-*/share/icons' --exclude='cmake-*/share/mime'

log "onnxruntime (prebuilt)"
# into lib64/ and include/onnxruntime/: where the tarball's own CMake config
# and pkg-config file look (the tarball itself has lib/ and include/)
ort=$BUILD/onnxruntime
rm -rf "$ort" "$PREFIX/include/onnxruntime" "$PREFIX"/lib64/libonnxruntime* "$PREFIX/lib64/cmake/onnxruntime"
mkdir -p "$ort" "$PREFIX/include/onnxruntime" "$PREFIX/lib64" "$PREFIX/share/doc/onnxruntime"
tar -xzf "$(dist onnxruntime)" -C "$ort" --strip-components=1
cp -a "$ort/include/." "$PREFIX/include/onnxruntime/"
cp -a "$ort/lib/." "$PREFIX/lib64/"
cp "$ort/LICENSE" "$ort/ThirdPartyNotices.txt" "$PREFIX/share/doc/onnxruntime/"
sed -i "s|^prefix=.*|prefix=$PREFIX|" "$PREFIX/lib64/pkgconfig/libonnxruntime.pc"

log "ACE+TAO + OpenDDS"
# OpenDDS's configure + GNU make build: unlike its CMake build, it installs
# ACE/TAO too (libs, headers, tao_idl). Release build, no tests; RPATHs are
# $ORIGIN-relative, so nothing needs LD_LIBRARY_PATH. RapidJSON (headers) is
# the commit OpenDDS pins; it is installed to PREFIX/include/rapidjson.
# ACE+TAO complete: OpenDDS's own workspace (DDS_TAOv2.mwc) builds only the
# ACE/TAO subset OpenDDS needs (ACE_TAO_for_OpenDDS.mwc). full.mwc is the same
# workspace with that subset replaced by ACE+TAO's full one (TAO/TAO_ACE.mwc:
# ACE, ACEXML, Kokyu, protocols, gperf, all of TAO, TAO_IDL, the TAO utils and
# orbsvcs with their services; no tests/examples). Projects that need an MPC
# feature that is off by default (ssl, zlib, xerces, Qt/Xt/Tk/Fl/Fox) are skipped.
dds=$BUILD/dds
rm -rf "$dds"
mkdir -p "$dds/rapidjson"
tar -xjf "$(dist ace-tao)" -C "$dds"
tar -xzf "$(dist opendds)" -C "$dds"
tar -xzf "$(dist rapidjson)" -C "$dds/rapidjson" --strip-components=1
cat >"$dds/full.mwc" <<'MWC'
workspace {
  $(ACE_ROOT)/ace
  $(ACE_ROOT)/apps/gperf/src
  $(ACE_ROOT)/ACEXML/common
  $(ACE_ROOT)/ACEXML/parser/parser
  $(ACE_ROOT)/ACEXML/apps/svcconf
  $(ACE_ROOT)/Kokyu/Kokyu.mpc
  $(ACE_ROOT)/protocols
  $(TAO_ROOT)/tao
  $(TAO_ROOT)/TAO_IDL
  $(TAO_ROOT)/utils
  $(TAO_ROOT)/orbsvcs
  dds
  tools
  java
  DevGuideExamples
  exclude {
    $(ACE_ROOT)/protocols/tests
    $(ACE_ROOT)/protocols/examples
    $(TAO_ROOT)/orbsvcs/tests
    $(TAO_ROOT)/orbsvcs/performance-tests
    $(TAO_ROOT)/orbsvcs/examples
    $(TAO_ROOT)/orbsvcs/DevGuideExamples
    java/jms
    tools/modeling/tests
  }
}
MWC
(cd "$dds"/OpenDDS-* &&
  ./configure --prefix="$PREFIX" --ace="$dds/ACE_wrappers" --tao="$dds/ACE_wrappers/TAO" \
    --mpc="$dds/ACE_wrappers/MPC" --ace-tao=ace8tao4 --rapidjson="$dds/rapidjson" \
    --workspace="$dds/full.mwc" \
    --no-debug --optimize --install-origin-relative >"$dds/configure.log" &&
  make -j "$JOBS" >"$dds/make.log" 2>&1 && make install >"$dds/install.log" 2>&1) ||
  { tail -30 "$dds/configure.log" "$dds/make.log" "$dds/install.log" 2>/dev/null; exit 1; }
# the installed config.cmake still names the build tree's ACE/TAO/MPC/RapidJSON,
# which would win over PREFIX (its OPENDDS_USE_PREFIX_PATH) and break once
# $BUILD is gone: drop them
sed -i -E '/^set\(OPENDDS_(SOURCE_DIR|MPC|ACE|TAO|RAPIDJSON) /d' "$PREFIX/share/cmake/OpenDDS/config.cmake"
if grep -v '^#' "$PREFIX/share/cmake/OpenDDS/config.cmake" | grep -qF "$dds"; then
  echo "OpenDDS config.cmake still refers to $dds" >&2
  exit 1
fi
