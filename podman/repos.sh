#!/bin/sh
# Repo setup for podman/Containerfile, run as root in both stages before any
# dnf install. Replace this file together with podman/base.conf: whatever the
# base image needs so that dnf finds every package the Containerfile installs
# (e.g. copy in .repo files), or nothing if its repos are already set up.
#
# Rocky Linux 9 (base.conf's default): CRB (pybind11-devel) and EPEL (opencv,
# glew, glfw), standing in for the RHEL9 target's own repos.
set -eu
dnf -y install dnf-plugins-core epel-release
dnf config-manager --set-enabled crb
