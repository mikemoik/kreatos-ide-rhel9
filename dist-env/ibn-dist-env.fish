# ibn-dist-env.fish — source it from fish: source PREFIX/bin/ibn-dist-env.fish
# The environment for the C/C++ libraries build-dist.sh installed in PREFIX
# (the directory above this script's bin/, so it works wherever PREFIX is
# seen: /workspace/ibn-dist in the container, ~/workspace/ibn-dist on the
# host): to build against them (CMake, pkg-config, the compiler and linker
# with plain -lACE etc., ACE/TAO/OpenDDS's own tools) and to run what links
# them. Sourcing it twice adds nothing twice. ibn-dist-env.sh is the same
# for bash.

set -l p (path resolve (status dirname)/..)
set -gx IBN_DIST_PREFIX $p

# VAR DIR…: the DIRs at the front of the path variable VAR, each once
function __ibn_dist_prepend -a var
    set -l dirs $argv[2..]
    set -l rest
    for d in $$var
        contains -- $d $dirs; or set -a rest $d
    end
    set -gx $var $dirs $rest
end

# CMake 4, tao_idl, opendds_idl, … ahead of RHEL's
__ibn_dist_prepend PATH $p/bin
# find_package(OpenDDS/ACE/TAO/onnxruntime/GDAL) without -D hints
__ibn_dist_prepend CMAKE_PREFIX_PATH $p
# pkg-config: ACE, TAO, TAO_* (lib), libonnxruntime and gdal (lib64)
__ibn_dist_prepend PKG_CONFIG_PATH $p/lib/pkgconfig $p/lib64/pkgconfig
# the compiler and linker without -I/-L: #include <ace/...>, -lACE -lTAO ...
__ibn_dist_prepend CPLUS_INCLUDE_PATH $p/include
__ibn_dist_prepend LIBRARY_PATH $p/lib $p/lib64
# the dynamic linker, for programs built without an $ORIGIN RPATH
__ibn_dist_prepend LD_LIBRARY_PATH $p/lib $p/lib64
# ACE+TAO and OpenDDS (as their share/*/*-devel.sh): opendds_idl and MPC need
# them when run by hand; find_package(OpenDDS) does not
set -gx ACE_ROOT $p/share/ace
set -gx TAO_ROOT $p/share/tao
set -gx DDS_ROOT $p/share/dds
# GDAL's data files (its compiled-in path is the PREFIX it was built in)
set -gx GDAL_DATA $p/share/gdal

functions -e __ibn_dist_prepend
