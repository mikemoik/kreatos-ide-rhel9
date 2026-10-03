#!/usr/bin/env bash
# build.sh [PREFIX] — offline build of kreatos-ide from vendor/ (no network).
#
# Needs only the RHEL9 toolchain: gcc, make, cmake, python3, rust-toolset
# (cargo), golang. The repo itself is never written to (it can be mounted
# read-only); intermediate files go to $KIDE_BUILD_DIR (default:
# $TMPDIR/kide-build).
#
# Result:
#   PREFIX/bin/nvim                   Neovim built from vendor/neovim
#   PREFIX/bin/kide                   launcher: nvim + the bundled config and tools
#   PREFIX/bin/{ruff,ty}              Python linter/formatter + type checker (LSP)
#   PREFIX/bin/neocmakelsp            CMake LSP
#   PREFIX/bin/shfmt                  shell formatter
#   PREFIX/bin/kide-python            python3 with the bundled debugpy (nvim-dap)
#   PREFIX/lib/kreatos-ide/python     debugpy (pure Python)
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

for tool in cc make cmake python3 cargo go; do
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

# --- tools: LSP servers + formatters ------------------------------------------
TOOLS=$BUILD/tools
rm -rf "$TOOLS"
mkdir -p "$TOOLS"

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

log "ruff + ty"
# ruff_python_parser only uses bstr's plain byte-string methods; its default
# `unicode` feature would need pregenerated binary DFA tables (stripped).
# Without it bstr no longer depends on regex-automata, so that edge leaves
# Cargo.lock too (cargo 1.92 insists, newer cargo would not).
mkdir -p "$TOOLS/ruff"
cp -a "$ROOT/vendor/tools/ruff/." "$TOOLS/ruff/"
python3 - "$TOOLS/ruff" <<'PY'
import sys
root = sys.argv[1]
patches = {
    "Cargo.toml": (
        'bstr = { version = "1.9.1" }',
        'bstr = { version = "1.9.1", default-features = false, features = ["std"] }',
    ),
    "Cargo.lock": (
        'name = "bstr"\nversion = "1.12.1"\n'
        'source = "registry+https://github.com/rust-lang/crates.io-index"\n'
        'checksum = "63044e1ae8e69f3b5a92c736ca6269b8d12fa7efe39bf34ddb06d102cf0e2cab"\n'
        'dependencies = [\n "memchr",\n "regex-automata",\n "serde",\n]',
        'name = "bstr"\nversion = "1.12.1"\n'
        'source = "registry+https://github.com/rust-lang/crates.io-index"\n'
        'checksum = "63044e1ae8e69f3b5a92c736ca6269b8d12fa7efe39bf34ddb06d102cf0e2cab"\n'
        'dependencies = [\n "memchr",\n "serde",\n]',
    ),
}
for rel, (old, new) in patches.items():
    path = f"{root}/{rel}"
    text = open(path).read()
    if old not in text:
        sys.exit(f"ruff bstr patch: expected text not found in {rel}")
    open(path, "w").write(text.replace(old, new, 1))
PY
cargo_build ruff -p ruff -p ty
install -m755 "$TOOLS/ruff/target/release/ruff" "$TOOLS/ruff/target/release/ty" "$PREFIX/bin/"

log "neocmakelsp"
# v0.11.0: the newest release that really builds with Rust 1.92 (v0.11.1 uses
# `if let` guards despite declaring rust-version 1.89)
cargo_build neocmakelsp -p neocmakelsp
install -m755 "$TOOLS/neocmakelsp/target/release/neocmakelsp" "$PREFIX/bin/"

log "shfmt"
cp -a "$ROOT/vendor/tools/shfmt" "$TOOLS/shfmt"
(cd "$TOOLS/shfmt" && GOFLAGS=-mod=vendor GOTOOLCHAIN=local GOPROXY=off \
  GOCACHE="$TOOLS/gocache" GOPATH="$TOOLS/gopath" go build -trimpath -o "$PREFIX/bin/shfmt" ./cmd/shfmt)

# debugpy runs from its source tree (pure Python; the optional Cython
# speedups are not built). nvim-dap-python starts it via kide-python.
log "debugpy"
PYLIB=$PREFIX/lib/kreatos-ide/python
rm -rf "$PYLIB"
mkdir -p "$PYLIB"
cp -a "$ROOT/vendor/tools/debugpy/src/debugpy" "$PYLIB/"
cat >"$PREFIX/bin/kide-python" <<'WRAPPER'
#!/bin/sh
# python3 with the bundled debugpy importable
lib=$(dirname "$(readlink -f "$0")")/../lib/kreatos-ide/python
export PYTHONPATH="$lib${PYTHONPATH:+:$PYTHONPATH}"
exec python3 "$@"
WRAPPER
chmod +x "$PREFIX/bin/kide-python"

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
