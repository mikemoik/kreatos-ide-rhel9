# tm NAME: attach to the tmux session NAME, or create it first: one window
# split top/bottom, the lower pane a third of the height, focus in the upper.
function tm --description 'attach to tmux session NAME, or create it (top/bottom split)'
    if test (count $argv) -ne 1
        echo "usage: tm <name>" >&2
        return 1
    end
    set -l name $argv[1]
    # =NAME: exact session name (no prefix match); NAME: = its active pane
    if not tmux has-session -t "=$name" 2>/dev/null
        tmux new-session -d -s $name; or return
        tmux split-window -v -l 33% -t "=$name:"
        tmux select-pane -U -t "=$name:"
    end
    if set -q TMUX
        tmux switch-client -t "=$name"
    else
        tmux attach-session -t "=$name"
    end
end
