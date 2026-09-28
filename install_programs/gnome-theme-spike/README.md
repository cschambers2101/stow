# GNOME theme spike (28 Sep 2026)

Spike, not wired into the installer. Themes the Ubuntu session from the DMS palette.

- `apply.sh WALLPAPER` sets the GNOME wallpaper, runs `dms matugen generate` (scheme-content,
  source-mode dominant), then `regen.py`: fills `gnome-shell.css.tmpl` into
  `~/.themes/S6C-Dank/gnome-shell/gnome-shell.css`, writes the Ptyxis palette, sets the dock keys
  and reloads the shell theme.
- `shot.py OUT.png` takes a screenshot through the xdg portal (the only route GNOME 50 allows).

Findings and undo steps: `projects/linux-device-build-2026/notes/gnome-option-plan-2026-09-28.md`.
