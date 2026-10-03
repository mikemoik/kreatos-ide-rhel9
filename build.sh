#!/usr/bin/env bash
# build.sh [PREFIX] — offline build of kreatos-ide from vendor/ (no network).
#
# Needs only the RHEL9 toolchain: gcc, gcc-c++, make, cmake, python3,
# rust-toolset (cargo). The repo itself is never written to (it can be mounted
# read-only); intermediate files go to $KIDE_BUILD_DIR (default:
# $TMPDIR/kide-build).
#
# Result:
#   PREFIX/bin/nvim                   Neovim built from vendor/neovim
#   PREFIX/bin/kide                   launcher: nvim + the bundled config and tools
#   PREFIX/bin/lua-language-server    LSP server (wrapper), runtime tree in
#                                     PREFIX/lib/lua-language-server
#   PREFIX/bin/stylua                 formatter
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

for tool in cc c++ make cmake python3 cargo; do
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

# --- tools: LSP servers + formatters -----------------------------------------
TOOLS=$BUILD/tools
rm -rf "$TOOLS"
mkdir -p "$TOOLS/bin"
export PATH="$TOOLS/bin:$PATH"

# ninja is only a build helper (luamake drives it); RHEL ships it only in CRB
log "ninja (build helper, not installed)"
cp -a "$ROOT/vendor/tools/ninja" "$TOOLS/ninja"
(cd "$TOOLS/ninja" && python3 configure.py --bootstrap >/dev/null)
cp "$TOOLS/ninja/ninja" "$TOOLS/bin/ninja"

log "lua-language-server"
cp -a "$ROOT/vendor/tools/lua-language-server" "$TOOLS/luals"
# luamake links libstdc++ statically; RHEL ships libstdc++-static only in CRB,
# so link it dynamically (built on the target, the system libstdc++ is there)
python3 - "$TOOLS/luals" <<'PY'
import sys
root = sys.argv[1]
patches = {
    "make.lua": ('crt = "static"', 'crt = "dynamic"'),
    "3rd/bee.lua/compile/common.lua": ('crt = "static"', 'crt = "dynamic"'),
    "3rd/luamake/bee.lua/compile/common.lua": ('crt = "static"', 'crt = "dynamic"'),
    "3rd/luamake/compile/ninja/linux.ninja": ("-Wl,-Bstatic -lstdc++ -Wl,-Bdynamic", "-lstdc++"),
}
for rel, (old, new) in patches.items():
    path = f"{root}/{rel}"
    text = open(path).read()
    if old not in text:
        sys.exit(f"static libstdc++ patch: {old!r} not found in {rel}")
    open(path, "w").write(text.replace(old, new))
PY
(cd "$TOOLS/luals/3rd/luamake" && ./compile/build.sh)
(cd "$TOOLS/luals" && ./3rd/luamake/luamake rebuild)
LUALS=$PREFIX/lib/lua-language-server
rm -rf "$LUALS"
mkdir -p "$LUALS"
cp -a "$TOOLS/luals/"{bin,locale,meta,script,main.lua,debugger.lua} "$LUALS/"
cat >"$PREFIX/bin/lua-language-server" <<'WRAPPER'
#!/bin/sh
# logs and generated meta files go to the user's state dir, not the install tree
lib=$(dirname "$(readlink -f "$0")")/../lib/lua-language-server
state=${XDG_STATE_HOME:-$HOME/.local/state}/kreatos-ide/lua-language-server
mkdir -p "$state"
exec "$lib/bin/lua-language-server" --logpath="$state/log" --metapath="$state/meta" "$@"
WRAPPER
chmod +x "$PREFIX/bin/lua-language-server"

# cargo_build NAME [cargo args…] — offline build against vendor/crates/NAME
cargo_build() {
  local name=$1
  shift
  # sources may already be in place (patched copy)
  [[ -d $TOOLS/$name ]] || cp -a "$ROOT/vendor/tools/$name" "$TOOLS/$name"
  mkdir -p "$TOOLS/$name/.cargo"
  sed "s|@CRATES@|$ROOT/vendor/crates/$name|" "$ROOT/vendor/crates/$name.cargo-config.toml" \
    >"$TOOLS/$name/.cargo/config.toml"
  (cd "$TOOLS/$name" && CARGO_HOME="$TOOLS/cargo-home" cargo build --release --frozen "$@")
}

log "stylua"
# edition 2018 means feature resolver 1, which leaks the test-only assert_cmd's
# bstr/unicode feature into the build; those use pregenerated binary DFA
# tables (stripped). Resolver 2 keeps dev-dependency features out.
mkdir -p "$TOOLS/stylua"
cp -a "$ROOT/vendor/tools/stylua/." "$TOOLS/stylua/"
python3 - "$TOOLS/stylua/Cargo.toml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
if "resolver" in text or "[package]\n" not in text:
    sys.exit("stylua resolver patch: unexpected Cargo.toml")
open(path, "w").write(text.replace("[package]\n", '[package]\nresolver = "2"\n', 1))
PY
cargo_build stylua --all-features
install -m755 "$TOOLS/stylua/target/release/stylua" "$PREFIX/bin/stylua"

# --- launcher ----------------------------------------------------------------
log "launcher"
cat >"$PREFIX/bin/kide" <<'EOF'
#!/bin/sh
# kreatos-ide: the bundled nvim with the bundled config and tools. NVIM_APPNAME
# keeps its data/state/cache (~/.local/share/kreatos-ide, …) apart from any
# other nvim.
bin=$(dirname "$(readlink -f "$0")")
export NVIM_APPNAME=kreatos-ide
export PATH="$bin:$PATH"
exec "$bin/nvim" -u "$bin/../share/kreatos-ide/config/init.lua" "$@"
EOF
chmod +x "$PREFIX/bin/kide"

log "done: $PREFIX/bin/kide"
