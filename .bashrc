# shellcheck shell=bash
case $- in
    *i*) ;;
    *) return ;;
esac

HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend checkwinsize

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then eval "$(dircolors -b ~/.dircolors)"; else eval "$(dircolors -b)"; fi
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

case "$TERM" in
    xterm*|rxvt*) PS1="\[\e]0;\u@\h: \w\a\]\u@\h:\w\$ " ;;
    *)            PS1='\u@\h:\w\$ ' ;;
esac

# shellcheck source=.bash_aliases
[ -f ~/.bash_aliases ] && . ~/.bash_aliases
# shellcheck source=.bash_functions
[ -f ~/.bash_functions ] && . ~/.bash_functions
if [ "${XDG_SESSION_TYPE:-}" = x11 ] && [ -f ~/.bash_x11 ]; then
    # shellcheck source=.bash_x11
    . ~/.bash_x11
fi

if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"

for _nvm in "$HOME/.nvm" "$HOME/.config/nvm"; do
    if [ -s "$_nvm/nvm.sh" ]; then
        export NVM_DIR="$_nvm"
        # shellcheck source=/dev/null
        . "$_nvm/nvm.sh"
        # shellcheck source=/dev/null
        [ -s "$_nvm/bash_completion" ] && . "$_nvm/bash_completion"
        break
    fi
done
unset _nvm
