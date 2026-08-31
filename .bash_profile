export VISUAL=vim
export EDITOR=vim


# Prepend a directory to PATH, but only if it exists AND is not already there.
#
# The second test is the fix for a real duplication: every addition below used
# to prepend unconditionally, so each re-source of this file stacked another
# copy. $HOME/.local/bin had accumulated THREE entries in a normal session.
# Harmless in effect, but it makes PATH unreadable and hides genuine problems.
path_prepend() {
    [ -d "$1" ] || return 0
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
    esac
    PATH="$1:$PATH"
}

# user's private bins
path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"

# .NET SDK (installed via dotnet-install.sh to ~/.dotnet)
if [ -d "$HOME/.dotnet" ] ; then
    export DOTNET_ROOT="$HOME/.dotnet"
    path_prepend "$HOME/.dotnet"
fi

# Rust / cargo. `cargo install` drops binaries here -- rmpc, the terminal MPD
# client. rustup writes ~/.cargo/env to do this job, but a bare `cargo install`
# never creates that file, so nothing added the directory and the binary sat
# installed-but-unreachable with no error to explain why.
path_prepend "$HOME/.cargo/bin"

# Go. `go install` drops binaries here -- mpd-mpris, the bridge that puts MPD
# on MPRIS so playerctl and the shell's media widget can see it. Exactly the
# same silent failure as cargo above, and found at the same time.
path_prepend "$HOME/go/bin"

export PATH
unset -f path_prepend

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
