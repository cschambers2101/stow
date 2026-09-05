#!/bin/bash

# =================================================================
# UBUNTU 26.04 LTS — NIRI / DANK STUDENT LAPTOP SETUP
# Run this script from install_programs/ after cloning the dotfiles repo.
# Requires: vanilla Ubuntu 26.04, Secure Boot DISABLED, network up.
#
# Do NOT run as root — dankinstall refuses to run as uid 0.
# =================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"
PKG_LIST="$SCRIPT_DIR/niri_programs_to_install.txt"

if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: run this as your normal user, not root. dankinstall refuses uid 0."
    exit 1
fi

# Cache sudo credentials up front: dankinstall's headless mode requires it,
# and it keeps the rest of the run unattended.
#
# `sudo true`, NOT `sudo -v`. Ubuntu 26.04 ships sudo-rs, whose -v always
# demands interactive authentication even when policy grants NOPASSWD --
# so `sudo -v` can never be satisfied in an unattended run. `sudo true`
# caches the timestamp identically and works in both cases: it prompts
# once for a human, and passes silently under NOPASSWD.
sudo true
# Keep the sudo timestamp alive for the whole run.
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT

# -----------------------------------------------------------------
# PREFLIGHT: SECURE BOOT
#
# The header of this script has always said "Requires: Secure Boot
# DISABLED", and nothing has ever checked. The 3 Sep 2026 laptop installed
# cleanly with it ON, because Intel graphics need no out-of-tree module --
# so the estate now holds both states by accident rather than by decision.
#
# Detected HERE, before anything that depends on it, and recorded rather
# than acted on: the build must complete either way, and a warning printed
# at minute two has left the scrollback by minute forty. It is used twice --
# to gate broadcom-sta-dkms in section 9, and to print an action block at
# the very end, where the user is actually looking.
#
# mokutil is authoritative. The lockdown fallback is a good proxy but not
# a synonym: a kernel can be locked down via the `lockdown=` parameter with
# Secure Boot off.
# -----------------------------------------------------------------
SECURE_BOOT=unknown
BROADCOM_BLOCKED=no
if command -v mokutil >/dev/null 2>&1; then
    case "$(mokutil --sb-state 2>&1)" in
        *"SecureBoot enabled"*)  SECURE_BOOT=on ;;
        *"SecureBoot disabled"*) SECURE_BOOT=off ;;
        # mokutil words this two ways depending on version and firmware:
        # "This system doesn't support Secure Boot" on a legacy-BIOS machine,
        # "EFI variables are not supported" where efivarfs is absent. Missing
        # the first left old BIOS-boot laptops as `unknown`, which skipped
        # broadcom-sta-dkms over a Secure Boot they do not have -- and those
        # are precisely the Broadcom-era machines that need it.
        *"doesn't support"*|*"not supported"*) SECURE_BOOT=unsupported ;;
    esac
fi
if [ "$SECURE_BOOT" = unknown ] && [ -r /sys/kernel/security/lockdown ]; then
    case "$(cat /sys/kernel/security/lockdown 2>/dev/null)" in
        *"[none]"*)                      SECURE_BOOT=off ;;
        *"[integrity]"*|*"[confidentiality]"*) SECURE_BOOT=on ;;
    esac
fi
case "$SECURE_BOOT" in
    on)          echo "Secure Boot: ENABLED — unsigned DKMS modules will be refused. See the end of this run." ;;
    off)         echo "Secure Boot: disabled." ;;
    unsupported) echo "Secure Boot: not supported by this firmware — nothing to do." ;;
    *)           echo "Secure Boot: could not be determined — treating it as possibly on." ;;
esac

secure_boot_action_block() {
    echo ""
    echo "======================================================="
    echo "  ACTION NEEDED — SECURE BOOT IS $(echo "$SECURE_BOOT" | tr '[:lower:]' '[:upper:]')"
    echo "======================================================="
    echo ""
    echo "  Reboot into firmware setup and DISABLE Secure Boot."
    echo "  On this Dell: F2 at the logo, Boot Configuration,"
    echo "  Secure Boot -> Disabled. Other makes vary."
    echo ""
    echo "  THIS DOES NOT MEAN REINSTALLING. It is a firmware"
    echo "  setting only:"
    echo "    * the system boots exactly as it does now"
    # Do NOT promise this unconditionally. A passphrase LUKS volume -- what
    # subiquity builds, and what /etc/crypttab shows as `none luks` -- is
    # unaffected by Secure Boot state. Ubuntu's TPM-backed FDE is NOT: it
    # seals to PCR 7, which measures Secure Boot, so turning it off breaks
    # the automatic unlock and needs the recovery key. Telling that user
    # "nothing changes" would lock them out of their own disk.
    if [ -r /etc/crypttab ] && grep -q "tpm2-device=" /etc/crypttab 2>/dev/null; then
        echo "    * !! THIS DISK IS TPM-SEALED. Changing Secure Boot"
        echo "      alters PCR 7 and the automatic unlock WILL fail."
        echo "      HAVE YOUR RECOVERY KEY TO HAND before doing this."
    else
        echo "    * your disk encryption passphrase is UNCHANGED"
        echo "      (this volume is not sealed to Secure Boot state)"
    fi
    echo "    * nothing on disk is touched"
    echo ""
    echo "  Why it matters on this machine:"
    if [ "$BROADCOM_BLOCKED" = yes ]; then
        echo "    * THIS MACHINE HAS BROADCOM WIFI and its driver was"
        echo "      SKIPPED. Wifi will not work until you do this and"
        echo "      re-run the script."
    fi
    echo "    * unsigned DKMS drivers (Broadcom wifi, NVIDIA) cannot"
    echo "      load while Secure Boot is on"
    echo "    * hibernation is refused outright by the locked-down"
    echo "      kernel, so a shut laptop keeps draining"
    echo ""
    echo "  Then re-run this script. It is safe to run twice."
    echo "======================================================="
}

# -----------------------------------------------------------------
# PREFLIGHT: CAN THIS MACHINE STILL REACH A NETWORK AFTERWARDS?
#
# The trap this guards against: a Broadcom laptop with no ethernet port,
# Secure Boot on, and a chip that needs the unsigned `wl` module. Section 9
# will refuse to install `wl` -- correctly, since a locked-down kernel cannot
# load it and installing it blacklists the in-kernel drivers too -- and the
# machine reboots with no wifi at all.
#
# The test is deliberately NOT "is an ethernet cable plugged in". Three
# reasons, all found on 4 Sep 2026:
#
#   1. Ethernet is the wrong question. A phone tether or a USB dongle serves
#      as well, and the XPS 13 has NO built-in ethernet -- only a USB adapter.
#      Asking for a cable is asking for something some hardware cannot have.
#   2. Many Broadcom parts are driven by in-kernel brcmfmac/b43/brcmsmac,
#      which are signed and load happily under Secure Boot. Blocking those
#      would strand builds that would have worked. `lspci -nnk` reports the
#      bound driver without root, so the two cases are distinguishable.
#   3. It cannot help the worst case anyway. If `wl` really is the only route
#      to a network, this script never ran: bootstrap.sh clones over HTTPS
#      first. That machine needs the firmware changed at intake, before it is
#      ever imaged -- see notes/rollout-runbook.md.
#
# So the question asked here is the one that matters: will this machine still
# have a network once we refuse its wifi driver?
# -----------------------------------------------------------------
BROADCOM_PRESENT=no
BROADCOM_DRIVER=""
BROADCOM_NEEDS_WL=no
BC_SLOTS=""
OTHER_NET=no

if command -v lspci >/dev/null 2>&1; then
    for _slot in $(lspci -nn 2>/dev/null | grep -iE "network|wireless" | grep -i broadcom | cut -d' ' -f1); do
        BROADCOM_PRESENT=yes
        BC_SLOTS="$BC_SLOTS $_slot"
        _d="$(lspci -nnks "$_slot" 2>/dev/null | sed -n 's/.*Kernel driver in use: *//p' | head -1 | xargs)"
        [ -n "$_d" ] && BROADCOM_DRIVER="$_d"
    done
fi

if [ "$BROADCOM_PRESENT" = yes ]; then
    case "$BROADCOM_DRIVER" in
        # In-kernel and signed: fine under Secure Boot, nothing to warn about.
        brcmfmac|b43|brcmsmac|bcma|ssb)
            echo "Broadcom wireless on $BROADCOM_DRIVER (in-kernel) — no unsigned module needed." ;;
        # Already bound: Secure Boot cannot be blocking it.
        wl)
            echo "Broadcom wireless already on wl." ;;
        "")
            BROADCOM_NEEDS_WL=yes ;;
        *)
            echo "Broadcom wireless on $BROADCOM_DRIVER." ;;
    esac
fi

# Any interface carrying a link that is NOT the Broadcom one. Covers USB
# ethernet, phone tethers and dongles alike, which a cable check would not.
for _if in /sys/class/net/*; do
    _n="$(basename "$_if")"
    [ "$_n" = lo ] && continue
    [ "$(cat "$_if/carrier" 2>/dev/null)" = "1" ] || continue
    _pci="$(basename "$(readlink -f "$_if/device" 2>/dev/null)" 2>/dev/null)"
    _isbc=no
    for _slot in $BC_SLOTS; do
        case "$_pci" in *"$_slot") _isbc=yes ;; esac
    done
    [ "$_isbc" = yes ] && continue
    OTHER_NET=yes
done

if [ "$BROADCOM_NEEDS_WL" = yes ] && { [ "$SECURE_BOOT" = on ] || [ "$SECURE_BOOT" = unknown ]; }; then
    BROADCOM_BLOCKED=yes
    if [ "$OTHER_NET" = no ] && [ -z "${ALLOW_NO_WIFI:-}" ]; then
        secure_boot_action_block
        echo ""
        echo "STOPPING BEFORE ANY CHANGES ARE MADE."
        echo ""
        echo "  This machine's only wireless is Broadcom, nothing is driving"
        echo "  it, and Secure Boot will not let the driver load. Building it"
        echo "  now would produce a machine with NO network at all."
        echo ""
        echo "  Either:"
        echo "    * disable Secure Boot as above (preferred), or"
        echo "    * attach a wired, tethered or USB-dongle connection"
        echo ""
        echo "  Then re-run. To build anyway, accepting no wifi until Secure"
        echo "  Boot is off:  ALLOW_NO_WIFI=1 ./ubuntu_26.04_niri_install.sh"
        echo "======================================================="
        exit 1
    fi
    # Either a network exists that does not depend on the refused driver, or
    # ALLOW_NO_WIFI was set. Say so NOW rather than in forty minutes -- but do
    # not claim a connection that is not there, which the override case is.
    echo ""
    echo "NOTE: Broadcom wireless here needs the unsigned wl module, which"
    echo "      Secure Boot will not load. This machine will have no wifi"
    echo "      until Secure Boot is disabled."
    if [ "$OTHER_NET" = yes ]; then
        echo "      The build continues over the connection you are on."
    else
        echo "      ALLOW_NO_WIFI is set and there is no other connection —"
        echo "      the build will proceed and will fail if it needs network."
    fi
    secure_boot_action_block
fi

# -----------------------------------------------------------------
# 0. THE CLOCK
#
#    Numbered 0 because it has to come before everything, including apt.
#    Two things break on a machine whose clock is wrong, and both fail in
#    ways that point nowhere near the time:
#
#      * TLS validation. Section 2A fetches the Oakford CA over https, and
#        a certificate is only valid between two dates. A dead CMOS battery
#        puts a fresh machine years out and that fetch fails - taking the
#        install down four sections before dankinstall, exactly the way the
#        CA ordering bug did.
#      * apt. A Release file carries Valid-Until, and a clock far enough
#        ahead or behind gets "Release file is not yet valid", which reads
#        like a broken mirror.
#
#    Nothing here needs anything installed first: chrony is Priority
#    important, so it is already on the base ISO, and timedatectl is part
#    of systemd.
# -----------------------------------------------------------------
sudo timedatectl set-ntp true

# ...and `set-ntp true` is NOT sufficient on Ubuntu 26.04. It reports success,
# `timedatectl` then says "NTP service: active", and the clock still never
# syncs. Found on ubuntu-craig-office 2 Sep 2026, when it had drifted
# 2m12s fast (132.5s) and Craig noticed it against his phone.
#
# WHY. 26.04 ships chrony instead of systemd-timesyncd, and its default
# sources use NTS (Network Time Security). NTS needs a key-establishment
# handshake on TCP 4460 before any time can be exchanged, and the S6C firewall
# filters 4460:
#
#     TCP 4460 to ntp-nts-{1,2,3}.ps{5,6}.canonical.com  TIMEOUT (filtered)
#     TCP 4460 to time.cloudflare.com                    TIMEOUT (filtered)
#     TCP  443 to the SAME canonical host                OPEN   <- not a host block
#
# So chrony runs, never establishes keys, and reports every source as `^?`
# with Stratum 0 and a 1970 reference time. `timedatectl` was showing
# "System clock synchronized: no" while claiming the NTP service was active.
#
# Plain NTP over UDP 123 is NOT blocked - verified reachable to the public
# pools, to the site gateway and to the internal DC, all agreeing on the same
# 132.5s offset. So the fix is simply to give chrony non-NTS sources.
#
# Public pools, deliberately, for two reasons: no site address goes into this
# PUBLIC repo, and a student laptop taken home still syncs. If outbound 123 is
# ever blocked too, the site-internal fallback is recorded in the private
# workspace notes (projects/linux-device-build-2026/notes/), not here.
#
# Added as a NEW file in sources.d rather than editing
# ubuntu-ntp-pools.sources, which is package-shipped but NOT a dpkg conffile -
# an upgrade would silently overwrite an edit.
#
# `prefer` MATTERS, and leaving it off was a bug in the first version of this
# fix (3 Sep 2026). Ubuntu ships its four NTS pools with `prefer`:
#
#     pool 1.ntp.ubuntu.com iburst maxsources 1 nts prefer
#
# and chrony prefers a preferred source "over other selectable sources without
# the prefer option". With the NTS pools preferred-but-unreachable and these
# plain ones merely selectable, chrony reached six plain servers, agreed with
# all of them to within milliseconds, marked every one `^-` (not combined),
# selected NOTHING, and kept reporting "System clock synchronized: no" with a
# reference ID of 00000000. Adding `prefer` here removes the asymmetry, so the
# reachable sources can actually win.
#
# The NTS pools are left in place and stay unreachable.
#
# THAT IS NOT HARMLESS, and it is the actual blocker - established 3 Sep 2026
# from `chronyc selectdata`, after two wrong guesses. chrony's
# `authselectmode` defaults to **mix**, and the manual is explicit about what
# mix does:
#
#     all authenticated NTP sources ... will get the require and trust
#     options to prevent synchronisation to unauthenticated NTP sources if
#     they do not agree with a majority of the authenticated sources
#
# `require` means: if that source is not selectable, NO source is selected.
# The NTS sources are authenticated, so they are granted require - and they
# are unreachable, so nothing can ever be selected. selectdata showed it
# directly: every plain server in state `W` (waiting), EOpts `-P---`, while
# every NTS row carried EOpts `-PTR-` - the T and R granted by mix.
#
# So adding plain pools can NEVER work on its own while any NTS source is
# configured. No number of them helps. `authselectmode ignore` is what makes
# unauthenticated sources selectable again.
#
# Security, stated plainly rather than glossed: `ignore` means we do
# synchronise to unauthenticated NTP, and an on-path attacker could skew the
# clock within chrony's maxdelay/maxdistance limits. That is a real downgrade.
# It is still the right call here, because NTS is *impossible* on this network
# - TCP 4460 is filtered - so the alternative is not authenticated time, it is
# NO time, and a wrong clock breaks TLS validation and apt's Release window,
# which is the larger security problem. This site already intercepts TLS, so
# an on-path actor is inside the threat model by design.
#
# GUARD (added 4 Sep 2026). Everything below is chrony-specific and assumes
# chrony is on the base ISO. That holds for the vanilla-26.04 student laptops
# but NOT for reimaged classroom PCs, which kept systemd-timesyncd from the old
# x86/qtile build: chrony is absent, /etc/chrony/conf.d does not exist, and
# writing into it aborted the WHOLE install under `set -e` (line 330, uutils
# `tee` -> "No such file or directory (os error 2)"). Only apply the chrony
# workaround when chrony is actually present; otherwise timesyncd - already
# started by `set-ntp true` above - handles sync and we just verify it.
if command -v chronyd >/dev/null 2>&1 && [ -d /etc/chrony ]; then
echo "Letting chrony select unauthenticated sources (NTS is unreachable here)..."
sudo tee /etc/chrony/conf.d/50-s6c-authselectmode.conf >/dev/null <<'AUTHEOF'
# chrony's default authselectmode is `mix`, which grants `require` to every
# authenticated (NTS) source. An unreachable required source blocks selection
# of ALL sources, so with NTS filtered the clock never syncs no matter how
# many plain servers are configured. See section 0 of the installer.
authselectmode ignore
AUTHEOF

echo "Adding plain-NTP sources (NTS needs TCP 4460, which is filtered here)..."
sudo tee /etc/chrony/sources.d/50-s6c-plain-ntp.sources >/dev/null <<'NTPEOF'
# Plain (non-NTS) NTP pools. See section 0 of ubuntu_26.04_niri_install.sh:
# NTS key establishment on TCP 4460 is filtered here, so the NTS pools Ubuntu
# ships in ubuntu-ntp-pools.sources can never sync. UDP 123 is open.
#
# `prefer` is required, not cosmetic: the shipped NTS pools carry it, and
# without it here chrony will not select these sources even when they are the
# only ones reachable.
pool 0.pool.ntp.org iburst maxsources 2 prefer
pool 1.pool.ntp.org iburst maxsources 2 prefer
pool ntp.ubuntu.com iburst maxsources 2 prefer
NTPEOF

# A domain controller, if this machine is on a domain, as a FALLBACK BELOW the
# public pools. Craig's call, 3 Sep 2026, and it is the right way round:
# student laptops and home machines spend most of their life off the school
# network, so the source that works everywhere should be the primary one.
#
# The tiering is `prefer`, which is exactly chrony's semantics - "prefer this
# source over other selectable sources without the prefer option":
#
#   public pools   prefer      -> chosen whenever they are reachable
#   domain contr.  no prefer   -> used only when nothing preferred is
#
# It earns its place in one specific scenario: a network that permits neither
# NTS (TCP 4460) nor plain outbound NTP (UDP 123). This site currently allows
# UDP 123, so the DC will sit unselected here - but if that is ever closed, the
# clock keeps working instead of silently free-running again.
#
# NO SITE VALUES. The DC is discovered from DNS: the DHCP-supplied search
# domain, then the standard AD locator record `_ldap._tcp.<domain>`. Any
# machine on any domain finds its own; a machine on no domain adds nothing.
# Verified on ubuntu-craig-office 3 Sep 2026 - found the site's DC, and the
# parsing was checked against no-domain and routing-only (`~domain`) output.
# (The DC's name is deliberately not written here: this repo is public, and
# internal server names belong in the private workspace notes, same rule as
# the printer and PaperCut addresses.)
#
# resolvectl, NOT dig: dig comes from bind9-dnsutils, which is not in
# niri_programs_to_install.txt and so is absent on a fresh build. resolvectl is
# part of systemd.
#
# Hostnames rather than addresses, so the entry survives the DC being
# renumbered. Off-site the name simply does not resolve and chrony ignores it.
echo "Looking for a domain controller to use as a time fallback..."
_dc_domains=$(resolvectl domain 2>/dev/null \
    | sed -n 's/^Link [0-9]* ([^)]*): //p' \
    | tr ' ' '\n' | sed '/^$/d;/^~/d' | sort -u)
_dc_hosts=""
for _d in $_dc_domains; do
    _dc_hosts="$_dc_hosts$(resolvectl --type=SRV query "_ldap._tcp.$_d" 2>/dev/null \
        | sed -n 's/.* IN SRV [0-9]* [0-9]* [0-9]* \([^ ]*\).*/\1/p' \
        | sed 's/\.$//' | sed '/^$/d')
"
done
_dc_hosts=$(printf '%s' "$_dc_hosts" | sed '/^$/d' | sort -u)

if [ -n "$_dc_hosts" ]; then
    {
        echo "# Domain controller(s) as an NTP FALLBACK, discovered from"
        echo "# _ldap._tcp.<search-domain> at install time. Deliberately WITHOUT"
        echo "# \`prefer\`, so the public pools in 50-s6c-plain-ntp.sources win"
        echo "# whenever they are reachable - most of these machines are off the"
        echo "# school network most of the time. This tier matters only where"
        echo "# outbound UDP 123 is blocked as well as TCP 4460."
        printf '%s\n' "$_dc_hosts" | sed 's/^/server /; s/$/ iburst/'
    } | sudo tee /etc/chrony/sources.d/60-s6c-dc-fallback.sources >/dev/null
    echo "   fallback: $(printf '%s' "$_dc_hosts" | tr '\n' ' ')"
else
    echo "   no domain controller found (not on a domain) - public pools only"
fi
unset _dc_domains _dc_hosts _d

# chrony re-reads sources.d on reload, but a restart also lets `makestep 1 3`
# (already in chrony.conf) STEP a large offset instead of slewing it away over
# hours. A 132s error would take most of a day to slew out.
sudo systemctl restart chrony 2>/dev/null || sudo systemctl restart chronyd 2>/dev/null || \
    echo "WARNING: could not restart chrony."

# Give it a moment to actually select a source, so the verification at the end
# of this script sees the true state rather than a race.
for _i in $(seq 1 20); do
    if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q '^yes$'; then
        echo "   clock synchronised, now $(date '+%H:%M:%S %Z')"
        break
    fi
    sleep 1
done
unset _i
timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q '^yes$' || \
    echo "WARNING: clock still not synchronised - check 'chronyc sources -v'."
else
    # No chrony (e.g. reimaged classroom PC on systemd-timesyncd). The NTS
    # breakage the block above works around is chrony-only, so there is nothing
    # to fix here - just confirm timesyncd got us a synced clock.
    echo "chrony not installed - relying on systemd-timesyncd for time sync."
    for _i in $(seq 1 20); do
        timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q '^yes$' && break
        sleep 1
    done
    if timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q '^yes$'; then
        echo "   clock synchronised, now $(date '+%H:%M:%S %Z')"
    else
        echo "WARNING: clock not synchronised and chrony absent - check 'timedatectl status'."
    fi
    unset _i
fi

# -----------------------------------------------------------------
# 1. APT SOURCES
#
#    The fleet-wide no-recommends lockdown was REMOVED on 31 Aug 2026
#    (Craig's call: match a stock Ubuntu desktop). It used to write
#    APT::Install-Recommends "false" here, and it cost more than it saved.
#
#    Two shipped bugs came from it, both silent, both `Recommends:` of
#    libqt6gui6:
#
#      qt6-svg-plugins      -- no Qt6 app could decode an SVG; quickshell
#                              logged "Unsupported image format" for its own
#                              greeter logo and the avatar was an empty circle
#      qt6-gtk-platformtheme -- every tray icon rendered as a transparency
#                              checkerboard
#
#    Each was found and patched individually before the pattern was spotted,
#    which is the real argument: the policy converts a maintainer's
#    considered "you probably want this too" into a silent absence, and you
#    only discover which ones mattered by shipping and looking.
#
#    Recommends are deliberately NOT disabled here any more. The file is
#    actively removed so re-running on an already-built machine undoes it.
# -----------------------------------------------------------------
sudo rm -f /etc/apt/apt.conf.d/99no-recommends

# --- Wait for the dpkg lock instead of dying on it -------------------------
#
# Found on run 14, 31 Aug 2026. A background unattended-upgrades run held the
# dpkg frontend lock while the install was working:
#
#   dpkg: error: dpkg frontend lock was locked by /usr/bin/python3.14 pid 18704
#   E: /etc/ca-certificates/update.d/jks-keystore exited with code 2.
#
# That instance was harmless -- it only failed to update Java's keystore, not
# the system trust store, and the Oakford CA verified fine afterwards. The
# hazard is not that instance. Ubuntu enables unattended-upgrades and the
# apt-daily timers on every fresh image, so a student running this installer
# shortly after first boot is racing them. Hit an `apt install` rather than a
# post-install hook and `set -e` ends the build.
#
# Being a race, it fails on some laptops and not others, with an error that
# points at whatever package happened to be unlucky -- the worst kind to
# diagnose in a room of students.
#
# Written as apt.conf rather than passed per-command on purpose: it then
# applies to EVERY apt invocation, including the ones inside dankinstall and
# any other sub-installer, which command-line flags cannot reach. Left in place
# afterwards deliberately -- waiting for a lock beats erroring, on a student
# laptop as much as during a build.
echo 'DPkg::Lock::Timeout "600";' | sudo tee /etc/apt/apt.conf.d/99lock-timeout >/dev/null

sudo add-apt-repository -y restricted
sudo add-apt-repository -y multiverse
# `|| echo` deliberately, not a bare call: apt runs Post-Invoke hooks after
# an index update, and a hook that fails takes apt's exit status with it.
# apt-show-versions segfaults this way on Ubuntu 26.04, and under `set -e`
# that aborted the whole install -- at section 7, since section 6 is what
# installs the hook in the first place.
sudo apt update || echo "WARNING: apt update reported an error (usually a post-invoke hook, not the index itself) - continuing."

# -----------------------------------------------------------------
# 2. KERNEL HEADERS, BUILD TOOLS & DRIVER UTILITIES
#
# Install the HWE *meta* packages, not a pinned version. linux-generic-hwe-26.04
# tracks the latest supported 26.04 kernel and rolls forward on normal updates,
# and linux-headers-generic-hwe-26.04 keeps matching headers present so out-of-
# tree modules always build. This is also the track the Canonical-signed
# prebuilt nvidia modules (linux-modules-nvidia-595-generic-hwe-26.04) follow,
# so a kernel bump pulls the matching signed nvidia module automatically - no
# DKMS rebuild, no MOK. The version-pinned linux-headers-$(uname -r) stays as a
# belt-and-braces guarantee of headers for the CURRENTLY running kernel, in case
# anything must DKMS-build before the next reboot.
# -----------------------------------------------------------------
sudo apt install -y \
    linux-generic-hwe-26.04 \
    linux-headers-generic-hwe-26.04 \
    "linux-headers-$(uname -r)" \
    build-essential \
    dkms \
    ubuntu-drivers-common \
    pciutils \
    usbutils \
    software-properties-common \
    libnss3-tools \
    git \
    curl \
    wget \
    stow

# -----------------------------------------------------------------
# 2A. NETWORK TRUST: THE OAKFORD ROOT CA
#
#    Lettered rather than renumbered on purpose. The numbers of the later
#    sections are cited from the project notes and from commit messages,
#    and shifting fourteen of them to insert one here would invalidate
#    every one of those references.
#
#    THE POSITION IS THE POINT. The site firewall intercepts TLS, so any
#    fetch from outside the Ubuntu archives fails certificate validation
#    until this CA is trusted. This block used to live in section 9,
#    two-thirds of the way through the run, which meant the first
#    third-party download -- dankinstall, section 5 -- died on a TLS error
#    and took the whole install down with it under `set -e`. Confirmed at
#    work, 2 Sep 2026: the run stopped at exactly that point, and completed
#    only after the certificate was installed by hand and the script re-run.
#
#    Exactly two things are meant to run before it, and both are safe:
#
#      * Sections 1 and 2, which fetch only from the Ubuntu archives.
#        Ubuntu install and upgrade traffic bypasses the firewall, so it
#        needs no CA -- as does oakfordhelp.co.uk itself, which is what
#        makes the download below possible before its own cert is trusted.
#      * `libnss3-tools` in section 2 specifically, because the
#        Chrome/NSS half of this block needs `certutil`. That dependency
#        is the reason this sits after section 2 rather than at line 1.
#
#    Everything that reaches outside the Ubuntu archives comes after:
#    section 5 (dankinstall), 7 (Chrome), 8 (Flathub), 11 (Node), 12
#    (yt-dlp, tpm, Claude Code). Keep it that way. A new third-party
#    download added ABOVE this line works on every network except the one
#    the fleet actually lives on, which is the worst way to find out.
# -----------------------------------------------------------------

# Download and trust the Oakford CA certificate system-wide.
#
# This installs a ROOT CA (CN=Oakford Internet Services CA, CA:TRUE, valid
# 16 Aug 2024 - 14 Aug 2034). Anything able to substitute this file can
# transparently intercept every TLS connection the machine makes, with no
# browser warning, so it gets two independent protections:
#
#   1. https://, not http://. The plain http:// URL 301-redirects here and
#      wget follows redirects, so the right file did arrive -- but the
#      request STARTED in cleartext, which means an active attacker on the
#      path (school wifi included) could answer with their own CA instead
#      of the redirect and have it trusted fleet-wide. Demanding TLS closes
#      that: the stock Ubuntu trust store validates oakfordhelp.co.uk
#      before a single byte of the certificate is read.
#
#   2. A SHA-256 pin. Fails CLOSED -- on any mismatch the certificate is
#      not installed at all. This also catches a legitimate re-issue, which
#      is deliberate: a new CA should be a conscious decision, not a silent
#      one. When Oakford re-issue, verify the new fingerprint out of band
#      and update the line below. Do not delete the check.
#
# Verified 30 Aug 2026 against both the live host and the copy already
# trusted on dell-ubuntu; the two matched.
OAKFORD_SHA256="70:0D:4D:BA:40:46:29:25:31:7F:9E:C3:33:D5:D7:52:D4:C6:B5:C9:A1:BD:7B:27:BA:B7:12:5C:9C:13:C5:A3"

# Retried: this is the installer's first fetch from outside the Ubuntu
# archives, and it runs early, so it is the most likely thing in the script
# to meet a link that is up but not yet usable on a freshly booted machine.
#
# Downloaded as the normal user, not root: only the install needs privilege.
# No EXIT trap here: this script already owns EXIT for the sudo keepalive
# set up at the top, and re-arming it would silently discard that, leaving a
# stray keepalive loop running after the install finished.
OAKFORD_TMP="$(mktemp)"

if wget -q --tries=3 --retry-connrefused --waitretry=5 --timeout=20 \
        https://oakfordhelp.co.uk/oakford.crt -O "$OAKFORD_TMP"; then
    OAKFORD_GOT="$(openssl x509 -in "$OAKFORD_TMP" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)"
    if [ "$OAKFORD_GOT" = "$OAKFORD_SHA256" ]; then
        sudo install -m 0644 -o root -g root "$OAKFORD_TMP" \
            /usr/local/share/ca-certificates/oakford.crt
        sudo update-ca-certificates

        # Add to Chrome/Chromium NSS store so Chrome trusts internal
        # services. Only reached when the fingerprint matched.
        mkdir -p "$HOME/.pki/nssdb"
        certutil -d sql:"$HOME/.pki/nssdb" -N -f /dev/null 2>/dev/null || true
        certutil -d sql:"$HOME/.pki/nssdb" -A -t "CT,," -n "Oakford CA" \
            -f /dev/null -i /usr/local/share/ca-certificates/oakford.crt || true
    else
        echo "ERROR: Oakford CA fingerprint did NOT match. Certificate NOT installed." >&2
        echo "  expected: $OAKFORD_SHA256" >&2
        echo "  received: ${OAKFORD_GOT:-<not a certificate>}" >&2
        echo "  Internal HTTPS services will not be trusted. Do not work around" >&2
        echo "  this by installing it manually until the new fingerprint is" >&2
        echo "  confirmed with Oakford." >&2
    fi
else
    echo "WARNING: could not download the Oakford CA certificate." >&2
    echo "  On the school network every later third-party download will now" >&2
    echo "  fail TLS validation: dankinstall (5), Chrome (7), Flathub (8)," >&2
    echo "  Node (11), yt-dlp and Claude Code (12). Off site this is harmless" >&2
    echo "  -- the CA is only needed behind the site firewall." >&2
fi

rm -f "$OAKFORD_TMP"

# -----------------------------------------------------------------
# 3. GRAPHICS DRIVERS & HARDWARE VIDEO ACCELERATION
#    Detects the GPU vendor rather than assuming NVIDIA. Students'
#    laptops will mostly be Intel or AMD integrated graphics.
#
#    If they ticked "Install third-party drivers" in the Ubuntu Desktop
#    installer, the NVIDIA branch is effectively a no-op.
# -----------------------------------------------------------------
GPU_INFO="$(lspci -nn | grep -iE 'vga|3d controller|display controller')"
echo "Detected graphics:"
echo "$GPU_INFO" | sed 's/^/    /'

# --- Mesa + VA-API core (needed by every vendor) ---
sudo apt install -y \
    mesa-va-drivers \
    mesa-vulkan-drivers \
    libva2 \
    vainfo \
    vulkan-tools

if echo "$GPU_INFO" | grep -qi nvidia; then
    echo "NVIDIA GPU detected — installing drivers..."
    # autoinstall picks the current recommended branch. Do NOT pin a
    # version here: the old qtile script pinned nvidia:595, but 26.04
    # already ships nvidia-driver-610.
    sudo ubuntu-drivers install --include-dkms || \
        sudo ubuntu-drivers autoinstall || \
        echo "WARNING: NVIDIA driver install failed — check 'ubuntu-drivers devices'."

    sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    # REQUIRED for Wayland. niri will not start correctly on the
    # proprietary driver without DRM kernel mode setting. Recent
    # drivers default it on, but the old X11 qtile script never needed
    # this and it is cheap to be explicit.
    sudo tee /etc/modprobe.d/nvidia-drm-modeset.conf <<'EOF'
options nvidia_drm modeset=1
EOF

    # 26.04 uses dracut, not update-initramfs
    sudo dracut -f
fi

if echo "$GPU_INFO" | grep -qi intel; then
    echo "Intel GPU detected — installing VA-API drivers..."
    # non-free variant covers H.264/HEVC decode on Gen9+; the plain
    # driver is the fallback for older parts.
    sudo apt install -y intel-media-va-driver-non-free || \
        sudo apt install -y intel-media-va-driver || \
        echo "WARNING: Intel VA-API driver not installed — video decode will be CPU-bound."
fi

if echo "$GPU_INFO" | grep -qiE "amd|radeon|advanced micro devices"; then
    echo "AMD GPU detected — amdgpu is in-kernel; ensuring firmware and Vulkan..."
    # linux-firmware is also installed in section 9; harmless if already present.
    sudo apt install -y linux-firmware libdrm-amdgpu1 || true
fi

# -----------------------------------------------------------------
# 3b. REALTEK rtw89 WIFI QUIRK
#
#     The RTL8852BE and its rtw89 siblings hang under PCIe ASPM power
#     management. Observed on real hardware 31 Aug 2026, kernel 7.0.0-30:
#     the adapter stopped answering on the bus and the driver's own error
#     recovery could not bring it back --
#
#       rtw89_8852be 0000:03:00.0: timed out to flush pci txch: 0..9
#       rtw89_8852be 0000:03:00.0: Err: ser L2 re-config timeout
#       rtw89_8852be 0000:03:00.0: mac preinit fail, ret: -110
#
#     followed by a cascade of mac80211 WARNINGs from the failed teardown.
#     Wifi stayed dead until a COLD boot; a warm reboot was not enough,
#     which points at the device needing a real power cycle rather than a
#     soft driver bug.
#
#     Disabling ASPM L1/L1SS and the driver power-save mode is the
#     documented mitigation for this family. It costs a little idle power;
#     a laptop that keeps its network is worth more than that.
#
#     Written only when the hardware is present, so other machines carry no
#     stray modprobe config.
# -----------------------------------------------------------------
if lspci -nn 2>/dev/null | grep -qiE "RTL885[0-9]|Realtek.*802\\.11|802\\.11.*Realtek"; then
    echo "Realtek rtw89 wifi detected - applying the ASPM/power-save quirk..."
    sudo tee /etc/modprobe.d/rtw89-quirks.conf >/dev/null <<MODEOF
# Realtek rtw89: ASPM L1/L1SS causes "timed out to flush pci txch" and an
# unrecoverable "ser L2 re-config timeout". See section 3b of
# ubuntu_26.04_niri_install.sh.
options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y disable_clkreq=y
options rtw89_core disable_ps_mode=y
MODEOF
    # Rebuild the initramfs so the options apply from the first probe, not
    # only after a manual module reload.
    sudo update-initramfs -u >/dev/null 2>&1 || \
        echo "WARNING: initramfs rebuild failed - the quirk still applies after the next reboot."
    echo "Wifi quirk written to /etc/modprobe.d/rtw89-quirks.conf (effective on reboot)."
fi

# -----------------------------------------------------------------
# 4. UBUNTU DESKTOP BASE
#    Provides pipewire/wireplumber (audio), cups + avahi (printing —
#    DNS-SD browsing moved into cupsd itself in CUPS 2.2.4, so the legacy
#    cups-browsed is NOT needed), bluez (bluetooth), the xdg portals, and
#    a GNOME session
#    as a fallback if niri ever fails to start — worth having on a
#    student machine.
#
#    Installing from the Ubuntu 26.04 DESKTOP iso: this is already
#    present and the command is a no-op. Kept so the script also works
#    on a Server base.
#
#    --install-recommends is kept explicit even though it is now the
#    default: ubuntu-desktop pulls most of the actual desktop in via
#    Recommends, so if anyone ever reinstates a no-recommends policy this
#    line still produces a real desktop rather than a hollow one.
#    thunderbird is EXCLUDED. It is not in our package list and nobody asked
#    for it - it only arrives as a Recommends of ubuntu-desktop. The deb is a
#    transitional shim whose postinst runs `snap install thunderbird`, and when
#    that fails (S6C proxy corrupted the .deb download on tf02-teacher, 4 Sep
#    2026) dpkg returns 1 and `set -e` kills the WHOLE build before the package
#    list, greetd, fonts and wallpaper ever install. A Pin-Priority -1 keeps it
#    from being pulled as a recommend. This does NOT stop a student who wants it
#    later: Thunderbird proper is the snap, so `snap install thunderbird` still
#    works and ignores this apt pin entirely.
# -----------------------------------------------------------------
sudo tee /etc/apt/preferences.d/no-thunderbird.pref >/dev/null <<'TBEOF'
Package: thunderbird
Pin: release *
Pin-Priority: -1
TBEOF
sudo apt install -y --install-recommends ubuntu-desktop

# The Desktop iso installs and enables gdm3. dankinstall (section 5)
# installs greetd and repoints display-manager.service, but leaving gdm3
# enabled invites a race over the seat on boot. Disabling is safe: the
# GNOME *session* stays selectable from the dms-greeter session picker,
# which is what actually provides the fallback.
if systemctl list-unit-files gdm3.service >/dev/null 2>&1; then
    echo "Disabling gdm3 in favour of greetd..."
    sudo systemctl disable gdm3 2>/dev/null || true
fi

# ubuntu-desktop drags in update-notifier. Swap it for the harmless
# alternative, so nothing nags the student from the tray.
#
#   Why not just remove it: ubuntu-desktop, ubuntu-desktop-minimal and
#   update-manager all declare the ALTERNATIVE dependency
#   `update-notifier | gnome-package-updater`. One of the two must be
#   installed. `apt-get remove update-notifier` therefore does not leave
#   a gap -- apt pulls in gnome-package-updater to satisfy the
#   alternative, and that is exactly what we want, because:
#
#     * gnome-package-updater ships NO /etc/xdg/autostart entry. It is
#       just /usr/bin/gpk-update-viewer, launched on demand. Nothing
#       appears in the tray.
#     * update-notifier ships TWO autostart entries that do --
#       update-notifier.desktop and, despite the package name,
#       ubuntu-advantage-notification.desktop (the Ubuntu Pro/livepatch
#       nag).
#
#   Do NOT then remove gnome-package-updater: apt would satisfy the
#   alternative by reinstalling update-notifier, undoing this.
#
#   Nothing is lost. DMS ships its own system updater and on Ubuntu
#   reports backends "System, Flatpak" -- it covers apt directly, so a
#   student still has an update path. Verified on dell-ubuntu
#   30 Aug 2026. Fleet updates belong to whoever runs the fleet anyway.
#
#   update-notifier-common is a SEPARATE package and is deliberately
#   left alone: it provides /usr/lib/update-notifier/apt-check, and both
#   ubuntu-server and ttf-mscorefonts-installer depend on it.
#   PURGE, not remove. The two autostart entries are dpkg CONFFILES, so
#   `apt-get remove` leaves them in /etc/xdg/autostart pointing at a
#   binary that no longer exists. Verified on dell-ubuntu 30 Aug 2026:
#   after `remove` the package went to state `rc` and both .desktop
#   files were still there; `purge` cleared them.
if dpkg -l update-notifier 2>/dev/null | grep -qE "^(ii|rc)"; then
    echo "Replacing update-notifier with gnome-package-updater (no tray nag)..."
    sudo apt-get purge -y update-notifier || \
        echo "WARNING: could not purge update-notifier."
fi

# ubuntu-desktop also leaves /etc/xdg/autostart entries that are X11-only
# or assume a system tray. systemd-xdg-autostart-generator turns each one
# into a user unit, so anything that exits non-zero shows up as a FAILED
# UNIT and turns verify-install.sh red -- on a machine that is otherwise
# perfectly healthy.
#
#   Found on ubuntu-craig-office, 2 Sep 2026, the first real NVIDIA box:
#
#     * nvidia-settings-autostart.desktop runs
#       `nvidia-settings --load-config-only`, which needs an X server and
#       exits 1 under a pure Wayland session. This fires on EVERY NVIDIA
#       machine in the fleet, so it is not specific to this desktop.
#     * blueman.desktop starts blueman-applet, which raced obexd during
#       first login and died in TransferService with
#       `g-io-error-quark: Timeout was reached (24)` from a synchronous
#       Gio.DBusObjectManagerClient.new_for_bus_sync call. The crash then
#       cascaded: apport picked the .crash file up and apport-autoreport
#       failed too (see below).
#
#   blueman is deliberately kept INSTALLED -- the package list wants it as
#   the fallback for stubborn pairings -- but blueman-manager is launched
#   on demand, so nothing is lost by not autostarting the applet. DMS has
#   its own bluetooth widget.
#
#   Masked with a user-level Hidden=true entry of the same basename rather
#   than by editing /etc/xdg/autostart: those files are dpkg CONFFILES and
#   an edit conflicts on upgrade. ~/.config takes precedence over /etc/xdg,
#   and Hidden=true stops the generator emitting a unit at all.
#   ~/.config/autostart is NOT stowed (stow symlinks individual .config
#   subdirectories, not .config itself), so a real directory here is safe.
#
#   Everything else the generator emits is left alone on purpose. In
#   particular polkit-gnome-authentication-agent-1 is REQUIRED under niri
#   for authentication prompts, and print-applet is left for the PaperCut
#   work. Only entries that actually fail are masked.
echo "Masking X11-only autostart entries that fail under niri..."
mkdir -p "$HOME/.config/autostart"
for _entry in nvidia-settings-autostart blueman; do
    _src="/etc/xdg/autostart/$_entry.desktop"
    [ -f "$_src" ] || continue
    _name="$(grep -m1 '^Name=' "$_src" | cut -d= -f2-)"
    cat > "$HOME/.config/autostart/$_entry.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${_name:-$_entry}
Exec=/bin/true
Hidden=true
# Masks /etc/xdg/autostart/$_entry.desktop under niri.
# Written by ubuntu_26.04_niri_install.sh -- see the reasoning there.
EOF
    echo "  masked $_entry"
done
unset _entry _src _name

# Stop apport trying to UPLOAD crash reports, while leaving it collecting
# them locally.
#
#   The failure mode, seen on ubuntu-craig-office 2 Sep 2026: a crash file
#   exists in /var/crash, apport-autoreport.path fires, whoopsie-upload-all
#   marks the report and then waits 20 s for whoopsie to confirm an upload.
#   whoopsie.service is `static` and never runs, so the .uploaded marker
#   never appears, the wait times out and the service exits 2. Any machine
#   with a crash file and no running whoopsie fails this way -- it is
#   structural, not a one-off.
#
#   Deliberately NOT setting enabled=0 in /etc/default/apport. Local crash
#   collection is how the blueman-applet bug above was diagnosed, and this
#   build is still being debugged; keeping /var/crash populated is worth
#   more than the disk. What we remove is the upload path, which also means
#   no student machine ships crash dumps to Canonical -- the right default
#   for college-owned hardware regardless of the unit failure.
echo "Disabling apport crash-report upload (keeping local collection)..."
for _u in apport-autoreport.path apport-autoreport.timer whoopsie.path; do
    sudo systemctl disable --now "$_u" 2>/dev/null || true
done
unset _u
sudo systemctl reset-failed apport-autoreport.service 2>/dev/null || true

# -----------------------------------------------------------------
# 5. DANK / NIRI STACK
#    Installs from ppa:avengemedia/danklinux + ppa:avengemedia/dms and
#    configures greetd + dms-greeter as the display manager.
#
#    Headless (unattended) mode is activated by passing --compositor and
#    --term together. The flags below reproduce this dotfiles setup:
#      niri compositor, alacritty terminal, dms-greeter greeter,
#      danksearch (with its user indexing service) and dankcalendar.
#
#    NOTE: dankinstall deploys its own default configs into
#    ~/.config/niri and ~/.config/DankMaterialShell. Section 10 removes
#    them before stow so our tracked versions win.
# -----------------------------------------------------------------
curl -fsSL https://install.danklinux.com | sh -s -- \
    --compositor niri \
    --term alacritty \
    --include-deps dms-greeter \
    --danksearch \
    --dankcalendar \
    --yes

# -----------------------------------------------------------------
# 6. BULK PACKAGES FROM THE LIST
#    One apt transaction for speed; if it fails, retry per-package so a
#    single bad or renamed package cannot abort the whole install.
# -----------------------------------------------------------------
if [ ! -f "$PKG_LIST" ]; then
    echo "ERROR: $PKG_LIST not found."
    exit 1
fi

# Pre-accept the Microsoft fonts EULA (avoids an interactive prompt)
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
    | sudo debconf-set-selections

if ! grep -vE '^\s*(#|$)' "$PKG_LIST" \
        | xargs -r sudo apt install -y; then
    echo "Bulk install failed — retrying individually to isolate the bad package(s)..."
    grep -vE '^\s*(#|$)' "$PKG_LIST" \
        | xargs -r -n1 sudo apt install -y || true
fi

# The Qt6 recommends top-up that used to live here is GONE, because the
# no-recommends policy it worked around is gone (section 1).
#
# It existed to force back two Recommends of libqt6gui6 -- qt6-svg-plugins
# and qt6-gtk-platformtheme -- after the fleet-wide policy dropped them and
# silently broke SVG decoding and every tray icon. Both are now pulled in
# normally, and both remain named explicitly in
# niri_programs_to_install.txt, so they are installed twice over rather
# than not at all.

# -----------------------------------------------------------------
# 7. GOOGLE CHROME
# -----------------------------------------------------------------
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
    | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
    | sudo tee /etc/apt/sources.list.d/google-chrome.list
# `|| echo` deliberately, not a bare call: apt runs Post-Invoke hooks after
# an index update, and a hook that fails takes apt's exit status with it.
# apt-show-versions segfaults this way on Ubuntu 26.04, and under `set -e`
# that aborted the whole install -- at section 7, since section 6 is what
# installs the hook in the first place.
sudo apt update || echo "WARNING: apt update reported an error (usually a post-invoke hook, not the index itself) - continuing."
sudo apt install -y google-chrome-stable

# -----------------------------------------------------------------
# 8. FLATPAK APPS
# -----------------------------------------------------------------
sudo apt install -y flatpak gnome-software-plugin-flatpak
sudo flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo
# Amberol is the music player for students, and deliberately the ONLY one: it
# plays local files, shows embedded cover art, needs no daemon and no config,
# and exports MPRIS so the bar and the media keys work. The MPD/rmpc stack is
# power-user tooling with a daemon, a config file and a database to maintain --
# nothing a student needs in order to play a song.
#
# Flatpak rather than apt: apt ships 2025.1, Flathub is a year newer, and it is
# a Libadwaita app so the newer build is the one that looks right.
FLATPAKS="io.bassi.Amberol"

# BambuStudio and FreeCAD are Craig's, not the fleet's (his call, 31 Aug 2026).
# A 3D-printer slicer and a CAD suite are a large download and a confusing menu
# entry on a laptop issued for study. Kept behind an opt-in rather than deleted,
# so building his own machine does not mean installing them by hand every time:
#
#     S6C_PERSONAL=1 ./ubuntu_26.04_niri_install.sh
#
# Same env-var pattern as S6C_PSK, TARGET_HOSTNAME and PAPERCUT_SERVER.
if [ -n "${S6C_PERSONAL:-}" ]; then
    echo "S6C_PERSONAL set — including Craig's personal flatpaks."
    FLATPAKS="$FLATPAKS com.bambulab.BambuStudio org.freecad.FreeCAD"
fi

# shellcheck disable=SC2086 # deliberate word splitting: a list of app ids
sudo flatpak install -y flathub $FLATPAKS || \
    echo "WARNING: flatpak install failed — retry after reboot."

# -----------------------------------------------------------------
# 9. NETWORKING & WIFI PROFILES
# -----------------------------------------------------------------
sudo apt install -y \
    linux-firmware \
    wpasupplicant \
    iw \
    rfkill

# broadcom-sta-dkms only for machines that actually need it. It blacklists
# b43/brcmsmac/bcma/ssb, so installing it unconditionally across a fleet of
# mixed student laptops can break wifi on Broadcom parts that brcmfmac
# already handles.
if lspci -nn | grep -iE "network|wireless" | grep -qi broadcom; then
    if [ "$SECURE_BOOT" = on ] || [ "$SECURE_BOOT" = unknown ]; then
        # Skipping is strictly better than installing here, and the reason is
        # the blacklist noted above. broadcom-sta-dkms blacklists b43,
        # brcmsmac, bcma and ssb -- and a locked-down kernel then refuses to
        # load the unsigned replacement. Installing it under Secure Boot
        # therefore disables the in-kernel drivers that might have worked AND
        # supplies nothing in their place: a machine that reports a clean
        # install and has no wifi at all. Leaving it out keeps whatever
        # brcmfmac can manage.
        echo "WARNING: Broadcom wireless found, but Secure Boot is $SECURE_BOOT." >&2
        echo "         broadcom-sta-dkms is unsigned and out-of-tree, so a locked-down" >&2
        echo "         kernel will refuse it. Installing it would also blacklist the" >&2
        echo "         in-kernel drivers, leaving NO wifi at all. Skipped." >&2
        echo "         Disable Secure Boot and re-run this script." >&2
        BROADCOM_BLOCKED=yes
    else
        echo "Broadcom wireless detected — installing broadcom-sta-dkms..."
        sudo apt install -y broadcom-sta-dkms || \
            echo "WARNING: broadcom-sta-dkms failed — check wifi after reboot."
    fi
else
    echo "No Broadcom wireless detected — skipping broadcom-sta-dkms."
fi

sudo rfkill unblock wifi

# Disable the installer's netplan config to prevent renderer conflicts
sudo mv /etc/netplan/00-installer-config.yaml \
    /etc/netplan/00-installer-config.yaml.bak 2>/dev/null || true

# Hand full network control to NetworkManager. This is what lets students
# add their own home wifi and VPN profiles from the desktop.
sudo tee /etc/netplan/01-network-manager-all.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
sudo chmod 600 /etc/netplan/01-network-manager-all.yaml
sudo netplan apply

# `netplan apply` tears down and rebuilds the network stack, and on a fresh
# desktop it also hard-restarts systemd-networkd (which is not running yet,
# so its dbus reload fails and it says so loudly -- that noise is expected
# and netplan still exits 0). Wait for it to come back before touching
# NetworkManager below.
#
# This wait was originally added for the Oakford CA download, which used to
# run here and died with wget's exit 4, "network failure", when it raced the
# restart -- timing-dependent, so it did not fail every time, but it killed
# the first full VM run at this exact line. The CA moved to section 2A on
# 2 Sep 2026. The wait stays: `nmcli connection reload` further down wants a
# settled NetworkManager just as much.
echo "Waiting for the network to come back after netplan apply..."
if ! nm-online -q --timeout=60; then
    echo "WARNING: network not online 60s after netplan apply; continuing anyway." >&2
fi


# School wifi profile.
#
# The PSK is committed here deliberately. It is the BYOD network key,
# already known to every current and former student, so treating it as a
# secret bought nothing and cost a great deal: without it the profile was
# skipped, and an unattended build produced a student laptop that could
# not reach the school network -- the one thing it most needs to do.
# Craig's call, 31 Aug 2026.
#
# Override for a different network or after a key change:
#
#     S6C_PSK='...' ./ubuntu_26.04_niri_install.sh
#
# NOTE the SINGLE quotes. This key contains two '!' characters, which an
# interactive bash will treat as history expansion inside double quotes
# ("bash: !BY0D: event not found"). Inside this script it is safe: the
# heredoc below is expanded by the script, not by an interactive shell.
#
# autoconnect-priority is negative so a student's own home network wins
# whenever both are in range; NetworkManager would otherwise pick
# arbitrarily between two autoconnect profiles.
# NOTE ${VAR-default}, with NO colon: that substitutes only when the
# variable is UNSET. The colon form also substitutes when it is set but
# EMPTY, which would have made the documented S6C_PSK='' opt-out
# silently install the profile anyway.
S6C_PSK="${S6C_PSK-!BY0D!S6C}"

if [ -n "${S6C_PSK:-}" ]; then
    # DE-DUPLICATE BEFORE WRITING ANYTHING.
    #
    # On a laptop, joining S6C by hand BEFORE running this script is not
    # operator error -- it is the only way to start. The XPS has no ethernet
    # port, and everything below this line needs the network: apt, the
    # Oakford CA, the Chrome repo, node, yt-dlp. So every laptop reaches
    # this point with an S6C connection already in place.
    #
    # NetworkManager persists that hand-made connection through netplan, as
    # /etc/netplan/90-NM-<uuid>.yaml regenerated under /run, and it carries
    # the DEFAULT autoconnect-priority of 0. Dropping our keyfile alongside
    # it leaves TWO autoconnect profiles for one SSID, and NetworkManager
    # picks between them. On s6c-ubuntu-xps-craig (3 Sep 2026) it picked the
    # netplan one: the install reported success, and the -10 we had just
    # written sat inert in a profile nothing used. The 2 Sep desktop was
    # WIRED, so it had no pre-existing wifi profile and never showed this.
    #
    # Modify what is already there rather than deleting it. On a wifi
    # install that connection is carrying this script -- `nmcli connection
    # delete` on it drops the network mid-run.
    S6C_CONNS="$(nmcli -t -f UUID,TYPE connection show 2>/dev/null || true)"
    S6C_EXISTING=""
    while IFS=: read -r _uuid _type; do
        [ "$_type" = "802-11-wireless" ] || continue
        [ "$(nmcli -g 802-11-wireless.ssid connection show "$_uuid" 2>/dev/null)" = "S6C" ] || continue
        S6C_EXISTING="$S6C_EXISTING $_uuid"
    done <<< "$S6C_CONNS"
    S6C_EXISTING="$(printf '%s' "$S6C_EXISTING" | xargs || true)"
fi

if [ -n "${S6C_PSK:-}" ] && [ -n "${S6C_EXISTING:-}" ]; then
    for _uuid in $S6C_EXISTING; do
        echo "Existing S6C profile $_uuid — setting autoconnect-priority=-10 in place."
        sudo nmcli connection modify "$_uuid" \
            connection.autoconnect yes \
            connection.autoconnect-priority -10 \
            || echo "WARNING: could not set the priority on S6C profile $_uuid." >&2
    done
elif [ -n "${S6C_PSK:-}" ]; then
    sudo mkdir -p /etc/NetworkManager/system-connections
    sudo tee /etc/NetworkManager/system-connections/S6C.nmconnection > /dev/null <<EOF
[connection]
id=S6C
type=wifi
autoconnect=true
autoconnect-priority=-10

[wifi]
mode=infrastructure
ssid=S6C

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${S6C_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF
    sudo chmod 600 /etc/NetworkManager/system-connections/S6C.nmconnection
    # Tell NetworkManager the keyfile exists. Dropping a file into
    # system-connections/ does NOT make NM read it -- without this reload the
    # profile stays invisible to `nmcli connection show` until the next reboot
    # or NM restart, so the machine has no school wifi for the rest of the
    # session while the installer reports success.
    #
    # Found on run 12, 31 Aug 2026, by the NetworkManager-based check added in
    # 2e19b02. The previous filesystem-based check could never have seen it:
    # the file was always written correctly, and being on disk was all it
    # tested for.
    sudo nmcli connection reload 2>/dev/null || \
        echo "WARNING: 'nmcli connection reload' failed — the S6C profile will load on the next reboot."
    echo "School wifi profile installed."
else
    # Only reachable if someone explicitly passes S6C_PSK='' to opt out.
    echo "S6C_PSK empty — skipping the school wifi profile."
fi

# Assert what we just did, because this exact fault was SILENT: the install
# exited 0 with a priority-0 profile in charge. Warn only -- a wifi
# priority is not worth aborting a build over, and verify-install.sh fails
# on it properly.
if [ -n "${S6C_PSK:-}" ]; then
    S6C_CONNS="$(nmcli -t -f UUID,TYPE connection show 2>/dev/null || true)"
    while IFS=: read -r _uuid _type; do
        [ "$_type" = "802-11-wireless" ] || continue
        [ "$(nmcli -g 802-11-wireless.ssid connection show "$_uuid" 2>/dev/null)" = "S6C" ] || continue
        _prio="$(nmcli -g connection.autoconnect-priority connection show "$_uuid" 2>/dev/null | xargs || true)"
        case "${_prio:-?}" in
            -*) ;;
            *)  echo "WARNING: S6C profile $_uuid has autoconnect-priority '${_prio:-unreadable}'; it may outrank the user's own network." >&2 ;;
        esac
    done <<< "$S6C_CONNS"
fi

# -----------------------------------------------------------------
# 10. DOTFILES — DE-CONFLICT, THEN STOW
#
#     dankinstall (section 5) deployed its own configs into
#     ~/.config/niri and ~/.config/DankMaterialShell. They must be
#     removed before stow, for two reasons:
#
#       1. stow cannot fold a directory that already exists, so it would
#          create per-FILE symlinks inside a real directory.
#       2. DMS writes settings.json atomically (temp file + rename),
#          which REPLACES a symlinked file with a regular one. The config
#          would silently detach from the repo on the first settings
#          change.
#
#     Directory-level symlinks survive that; per-file ones do not.
#     Never use `stow --adopt` here — it would pull dankinstall's
#     freshly-deployed defaults INTO the repo, overwriting yours.
# -----------------------------------------------------------------
#     alacritty is in this list for the same reason as of 2 Sep 2026. The repo
#     now owns ~/.config/alacritty, because Claude Code's `/terminal-setup`
#     APPENDS an `[[keyboard.bindings]]` array-of-tables to whatever
#     dankinstall generated -- and dankinstall writes `bindings` as an INLINE
#     ARRAY. TOML forbids redefining a key already set as an inline array, so
#     the file stops parsing entirely:
#
#         TOML parse error at line 39 ... duplicate key
#
#     Alacritty then refuses to start with the user's config. Owning the file
#     here means the Shift+Enter binding ships correct and version-controlled,
#     rather than being bolted on afterwards by a tool that cannot see what is
#     already in the file.
for d in niri DankMaterialShell danksearch alacritty; do
    if [ -e "$HOME/.config/$d" ] && [ ! -L "$HOME/.config/$d" ]; then
        echo "Removing dankinstall's default $d config (repo version wins)..."
        rm -rf "$HOME/.config/$d"
    fi
done

# A fresh Ubuntu install seeds $HOME from /etc/skel — ~/.bashrc and
# ~/.profile among them. stow refuses to overwrite a real file and aborts
# the WHOLE deployment, so move aside any top-level dotfile that the repo
# also provides. Symlinks are left alone, making this safe to re-run.
cd "$DOTFILES_DIR"
while IFS= read -r f; do
    if [ -f "$HOME/$f" ] && [ ! -L "$HOME/$f" ]; then
        echo "Moving aside default $f (repo version wins)..."
        mv "$HOME/$f" "$HOME/$f.pre-stow.bak"
    fi
done < <(find . -maxdepth 1 -type f -name '.*' -printf '%f\n')

# Do NOT mkdir anything stow provides — see the note above.
#
# NOTE: `stow -n` always writes "WARNING: in simulation mode..." to
# stderr, so that line must be filtered out before testing for conflicts.
# Without the filter the check always trips and stow never runs.
STOW_CONFLICTS="$(stow -n . 2>&1 | grep -v 'in simulation mode' || true)"
if [ -n "$STOW_CONFLICTS" ]; then
    echo "WARNING: stow reported conflicts (dry run):"
    echo "$STOW_CONFLICTS" | sed 's/^/    /'
    echo "Resolve the above, then run 'stow .' from $DOTFILES_DIR manually."
else
    stow .
    echo "Dotfiles stowed."
fi

fc-cache -f

# --- Default wallpaper ---------------------------------------------
#
#     The image itself ships in the repo and stow puts it at
#     ~/.local/share/backgrounds/0288.jpg. Two things still have to be
#     pointed AT it, and stow covers neither:
#
#       1. The greeter runs as user `greeter`, not as the logged-in
#          user, and greeterWallpaperPath lives in the repo's
#          settings.json -- ONE file shared by every machine. An
#          absolute path under /home/<someone> is therefore wrong on
#          any machine with a different username, and would also lean
#          on the greeter ACL over that home directory. So the image is
#          installed to a system-wide, world-readable path instead and
#          the setting points there.
#
#       2. The desktop wallpaper is `wallpaperPath` in
#          ~/.local/state/DankMaterialShell/session.json. That is
#          runtime STATE, deliberately not stowed, so on a new machine
#          it starts empty and the desktop comes up on DMS's default
#          dark gradient. Seed it here -- but only if the user has not
#          already chosen something, so re-running never overwrites a
#          preference.
#
#     Not fatal: a machine with no wallpaper still boots to a usable
#     desktop, so every step below is guarded under `set -e`.
S6C_WALLPAPER_SRC="$HOME/.local/share/backgrounds/0288.jpg"
S6C_WALLPAPER="/usr/share/backgrounds/s6c/ladybird.jpg"

if [ -f "$S6C_WALLPAPER_SRC" ]; then
    if sudo install -d -m 0755 /usr/share/backgrounds/s6c &&
       sudo install -m 0644 "$S6C_WALLPAPER_SRC" "$S6C_WALLPAPER"; then
        echo "Default wallpaper installed to $S6C_WALLPAPER"
    else
        echo "WARNING: could not install the default wallpaper system-wide."
    fi

    S6C_SESSION_JSON="$HOME/.local/state/DankMaterialShell/session.json"
    mkdir -p "$(dirname "$S6C_SESSION_JSON")"
    python3 - "$S6C_SESSION_JSON" "$S6C_WALLPAPER" <<'PYEOF' ||         echo "WARNING: could not seed the desktop wallpaper."
import json, os, sys

path, wallpaper = sys.argv[1], sys.argv[2]
try:
    with open(path) as fh:
        data = json.load(fh)
except (FileNotFoundError, ValueError):
    data = {}

if data.get("wallpaperPath"):
    print("Desktop wallpaper already set (%s) -- left alone." % data["wallpaperPath"])
else:
    data["wallpaperPath"] = wallpaper
    # DMS itself writes this file atomically; match that so a running
    # shell never reads a half-written file.
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
    os.replace(tmp, path)
    print("Desktop wallpaper seeded to %s" % wallpaper)
PYEOF
else
    echo "WARNING: $S6C_WALLPAPER_SRC not found after stow -- skipping wallpaper setup."
fi

# --- Default user avatar --------------------------------------------
#
#     Without this the greeter shows an empty circle where the user's
#     face should be. That is an upstream DMS bug, not a missing file:
#     GreeterContent.qml passes `fallbackIcon: "person"` to
#     DankCircularImage, and AppIconRenderer dispatches on a PREFIX --
#     "material:" for a Material Symbols glyph, "svg:"/"image:" for a
#     path, and anything unprefixed goes to a freedesktop icon-theme
#     lookup. "person" is unprefixed, and no installed theme has an icon
#     by that name (Material Symbols does, but it would have to be
#     "material:person"), so the fallback silently draws nothing.
#
#     Patching the shipped QML is not an option on a fleet -- the next
#     package update would revert it. Instead give the greeter a real
#     image to find. Its lookup order is:
#
#       <cache>/profile.{jpg,jpeg,png,webp}
#       /var/lib/AccountsService/icons/<user>
#       ~/.face
#       ~/.face.icon
#
#     ~/.face is the friendliest of those: owned by the user, so they can
#     replace it without root, and the greeter's own avatar picker will
#     override it.
#
#     The image is ours, stowed from the repo, rather than Yaru's
#     avatar-default.png -- Yaru's icons are CC-BY-SA and this repo is
#     public. It is navy #022B3A on cream #FAF7F0 to match brand.md
#     (13.93:1, AAA) instead of Yaru's bright blue, which clashes badly
#     with a warm wallpaper. See .local/share/s6c/README.md.
#
#     Only seeds when absent, so re-running never overwrites a user's
#     own picture.
S6C_AVATAR_SRC="$HOME/.local/share/s6c/avatar-default.png"
if [ ! -f "$HOME/.face" ] && [ ! -f "$HOME/.face.icon" ]; then
    if [ -f "$S6C_AVATAR_SRC" ]; then
        cp "$S6C_AVATAR_SRC" "$HOME/.face" && chmod 0644 "$HOME/.face" && \
            echo "Seeded default user avatar at ~/.face" || \
            echo "WARNING: could not seed the default avatar."
    else
        echo "WARNING: $S6C_AVATAR_SRC not found after stow -- skipping default avatar."
    fi
else
    echo "User avatar already present -- left alone."
fi

# --- Push settings and theme into the greeter -----------------------
#
#     dankinstall (section 5) sets greetd up, but it does NOT reconcile
#     the greeter with THIS user's settings, and nothing else here did
#     either -- so before this line the build shipped a greeter that was
#     missing four separate things. `dms greeter status` on a machine
#     built by the old script reports them:
#
#       * The greeter wallpaper never appears. greeterWallpaperPath is
#         only a SOURCE path; the greeter actually loads a fixed file,
#         <cache>/greeter_wallpaper_override.jpg, and only the sync
#         copies it there. Setting the path alone does nothing at all,
#         silently -- verified in the test VM 30 Aug 2026.
#       * Greeter colours are never generated from the wallpaper, and
#         the dms-colors.json symlink points at the wrong file.
#       * /etc/pam.d/dankshell is not created -- that is the PAM stack
#         the LOCK SCREEN authenticates against.
#       * The DMS AppArmor profile is not installed. `dms greeter status`
#         flags this itself: "Run 'dms greeter sync' to install it and
#         prevent potential TTY fallback".
#
#     Must run AFTER stow (so it reads the repo's settings.json, not
#     dankinstall's) and AFTER the wallpaper is in place above.
#
#     Not fatal: a failed sync leaves a plain but working greeter.
#     DMS_PRIVESC pins the privilege-escalation tool. Without it, `dms
#     greeter sync` detects both sudo and run0 and STOPS to ask:
#
#         Multiple privilege escalation tools detected:
#           [1] sudo  [2] run0
#         Choose one [1-2] (default 1, ...):
#
#     It only asks when stdin is a terminal -- which is exactly the
#     documented student route, `bash <(wget ...)` typed at a prompt. Every
#     VM run before this one drove the install over ssh with no pty, so the
#     prompt never appeared and three "clean" runs missed it. A student
#     would have been left staring at an unexplained question two thirds of
#     the way through, and an automated run with a pty hangs on it outright.
if command -v dms >/dev/null 2>&1; then
    echo "Syncing settings, theme and wallpaper into the greeter..."
    if DMS_PRIVESC=sudo dms greeter sync; then
        echo "Greeter synced."
    else
        echo "WARNING: 'dms greeter sync' failed. The greeter will still start,"
        echo "         but it will show default colours and no wallpaper, and the"
        echo "         lock screen PAM file may be missing. Re-run it by hand."
    fi
else
    echo "WARNING: 'dms' not on PATH -- skipping greeter sync."
fi

# -----------------------------------------------------------------
# 11. NODE.JS
# -----------------------------------------------------------------
if [ -f "$SCRIPT_DIR/install_node.sh" ]; then
    # install_node.sh git-clones node_install into the CURRENT directory, and
    # section 10 left us in $DOTFILES_DIR. Run it from install_programs/ so the
    # clone lands where .gitignore expects it, not in the repo root.
    ( cd "$SCRIPT_DIR" && bash ./install_node.sh )
else
    echo "WARNING: install_node.sh not found at $SCRIPT_DIR — skipping Node.js install."
fi

export NVM_DIR="$HOME/.nvm"
# NOT `[ -s ... ] && . ...` : under `set -e` a false test makes the whole
# AND-list return non-zero and aborts the script silently.
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
else
    echo "WARNING: nvm not found — skipping the npm-based installs below."
fi

# -----------------------------------------------------------------
# 12. YT-DLP, TPM, CLAUDE CODE, ANTIGRAVITY CLI
# -----------------------------------------------------------------
sudo wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -O /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp

# --- Keep yt-dlp current, automatically -----------------------------------
#
# yt-dlp is the one tool in this build whose failure mode is EXTERNAL: when
# YouTube changes something, every existing copy stops working until it is
# updated. Nothing on the machine caused it and nothing on the machine fixes it.
#
# That is why it is fetched from GitHub rather than apt -- apt's build was five
# months behind at the time of writing. But a build-time fetch only pins the
# problem to the build date: a laptop imaged in September breaks in October and
# the student has no idea why.
#
# `yt-dlp -U` replaces the binary in place, so a root-owned single file plus a
# systemd timer is the entire mechanism. No pip, no pipx, no second package
# manager to keep working.
sudo tee /etc/systemd/system/yt-dlp-update.service >/dev/null <<'EOF'
[Unit]
Description=Update yt-dlp to the latest release
Documentation=https://github.com/yt-dlp/yt-dlp
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/yt-dlp -U
# A failed update must never look like a broken machine. The binary already on
# disk keeps working and the next run tries again, so a non-zero exit here is
# not a fault worth reporting.
SuccessExitStatus=0 1
EOF

sudo tee /etc/systemd/system/yt-dlp-update.timer >/dev/null <<'EOF'
[Unit]
Description=Daily yt-dlp update

[Timer]
OnCalendar=daily
# Spread a fleet's requests rather than having every laptop in the college hit
# GitHub at the same second.
RandomizedDelaySec=2h
# This matters more than the schedule. These are laptops: they are asleep or
# shut at 03:00, and without Persistent a missed timer is simply skipped, so a
# machine that is never awake at the right moment never updates at all.
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable yt-dlp-update.timer
# `enable --now` is a no-op on an already-running unit -- the same trap that let
# the zram algorithm silently stay lz4 (failure log bug 6). Restart explicitly
# so a changed timer actually takes effect on a re-run.
sudo systemctl restart yt-dlp-update.timer

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi

curl -fsSL https://claude.ai/install.sh | bash || \
    echo "WARNING: Claude Code install failed — install manually after reboot."

# Tell Claude Code its Shift+Enter binding is already installed, because it is:
# the repo's ~/.config/alacritty/alacritty.toml ships
# `{ key = "Enter", mods = "Shift", chars = "\u001B\r" }` inside the existing
# inline `bindings` array (see section 10).
#
# Without this, running `/terminal-setup` APPENDS an `[[keyboard.bindings]]`
# array-of-tables block, which is a TOML duplicate-key error against that
# inline array and stops alacritty parsing its config at all. Craig hit exactly
# that on ubuntu-craig-office, 2 Sep 2026.
#
# Belt and braces with section 10: section 10 makes the binding correct, this
# stops anything appending a second definition of it later.
CLAUDE_JSON="$HOME/.claude.json"
if command -v python3 >/dev/null 2>&1; then
    python3 - "$CLAUDE_JSON" <<'PYEOF' || echo "WARNING: could not seed shiftEnterKeyBindingInstalled."
import json, os, sys
p = sys.argv[1]
try:
    d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
except (ValueError, OSError):
    print("   .claude.json unreadable or not JSON; leaving it alone")
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
if d.get("shiftEnterKeyBindingInstalled") is True:
    print("   shiftEnterKeyBindingInstalled already set")
    sys.exit(0)
d["shiftEnterKeyBindingInstalled"] = True
tmp = p + ".tmp"
with open(tmp, "w") as f:
    json.dump(d, f, indent=2)
os.replace(tmp, p)
print("   seeded shiftEnterKeyBindingInstalled=true (stops /terminal-setup breaking the alacritty config)")
PYEOF
fi

# Antigravity CLI: REMOVED 31 Aug 2026 (Craig's call).
#
# It was the replacement for Gemini CLI, which Google deprecated on
# 2026-06-18 for exactly the tiers students would be on. Dropped for three
# reasons found on the first real hardware build:
#
#   1. It installs a 199 MB Go binary at ~/.local/bin/agy -- and
#      ~/.local/bin is a stow symlink INTO the dotfiles repo, so the blob
#      lands in the working tree and shows up in `git status`.
#   2. Its installer appends `export PATH="/home/<user>/.local/bin:$PATH"`
#      to BOTH .bashrc and .bash_profile, unconditionally. That is
#      redundant -- .bash_profile already adds ~/.local/bin -- and it
#      hardcodes an absolute home path, so it dirties two TRACKED files on
#      every single build.
#   3. Nobody had asked for it.
#
# If it is ever wanted back, add `.local/bin/agy` handling first: the
# .gitignore entry for it stays in place deliberately, so a hand install
# does not pollute the repo.

# -----------------------------------------------------------------
# 13. MACHINE IDENTITY: KEYBOARD, LOCALE, TIMEZONE, HOSTNAME
#     config.kdl leaves niri's xkb block empty on purpose, so niri reads
#     the layout from org.freedesktop.locale1. Without this, a fresh
#     install gives students a US keyboard.
# -----------------------------------------------------------------
# NOT `localectl set-x11-keymap`. Ubuntu ships
#     /usr/share/dbus-1/system.d/org.freedesktop.locale1.read-only.conf
# which denies SetX11Keyboard and SetVConsoleKeyboard on the system bus to
# *every* caller, root included:
#     Rejected send message, 5 matched rules; ... uid=0 ...
#     member="SetX11Keyboard" ... error-name=...DBus.Error.AccessDenied
# Keyboard config on Ubuntu belongs to console-setup, so localed may only
# read it, never write it. Under `set -e` that one line aborted the whole
# script, taking sections 13-16 with it.
#
# localed still *reports* the layout over locale1, which is what niri
# consumes, so writing the file gets us exactly the property we need --
# verified: setting XKBLAYOUT=de made `localectl status` report de.
sudo tee /etc/default/keyboard >/dev/null <<'KBD'
# Managed by ubuntu_26.04_niri_install.sh
XKBMODEL="pc105"
XKBLAYOUT="gb"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KBD

# Seed debconf too, so a later `dpkg-reconfigure keyboard-configuration`
# agrees with the file instead of reverting it.
sudo debconf-set-selections <<'DEBCONF' || true
keyboard-configuration keyboard-configuration/modelcode string pc105
keyboard-configuration keyboard-configuration/layoutcode string gb
DEBCONF

# Applies to the virtual consoles. Exits 0 with a note when run off-console
# (e.g. over ssh), so it is safe under set -e either way.
sudo setupcon --save || true
sudo systemctl try-restart systemd-localed.service || true

# SetLocale is *not* in that deny list, so this one still works over D-Bus.
sudo localectl set-locale LANG=en_GB.UTF-8

# The Desktop installer asks for a timezone, but an unattended/preseeded
# install can land on UTC, which silently skews every timestamp students see.
sudo timedatectl set-timezone Europe/London
# Time sync used to live here. It moved to SECTION 0, ahead of everything
# else, because a skewed clock breaks TLS validation and apt's Release-file
# validity window - both of which happen long before this point. See there.


# Hostname. A fleet of machines all called "ubuntu" is miserable to
# manage - you cannot tell them apart in DHCP leases, print queues or
# ssh known_hosts. Supply it either way round:
#
#     TARGET_HOSTNAME=s6c-laptop-07 ./ubuntu_26.04_niri_install.sh
#     ./ubuntu_26.04_niri_install.sh        (prompts, blank = keep current)
CURRENT_HOSTNAME="$(hostname)"
if [ -z "${TARGET_HOSTNAME:-}" ] && [ -t 0 ]; then
    read -r -p "Hostname for this machine [$CURRENT_HOSTNAME]: " TARGET_HOSTNAME
fi

if [ -n "${TARGET_HOSTNAME:-}" ] && [ "$TARGET_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
    # RFC 1123: letters, digits and hyphens only, not starting or ending
    # with a hyphen. An invalid hostname breaks sudo's reverse lookup.
    if printf '%s' "$TARGET_HOSTNAME" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'; then
        echo "Setting hostname to $TARGET_HOSTNAME ..."
        sudo hostnamectl set-hostname "$TARGET_HOSTNAME"
        # /etc/hosts still maps 127.0.1.1 to the OLD name. Leaving it stale
        # makes every sudo call wait on a failed name lookup first.
        sudo sed -i "s/\b${CURRENT_HOSTNAME}\b/${TARGET_HOSTNAME}/g" /etc/hosts
    else
        echo "WARNING: '$TARGET_HOSTNAME' is not a valid hostname — keeping $CURRENT_HOSTNAME."
    fi
fi

# -----------------------------------------------------------------
# 14. POST-INSTALL CONFIGURATION
#     greetd is enabled LAST so that a failure earlier in this script
#     leaves a working TTY rather than a broken graphical boot.
# -----------------------------------------------------------------
xdg-user-dirs-update

# zram compressed swap. zram-tools installs /etc/default/zramswap but does
# not necessarily enable the unit, and its default ALGO is lz4. zstd
# compresses substantially better, which matters more than raw speed on
# the 4-8GB laptops this targets.
if [ -f /etc/default/zramswap ]; then
    sudo sed -i 's/^ALGO=.*/ALGO=zstd/'   /etc/default/zramswap
    sudo sed -i 's/^PERCENT=.*/PERCENT=50/' /etc/default/zramswap
    # `enable --now` is NOT enough. zram-tools' postinst already started
    # zramswap when the package was installed back in the package sweep, and
    # `--now` is a no-op on a unit that is already running -- so the ALGO edit
    # above never reached the running device and every machine silently kept
    # the default lz4. Verified on dell-ubuntu 30 Aug 2026: zramctl reported
    # lz4 with ALGO=zstd sitting in the config file; a restart produced zstd.
    sudo systemctl enable zramswap.service || true
    sudo systemctl restart zramswap.service || \
        echo "WARNING: zramswap did not start — check 'zramctl' after reboot."
else
    echo "WARNING: /etc/default/zramswap missing — is zram-tools installed?"
fi

# Deep sleep (S3) where the firmware actually offers it.
#
# The XPS 13 9310 of the first laptop build (3 Sep 2026) reports
# `ACPI: PM: (supports S0 S4 S5)` -- no S3 at all -- so /sys/power/mem_sleep
# offers only [s2idle]. Modern Standby drains a shut laptop in a way S3 does
# not. NOTHING in Linux can conjure S3 on such a machine: mem_sleep_default
# is ignored outright when the firmware never advertised the state, which is
# why this is conditional by necessity rather than by caution.
#
# It still earns its place, because the fleet is not all XPS. Older Latitudes
# and ThinkPads -- the likely shape of a second-hand student laptop -- do
# advertise S3, and Ubuntu still defaults them to s2idle.
#
# Deliberately NOT gated on Secure Boot. A GRUB command line is unaffected by
# kernel lockdown, unlike hibernation, which lockdown forbids outright. We
# assume Secure Boot stays ON in the field -- students will not turn it off
# whatever they are told -- so anything that needs it off is not a fleet
# option. See notes/sleep-and-hibernate-plan-2026-09-04.md.
GRUB_FILE=/etc/default/grub
if [ ! -r /sys/power/mem_sleep ]; then
    echo "No /sys/power/mem_sleep — skipping deep sleep configuration."
elif ! grep -qw deep /sys/power/mem_sleep; then
    echo "Firmware advertises no S3 (mem_sleep: $(cat /sys/power/mem_sleep)) — leaving suspend at s2idle."
elif [ ! -f "$GRUB_FILE" ]; then
    echo "WARNING: S3 is available but $GRUB_FILE is missing — cannot make it the default." >&2
elif grep -q 'mem_sleep_default=deep' "$GRUB_FILE"; then
    echo "Deep sleep is already the default in $GRUB_FILE."
else
    echo "Firmware offers S3 — making deep sleep the default."
    # Strip any previous mem_sleep_default= first, so re-running this script
    # cannot accumulate two of them on one command line.
    sudo sed -i -E 's/[[:space:]]*mem_sleep_default=[^ "]*//g' "$GRUB_FILE" || true
    sudo sed -i -E 's|^(GRUB_CMDLINE_LINUX_DEFAULT=")(.*)"|\1\2 mem_sleep_default=deep"|' "$GRUB_FILE" || true
    # Tidy the leading space left when the command line started out empty.
    sudo sed -i -E 's|^(GRUB_CMDLINE_LINUX_DEFAULT=")[[:space:]]+|\1|' "$GRUB_FILE" || true
    # Assert rather than assume. A substitution that quietly did nothing here
    # is invisible until someone shuts the lid a week later and finds a flat
    # battery -- the same class of silent fault as the wifi priority.
    if grep -q 'mem_sleep_default=deep' "$GRUB_FILE"; then
        sudo update-grub || \
            echo "WARNING: update-grub failed — deep sleep applies at the next successful update-grub." >&2
    else
        echo "WARNING: could not add mem_sleep_default=deep to $GRUB_FILE — suspend stays s2idle." >&2
    fi
fi

# Two things that stop a machine coming back from suspend, fixed only where
# they are present: Realtek rtw89 wifi (RTL8852BE family) never returns from
# S3 with its driver bound, so a sleep hook reloads the driver across the
# sleep; and an rclone FUSE mount holds tasks in D state so the freezer gives
# up, so a system unit stops the mount before sleep and restarts it after.
# Detection, reasoning and the 5 Sep 2026 evidence live in setup-suspend.sh.
# On most student laptops it prints two "not needed" lines. Never fails the
# build.
bash "$SCRIPT_DIR/setup-suspend.sh" || echo "WARNING: setup-suspend.sh failed — check suspend/resume by hand." >&2

sudo systemctl enable udisks2
sudo systemctl enable cups          || true
sudo systemctl enable avahi-daemon  || true
sudo systemctl enable greetd
sudo systemctl set-default graphical.target

# -----------------------------------------------------------------
# 15. PER-STUDENT GIT IDENTITY & GITHUB ACCESS
#
#     IMPORTANT: nothing in this script uses the maintainer's GitHub key,
#     and it must stay that way. A shared private key across a fleet of
#     student laptops is a shared credential: it cannot be attributed to
#     anyone, any one lost laptop exposes it, and revoking it breaks every
#     machine at once.
#
#     bootstrap.sh therefore clones this repo over HTTPS, so no key at all
#     is needed to INSTALL. A credential is only needed to PUSH, and each
#     student sets up their own below.
# -----------------------------------------------------------------

# Make sure the clone is on an HTTPS remote. If someone cloned with SSH
# using a borrowed key, rewrite it so pushes prompt for the student's own
# GitHub credentials instead of silently using that key.
if git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null | grep -q '^git@github.com:'; then
    OLD_URL="$(git -C "$DOTFILES_DIR" remote get-url origin)"
    NEW_URL="https://github.com/${OLD_URL#git@github.com:}"
    echo "Rewriting origin to HTTPS so pushes use this student's own credentials:"
    echo "    $OLD_URL  ->  $NEW_URL"
    git -C "$DOTFILES_DIR" remote set-url origin "$NEW_URL"
fi

# Generate a per-machine SSH key if there isn't one. No passphrase: under
# niri there is no graphical ssh-askpass in the default session, so a
# passphrased key would prompt into a void. Students who want one can add
# it later with `ssh-keygen -p -f ~/.ssh/id_ed25519`.
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating a per-machine SSH key..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -C "$(whoami)@$(hostname)" \
        -f "$HOME/.ssh/id_ed25519" >/dev/null
fi

GIT_IDENTITY_SET=yes
if [ -z "$(git config --global user.email 2>/dev/null || true)" ]; then
    GIT_IDENTITY_SET=no
fi

# -----------------------------------------------------------------
# 16. PAPERCUT PRINTING
#
#     School printers are PaperCut. The finding that shapes this whole
#     section: MOBILITY PRINT HAS NO LINUX CLIENT. PaperCut support
#     Windows, macOS, Chrome, iOS and Android only, and say so plainly:
#     "Linux devices are not supported because there is no dedicated
#     Mobility Print client." Print Deploy is the only supported route
#     onto Linux — and it can itself import Mobility Print queues.
#       https://www.papercut.com/help/manuals/mobility-print/overview/what-product-to-use-when/
#
#     Do NOT be tempted to hand-roll an lpadmin queue against
#     ipps://user:pass@host:9164/printers/<queue>. That form comes from a
#     2018 third-party blog post, PaperCut separately state they do not
#     support IPP Everywhere, and it bakes ONE user's credentials into
#     the queue — exactly wrong for a shared student image. Print Deploy
#     runs a localhost IPP proxy (port 9177) that injects whoever is
#     actually logged in.
#
#     Supply the server either way round:
#       PAPERCUT_SERVER=https://print.school.example:9174 ./ubuntu_26.04_niri_install.sh
#       ./ubuntu_26.04_niri_install.sh    (prompts; blank skips printing)
#
#     ⚠️ Two things to check against YOUR server before trusting this:
#       1. The download endpoint /print-deploy/client/linux-debian is
#          confirmed from a live PaperCut-generated client-setup page,
#          NOT from PaperCut's manual.
#       2. The port. 9174 is the Print Deploy server's runtime port, but
#          the client-setup page is served by the Application Server
#          (9191/9192, or 443 behind a proxy). If the download 404s, try
#          the Application Server URL instead.
#
#     Wayland note: the Print Deploy client GUI is GTK/WebKitGTK, so it
#     runs natively under niri — no XWayland needed. The older Java Swing
#     pc-client (the balance/account popup) is a different matter: AWT has
#     no GA Wayland toolkit, so it would need xwayland-satellite running
#     and DISPLAY exported, and its XEmbed tray icon will not appear on a
#     Wayland bar. It is deliberately NOT installed here.
# -----------------------------------------------------------------
if [ -z "${PAPERCUT_SERVER:-}" ] && [ -t 0 ]; then
    echo ""
    echo "PaperCut Print Deploy server URL, e.g. https://print.school.example:9174"
    read -r -p "  (blank to skip printer setup): " PAPERCUT_SERVER
fi

if [ -n "${PAPERCUT_SERVER:-}" ]; then
    # Strip any trailing slash so the URL join below cannot double up.
    PAPERCUT_SERVER="${PAPERCUT_SERVER%/}"

    # CUPS must already be installed: the .deb's postinst aborts with
    # "Unable to find cupsd - is CUPS installed?" and dpkg then errors out.
    # libwebkit2gtk-4.1-0 is a hard dependency of the client GUI.
    # avahi-daemon + libnss-mdns are needed for mDNS-discovered queues.
    echo "Installing Print Deploy prerequisites..."
    sudo apt install -y \
        cups \
        cups-ipp-utils \
        libwebkit2gtk-4.1-0 \
        avahi-daemon \
        avahi-utils \
        libnss-mdns

    # Pre-seed the config so the downloaded filename does not have to carry
    # the server name. Written BEFORE the package is installed, which is
    # what --force-confdef below protects.
    #
    # StrictSSLCheckingEnabled defaults to true here. Set
    # PAPERCUT_STRICT_SSL=false only if your PaperCut server presents a
    # self-signed certificate that is not in the system CA store — section
    # 9 already installs the Oakford CA, so try true first.
    sudo mkdir -p /etc/papercut-print-deploy-client
    sudo tee /etc/papercut-print-deploy-client/client.conf.toml > /dev/null <<EOF
ServerBaseURL = "${PAPERCUT_SERVER}"
StrictSSLCheckingEnabled = ${PAPERCUT_STRICT_SSL:-true}
HTTPProxy = ""
EOF

    PC_TMP="$(mktemp -d)"
    # -OJ: the filename arrives via Content-Disposition and encodes the
    # server address; PaperCut are explicit that it must not be renamed.
    if ( cd "$PC_TMP" && curl -fL -OJ "${PAPERCUT_SERVER}/print-deploy/client/linux-debian" ); then
        PC_DEB="$(find "$PC_TMP" -maxdepth 1 -name '*.deb' | head -1)"
        if [ -n "$PC_DEB" ]; then
            echo "Installing $(basename "$PC_DEB") ..."
            # SKIP_DPM must be passed as an ENVIRONMENT VARIABLE — it is not
            # read from the TOML. It skips the Direct Print Monitor, which a
            # student laptop does not need.
            # --force-confdef or dpkg prompts interactively and overwrites
            # the conffile written above.
            sudo SKIP_DPM=true dpkg -i --force-confdef "$PC_DEB" || {
                echo "dpkg reported unmet dependencies — resolving..."
                sudo apt-get -y -f install
            }
            echo "Print Deploy installed. Queues appear after first login."
            echo "  Logs: /opt/PaperCutPrintDeployClient/data/logs/install.log"
        else
            echo "WARNING: download produced no .deb — skipping Print Deploy."
        fi
    else
        echo "WARNING: could not download the Print Deploy client from"
        echo "         ${PAPERCUT_SERVER}/print-deploy/client/linux-debian"
        echo "         Check the host and port (9174 vs the App Server's"
        echo "         9192/443), then install by hand from:"
        echo "         ${PAPERCUT_SERVER}/print-deploy/client-setup/linux.html"
    fi
    rm -rf "$PC_TMP"

    # Note: the Linux Print Deploy client does NOT auto-update. Reinstall
    # over the top when the server is upgraded, re-passing SKIP_DPM=true.
else
    echo "No PaperCut server given — skipping printer setup."
    echo "Students can still add printers with system-config-printer."
fi

# -----------------------------------------------------------------
echo ""
echo "-------------------------------------------------------"
echo "SETUP COMPLETE."
echo ""
echo "Reboot to enter Niri. At the greeter you can also pick the"
echo "GNOME session if Niri ever fails to start."
echo ""
echo "For students:"
echo "  * Home wifi:  DMS control centre, or nm-connection-editor"
echo "  * VPN:        create the profile in nm-connection-editor, then"
echo "                toggle it from the DMS bar VPN widget"
if [ -n "${PAPERCUT_SERVER:-}" ]; then
    echo "  * Printers:   school queues arrive via PaperCut Print Deploy"
    echo "                shortly after your first login. Home printers:"
    echo "                system-config-printer"
else
    echo "  * Printers:   system-config-printer"
fi
echo ""
echo "  GITHUB — set up your OWN access. Never share a private key:"
if [ "$GIT_IDENTITY_SET" = no ]; then
    echo "    1. Tell git who you are:"
    echo "         git config --global user.name  'Your Name'"
    echo "         git config --global user.email 'you@example.com'"
fi
echo "    2. Authenticate. Easiest, no SSH key needed:"
echo "         gh auth login      (choose GitHub.com -> HTTPS -> browser)"
echo "       Or add this machine's public key at github.com/settings/keys:"
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    sed 's/^/         /' "$HOME/.ssh/id_ed25519.pub"
fi
echo ""
echo "  Mod+Alt+L locks the screen using dank-lock.sh (pixelated"
echo "  screenshot background)."
echo ""
echo "  NVIDIA only: watch for the MOK enrollment screen on first"
echo "  boot and enroll the key."
echo "-------------------------------------------------------"

# The one message in this script that has to change somebody's behaviour, so
# it goes last and it answers the objection before it is raised. Craig's
# assumption on 4 Sep 2026 was that turning Secure Boot off means a reinstall;
# it does not, and saying so plainly is what decides whether anyone does it.
# Defined as a function in preflight because it is ALSO printed at the start
# on a machine whose wifi this run is about to refuse -- learning that after
# a forty-minute build is too late to be useful.
if [ "$SECURE_BOOT" = on ] || [ "$SECURE_BOOT" = unknown ]; then
    secure_boot_action_block
fi
