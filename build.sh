#!/usr/bin/env bash
# build.sh [--no-build] [PREFIX] — offline build of kreatos-ide from vendor/
# (no network).
#
# --no-build: refresh an existing install's plugins, nvim + yazi config,
# launcher and bashrc only; nvim, the parsers and the tools are not rebuilt.
#
# Needs only the RHEL9 toolchain: gcc, make, cmake, python3, rust-toolset
# (cargo), golang, libevent-devel + ncurses-devel (tmux), and perl,
# perl-Dumpvalue + bzip2 (ACE+TAO/OpenDDS). The repo itself is never written to (it can be mounted
# read-only); intermediate files go to $KIDE_BUILD_DIR (default:
# $TMPDIR/kide-build).
#
# Result:
#   PREFIX/bin/nvim                   Neovim built from vendor/neovim
#   PREFIX/bin/kide                   launcher: nvim + the bundled config and tools
#   PREFIX/bin/{ruff,ty}              Python linter/formatter + type checker (LSP)
#   PREFIX/bin/neocmakelsp            CMake LSP
#   PREFIX/bin/shfmt                  shell formatter
#   PREFIX/bin/{fd,fzf,lazygit}       file finder, fuzzy finder, git TUI
#   PREFIX/bin/{yazi,ya}              file manager + its CLI
#   PREFIX/bin/fish                   fish shell (the container's shell; its
#                                     functions and completions are built in),
#                                     + fish_indent, fish_key_reader links
#   PREFIX/bin/tmux                   terminal multiplexer (fish's `tm`)
#   PREFIX/bin/kide-python            python3 with the bundled debugpy (nvim-dap)
#   PREFIX/bin/{cmake,ctest,cpack}    CMake 4 (upstream's prebuilt, dist/),
#                                     ahead of RHEL's cmake on PATH
#   PREFIX/{include,lib64}            onnxruntime (upstream's prebuilt, dist/):
#                                     find_package(onnxruntime), pkg-config
#   PREFIX/{bin,include,lib,share}    ACE+TAO 8 + OpenDDS 3.34 built from dist/
#                                     (ACE+TAO complete: all of TAO + orbsvcs
#                                     services, tao_idl, opendds_idl; find_package(OpenDDS))
#   PREFIX/lib/kreatos-ide/python     debugpy (pure Python)
#   PREFIX/share/kreatos-ide/config   config/ (init.lua, lua/misw, …)
#   PREFIX/share/kreatos-ide/yazi     yazi/ (yazi.toml: text opens in kide)
#   PREFIX/share/kreatos-ide/fish     fish/ (config.fish + aliases: the IDE's
#                                     shell helpers)
#   PREFIX/share/kreatos-ide/site     pack/vendor/opt plugins, parser/, queries/
#   PREFIX/bashrc                     puts PREFIX/bin first on PATH, points
#                                     YAZI_CONFIG_HOME at the yazi config; sourced by
#                                     one line in ~/.bashrc (the only change
#                                     outside PREFIX)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
NO_BUILD=0
args=()
for arg in "$@"; do
  if [[ $arg == --no-build ]]; then NO_BUILD=1; else args+=("$arg"); fi
done
PREFIX=$(realpath -m "${args[0]:-$HOME/.local/kreatos-ide}")
BUILD=$(realpath -m "${KIDE_BUILD_DIR:-${TMPDIR:-/tmp}/kide-build}")
JOBS=${JOBS:-$(nproc)}
SHARE=$PREFIX/share/kreatos-ide
SITE=$SHARE/site
# the build uses RHEL's cmake, not PREFIX/bin/cmake from an earlier install
PATH=$(tr : '\n' <<<"$PATH" | grep -vxF "$PREFIX/bin" | paste -sd:)

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

log "checking sources (no binaries)"
python3 "$ROOT/scripts/check-sources.py" "$ROOT/vendor" "$ROOT/config" "$ROOT/yazi" "$ROOT/fish"

if ((NO_BUILD)) && [[ ! -x $PREFIX/bin/nvim ]]; then
  echo "--no-build: no kide install in $PREFIX (run without --no-build first)" >&2
  exit 1
fi

# --- binaries: nvim, parsers, tools (skipped with --no-build) ------------------
# (not indented: the heredocs below must stay at column 0)
if ((!NO_BUILD)); then

for tool in cc make cmake python3 cargo go perl bzip2; do
  command -v "$tool" >/dev/null || { echo "missing build tool: $tool" >&2; exit 1; }
done

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
chmod -R u+w "$TOOLS" 2>/dev/null || true # Go leaves its module cache read-only
rm -rf "$TOOLS"
mkdir -p "$TOOLS"

# cargo_build NAME [cargo args…] — offline build against vendor/crates/NAME
# (or $CRATES, a patched copy of it)
cargo_build() {
  local name=$1 crates=${CRATES:-$ROOT/vendor/crates/$1}
  shift
  # sources may already be in place (patched copy)
  [[ -d $TOOLS/$name ]] || cp -a "$ROOT/vendor/tools/$name" "$TOOLS/$name"
  mkdir -p "$TOOLS/$name/.cargo"
  sed "s|@CRATES@|$crates|" "$ROOT/vendor/crates/$name.cargo-config.toml" \
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

# go_build NAME OUT PKG [go build args…] — offline build against the tool's vendor/
go_build() {
  local name=$1 out=$2 pkg=$3
  shift 3
  cp -a "$ROOT/vendor/tools/$name" "$TOOLS/$name"
  (cd "$TOOLS/$name" && GOFLAGS='-mod=vendor -modcacherw' GOTOOLCHAIN=local GOPROXY=off \
    GOCACHE="$TOOLS/gocache" GOPATH="$TOOLS/gopath" go build -trimpath "$@" -o "$out" "$pkg")
}

log "shfmt"
go_build shfmt "$PREFIX/bin/shfmt" ./cmd/shfmt

log "fd"
cargo_build fd -p fd-find
install -m755 "$TOOLS/fd/target/release/fd" "$PREFIX/bin/"

log "fzf"
go_build fzf "$PREFIX/bin/fzf" . -ldflags "-X main.version=$(awk '$1 == "fzf" { print substr($4, 2) }' "$ROOT/manifest/tools.tsv") -X main.revision=kide"

log "lazygit"
go_build lazygit "$PREFIX/bin/lazygit" . -ldflags "-X main.version=$(awk '$1 == "lazygit" { print substr($4, 2) }' "$ROOT/manifest/tools.tsv") -X main.buildSource=kide"

log "fish"
# without the default features: embed-manpages needs Sphinx, localize-messages
# needs msgfmt (gettext). Functions and completions (share/) are embedded in
# the binary either way; builtins' --help has no man page to show. One
# multicall binary: fish_indent and fish_key_reader are links to it.
cargo_build fish -p fish --no-default-features --bin fish
install -m755 "$TOOLS/fish/target/release/fish" "$PREFIX/bin/"
ln -sf fish "$PREFIX/bin/fish_indent"
ln -sf fish "$PREFIX/bin/fish_key_reader"

log "tmux"
# the release tarball (manifest kind release) has a generated configure and
# cmd-parse.c, so no autotools or yacc are needed (RHEL/UBI have no yacc):
# - configure still insists on finding one; YACC=true satisfies the check
# - git keeps no mtimes, so cmd-parse.y or configure.ac can look newer than
#   what was generated from them; one mtime for all files stops make from
#   regenerating them
# Links RHEL's libevent and ncurses (libtinfo).
cp -a "$ROOT/vendor/tools/tmux" "$TOOLS/tmux"
find "$TOOLS/tmux" -exec touch -h -d @1700000000 {} +
(cd "$TOOLS/tmux" && ./configure YACC=true --prefix="$PREFIX" >configure.log && make -j "$JOBS" >make.log) ||
  { tail -30 "$TOOLS/tmux/configure.log" "$TOOLS/tmux/make.log" 2>/dev/null; exit 1; }
install -m755 "$TOOLS/tmux/tmux" "$PREFIX/bin/"

# yazi needs two binary inputs that the source-only rule strips:
# - yazi-prebuilt's built/syntaxes, the compiled syntax set for code previews:
#   rebuilt here with yazi-prebuilt's own generator from the .sublime-syntax
#   files in vendor/tools/yazi-prebuilt/syntaxes
# - four DER templates ring (SFTP via russh) includes, 13–41 bytes each:
#   written from the hex below (the PKCS#8 headers for Ed25519, P-256, P-384
#   and the rsaEncryption AlgorithmIdentifier, as in ring 0.17.14)
# Both go into a copy of the crate dir; the other crates are symlinked.
log "yazi: syntax set"
cp -a "$ROOT/vendor/tools/yazi-prebuilt" "$TOOLS/yazi-prebuilt"
: >"$TOOLS/yazi-prebuilt/built/syntaxes" # lib.rs includes it; the generator does not use it
# syntect's defaults embed its own prebuilt dumps (default-syntaxes,
# default-themes; stripped, and unused by the generator; no crates of their own)
sed -i 's|^syntect = { version = "^5", optional = true }$|syntect = { version = "^5", optional = true, default-features = false, features = ["parsing", "html", "plist-load", "yaml-load", "dump-load", "dump-create", "regex-onig"] }|' \
  "$TOOLS/yazi-prebuilt/Cargo.toml"
grep -q 'default-features = false' "$TOOLS/yazi-prebuilt/Cargo.toml" || { echo "yazi-prebuilt: syntect line not found" >&2; exit 1; }
# yazi 26.1.22 loads the set with from_uncompressed_data; generate.rs at the
# pinned commit still writes it compressed (dump_to_file)
sed -i 's/dump_to_file/dump_to_uncompressed_file/g' "$TOOLS/yazi-prebuilt/generate.rs"
grep -q 'dump_to_uncompressed_file(' "$TOOLS/yazi-prebuilt/generate.rs" || { echo "yazi-prebuilt: dump_to_file not found" >&2; exit 1; }
cargo_build yazi-prebuilt --features build_deps --bin generate
# Sublime syntaxes newer than syntect supports are skipped (as upstream)
(cd "$TOOLS/yazi-prebuilt" && ./target/release/generate >generate.log)
skipped=$(grep -c '^Failed to load syntax' "$TOOLS/yazi-prebuilt/generate.log" || true)
echo "  syntax set built; $skipped syntaxes skipped (too new for syntect: HTML, TypeScript, PHP, embeddings)"
yazi_crates=$TOOLS/yazi-crates
mkdir -p "$yazi_crates"
for crate in "$ROOT/vendor/crates/yazi"/*/; do ln -s "$crate" "$yazi_crates/$(basename "$crate")"; done
prebuilt=$(cd "$ROOT/vendor/crates/yazi" && echo yazi-prebuilt-*)
ring=$(cd "$ROOT/vendor/crates/yazi" && echo ring-0.17.*)
for crate in "$prebuilt" "$ring"; do
  rm "$yazi_crates/$crate"
  cp -a "$ROOT/vendor/crates/yazi/$crate" "$yazi_crates/$crate"
done
cp "$TOOLS/yazi-prebuilt/built/syntaxes" "$yazi_crates/$prebuilt/built/syntaxes"
while read -r file hex; do
  mkdir -p "$(dirname "$yazi_crates/$ring/$file")" # src/data held only the stripped file
  printf "$(sed 's/../\\x&/g' <<<"$hex")" >"$yazi_crates/$ring/$file"
done <<'EOF'
src/ec/curve25519/ed25519/ed25519_pkcs8_v2_template.der 3051020101300506032b657004220420812100
src/ec/suite_b/ecdsa/ecPublicKey_p256_pkcs8_v1_template.der 308187020100301306072a8648ce3d020106082a8648ce3d030107046d306b0201010420a144034200
src/ec/suite_b/ecdsa/ecPublicKey_p384_pkcs8_v1_template.der 3081b6020100301006072a8648ce3d020106052b8104002204819e30819b0201010430a164036200
src/data/alg-rsa-encryption.der 06092a864886f70d0101010500
EOF

log "yazi"
CRATES=$yazi_crates cargo_build yazi -p yazi-fm -p yazi-cli
install -m755 "$TOOLS/yazi/target/release/yazi" "$TOOLS/yazi/target/release/ya" "$PREFIX/bin/"

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

# --- C/C++ libraries from dist/: cmake, onnxruntime, ACE+TAO + OpenDDS -------
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

fi # binaries

# --- plugins + config ----------------------------------------------------------
log "plugins"
rm -rf "$SITE/pack"
mkdir -p "$SITE/pack/vendor/opt"
cp -a "$ROOT/vendor/plugins/." "$SITE/pack/vendor/opt/"

log "config"
rm -rf "$SHARE/config" "$SHARE/yazi" "$SHARE/fish"
cp -a "$ROOT/config" "$SHARE/config"
cp -a "$ROOT/yazi" "$SHARE/yazi"
cp -a "$ROOT/fish" "$SHARE/fish"

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

# --- PATH --------------------------------------------------------------------
# PREFIX/bashrc puts PREFIX/bin at the front of PATH; the only change outside
# PREFIX is one line in ~/.bashrc sourcing it (added once)
log "PATH: $PREFIX/bin first ($PREFIX/bashrc, sourced from ~/.bashrc)"
cat >"$PREFIX/bashrc" <<EOF
# kreatos-ide (written by build.sh): its executables come first
case "\$PATH" in
  "$PREFIX/bin:"*) ;;
  *) PATH="$PREFIX/bin:\$PATH" ;;
esac
export PATH
# yazi with the bundled config (text files open in kide), not ~/.config/yazi
export YAZI_CONFIG_HOME="$SHARE/yazi"
EOF
source_line="[ -f '$PREFIX/bashrc' ] && . '$PREFIX/bashrc'  # kreatos-ide"
grep -qxF "$source_line" "$HOME/.bashrc" 2>/dev/null || printf '%s\n' "$source_line" >>"$HOME/.bashrc"

log "done: $PREFIX/bin/kide — open a new shell, then run: kide"
