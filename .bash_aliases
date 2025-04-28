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
alias f="cd \$(find ~/ -type d \( -name node_modules -o -name .git \) -prune -o -name '*'  -type d -print | fzf)"
alias ss='xrandr --output eDP-1 --scale 0.5x0.5'

# some more ls aliases
alias la='ls -A'
alias l='ls -CF'

# add logout for terminal
alias logout='gnome-session-quit'
alias hib='sudo systemctl hibernate'

