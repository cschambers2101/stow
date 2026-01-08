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
alias mp3="yt-dlp -x --audio-format mp3 --audio-quality 0 '~/Music/%(title)s.%(ext)s' "
alias aac="youtube-dl -x --audio-format aac -o '~/Music/%(title)s.%(ext)s' "
alias python="python3"
alias update="update_os"
alias c="clear"
alias attach="tmux attach-session -t "
alias tnew="tmux new -s "
alias activate="source venv/bin/activate"
alias f="cd \$(find ~/ -type d \( -name node_modules -o -name .git \) -prune -o -name '*'  -type d -print | fzf)"
alias ss='xrandr --output eDP-1 --scale 0.5x0.5'
alias mkdir='mkdir -p'
alias fcp='filecopy' # alais to function in ~/.bash_functions
alias build='dotnet restore && dotnet clean && dotnet build'
alias run='dotnet run --urls http://localhost:5001'
alias watch='dotnet watch run --urls http://localhost:5001'
alias s6cmon='bash ~/.screenlayout/s6c_monitors.sh'
alias lapmon='bash ~/.screenlayout/laptop_monitor.sh'
alias ms='toggle_monitors' # alias to function in ~/.bash_functions for switching monitor layouts between s6c and laptop

# some more ls aliases
alias la='ls -A'
alias l='ls -CF'

# add logout for terminal
alias logout='gnome-session-quit'
alias hib='sudo systemctl hibernate'

# Notes
alias cn='create_note.sh' # alias to script in ~/bin to create a dated note in ~/Notes and open it in vim
alias snf='find_note_file.sh' # alias to script in ~/bin to search notes using fzf and open selected note in vim
alias snt='find_note_tag.sh' # alias to script in ~/bin to search notes by tag using fzf and open selected note in vim
