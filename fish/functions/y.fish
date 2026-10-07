# y [ARGS]: yazi; quitting with Q cds the shell to the directory yazi was in
# (yazi writes it to --cwd-file; q quits without it, see yazi/keymap.toml)
function y --wraps=yazi --description 'yazi; Q quits into its directory'
    set -l tmp (mktemp -t yazi-cwd.XXXXXX)
    yazi $argv --cwd-file=$tmp
    if read -z cwd <$tmp; and test -n "$cwd"; and test "$cwd" != "$PWD"
        builtin cd -- $cwd
    end
    rm -f -- $tmp
end
