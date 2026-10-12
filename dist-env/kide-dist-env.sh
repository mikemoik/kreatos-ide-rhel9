# kide-dist-env.sh — source it from bash: . PREFIX/bin/kide-dist-env.sh
# The environment for the C/C++ libraries build-dist.sh installed in PREFIX
# (the directory above this script's bin/, so it works wherever PREFIX is
# seen: /workspace/kide-dist in the container, ~/workspace/kide-dist on the
# host): to build against them (CMake, pkg-config, the compiler and linker
# with plain -lACE etc., ACE/TAO/OpenDDS's own tools) and to run what links
# them. Sourcing it twice adds nothing twice. kide-dist-env.fish is the same
# for fish.

_kide_dist_prepend() { # VAR DIR: DIR at the front of the :-list VAR, once
  local val=":${!1-}:"
  val=${val//:$2:/:}
  val=${val#:}
  val=${val%:}
  export "$1=$2${val:+:$val}"
}

KIDE_DIST_PREFIX=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export KIDE_DIST_PREFIX

# CMake 4, tao_idl, opendds_idl, … ahead of RHEL's
_kide_dist_prepend PATH "$KIDE_DIST_PREFIX/bin"
# find_package(OpenDDS/ACE/TAO/onnxruntime) without -D hints
_kide_dist_prepend CMAKE_PREFIX_PATH "$KIDE_DIST_PREFIX"
# pkg-config: ACE, TAO, TAO_* (lib) and libonnxruntime (lib64)
_kide_dist_prepend PKG_CONFIG_PATH "$KIDE_DIST_PREFIX/lib64/pkgconfig"
_kide_dist_prepend PKG_CONFIG_PATH "$KIDE_DIST_PREFIX/lib/pkgconfig"
# the compiler and linker without -I/-L: #include <ace/...>, -lACE -lTAO ...
_kide_dist_prepend CPLUS_INCLUDE_PATH "$KIDE_DIST_PREFIX/include"
_kide_dist_prepend LIBRARY_PATH "$KIDE_DIST_PREFIX/lib64"
_kide_dist_prepend LIBRARY_PATH "$KIDE_DIST_PREFIX/lib"
# the dynamic linker, for programs built without an $ORIGIN RPATH
_kide_dist_prepend LD_LIBRARY_PATH "$KIDE_DIST_PREFIX/lib64"
_kide_dist_prepend LD_LIBRARY_PATH "$KIDE_DIST_PREFIX/lib"
# ACE+TAO and OpenDDS (as their share/*/*-devel.sh): opendds_idl and MPC need
# them when run by hand; find_package(OpenDDS) does not
export ACE_ROOT=$KIDE_DIST_PREFIX/share/ace
export TAO_ROOT=$KIDE_DIST_PREFIX/share/tao
export DDS_ROOT=$KIDE_DIST_PREFIX/share/dds

unset -f _kide_dist_prepend
