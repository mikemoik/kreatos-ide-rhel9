# kreatos-ide-rhel9

misw's kreatos Neovim setup, packaged to build **offline from source** on
RHEL9. Everything the build needs is in this repo; the build never touches the
network, and the repo holds no binaries (checked by `scripts/check-sources.py`).

## Build (on the RHEL9 box)

Toolchain, from the RHEL repos only:

    dnf install gcc make cmake python3 git-core

Then:

    ./build.sh                 # installs into ~/.local/opt/kreatos-ide
    ./build.sh /opt/kide       # or any prefix
    ~/.local/opt/kreatos-ide/bin/kide

`kide` runs the bundled nvim with the bundled config. Its data, state and
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
| `config` | the nvim config (kreatos `home/nvim`, adapted, see below) |
| `manifest/` | the pins; `parsers.lock.tsv` is generated from `parsers.txt` |
| `VERSIONS` | every vendored component with upstream URL and commit/tag/sha256 |

Binary files in upstream sources (images, test archives, wasm, the
`nvim.png` desktop icon) are stripped at vendor time; nothing the build or the
editor needs is lost.

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
| 2 | lua-language-server, stylua | open |
| 3 | ruff + ty (newest tag that builds with Rust 1.92) | open |
| 4 | shfmt, debugpy | open |

## Updating the pins (on a connected machine)

1. Edit `manifest/` (Neovim tag, plugin commits, parser list).
2. `scripts/vendor-update.sh` — the only step that downloads; needs curl, tar,
   sha256sum, python3 and an nvim to resolve the parser list.
3. `test/run.sh` — must pass before committing.
4. Review `git status` / `VERSIONS`, commit.

## Testing

`test/run.sh` builds a clean `registry.access.redhat.com/ubi9/ubi` image with
only the toolchain RPMs, then runs `build.sh` and `test/smoke.lua` in it with
`--network=none` and the repo mounted read-only. The smoke test checks: clean
startup, every plugin on the runtimepath, every parser loads and its
highlights query compiles, treesitter highlighting on Lua/Python/sh/TypeScript
files, blink.cmp running with the Lua matcher.
