# kreatos-ide-rhel9

misw's kreatos Neovim setup, packaged to build **offline from source** on
RHEL9. Everything the build needs is in this repo; the build never touches the
network, and the repo holds no binaries (checked by `scripts/check-sources.py`).

## Build (on the RHEL9 box)

Toolchain, from the RHEL repos only:

    dnf install gcc gcc-c++ make cmake python3 rust-toolset git-core

Then:

    ./build.sh                 # installs into ~/.local/opt/kreatos-ide
    ./build.sh /opt/kide       # or any prefix
    ~/.local/opt/kreatos-ide/bin/kide

`kide` runs the bundled nvim with the bundled config, with the bundled LSP
servers and formatters (`PREFIX/bin`) first on `PATH`. Its data, state and
cache live under `NVIM_APPNAME=kreatos-ide` (`~/.local/share/kreatos-ide`, …),
so it never mixes with another nvim. The repo is only read; intermediate files
go to `$KIDE_BUILD_DIR` (default `/tmp/kide-build`, safe to delete afterwards).

## What is inside

| Path | Content |
|---|---|
| `vendor/neovim` | Neovim source (`manifest/neovim.txt`) |
| `vendor/neovim-deps` | its bundled deps as source trees (libuv, LuaJIT, luv, lpeg, unibilium, utf8proc, tree-sitter, bundled parsers), pinned + sha256-checked by Neovim's `cmake.deps/deps.txt` |
| `vendor/plugins` | the plugins, plain source at pinned commits (`manifest/plugins.tsv`) |
| `vendor/grammars` | treesitter grammar repos (`grammar.js` + generated `src/parser.c`) |
| `vendor/tools` | LSP servers, formatters, build helpers (`manifest/tools.tsv`): ninja, lua-language-server (with submodules), stylua |
| `vendor/crates` | the Rust crates of each cargo tool (`cargo vendor --locked`), plus the cargo source config |
| `config` | the nvim config (kreatos `home/nvim`, adapted, see below) |
| `manifest/` | the pins; `parsers.lock.tsv` is generated from `parsers.txt` |
| `VERSIONS` | every vendored component with upstream URL and commit/tag/sha256 |

Binary files in upstream sources (images, test archives, wasm, the
`nvim.png` desktop icon, Windows import libraries) are stripped at vendor
time; nothing the build or the editor needs is lost.

Rust crates that the built binaries never compile on Linux — Windows/macOS/wasm
crates, test-only dependencies, crates only other workspace members need — are
reduced to stubs (their `Cargo.toml` only, so cargo can still resolve the
lockfile; `scripts/prune-crates.py`). `VERSIONS` marks them.

Build-time adjustments (applied to the build copy, the vendored tree stays
untouched):

- lua-language-server links libstdc++ dynamically (upstream links it
  statically; `libstdc++-static` is only in RHEL's CRB repo).
- stylua is built with cargo's feature resolver 2, so its test-only
  dependencies don't switch on bstr's pregenerated (binary) Unicode tables.
- ninja (needed by lua-language-server's luamake) is built from source and
  used for the build only; RHEL ships it only in CRB.

## Differences from the kreatos config

- No `vim.pack`: plugins are installed by `build.sh` as opt packages and
  loaded with `packadd` in the same order.
- No claudecode.nvim (`<leader>a`), no jsonls / JSON schemas.
- blink.cmp uses its pure-Lua fuzzy matcher (the Rust one needs nightly Rust).
- Treesitter parsers are compiled by `build.sh`; nvim-treesitter never
  installs anything.
- LSP servers: `ty`, `ruff`, `lua_ls`. A server whose binary is missing is
  skipped.

## Status

| Step | Content | State |
|---|---|---|
| 1 | Neovim + plugins + parsers | done, passes in UBI9 offline |
| 2 | lua-language-server, stylua | done, passes in UBI9 offline |
| 3 | ruff + ty 0.15.11 (newest tag that builds with Rust 1.92) | open |
| 4 | shfmt, debugpy | open |

## Updating the pins (on a connected machine)

1. Edit `manifest/` (Neovim tag, plugin commits, parser list).
2. `scripts/vendor-update.sh` — the only step that downloads; needs curl, tar,
   sha256sum, git, cargo, Python >= 3.11 and an nvim to resolve the parser list.
3. `test/run.sh` — must pass before committing.
4. Review `git status` / `VERSIONS`, commit.

## Testing

`test/run.sh` builds a clean `registry.access.redhat.com/ubi9/ubi` image with
only the toolchain RPMs, then runs `build.sh` and `test/smoke.lua` in it with
`--network=none` and the repo mounted read-only. The smoke test checks: clean
startup, every plugin on the runtimepath, every parser loads and its
highlights query compiles, treesitter highlighting on Lua/Python/sh/TypeScript
files, each LSP server attaches to a small project and reports a diagnostic,
each formatter formats through conform, blink.cmp running with the Lua
matcher.
