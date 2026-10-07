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
# kide-data. TERM and SSH_CONNECTION are passed on when set (PuTTY/SSH).
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

mkdir -p "$HOME/workspace"
exec podman run --rm -it -e TERM -e SSH_CONNECTION \
    --userns="keep-id:uid=$KIDE_UID,gid=$KIDE_GID" \
    -v "$HOME/workspace:/workspace:Z" \
    -v kide-data:/var/lib/kide \
    "${entrypoint[@]}" kide "$@"
