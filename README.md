# kreatos-ide-rhel9

misw's kreatos Neovim setup, packaged to build **offline from source** on
RHEL9. Everything the build needs is in this repo; the build never touches the
network, and the repo holds no binaries (checked by `scripts/check-sources.py`).

## Build (on the RHEL9 box)

Toolchain, from the RHEL repos only:

    dnf install gcc make cmake python3 rust-toolset git-core

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
| `vendor/tools` | LSP servers and formatters (`manifest/tools.tsv`): ruff + ty |
| `vendor/crates` | the Rust crates of each cargo tool (`cargo vendor --locked`), plus the cargo source config |
| `config` | the nvim config (kreatos `home/nvim`, adapted, see below) |
| `manifest/` | the pins; `parsers.lock.tsv` is generated from `parsers.txt`; `licenses.tsv` holds license facts the inventory cannot detect |
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

- ruff/ty: bstr's `unicode` feature is switched off (ruff only uses its plain
  byte-string methods; the feature needs pregenerated binary DFA tables), and
  the matching `regex-automata` edge is dropped from Cargo.lock.

Why the Rust crates are vendored: ruff and ty are Rust programs, and
cargo normally downloads their library crates from crates.io at build time.
RHEL ships the Rust toolchain but no crates (no `rust-*-devel` packages, not
even in CRB), so every crate the build needs is in `vendor/crates` as source.

## Differences from the kreatos config

- No `vim.pack`: plugins are installed by `build.sh` as opt packages and
  loaded with `packadd` in the same order.
- No claudecode.nvim (`<leader>a`), no jsonls / JSON schemas.
- blink.cmp uses its pure-Lua fuzzy matcher (the Rust one needs nightly Rust).
- Treesitter parsers are compiled by `build.sh`; nvim-treesitter never
  installs anything.
- LSP servers: `ty`, `ruff` (no `lua_ls`); no Lua formatter (no stylua).
  Lua files still get treesitter highlighting, indent and folds. A server
  whose binary is missing is skipped.

## Status

| Step | Content | State |
|---|---|---|
| 1 | Neovim + plugins + parsers | done, passes in UBI9 offline |
| 2 | lua-language-server, stylua | built and tested, then dropped: no Lua development on the target |
| 3 | ruff + ty 0.15.11 (newest tag that builds with Rust 1.92) | done, passes in UBI9 offline |
| 4 | shfmt, debugpy | open |

## Updating the pins (on a connected machine)

1. Edit `manifest/` (Neovim tag, plugin commits, parser list).
2. `scripts/vendor-update.sh` — the only step that downloads; needs curl, tar,
   sha256sum, git, cargo, Python >= 3.11 and an nvim to resolve the parser list.
3. `test/run.sh` — must pass before committing.
4. Review `git status` / `VERSIONS` and the regenerated "Third-party
   software" section below (a new component with an unrecognised license
   stops the vendor run until it is added to `manifest/licenses.tsv`), commit.

## Testing

`test/run.sh` builds a clean `registry.access.redhat.com/ubi9/ubi` image with
only the toolchain RPMs, then runs `build.sh` and `test/smoke.lua` in it with
`--network=none` and the repo mounted read-only. The smoke test checks: clean
startup, every plugin on the runtimepath, every parser loads and its
highlights query compiles, treesitter highlighting on Lua/Python/sh/TypeScript
files, each LSP server attaches to a small project and reports a diagnostic,
each formatter formats through conform, blink.cmp running with the Lua
matcher.

<!-- inventory:start -->

## Third-party software

Everything vendored in this repo, with the pinned upstream version and its
license. Generated from `VERSIONS` by `scripts/gen-inventory.py` (run by
`scripts/vendor-update.sh`); do not edit by hand.

| Component | Upstream | Version / commit | License |
|---|---|---|---|
| grammar/tree-sitter-bash | <https://github.com/tree-sitter/tree-sitter-bash> | `a06c2e4415e9` | MIT |
| grammar/tree-sitter-c | <https://github.com/tree-sitter/tree-sitter-c> | `ae19b676b13b` | MIT |
| grammar/tree-sitter-diff | <https://github.com/tree-sitter-grammars/tree-sitter-diff> | `2520c3f934b3` | MIT |
| grammar/tree-sitter-html | <https://github.com/tree-sitter/tree-sitter-html> | `73a3947324f6` | MIT |
| grammar/tree-sitter-javascript | <https://github.com/tree-sitter/tree-sitter-javascript> | `58404d8cf191` | MIT |
| grammar/tree-sitter-jsdoc | <https://github.com/tree-sitter/tree-sitter-jsdoc> | `658d18dcdddb` | MIT |
| grammar/tree-sitter-json | <https://github.com/tree-sitter/tree-sitter-json> | `001c28d7a298` | MIT |
| grammar/tree-sitter-luadoc | <https://github.com/tree-sitter-grammars/tree-sitter-luadoc> | `873612aadd3f` | MIT |
| grammar/tree-sitter-lua | <https://github.com/tree-sitter-grammars/tree-sitter-lua> | `e40f5b6e6df9` | MIT |
| grammar/tree-sitter-luap | <https://github.com/tree-sitter-grammars/tree-sitter-luap> | `c134aaec6acf` | MIT |
| grammar/tree-sitter-markdown | <https://github.com/tree-sitter-grammars/tree-sitter-markdown> | `da063e1ba430` | MIT |
| grammar/tree-sitter-printf | <https://github.com/tree-sitter-grammars/tree-sitter-printf> | `ec4e5674573d` | ISC |
| grammar/tree-sitter-python | <https://github.com/tree-sitter/tree-sitter-python> | `v0.25.0` | MIT |
| grammar/tree-sitter-query | <https://github.com/tree-sitter-grammars/tree-sitter-query> | `6350ad724e7b` | Apache-2.0 |
| grammar/tree-sitter-regex | <https://github.com/tree-sitter/tree-sitter-regex> | `b2ac15e27fce` | MIT |
| grammar/tree-sitter-toml | <https://github.com/tree-sitter-grammars/tree-sitter-toml> | `64b56832c2cf` | MIT |
| grammar/tree-sitter-typescript | <https://github.com/tree-sitter/tree-sitter-typescript> | `75b3874edb2d` | MIT |
| grammar/tree-sitter-vimdoc | <https://github.com/neovim/tree-sitter-vimdoc> | `f061895a0eff` | Apache-2.0 |
| grammar/tree-sitter-vim | <https://github.com/tree-sitter-grammars/tree-sitter-vim> | `1cd0a0892b38` | MIT |
| grammar/tree-sitter-xml | <https://github.com/tree-sitter-grammars/tree-sitter-xml> | `5000ae8f22d1` | MIT |
| grammar/tree-sitter-yaml | <https://github.com/tree-sitter-grammars/tree-sitter-yaml> | `7708026449be` | MIT |
| neovim-dep/libuv | <https://github.com/libuv/libuv/archive/v1.52.1.tar.gz> | `tarball, sha256:478baf2599bf…` | MIT AND CC-BY-4.0 |
| neovim-dep/lpeg | <https://github.com/neovim/deps/raw/d495ee6f79e7962a53ad79670cb92488abe0b9b4/opt/lpeg-1.1.0.tar.gz> | `tarball, sha256:4b155d67d224…` | MIT |
| neovim-dep/lua_compat53 | <https://github.com/lunarmodules/lua-compat-5.3/archive/v0.13.tar.gz> | `tarball, sha256:f5dc30e7b1fd…` | MIT |
| neovim-dep/luajit | <https://github.com/luajit/luajit/archive/fbb36bb6bfa88716a47c58bcf9ce9f2ef752abac.tar.gz> | `tarball, sha256:e60cd2f3057a…` | MIT |
| neovim-dep/luv | <https://github.com/luvit/luv/archive/1.52.1-0.tar.gz> | `tarball, sha256:e8b8774b31d2…` | Apache-2.0 |
| neovim-dep/treesitter_c | <https://github.com/tree-sitter/tree-sitter-c/archive/v0.24.1.tar.gz> | `tarball, sha256:25dd4bb3dec7…` | MIT |
| neovim-dep/treesitter | <https://github.com/tree-sitter/tree-sitter/archive/v0.26.13.tar.gz> | `tarball, sha256:ece24c3c5e2a…` | MIT |
| neovim-dep/treesitter_lua | <https://github.com/tree-sitter-grammars/tree-sitter-lua/archive/v0.5.0.tar.gz> | `tarball, sha256:cf01b93f4b61…` | MIT |
| neovim-dep/treesitter_markdown | <https://github.com/tree-sitter-grammars/tree-sitter-markdown/archive/v0.5.3.tar.gz> | `tarball, sha256:df845b1ab7c7…` | MIT |
| neovim-dep/treesitter_query | <https://github.com/tree-sitter-grammars/tree-sitter-query/archive/v0.8.0.tar.gz> | `tarball, sha256:c2b23b9a54cf…` | Apache-2.0 |
| neovim-dep/treesitter_vimdoc | <https://github.com/neovim/tree-sitter-vimdoc/archive/v4.1.0.tar.gz> | `tarball, sha256:020e8f117f64…` | Apache-2.0 |
| neovim-dep/treesitter_vim | <https://github.com/tree-sitter-grammars/tree-sitter-vim/archive/v0.8.1.tar.gz> | `tarball, sha256:93cafb9a0269…` | MIT |
| neovim-dep/unibilium | <https://github.com/neovim/unibilium/archive/v2.1.2.tar.gz> | `tarball, sha256:370ecb07fbbc…` | LGPL-3.0 |
| neovim-dep/utf8proc | <https://github.com/juliastrings/utf8proc/archive/v2.11.3.tar.gz> | `tarball, sha256:abfed50b6d4d…` | MIT |
| neovim | <https://github.com/neovim/neovim> | `v0.12.5` | Apache-2.0 AND Vim |
| plugin/blink.cmp | <https://github.com/saghen/blink.cmp> | `b19413d21406` | MIT |
| plugin/bufferline.nvim | <https://github.com/akinsho/bufferline.nvim> | `655133c3b4c3` | GPL-3.0 |
| plugin/conform.nvim | <https://github.com/stevearc/conform.nvim> | `c2526f1cde52` | MIT |
| plugin/ethereal.nvim | <https://github.com/bjarneo/ethereal.nvim> | `a0ec73332e53` | MIT |
| plugin/flash.nvim | <https://github.com/folke/flash.nvim> | `fcea7ff88323` | Apache-2.0 |
| plugin/friendly-snippets | <https://github.com/rafamadriz/friendly-snippets> | `6cd7280adead` | MIT |
| plugin/gitsigns.nvim | <https://github.com/lewis6991/gitsigns.nvim> | `abf82a65f185` | MIT |
| plugin/grug-far.nvim | <https://github.com/MagicDuck/grug-far.nvim> | `1f7a722a9b9f` | MIT |
| plugin/lazydev.nvim | <https://github.com/folke/lazydev.nvim> | `5231c62aa83c` | Apache-2.0 |
| plugin/lualine.nvim | <https://github.com/nvim-lualine/lualine.nvim> | `47f91c416dae` | MIT |
| plugin/mini.ai | <https://github.com/nvim-mini/mini.ai> | `9eae720f2b20` | MIT |
| plugin/mini.icons | <https://github.com/nvim-mini/mini.icons> | `efc85e42262c` | MIT |
| plugin/mini.pairs | <https://github.com/nvim-mini/mini.pairs> | `4089aa6ea642` | MIT |
| plugin/neo-tree.nvim | <https://github.com/nvim-neo-tree/neo-tree.nvim> | `1bd82358e516` | MIT |
| plugin/noice.nvim | <https://github.com/folke/noice.nvim> | `7bfd942445fb` | Apache-2.0 |
| plugin/nui.nvim | <https://github.com/MunifTanjim/nui.nvim> | `de740991c124` | MIT |
| plugin/nvim-dap | <https://github.com/mfussenegger/nvim-dap> | `085386b9359d` | GPL-3.0 |
| plugin/nvim-dap-python | <https://github.com/mfussenegger/nvim-dap-python> | `1808458eba2b` | GPL-3.0 |
| plugin/nvim-dap-ui | <https://github.com/rcarriga/nvim-dap-ui> | `cf91d5e2d07c` | MIT |
| plugin/nvim-dap-virtual-text | <https://github.com/theHamsta/nvim-dap-virtual-text> | `fbdb48c2ed45` | GPL-3.0 |
| plugin/nvim-lspconfig | <https://github.com/neovim/nvim-lspconfig> | `ff9c0af8f9b2` | Apache-2.0 |
| plugin/nvim-nio | <https://github.com/nvim-neotest/nvim-nio> | `21f5324bfac1` | MIT |
| plugin/nvim-treesitter | <https://github.com/nvim-treesitter/nvim-treesitter> | `f8bbc3177d92` | Apache-2.0 |
| plugin/nvim-treesitter-textobjects | <https://github.com/nvim-treesitter/nvim-treesitter-textobjects> | `52bda74e0870` | Apache-2.0 |
| plugin/persistence.nvim | <https://github.com/folke/persistence.nvim> | `b20b2a7887bd` | Apache-2.0 |
| plugin/plenary.nvim | <https://github.com/nvim-lua/plenary.nvim> | `b9fd5226c2f7` | MIT |
| plugin/snacks.nvim | <https://github.com/folke/snacks.nvim> | `fe7cfe9800a1` | Apache-2.0 |
| plugin/todo-comments.nvim | <https://github.com/folke/todo-comments.nvim> | `31e3c38ce9b2` | Apache-2.0 |
| plugin/trouble.nvim | <https://github.com/folke/trouble.nvim> | `bd67efe408d4` | Apache-2.0 |
| plugin/which-key.nvim | <https://github.com/folke/which-key.nvim> | `3aab2147e748` | Apache-2.0 |
| tool/ruff | <https://github.com/astral-sh/ruff> | `0.15.11` | MIT |

<details><summary>Rust crates of ruff: 301 built, 187 manifest-only stubs (pinned by its Cargo.lock)</summary>

| Crate | License | Built |
|---|---|---|
| adler2-2.0.1 | 0BSD OR MIT OR Apache-2.0 | yes |
| aho-corasick-1.1.4 | Unlicense OR MIT | yes |
| alloca-0.4.0 | MIT | no (stub) |
| allocator-api2-0.2.21 | MIT OR Apache-2.0 | yes |
| android_system_properties-0.1.5 | MIT OR Apache-2.0 | no (stub) |
| anes-0.1.6 | MIT OR Apache-2.0 | no (stub) |
| annotate-snippets-0.11.5 | MIT OR Apache-2.0 | yes |
| anstream-0.6.21 | MIT OR Apache-2.0 | no (stub) |
| anstream-1.0.0 | MIT OR Apache-2.0 | yes |
| anstyle-1.0.14 | MIT OR Apache-2.0 | yes |
| anstyle-lossy-1.1.4 | MIT OR Apache-2.0 | no (stub) |
| anstyle-parse-0.2.7 | MIT OR Apache-2.0 | no (stub) |
| anstyle-parse-1.0.0 | MIT OR Apache-2.0 | yes |
| anstyle-query-1.1.4 | MIT OR Apache-2.0 | yes |
| anstyle-svg-0.1.11 | MIT OR Apache-2.0 | no (stub) |
| anstyle-wincon-3.0.10 | MIT OR Apache-2.0 | no (stub) |
| anyhow-1.0.102 | MIT OR Apache-2.0 | yes |
| approx-0.5.1 | Apache-2.0 | no (stub) |
| arc-swap-1.9.1 | MIT OR Apache-2.0 | yes |
| argfile-1.0.0 | MIT OR Apache-2.0 | yes |
| arrayvec-0.7.6 | MIT OR Apache-2.0 | yes |
| assert_fs-1.1.3 | MIT OR Apache-2.0 | no (stub) |
| attribute-derive-0.10.3 | MIT OR Apache-2.0 | yes |
| attribute-derive-macro-0.10.3 | MIT | yes |
| autocfg-1.5.0 | Apache-2.0 OR MIT | yes |
| bincode-2.0.1 | MIT | yes |
| bincode_derive-2.0.1 | MIT | yes |
| bitflags-1.3.2 | MIT OR Apache-2.0 | yes |
| bitflags-2.11.0 | MIT OR Apache-2.0 | yes |
| bit-set-0.8.0 | Apache-2.0 OR MIT | no (stub) |
| bit-vec-0.8.0 | Apache-2.0 OR MIT | no (stub) |
| bitvec-1.0.1 | MIT | yes |
| block2-0.6.2 | MIT | no (stub) |
| block-buffer-0.10.4 | MIT OR Apache-2.0 | no (stub) |
| boxcar-0.2.14 | MIT | yes |
| bstr-1.12.1 | MIT OR Apache-2.0 | yes |
| bumpalo-3.19.0 | MIT OR Apache-2.0 | no (stub) |
| byteorder-1.5.0 | Unlicense OR MIT | yes |
| cachedir-0.3.1 | MIT | yes |
| camino-1.2.2 | MIT OR Apache-2.0 | yes |
| cast-0.3.0 | MIT OR Apache-2.0 | no (stub) |
| castaway-0.2.4 | MIT | yes |
| cc-1.2.38 | MIT OR Apache-2.0 | yes |
| cfg_aliases-0.2.1 | MIT | yes |
| cfg-if-1.0.3 | MIT OR Apache-2.0 | yes |
| chacha20-0.10.0 | MIT OR Apache-2.0 | yes |
| chrono-0.4.44 | MIT OR Apache-2.0 | yes |
| ciborium-0.2.2 | Apache-2.0 | no (stub) |
| ciborium-io-0.2.2 | Apache-2.0 | no (stub) |
| ciborium-ll-0.2.2 | Apache-2.0 | no (stub) |
| clap-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_builder-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_complete-4.5.58 | MIT OR Apache-2.0 | yes |
| clap_complete_command-0.6.1 | MIT | yes |
| clap_complete_nushell-4.5.8 | MIT OR Apache-2.0 | yes |
| clap_derive-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_lex-1.0.0 | MIT OR Apache-2.0 | yes |
| clearscreen-4.0.6 | Apache-2.0 OR MIT | yes |
| codspeed-4.4.1 | MIT OR Apache-2.0 | no (stub) |
| codspeed-criterion-compat-4.4.1 | MIT OR Apache-2.0 | no (stub) |
| codspeed-criterion-compat-walltime-4.4.1 | Apache-2.0 OR MIT | no (stub) |
| codspeed-divan-compat-4.4.1 | MIT OR Apache-2.0 | no (stub) |
| codspeed-divan-compat-macros-4.4.1 | MIT OR Apache-2.0 | no (stub) |
| codspeed-divan-compat-walltime-4.4.1 | MIT OR Apache-2.0 | no (stub) |
| collection_literals-1.0.2 | MIT | yes |
| colorchoice-1.0.4 | MIT OR Apache-2.0 | yes |
| colored-2.2.0 | MPL-2.0 | no (stub) |
| colored-3.1.1 | MPL-2.0 | yes |
| compact_str-0.9.0 | MIT | yes |
| condtype-1.3.0 | MIT OR Apache-2.0 | no (stub) |
| console-0.16.1 | MIT | yes |
| console_error_panic_hook-0.1.7 | Apache-2.0 OR MIT | no (stub) |
| console_log-1.0.0 | MIT OR Apache-2.0 | no (stub) |
| core-foundation-sys-0.8.7 | MIT OR Apache-2.0 | no (stub) |
| countme-3.0.1 | MIT OR Apache-2.0 | yes |
| cpufeatures-0.2.17 | MIT OR Apache-2.0 | no (stub) |
| cpufeatures-0.3.0 | MIT OR Apache-2.0 | yes |
| crc32fast-1.5.0 | MIT OR Apache-2.0 | yes |
| criterion-0.8.2 | Apache-2.0 OR MIT | no (stub) |
| criterion-plot-0.5.0 | MIT OR Apache-2.0 | no (stub) |
| criterion-plot-0.8.2 | Apache-2.0 OR MIT | no (stub) |
| crossbeam-0.8.4 | MIT OR Apache-2.0 | yes |
| crossbeam-channel-0.5.15 | MIT OR Apache-2.0 | yes |
| crossbeam-deque-0.8.6 | MIT OR Apache-2.0 | yes |
| crossbeam-epoch-0.9.18 | MIT OR Apache-2.0 | yes |
| crossbeam-queue-0.3.12 | MIT OR Apache-2.0 | yes |
| crossbeam-utils-0.8.21 | MIT OR Apache-2.0 | yes |
| crunchy-0.2.4 | MIT | no (stub) |
| crypto-common-0.1.6 | MIT OR Apache-2.0 | no (stub) |
| csv-1.4.0 | Unlicense OR MIT | no (stub) |
| csv-core-0.1.12 | Unlicense OR MIT | no (stub) |
| ctrlc-3.5.2 | MIT OR Apache-2.0 | yes |
| darling-0.23.0 | MIT | yes |
| darling_core-0.23.0 | MIT | yes |
| darling_macro-0.23.0 | MIT | yes |
| dashmap-6.1.0 | MIT | yes |
| datatest-stable-0.3.3 | MIT OR Apache-2.0 | no (stub) |
| derive-where-1.6.0 | MIT OR Apache-2.0 | yes |
| diff-0.1.13 | MIT OR Apache-2.0 | no (stub) |
| difflib-0.4.0 | MIT | no (stub) |
| digest-0.10.7 | MIT OR Apache-2.0 | no (stub) |
| dirs-6.0.0 | MIT OR Apache-2.0 | yes |
| dirs-sys-0.5.0 | MIT OR Apache-2.0 | yes |
| dispatch2-0.3.0 | Zlib OR Apache-2.0 OR MIT | no (stub) |
| displaydoc-0.2.5 | MIT OR Apache-2.0 | yes |
| divan-macros-0.1.17 | MIT OR Apache-2.0 | no (stub) |
| doc-comment-0.3.3 | MIT | no (stub) |
| drop_bomb-0.1.5 | MIT OR Apache-2.0 | yes |
| dunce-1.0.5 | CC0-1.0 OR MIT-0 OR Apache-2.0 | yes |
| dyn-clone-1.0.20 | MIT OR Apache-2.0 | yes |
| either-1.15.0 | MIT OR Apache-2.0 | yes |
| encode_unicode-1.0.0 | Apache-2.0 OR MIT | no (stub) |
| equivalent-1.0.2 | Apache-2.0 OR MIT | yes |
| errno-0.3.14 | MIT OR Apache-2.0 | yes |
| escape8259-0.5.3 | MIT | no (stub) |
| escargot-0.5.15 | MIT OR Apache-2.0 | no (stub) |
| etcetera-0.11.0 | MIT OR Apache-2.0 | yes |
| fancy-regex-0.14.0 | MIT | no (stub) |
| fastrand-2.3.0 | Apache-2.0 OR MIT | yes |
| fern-0.7.1 | MIT | yes |
| filetime-0.2.27 | MIT OR Apache-2.0 | yes |
| find-msvc-tools-0.1.2 | MIT OR Apache-2.0 | yes |
| flate2-1.1.2 | MIT OR Apache-2.0 | yes |
| fnv-1.0.7 | Apache-2.0  OR  MIT | yes |
| foldhash-0.1.5 | Zlib | yes |
| form_urlencoded-1.2.2 | MIT OR Apache-2.0 | yes |
| fs-err-3.3.0 | MIT OR Apache-2.0 | yes |
| fsevent-sys-4.1.0 | MIT | no (stub) |
| funty-2.0.0 | MIT | yes |
| generic-array-0.14.7 | MIT | no (stub) |
| getopts-0.2.24 | MIT OR Apache-2.0 | yes |
| getrandom-0.2.16 | MIT OR Apache-2.0 | yes |
| getrandom-0.3.4 | MIT OR Apache-2.0 | yes |
| getrandom-0.4.2 | MIT OR Apache-2.0 | yes |
| get-size2-0.7.4 | MIT OR Apache-2.0 | yes |
| get-size-derive2-0.7.4 | MIT OR Apache-2.0 | yes |
| glob-0.3.3 | MIT OR Apache-2.0 | yes |
| globset-0.4.18 | Unlicense OR MIT | yes |
| globwalk-0.9.1 | MIT | yes |
| half-2.6.0 | MIT OR Apache-2.0 | no (stub) |
| hashbrown-0.14.5 | MIT OR Apache-2.0 | yes |
| hashbrown-0.15.5 | MIT OR Apache-2.0 | yes |
| hashbrown-0.16.1 | MIT OR Apache-2.0 | yes |
| hashlink-0.10.0 | MIT OR Apache-2.0 | yes |
| heck-0.5.0 | MIT OR Apache-2.0 | yes |
| hermit-abi-0.5.2 | MIT OR Apache-2.0 | no (stub) |
| html-escape-0.2.13 | MIT | no (stub) |
| iana-time-zone-0.1.64 | MIT OR Apache-2.0 | yes |
| iana-time-zone-haiku-0.1.2 | MIT OR Apache-2.0 | no (stub) |
| icu_collections-2.2.0 | Unicode-3.0 | yes |
| icu_locale_core-2.2.0 | Unicode-3.0 | yes |
| icu_normalizer-2.2.0 | Unicode-3.0 | yes |
| icu_normalizer_data-2.2.0 | Unicode-3.0 | yes |
| icu_properties-2.2.0 | Unicode-3.0 | yes |
| icu_properties_data-2.2.0 | Unicode-3.0 | yes |
| icu_provider-2.2.0 | Unicode-3.0 | yes |
| id-arena-2.3.0 | MIT OR Apache-2.0 | no (stub) |
| ident_case-1.0.1 | MIT OR Apache-2.0 | yes |
| idna-1.1.0 | MIT OR Apache-2.0 | yes |
| idna_adapter-1.2.1 | Apache-2.0 OR MIT | yes |
| ignore-0.4.25 | Unlicense OR MIT | yes |
| imara-diff-0.2.0 | Apache-2.0 | no (stub) |
| imperative-1.0.7 | MIT OR Apache-2.0 | yes |
| indexmap-2.13.1 | Apache-2.0 OR MIT | yes |
| indicatif-0.18.4 | MIT | yes |
| indoc-2.0.7 | MIT OR Apache-2.0 | no (stub) |
| inotify-0.11.0 | ISC | yes |
| inotify-sys-0.1.5 | ISC | yes |
| insta-1.47.2 | Apache-2.0 | no (stub) |
| insta-cmd-0.6.0 | Apache-2.0 | no (stub) |
| interpolator-0.5.0 | MIT OR Apache-2.0 | yes |
| intrusive-collections-0.9.7 | Apache-2.0 OR MIT | yes |
| inventory-0.3.21 | MIT OR Apache-2.0 | yes |
| is-macro-0.3.7 | Apache-2.0 | yes |
| is-terminal-0.4.16 | MIT | no (stub) |
| is_terminal_polyfill-1.70.1 | MIT OR Apache-2.0 | yes |
| itertools-0.10.5 | MIT OR Apache-2.0 | no (stub) |
| itertools-0.13.0 | MIT OR Apache-2.0 | yes |
| itertools-0.14.0 | MIT OR Apache-2.0 | yes |
| itoa-1.0.15 | MIT OR Apache-2.0 | yes |
| jiff-0.2.23 | Unlicense OR MIT | yes |
| jiff-static-0.2.23 | Unlicense OR MIT | yes |
| jiff-tzdb-0.1.4 | Unlicense OR MIT | no (stub) |
| jiff-tzdb-platform-0.1.3 | Unlicense OR MIT | no (stub) |
| jobserver-0.1.34 | MIT OR Apache-2.0 | yes |
| jod-thread-1.0.0 | MIT OR Apache-2.0 | yes |
| js-sys-0.3.82 | MIT OR Apache-2.0 | no (stub) |
| kqueue-1.1.1 | MIT | no (stub) |
| kqueue-sys-1.0.4 | MIT | no (stub) |
| lazy_static-1.5.0 | MIT OR Apache-2.0 | yes |
| leb128fmt-0.1.0 | MIT OR Apache-2.0 | no (stub) |
| libc-0.2.184 | MIT OR Apache-2.0 | yes |
| libcst-1.8.6 | MIT AND (MIT AND PSF-2.0) | yes |
| libcst_derive-1.8.6 | MIT | yes |
| libmimalloc-sys-0.1.44 | MIT | no (stub) |
| libredox-0.1.10 | MIT | no (stub) |
| libtest-mimic-0.7.3 | MIT OR Apache-2.0 | no (stub) |
| libtest-mimic-0.8.1 | MIT OR Apache-2.0 | no (stub) |
| linux-raw-sys-0.12.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| litemap-0.8.0 | Unicode-3.0 | yes |
| lock_api-0.4.13 | MIT OR Apache-2.0 | yes |
| log-0.4.29 | MIT OR Apache-2.0 | yes |
| lsp-server-0.7.9 | MIT OR Apache-2.0 | yes |
| lsp-types-0.95.1 | MIT | yes |
| manyhow-0.11.4 | MIT OR Apache-2.0 | yes |
| manyhow-macros-0.11.4 | MIT OR Apache-2.0 | yes |
| markdown-1.0.0 | MIT | no (stub) |
| matchers-0.2.0 | MIT | yes |
| matchit-0.9.1 | MIT AND BSD-3-Clause | yes |
| memchr-2.8.0 | Unlicense OR MIT | yes |
| memoffset-0.9.1 | MIT | yes |
| mimalloc-0.1.48 | MIT | no (stub) |
| minicov-0.3.7 | Apache-2.0 OR MIT | no (stub) |
| minimal-lexical-0.2.1 | MIT OR Apache-2.0 | yes |
| miniz_oxide-0.8.9 | MIT OR Zlib OR Apache-2.0 | yes |
| mio-1.0.4 | MIT | yes |
| natord-1.0.9 | MIT | yes |
| newtype-uuid-1.3.2 | MIT OR Apache-2.0 | yes |
| nix-0.31.2 | MIT | yes |
| nom-7.1.3 | MIT | yes |
| normalize-line-endings-0.3.0 | Apache-2.0 | no (stub) |
| notify-8.2.0 | CC0-1.0 | yes |
| notify-types-2.0.0 | MIT OR Apache-2.0 | yes |
| nu-ansi-term-0.50.1 | MIT | yes |
| num_cpus-1.17.0 | MIT OR Apache-2.0 | no (stub) |
| num-traits-0.2.19 | MIT OR Apache-2.0 | yes |
| objc2-0.6.3 | MIT | no (stub) |
| objc2-encode-4.1.0 | MIT | no (stub) |
| once_cell-1.21.3 | MIT OR Apache-2.0 | yes |
| once_cell_polyfill-1.70.1 | MIT OR Apache-2.0 | no (stub) |
| oorandom-11.1.5 | MIT | no (stub) |
| option-ext-0.2.0 | MPL-2.0 | yes |
| ordermap-1.1.0 | Apache-2.0 OR MIT | yes |
| os_pipe-1.2.2 | MIT | no (stub) |
| os_str_bytes-7.1.1 | MIT OR Apache-2.0 | yes |
| page_size-0.6.0 | MIT OR Apache-2.0 | no (stub) |
| parking_lot-0.12.4 | MIT OR Apache-2.0 | yes |
| parking_lot_core-0.9.11 | MIT OR Apache-2.0 | yes |
| paste-1.0.15 | MIT OR Apache-2.0 | yes |
| path-absolutize-3.1.1 | MIT | yes |
| path-dedot-3.1.1 | MIT | yes |
| pathdiff-0.2.3 | MIT OR Apache-2.0 | yes |
| path-slash-0.2.1 | MIT | yes |
| peg-0.8.5 | MIT | yes |
| peg-macros-0.8.5 | MIT | yes |
| peg-runtime-0.8.5 | MIT | yes |
| pep440_rs-0.7.3 | Apache-2.0 OR BSD-2-Clause | yes |
| pep508_rs-0.9.2 | Apache-2.0 OR BSD-2-Clause | yes |
| percent-encoding-2.3.2 | MIT OR Apache-2.0 | yes |
| pest-2.8.2 | MIT OR Apache-2.0 | no (stub) |
| pest_derive-2.8.2 | MIT OR Apache-2.0 | no (stub) |
| pest_generator-2.8.2 | MIT OR Apache-2.0 | no (stub) |
| pest_meta-2.8.2 | MIT OR Apache-2.0 | no (stub) |
| phf-0.11.3 | MIT | yes |
| phf-0.13.1 | MIT | yes |
| phf_codegen-0.11.3 | MIT | yes |
| phf_generator-0.11.3 | MIT | yes |
| phf_shared-0.11.3 | MIT | yes |
| phf_shared-0.13.1 | MIT | yes |
| pin-project-lite-0.2.16 | Apache-2.0 OR MIT | yes |
| pkg-config-0.3.32 | MIT OR Apache-2.0 | yes |
| portable-atomic-1.13.1 | Apache-2.0 OR MIT | yes |
| portable-atomic-util-0.2.4 | Apache-2.0 OR MIT | no (stub) |
| potential_utf-0.1.3 | Unicode-3.0 | yes |
| ppv-lite86-0.2.21 | MIT OR Apache-2.0 | yes |
| predicates-3.1.3 | MIT OR Apache-2.0 | no (stub) |
| predicates-core-1.0.9 | MIT OR Apache-2.0 | no (stub) |
| predicates-tree-1.0.12 | MIT OR Apache-2.0 | no (stub) |
| pretty_assertions-1.4.1 | MIT OR Apache-2.0 | no (stub) |
| prettyplease-0.2.37 | MIT OR Apache-2.0 | no (stub) |
| proc-macro2-1.0.106 | MIT OR Apache-2.0 | yes |
| proc-macro-crate-3.4.0 | MIT OR Apache-2.0 | no (stub) |
| proc-macro-utils-0.10.0 | MIT OR Apache-2.0 | yes |
| pyproject-toml-0.13.7 | MIT | yes |
| quickcheck-1.1.0 | Unlicense OR MIT | no (stub) |
| quickcheck_macros-1.2.0 | Unlicense OR MIT | no (stub) |
| quick-junit-0.6.0 | Apache-2.0 OR MIT | yes |
| quick-xml-0.38.4 | MIT | yes |
| quote-1.0.45 | MIT OR Apache-2.0 | yes |
| quote-use-0.8.4 | MIT | yes |
| quote-use-macros-0.8.4 | MIT | yes |
| radium-0.7.0 | MIT | yes |
| rand-0.10.1 | MIT OR Apache-2.0 | yes |
| rand-0.8.5 | MIT OR Apache-2.0 | yes |
| rand_chacha-0.3.1 | MIT OR Apache-2.0 | yes |
| rand_core-0.10.0 | MIT OR Apache-2.0 | yes |
| rand_core-0.6.4 | MIT OR Apache-2.0 | yes |
| rayon-1.11.0 | MIT OR Apache-2.0 | yes |
| rayon-core-1.13.0 | MIT OR Apache-2.0 | yes |
| redox_syscall-0.5.17 | MIT | no (stub) |
| redox_users-0.5.2 | MIT | no (stub) |
| ref-cast-1.0.25 | MIT OR Apache-2.0 | yes |
| ref-cast-impl-1.0.25 | MIT OR Apache-2.0 | yes |
| r-efi-5.3.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later | no (stub) |
| r-efi-6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later | no (stub) |
| regex-1.12.3 | MIT OR Apache-2.0 | yes |
| regex-automata-0.4.14 | MIT OR Apache-2.0 | yes |
| regex-lite-0.1.7 | MIT OR Apache-2.0 | no (stub) |
| regex-syntax-0.8.10 | MIT OR Apache-2.0 | yes |
| ron-0.12.0 | MIT OR Apache-2.0 | no (stub) |
| rustc-hash-2.1.2 | Apache-2.0 OR MIT | yes |
| rustc-stable-hash-0.1.2 | Apache-2.0 OR MIT | no (stub) |
| rustix-1.1.4 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| rust-stemmers-1.2.0 | MIT OR BSD-3-Clause | yes |
| rustversion-1.0.22 | MIT OR Apache-2.0 | yes |
| ryu-1.0.20 | Apache-2.0 OR BSL-1.0 | yes |
| salsa-0.26.1 | Apache-2.0 OR MIT | yes |
| salsa-macro-rules-0.26.1 | Apache-2.0 OR MIT | yes |
| salsa-macros-0.26.1 | Apache-2.0 OR MIT | yes |
| same-file-1.0.6 | Unlicense OR MIT | yes |
| schemars-1.2.1 | MIT | yes |
| schemars_derive-1.2.1 | MIT | yes |
| scopeguard-1.2.0 | MIT OR Apache-2.0 | yes |
| seahash-4.1.0 | MIT | yes |
| semver-1.0.27 | MIT OR Apache-2.0 | no (stub) |
| serde-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_core-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_derive-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_derive_internals-0.29.1 | MIT OR Apache-2.0 | yes |
| serde_json-1.0.149 | MIT OR Apache-2.0 | yes |
| serde_repr-0.1.20 | MIT OR Apache-2.0 | yes |
| serde_spanned-1.1.1 | MIT OR Apache-2.0 | yes |
| serde_test-1.0.177 | MIT OR Apache-2.0 | no (stub) |
| serde-wasm-bindgen-0.6.5 | MIT | no (stub) |
| serde_with-3.18.0 | MIT OR Apache-2.0 | yes |
| serde_with_macros-3.18.0 | MIT OR Apache-2.0 | yes |
| sha2-0.10.9 | MIT OR Apache-2.0 | no (stub) |
| sharded-slab-0.1.7 | MIT | yes |
| shellexpand-3.1.2 | MIT OR Apache-2.0 | yes |
| shlex-1.3.0 | MIT OR Apache-2.0 | yes |
| similar-2.7.0 | Apache-2.0 | no (stub) |
| similar-3.1.0 | Apache-2.0 | yes |
| siphasher-1.0.1 | MIT OR Apache-2.0 | yes |
| smallvec-1.15.1 | MIT OR Apache-2.0 | yes |
| snapbox-1.0.0 | MIT OR Apache-2.0 | no (stub) |
| snapbox-macros-1.0.0 | MIT OR Apache-2.0 | no (stub) |
| stable_deref_trait-1.2.0 | MIT OR Apache-2.0 | yes |
| static_assertions-1.1.0 | MIT OR Apache-2.0 | yes |
| statrs-0.18.0 | MIT | no (stub) |
| strip-ansi-escapes-0.2.1 | Apache-2.0 OR MIT | yes |
| strsim-0.11.1 | MIT | yes |
| strum-0.28.0 | MIT | yes |
| strum_macros-0.28.0 | MIT | yes |
| supports-hyperlinks-3.2.0 | Apache-2.0 | yes |
| syn-2.0.117 | MIT OR Apache-2.0 | yes |
| synstructure-0.13.2 | MIT | yes |
| tap-1.0.1 | MIT | yes |
| tempfile-3.27.0 | MIT OR Apache-2.0 | yes |
| termcolor-1.4.1 | Unlicense OR MIT | no (stub) |
| terminal_size-0.4.3 | MIT OR Apache-2.0 | yes |
| terminfo-0.9.0 | WTFPL | yes |
| termtree-0.5.1 | MIT | no (stub) |
| test-case-3.3.1 | MIT | no (stub) |
| test-case-core-3.3.1 | MIT | no (stub) |
| test-case-macros-3.3.1 | MIT | no (stub) |
| thin-vec-0.2.14 | MIT OR Apache-2.0 | yes |
| thiserror-1.0.69 | MIT OR Apache-2.0 | yes |
| thiserror-2.0.18 | MIT OR Apache-2.0 | yes |
| thiserror-impl-1.0.69 | MIT OR Apache-2.0 | yes |
| thiserror-impl-2.0.18 | MIT OR Apache-2.0 | yes |
| thread_local-1.1.9 | MIT OR Apache-2.0 | yes |
| threadpool-1.8.1 | MIT OR Apache-2.0 | no (stub) |
| tikv-jemallocator-0.6.1 | MIT OR Apache-2.0 | yes |
| tikv-jemalloc-sys-0.6.1+5.3.0-1-ge13ca993e8ccb9ba9847cc330696e02839f328f7 | MIT OR Apache-2.0 | yes |
| tinystr-0.8.3 | Unicode-3.0 | yes |
| tinytemplate-1.2.1 | Apache-2.0 OR MIT | no (stub) |
| tinyvec-1.10.0 | Zlib OR Apache-2.0 OR MIT | yes |
| tinyvec_macros-0.1.1 | MIT OR Apache-2.0 OR Zlib | yes |
| toml-0.9.12+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml-1.1.2+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_datetime-0.7.5+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_datetime-1.1.1+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_edit-0.23.6 | MIT OR Apache-2.0 | no (stub) |
| toml_parser-1.1.2+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_writer-1.1.1+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| tracing-0.1.44 | MIT | yes |
| tracing-attributes-0.1.31 | MIT | yes |
| tracing-core-0.1.36 | MIT | yes |
| tracing-flame-0.2.0 | MIT | yes |
| tracing-indicatif-0.3.14 | MIT | no (stub) |
| tracing-log-0.2.0 | MIT | yes |
| tracing-subscriber-0.3.23 | MIT | yes |
| tryfn-1.0.0 | MIT OR Apache-2.0 | no (stub) |
| typed-arena-2.0.2 | MIT | yes |
| typeid-1.0.3 | MIT OR Apache-2.0 | no (stub) |
| typenum-1.18.0 | MIT OR Apache-2.0 | no (stub) |
| ucd-trie-0.1.7 | MIT OR Apache-2.0 | no (stub) |
| unicode-id-0.3.6 | MIT OR Apache-2.0 | no (stub) |
| unicode-ident-1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 | yes |
| unicode_names2-1.3.0 | (MIT OR Apache-2.0) AND Unicode-DFS-2016 | yes |
| unicode_names2_generator-1.3.0 | MIT OR Apache-2.0 | yes |
| unicode-normalization-0.1.24 | MIT OR Apache-2.0 | yes |
| unicode-width-0.2.2 | MIT OR Apache-2.0 | yes |
| unicode-xid-0.2.6 | MIT OR Apache-2.0 | no (stub) |
| unit-prefix-0.5.1 | MIT | yes |
| unscanny-0.1.0 | MIT OR Apache-2.0 | yes |
| unty-0.0.4 | MIT OR Apache-2.0 | yes |
| url-2.5.8 | MIT OR Apache-2.0 | yes |
| urlencoding-2.1.3 | MIT | yes |
| utf8_iter-1.0.4 | Apache-2.0 OR MIT | yes |
| utf8parse-0.2.2 | Apache-2.0 OR MIT | yes |
| utf8-width-0.1.7 | MIT | no (stub) |
| uuid-1.23.0 | Apache-2.0 OR MIT | yes |
| valuable-0.1.1 | MIT | no (stub) |
| version_check-0.9.5 | MIT OR Apache-2.0 | no (stub) |
| version-ranges-0.1.1 | MPL-2.0 | yes |
| virtue-0.0.18 | MIT | yes |
| vt100-0.16.2 | MIT | yes |
| vte-0.14.1 | Apache-2.0 OR MIT | yes |
| vte-0.15.0 | Apache-2.0 OR MIT | yes |
| wait-timeout-0.2.1 | MIT OR Apache-2.0 | no (stub) |
| walkdir-2.5.0 | Unlicense OR MIT | yes |
| wasi-0.11.1+wasi-snapshot-preview1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasip2-1.0.1+wasi-0.2.4 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasip3-0.4.0+wasi-0.3.0-rc-2026-01-06 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-bindgen-0.2.105 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-futures-0.4.55 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-macro-0.2.105 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-macro-support-0.2.105 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-shared-0.2.105 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-test-0.3.55 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-test-macro-0.3.55 | MIT OR Apache-2.0 | no (stub) |
| wasm-encoder-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-metadata-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasmparser-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| web-sys-0.3.82 | MIT OR Apache-2.0 | no (stub) |
| web-time-1.1.0 | MIT OR Apache-2.0 | no (stub) |
| which-8.0.2 | MIT | yes |
| wild-2.2.1 | Apache-2.0 OR MIT | yes |
| winapi-0.3.9 | MIT OR Apache-2.0 | no (stub) |
| winapi-i686-pc-windows-gnu-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| winapi-util-0.1.11 | Unlicense OR MIT | no (stub) |
| winapi-x86_64-pc-windows-gnu-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_gnullvm-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows-core-0.62.0 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows-implement-0.60.0 | MIT OR Apache-2.0 | no (stub) |
| windows-interface-0.59.1 | MIT OR Apache-2.0 | no (stub) |
| windows-link-0.1.3 | MIT OR Apache-2.0 | no (stub) |
| windows-link-0.2.0 | MIT OR Apache-2.0 | no (stub) |
| windows-result-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| windows-strings-0.5.0 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.52.0 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.59.0 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.60.2 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.61.0 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.53.3 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.53.0 | MIT OR Apache-2.0 | no (stub) |
| winnow-0.7.13 | MIT | yes |
| winnow-1.0.0 | MIT | yes |
| wit-bindgen-0.46.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-core-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-rust-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-rust-macro-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-component-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-parser-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| writeable-0.6.2 | Unicode-3.0 | yes |
| wyz-0.5.1 | MIT | yes |
| yansi-1.0.1 | MIT OR Apache-2.0 | no (stub) |
| yoke-0.8.2 | Unicode-3.0 | yes |
| yoke-derive-0.8.2 | Unicode-3.0 | yes |
| zerocopy-0.8.27 | BSD-2-Clause OR Apache-2.0 OR MIT | yes |
| zerocopy-derive-0.8.27 | BSD-2-Clause OR Apache-2.0 OR MIT | no (stub) |
| zerofrom-0.1.6 | Unicode-3.0 | yes |
| zerofrom-derive-0.1.6 | Unicode-3.0 | yes |
| zerotrie-0.2.4 | Unicode-3.0 | yes |
| zerovec-0.11.6 | Unicode-3.0 | yes |
| zerovec-derive-0.11.3 | Unicode-3.0 | yes |
| zip-0.6.6 | MIT | yes |
| zmij-1.0.10 | MIT | yes |
| zstd-0.11.2+zstd.1.5.2 | MIT | yes |
| zstd-safe-5.0.2+zstd.1.5.2 | MIT OR Apache-2.0 | yes |
| zstd-sys-2.0.16+zstd.1.5.7 | MIT OR Apache-2.0 | yes |

</details>

<!-- inventory:end -->
