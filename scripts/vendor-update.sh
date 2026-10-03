#!/usr/bin/env bash
# vendor-update.sh — the ONLY step that touches the network.
#
# Re-fetches every pinned source listed in manifest/ into vendor/, strips
# non-text files, and writes VERSIONS. Run it deliberately (on a connected
# machine with curl, tar, sha256sum, python3 and nvim), review the diff,
# commit. build.sh never downloads anything.
#
#   manifest/neovim.txt    Neovim release tag; its cmake.deps/deps.txt pins the deps
#   manifest/plugins.tsv   name <TAB> url <TAB> commit
#   manifest/parsers.txt   treesitter languages; url/commit come from the
#                          vendored nvim-treesitter's parsers.lua
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
V=$ROOT/vendor
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# fetch_tar URL DEST [SHA256] — download a tarball, verify, unpack into DEST
fetch_tar() {
  local url=$1 dest=$2 sha=${3:-} file="$TMP/dl"
  curl -fsSL --retry 3 "$url" -o "$file"
  if [[ -n $sha ]]; then
    echo "$sha  $file" | sha256sum -c --quiet - || { echo "sha256 mismatch: $url" >&2; exit 1; }
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  tar xzf "$file" -C "$dest" --strip-components=1
}

# github_archive URL COMMIT — tarball URL for a commit of a github repo
github_archive() { echo "${1%.git}/archive/$2.tar.gz"; }

: >"$TMP/versions"
record() { printf '%-28s %-60s %s\n' "$1" "$2" "$3" >>"$TMP/versions"; }

# --- Neovim + bundled deps ---------------------------------------------------
nvim_tag=$(<"$ROOT/manifest/neovim.txt")
log "neovim $nvim_tag"
fetch_tar "https://github.com/neovim/neovim/archive/refs/tags/$nvim_tag.tar.gz" "$V/neovim"
record neovim https://github.com/neovim/neovim "$nvim_tag"

# deps the Linux build uses (see cmake.deps/CMakeLists.txt); the rest are for
# Windows/macOS (win32yank, gettext, libiconv), optional (wasmtime) or dev
# tools (uncrustify, PUC lua for tests)
deps=(LIBUV LUAJIT UNIBILIUM LUV LUA_COMPAT53 LPEG UTF8PROC TREESITTER
  TREESITTER_C TREESITTER_LUA TREESITTER_VIM TREESITTER_VIMDOC TREESITTER_QUERY TREESITTER_MARKDOWN)
rm -rf "$V/neovim-deps"
for dep in "${deps[@]}"; do
  url=$(awk -v k="${dep}_URL" '$1 == k { print $2 }' "$V/neovim/cmake.deps/deps.txt")
  sha=$(awk -v k="${dep}_SHA256" '$1 == k { print $2 }' "$V/neovim/cmake.deps/deps.txt")
  name=${dep,,} # ExternalProject name = source dir name under .deps/build/src
  log "neovim dep $name"
  fetch_tar "$url" "$V/neovim-deps/$name" "$sha"
  record "neovim-dep/$name" "$url" "sha256:$sha"
done

# --- plugins -----------------------------------------------------------------
rm -rf "$V/plugins"
while IFS=$'\t' read -r name url rev; do
  [[ -z $name || $name == \#* ]] && continue
  log "plugin $name"
  fetch_tar "$(github_archive "$url" "$rev")" "$V/plugins/$name"
  record "plugin/$name" "$url" "$rev"
done <"$ROOT/manifest/plugins.tsv"

# --- treesitter grammars -----------------------------------------------------
# resolve the languages + their `requires` against the vendored parsers.lua
log "resolving parsers"
nvim --clean -l "$ROOT/scripts/resolve-parsers.lua" \
  "$V/plugins/nvim-treesitter/lua/nvim-treesitter/parsers.lua" \
  "$ROOT/manifest/parsers.txt" >"$ROOT/manifest/parsers.lock.tsv"

rm -rf "$V/grammars"
# lang url rev location; several langs can share one repo (typescript/tsx, …)
while IFS=$'\t' read -r lang url rev _location; do
  [[ $url == - ]] && continue # query-only language (ecma, jsx, html_tags)
  repo=$(basename "${url%.git}")
  if [[ ! -d $V/grammars/$repo ]]; then
    log "grammar $repo"
    fetch_tar "$(github_archive "$url" "$rev")" "$V/grammars/$repo"
    record "grammar/$repo" "$url" "$rev"
  fi
done <"$ROOT/manifest/parsers.lock.tsv"

# --- strip + record ----------------------------------------------------------
log "stripping non-text files"
python3 "$ROOT/scripts/check-sources.py" --strip "$V"
sort "$TMP/versions" >"$ROOT/VERSIONS"
log "done — review 'git status', then commit"
