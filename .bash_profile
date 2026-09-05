export VISUAL=vim
export EDITOR=vim

path_prepend() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
    esac
    PATH="$1:$PATH"
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"

if [ -d "$HOME/.dotnet" ]; then
    export DOTNET_ROOT="$HOME/.dotnet"
    path_prepend "$HOME/.dotnet"
fi

path_prepend "$HOME/.cargo/bin"
path_prepend "$HOME/go/bin"

export PATH
unset -f path_prepend

if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    # shellcheck source=.bashrc
    . "$HOME/.bashrc"
fi
