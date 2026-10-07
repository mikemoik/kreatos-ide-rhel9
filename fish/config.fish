# kreatos-ide fish config (container shell). build.sh installs this directory
# to PREFIX/share/kreatos-ide/fish; the container's ~/.config/fish/config.fish
# sources this file. The IDE's shell helpers (aliases, functions) live here.

# PREFIX = three levels up from PREFIX/share/kreatos-ide/fish
set -l kide_prefix (path resolve (status dirname)/../../..)

# what PREFIX/bashrc does for bash: kide's executables come first, yazi uses
# the bundled config
contains -- $kide_prefix/bin $PATH; or set -gx PATH $kide_prefix/bin $PATH
set -gx YAZI_CONFIG_HOME $kide_prefix/share/kreatos-ide/yazi

# functions/: the IDE's fish functions (autoloaded, e.g. tm)
set -l kide_functions (status dirname)/functions
contains -- $kide_functions $fish_function_path
or set -g fish_function_path $kide_functions $fish_function_path

if status is-interactive
    source (status dirname)/aliases.fish
end
