# kide's prompt: misw's mainframe starship prompt (~/.config/starship.toml)
# in plain fish, no starship binary. Same layout:
#   <blank line>
#   <dir> <branch> <git status><venv><fish icon> ❯
# - dir bold cyan: last 2 parts, "…/" when cut; inside a git repo the path
#   starts at the repo root; 🔒 when not writable
# - branch italic cyan; status cyan: conflicted, modified, "?" untracked
#   (starship's $all_status with misw's symbols; ahead/behind are not in
#   that format either)
# - venv only when one is active (starship also shows "()" in any Python dir)
# - ❯ bold cyan, ✗ bold red after a failed command
# The icons need a Nerd Font (Ghostty, the PuTTY session's font).
function fish_prompt
    set -l last_status $status

    # add_newline: a blank line before every prompt but the first
    if set -q __kide_prompt_drawn
        echo
    else
        set -g __kide_prompt_drawn 1
    end

    # directory: ~ for home; in a repo, relative to (and including) its root
    set -l root (command git rev-parse --show-toplevel 2>/dev/null)
    set -l dir (string replace -r -- '^'(string escape --style=regex -- $HOME)'(?=/|$)' '~' $PWD)
    if test -n "$root"
        set dir (path basename -- $root)(string replace -- $root '' $PWD)
    end
    set -l parts (string split -n / -- $dir)
    if test (count $parts) -gt 2
        set dir '…/'(string join / -- $parts[-2..-1])
    end
    set_color --bold cyan
    echo -n $dir
    if not test -w .
        set_color red
        echo -n '🔒'
    end
    set_color normal
    echo -n ' '

    # git branch + status
    if test -n "$root"
        set_color --italics cyan
        echo -n (command git symbolic-ref --short -q HEAD; or echo HEAD)
        set_color normal
        echo -n ' '
        set -l st (command git status --porcelain=v2 2>/dev/null)
        set_color cyan
        string match -q -r '^u ' -- $st; and echo -n ' '
        string match -q -r '^[12] .M' -- $st; and echo -n ' '
        string match -q -r '^\? ' -- $st; and echo -n '? '
    end

    # python venv
    if set -q VIRTUAL_ENV
        set_color yellow
        echo -n ' '
        set_color green
        echo -n '('(path basename -- $VIRTUAL_ENV)')'
    end

    # shell indicator + character
    set_color --bold white
    # starship's shell module adds a space after the indicator's own one
    echo -n \U000f023a'  '
    if test $last_status -eq 0
        set_color --bold cyan
        echo -n '❯'
    else
        set_color --bold red
        echo -n '✗'
    end
    set_color normal
    echo -n ' '
end
