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

    podman run --rm -it -v "$PWD:/work:Z" -v kide-data:/root/.local --entrypoint bash kide

A short alias for `~/.bashrc`:

    alias kide='podman run --rm -it -v "$PWD:/work:Z" -v kide-data:/root/.local kide'

## Limits

- Only the mounted directory is visible; paths outside it (`../other`,
  `~/notes`) are not.
- No clipboard tool in the image (no X/Wayland socket): copying out of kide
  only works where Neovim falls back to OSC 52 and the terminal allows it.
- C/C++ builds and debugging run inside the container with RHEL9's compilers,
  not the host's.
- Updating: pull/checkout the new version and build the image again.
