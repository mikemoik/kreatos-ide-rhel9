# kreatos-ide aliases (interactive fish only; sourced by config.fish)

alias vi="kide"
alias lg="lazygit"
alias ll="ls -alh"
# pick a file with fzf (preview: its first lines) and open it in kide
alias ff='kide (fzf --preview="head -n 200 {}")'
# pick an exported variable with fzf and copy it (fish_clipboard_copy: OSC 52
# in the container; needs a terminal that supports it, PuTTY does not)
alias ffex='export | fzf | fish_clipboard_copy'
