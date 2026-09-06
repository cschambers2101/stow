# dotfiles

Craig Chambers' dotfiles and machine build scripts, deployed with GNU Stow.

| Path | What |
|------|------|
| `.bashrc` `.bash_aliases` `.bash_functions` `.bash_profile` `.bash_x11` | Shell. `.bash_x11` is only sourced under an X11 session |
| `.config/` | niri, DankMaterialShell, alacritty, dunst, starship, yazi, xfce4 helpers |
| `.local/bin/` | Commands: `dank-lock.sh`, `ytmusic`, `ytmusic-tag`, `s6c-booklet`, the `*_note.sh` tools, `graph` |
| `.local/share/` | Fonts, wallpaper, CSS, the Oakford CA copy, the default avatar |
| `install_programs/` | Machine builds. Start at [`install_programs/INSTRUCTIONS.md`](install_programs/INSTRUCTIONS.md) |
| `_archive/` | Retired qtile / Debian / X11 material. Not stowed |

## Deploy

```bash
git clone --depth 1 https://github.com/cschambers2101/stow.git ~/.dotfiles
cd ~/.dotfiles && stow .
```

`.stow-local-ignore` keeps `install_programs/`, `_archive/`, `.github/` and this
file out of `$HOME`. On a machine stowed before September 2026 a stale
`~/install_programs` symlink may remain; `rm ~/install_programs` is safe.

## Lint

```bash
bash install_programs/lint.sh      # shellcheck -S warning + bash -n over every shell file
```

The same runs in GitHub Actions on every push.

## Conventions

- `#!/usr/bin/env bash`, `set -Eeuo pipefail` via `install_programs/lib/common.sh`, which also owns every constant and URL.
- No absolute home paths anywhere: scripts derive their location from `BASH_SOURCE`.
- Scripts carry no explanatory comments; the reasoning lives in the private workspace notes (see INSTRUCTIONS.md).
