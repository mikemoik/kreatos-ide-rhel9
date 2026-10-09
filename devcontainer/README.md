# kide-dev: a VS Code dev container

The toolchain of the kide podman image (`podman/Containerfile`) without
the terminal IDE, for VS Code's Dev Containers extension with podman. VS Code
is the editor and bash is the shell.

What is in it, the same as in `kide`:

- the RHEL9 packages: gcc/g++, make, cmake, clangd/clang-format/clang-tidy,
  gdb, lldb (`lldb-dap`), git, perl + perl-Dumpvalue, Python 3.12 with numpy
  and pybind11, opencv, glew, glfw, gdal + gdal-libs, Qt5, libtiff, and
  `gdal-devel` 3.10.3 from `dist/`
- in `/opt/kide` (built by `build-dist.sh`, the same step as in the kide
  image): CMake 4 (ahead of RHEL's on `PATH`), onnxruntime, ACE+TAO 8 + OpenDDS
  3.34 (`tao_idl`, `opendds_idl`, `find_package(OpenDDS)`); found by the
  dynamic linker through `/etc/ld.so.conf.d/kide.conf`, and by pkg-config
  (`ACE`, `TAO`, `TAO_*`, `libonnxruntime`) through `PKG_CONFIG_PATH`; `~/.bashrc` sets
  `CMAKE_PREFIX_PATH=/opt/kide` and `CPLUS_INCLUDE_PATH=/opt/kide/include`
- pip/uv config and the pip server certificate from `CONF_DIR`, and pip + uv
  in `KIDE_USER`'s `~/.local`
- `safe.directory = *` for git

Left out: nvim/kide, yazi, fish, tmux, fd, fzf, lazygit, ruff/ty,
neocmakelsp, shfmt, debugpy. With them gone, the build stage needs no Rust
or Go and the image has no `kide-data` volume. The ACE+TAO/OpenDDS compile
still takes most of the build time.

## Build

From the repo root, with the same `podman/base.conf` as the kide image
(base image, repos, `KIDE_USER`, pip index):

    podman build --build-arg-file podman/base.conf -t kide-dev -f devcontainer/Containerfile .

## Use

1. VS Code setting: `"dev.containers.dockerPath": "podman"`.
2. Copy `devcontainer/devcontainer.json` to `<project>/.devcontainer/devcontainer.json`.
   If `podman/base.conf` sets a different `KIDE_USER`/`KIDE_UID`/`KIDE_GID`,
   change `default`, `1001`, and the home path in `mounts` to match.
3. *Dev Containers: Reopen in Container*.

What the template sets:

- The project is mounted on `/workspace` with `Z`, which relabels it for SELinux (needed on RHEL).
- `--userns=keep-id:uid=1001,gid=1001` maps your host user to `default`, so
  files written in the project stay yours. Rootless podman only.
  `updateRemoteUserUID: false`: the mapping already does this.
- `--http-proxy=false`: the host's proxy variables stay out. As a fallback, `~/.bashrc` unsets them too.
- The `kide-dev-vscode` volume on `~/.vscode-server` keeps VS Code's server
  and extensions across rebuilt containers.
- Extensions: clangd, lldb-dap, CMake Tools, Python. Their settings point at
  `/usr/bin/clangd`, `/usr/bin/lldb-dap`, `/opt/kide/bin/cmake` and
  `/usr/bin/python3.12`.

To use the image without VS Code (a shell):

    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$PWD:/workspace:Z" kide-dev bash
