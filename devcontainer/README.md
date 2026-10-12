# kide-dev: a VS Code dev container

The ibn-dev build environment (`podman/Containerfile.ibn-dev`, see
[podman/README.md](../podman/README.md)) without the terminal IDE, for VS
Code's Dev Containers extension with podman. VS Code is the editor and bash
is the shell. `devcontainer/Containerfile` is a thin layer on top of ibn-dev:
it only adds `~/.vscode-server`, owned by `KIDE_USER`, for the volume below.

What is in it, all from ibn-dev:

- the RHEL9 packages: gcc/g++, make, cmake, clangd/clang-format/clang-tidy,
  gdb, lldb (`lldb-dap`), git, perl + perl-Dumpvalue, Python 3.12 with numpy
  and pybind11, opencv, glew, glfw, gdal + gdal-libs, Qt5, libtiff, and
  `gdal-devel` 3.10.3 from `dist/`
- `build-dist.sh` with `dist/` (in `/opt/kide/dist`, on `PATH`): run once in
  the container, it builds CMake 4 (ahead of RHEL's on `PATH`), onnxruntime,
  ACE+TAO 8 + OpenDDS 3.34 (`tao_idl`, `opendds_idl`, `find_package(OpenDDS)`)
  into `/workspace/kide-dist/{bin,include,lib,lib64,share}`, that is, into
  `kide-dist/` in the mounted project on the host;
  found by the dynamic linker through `LD_LIBRARY_PATH`, and by pkg-config
  (`ACE`, `TAO`, `TAO_*`, `libonnxruntime`) through `PKG_CONFIG_PATH`;
  `~/.bashrc` sources `kide-dist/bin/kide-dist-env.sh` (`CMAKE_PREFIX_PATH`,
  `CPLUS_INCLUDE_PATH`, `LIBRARY_PATH`, `ACE_ROOT`/`TAO_ROOT`/`DDS_ROOT`)
- pip/uv config and the pip server certificate from `CONF_DIR`, and pip + uv
  in `KIDE_USER`'s `~/.local`
- `safe.directory = *` for git

Left out: kide (`podman/Containerfile.kide`: nvim, yazi, fish, tmux, fd,
fzf, lazygit, ruff/ty, neocmakelsp, shfmt, debugpy), so no Rust or Go build
and no `kide-data` volume. The ACE+TAO/OpenDDS compile (~7 min) happens
later, in the container (`build-dist.sh`).

## Build

From the repo root, with the same `podman/base.conf` as ibn-dev and kide
(`KIDE_USER`; the other args are not used here). ibn-dev first, if it is not
built yet:

    podman build --build-arg-file podman/base.conf -t ibn-dev -f podman/Containerfile.ibn-dev .
    podman build --build-arg-file podman/base.conf -t kide-dev -f devcontainer/Containerfile .

`--build-arg IBN_DEV=<image>` builds on another ibn-dev image (default
`localhost/ibn-dev`).

## Use

1. VS Code setting: `"dev.containers.dockerPath": "podman"`.
2. Copy `devcontainer/devcontainer.json` to `<project>/.devcontainer/devcontainer.json`.
   If `podman/base.conf` sets a different `KIDE_USER`/`KIDE_UID`/`KIDE_GID`,
   change `default`, `1001`, and the home path in `mounts` to match.
3. *Dev Containers: Reopen in Container*.
4. Once per project, in the container's terminal: `build-dist.sh`. This
   installs the C/C++ libraries into `kide-dist/` in the project directory
   (add it to the project's `.gitignore`). New terminals pick up
   `kide-dist-env.sh`; in the one it ran in, run
   `. /workspace/kide-dist/bin/kide-dist-env.sh` once.

What the template sets:

- The project is mounted on `/workspace` with `Z`, which relabels it for SELinux (needed on RHEL).
- `--userns=keep-id:uid=1001,gid=1001` maps your host user to `default`, so
  files written in the project stay yours. Rootless podman only.
  `updateRemoteUserUID: false`: the mapping already does this.
- `--http-proxy=false`: the host's proxy variables stay out. As a fallback, `~/.bashrc` unsets them too.
- The `kide-dev-vscode` volume on `~/.vscode-server` keeps VS Code's server
  and extensions across rebuilt containers.
- Extensions: clangd, lldb-dap, CMake Tools, Python. Their settings point at
  `/usr/bin/clangd`, `/usr/bin/lldb-dap`, `/workspace/kide-dist/bin/cmake` and
  `/usr/bin/python3.12`.

To use the image without VS Code (a shell):

    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$PWD:/workspace:Z" kide-dev bash
