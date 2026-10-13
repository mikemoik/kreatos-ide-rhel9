# ibn-dist-env.sh — source it from bash: . PREFIX/bin/ibn-dist-env.sh
# The environment for the C/C++ libraries build-dist.sh installed in PREFIX
# (the directory above this script's bin/, so it works wherever PREFIX is
# seen: /workspace/ibn-dist in the container, ~/workspace/ibn-dist on the
# host): to build against them (CMake, pkg-config, the compiler and linker
# with plain -lACE etc., ACE/TAO/OpenDDS's own tools) and to run what links
# them. Sourcing it twice adds nothing twice. ibn-dist-env.fish is the same
# for fish.

_ibn_dist_prepend() { # VAR DIR: DIR at the front of the :-list VAR, once
  local val=":${!1-}:"
  val=${val//:$2:/:}
  val=${val#:}
  val=${val%:}
  export "$1=$2${val:+:$val}"
}

IBN_DIST_PREFIX=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export IBN_DIST_PREFIX

# CMake 4, tao_idl, opendds_idl, … ahead of RHEL's
_ibn_dist_prepend PATH "$IBN_DIST_PREFIX/bin"
# find_package(OpenDDS/ACE/TAO/onnxruntime/GDAL) without -D hints
_ibn_dist_prepend CMAKE_PREFIX_PATH "$IBN_DIST_PREFIX"
# pkg-config: ACE, TAO, TAO_* (lib), libonnxruntime and gdal (lib64)
_ibn_dist_prepend PKG_CONFIG_PATH "$IBN_DIST_PREFIX/lib64/pkgconfig"
_ibn_dist_prepend PKG_CONFIG_PATH "$IBN_DIST_PREFIX/lib/pkgconfig"
# the compiler and linker without -I/-L: #include <ace/...>, -lACE -lTAO ...
_ibn_dist_prepend CPLUS_INCLUDE_PATH "$IBN_DIST_PREFIX/include"
_ibn_dist_prepend LIBRARY_PATH "$IBN_DIST_PREFIX/lib64"
_ibn_dist_prepend LIBRARY_PATH "$IBN_DIST_PREFIX/lib"
# the dynamic linker, for programs built without an $ORIGIN RPATH
_ibn_dist_prepend LD_LIBRARY_PATH "$IBN_DIST_PREFIX/lib64"
_ibn_dist_prepend LD_LIBRARY_PATH "$IBN_DIST_PREFIX/lib"
# ACE+TAO and OpenDDS (as their share/*/*-devel.sh): opendds_idl and MPC need
# them when run by hand; find_package(OpenDDS) does not
export ACE_ROOT=$IBN_DIST_PREFIX/share/ace
export TAO_ROOT=$IBN_DIST_PREFIX/share/tao
export DDS_ROOT=$IBN_DIST_PREFIX/share/dds
# GDAL's data files (its compiled-in path is the PREFIX it was built in)
export GDAL_DATA=$IBN_DIST_PREFIX/share/gdal

unset -f _ibn_dist_prepend
