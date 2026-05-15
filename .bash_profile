export VISUAL=vim
export EDITOR=vim


# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# .NET SDK (installed via dotnet-install.sh to ~/.dotnet)
if [ -d "$HOME/.dotnet" ] ; then
    export DOTNET_ROOT="$HOME/.dotnet"
    PATH="$HOME/.dotnet:$PATH"
fi

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
