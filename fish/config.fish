# kreatos-ide fish config (container shell). build-ide.sh installs this directory
# to PREFIX/share/kreatos-ide/fish; the container's ~/.config/fish/config.fish
# sources this file. The IDE's shell helpers (aliases, functions) live here.

# PREFIX = three levels up from PREFIX/share/kreatos-ide/fish
set -l kide_prefix (path resolve (status dirname)/../../..)

# what PREFIX/bashrc does for bash: kide's executables come first, yazi uses
# the bundled config
contains -- $kide_prefix/bin $PATH; or set -gx PATH $kide_prefix/bin $PATH
set -gx YAZI_CONFIG_HOME $kide_prefix/share/kreatos-ide/yazi

# ACE+TAO and OpenDDS in PREFIX (as their share/*/*-devel.sh): opendds_idl and
# MPC need them when run by hand; find_package(OpenDDS) does not
set -gx ACE_ROOT $kide_prefix/share/ace
set -gx TAO_ROOT $kide_prefix/share/tao
set -gx DDS_ROOT $kide_prefix/share/dds

# CMake and the compiler find the libraries in PREFIX without -D/-I hints
set -gx CMAKE_PREFIX_PATH $kide_prefix
set -gx CPLUS_INCLUDE_PATH $kide_prefix/include

# functions/: the IDE's fish functions (autoloaded, e.g. tm)
set -l kide_functions (status dirname)/functions
contains -- $kide_functions $fish_function_path
or set -g fish_function_path $kide_functions $fish_function_path

if status is-interactive
    source (status dirname)/aliases.fish
end
