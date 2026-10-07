# kide in a podman container

kide without installing anything on the host except podman: the image is
UBI9 with kide built into `/opt/kide` and the RHEL packages it uses (python3,
git, file, gcc/g++, make, cmake, clangd/clang-format/clang-tidy, gdb, lldb).
The build stage is `build.sh`, as on a normal install; the Rust and Go
toolchains stay in the build stage and are not in the final image.

## Build

The last argument of `podman build` is the repo directory (the build
context); the Containerfile copies all of it into the image and runs
`build.sh`. From an unpacked tarball or a git checkout, run it in the repo's
top directory (where `install.sh` and `podman/` are; ~5–10 min):

    tar -xzf kreatos-ide-rhel9-main.tar.gz
    cd kreatos-ide-rhel9-main
    podman build -t kide -f podman/Containerfile .

Without a checkout, straight from GitHub (no curl needed):

    podman build -t kide -f podman/Containerfile https://github.com/mikemoik/kreatos-ide-rhel9.git

The build stage has two layers: the compile step (`vendor/`, `manifest/`,
`scripts/`, `build.sh`) and the config step (`config/`, `yazi/`, `fish/`, run
with `build.sh --no-build`). After a change to the config only, podman reuses
the compiled layer and the rebuild takes seconds; a change to the compile
inputs rebuilds everything (~10–15 min).

The `dnf install` steps need the RHEL/UBI repos; `build.sh` itself never
touches the network. The build context is what git tracks (`.containerignore`
leaves out `.git` and `vendor.staging`).

## Run

Edit the current directory:

    podman run --rm -it -v "$PWD:/work:Z" -v kide-data:/root/.local kide
    podman run --rm -it -v "$PWD:/work:Z" -v kide-data:/root/.local kide src/main.py

- `-v "$PWD:/work:Z"`: the project, the container's working directory. `:Z`
  relabels it for SELinux (needed on RHEL).
- `-v kide-data:/root/.local`: kide's data and state (undo history, shada,
  sessions) survive the container. Leave it out for a throwaway session.
- Use **rootless** podman (your normal user, not `sudo podman`): root inside
  the container is your own user on the host, so files kide writes into the
  project stay yours.

A shell in the container (lazygit, yazi, cmake, gdb, … are all on `PATH`):

    podman run --rm -it -v "$PWD:/work:Z" -v kide-data:/root/.local --entrypoint fish kide

## Shell: fish

fish is the container's default shell: `$SHELL` and root's login shell, so
terminals opened in kide (`:terminal`, the terminal window) and shells started
from lazygit or yazi are fish too. It is built from source by `build.sh`, like the other tools
(a normal install gets `PREFIX/bin/fish` too; its login shell stays bash).

The IDE's shell helpers live in the repo's `fish/` directory, installed to
`/opt/kide/share/kreatos-ide/fish` and sourced from root's
`~/.config/fish/config.fish`:

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
`~/.local/share/fish`, so it survives the container with the `kide-data`
volume. `--entrypoint bash` still works as a fallback.

fish is built without its man pages (they need Sphinx), so builtins' `--help`
has no page to show; `help` points to <https://fishshell.com/docs/current/>.

A short alias for `~/.bashrc`:

    alias kide='podman run --rm -it -v "$PWD:/work:Z" -v kide-data:/root/.local kide'

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
     "mounts": ["source=kide-data,target=/root/.local,type=volume"],
     "remoteUser": "root"
   }
   ```

- `Z` in `workspaceMount` relabels the project for SELinux (needed on RHEL),
  like `:Z` in `podman run`.
- With rootless podman, root in the container is your own user, so files VS
  Code writes into the project stay yours; no `--userns=keep-id` needed (the
  image runs as root).
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
  needs no RHEL repo beyond UBI's.
- Updating: pull/checkout the new version and build the image again.
