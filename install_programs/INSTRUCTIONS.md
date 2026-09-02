# How to build a machine

From a blank laptop to a working niri / DankMaterialShell desktop.

**Prerequisites:** Ubuntu 26.04 Desktop, **Secure Boot disabled**, network up.
Run as your normal user — *not* root, and not with `sudo`.

---

## Route A — manual (normal case)

Install Ubuntu 26.04 Desktop as usual, log in, open a terminal and run:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/cschambers2101/stow/main/install_programs/bootstrap.sh)
```

**`wget`, not `curl`.** Ubuntu 26.04.1 Desktop ships `wget` but not `curl`, so
the curl form of this line fails before it starts.

That is the whole thing. `bootstrap.sh` shallow-clones this repo to
`~/.dotfiles` and hands off to `ubuntu_26.04_niri_install.sh`, which runs 16
sections: drivers, desktop base, the niri/Dank stack, packages, dotfiles,
Node, machine identity, printing.

**Section order matters on the school network.** Section 2A installs the
Oakford root CA, and the site firewall intercepts TLS on everything except
Ubuntu archive traffic and `oakfordhelp.co.uk`. Every download from anywhere
else — dankinstall (5), Chrome (7), Flathub (8), Node (11), yt-dlp and Claude
Code (12) — fails certificate validation until that CA is trusted, and under
`set -e` the first failure ends the install. **Do not add a third-party
download above section 2A.** It will work everywhere except on site.

Takes roughly 30–45 minutes on school wifi. **Reboot when it finishes.**

## Route B — unattended (fleet)

For building several machines from a USB stick, see
[`autoinstall/README.md`](autoinstall/README.md). Short version: write the
Ubuntu Desktop ISO to one stick with `dd`, then

```bash
./autoinstall/make-cidata.sh /dev/sdX     # ⚠️ ERASES that device
```

onto a second small stick, and boot with both plugged in. Cloud-init finds the
one labelled `CIDATA` and installs unattended, then clones and runs the same
installer.

---

## The two questions it asks

Interactively it prompts for these. Set them as environment variables first to
run unattended — each prompt is skipped when its variable is already set or
when there is no terminal:

| Variable | What it is |
|----------|------------|
| `TARGET_HOSTNAME` | Machine name |
| `PAPERCUT_SERVER` | Print server, e.g. `https://print.school.example:9174` |

```bash
TARGET_HOSTNAME='s6c-laptop-01' ./ubuntu_26.04_niri_install.sh
```

**School wifi is no longer one of them.** The S6C profile is written on every
build using the BYOD key, so a laptop reaches the school network without anyone
being asked. Override only for a different network or after a key change:

```bash
S6C_PSK='...' ./ubuntu_26.04_niri_install.sh     # single quotes
```

Use **single** quotes. The key contains `!`, which an interactive bash expands
as history inside double quotes (`bash: event not found`). Passing
`S6C_PSK=''` explicitly skips the profile.

---

## After the reboot — verify

Run this first. It checks 25 things in a couple of seconds and exits non-zero
if anything is wrong:

```bash
bash ~/.dotfiles/install_programs/verify-install.sh
```

Run it with sudo available (or just after an install, while the credential is
still cached) to get the full set — the few checks needing root are skipped
rather than failed otherwise.

Then check these five by eye, because they are the ones a script cannot
confirm. Three of the faults found in testing were **silent**: the install
reported success and the machine looked fine.

1. **The greeter draws** — cream background, ladybird wallpaper, and a
   round person icon beside the password field. A blank or black screen means
   graphics, not greetd.
2. **Tray icons are real icons**, not grey checkerboards. Checkerboards mean
   `qt6-gtk-platformtheme` is missing.
3. **The wallpaper is the ladybird**, on both the greeter and the desktop. If
   the greeter shows a different one, `dms greeter sync` did not run.
4. **You can lock and unlock** with `Mod+Alt+L`. If unlocking rejects a correct
   password, `/etc/pam.d/dankshell` is missing — again `dms greeter sync`.
5. **`systemctl --failed`** is empty.

### If you see this, stop

```
ERROR: Oakford CA fingerprint did NOT match. Certificate NOT installed.
```

The install adds the Oakford **root CA** to the system trust store, so it is
fetched over HTTPS with its fingerprint pinned, and refuses to install anything
that does not match. **Do not install the certificate by hand to get past
this.** Either Oakford have re-issued it, or something is interfering. Confirm
the new fingerprint with Oakford, then update `OAKFORD_SHA256`. Internal HTTPS
sites will not be trusted until then — that is the intended behaviour, not a
bug.

Two warnings during the run are **expected and harmless**:

- `greeter auto-login sync failed: … memory.json: permission denied` — a
  group-membership race. It self-heals on first login.
- `dsearch.service does not exist` — from `danksearch`. Cosmetic.

---

## Where things are

| What | Where |
|------|-------|
| Live package list | `niri_programs_to_install.txt` — **edit this one** |
| Main installer | `ubuntu_26.04_niri_install.sh` |
| Student entry point | `bootstrap.sh` |
| Unattended install | `autoinstall/` |
| Craig's qtile laptop | `ubuntu_26.04_qtile_install.sh` |
| Chromebook / Crostini | `chromebook_setup.sh` |
| Not used by anything | `archived/` |

Decisions, research and the rollout runbook live outside this repo, in the
`linux-device-build-2026` project folder.
