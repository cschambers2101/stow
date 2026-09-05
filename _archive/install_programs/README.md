# Archived install scripts

Moved here 30 August 2026. **Nothing in this folder is executed by anything.**
They are kept rather than deleted so the Linux Device Build testing cycle stays
reversible — restore with `git mv archived/<file> ../<file>`.

Verified before moving: no live script references any of these. The one
candidate that *was* still referenced — `install_eucalyptus_drop_sddm_theme.sh`,
called at §20 of `ubuntu_26.04_qtile_install.sh` — was deliberately left in
place.

| File | Why it is here |
|------|----------------|
| `install_required_programs_old.sh` | Superseded by `ubuntu_26.04_niri_install.sh`. Referenced by nothing. |
| `install_qtile.sh` | `pip install qtile==0.22.1`; its own header comment is dated July 2023. Qtile is now built by `ubuntu_26.04_qtile_install.sh`. |
| `optional_programs.txt` | Zero references anywhere in the repo. Last modified May 2025. |
| `programs_to_install.txt` | **Read only by `install_required_programs_old.sh`**, which is itself dead — see the note below. |

## The `programs_to_install.txt` trap

This file looked live and was not. The live list is
`../niri_programs_to_install.txt`; the qtile script keeps its packages inline.

`fastfetch` was added to this dead file on 30 August 2026. Nothing was lost —
`fastfetch` is also in the live niri list — but the edit had no effect. Every
package unique to this file is X11-era (`i3`, `picom`, `polybar`, `rofi`,
`dunst`, `sxhkd`, `xss-lock`, `feh`, `scrot`), so nothing niri needs is missing.

**If you are adding a package, edit `../niri_programs_to_install.txt`.**
