# kide in a podman container

kide without installing anything on the host except podman, in two images.
Each is built on top of a base image (`BASE` in `podman/base.conf`, default
Rocky Linux 9, RHEL9-compatible), and each works on top of the other:

- **ibn-dev** (`Containerfile.ibn-dev`): the build environment. The RHEL
  packages (gcc/g++, make, cmake, clangd/clang-format/clang-tidy, gdb, lldb,
  git, perl + perl-Dumpvalue, Python 3.12 with numpy and pybind11, opencv,
  glew, glfw, gdal + gdal-libs, Qt5 (`qt5`), libtiff + libtiff-devel, from
  AppStream/CRB/EPEL), `gdal-devel` 3.10.3-3.fc43 as an RPM from `dist/`
  (installed with `rpm -i --nodeps`, it pins Fedora's gdal-libs build), and
  what C/C++ projects build against beyond that: CMake 4, onnxruntime,
  ACE+TAO and OpenDDS (`dist/`, built once in the container into the mounted
  `/workspace/kide-dist` with `build-dist.sh`, see
  [Libraries](#libraries-built-into-workspacekide-dist)). pip (newest) and uv
  for Python 3.12 are pip-installed by the image's user (`KIDE_USER`) into
  its `~/.local`; root installs nothing with pip, it only sets up their config
  and certificate system-wide. bash is the shell.
- **kide** (`Containerfile.kide`): kide built into `/opt/kide` by
  `build-ide.sh` in a build stage, as on a normal install (the Rust and Go
  toolchains stay in that stage), and the RHEL packages kide itself uses
  (python3, git, file, clangd/clang-format/clang-tidy, gdb, lldb). fish is the
  shell.

kide on top of ibn-dev (`--build-arg BASE=localhost/ibn-dev`) is the
complete environment: IDE plus build environment. kide on the plain base is
the IDE alone, and ibn-dev alone is a build environment without the IDE. Each
Containerfile only adds to its base, so a change to one rebuilds only that
image (and kide, when ibn-dev changed under it).

Not UBI9: UBI lacks packages the EPEL ones depend on (Qt5, gdal, protobuf for
opencv; GL libraries for glew/glfw).

## Build

The last argument of `podman build` is the repo directory (the build
context); the Containerfiles copy from it into the image. From an unpacked
tarball or a git checkout, run them in the repo's top directory (where
`install.sh` and `podman/` are). ibn-dev first (a few minutes, mostly dnf),
then kide on top of it (~5–10 min):

    tar -xzf kreatos-ide-rhel9-main.tar.gz
    cd kreatos-ide-rhel9-main
    podman build --build-arg-file podman/base.conf -t ibn-dev -f podman/Containerfile.ibn-dev .
    podman build --build-arg-file podman/base.conf --build-arg BASE=localhost/ibn-dev -t kide -f podman/Containerfile.kide .

Leave out `--build-arg BASE=…` for kide without the build environment.

Without a checkout, straight from GitHub (no curl needed):

    podman build --build-arg BASE=docker.io/rockylinux/rockylinux:9 --build-arg CONF_DIR=podman/conf --build-arg KIDE_USER=default --build-arg KIDE_UID=1001 --build-arg KIDE_GID=1001 --build-arg PIP_INDEX_URL=https://pypi.org/simple -t ibn-dev -f podman/Containerfile.ibn-dev https://github.com/kreatos/kreatos-ide-rhel9.git
    podman build --build-arg BASE=localhost/ibn-dev --build-arg CONF_DIR=podman/conf --build-arg KIDE_USER=default --build-arg KIDE_UID=1001 --build-arg KIDE_GID=1001 -t kide -f podman/Containerfile.kide https://github.com/kreatos/kreatos-ide-rhel9.git

kide's build stage has two layers, each reused until its inputs change:

1. IDE compile: nvim, parsers, tools (`build-ide.sh`, from `vendor/`,
   `manifest/`, `scripts/`; ~5 min)
2. config: `config/`, `yazi/`, `fish/` (`build-ide.sh --no-build`; seconds)

A config change rebuilds only layer 2, and an IDE or vendor change rebuilds both.
The C/C++ libraries are not compiled at image build time (next section);
`dist/`, `manifest/dist.tsv` and `build-dist.sh` are only copied into ibn-dev.

### Libraries: built into /workspace/kide-dist

ibn-dev (and so kide on top of it) contains `build-dist.sh` and `dist/` (in `/opt/kide/dist`,
`build-dist.sh` on `PATH`), not the built libraries. Run it once in the
container:

    build-dist.sh

It builds CMake 4, onnxruntime, ACE+TAO and OpenDDS into
`/workspace/kide-dist/{bin,include,lib,lib64,share}` (its default `PREFIX`
is `KIDE_DIST_PREFIX=/workspace/kide-dist`), which is the host's
`~/workspace/kide-dist`, so they stay there for every later container. The
idea is that your projects are built in the container, installed to
`/workspace`, and run on the host against these libraries. See
[C/C++ libraries](../README.md#cc-libraries) for the RPATH and RHEL-version
conditions.

With them it installs `kide-dist/bin/kide-dist-env.fish` and
`kide-dist-env.sh`, which set the environment for building against the
libraries (`CMAKE_PREFIX_PATH`, `CPLUS_INCLUDE_PATH`, `LIBRARY_PATH`,
`ACE_ROOT`/`TAO_ROOT`/`DDS_ROOT`, …). bash (ibn-dev's shell, and kide's
with `--entrypoint bash`) and kide's fish source them at start; in the shell
`build-dist.sh` ran in, source `/workspace/kide-dist/bin/kide-dist-env.sh`
(bash) or `.fish` once by hand. On the host the
same files are in `~/workspace/kide-dist/bin`.

`LD_LIBRARY_PATH` is `/workspace/kide-dist/lib:/workspace/kide-dist/lib64`
(set in the image, also for programs not started from a shell), so every program in
the container finds them, also binaries built without an RPATH. An
`ld.so.conf.d` entry would not work, because the libraries only show up in the
mount at run time, too late for `ldconfig`.

`PKG_CONFIG_PATH` is `/workspace/kide-dist/lib/pkgconfig:/workspace/kide-dist/lib64/pkgconfig`, so
`pkg-config` (and CMake's `pkg_check_modules`) finds `ACE`, `TAO`, the
`TAO_*` libraries (e.g. `TAO_Messaging`) and `libonnxruntime`.

### Another base image

The Containerfiles name no base image and set up no repos themselves;
`podman/base.conf` and the files in its `CONF_DIR` do, and only they change for another base (e.g. a company RHEL9 image
with its own dnf repos):

- `podman/base.conf`: `BASE=<image>`, the base of ibn-dev (and of kide's
  two stages when kide is built without ibn-dev), read with
  `--build-arg-file` (podman ≥ 4.7). Default: `docker.io/rockylinux/rockylinux:9`.
  Without the file, `--build-arg BASE=<image>`; with neither, the build stops
  (no default).
- `CONF_DIR` in `podman/base.conf` (default `podman/conf`, relative to the
  repo root): files copied into the image — `repos.sh` (below), `ubi.repo` to
  `/etc/yum.repos.d/` (every stage, before any `dnf install`), and in
  ibn-dev, system-wide as root:
  - `pip.conf` to `/etc/pip.conf`: `index-url` (the pip package repo) and
    `cert = /etc/pki/tls/certs/ca-bundle.crt` (the system trust store)
  - `uv.toml` to `/etc/uv/uv.toml`; uv does not read `pip.conf`, so the repo
    goes here too (`[[index]]` with `default = true`), plus
    `system-certs = true` (server certificate checked against the system
    trust store), `python-preference = "only-system"`,
    `python-downloads = "never"` and `link-mode = "copy"` (uv's cache and the
    install target are on different filesystems in the container, so
    hardlinks fail with "Failed to hardlink files")
  - `pip-server.crt`: the pip server's certificate, or the company CA that
    signed it (PEM, `BEGIN CERTIFICATE`; the build stops on anything else or
    on a private key in it). It goes into the system trust store
    (`/etc/pki/ca-trust/source/anchors/`, `update-ca-trust`), so every pip
    and uv call trusts the repo, at build time and at runtime: pip through
    `cert` in `/etc/pip.conf`, uv through `system-certs = true`.

  Then `KIDE_USER` runs `/usr/bin/python3.12 -m pip install --user --upgrade pip uv` (the dnf Python by full path: pip refuses `--user` in a venv, which some base images put first on `PATH`)
  with that config. `podman/conf` holds a
  self-signed dummy `pip-server.crt` and an empty `ubi.repo`; replace them
  with the real ones on prod. Point `CONF_DIR` at a directory with the real ones (it has
  to be inside the build context).
- `PIP_INDEX_URL` in `podman/base.conf` (default `https://pypi.org/simple`):
  the pip package repo. `pip.conf` and `uv.toml` are templates; the build
  replaces `@PIP_INDEX_URL@` in both with it (and stops if it is empty). On
  prod set the company repo here, nothing else changes.
- `$CONF_DIR/repos.sh` (`podman/conf/repos.sh`): runs as root in every stage before any `dnf install` (so on top of ibn-dev a second time, which changes nothing).
  Default: enables CRB and EPEL (Rocky's stand-in for the target repos).
  Replace it with whatever the base needs so dnf finds every package the
  Containerfiles install (e.g. copying `.repo` files into
  `/etc/yum.repos.d/`), or with an empty script if the base is ready as is.
- `KIDE_USER`, `KIDE_UID`, `KIDE_GID` in `podman/base.conf` (default
  `default`, 1001, 1001): the user the image runs as. Every step that
  installs or writes system files runs as root (`USER root` at the start of
  every stage, also when the base image defaults to another user); the last
  step switches to `KIDE_USER`. A base image that already has that user
  (e.g. `default` in Red Hat's application images) keeps it; set
  `KIDE_UID`/`KIDE_GID` to its uid/gid then (`podman run --rm <base> id default`).
  Otherwise it is created with them. The run commands below map you to it
  with `--userns=keep-id:uid=<KIDE_UID>,gid=<KIDE_GID>`: change the numbers
  there too if you change them here.

The `dnf install` steps need those repos and the `pip install` step PyPI; `build-ide.sh` itself never touches the network. The build context is what git tracks (`.containerignore`
leaves out `.git` and `vendor.staging`).

## Run

Edit your `~/workspace` (create it once on the host: `mkdir -p ~/workspace`).

`podman/start.sh` does exactly this (it creates `~/workspace` if missing,
takes the uid/gid from `podman/base.conf` and passes on `TERM` and
`SSH_CONNECTION`); `--shell` starts fish instead of kide. For git over SSH it
loads your key `~/.ssh/gitlab` into an ssh-agent for the session (asking for
its passphrase, if any) and passes the agent in (with
`--security-opt label=disable`, as SELinux blocks the agent socket otherwise),
plus `~/.ssh/known_hosts` and `~/.gitconfig` read-only; all three files must
exist:

    podman/start.sh                       # kide in ~/workspace
    podman/start.sh myproject/src/main.py # a file, relative to ~/workspace
    podman/start.sh --shell               # fish

By hand (`start.sh` also adds `-e TERM -e SSH_CONNECTION`):

    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide kide
    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide kide myproject/src/main.py

- `--http-proxy=false`: podman would otherwise copy the host's proxy
  variables (`http_proxy`, `https_proxy`, `HTTP_PROXY`, `HTTPS_PROXY`,
  `ftp_proxy`, `no_proxy`, …) into the container; kide runs without them. The
  build (`podman build`) still gets them, so dnf and pip can use the proxy.
  As a fallback, the image's fish config unsets them too (a `podman run`
  without the flag still has them in kide itself, which is not started from fish).
- `-v "$HOME/workspace:/workspace:Z"`: your `~/workspace` on the host (create it once: `mkdir -p ~/workspace`),
  mounted on `/workspace`, the container's working directory: kide and fish
  start there, whatever directory you start from. `:Z` relabels it for SELinux
  (needed on RHEL). A file argument is relative to it (e.g.
  `kide myproject/src/main.py`). fish sources every `*.fish` in
  `~/workspace/.container/fish/` (in the container
  `/workspace/.container/fish/`) last, in name order: your own fish config
  (aliases, PATH, …), kept on the host. Likewise tmux reads
  `~/workspace/.container/tmux.conf` last, if it exists, after the image's
  `/etc/tmux.conf` (mouse on).
- `-v kide-data:/var/lib/kide`: kide's data and state (undo history, shada,
  swap files, sessions, fish history) survive the container. Leave it out for
  a throwaway session. The image points `XDG_DATA_HOME`/`XDG_STATE_HOME` there
  instead of `~/.local`, so the mount point does not depend on the user's
  home.
- `--userns=keep-id:uid=1001,gid=1001`: the container runs as `KIDE_USER`
  (`default`, uid/gid 1001), not root. With **rootless** podman (your normal
  user, not `sudo podman`) this maps your host user to it, so it can write
  the project and the files it writes stay yours (podman 4.3 or newer).
  Without it, the project is owned by root inside and `default` cannot write
  it.
- Root inside for a one-off (e.g. `dnf install` to try a package): add
  `--user root` and leave out `--userns=…`; root then is you on the host.
  Not kept: the next container starts from the image again.
- git trusts every repo in the container (`safe.directory = *` in
  `/etc/gitconfig`), so it never stops with "dubious ownership", whichever
  uid the project appears as inside.

A shell in the container (lazygit, yazi, cmake, gdb, … are all on `PATH`):

    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide --entrypoint fish kide

## Shell: fish

fish is the container's default shell: `$SHELL` and the login shell of
`KIDE_USER` and root, so
terminals opened in kide (`:terminal`, the terminal window) and shells started
from lazygit or yazi are fish too. It is built from source by `build-ide.sh`, like the other tools
(a normal install gets `PREFIX/bin/fish` too; its login shell stays bash).

The IDE's shell helpers live in the repo's `fish/` directory, installed to
`/opt/kide/share/kreatos-ide/fish` and sourced from `~/.config/fish/config.fish`
(of `KIDE_USER` and root):

- `config.fish`: kide's `bin` first on `PATH`, `YAZI_CONFIG_HOME`, and
  `kide-dist-env.fish` from the libraries' prefix (`KIDE_DIST_PREFIX=/workspace/kide-dist`
  in the image) once `build-dist.sh` has installed it: `ACE_ROOT`/`TAO_ROOT`/`DDS_ROOT`,
  `CMAKE_PREFIX_PATH`, `CPLUS_INCLUDE_PATH`, `LIBRARY_PATH`
- `aliases.fish`: aliases for interactive shells

| Alias | Runs |
|---|---|
| `vi` | `kide` |
| `lg` | `lazygit` |
| `ll` | `ls -alh` |
| `ff` | pick a file with `fzf` (preview: first 200 lines), open it in `kide` |
| `ffex` | pick an exported variable with `fzf`, copy it to the clipboard (OSC 52: not in PuTTY) |

Functions (`fish/functions/`, autoloaded):

| Function | Does |
|---|---|
| `y [ARGS]` | `yazi`; quitting with `Q` cds the shell to the directory yazi was in (`q` quits without cd) |
| `fish_prompt` | the prompt: misw's mainframe starship look in plain fish (dir, git branch/status, venv, `❯`/`✗`); needs a Nerd Font for its icons |
| `tm NAME` | attach to the tmux session `NAME`, or create it: one window split top/bottom (lower helper pane 23 % of the height at creation, like the tmuxinator `ait` layout), focus in the upper pane. Inside tmux it switches to the session. |

New helpers go into `fish/` (aliases into `aliases.fish`, functions into
`functions/NAME.fish`) and the tables above;
the image has to be built again to pick them up. fish's history is in
`/var/lib/kide/share/fish` (`XDG_DATA_HOME`), so it survives the container with the `kide-data`
volume. `--entrypoint bash` still works as a fallback.

fish is built without its man pages (they need Sphinx), so builtins' `--help`
has no page to show; `help` points to <https://fishshell.com/docs/current/>.

A short alias for `~/.bashrc`:

    alias kide='podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide kide'

## VS Code dev container

For VS Code without the terminal IDE, use the `kide-dev` image instead, a
thin layer on top of ibn-dev: `devcontainer/` (see `devcontainer/README.md`).

The `kide` image itself also works as a VS Code dev container (Dev Containers extension)
with podman instead of docker. Not tested yet.

1. Point the extension at podman (VS Code settings):

       "dev.containers.dockerPath": "podman"

   (`docker-compose.yml` setups also need
   `"dev.containers.dockerComposePath": "podman-compose"`, a separate package.)

2. `.devcontainer/devcontainer.json` in the project:

   ```json
   {
     "name": "kide",
     "image": "localhost/kide",
     "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,Z",
     "workspaceFolder": "/workspace",
     "mounts": ["source=kide-data,target=/var/lib/kide,type=volume"],
     "runArgs": ["--userns=keep-id:uid=1001,gid=1001", "--http-proxy=false"],
     "containerUser": "default",
     "remoteUser": "default"
   }
   ```

- `Z` in `workspaceMount` relabels the project for SELinux (needed on RHEL),
  like `:Z` in `podman run`.
- `--userns=keep-id:…` maps your host user to `default` (as in
  `podman run`), so files VS Code writes into the project stay yours.
- VS Code replaces the image's entrypoint (`kide`) with its own command
  (`overrideCommand`); its integrated terminal gets fish (`$SHELL`).
- VS Code installs its server into each new container (`~/.vscode-server`),
  which repeats for every fresh container unless that dir is on a volume too.

## Limits

- Only the mounted directory is visible; paths outside it (`../other`,
  `~/notes`) are not.
- No clipboard tool in the image (no X/Wayland socket): copying out of kide
  only works where Neovim falls back to OSC 52 and the terminal allows it.
- C/C++ builds and debugging run inside the container with RHEL9's compilers,
  not the host's.
- tmux (3.7c) is built from source by `build-ide.sh`, like the other tools; it
  needs only base packages (libevent, ncurses).
- Updating: pull/checkout the new version and build the image again.
