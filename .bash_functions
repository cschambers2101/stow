# shellcheck shell=bash
mcd() { mkdir -p "$1" && cd "$1" || return; }

extract() {
    if [ -z "$1" ]; then
        echo "Usage: extract <archive> [archive ...]"
        return 1
    fi
    local n
    for n in "$@"; do
        if [ ! -f "$n" ]; then
            echo "'$n' - file does not exist"
            return 1
        fi
        case "${n%,}" in
            *.tar.bz2|*.tar.gz|*.tar.xz|*.tbz2|*.tgz|*.txz|*.tar) tar xvf "$n" ;;
            *.lzma) unlzma ./"$n" ;;
            *.bz2)  bunzip2 ./"$n" ;;
            *.rar)  unrar x -ad ./"$n" ;;
            *.gz)   gunzip ./"$n" ;;
            *.zip)  unzip ./"$n" ;;
            *.z)    uncompress ./"$n" ;;
            *.7z|*.arj|*.cab|*.chm|*.deb|*.dmg|*.iso|*.lzh|*.msi|*.rpm|*.udf|*.wim|*.xar) 7z x ./"$n" ;;
            *.xz)   unxz ./"$n" ;;
            *.exe)  cabextract ./"$n" ;;
            *) echo "extract: '$n' - unknown archive method"; return 1 ;;
        esac
    done
}

myhelp() {
    echo "Aliases"
    grep -hE '^alias ' ~/.bash_aliases ~/.bash_x11 2>/dev/null | sed "s/^alias //; s/^/  /"
    echo
    echo "Functions"
    declare -F | awk '{print $3}' | grep -vE '^_|^__' | sed 's/^/  /'
}

apt() {
    local runner
    if command -v nala >/dev/null 2>&1; then runner=nala; else runner=/usr/bin/apt; fi
    case "$1" in
        install|remove|purge|update|upgrade|autoremove|list) sudo "$runner" "$@" ;;
        search|show) "$runner" "$@" ;;
        *) command apt "$@" ;;
    esac
}

update_os() {
    apt update && apt upgrade -y && apt autoremove -y && apt install --fix-broken -y
}

update_firmware() {
    fwupdmgr refresh
    fwupdmgr get-updates
    sudo fwupdmgr update
}

logout() {
    if [ -n "${NIRI_SOCKET:-}" ]; then niri msg action quit; else gnome-session-quit; fi
}

md2pdf() {
    local default_css="$HOME/.local/share/css/s6c_remarkable_style.css"
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "Usage: md2pdf <markdown_file.md> [css_file.css]   (default css: $default_css)"
        return 1
    fi
    local md_file="$1" css_file="${2:-$default_css}"
    [ -r "$md_file" ]  || { echo "Error: markdown file '$md_file' not found or not readable."; return 1; }
    [ -r "$css_file" ] || { echo "Error: CSS file '$css_file' not found or not readable."; return 1; }
    local pdf_file
    pdf_file="$(basename "$md_file" .md).pdf"
    echo "Converting '$md_file' to '$pdf_file' using '$css_file'..."
    if pandoc "$md_file" --to=html5 --css="$css_file" --standalone --pdf-engine=weasyprint --output="$pdf_file"; then
        echo "Successfully created '$pdf_file'."
    else
        echo "Error: pandoc conversion failed."
        return 1
    fi
}

filecopy() {
    [ -n "$1" ] || { echo "Usage: filecopy <file>" >&2; return 1; }
    [ -r "$1" ] || { echo "Error: file not found or unreadable: $1" >&2; return 1; }
    if command -v wl-copy >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        wl-copy < "$1"
    elif command -v xclip >/dev/null 2>&1; then
        xclip -selection clipboard < "$1"
    else
        echo "Error: neither wl-copy nor xclip is installed." >&2
        return 1
    fi
    echo "Copied content of '$1' to clipboard."
}

music() { ytmusic "$@"; }
mp3()   { ytmusic --mp3 "$@"; }
aac()   { ytmusic --aac "$@"; }

_ytlist() {
    local fmt="$1"; shift
    local args=() files=0
    [ -n "$fmt" ] && args+=("$fmt")
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dir|--max-dur) args+=("$1" "$2"); shift 2; continue ;;
            -*)              args+=("$1") ;;
            *)               args+=(--from-file "$1"); files=$((files + 1)) ;;
        esac
        shift
    done
    if [ "$files" -eq 0 ]; then
        echo "usage: ${FUNCNAME[1]} <list.txt> [more.txt ...]" >&2
        return 2
    fi
    ytmusic "${args[@]}"
}
musiclist() { _ytlist ""    "$@"; }
mp3list()   { _ytlist --mp3 "$@"; }
aaclist()   { _ytlist --aac "$@"; }

y() {
    local tmp cwd
    tmp="$(mktemp -t yazi-cwd.XXXXXX)" || return
    yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd <"$tmp"
    [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
    command rm -f -- "$tmp"
}
