# functions
function mcd () {
    mkdir -p $1
    cd $1
}

function extract {
 if [ -z "$1" ]; then
    # display usage if no parameters given
    echo "Usage: extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz>"
    echo "       extract <path/file_name_1.ext> [path/file_name_2.ext] [path/file_name_3.ext]"
    return 1
 else
    for n in $@
    do
      if [ -f "$n" ] ; then
          case "${n%,}" in
            *.tar.bz2|*.tar.gz|*.tar.xz|*.tbz2|*.tgz|*.txz|*.tar) 
                         tar xvf "$n"       ;;
            *.lzma)      unlzma ./"$n"      ;;
            *.bz2)       bunzip2 ./"$n"     ;;
            *.rar)       unrar x -ad ./"$n" ;;
            *.gz)        gunzip ./"$n"      ;;
            *.zip)       unzip ./"$n"       ;;
            *.z)         uncompress ./"$n"  ;;
            *.7z|*.arj|*.cab|*.chm|*.deb|*.dmg|*.iso|*.lzh|*.msi|*.rpm|*.udf|*.wim|*.xar)
                         7z x ./"$n"        ;;
            *.xz)        unxz ./"$n"        ;;
            *.exe)       cabextract ./"$n"  ;;
            *)
                         echo "extract: '$n' - unknown archive method"
                         return 1
                         ;;
          esac
      else
          echo "'$n' - file does not exist"
          return 1
      fi
    done
fi
}

function myhelp() {
    echo 'Aliases in my ~/.bashrc'
    echo
    echo 'll -> ls -lhA'
    echo 'cd.. -> cd ..'
    echo 'here -> finds a named file in the current directory'
    echo 'df -> df -Ths --total'
    echo 'du -> du -ach | sort -h'
    echo 'free -> free -mt'
    echo 'psg -> ps aux | grep -v grep | grep -i -e VSZ -e'
    echo 'mkdir -> mkdir -pv'
    echo 'wget -> wget -c'
    echo 'myip -> curl http://ipecho.net/plain; echo'
    echo 'mp3 -> downloads mp3 file from youtube'
    echo 'tnew -> tmux new -s '
    echo 'attach -> tmux attach-session -t '
    echo
    echo 'Functions'
    echo
    echo 'mcd -> creates directory and cds into it'
    echo 'extract -> should extract any archive file into the current directory'
    echo 'c -> clear'
    echo 'qtile_scaling -> Sets scaling to 0.5 for Qtile on HDPI displays'
    echo 'myhelp -> prints this help file'
    # echo 'server -> browser-sync start --server --files . --no-notify --host $SERVER_IP --port 9000 #requires node to be installed'
}

function update_os() {
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt install --fix-broken -y
}

function qtile_scaling() {
    xrandr --output eDP-1 --scale 0.5x0.5
}
