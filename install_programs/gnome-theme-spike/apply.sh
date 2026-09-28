#!/bin/bash
set -e
wp="$1"; cd "$(dirname "$0")"
gsettings set org.gnome.desktop.background picture-uri "file://$wp"; gsettings set org.gnome.desktop.background picture-uri-dark "file://$wp"
cd ~ && dms matugen generate --kind image --value "$wp" --mode dark --matugen-type scheme-content --source-mode dominant --run-user-templates --state-dir ~/.cache/DankMaterialShell --shell-dir /usr/share/quickshell/dms/quickshell --config-dir ~/.config >/dev/null 2>&1 || [ $? -eq 2 ]
cd - >/dev/null; python3 regen.py
U=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'"); P=org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$U/
gsettings set $P palette Ubuntu; sleep 0.5; gsettings set $P palette S6C-Dank
