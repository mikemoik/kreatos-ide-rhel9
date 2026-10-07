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
#   manifest/tools.tsv     name <TAB> kind <TAB> url <TAB> tag <TAB> packages
#                          (LSP servers, formatters, build helpers); for kind
#                          cargo, packages = the crates build.sh builds
#                          (comma-separated); needs `cargo`. A git tool
#                          with packages (not -) gets its crates vendored too
#   manifest/dist.tsv      upstream release tarballs kept as-is in dist/
#                          (cmake, onnxruntime, ACE+TAO, OpenDDS, RapidJSON),
#                          sha256-checked
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# everything is fetched into a staging dir; vendor/ is replaced only when the
# whole run succeeded
V=$ROOT/vendor.staging
D=$ROOT/dist.staging
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" "$V" "$D"' EXIT
rm -rf "$V" "$D"

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# fetch_tar URL DEST [SHA256] — download a tarball, verify, unpack into DEST
fetch_tar() {
  local url=$1 dest=$2 sha=${3:-} file="$TMP/dl"
  curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors "$url" -o "$file"
  if [[ -n $sha ]]; then
    echo "$sha  $file" | sha256sum -c --quiet - || { echo "sha256 mismatch: $url" >&2; exit 1; }
  fi
  rm -rf "$dest"
  mkdir -p "$dest"
  tar xzf "$file" -C "$dest" --strip-components=1
}

# go_vendor DIR — `go mod vendor` in DIR. Uses a local go if there is one,
# else RHEL's own Go in a UBI9 container (the same Go the target builds with).
go_vendor() {
  if command -v go >/dev/null; then
    (cd "$1" && GOFLAGS=-mod=mod GOTOOLCHAIN=local go mod vendor)
  else
    # run as the calling user: with a root docker daemon the files would
    # otherwise be root-owned on the host
    docker run --rm -v "$1:/w" -w /w --user "$(id -u):$(id -g)" \
      -e GOTOOLCHAIN=local -e HOME=/tmp -e GOPATH=/tmp/go -e GOCACHE=/tmp/gocache \
      "$(go_image)" go mod vendor
    # module files come out read-only; keep them deletable for the next run
    chmod -R u+w "$1/vendor"
  fi
}
go_image() {
  docker build -q -t kreatos-ide-rhel9-go - >/dev/null <<'EOF'
FROM registry.access.redhat.com/ubi9/ubi:latest
RUN dnf -y install golang && dnf clean all
EOF
  echo kreatos-ide-rhel9-go
}

# the syntax repos (submodules of yazi-prebuilt) yazi's code previews are
# highlighted with; official = Sublime Text's Packages (Python, C/C++, shell,
# Lua, JSON, YAML, Markdown, Makefile, HTML/JS/TS, Rust, Go, …)
YAZI_SYNTAXES=(official cmake toml docker)

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
  "$ROOT/manifest/parsers.txt" >"$TMP/parsers.lock.tsv"

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
done <"$TMP/parsers.lock.tsv"

# --- tools (LSP servers, formatters, build helpers) ----------------------------
# kind tarball: release tarball of a tag
# kind release: the release asset NAME-TAG.tar.gz of a github release (has a
#               generated configure, unlike the tag tarball)
# kind git:     shallow clone of a tag, branch or commit with all submodules
#               (their commits go to VERSIONS); a submodule whose upstream is
#               gone is skipped with a warning
# kind cargo:   tarball + `cargo vendor` of its locked crates into vendor/crates
# kind gomod:   tarball + `go mod vendor` (modules land in the tool's own vendor/)
# kind pypi:    the sdist of a PyPI release (url = https://pypi.org/project/NAME)
rm -rf "$V/tools" "$V/crates"
mkdir -p "$V/tools" "$V/crates"
while IFS=$'\t' read -r name kind url ref packages; do
  [[ -z $name || $name == \#* ]] && continue
  log "tool $name ($kind $ref)"
  dest=$V/tools/$name
  case $kind in
    tarball | cargo | gomod)
      fetch_tar "$url/archive/refs/tags/$ref.tar.gz" "$dest"
      record "tool/$name" "$url" "$ref"
      ;;
    release)
      fetch_tar "$url/releases/download/$ref/$name-$ref.tar.gz" "$dest"
      record "tool/$name" "$url" "$ref"
      ;;
    pypi)
      read -r sdist sha < <(curl -fsSL --retry 5 "https://pypi.org/pypi/${url##*/}/$ref/json" |
        python3 -c 'import json, sys
u = [u for u in json.load(sys.stdin)["urls"] if u["packagetype"] == "sdist"][0]
print(u["url"], u["digests"]["sha256"])')
      fetch_tar "$sdist" "$dest" "$sha"
      record "tool/$name" "$url" "$ref"
      ;;
    git)
      git init -q "$dest"
      git -C "$dest" fetch -q --depth 1 "$url" "$ref"
      git -C "$dest" -c advice.detachedHead=false checkout -q FETCH_HEAD
      record "tool/$name" "$url" "$ref"
      git -C "$dest" config -f .gitmodules --get-regexp '^submodule\..*\.path$' |
        while read -r _ path; do
          if [[ $name == yazi-prebuilt && " ${YAZI_SYNTAXES[*]} " != *" ${path#syntaxes/} "* ]]; then
            continue
          fi
          git -C "$dest" submodule -q update --init --recursive --depth 1 -- "$path" </dev/null 2>/dev/null ||
            echo "WARNING: $name: submodule $path not fetchable, skipped" >&2
        done
      git -C "$dest" submodule --quiet foreach --recursive \
        'printf "%s\t%s\t%s\n" "$displaypath" "$(git config --get remote.origin.url)" "$sha1"' \
        >"$TMP/submodules"
      find "$dest" -name .git -prune -exec rm -rf {} +
      # yazi's syntax set is compiled by build.sh from the .sublime-syntax
      # files alone (yazi-prebuilt's generate.rs); drop the repos' tests etc.
      if [[ $name == yazi-prebuilt ]]; then
        find "$dest/syntaxes" -type f ! -name '*.sublime-syntax' \
          ! -iregex '.*/\(licen[cs]e\|copying\|copyright\|unlicense\)\([-._][^/]*\)?' -delete
        find "$dest/syntaxes" -type d -empty -delete
        # repos with no .sublime-syntax at all (only .tmLanguage) add nothing
        for dir in "$dest/syntaxes"/*/; do
          [[ -n $(find "$dir" -name '*.sublime-syntax' -print -quit) ]] || rm -rf "$dir"
        done
      fi
      # submodules removed by that contribute nothing and are not recorded
      while IFS=$'\t' read -r path surl sha; do
        [[ -d $dest/$path ]] && record "tool/$name/$path" "$surl" "$sha"
      done <"$TMP/submodules"
      ;;
    *)
      echo "unknown tool kind: $kind" >&2
      exit 1
      ;;
  esac
  if [[ $kind == gomod ]]; then
    go_vendor "$dest"
    # Windows/Plan 9 parts of golang.org/x/sys are never compiled on Linux
    find "$dest/vendor/golang.org/x/sys" -mindepth 1 -maxdepth 1 -type d \
      \( -name windows -o -name plan9 \) -exec rm -rf {} + 2>/dev/null || true
    # "# <module> <version>" lines of modules.txt are the pins (from go.sum);
    # only modules with package lines below them were vendored (the others
    # are test-only or unused indirect requirements)
    awk '$1 == "#" && $2 !~ /^=>/ { mod = $2 " " $3; next }
         $1 !~ /^#/ && mod != "" { print mod; mod = "" }' "$dest/vendor/modules.txt" |
      while read -r mod ver; do record "gomod/$name/$mod" "https://$mod" "$ver"; done
  fi
  if [[ $kind == cargo || ($kind == git && $packages != -) ]]; then
    # the source replacement config cargo prints, with the crate dir as a
    # placeholder that build.sh fills in
    (cd "$dest" && cargo vendor --locked --versioned-dirs "$V/crates/$name" 2>/dev/null) |
      sed "s|$V/crates/$name|@CRATES@|" >"$V/crates/$name.cargo-config.toml"
    grep -q '@CRATES@' "$V/crates/$name.cargo-config.toml" || { echo "cargo vendor printed no config" >&2; exit 1; }
    # crates Linux never builds (windows-sys, web-sys, …) become manifest stubs
    # (and those only tests or other workspace members need)
    python3 "$ROOT/scripts/prune-crates.py" "$dest" "$V/crates/$name" ${packages//,/ } >"$TMP/stubbed"
    for crate in "$V/crates/$name"/*/; do # <crate>-<version>, pinned by Cargo.lock
      crate=$(basename "$crate")
      if grep -qx "$crate" "$TMP/stubbed"; then
        record "crate/$name/$crate" https://crates.io "Cargo.lock (stub: not built on Linux)"
      else
        record "crate/$name/$crate" https://crates.io Cargo.lock
      fi
    done
  fi
done <"$ROOT/manifest/tools.tsv"

# --- dist: release tarballs, kept as-is ----------------------------------------
# a tarball already in dist/ with the pinned sha256 is reused, not downloaded
mkdir -p "$D"
while IFS=$'\t' read -r name kind version file url sha; do
  [[ -z $name || $name == \#* ]] && continue
  if [[ -f $ROOT/dist/$file ]] && echo "$sha  $ROOT/dist/$file" | sha256sum -c --quiet - 2>/dev/null; then
    cp "$ROOT/dist/$file" "$D/$file"
  else
    log "dist $name $version"
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors "$url" -o "$D/$file"
    echo "$sha  $D/$file" | sha256sum -c --quiet - || { echo "sha256 mismatch: $url" >&2; exit 1; }
  fi
  record "dist/$name" "$url" "$version ($kind)"
done <"$ROOT/manifest/dist.tsv"

# --- strip + record ----------------------------------------------------------
log "stripping non-text files"
python3 "$ROOT/scripts/check-sources.py" --strip "$V"
sort "$TMP/versions" >"$ROOT/VERSIONS"
cp "$TMP/parsers.lock.tsv" "$ROOT/manifest/parsers.lock.tsv"
rm -rf "$ROOT/vendor" "$ROOT/dist"
mv "$V" "$ROOT/vendor"
mv "$D" "$ROOT/dist"
# upstream .gitignore files (fzf ignores its own vendor/) would keep vendored
# sources out of the commit; the build only sees them in this checkout
ignored=$(git -C "$ROOT" status --ignored --porcelain vendor | sed -n 's/^!! //p')
if [[ -n $ignored ]]; then
  printf 'git-ignored under vendor/ (git add -f them):\n%s\n' "$ignored" >&2
  exit 1
fi
log "third-party inventory (README.md)"
python3 "$ROOT/scripts/gen-inventory.py"
log "done — review 'git status', then commit"
