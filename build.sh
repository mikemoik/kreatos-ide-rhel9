#!/usr/bin/env bash
# build.sh [PREFIX] — offline build of kreatos-ide from vendor/ (no network).
#
# Needs only the RHEL9 toolchain: gcc, make, cmake, python3. The repo itself
# is never written to (it can be mounted read-only); intermediate files go to
# $KIDE_BUILD_DIR (default: $TMPDIR/kide-build).
#
# Result:
#   PREFIX/bin/nvim                   Neovim built from vendor/neovim
#   PREFIX/bin/kide                   launcher: nvim + the bundled config
#   PREFIX/share/kreatos-ide/config   config/ (init.lua, lua/misw, …)
#   PREFIX/share/kreatos-ide/site     pack/vendor/opt plugins, parser/, queries/
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
PREFIX=$(realpath -m "${1:-$HOME/.local/opt/kreatos-ide}")
BUILD=$(realpath -m "${KIDE_BUILD_DIR:-${TMPDIR:-/tmp}/kide-build}")
JOBS=${JOBS:-$(nproc)}
SHARE=$PREFIX/share/kreatos-ide
SITE=$SHARE/site

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

for tool in cc make cmake python3; do
  command -v "$tool" >/dev/null || { echo "missing build tool: $tool" >&2; exit 1; }
done

log "checking sources (no binaries)"
python3 "$ROOT/scripts/check-sources.py" "$ROOT/vendor" "$ROOT/config"

# --- Neovim ------------------------------------------------------------------
# cmake.deps with USE_EXISTING_SRC_DIR builds each dep from .deps/build/src/<name>
# instead of downloading; some deps build in-source, so work on a copy.
log "neovim: preparing sources in $BUILD"
rm -rf "$BUILD/neovim"
mkdir -p "$BUILD"
cp -a "$ROOT/vendor/neovim" "$BUILD/neovim"
# the desktop icon runtime/nvim.png was stripped (binary): drop its install rule
python3 - "$BUILD/neovim/runtime/CMakeLists.txt" <<'EOF'
import sys
path = sys.argv[1]
rule = """install_helper(
  FILES ${CMAKE_CURRENT_SOURCE_DIR}/nvim.png
  DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/128x128/apps)
"""
text = open(path).read()
if rule not in text:
    sys.exit("nvim.png install rule not found in " + path)
open(path, "w").write(text.replace(rule, ""))
EOF
mkdir -p "$BUILD/neovim/.deps/build/src"
cp -a "$ROOT/vendor/neovim-deps/." "$BUILD/neovim/.deps/build/src/"

log "neovim: bundled deps"
cmake -S "$BUILD/neovim/cmake.deps" -B "$BUILD/neovim/.deps" -G "Unix Makefiles" \
  -D USE_EXISTING_SRC_DIR=ON -D CMAKE_BUILD_TYPE=Release
cmake --build "$BUILD/neovim/.deps" -j "$JOBS"

log "neovim: nvim"
cmake -S "$BUILD/neovim" -B "$BUILD/neovim/build" -G "Unix Makefiles" \
  -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build "$BUILD/neovim/build" -j "$JOBS"
cmake --install "$BUILD/neovim/build"

# --- plugins + config ----------------------------------------------------------
log "plugins"
rm -rf "$SITE/pack"
mkdir -p "$SITE/pack/vendor/opt"
cp -a "$ROOT/vendor/plugins/." "$SITE/pack/vendor/opt/"

log "config"
rm -rf "$SHARE/config"
cp -a "$ROOT/config" "$SHARE/config"

# --- treesitter parsers + queries --------------------------------------------
# what nvim-treesitter's installer would do: parser/<lang>.so,
# parser-info/<lang>.revision, queries/<lang> (copied from its runtime)
log "treesitter parsers"
rm -rf "$SITE/parser" "$SITE/parser-info" "$SITE/queries"
mkdir -p "$SITE/parser" "$SITE/parser-info" "$SITE/queries"
queries_src=$ROOT/vendor/plugins/nvim-treesitter/runtime/queries
while IFS=$'\t' read -r lang url rev location; do
  if [[ -d $queries_src/$lang ]]; then
    cp -a "$queries_src/$lang" "$SITE/queries/$lang"
  fi
  [[ $url == - ]] && continue # query-only language
  src=$ROOT/vendor/grammars/$(basename "${url%.git}")
  [[ $location != - ]] && src=$src/$location
  files=("$src/src/parser.c")
  [[ -f $src/src/scanner.c ]] && files+=("$src/src/scanner.c")
  printf '  %s\n' "$lang"
  cc -O2 -fPIC -shared -I"$src/src" "${files[@]}" -o "$SITE/parser/$lang.so"
  echo "$rev" >"$SITE/parser-info/$lang.revision"
done <"$ROOT/manifest/parsers.lock.tsv"

# --- launcher ----------------------------------------------------------------
log "launcher"
cat >"$PREFIX/bin/kide" <<'EOF'
#!/bin/sh
# kreatos-ide: the bundled nvim with the bundled config. NVIM_APPNAME keeps its
# data/state/cache (~/.local/share/kreatos-ide, …) apart from any other nvim.
bin=$(dirname "$(readlink -f "$0")")
export NVIM_APPNAME=kreatos-ide
exec "$bin/nvim" -u "$bin/../share/kreatos-ide/config/init.lua" "$@"
EOF
chmod +x "$PREFIX/bin/kide"

log "done: $PREFIX/bin/kide"
