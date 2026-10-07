#!/usr/bin/env bash
# install.sh [--no-build] [PREFIX] — the whole install in one call:
#
#   curl -fsSL https://raw.githubusercontent.com/mikemoik/kreatos-ide-rhel9/main/install.sh | bash
#   curl -fsSL …/install.sh | bash -s -- --no-build   # config only, see build.sh
#   ./install.sh [--no-build] [PREFIX]                 # from a checkout (no download)
#
#   1. installs the missing RHEL packages (dnf; asks for the sudo password)
#   2. piped from curl: downloads the repo tarball ($KIDE_TARBALL) to a temp dir
#   3. builds kreatos-ide offline into PREFIX (build.sh, default ~/.local/kreatos-ide);
#      with --no-build only refreshes plugins, config, launcher and bashrc
#   4. copies the sample projects (test/proj) to ~/kide-samples, if not there yet
#   5. starts a new shell in which `kide` is on PATH
set -euo pipefail

KIDE_TARBALL=${KIDE_TARBALL:-https://github.com/mikemoik/kreatos-ide-rhel9/archive/refs/heads/main.tar.gz}

# build toolchain, tar (download), git (gitsigns, lazygit), file (yazi), the
# C/C++ tools kide uses from RHEL, and libevent/ncurses headers (tmux build)
PKGS=(gcc make cmake python3 rust-toolset golang findutils diffutils tar
      git-core gcc-c++ clang-tools-extra gdb lldb file libevent-devel ncurses-devel)

log() { printf '\033[1m==> %s\033[0m\n' "$*"; }

# everything runs inside main, so bash has read the whole script before any
# command (sudo, dnf) can read from stdin when it is piped from curl
main() {
  local missing=() p src tmp=
  for p in "${PKGS[@]}"; do rpm -q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if ((${#missing[@]})); then
    log "installing RHEL packages: ${missing[*]}"
    if ((EUID == 0)); then dnf -y install "${missing[@]}"
    else sudo dnf -y install "${missing[@]}" </dev/tty
    fi
  fi

  src=$(dirname "${BASH_SOURCE[0]:-}")
  if [ ! -f "$src/build.sh" ]; then
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" EXIT
    log "downloading $KIDE_TARBALL"
    curl -fL "$KIDE_TARBALL" | tar -xz -C "$tmp" --strip-components=1
    src=$tmp
  fi

  "$src/build.sh" "$@"

  # sample projects to try kide on; never overwrites an existing copy
  if [ ! -e "$HOME/kide-samples" ]; then
    log "sample projects: ~/kide-samples"
    cp -r "$src/test/proj" "$HOME/kide-samples"
  fi

  # a script cannot change its caller's PATH: replace it with a new shell that
  # reads ~/.bashrc (interactive terminals only)
  if [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then
    [ -n "$tmp" ] && rm -rf "$tmp"
    log "new shell: run kide (exit returns to the previous shell)"
    exec bash -i </dev/tty
  fi
}

main "$@"
