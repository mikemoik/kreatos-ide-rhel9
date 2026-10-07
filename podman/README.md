# kide in a podman container

kide without installing anything on the host except podman: the image is
Rocky Linux 9 (RHEL9-compatible) with kide built into `/opt/kide` and the RHEL
packages it uses (python3, git, file, gcc/g++, make, cmake,
clangd/clang-format/clang-tidy, gdb, lldb), plus what C/C++ projects build
against: CMake 4, onnxruntime, ACE+TAO and OpenDDS in `/opt/kide` (from
`dist/`), and from CRB/EPEL perl + perl-Dumpvalue, Python 3.12 with numpy and
pybind11, opencv, glew, glfw. pip (newest) and uv for Python 3.12 are
pip-installed by the image's user (`KIDE_USER`) into its `~/.local`; root
installs nothing with pip, it only sets up their config and certificate
system-wide. Not UBI9: UBI lacks packages the EPEL ones
depend on (Qt5, gdal, protobuf for opencv; GL libraries for glew/glfw).
The build stage is `build.sh`, as on a normal install; the Rust and Go
toolchains stay in the build stage and are not in the final image.

## Build

The last argument of `podman build` is the repo directory (the build
context); the Containerfile copies all of it into the image and runs
`build.sh`. From an unpacked tarball or a git checkout, run it in the repo's
top directory (where `install.sh` and `podman/` are; ~5–10 min):

    tar -xzf kreatos-ide-rhel9-main.tar.gz
    cd kreatos-ide-rhel9-main
    podman build --build-arg-file podman/base.conf -t kide -f podman/Containerfile .

Without a checkout, straight from GitHub (no curl needed):

    podman build --build-arg BASE=docker.io/rockylinux/rockylinux:9 --build-arg CONF_DIR=podman/conf --build-arg KIDE_USER=default --build-arg KIDE_UID=1001 --build-arg KIDE_GID=1001 -t kide -f podman/Containerfile https://github.com/kreatos/kreatos-ide-rhel9.git

The build stage has two layers: the compile step (`vendor/`, `dist/`, `manifest/`,
`scripts/`, `build.sh`) and the config step (`config/`, `yazi/`, `fish/`, run
with `build.sh --no-build`). After a change to the config only, podman reuses
the compiled layer and the rebuild takes seconds; a change to the compile
inputs rebuilds everything (~10–15 min).

### Libraries: no LD_LIBRARY_PATH

`/etc/ld.so.conf.d/kide.conf` lists `/opt/kide/lib` (ACE, TAO, OpenDDS) and
`/opt/kide/lib64` (onnxruntime), so every program in the container finds
them, also binaries built without an RPATH (plain `g++ -L… -l…`, or
`cmake --install`ed elsewhere). No `LD_LIBRARY_PATH` is set.

### Another base image

The Containerfile names no base image and sets up no repos itself;
`podman/base.conf` and the files in its `CONF_DIR` do, and only they change for another base (e.g. a company RHEL9 image
with its own dnf repos):

- `podman/base.conf`: `BASE=<image>`, used by both stages and read with
  `--build-arg-file` (podman ≥ 4.7). Default: `docker.io/rockylinux/rockylinux:9`.
  Without the file, `--build-arg BASE=<image>`; with neither, the build stops
  (no default).
- `CONF_DIR` in `podman/base.conf` (default `podman/conf`, relative to the
  repo root): files copied into the image — `repos.sh` (below), `ubi.repo` to
  `/etc/yum.repos.d/` (both stages, before any `dnf install`), and in the
  runtime stage, system-wide as root:
  - `pip.conf` to `/etc/pip.conf` (e.g. `[global]` `index-url = …`)
  - `uv.toml` to `/etc/uv/uv.toml`; uv does not read `pip.conf`, so the index
    goes here too, e.g. `[[index]]` `url = "https://<mirror>/simple"`
    `default = true`
  - `machine.crt` is the **client certificate** (mTLS: certificate and its
    private key in one PEM file; the build stops if the key is missing). It
    does not go into the trust store: `KIDE_USER` keeps it as
    `~/.pip/machine.crt` (mode 600), and its fish and bash config set
    `PIP_CLIENT_CERT` (pip) and `SSL_CLIENT_CERT` (uv, which has no
    `uv.toml` setting for it) to it, so `pip.conf` needs no `client-cert`
    line. Empty: no client certificate.
  - every other `*.crt` is a **CA** (PEM, also a chain with several
    certificates, or DER) and goes into the system trust store
    (`/etc/pki/ca-trust/source/anchors/kide-<name>.pem`, `update-ca-trust`).
    The build checks that each certificate is in
    `/etc/pki/tls/certs/ca-bundle.crt` and stops if one is not, or if such a
    file holds a private key (a client certificate under another name) or no
    certificate. `PIP_CERT` and `SSL_CERT_FILE` point pip and uv (and
    Python's `ssl`) at that bundle, so no `cert =` line is needed; git and
    curl use it anyway. Empty files and no `*.crt` at all add nothing.

  Then `KIDE_USER` runs `python3.12 -m pip install --user --upgrade pip uv`
  with that config and the client certificate. `podman/conf` holds empty
  placeholders; point `CONF_DIR` at a directory with the real ones (it has
  to be inside the build context).
- `$CONF_DIR/repos.sh` (`podman/conf/repos.sh`): runs as root in both stages before any `dnf install`.
  Default: enables CRB and EPEL (Rocky's stand-in for the target repos).
  Replace it with whatever the base needs so dnf finds every package the
  Containerfile installs (e.g. copying `.repo` files into
  `/etc/yum.repos.d/`), or with an empty script if the base is ready as is.
- `KIDE_USER`, `KIDE_UID`, `KIDE_GID` in `podman/base.conf` (default
  `default`, 1001, 1001): the user the image runs as. Every step that
  installs or writes system files runs as root (`USER root` at the start of
  both stages, also when the base image defaults to another user); the last
  step switches to `KIDE_USER`. A base image that already has that user
  (e.g. `default` in Red Hat's application images) keeps it; set
  `KIDE_UID`/`KIDE_GID` to its uid/gid then (`podman run --rm <base> id default`).
  Otherwise it is created with them. The run commands below map you to it
  with `--userns=keep-id:uid=<KIDE_UID>,gid=<KIDE_GID>`: change the numbers
  there too if you change them here.

The `dnf install` steps need those repos and the `pip install` step PyPI; `build.sh` itself never touches the network. The build context is what git tracks (`.containerignore`
leaves out `.git` and `vendor.staging`).

## Run

Edit the current directory:

    podman run --rm -it --userns=keep-id:uid=1001,gid=1001 -v "$PWD:/work:Z" -v kide-data:/var/lib/kide kide
    podman run --rm -it --userns=keep-id:uid=1001,gid=1001 -v "$PWD:/work:Z" -v kide-data:/var/lib/kide kide src/main.py

- `-v "$PWD:/work:Z"`: the project, the container's working directory. `:Z`
  relabels it for SELinux (needed on RHEL).
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

A shell in the container (lazygit, yazi, cmake, gdb, … are all on `PATH`):

    podman run --rm -it --userns=keep-id:uid=1001,gid=1001 -v "$PWD:/work:Z" -v kide-data:/var/lib/kide --entrypoint fish kide

## Shell: fish

fish is the container's default shell: `$SHELL` and the login shell of
`KIDE_USER` and root, so
terminals opened in kide (`:terminal`, the terminal window) and shells started
from lazygit or yazi are fish too. It is built from source by `build.sh`, like the other tools
(a normal install gets `PREFIX/bin/fish` too; its login shell stays bash).

The IDE's shell helpers live in the repo's `fish/` directory, installed to
`/opt/kide/share/kreatos-ide/fish` and sourced from `~/.config/fish/config.fish`
(of `KIDE_USER` and root):

- `config.fish`: kide's `bin` first on `PATH`, `YAZI_CONFIG_HOME`
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

    alias kide='podman run --rm -it --userns=keep-id:uid=1001,gid=1001 -v "$PWD:/work:Z" -v kide-data:/var/lib/kide kide'

## VS Code dev container

The image also works as a VS Code dev container (Dev Containers extension)
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
     "workspaceMount": "source=${localWorkspaceFolder},target=/work,type=bind,Z",
     "workspaceFolder": "/work",
     "mounts": ["source=kide-data,target=/var/lib/kide,type=volume"],
     "runArgs": ["--userns=keep-id:uid=1001,gid=1001"],
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
- tmux (3.7c) is built from source by `build.sh`, like the other tools; it
  needs only base packages (libevent, ncurses).
- Updating: pull/checkout the new version and build the image again.
