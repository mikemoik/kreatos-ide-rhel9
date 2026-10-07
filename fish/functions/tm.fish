# tm NAME: attach to the tmux session NAME, or create it first: one window
# split top/bottom, the lower (helper) pane 23 % of the height (the ratio of
# misw's tmuxinator `ait` layout, 53:16 rows), focus in the upper. Like that
# layout, the ratio is applied once, at creation; tmux spreads rows added by a
# later resize over both panes.
function tm --description 'attach to tmux session NAME, or create it (top/bottom split)'
    if test (count $argv) -ne 1
        echo "usage: tm <name>" >&2
        return 1
    end
    set -l name $argv[1]
    # =NAME: exact session name (no prefix match); NAME: = its active pane
    if not tmux has-session -t "=$name" 2>/dev/null
        # create it at the terminal's size: a detached session starts at
        # 80x24, and the split would be rounded at that size
        tmux new-session -d -s $name -x $COLUMNS -y $LINES; or return
        tmux split-window -v -l 23% -t "=$name:"
        tmux select-pane -U -t "=$name:"
    end
    if set -q TMUX
        tmux switch-client -t "=$name"
    else
        tmux attach-session -t "=$name"
    end
end
