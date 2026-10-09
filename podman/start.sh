#!/usr/bin/env bash
# podman/start.sh [--shell] [FILE…] — start the kide container (image `kide`,
# podman/Containerfile) on your ~/workspace.
#
# The host's ~/workspace (created if missing) is mounted on the container's
# WORKDIR /workspace; FILE arguments are relative to it. --shell starts fish
# instead of kide. Run as your normal user (rootless podman, not sudo): your
# host user is mapped to the image's user (KIDE_UID/KIDE_GID from
# podman/base.conf next to this script, default 1001), so files written in
# ~/workspace stay yours. kide's data and state are kept in the volume
# kide-data. TERM and SSH_CONNECTION are passed on when set (PuTTY/SSH); the
# host's proxy variables (http_proxy, https_proxy, … ) are not (--http-proxy=false).
#
# git over SSH with your host key: a running SSH agent (SSH_AUTH_SOCK, e.g.
# Pageant through PuTTY's agent forwarding) is passed in, with SELinux
# confinement off for this container (label=disable), since SELinux blocks the
# container from the host's agent socket. Your ~/.ssh/known_hosts and
# ~/.gitconfig, if present, go in read-only at home-independent paths (ssh's
# system-wide known_hosts, GIT_CONFIG_GLOBAL), so the image user's home
# doesn't matter.
set -euo pipefail

KIDE_UID=1001
KIDE_GID=1001
conf="$(dirname "$(readlink -f "$0")")/base.conf"
if [ -f "$conf" ]; then
    KIDE_UID=$(sed -n 's/^KIDE_UID=//p' "$conf")
    KIDE_GID=$(sed -n 's/^KIDE_GID=//p' "$conf")
fi

entrypoint=()
if [ "${1:-}" = --shell ]; then
    entrypoint=(--entrypoint fish)
    shift
fi

git=()
if [ -S "${SSH_AUTH_SOCK:-}" ]; then
    git+=(--security-opt label=disable
          -v "$SSH_AUTH_SOCK:/run/ssh-agent.sock" -e SSH_AUTH_SOCK=/run/ssh-agent.sock)
fi
if [ -f "$HOME/.ssh/known_hosts" ]; then
    git+=(-v "$HOME/.ssh/known_hosts:/etc/ssh/ssh_known_hosts:ro")
fi
if [ -f "$HOME/.gitconfig" ]; then
    git+=(-v "$HOME/.gitconfig:/run/gitconfig:ro" -e GIT_CONFIG_GLOBAL=/run/gitconfig)
fi

mkdir -p "$HOME/workspace"
exec podman run --rm -it --http-proxy=false -e TERM -e SSH_CONNECTION \
    --userns="keep-id:uid=$KIDE_UID,gid=$KIDE_GID" \
    "${git[@]}" \
    -v "$HOME/workspace:/workspace:Z" \
    -v kide-data:/var/lib/kide \
    "${entrypoint[@]}" kide "$@"
