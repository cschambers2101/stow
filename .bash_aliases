# aliases
alias ll="ls -lhA"
alias cd..="cd .."
alias here="find . -name "
alias df="df -Tha --total"
alias du="du -ach | sort -h"
alias free="free -mt"
alias psg="ps aux | grep -v grep | grep -i -e VSZ -e"
alias mkdir="mkdir -pv"
alias wget="wget -c"
alias myip="curl http://ipecho.net/plain; echo"
alias mp3="youtube-dl -x --audio-format mp3 -o '~/Music/%(title)s.%(ext)s' "
alias aac="youtube-dl -x --audio-format aac -o '~/Music/%(title)s.%(ext)s' "
alias python="python3"
alias update="update_os"
alias c="clear"
alias attach="tmux attach-session -t "
alias tnew="tmux new -s "
alias activate="source venv/bin/activate"
alias projectroom="ssh -i ~/.ssh/id_ed25519 craigchambers@10.1.23.23"

# some more ls aliases
alias la='ls -A'
alias l='ls -CF'

# add logout for terminal
logout='gnome-session-quit'
hib='sudo systemctl hibernate'

