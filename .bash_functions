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
    echo 'upgrade -> runs update_os function'
    echo
    echo 'Functions'
    echo
    echo 'mcd -> creates directory and cds into it'
    echo 'extract -> should extract any archive file into the current directory'
    echo 'c -> clear'
    echo 'qtile_scaling -> Sets scaling to 0.5 for Qtile on HDPI displays'
    echo 'myhelp -> prints this help file'
    echo 'fcp or filecopy -> copy the given filename to the clipboard'
    echo 'ms -> switches between monitors at S6C and the laptop'
    echo 'md2pdf -> converts markdown file to pdf using pandoc and a custom css file'
    echo 'update_firmware -> updates firmware using fwupdmgr'
    # echo 'server -> browser-sync start --server --files . --no-notify --host $SERVER_IP --port 9000 #requires node to be installed'
}

function update_os() {
    sudo apt update
    sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt install --fix-broken -y
}

function update_firmware() {
    fwupdmgr refresh
    fwupdmgr get-updates
    sudo fwupdmgr update
}

function qtile_scaling() {
    xrandr --output eDP-1 --scale 0.5x0.5
}

md2pdf() {
  # --- Default CSS Path ---
  # Define the path to the default CSS file, expanding the tilde to the home directory
  local default_css_file="$HOME/.local/share/css/s6c_remarkable_style.css"

  # --- Input Validation ---
  # Check if the number of arguments is correct (1 or 2)
  if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: md2pdf <markdown_file.md> [css_file.css]"
    echo "If css_file.css is omitted, '$default_css_file' will be used."
    return 1 # Return error code for incorrect usage
  fi

  local md_file="$1" # First argument is the markdown file
  local css_file     # Variable to hold the path to the CSS file

  # Determine which CSS file to use based on the number of arguments
  if [ "$#" -eq 2 ]; then
    # CSS file provided as the second argument
    css_file="$2"
  else
    # Use the defined default CSS file
    css_file="$default_css_file"
    echo "No CSS file provided, using default: '$css_file'"
  fi

  # Check if the markdown file exists and is readable
  if [ ! -f "$md_file" ] || [ ! -r "$md_file" ]; then
    echo "Error: Markdown file '$md_file' not found or not readable."
    return 1 # Return error code
  fi

  # Check if the selected CSS file exists and is readable
  if [ ! -f "$css_file" ] || [ ! -r "$css_file" ]; then
    echo "Error: CSS file '$css_file' not found or not readable."
    # Provide a hint if the default CSS file is missing
    if [ "$css_file" == "$default_css_file" ]; then
        echo "Hint: Ensure the default CSS file exists at '$default_css_file'."
    fi
    return 1 # Return error code
  fi

  # --- File Name Extraction ---
  # Get the base name of the markdown file (e.g., "report" from "path/to/report.md")
  # This removes the directory path and the .md extension
  local base_name
  base_name=$(basename "$md_file" .md)

  # Define the output PDF file name using the base name
  local pdf_file="${base_name}.pdf"
  # PDF title metadata is NO LONGER set automatically.
  # Add title in Markdown source (e.g., YAML front matter like --- title: My Title ---) if needed.

  # --- Pandoc Conversion ---
  # Inform the user about the conversion process
  echo "Converting '$md_file' to '$pdf_file' using '$css_file'..."

  # Execute the pandoc command (without the --metadata title option)
  pandoc "$md_file" \
    --to=html5 \
    --css="$css_file" \
    --standalone \
    --pdf-engine=weasyprint \
    --output="$pdf_file"

  # --- Check Result ---
  # Check the exit status of the pandoc command
  if [ $? -eq 0 ]; then
    # Success message
    echo "Successfully created '$pdf_file'."
    return 0 # Return success code
  else
    # Error message
    echo "Error: Pandoc conversion failed."
    return 1 # Return error code
  fi
}

# Usage:
#   filecopy <filename>
#
# Example:
#   filecopy ~/.vimrc
#   filecopy ~/Documents/report.txt
#
function filecopy() {
    # Check if a filename was provided as an argument
    if [ -z "$1" ]; then
        echo "Error: Please specify a file to copy." >&2
        return 1
    fi

    local FILE_PATH="$1"

    # Check if the file exists and is readable
    if [ ! -r "$FILE_PATH" ]; then
        echo "Error: File not found or is unreadable: $FILE_PATH" >&2
        return 1
    fi

    # Check if xclip is available
    if ! command -v xclip &> /dev/null
    then
        echo "Error: xclip is not installed. Please install it using 'sudo apt install xclip'." >&2
        return 1
    fi

    # Use cat to output the file content and pipe it to xclip
    # -selection clipboard ensures it goes to the Ctrl+C/Ctrl+V buffer.
    cat "$FILE_PATH" | xclip -selection clipboard

    echo "Copied content of '$FILE_PATH' to clipboard."
}


# ===============================================
# Reliable Monitor Toggling Function (FIXED)
# ===============================================

# Function to safely toggle between monitor configurations.
# It uses the 'touch' command to update the timestamp of the executed file,
# ensuring the logic reliably alternates on the next run.

function toggle_monitors() {
    # Define the full paths to your configuration scripts
    local LAPTOP_CONF="$HOME/.screenlayout/laptop_monitor.sh"
    local S6C_CONF="$HOME/.screenlayout/s6c_monitors.sh"

    echo "Checking current configuration..."

    # The -nt operator checks if the first file is Newer Than the second.
    # This determines which setup was run last.
    if [ "$S6C_CONF" -nt "$LAPTOP_CONF" ]; then
        # S6C was run last (it has the newer timestamp), so we switch to Laptop.
        echo "--> Switching to Laptop-Only Configuration..."
        bash "$LAPTOP_CONF"
        
        # CRITICAL FIX: Update the timestamp of the Laptop script. 
        # This makes LAPTOP_CONF the 'newer' file, so the next toggle runs S6C.
        touch "$LAPTOP_CONF"
    else
        # Laptop was run last, or both are the same age, so we switch to S6C.
        echo "--> Switching to S6C Multi-Monitor Configuration..."
        bash "$S6C_CONF"
        
        # CRITICAL FIX: Update the timestamp of the S6C script.
        # This makes S6C_CONF the 'newer' file, so the next toggle runs Laptop.
        touch "$S6C_CONF"
    fi
}

mp3() {
    yt-dlp -x --audio-format mp3 --audio-quality 0 -o "~/Music/%(uploader)s/%(title)s.%(ext)s" "$1"
}

aac() {
    yt-dlp -x --audio-format aac --audio-quality 0 -o "~/Music/%(uploader)s/%(title)s.%(ext)s" "$1"
}
