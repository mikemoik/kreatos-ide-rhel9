# kreatos-ide-rhel9

misw's kreatos Neovim setup, packaged to build **offline from source** on
RHEL9. Everything the build needs is in this repo; the build never touches the
network, and the repo holds no binaries (checked by `scripts/check-sources.py`).

## Install (on the RHEL9 box)

One call does everything:

    curl -fsSL https://raw.githubusercontent.com/mikemoik/kreatos-ide-rhel9/main/install.sh | bash

1. Installs the RHEL packages that are missing (from the RHEL repos only;
   asks for your sudo password): the build toolchain (gcc, make, cmake,
   python3, rust-toolset, golang), tar, git-core, and the C/C++ tools below.
2. Downloads this repo as a tarball into a temp dir (removed afterwards).
3. Builds and installs kreatos-ide offline into `~/.local/kreatos-ide`
   (`build.sh`, ~5 min).
4. Copies the sample projects to `~/kide-samples` (only if that does not
   exist yet): `customers-py` and `customers-cpp`, a multi-file customer
   database in Python and C++/CMake to try kide on (see their READMEs).
5. Opens a new shell in which `kide` works. Every later shell finds it too.

Without network (repo copied over), run `./install.sh` from the checkout: it
skips the download. Another prefix: `./install.sh /opt/kide`, or
`curl … | bash -s /opt/kide`.

Everything is installed inside `PREFIX`. The only changes outside it are
`~/kide-samples` and one line `build.sh` adds to `~/.bashrc` (once), sourcing
`PREFIX/bashrc`, which
puts `PREFIX/bin` at the front of `PATH`, so `kide` and the bundled tools are
found first in every new shell.

`kide` runs the bundled nvim with the bundled config, with the bundled LSP
servers and formatters (`PREFIX/bin`) first on `PATH`. Its data, state and
cache live under `NVIM_APPNAME=kreatos-ide` (`~/.local/share/kreatos-ide`, …),
so it never mixes with another nvim. The repo is only read; intermediate files
go to `$KIDE_BUILD_DIR` (default `/tmp/kide-build`, safe to delete afterwards).

### C/C++ development

RHEL9 ships the heavy C/C++ tools itself, so they are **not** bundled; kide
uses them when installed (and skips them otherwise). `install.sh` installs
them: `gcc-c++ clang-tools-extra gdb lldb`.

- `clang-tools-extra`: clangd (LSP), clang-format (format on save),
  clang-tidy (runs inside clangd)
- `gdb` (16, speaks DAP itself) and `lldb` (`lldb-dap`): the two debug
  adapters; gdb is the default (also for cmake-tools and neotest-gtest)
- `cmake`, `make`, `gcc`/`gcc-toolset-*`, `clang`, `valgrind` as usual

Bundled for C/C++: neocmakelsp (CMake LSP), clangd_extensions.nvim,
cmake-tools.nvim, neotest + neotest-gtest, neogen, and the cpp, cmake, make
and doxygen parsers. Keys:

| Keys | Action |
|---|---|
| `<leader>ch` / `cH` / `cs` | switch source/header, type hierarchy, symbol info |
| `<leader>mg` `mb` `mr` `md` | CMake generate, build, run, debug target |
| `<leader>mt` `mT` `ms` `mc` | select launch target, build target, build type; clean |
| `<leader>tr` `tt` `tT` `td` | run nearest test, file, all; debug nearest |
| `<leader>ts` `to` `tO` `tl` `tS` | test summary, output, output panel, run last, stop |
| `<leader>cn` | Doxygen/docstring skeleton for the function under the cursor |
| `<leader>d…` | debugging (pick "Launch (gdb)" or "Launch (lldb-dap)") |

cmake-tools builds into `build/<BuildType>` and links `compile_commands.json`
into the project root, which is what clangd reads.

### Terminal tools

Also built from source and put on `PATH` with kide (plain binaries, upstream
defaults, no config):

- `lazygit` — git TUI; inside kide on `<leader>gg` (root dir) / `<leader>gG` (cwd)
- `yazi` + `ya` — file manager. Needs RHEL's `file` for file-type detection
  (`install.sh` installs it). Code previews are highlighted for the languages
  of Sublime Text's own packages (Python, C/C++, shell, Lua, JSON, YAML,
  Markdown, Makefile, HTML/JS/TS, Rust, Go, …) plus CMake, TOML and
  Dockerfile; other text files preview as plain text, and so do HTML,
  TypeScript/JSX/TSX and PHP (their Sublime syntaxes are too new for
  syntect, as in upstream yazi).
- `fd` — fast `find`; the snacks file pickers use it
- `fzf` — fuzzy finder

## What is inside

| Path | Content |
|---|---|
| `vendor/neovim` | Neovim source (`manifest/neovim.txt`) |
| `vendor/neovim-deps` | its bundled deps as source trees (libuv, LuaJIT, luv, lpeg, unibilium, utf8proc, tree-sitter, bundled parsers), pinned + sha256-checked by Neovim's `cmake.deps/deps.txt` |
| `vendor/plugins` | the plugins, plain source at pinned commits (`manifest/plugins.tsv`) |
| `vendor/grammars` | treesitter grammar repos (`grammar.js` + generated `src/parser.c`) |
| `vendor/tools` | LSP servers, formatters, debugger (`manifest/tools.tsv`): ruff + ty, neocmakelsp, shfmt, debugpy, fd, fzf, lazygit, yazi, yazi-prebuilt (the syntax repos for yazi's previews); Go tools carry their modules in their own `vendor/` |
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
- yazi: its compiled syntax set (`yazi-prebuilt/built/syntaxes`, binary) is
  regenerated by yazi-prebuilt's own `generate.rs` from the `.sublime-syntax`
  files in `vendor/tools/yazi-prebuilt/syntaxes` (official, cmake, toml,
  docker: `YAZI_SYNTAXES` in `scripts/vendor-update.sh`), uncompressed as
  yazi 26.1.22 expects (the pinned `generate.rs` still compresses), and
  without syntect's own default dumps (stripped). ring's four DER
  templates (13–41 byte PKCS#8/AlgorithmIdentifier headers, included by
  yazi's SFTP code) are written from hex in `build.sh`. Both go into a copy
  of the crate dir.

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
- nvim-dap-python starts the bundled debugpy through `kide-python` (python3
  with the bundled debugpy on `PYTHONPATH`) instead of a system debugpy.
- LSP servers: `ty`, `ruff`, `clangd` (from RHEL), `neocmake` (no `lua_ls`);
  no Lua formatter (no stylua). C/C++ additions: see above.
  Lua files still get treesitter highlighting, indent and folds. A server
  whose binary is missing is skipped.

## Status

| Step | Content | State |
|---|---|---|
| 1 | Neovim + plugins + parsers | done, passes in UBI9 offline |
| 2 | lua-language-server, stylua | built and tested, then dropped: no Lua development on the target |
| 3 | ruff + ty 0.15.11 (newest tag that builds with Rust 1.92) | done, passes in UBI9 offline |
| 4 | shfmt 3.13.1, debugpy 1.8.21 (last release for Python 3.9) | done, passes in UBI9 offline |
| C++ | parsers, neocmakelsp 0.11.0 (newest that builds with Rust 1.92), clangd_extensions, cmake-tools, neotest-gtest, neogen; config for RHEL's clangd/clang-format/gdb/lldb-dap | task 123 |
| tools | fd 10.5.0, fzf 0.74.4, lazygit 0.65.1, yazi 26.1.22 (newest that builds with Rust 1.92; later ones need 1.95) | in progress |

## Updating the pins (on a connected machine)

1. Edit `manifest/` (Neovim tag, plugin commits, parser list).
2. `scripts/vendor-update.sh` — the only step that downloads; needs curl, tar,
   sha256sum, git, cargo, Python >= 3.11, an nvim to resolve the parser list,
   and Go (if not installed, RHEL's Go runs in a UBI9 container via docker).
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
each formatter formats through conform, a debugpy session started through
nvim-dap-python stops at a breakpoint, blink.cmp running with the Lua
matcher. For C/C++ (the test image also installs RHEL's gcc-c++,
clang-tools-extra, gdb and lldb): a small CMake project is configured and
built, clangd reports an error, neocmakelsp attaches, clang-format formats,
gdb and lldb-dap each stop at a breakpoint in the built program, cmake-tools,
clangd_extensions and neotest-gtest load, neogen writes a Doxygen comment.

To try the install by hand in the same container (the image has every
package, so `install.sh` only builds; the container and its install are gone
on exit):

    docker run --rm -it --network=none -v "$PWD:/src:ro" kreatos-ide-rhel9-test /src/install.sh

<!-- inventory:start -->

## Third-party software

Everything vendored in this repo, with the pinned upstream version and its
license. Generated from `VERSIONS` by `scripts/gen-inventory.py` (run by
`scripts/vendor-update.sh`); do not edit by hand.

| Component | Upstream | Version / commit | License |
|---|---|---|---|
| gomod/fzf/github.com/charlievieth/fastwalk | <https://github.com/charlievieth/fastwalk> | `v1.0.14` | MIT |
| gomod/fzf/github.com/gdamore/encoding | <https://github.com/gdamore/encoding> | `v1.0.1` | Apache-2.0 |
| gomod/fzf/github.com/gdamore/tcell/v2 | <https://github.com/gdamore/tcell/v2> | `v2.9.0` | Apache-2.0 |
| gomod/fzf/github.com/junegunn/go-shellwords | <https://github.com/junegunn/go-shellwords> | `v0.0.0-20250` | MIT |
| gomod/fzf/github.com/lucasb-eyer/go-colorful | <https://github.com/lucasb-eyer/go-colorful> | `v1.2.0` | MIT |
| gomod/fzf/github.com/mattn/go-isatty | <https://github.com/mattn/go-isatty> | `v0.0.24` | MIT |
| gomod/fzf/github.com/mattn/go-runewidth | <https://github.com/mattn/go-runewidth> | `v0.0.16` | MIT |
| gomod/fzf/github.com/rivo/uniseg | <https://github.com/rivo/uniseg> | `v0.4.7` | MIT |
| gomod/fzf/golang.org/x/sys | <https://golang.org/x/sys> | `v0.35.0` | BSD-3-Clause |
| gomod/fzf/golang.org/x/term | <https://golang.org/x/term> | `v0.34.0` | BSD-3-Clause |
| gomod/fzf/golang.org/x/text | <https://golang.org/x/text> | `v0.28.0` | BSD-3-Clause |
| gomod/lazygit/dario.cat/mergo | <https://dario.cat/mergo> | `v1.0.2` | BSD-3-Clause |
| gomod/lazygit/github.com/adrg/xdg | <https://github.com/adrg/xdg> | `v0.5.3` | MIT |
| gomod/lazygit/github.com/atotto/clipboard | <https://github.com/atotto/clipboard> | `v0.1.4` | BSD-3-Clause |
| gomod/lazygit/github.com/aybabtme/humanlog | <https://github.com/aybabtme/humanlog> | `v0.4.1` | Apache-2.0 |
| gomod/lazygit/github.com/bahlo/generic-list-go | <https://github.com/bahlo/generic-list-go> | `v0.2.0` | BSD-3-Clause |
| gomod/lazygit/github.com/buger/jsonparser | <https://github.com/buger/jsonparser> | `v1.1.2` | MIT |
| gomod/lazygit/github.com/cli/go-gh/v2 | <https://github.com/cli/go-gh/v2> | `v2.13.0` | MIT |
| gomod/lazygit/github.com/clipperhouse/displaywidth | <https://github.com/clipperhouse/displaywidth> | `v0.11.0` | MIT |
| gomod/lazygit/github.com/clipperhouse/uax29/v2 | <https://github.com/clipperhouse/uax29/v2> | `v2.7.0` | MIT |
| gomod/lazygit/github.com/cli/safeexec | <https://github.com/cli/safeexec> | `v1.0.1` | BSD-2-Clause |
| gomod/lazygit/github.com/cloudfoundry/jibber_jabber | <https://github.com/cloudfoundry/jibber_jabber> | `v0.0.0-20151` | Apache-2.0 |
| gomod/lazygit/github.com/creack/pty | <https://github.com/creack/pty> | `v1.1.24` | MIT |
| gomod/lazygit/github.com/fatih/color | <https://github.com/fatih/color> | `v1.9.0` | MIT |
| gomod/lazygit/github.com/gdamore/encoding | <https://github.com/gdamore/encoding> | `v1.0.1` | Apache-2.0 |
| gomod/lazygit/github.com/gdamore/tcell/v3 | <https://github.com/gdamore/tcell/v3> | `v3.5.0` | Apache-2.0 |
| gomod/lazygit/github.com/go-errors/errors | <https://github.com/go-errors/errors> | `v1.5.1` | MIT |
| gomod/lazygit/github.com/go-logfmt/logfmt | <https://github.com/go-logfmt/logfmt> | `v0.5.0` | MIT |
| gomod/lazygit/github.com/gookit/color | <https://github.com/gookit/color> | `v1.6.1` | MIT |
| gomod/lazygit/github.com/integrii/flaggy | <https://github.com/integrii/flaggy> | `v1.8.0` | Unlicense |
| gomod/lazygit/github.com/jesseduffield/generics | <https://github.com/jesseduffield/generics> | `v0.0.0-20250` | MIT |
| gomod/lazygit/github.com/jesseduffield/lazycore | <https://github.com/jesseduffield/lazycore> | `v0.0.0-20221` | MIT |
| gomod/lazygit/github.com/kardianos/osext | <https://github.com/kardianos/osext> | `v0.0.0-20190` | BSD-3-Clause |
| gomod/lazygit/github.com/karimkhaleel/jsonschema | <https://github.com/karimkhaleel/jsonschema> | `v0.0.0-20231` | MIT |
| gomod/lazygit/github.com/kr/logfmt | <https://github.com/kr/logfmt> | `v0.0.0-20140` | MIT |
| gomod/lazygit/github.com/kyokomi/emoji/v2 | <https://github.com/kyokomi/emoji/v2> | `v2.2.14` | MIT |
| gomod/lazygit/github.com/lucasb-eyer/go-colorful | <https://github.com/lucasb-eyer/go-colorful> | `v1.4.1` | MIT |
| gomod/lazygit/github.com/mailru/easyjson | <https://github.com/mailru/easyjson> | `v0.7.7` | MIT |
| gomod/lazygit/github.com/mattn/go-colorable | <https://github.com/mattn/go-colorable> | `v0.1.13` | MIT |
| gomod/lazygit/github.com/mattn/go-isatty | <https://github.com/mattn/go-isatty> | `v0.0.20` | MIT |
| gomod/lazygit/github.com/mgutz/str | <https://github.com/mgutz/str> | `v1.2.0` | MIT |
| gomod/lazygit/github.com/mitchellh/go-ps | <https://github.com/mitchellh/go-ps> | `v1.0.0` | MIT |
| gomod/lazygit/github.com/petermattis/goid | <https://github.com/petermattis/goid> | `v0.0.0-20250` | Apache-2.0 |
| gomod/lazygit/github.com/rivo/uniseg | <https://github.com/rivo/uniseg> | `v0.4.7` | MIT |
| gomod/lazygit/github.com/sahilm/fuzzy | <https://github.com/sahilm/fuzzy> | `v0.1.3` | MIT |
| gomod/lazygit/github.com/samber/lo | <https://github.com/samber/lo> | `v1.53.0` | MIT |
| gomod/lazygit/github.com/sanity-io/litter | <https://github.com/sanity-io/litter> | `v1.5.8` | MIT |
| gomod/lazygit/github.com/sasha-s/go-deadlock | <https://github.com/sasha-s/go-deadlock> | `v0.3.9` | Apache-2.0 |
| gomod/lazygit/github.com/sirupsen/logrus | <https://github.com/sirupsen/logrus> | `v1.10.2` | MIT |
| gomod/lazygit/github.com/spf13/afero | <https://github.com/spf13/afero> | `v1.15.0` | Apache-2.0 |
| gomod/lazygit/github.com/spkg/bom | <https://github.com/spkg/bom> | `v1.0.1` | MIT |
| gomod/lazygit/github.com/stefanhaller/git-todo-parser | <https://github.com/stefanhaller/git-todo-parser> | `v0.0.7-0.202` | MIT |
| gomod/lazygit/github.com/stretchr/testify | <https://github.com/stretchr/testify> | `v1.12.1` | MIT |
| gomod/lazygit/github.com/wk8/go-ordered-map/v2 | <https://github.com/wk8/go-ordered-map/v2> | `v2.1.8` | Apache-2.0 |
| gomod/lazygit/github.com/xo/terminfo | <https://github.com/xo/terminfo> | `v1.0.0` | MIT |
| gomod/lazygit/golang.org/x/exp | <https://golang.org/x/exp> | `v0.0.0-20240` | BSD-3-Clause |
| gomod/lazygit/golang.org/x/mod | <https://golang.org/x/mod> | `v0.38.0` | BSD-3-Clause |
| gomod/lazygit/golang.org/x/sync | <https://golang.org/x/sync> | `v0.22.0` | BSD-3-Clause |
| gomod/lazygit/golang.org/x/sys | <https://golang.org/x/sys> | `v0.47.0` | BSD-3-Clause |
| gomod/lazygit/golang.org/x/term | <https://golang.org/x/term> | `v0.45.0` | BSD-3-Clause |
| gomod/lazygit/golang.org/x/text | <https://golang.org/x/text> | `v0.41.0` | BSD-3-Clause |
| gomod/lazygit/golang.org/x/tools | <https://golang.org/x/tools> | `v0.48.0` | BSD-3-Clause |
| gomod/lazygit/gopkg.in/ozeidan/fuzzy-patricia.v3 | <https://gopkg.in/ozeidan/fuzzy-patricia.v3> | `v3.0.0` | MIT |
| gomod/lazygit/gopkg.in/yaml.v3 | <https://gopkg.in/yaml.v3> | `v3.0.1` | Apache-2.0 OR MIT |
| gomod/lazygit/go.yaml.in/yaml/v3 | <https://go.yaml.in/yaml/v3> | `v3.0.5` | Apache-2.0 OR MIT |
| gomod/lazygit/mvdan.cc/gofumpt | <https://mvdan.cc/gofumpt> | `v0.11.0` | BSD-3-Clause |
| gomod/shfmt/github.com/creack/pty | <https://github.com/creack/pty> | `v1.1.24` | MIT |
| gomod/shfmt/github.com/google/go-cmp | <https://github.com/google/go-cmp> | `v0.7.0` | BSD-3-Clause |
| gomod/shfmt/github.com/google/renameio/v2 | <https://github.com/google/renameio/v2> | `v2.0.2` | Apache-2.0 |
| gomod/shfmt/github.com/go-quicktest/qt | <https://github.com/go-quicktest/qt> | `v1.101.0` | MIT |
| gomod/shfmt/github.com/kr/pretty | <https://github.com/kr/pretty> | `v0.3.1` | MIT |
| gomod/shfmt/github.com/kr/text | <https://github.com/kr/text> | `v0.2.0` | MIT |
| gomod/shfmt/github.com/rogpeppe/go-internal | <https://github.com/rogpeppe/go-internal> | `v1.14.1` | BSD-3-Clause |
| gomod/shfmt/golang.org/x/mod | <https://golang.org/x/mod> | `v0.29.0` | BSD-3-Clause |
| gomod/shfmt/golang.org/x/sync | <https://golang.org/x/sync> | `v0.17.0` | BSD-3-Clause |
| gomod/shfmt/golang.org/x/sys | <https://golang.org/x/sys> | `v0.42.0` | BSD-3-Clause |
| gomod/shfmt/golang.org/x/term | <https://golang.org/x/term> | `v0.41.0` | BSD-3-Clause |
| gomod/shfmt/golang.org/x/tools | <https://golang.org/x/tools> | `v0.38.0` | BSD-3-Clause |
| gomod/shfmt/mvdan.cc/editorconfig | <https://mvdan.cc/editorconfig> | `v0.3.0` | BSD-3-Clause |
| grammar/tree-sitter-bash | <https://github.com/tree-sitter/tree-sitter-bash> | `a06c2e4415e9` | MIT |
| grammar/tree-sitter-c | <https://github.com/tree-sitter/tree-sitter-c> | `ae19b676b13b` | MIT |
| grammar/tree-sitter-cmake | <https://github.com/uyha/tree-sitter-cmake> | `c7b2a71e7f8e` | MIT |
| grammar/tree-sitter-cpp | <https://github.com/tree-sitter/tree-sitter-cpp> | `12bd6f7e9608` | MIT |
| grammar/tree-sitter-diff | <https://github.com/tree-sitter-grammars/tree-sitter-diff> | `2520c3f934b3` | MIT |
| grammar/tree-sitter-doxygen | <https://github.com/tree-sitter-grammars/tree-sitter-doxygen> | `ccd998f378c3` | MIT |
| grammar/tree-sitter-html | <https://github.com/tree-sitter/tree-sitter-html> | `73a3947324f6` | MIT |
| grammar/tree-sitter-javascript | <https://github.com/tree-sitter/tree-sitter-javascript> | `58404d8cf191` | MIT |
| grammar/tree-sitter-jsdoc | <https://github.com/tree-sitter/tree-sitter-jsdoc> | `658d18dcdddb` | MIT |
| grammar/tree-sitter-json | <https://github.com/tree-sitter/tree-sitter-json> | `001c28d7a298` | MIT |
| grammar/tree-sitter-luadoc | <https://github.com/tree-sitter-grammars/tree-sitter-luadoc> | `873612aadd3f` | MIT |
| grammar/tree-sitter-lua | <https://github.com/tree-sitter-grammars/tree-sitter-lua> | `e40f5b6e6df9` | MIT |
| grammar/tree-sitter-luap | <https://github.com/tree-sitter-grammars/tree-sitter-luap> | `c134aaec6acf` | MIT |
| grammar/tree-sitter-make | <https://github.com/tree-sitter-grammars/tree-sitter-make> | `5e9e8f8ff338` | MIT |
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
| plugin/clangd_extensions.nvim | <https://github.com/p00f/clangd_extensions.nvim> | `78c2ecd659d5` | MIT |
| plugin/cmake-tools.nvim | <https://github.com/Civitasv/cmake-tools.nvim> | `ee807ac4e625` | GPL-3.0 |
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
| plugin/neogen | <https://github.com/danymat/neogen> | `23e7e9f883d0` | GPL-3.0 |
| plugin/neotest-gtest | <https://github.com/alfaix/neotest-gtest> | `bdffb45731ed` | MIT |
| plugin/neotest | <https://github.com/nvim-neotest/neotest> | `27bf92149804` | MIT |
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
| tool/debugpy | <https://pypi.org/project/debugpy> | `1.8.21` | MIT |
| tool/fd | <https://github.com/sharkdp/fd> | `v10.5.0` | Apache-2.0 OR MIT |
| tool/fzf | <https://github.com/junegunn/fzf> | `v0.74.4` | MIT |
| tool/lazygit | <https://github.com/jesseduffield/lazygit> | `v0.65.1` | MIT |
| tool/neocmakelsp | <https://github.com/neocmakelsp/neocmakelsp> | `v0.11.0` | MIT |
| tool/ruff | <https://github.com/astral-sh/ruff> | `0.15.11` | MIT |
| tool/shfmt | <https://github.com/mvdan/sh> | `v3.13.1` | BSD-3-Clause |
| tool/yazi | <https://github.com/sxyazi/yazi> | `v26.1.22` | MIT |
| tool/yazi-prebuilt | <https://github.com/yazi-rs/prebuilt> | `2d52c0b8b399` | MIT |
| tool/yazi-prebuilt/syntaxes/cmake | <https://github.com/zyxar/Sublime-CMakeLists.git> | `eb40ede56c2d` | MIT |
| tool/yazi-prebuilt/syntaxes/docker | <https://github.com/asbjornenge/Docker.tmbundle.git> | `0f6b7bc87acf` | MIT |
| tool/yazi-prebuilt/syntaxes/official | <https://github.com/sublimehq/Packages.git> | `0a97be539c27` | LicenseRef-SublimeHQ-Packages |
| tool/yazi-prebuilt/syntaxes/toml | <https://github.com/jasonwilliams/sublime_toml_highlighting.git> | `fd0bf3e5d6c9` | MIT |

<details><summary>Rust crates of fd: 69 built, 60 manifest-only stubs (pinned by its Cargo.lock)</summary>

| Crate | License | Built |
|---|---|---|
| aho-corasick-1.1.4 | Unlicense OR MIT | yes |
| anstream-1.0.0 | MIT OR Apache-2.0 | yes |
| anstyle-1.0.13 | MIT OR Apache-2.0 | yes |
| anstyle-parse-1.0.0 | MIT OR Apache-2.0 | yes |
| anstyle-query-1.1.5 | MIT OR Apache-2.0 | yes |
| anstyle-wincon-3.0.11 | MIT OR Apache-2.0 | no (stub) |
| anyhow-1.0.104 | MIT OR Apache-2.0 | yes |
| argmax-0.4.0 | MIT OR Apache-2.0 | yes |
| bitflags-1.3.2 | MIT OR Apache-2.0 | yes |
| bitflags-2.11.0 | MIT OR Apache-2.0 | yes |
| block2-0.6.2 | MIT | no (stub) |
| bstr-1.12.1 | MIT OR Apache-2.0 | yes |
| cc-1.2.56 | MIT OR Apache-2.0 | yes |
| cfg_aliases-0.2.1 | MIT | yes |
| cfg-if-1.0.4 | MIT OR Apache-2.0 | yes |
| clap-4.6.1 | MIT OR Apache-2.0 | yes |
| clap_builder-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_complete-4.6.5 | MIT OR Apache-2.0 | yes |
| clap_derive-4.6.1 | MIT OR Apache-2.0 | yes |
| clap_lex-1.0.0 | MIT OR Apache-2.0 | yes |
| colorchoice-1.0.4 | MIT OR Apache-2.0 | yes |
| crossbeam-channel-0.5.16 | MIT OR Apache-2.0 | yes |
| crossbeam-deque-0.8.6 | MIT OR Apache-2.0 | yes |
| crossbeam-epoch-0.9.18 | MIT OR Apache-2.0 | yes |
| crossbeam-utils-0.8.21 | MIT OR Apache-2.0 | yes |
| ctrlc-3.5.2 | MIT OR Apache-2.0 | yes |
| defmt-1.1.0 | MIT OR Apache-2.0 | yes |
| defmt-macros-1.1.0 | MIT OR Apache-2.0 | yes |
| defmt-parser-1.0.0 | MIT OR Apache-2.0 | yes |
| diff-0.1.13 | MIT OR Apache-2.0 | no (stub) |
| dispatch2-0.3.1 | Zlib OR Apache-2.0 OR MIT | no (stub) |
| equivalent-1.0.2 | Apache-2.0 OR MIT | no (stub) |
| errno-0.3.14 | MIT OR Apache-2.0 | yes |
| etcetera-0.11.0 | MIT OR Apache-2.0 | yes |
| faccess-0.2.4 | MIT | yes |
| fastrand-2.3.0 | Apache-2.0 OR MIT | no (stub) |
| filetime-0.2.29 | MIT OR Apache-2.0 | no (stub) |
| find-msvc-tools-0.1.9 | MIT OR Apache-2.0 | yes |
| foldhash-0.1.5 | Zlib | no (stub) |
| getrandom-0.4.2 | MIT OR Apache-2.0 | no (stub) |
| globset-0.4.19 | Unlicense OR MIT | yes |
| hashbrown-0.15.5 | MIT OR Apache-2.0 | no (stub) |
| hashbrown-0.16.1 | MIT OR Apache-2.0 | no (stub) |
| heck-0.5.0 | MIT OR Apache-2.0 | yes |
| id-arena-2.3.0 | MIT OR Apache-2.0 | no (stub) |
| ignore-0.4.31 | Unlicense OR MIT | yes |
| indexmap-2.13.0 | Apache-2.0 OR MIT | no (stub) |
| is_terminal_polyfill-1.70.2 | MIT OR Apache-2.0 | yes |
| itoa-1.0.17 | MIT OR Apache-2.0 | no (stub) |
| jiff-0.2.29 | Unlicense OR MIT | yes |
| jiff-static-0.2.29 | Unlicense OR MIT | yes |
| jiff-tzdb-0.1.6 | Unlicense OR MIT | no (stub) |
| jiff-tzdb-platform-0.1.3 | Unlicense OR MIT | no (stub) |
| leb128fmt-0.1.0 | MIT OR Apache-2.0 | no (stub) |
| libc-0.2.189 | MIT OR Apache-2.0 | yes |
| linux-raw-sys-0.12.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| log-0.4.29 | MIT OR Apache-2.0 | yes |
| lscolors-0.21.0 | MIT OR Apache-2.0 | yes |
| memchr-2.8.0 | Unlicense OR MIT | yes |
| nix-0.30.1 | MIT | yes |
| nix-0.31.3 | MIT | yes |
| normpath-1.5.1 | MIT OR Apache-2.0 | yes |
| nu-ansi-term-0.50.3 | MIT | yes |
| objc2-0.6.4 | MIT | no (stub) |
| objc2-encode-4.1.0 | MIT | no (stub) |
| once_cell-1.21.3 | MIT OR Apache-2.0 | yes |
| once_cell_polyfill-1.70.2 | MIT OR Apache-2.0 | no (stub) |
| portable-atomic-1.13.1 | Apache-2.0 OR MIT | no (stub) |
| portable-atomic-util-0.2.5 | Apache-2.0 OR MIT | no (stub) |
| prettyplease-0.2.37 | MIT OR Apache-2.0 | no (stub) |
| proc-macro2-1.0.106 | MIT OR Apache-2.0 | yes |
| proc-macro-error2-2.0.1 | MIT OR Apache-2.0 | yes |
| proc-macro-error-attr2-2.0.0 | MIT OR Apache-2.0 | yes |
| quote-1.0.45 | MIT OR Apache-2.0 | yes |
| r-efi-6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later | no (stub) |
| regex-1.12.4 | MIT OR Apache-2.0 | yes |
| regex-automata-0.4.14 | MIT OR Apache-2.0 | yes |
| regex-syntax-0.8.11 | MIT OR Apache-2.0 | yes |
| rustix-1.1.4 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| same-file-1.0.6 | Unlicense OR MIT | yes |
| semver-1.0.27 | MIT OR Apache-2.0 | no (stub) |
| serde-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_core-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_derive-1.0.228 | MIT OR Apache-2.0 | no (stub) |
| serde_json-1.0.149 | MIT OR Apache-2.0 | no (stub) |
| shlex-1.3.0 | MIT OR Apache-2.0 | yes |
| strsim-0.11.1 | MIT | yes |
| syn-2.0.117 | MIT OR Apache-2.0 | yes |
| tempfile-3.27.0 | MIT OR Apache-2.0 | no (stub) |
| terminal_size-0.4.3 | MIT OR Apache-2.0 | yes |
| test-case-3.3.1 | MIT | no (stub) |
| test-case-core-3.3.1 | MIT | no (stub) |
| test-case-macros-3.3.1 | MIT | no (stub) |
| thiserror-2.0.18 | MIT OR Apache-2.0 | yes |
| thiserror-impl-2.0.18 | MIT OR Apache-2.0 | yes |
| tikv-jemallocator-0.7.0 | MIT OR Apache-2.0 | yes |
| tikv-jemalloc-sys-0.7.1+5.3.1-0-g81034ce1f1373e37dc865038e1bc8eeecf559ce8 | MIT OR Apache-2.0 | yes |
| unicode-ident-1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 | yes |
| unicode-xid-0.2.6 | MIT OR Apache-2.0 | no (stub) |
| utf8parse-0.2.2 | Apache-2.0 OR MIT | yes |
| walkdir-2.5.0 | Unlicense OR MIT | yes |
| wasip2-1.0.2+wasi-0.2.9 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasip3-0.4.0+wasi-0.3.0-rc-2026-01-06 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-encoder-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-metadata-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasmparser-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| winapi-0.3.9 | MIT OR Apache-2.0 | no (stub) |
| winapi-i686-pc-windows-gnu-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| winapi-util-0.1.11 | Unlicense OR MIT | no (stub) |
| winapi-x86_64-pc-windows-gnu-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows-link-0.2.1 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.60.2 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.61.2 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.53.5 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| wit-bindgen-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-core-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-rust-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-rust-macro-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-component-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-parser-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| zmij-1.0.21 | MIT | no (stub) |

</details>

<details><summary>Rust crates of neocmakelsp: 162 built, 63 manifest-only stubs (pinned by its Cargo.lock)</summary>

| Crate | License | Built |
|---|---|---|
| aho-corasick-1.1.4 | Unlicense OR MIT | yes |
| android_system_properties-0.1.5 | MIT OR Apache-2.0 | no (stub) |
| anstream-1.0.0 | MIT OR Apache-2.0 | yes |
| anstyle-1.0.14 | MIT OR Apache-2.0 | yes |
| anstyle-parse-1.0.0 | MIT OR Apache-2.0 | yes |
| anstyle-query-1.1.5 | MIT OR Apache-2.0 | yes |
| anstyle-wincon-3.0.11 | MIT OR Apache-2.0 | no (stub) |
| anyhow-1.0.102 | MIT OR Apache-2.0 | yes |
| assert_cmd-2.2.0 | MIT OR Apache-2.0 | no (stub) |
| autocfg-1.5.1 | Apache-2.0 OR MIT | yes |
| auto_impl-1.3.0 | MIT OR Apache-2.0 | yes |
| bitflags-2.11.0 | MIT OR Apache-2.0 | yes |
| bstr-1.12.1 | MIT OR Apache-2.0 | yes |
| bumpalo-3.20.3 | MIT OR Apache-2.0 | no (stub) |
| bytes-1.11.1 | MIT | yes |
| cc-1.2.58 | MIT OR Apache-2.0 | yes |
| cfg-if-1.0.4 | MIT OR Apache-2.0 | yes |
| chrono-0.4.45 | MIT OR Apache-2.0 | yes |
| clap-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_builder-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_complete-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_derive-4.6.0 | MIT OR Apache-2.0 | yes |
| clap_lex-1.1.0 | MIT OR Apache-2.0 | yes |
| cli-table-0.5.0 | MIT OR Apache-2.0 | yes |
| cli-table-derive-0.5.0 | MIT OR Apache-2.0 | yes |
| colorchoice-1.0.5 | MIT OR Apache-2.0 | yes |
| console-0.16.4 | MIT | yes |
| const-random-0.1.18 | MIT OR Apache-2.0 | yes |
| const-random-macro-0.1.16 | MIT OR Apache-2.0 | yes |
| core-foundation-sys-0.8.7 | MIT OR Apache-2.0 | no (stub) |
| crossbeam-deque-0.8.6 | MIT OR Apache-2.0 | yes |
| crossbeam-epoch-0.9.18 | MIT OR Apache-2.0 | yes |
| crossbeam-utils-0.8.21 | MIT OR Apache-2.0 | yes |
| crunchy-0.2.4 | MIT | yes |
| csv-1.4.0 | Unlicense OR MIT | yes |
| csv-core-0.1.13 | Unlicense OR MIT | yes |
| dashmap-6.2.1 | MIT | yes |
| dialoguer-0.12.0 | MIT | yes |
| difflib-0.4.0 | MIT | no (stub) |
| displaydoc-0.2.5 | MIT OR Apache-2.0 | yes |
| dlv-list-0.5.2 | MIT OR Apache-2.0 | yes |
| encode_unicode-1.0.0 | Apache-2.0 OR MIT | no (stub) |
| equivalent-1.0.2 | Apache-2.0 OR MIT | yes |
| errno-0.3.14 | MIT OR Apache-2.0 | yes |
| etcetera-0.11.0 | MIT OR Apache-2.0 | yes |
| fastrand-2.3.0 | Apache-2.0 OR MIT | yes |
| find-msvc-tools-0.1.9 | MIT OR Apache-2.0 | yes |
| foldhash-0.1.5 | Zlib | no (stub) |
| form_urlencoded-1.2.2 | MIT OR Apache-2.0 | yes |
| futures-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-channel-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-core-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-io-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-macro-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-sink-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-task-0.3.32 | MIT OR Apache-2.0 | yes |
| futures-util-0.3.32 | MIT OR Apache-2.0 | yes |
| fuzzy-matcher-0.3.7 | MIT | yes |
| gen-lsp-types-0.9.0 | MIT | yes |
| getrandom-0.2.17 | MIT OR Apache-2.0 | yes |
| getrandom-0.4.2 | MIT OR Apache-2.0 | yes |
| glob-0.3.3 | MIT OR Apache-2.0 | yes |
| globset-0.4.18 | Unlicense OR MIT | yes |
| hashbrown-0.14.5 | MIT OR Apache-2.0 | yes |
| hashbrown-0.15.5 | MIT OR Apache-2.0 | no (stub) |
| hashbrown-0.16.1 | MIT OR Apache-2.0 | yes |
| heck-0.5.0 | MIT OR Apache-2.0 | yes |
| httparse-1.10.1 | MIT OR Apache-2.0 | yes |
| iana-time-zone-0.1.65 | MIT OR Apache-2.0 | yes |
| iana-time-zone-haiku-0.1.2 | MIT OR Apache-2.0 | no (stub) |
| icu_collections-2.2.0 | Unicode-3.0 | yes |
| icu_locale_core-2.2.0 | Unicode-3.0 | yes |
| icu_normalizer-2.2.0 | Unicode-3.0 | yes |
| icu_normalizer_data-2.2.0 | Unicode-3.0 | yes |
| icu_properties-2.2.0 | Unicode-3.0 | yes |
| icu_properties_data-2.2.0 | Unicode-3.0 | yes |
| icu_provider-2.2.0 | Unicode-3.0 | yes |
| id-arena-2.3.0 | MIT OR Apache-2.0 | no (stub) |
| idna-1.1.0 | MIT OR Apache-2.0 | yes |
| idna_adapter-1.2.2 | Apache-2.0 OR MIT | yes |
| ignore-0.4.25 | Unlicense OR MIT | yes |
| indexmap-2.13.0 | Apache-2.0 OR MIT | yes |
| indoc-2.0.7 | MIT OR Apache-2.0 | no (stub) |
| is_executable-1.0.5 | MIT OR Apache-2.0 | yes |
| is_terminal_polyfill-1.70.2 | MIT OR Apache-2.0 | yes |
| itoa-1.0.18 | MIT OR Apache-2.0 | yes |
| js-sys-0.3.103 | MIT OR Apache-2.0 | no (stub) |
| lazy_static-1.5.0 | MIT OR Apache-2.0 | yes |
| leb128fmt-0.1.0 | MIT OR Apache-2.0 | no (stub) |
| libc-0.2.184 | MIT OR Apache-2.0 | yes |
| linux-raw-sys-0.12.1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| litemap-0.8.2 | Unicode-3.0 | yes |
| lock_api-0.4.14 | MIT OR Apache-2.0 | yes |
| log-0.4.29 | MIT OR Apache-2.0 | yes |
| memchr-2.8.0 | Unlicense OR MIT | yes |
| mio-1.2.0 | MIT | yes |
| nu-ansi-term-0.50.3 | MIT | yes |
| num-traits-0.2.19 | MIT OR Apache-2.0 | yes |
| once_cell-1.21.4 | MIT OR Apache-2.0 | yes |
| once_cell_polyfill-1.70.2 | MIT OR Apache-2.0 | no (stub) |
| ordered-multimap-0.7.3 | MIT | yes |
| parking_lot-0.12.5 | MIT OR Apache-2.0 | yes |
| parking_lot_core-0.9.12 | MIT OR Apache-2.0 | yes |
| path-absolutize-4.0.1 | MIT | no (stub) |
| path-dedot-4.0.1 | MIT | no (stub) |
| pathdiff-0.2.3 | MIT OR Apache-2.0 | yes |
| percent-encoding-2.3.2 | MIT OR Apache-2.0 | yes |
| pin-project-lite-0.2.17 | Apache-2.0 OR MIT | yes |
| potential_utf-0.1.5 | Unicode-3.0 | yes |
| predicates-3.1.4 | MIT OR Apache-2.0 | no (stub) |
| predicates-core-1.0.10 | MIT OR Apache-2.0 | no (stub) |
| predicates-tree-1.0.13 | MIT OR Apache-2.0 | no (stub) |
| prettyplease-0.2.37 | MIT OR Apache-2.0 | no (stub) |
| proc-macro2-1.0.106 | MIT OR Apache-2.0 | yes |
| quote-1.0.45 | MIT OR Apache-2.0 | yes |
| redox_syscall-0.5.18 | MIT | no (stub) |
| r-efi-6.0.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later | no (stub) |
| regex-1.13.1 | MIT OR Apache-2.0 | yes |
| regex-automata-0.4.16 | MIT OR Apache-2.0 | yes |
| regex-syntax-0.8.11 | MIT OR Apache-2.0 | yes |
| rust-ini-0.21.3 | MIT | yes |
| rustix-1.1.4 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| rustversion-1.0.22 | MIT OR Apache-2.0 | no (stub) |
| ryu-1.0.23 | Apache-2.0 OR BSL-1.0 | yes |
| same-file-1.0.6 | Unlicense OR MIT | yes |
| scopeguard-1.2.0 | MIT OR Apache-2.0 | yes |
| semver-1.0.27 | MIT OR Apache-2.0 | no (stub) |
| serde-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_core-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_derive-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_json-1.0.150 | MIT OR Apache-2.0 | yes |
| serde_spanned-1.1.1 | MIT OR Apache-2.0 | yes |
| sharded-slab-0.1.7 | MIT | yes |
| shell-words-1.1.1 | MIT OR Apache-2.0 | yes |
| shlex-1.3.0 | MIT OR Apache-2.0 | yes |
| signal-hook-registry-1.4.8 | MIT OR Apache-2.0 | yes |
| slab-0.4.12 | MIT | yes |
| smallvec-1.15.1 | MIT OR Apache-2.0 | yes |
| socket2-0.6.3 | MIT OR Apache-2.0 | yes |
| stable_deref_trait-1.2.1 | MIT OR Apache-2.0 | yes |
| streaming-iterator-0.1.9 | MIT OR Apache-2.0 | yes |
| strsim-0.11.1 | MIT | yes |
| syn-2.0.117 | MIT OR Apache-2.0 | yes |
| sync_wrapper-1.0.2 | Apache-2.0 | yes |
| synstructure-0.13.2 | MIT | yes |
| tempfile-3.27.0 | MIT OR Apache-2.0 | yes |
| termcolor-1.4.1 | Unlicense OR MIT | yes |
| termtree-0.5.1 | MIT | no (stub) |
| thread_local-1.1.9 | MIT OR Apache-2.0 | yes |
| tiny-keccak-2.0.2 | CC0-1.0 | yes |
| tinystr-0.8.3 | Unicode-3.0 | yes |
| tokio-1.52.0 | MIT | yes |
| tokio-macros-2.7.0 | MIT | yes |
| tokio-util-0.7.18 | MIT | yes |
| toml-1.1.2+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_datetime-1.1.1+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_parser-1.1.2+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_writer-1.1.1+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| tower-0.5.3 | MIT | yes |
| tower-layer-0.3.3 | MIT | yes |
| tower-lsp-f-0.26.0 | MIT OR Apache-2.0 | yes |
| tower-service-0.3.3 | MIT | yes |
| tracing-0.1.44 | MIT | yes |
| tracing-attributes-0.1.31 | MIT | yes |
| tracing-core-0.1.36 | MIT | yes |
| tracing-log-0.2.0 | MIT | yes |
| tracing-subscriber-0.3.23 | MIT | yes |
| tree-sitter-0.26.8 | MIT | yes |
| tree-sitter-cmake-0.7.2 | MIT | yes |
| treesitter_kind_collector-0.2.0 | MIT | yes |
| tree-sitter-language-0.1.7 | MIT | yes |
| unicode-ident-1.0.24 | (MIT OR Apache-2.0) AND Unicode-3.0 | yes |
| unicode-width-0.2.2 | MIT OR Apache-2.0 | yes |
| unicode-xid-0.2.6 | MIT OR Apache-2.0 | no (stub) |
| url-2.5.8 | MIT OR Apache-2.0 | yes |
| utf8_iter-1.0.4 | Apache-2.0 OR MIT | yes |
| utf8parse-0.2.2 | Apache-2.0 OR MIT | yes |
| valuable-0.1.1 | MIT | no (stub) |
| wait-timeout-0.2.1 | MIT OR Apache-2.0 | no (stub) |
| walkdir-2.5.0 | Unlicense OR MIT | yes |
| wasi-0.11.1+wasi-snapshot-preview1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasip2-1.0.2+wasi-0.2.9 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasip3-0.4.0+wasi-0.3.0-rc-2026-01-06 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-bindgen-0.2.126 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-macro-0.2.126 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-macro-support-0.2.126 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-shared-0.2.126 | MIT OR Apache-2.0 | no (stub) |
| wasm-encoder-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-metadata-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasmparser-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| winapi-util-0.1.11 | Unlicense OR MIT | no (stub) |
| windows_aarch64_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows-core-0.62.2 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows-implement-0.60.2 | MIT OR Apache-2.0 | no (stub) |
| windows-interface-0.59.3 | MIT OR Apache-2.0 | no (stub) |
| windows-link-0.2.1 | MIT OR Apache-2.0 | no (stub) |
| windows-result-0.4.1 | MIT OR Apache-2.0 | no (stub) |
| windows-strings-0.5.1 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.60.2 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.61.2 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.53.5 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| winnow-1.0.1 | MIT | yes |
| wit-bindgen-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-core-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-rust-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-bindgen-rust-macro-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-component-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wit-parser-0.244.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| writeable-0.6.3 | Unicode-3.0 | yes |
| yoke-0.8.2 | Unicode-3.0 | yes |
| yoke-derive-0.8.2 | Unicode-3.0 | yes |
| zerofrom-0.1.8 | Unicode-3.0 | yes |
| zerofrom-derive-0.1.7 | Unicode-3.0 | yes |
| zeroize-1.9.0 | Apache-2.0 OR MIT | yes |
| zerotrie-0.2.4 | Unicode-3.0 | yes |
| zerovec-0.11.6 | Unicode-3.0 | yes |
| zerovec-derive-0.11.3 | Unicode-3.0 | yes |
| zmij-1.0.21 | MIT | yes |

</details>

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

<details><summary>Rust crates of yazi: 480 built, 78 manifest-only stubs (pinned by its Cargo.lock)</summary>

| Crate | License | Built |
|---|---|---|
| addr2line-0.25.1 | Apache-2.0 OR MIT | yes |
| adler2-2.0.1 | 0BSD OR MIT OR Apache-2.0 | yes |
| aead-0.5.2 | MIT OR Apache-2.0 | yes |
| aes-0.8.4 | MIT OR Apache-2.0 | yes |
| aes-gcm-0.10.3 | Apache-2.0 OR MIT | yes |
| aho-corasick-1.1.4 | Unlicense OR MIT | yes |
| aligned-0.4.3 | MIT OR Apache-2.0 | yes |
| aligned-vec-0.6.4 | MIT | yes |
| allocator-api2-0.2.21 | MIT OR Apache-2.0 | yes |
| android_system_properties-0.1.5 | MIT OR Apache-2.0 | no (stub) |
| ansi-to-tui-8.0.1 | MIT | yes |
| anstream-0.6.21 | MIT OR Apache-2.0 | yes |
| anstyle-1.0.13 | MIT OR Apache-2.0 | yes |
| anstyle-parse-0.2.7 | MIT OR Apache-2.0 | yes |
| anstyle-query-1.1.5 | MIT OR Apache-2.0 | yes |
| anstyle-wincon-3.0.11 | MIT OR Apache-2.0 | no (stub) |
| anyhow-1.0.100 | MIT OR Apache-2.0 | yes |
| arbitrary-1.4.2 | MIT OR Apache-2.0 | no (stub) |
| arc-swap-1.8.0 | MIT OR Apache-2.0 | yes |
| arg_enum_proc_macro-0.3.4 | MIT | yes |
| argon2-0.5.3 | MIT OR Apache-2.0 | yes |
| arrayvec-0.7.6 | MIT OR Apache-2.0 | yes |
| as-slice-0.2.1 | MIT OR Apache-2.0 | yes |
| async-priority-channel-0.2.0 | Apache-2.0 OR MIT | yes |
| atomic-0.6.1 | Apache-2.0 OR MIT | yes |
| autocfg-1.5.0 | Apache-2.0 OR MIT | yes |
| av1-grain-0.2.5 | BSD-2-Clause | yes |
| avif-serialize-0.8.6 | BSD-3-Clause | yes |
| av-scenechange-0.14.1 | MIT | yes |
| backtrace-0.3.76 | MIT OR Apache-2.0 | yes |
| base16ct-0.2.0 | Apache-2.0 OR MIT | yes |
| base16ct-1.0.0 | Apache-2.0 OR MIT | yes |
| base64-0.22.1 | MIT OR Apache-2.0 | yes |
| base64ct-1.8.3 | Apache-2.0 OR MIT | yes |
| bcrypt-pbkdf-0.10.0 | MIT OR Apache-2.0 | yes |
| better-panic-0.3.0 | MIT | yes |
| bincode-1.3.3 | MIT | yes |
| bit_field-0.10.3 | Apache-2.0 OR MIT | yes |
| bitflags-1.3.2 | MIT OR Apache-2.0 | yes |
| bitflags-2.10.0 | MIT OR Apache-2.0 | yes |
| bit-set-0.5.3 | MIT OR Apache-2.0 | yes |
| bitstream-io-4.9.0 | MIT OR Apache-2.0 | yes |
| bit-vec-0.6.3 | MIT OR Apache-2.0 | yes |
| bitvec-1.0.1 | MIT | yes |
| blake2-0.10.6 | MIT OR Apache-2.0 | yes |
| block-buffer-0.10.4 | MIT OR Apache-2.0 | yes |
| block-buffer-0.11.0 | MIT OR Apache-2.0 | yes |
| block-padding-0.3.3 | MIT OR Apache-2.0 | yes |
| blowfish-0.9.1 | MIT OR Apache-2.0 | yes |
| bstr-1.12.1 | MIT OR Apache-2.0 | yes |
| built-0.8.0 | MIT | yes |
| bumpalo-3.19.1 | MIT OR Apache-2.0 | yes |
| by_address-1.2.1 | MIT OR Apache-2.0 | yes |
| bytemuck-1.24.0 | Zlib OR Apache-2.0 OR MIT | yes |
| bytemuck_derive-1.10.2 | Zlib OR Apache-2.0 OR MIT | yes |
| byteorder-1.5.0 | Unlicense OR MIT | yes |
| byteorder-lite-0.1.0 | Unlicense OR MIT | yes |
| bytes-1.11.0 | MIT | yes |
| castaway-0.2.4 | MIT | yes |
| cbc-0.1.2 | MIT OR Apache-2.0 | yes |
| cc-1.2.53 | MIT OR Apache-2.0 | yes |
| cfg_aliases-0.2.1 | MIT | yes |
| cfg-if-1.0.4 | MIT OR Apache-2.0 | yes |
| chacha20-0.9.1 | Apache-2.0 OR MIT | yes |
| chrono-0.4.43 | MIT OR Apache-2.0 | yes |
| cipher-0.4.4 | MIT OR Apache-2.0 | yes |
| clap-4.5.54 | MIT OR Apache-2.0 | yes |
| clap_builder-4.5.54 | MIT OR Apache-2.0 | yes |
| clap_complete-4.5.65 | MIT OR Apache-2.0 | yes |
| clap_complete_fig-4.5.2 | MIT OR Apache-2.0 | yes |
| clap_complete_nushell-4.5.10 | MIT OR Apache-2.0 | yes |
| clap_derive-4.5.49 | MIT OR Apache-2.0 | yes |
| clap_lex-0.7.7 | MIT OR Apache-2.0 | yes |
| clipboard-win-5.4.1 | BSL-1.0 | no (stub) |
| cmov-0.5.0-pre.0 | Apache-2.0 OR MIT | yes |
| colorchoice-1.0.4 | MIT OR Apache-2.0 | yes |
| color_quant-1.1.0 | MIT | yes |
| compact_str-0.9.0 | MIT | yes |
| concurrent-queue-2.5.0 | Apache-2.0 OR MIT | yes |
| console-0.15.11 | MIT | yes |
| const-oid-0.10.2 | Apache-2.0 OR MIT | yes |
| const-oid-0.9.6 | Apache-2.0 OR MIT | yes |
| convert_case-0.10.0 | MIT | yes |
| core2-0.4.0 | Apache-2.0 OR MIT | yes |
| core-foundation-sys-0.8.7 | MIT OR Apache-2.0 | no (stub) |
| core-models-0.0.4 | Apache-2.0 | no (stub) |
| cpufeatures-0.2.17 | MIT OR Apache-2.0 | yes |
| crc32fast-1.5.0 | MIT OR Apache-2.0 | yes |
| crossbeam-channel-0.5.15 | MIT OR Apache-2.0 | yes |
| crossbeam-deque-0.8.6 | MIT OR Apache-2.0 | yes |
| crossbeam-epoch-0.9.18 | MIT OR Apache-2.0 | yes |
| crossbeam-utils-0.8.21 | MIT OR Apache-2.0 | yes |
| crossterm-0.28.1 | MIT | yes |
| crossterm-0.29.0 | MIT | yes |
| crossterm_winapi-0.9.1 | MIT | no (stub) |
| crunchy-0.2.4 | MIT | no (stub) |
| crypto-bigint-0.5.5 | Apache-2.0 OR MIT | yes |
| crypto-bigint-0.7.0-rc.18 | Apache-2.0 OR MIT | yes |
| crypto-common-0.1.7 | MIT OR Apache-2.0 | yes |
| crypto-common-0.2.0-rc.10 | MIT OR Apache-2.0 | yes |
| crypto-primes-0.7.0-pre.6 | Apache-2.0 OR MIT | yes |
| csscolorparser-0.6.2 | MIT OR Apache-2.0 | yes |
| ctr-0.9.2 | MIT OR Apache-2.0 | yes |
| ctutils-0.3.2 | Apache-2.0 OR MIT | yes |
| curve25519-dalek-4.1.3 | BSD-3-Clause | yes |
| curve25519-dalek-derive-0.1.1 | MIT OR Apache-2.0 | yes |
| darling-0.20.11 | MIT | yes |
| darling-0.23.0 | MIT | yes |
| darling_core-0.20.11 | MIT | yes |
| darling_core-0.23.0 | MIT | yes |
| darling_macro-0.20.11 | MIT | yes |
| darling_macro-0.23.0 | MIT | yes |
| data-encoding-2.10.0 | MIT | yes |
| deadpool-0.12.3 | MIT OR Apache-2.0 | yes |
| deadpool-runtime-0.1.4 | MIT OR Apache-2.0 | yes |
| delegate-0.13.5 | MIT OR Apache-2.0 | yes |
| deltae-0.3.2 | MIT | yes |
| der-0.7.10 | Apache-2.0 OR MIT | yes |
| der-0.8.0-rc.10 | Apache-2.0 OR MIT | yes |
| deranged-0.5.5 | MIT OR Apache-2.0 | yes |
| derive_builder-0.20.2 | MIT OR Apache-2.0 | yes |
| derive_builder_core-0.20.2 | MIT OR Apache-2.0 | yes |
| derive_builder_macro-0.20.2 | MIT OR Apache-2.0 | yes |
| derive_more-2.1.1 | MIT | yes |
| derive_more-impl-2.1.1 | MIT | yes |
| digest-0.10.7 | MIT OR Apache-2.0 | yes |
| digest-0.11.0-rc.6 | MIT OR Apache-2.0 | yes |
| dirs-6.0.0 | MIT OR Apache-2.0 | yes |
| dirs-sys-0.5.0 | MIT OR Apache-2.0 | yes |
| document-features-0.2.12 | MIT OR Apache-2.0 | yes |
| ecdsa-0.16.9 | Apache-2.0 OR MIT | yes |
| ed25519-2.2.3 | Apache-2.0 OR MIT | yes |
| ed25519-dalek-2.2.0 | BSD-3-Clause | yes |
| either-1.15.0 | MIT OR Apache-2.0 | yes |
| elliptic-curve-0.13.8 | Apache-2.0 OR MIT | yes |
| encode_unicode-1.0.0 | Apache-2.0 OR MIT | no (stub) |
| enum_dispatch-0.3.13 | MIT OR Apache-2.0 | yes |
| env_home-0.1.0 | MIT OR Apache-2.0 | yes |
| equator-0.4.2 | MIT | yes |
| equator-macro-0.4.2 | MIT | yes |
| equivalent-1.0.2 | Apache-2.0 OR MIT | yes |
| erased-serde-0.4.9 | MIT OR Apache-2.0 | yes |
| errno-0.3.14 | MIT OR Apache-2.0 | yes |
| error-code-3.3.2 | BSL-1.0 | no (stub) |
| euclid-0.22.13 | MIT OR Apache-2.0 | yes |
| event-listener-4.0.3 | Apache-2.0 OR MIT | yes |
| exr-1.74.0 | BSD-3-Clause | yes |
| fancy-regex-0.11.0 | MIT | yes |
| fast-srgb8-1.0.0 | MIT OR Apache-2.0 OR CC0-1.0 | yes |
| fax-0.2.6 | MIT | yes |
| fax_derive-0.2.0 | MIT | yes |
| fdeflate-0.3.7 | MIT OR Apache-2.0 | yes |
| fdlimit-0.3.0 | Apache-2.0 | yes |
| ff-0.13.1 | MIT OR Apache-2.0 | yes |
| fiat-crypto-0.2.9 | MIT OR Apache-2.0 OR BSD-1-Clause | no (stub) |
| filedescriptor-0.8.3 | MIT | yes |
| find-msvc-tools-0.1.8 | MIT OR Apache-2.0 | yes |
| finl_unicode-1.4.0 | (MIT OR Apache-2.0) AND Unicode-DFS-2016 | yes |
| fixedbitset-0.4.2 | MIT OR Apache-2.0 | yes |
| flate2-1.1.8 | MIT OR Apache-2.0 | yes |
| fnv-1.0.7 | Apache-2.0  OR  MIT | yes |
| foldhash-0.2.0 | Zlib | yes |
| fsevent-sys-4.1.0 | MIT | no (stub) |
| funty-2.0.0 | MIT | yes |
| futures-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-channel-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-core-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-executor-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-io-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-macro-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-sink-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-task-0.3.31 | MIT OR Apache-2.0 | yes |
| futures-util-0.3.31 | MIT OR Apache-2.0 | yes |
| generic-array-0.14.7 | MIT | yes |
| generic-array-1.3.5 | MIT | yes |
| getrandom-0.2.17 | MIT OR Apache-2.0 | yes |
| getrandom-0.3.4 | MIT OR Apache-2.0 | yes |
| ghash-0.5.1 | Apache-2.0 OR MIT | yes |
| gif-0.14.1 | MIT OR Apache-2.0 | yes |
| gimli-0.32.3 | MIT OR Apache-2.0 | yes |
| globset-0.4.18 | Unlicense OR MIT | yes |
| group-0.13.0 | MIT OR Apache-2.0 | yes |
| half-2.7.1 | MIT OR Apache-2.0 | yes |
| hashbrown-0.16.1 | MIT OR Apache-2.0 | yes |
| hax-lib-0.3.5 | Apache-2.0 | yes |
| hax-lib-macros-0.3.5 | Apache-2.0 | yes |
| hax-lib-macros-types-0.3.5 | Apache-2.0 | no (stub) |
| heck-0.5.0 | MIT OR Apache-2.0 | yes |
| hermit-abi-0.5.2 | MIT OR Apache-2.0 | no (stub) |
| hex-0.4.3 | MIT OR Apache-2.0 | yes |
| hex-literal-0.4.1 | MIT OR Apache-2.0 | yes |
| hkdf-0.12.4 | MIT OR Apache-2.0 | yes |
| hmac-0.12.1 | MIT OR Apache-2.0 | yes |
| home-0.5.12 | MIT OR Apache-2.0 | yes |
| hybrid-array-0.4.5 | MIT OR Apache-2.0 | yes |
| iana-time-zone-0.1.64 | MIT OR Apache-2.0 | yes |
| iana-time-zone-haiku-0.1.2 | MIT OR Apache-2.0 | no (stub) |
| ident_case-1.0.1 | MIT OR Apache-2.0 | yes |
| image-0.25.9 | MIT OR Apache-2.0 | yes |
| image-webp-0.2.4 | MIT OR Apache-2.0 | yes |
| imgref-1.12.0 | CC0-1.0 OR Apache-2.0 | yes |
| indexmap-2.13.0 | Apache-2.0 OR MIT | yes |
| indoc-2.0.7 | MIT OR Apache-2.0 | yes |
| inotify-0.11.0 | ISC | yes |
| inotify-sys-0.1.5 | ISC | yes |
| inout-0.1.4 | MIT OR Apache-2.0 | yes |
| instability-0.3.11 | MIT | yes |
| internal-russh-forked-ssh-key-0.6.16+upstream-0.6.7 | Apache-2.0 OR MIT | yes |
| interpolate_name-0.2.4 | MIT | no (stub) |
| is_terminal_polyfill-1.70.2 | MIT OR Apache-2.0 | yes |
| itertools-0.14.0 | MIT OR Apache-2.0 | yes |
| itoa-1.0.17 | MIT OR Apache-2.0 | yes |
| jobserver-0.1.34 | MIT OR Apache-2.0 | yes |
| js-sys-0.3.85 | MIT OR Apache-2.0 | no (stub) |
| kasuari-0.4.11 | MIT OR Apache-2.0 | yes |
| kqueue-1.1.1 | MIT | no (stub) |
| kqueue-sys-1.0.4 | MIT | no (stub) |
| lab-0.11.0 | MIT | yes |
| lazy_static-1.5.0 | MIT OR Apache-2.0 | yes |
| lebe-0.5.3 | BSD-3-Clause | yes |
| libc-0.2.180 | MIT OR Apache-2.0 | yes |
| libcrux-intrinsics-0.0.4 | Apache-2.0 | yes |
| libcrux-ml-kem-0.0.4 | Apache-2.0 | yes |
| libcrux-platform-0.0.2 | Apache-2.0 | yes |
| libcrux-secrets-0.0.4 | Apache-2.0 | yes |
| libcrux-sha3-0.0.4 | Apache-2.0 | yes |
| libcrux-traits-0.0.4 | Apache-2.0 | yes |
| libfuzzer-sys-0.4.10 | (MIT OR Apache-2.0) AND NCSA | no (stub) |
| libm-0.2.15 | MIT | yes |
| libredox-0.1.12 | MIT | no (stub) |
| line-clipping-0.3.5 | MIT OR Apache-2.0 | yes |
| linux-raw-sys-0.11.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| linux-raw-sys-0.4.15 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| litrs-1.0.0 | MIT OR Apache-2.0 | yes |
| lock_api-0.4.14 | MIT OR Apache-2.0 | yes |
| log-0.4.29 | MIT OR Apache-2.0 | yes |
| loop9-0.1.5 | MIT | yes |
| lru-0.16.3 | MIT | yes |
| luajit-src-210.6.6+707c12b | MIT | yes |
| lua-src-548.1.2 | MIT | yes |
| mac_address-1.1.8 | MIT OR Apache-2.0 | yes |
| matchers-0.2.0 | MIT | yes |
| maybe-rayon-0.1.1 | MIT | yes |
| md5-0.7.0 | Apache-2.0 OR MIT | yes |
| memchr-2.7.6 | Unlicense OR MIT | yes |
| memmem-0.1.1 | MIT OR Apache-2.0 | yes |
| memoffset-0.9.1 | MIT | yes |
| minimal-lexical-0.2.1 | MIT OR Apache-2.0 | yes |
| miniz_oxide-0.8.9 | MIT OR Zlib OR Apache-2.0 | yes |
| mio-1.1.1 | MIT | yes |
| mlua-0.11.5 | MIT | yes |
| mlua_derive-0.11.0 | MIT | yes |
| mlua-sys-0.9.0 | MIT | yes |
| moxcms-0.7.11 | BSD-3-Clause OR Apache-2.0 | yes |
| moxcms-0.8.0 | BSD-3-Clause OR Apache-2.0 | yes |
| new_debug_unreachable-1.0.6 | MIT | yes |
| nix-0.29.0 | MIT | yes |
| nom-7.1.3 | MIT | yes |
| nom-8.0.0 | MIT | yes |
| noop_proc_macro-0.3.0 | MIT | yes |
| notify-8.2.0 | CC0-1.0 | yes |
| notify-types-2.0.0 | MIT OR Apache-2.0 | yes |
| nu-ansi-term-0.50.3 | MIT | yes |
| num-bigint-0.4.6 | MIT OR Apache-2.0 | yes |
| num-bigint-dig-0.8.6 | MIT OR Apache-2.0 | yes |
| num-conv-0.1.0 | MIT OR Apache-2.0 | yes |
| num_cpus-1.17.0 | MIT OR Apache-2.0 | yes |
| num-derive-0.4.2 | MIT OR Apache-2.0 | yes |
| num-integer-0.1.46 | MIT OR Apache-2.0 | yes |
| num-iter-0.1.45 | MIT OR Apache-2.0 | yes |
| num-rational-0.4.2 | MIT OR Apache-2.0 | yes |
| num_threads-0.1.7 | MIT OR Apache-2.0 | yes |
| numtoa-0.2.4 | MIT OR Apache-2.0 | yes |
| num-traits-0.2.19 | MIT OR Apache-2.0 | yes |
| objc2-0.6.3 | MIT | no (stub) |
| objc2-encode-4.1.0 | MIT | no (stub) |
| objc2-foundation-0.3.2 | MIT | no (stub) |
| object-0.37.3 | Apache-2.0 OR MIT | yes |
| once_cell-1.21.3 | MIT OR Apache-2.0 | yes |
| once_cell_polyfill-1.70.2 | MIT OR Apache-2.0 | no (stub) |
| onig-6.5.1 | MIT | yes |
| onig_sys-69.9.1 | MIT | yes |
| opaque-debug-0.3.1 | MIT OR Apache-2.0 | yes |
| option-ext-0.2.0 | MPL-2.0 | yes |
| ordered-float-2.10.1 | MIT | yes |
| ordered-float-4.6.0 | MIT | yes |
| ordered-float-5.1.0 | MIT | yes |
| p256-0.13.2 | Apache-2.0 OR MIT | yes |
| p384-0.13.1 | Apache-2.0 OR MIT | yes |
| p521-0.13.3 | Apache-2.0 OR MIT | yes |
| pageant-0.2.0 | Apache-2.0 | no (stub) |
| palette-0.7.6 | MIT OR Apache-2.0 | yes |
| palette_derive-0.7.6 | MIT OR Apache-2.0 | yes |
| parking-2.2.1 | Apache-2.0 OR MIT | yes |
| parking_lot-0.12.5 | MIT OR Apache-2.0 | yes |
| parking_lot_core-0.9.12 | MIT OR Apache-2.0 | yes |
| password-hash-0.5.0 | MIT OR Apache-2.0 | yes |
| paste-1.0.15 | MIT OR Apache-2.0 | yes |
| pastey-0.1.1 | MIT OR Apache-2.0 | yes |
| pbkdf2-0.12.2 | MIT OR Apache-2.0 | yes |
| pem-rfc7468-0.7.0 | Apache-2.0 OR MIT | yes |
| pem-rfc7468-1.0.0 | Apache-2.0 OR MIT | yes |
| percent-encoding-2.3.2 | MIT OR Apache-2.0 | yes |
| pest-2.8.5 | MIT OR Apache-2.0 | yes |
| pest_derive-2.8.5 | MIT OR Apache-2.0 | yes |
| pest_generator-2.8.5 | MIT OR Apache-2.0 | yes |
| pest_meta-2.8.5 | MIT OR Apache-2.0 | yes |
| phf-0.11.3 | MIT | yes |
| phf_codegen-0.11.3 | MIT | yes |
| phf_generator-0.11.3 | MIT | yes |
| phf_macros-0.11.3 | MIT | yes |
| phf_shared-0.11.3 | MIT | yes |
| pin-project-lite-0.2.16 | Apache-2.0 OR MIT | yes |
| pin-utils-0.1.0 | MIT OR Apache-2.0 | yes |
| pkcs1-0.8.0-rc.4 | Apache-2.0 OR MIT | yes |
| pkcs5-0.7.1 | Apache-2.0 OR MIT | yes |
| pkcs8-0.10.2 | Apache-2.0 OR MIT | yes |
| pkcs8-0.11.0-rc.9 | Apache-2.0 OR MIT | yes |
| pkg-config-0.3.32 | MIT OR Apache-2.0 | yes |
| plist-1.8.0 | MIT | yes |
| png-0.18.0 | MIT OR Apache-2.0 | yes |
| poly1305-0.8.0 | Apache-2.0 OR MIT | yes |
| polyval-0.6.2 | Apache-2.0 OR MIT | yes |
| portable-atomic-1.13.0 | Apache-2.0 OR MIT | yes |
| powerfmt-0.2.0 | MIT OR Apache-2.0 | yes |
| ppv-lite86-0.2.21 | MIT OR Apache-2.0 | yes |
| primeorder-0.13.6 | Apache-2.0 OR MIT | yes |
| proc-macro2-1.0.106 | MIT OR Apache-2.0 | yes |
| proc-macro-error2-2.0.1 | MIT OR Apache-2.0 | yes |
| proc-macro-error-attr2-2.0.0 | MIT OR Apache-2.0 | yes |
| profiling-1.0.17 | MIT OR Apache-2.0 | yes |
| profiling-procmacros-1.0.17 | MIT OR Apache-2.0 | yes |
| pxfm-0.1.27 | BSD-3-Clause OR Apache-2.0 | yes |
| qoi-0.4.1 | MIT OR Apache-2.0 | yes |
| quantette-0.5.1 | MIT OR Apache-2.0 | yes |
| quick-error-2.0.1 | MIT OR Apache-2.0 | yes |
| quick-xml-0.38.4 | MIT | yes |
| quote-1.0.43 | MIT OR Apache-2.0 | yes |
| radium-0.7.0 | MIT | yes |
| rand-0.8.5 | MIT OR Apache-2.0 | yes |
| rand-0.9.2 | MIT OR Apache-2.0 | yes |
| rand_chacha-0.3.1 | MIT OR Apache-2.0 | yes |
| rand_chacha-0.9.0 | MIT OR Apache-2.0 | yes |
| rand_core-0.10.0-rc-3 | MIT OR Apache-2.0 | yes |
| rand_core-0.6.4 | MIT OR Apache-2.0 | yes |
| rand_core-0.9.5 | MIT OR Apache-2.0 | yes |
| ratatui-0.30.0 | MIT | yes |
| ratatui-core-0.1.0 | MIT | yes |
| ratatui-crossterm-0.1.0 | MIT | yes |
| ratatui-macros-0.7.0 | MIT | yes |
| ratatui-termion-0.1.0 | MIT | yes |
| ratatui-termwiz-0.1.0 | MIT | yes |
| ratatui-widgets-0.3.0 | MIT | yes |
| rav1e-0.8.1 | BSD-2-Clause | yes |
| ravif-0.12.0 | BSD-3-Clause | yes |
| rayon-1.11.0 | MIT OR Apache-2.0 | yes |
| rayon-core-1.13.0 | MIT OR Apache-2.0 | yes |
| redox_syscall-0.5.18 | MIT | no (stub) |
| redox_users-0.5.2 | MIT | no (stub) |
| ref-cast-1.0.25 | MIT OR Apache-2.0 | yes |
| ref-cast-impl-1.0.25 | MIT OR Apache-2.0 | yes |
| r-efi-5.3.0 | MIT OR Apache-2.0 OR LGPL-2.1-or-later | no (stub) |
| regex-1.12.2 | MIT OR Apache-2.0 | yes |
| regex-automata-0.4.13 | MIT OR Apache-2.0 | yes |
| regex-syntax-0.8.8 | MIT OR Apache-2.0 | yes |
| rfc6979-0.4.0 | Apache-2.0 OR MIT | yes |
| rgb-0.8.52 | MIT | yes |
| ring-0.17.14 | Apache-2.0 AND ISC | yes |
| rsa-0.10.0-rc.12 | MIT OR Apache-2.0 | yes |
| russh-0.56.0 | Apache-2.0 | yes |
| russh-cryptovec-0.52.0 | Apache-2.0 | yes |
| russh-util-0.52.0 | Apache-2.0 | yes |
| rustc-demangle-0.1.27 | MIT OR Apache-2.0 | yes |
| rustc-hash-2.1.1 | Apache-2.0 OR MIT | yes |
| rustc_version-0.4.1 | MIT OR Apache-2.0 | yes |
| rustix-0.38.44 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| rustix-1.1.3 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | yes |
| rustversion-1.0.22 | MIT OR Apache-2.0 | yes |
| ryu-1.0.22 | Apache-2.0 OR BSL-1.0 | yes |
| safe_arch-0.9.3 | Zlib OR Apache-2.0 OR MIT | yes |
| salsa20-0.10.2 | MIT OR Apache-2.0 | yes |
| same-file-1.0.6 | Unlicense OR MIT | yes |
| scopeguard-1.2.0 | MIT OR Apache-2.0 | yes |
| scrypt-0.11.0 | MIT OR Apache-2.0 | yes |
| sec1-0.7.3 | Apache-2.0 OR MIT | yes |
| semver-1.0.27 | MIT OR Apache-2.0 | yes |
| serde-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_core-1.0.228 | MIT OR Apache-2.0 | yes |
| serdect-0.4.2 | Apache-2.0 OR MIT | yes |
| serde_derive-1.0.228 | MIT OR Apache-2.0 | yes |
| serde_json-1.0.149 | MIT OR Apache-2.0 | yes |
| serde_spanned-1.0.4 | MIT OR Apache-2.0 | yes |
| serde-value-0.7.0 | MIT | yes |
| sha1-0.10.6 | MIT OR Apache-2.0 | yes |
| sha1-0.11.0-rc.3 | MIT OR Apache-2.0 | yes |
| sha2-0.10.9 | MIT OR Apache-2.0 | yes |
| sha2-0.11.0-rc.3 | MIT OR Apache-2.0 | yes |
| sharded-slab-0.1.7 | MIT | yes |
| shlex-1.3.0 | MIT OR Apache-2.0 | yes |
| signal-hook-0.3.18 | Apache-2.0 OR MIT | yes |
| signal-hook-0.4.1 | MIT OR Apache-2.0 | yes |
| signal-hook-mio-0.2.5 | MIT OR Apache-2.0 | yes |
| signal-hook-registry-1.4.8 | MIT OR Apache-2.0 | yes |
| signal-hook-tokio-0.4.0 | MIT OR Apache-2.0 | yes |
| signature-2.2.0 | Apache-2.0 OR MIT | yes |
| signature-3.0.0-rc.6 | Apache-2.0 OR MIT | yes |
| simd-adler32-0.3.8 | MIT | yes |
| simd_helpers-0.1.0 | MIT | yes |
| simdutf8-0.1.5 | MIT OR Apache-2.0 | yes |
| siphasher-1.0.1 | MIT OR Apache-2.0 | yes |
| slab-0.4.11 | MIT | yes |
| smallvec-1.15.1 | MIT OR Apache-2.0 | yes |
| socket2-0.6.1 | MIT OR Apache-2.0 | yes |
| spin-0.9.8 | MIT | yes |
| spki-0.7.3 | Apache-2.0 OR MIT | yes |
| spki-0.8.0-rc.4 | Apache-2.0 OR MIT | yes |
| ssh-cipher-0.2.0 | Apache-2.0 OR MIT | yes |
| ssh-encoding-0.2.0 | Apache-2.0 OR MIT | yes |
| stable_deref_trait-1.2.1 | MIT OR Apache-2.0 | yes |
| static_assertions-1.1.0 | MIT OR Apache-2.0 | yes |
| strsim-0.11.1 | MIT | yes |
| strum-0.27.2 | MIT | yes |
| strum_macros-0.27.2 | MIT | yes |
| subtle-2.6.1 | BSD-3-Clause | yes |
| syn-1.0.109 | MIT OR Apache-2.0 | yes |
| syn-2.0.114 | MIT OR Apache-2.0 | yes |
| syntect-5.3.0 | MIT | yes |
| tap-1.0.1 | MIT | yes |
| terminfo-0.9.0 | WTFPL | yes |
| termion-4.0.6 | MIT | yes |
| termios-0.3.3 | MIT | yes |
| termwiz-0.23.3 | MIT | yes |
| thiserror-1.0.69 | MIT OR Apache-2.0 | yes |
| thiserror-2.0.18 | MIT OR Apache-2.0 | yes |
| thiserror-impl-1.0.69 | MIT OR Apache-2.0 | yes |
| thiserror-impl-2.0.18 | MIT OR Apache-2.0 | yes |
| thread_local-1.1.9 | MIT OR Apache-2.0 | yes |
| tiff-0.10.3 | MIT | yes |
| tikv-jemallocator-0.6.1 | MIT OR Apache-2.0 | yes |
| tikv-jemalloc-sys-0.6.1+5.3.0-1-ge13ca993e8ccb9ba9847cc330696e02839f328f7 | MIT OR Apache-2.0 | yes |
| time-0.3.45 | MIT OR Apache-2.0 | yes |
| time-core-0.1.7 | MIT OR Apache-2.0 | yes |
| time-macros-0.2.25 | MIT OR Apache-2.0 | yes |
| tls_codec-0.4.2 | Apache-2.0 OR MIT | yes |
| tls_codec_derive-0.4.2 | Apache-2.0 OR MIT | yes |
| tokio-1.49.0 | MIT | yes |
| tokio-macros-2.6.0 | MIT | yes |
| tokio-stream-0.1.18 | MIT | yes |
| tokio-util-0.7.18 | MIT | yes |
| toml-0.9.11+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_datetime-0.7.5+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_parser-1.0.6+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| toml_writer-1.0.6+spec-1.1.0 | MIT OR Apache-2.0 | yes |
| tracing-0.1.44 | MIT | yes |
| tracing-appender-0.2.4 | MIT | yes |
| tracing-attributes-0.1.31 | MIT | yes |
| tracing-core-0.1.36 | MIT | yes |
| tracing-log-0.2.0 | MIT | yes |
| tracing-subscriber-0.3.22 | MIT | yes |
| trash-5.2.5 | MIT | yes |
| twox-hash-2.1.2 | MIT | yes |
| typed-path-0.12.0 | MIT OR Apache-2.0 | yes |
| typeid-1.0.3 | MIT OR Apache-2.0 | yes |
| typenum-1.19.0 | MIT OR Apache-2.0 | yes |
| ucd-trie-0.1.7 | MIT OR Apache-2.0 | yes |
| unicode-ident-1.0.22 | (MIT OR Apache-2.0) AND Unicode-3.0 | yes |
| unicode-segmentation-1.12.0 | MIT OR Apache-2.0 | yes |
| unicode-truncate-2.0.1 | MIT OR Apache-2.0 | yes |
| unicode-width-0.2.2 | MIT OR Apache-2.0 | yes |
| universal-hash-0.5.1 | MIT OR Apache-2.0 | yes |
| untrusted-0.9.0 | ISC | yes |
| urlencoding-2.1.3 | MIT | yes |
| utf8parse-0.2.2 | Apache-2.0 OR MIT | yes |
| uuid-1.19.0 | Apache-2.0 OR MIT | yes |
| uzers-0.12.2 | MIT | yes |
| valuable-0.1.1 | MIT | no (stub) |
| vergen-9.1.0 | MIT OR Apache-2.0 | yes |
| vergen-gitcl-9.1.0 | MIT OR Apache-2.0 | yes |
| vergen-lib-9.1.0 | MIT OR Apache-2.0 | yes |
| version_check-0.9.5 | MIT OR Apache-2.0 | yes |
| v_frame-0.3.9 | BSD-2-Clause | yes |
| vtparse-0.6.2 | MIT | yes |
| walkdir-2.5.0 | Unlicense OR MIT | yes |
| wasi-0.11.1+wasi-snapshot-preview1 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasip2-1.0.2+wasi-0.2.9 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wasm-bindgen-0.2.108 | MIT OR Apache-2.0 | yes |
| wasm-bindgen-futures-0.4.58 | MIT OR Apache-2.0 | no (stub) |
| wasm-bindgen-macro-0.2.108 | MIT OR Apache-2.0 | yes |
| wasm-bindgen-macro-support-0.2.108 | MIT OR Apache-2.0 | yes |
| wasm-bindgen-shared-0.2.108 | MIT OR Apache-2.0 | yes |
| web-sys-0.3.85 | MIT OR Apache-2.0 | no (stub) |
| weezl-0.1.12 | MIT OR Apache-2.0 | yes |
| wezterm-bidi-0.2.3 | MIT AND Unicode-DFS-2016 | yes |
| wezterm-blob-leases-0.1.1 | MIT | yes |
| wezterm-color-types-0.3.0 | MIT | yes |
| wezterm-dynamic-0.2.1 | MIT | yes |
| wezterm-dynamic-derive-0.1.1 | MIT | yes |
| wezterm-input-types-0.1.0 | MIT | yes |
| which-8.0.0 | MIT | yes |
| wide-0.8.3 | Zlib OR Apache-2.0 OR MIT | yes |
| winapi-0.3.9 | MIT OR Apache-2.0 | no (stub) |
| winapi-i686-pc-windows-gnu-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| winapi-util-0.1.11 | Unlicense OR MIT | no (stub) |
| winapi-x86_64-pc-windows-gnu-0.4.0 | MIT OR Apache-2.0 | no (stub) |
| windows-0.56.0 | MIT OR Apache-2.0 | no (stub) |
| windows-0.62.2 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows-collections-0.3.2 | MIT OR Apache-2.0 | no (stub) |
| windows-core-0.56.0 | MIT OR Apache-2.0 | no (stub) |
| windows-core-0.62.2 | MIT OR Apache-2.0 | no (stub) |
| windows-future-0.3.2 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows-implement-0.56.0 | MIT OR Apache-2.0 | no (stub) |
| windows-implement-0.60.2 | MIT OR Apache-2.0 | no (stub) |
| windows-interface-0.56.0 | MIT OR Apache-2.0 | no (stub) |
| windows-interface-0.59.3 | MIT OR Apache-2.0 | no (stub) |
| windows-link-0.2.1 | MIT OR Apache-2.0 | no (stub) |
| windows-numerics-0.3.1 | MIT OR Apache-2.0 | no (stub) |
| windows-result-0.1.2 | MIT OR Apache-2.0 | no (stub) |
| windows-result-0.4.1 | MIT OR Apache-2.0 | no (stub) |
| windows-strings-0.5.1 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.52.0 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.59.0 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.60.2 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.61.2 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.53.5 | MIT OR Apache-2.0 | no (stub) |
| windows-threading-0.2.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.53.1 | MIT OR Apache-2.0 | no (stub) |
| winnow-0.7.14 | MIT | yes |
| winsafe-0.0.19 | MIT | no (stub) |
| wit-bindgen-0.51.0 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT | no (stub) |
| wyz-0.5.1 | MIT | yes |
| y4m-0.8.0 | MIT | yes |
| yazi-prebuilt-0.1.0 | MIT | yes |
| zerocopy-0.8.33 | BSD-2-Clause OR Apache-2.0 OR MIT | yes |
| zerocopy-derive-0.8.33 | BSD-2-Clause OR Apache-2.0 OR MIT | yes |
| zeroize-1.8.2 | Apache-2.0 OR MIT | yes |
| zeroize_derive-1.4.3 | Apache-2.0 OR MIT | yes |
| zmij-1.0.16 | MIT | yes |
| zune-core-0.4.12 | MIT OR Apache-2.0 OR Zlib | yes |
| zune-core-0.5.1 | MIT OR Apache-2.0 OR Zlib | yes |
| zune-inflate-0.2.54 | MIT OR Apache-2.0 OR Zlib | yes |
| zune-jpeg-0.4.21 | MIT OR Apache-2.0 OR Zlib | yes |
| zune-jpeg-0.5.11 | MIT OR Apache-2.0 OR Zlib | yes |

</details>

<details><summary>Rust crates of yazi-prebuilt: 45 built, 12 manifest-only stubs (pinned by its Cargo.lock)</summary>

| Crate | License | Built |
|---|---|---|
| adler2-2.0.0 | 0BSD OR MIT OR Apache-2.0 | yes |
| anyhow-1.0.97 | MIT OR Apache-2.0 | yes |
| base64-0.22.1 | MIT OR Apache-2.0 | yes |
| bincode-1.3.3 | MIT | yes |
| bitflags-1.3.2 | MIT OR Apache-2.0 | yes |
| cc-1.2.16 | MIT OR Apache-2.0 | yes |
| cfg-if-1.0.0 | MIT OR Apache-2.0 | yes |
| crc32fast-1.4.2 | MIT OR Apache-2.0 | yes |
| deranged-0.4.0 | MIT OR Apache-2.0 | yes |
| equivalent-1.0.2 | Apache-2.0 OR MIT | yes |
| flate2-1.1.0 | MIT OR Apache-2.0 | yes |
| fnv-1.0.7 | Apache-2.0  OR  MIT | yes |
| hashbrown-0.15.2 | MIT OR Apache-2.0 | yes |
| indexmap-2.8.0 | Apache-2.0 OR MIT | yes |
| itoa-1.0.15 | MIT OR Apache-2.0 | yes |
| libc-0.2.171 | MIT OR Apache-2.0 | no (stub) |
| linked-hash-map-0.5.6 | MIT OR Apache-2.0 | yes |
| memchr-2.7.4 | Unlicense OR MIT | yes |
| miniz_oxide-0.8.5 | MIT OR Zlib OR Apache-2.0 | yes |
| num-conv-0.1.0 | MIT OR Apache-2.0 | yes |
| once_cell-1.21.1 | MIT OR Apache-2.0 | yes |
| onig-6.4.0 | MIT | yes |
| onig_sys-69.8.1 | MIT | yes |
| pkg-config-0.3.32 | MIT OR Apache-2.0 | yes |
| plist-1.7.0 | MIT | yes |
| powerfmt-0.2.0 | MIT OR Apache-2.0 | yes |
| proc-macro2-1.0.94 | MIT OR Apache-2.0 | yes |
| quick-xml-0.32.0 | MIT | yes |
| quote-1.0.40 | MIT OR Apache-2.0 | yes |
| regex-syntax-0.8.5 | MIT OR Apache-2.0 | yes |
| ryu-1.0.20 | Apache-2.0 OR BSL-1.0 | yes |
| same-file-1.0.6 | Unlicense OR MIT | yes |
| serde-1.0.219 | MIT OR Apache-2.0 | yes |
| serde_derive-1.0.219 | MIT OR Apache-2.0 | yes |
| serde_json-1.0.140 | MIT OR Apache-2.0 | yes |
| shlex-1.3.0 | MIT OR Apache-2.0 | yes |
| syn-2.0.100 | MIT OR Apache-2.0 | yes |
| syntect-5.2.0 | MIT | yes |
| thiserror-1.0.69 | MIT OR Apache-2.0 | yes |
| thiserror-impl-1.0.69 | MIT OR Apache-2.0 | yes |
| time-0.3.40 | MIT OR Apache-2.0 | yes |
| time-core-0.1.4 | MIT OR Apache-2.0 | yes |
| time-macros-0.2.21 | MIT OR Apache-2.0 | yes |
| unicode-ident-1.0.18 | (MIT OR Apache-2.0) AND Unicode-3.0 | yes |
| walkdir-2.5.0 | Unlicense OR MIT | yes |
| winapi-util-0.1.9 | Unlicense OR MIT | no (stub) |
| windows_aarch64_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_aarch64_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnu-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_i686_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows-sys-0.59.0 | MIT OR Apache-2.0 | no (stub) |
| windows-targets-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnu-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_gnullvm-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| windows_x86_64_msvc-0.52.6 | MIT OR Apache-2.0 | no (stub) |
| yaml-rust-0.4.5 | MIT OR Apache-2.0 | yes |

</details>

<!-- inventory:end -->
