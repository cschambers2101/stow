#!/usr/bin/env bash
# setup-printing.sh - build the CUPS queues for a Xerox AltaLink finisher + PaperCut
#
# PUBLIC REPO: no site addresses are hardcoded. Supply them by env var or in a
# config file that is NOT in git:
#
#     ~/.config/s6c-printing.conf        (see the sample this script prints with --sample)
#
# Site-specific values for S6C live in the private workspace notes:
#     projects/printing-2026/notes/printing-runbook.md
#
# Usage:  bash setup-printing.sh [--packages] [--ppd] [--queues] [--verify] [--all]
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # never a hardcoded path
CONF="${S6C_PRINTING_CONF:-$HOME/.config/s6c-printing.conf}"

# --- defaults; every one overridable by conf or env -------------------------
PRINTER_IP="${PRINTER_IP:-}"          # AltaLink with the finisher
PAPERCUT_IP="${PAPERCUT_IP:-}"        # PaperCut / Mobility Print server
PAPERCUT_USER="${PAPERCUT_USER:-}"    # <initial><surname>
TRAY_FLAT="${TRAY_FLAT:-Tray1}"       # any A4 tray; need not fold
TRAY_A3_SEF="${TRAY_A3_SEF:-Tray2}"   # A3 short-edge feed -> A4 booklets
TRAY_A4_SEF="${TRAY_A4_SEF:-Tray3}"   # A4 short-edge feed -> A5 booklets
PPD_URL="${PPD_URL:-https://download.support.xerox.com/pub/drivers/ALC81XX/drivers/win10/en_GB/AltaLink_C8130-C8170_5.709.0.0_PPD.zip}"
PPD_ZIP_SHA="${PPD_ZIP_SHA:-93594570cc6a5858d19c7702bdba8c5f5f097ddc159b243f75d6ccbbada9bf69}"
PPD_SHA="${PPD_SHA:-e8a6fe45b18053dc876707cab18ec26ebb81892ab1325ff2c67134d8c3045967}"
PPD_MODEL="${PPD_MODEL:-xrxC8135.ppd}"
PPD_DIR="${PPD_DIR:-$HOME/.local/share/xerox-ppd}"
PREFIX="${PREFIX:-S6C}"

[ -r "$CONF" ] && . "$CONF"

# Wait for cupsd to finish generating a driverless queue's PPD.
#
# With `-m everywhere` the queue appears immediately but its PPD is built
# asynchronously from the printer's IPP attributes. Setting defaults before
# that completes silently loses them — on ubuntu-craig-office (2 Sep 2026) a
# `sides-default=two-sided-long-edge` issued straight after creation came back
# as `one-sided`, and ColorModel/Duplex still read the pre-PPD fallbacks.
# `lpoptions -l` returning a ColorModel line is the signal that it is ready.
wait_for_ppd() {
    local q="$1" i=0
    while [ "$i" -lt 30 ]; do
        if lpoptions -p "$q" -l 2>/dev/null | grep -q '^ColorModel/'; then
            return 0
        fi
        sleep 1; i=$((i+1))
    done
    echo "   WARNING: $q PPD not ready after ${i}s; defaults may not stick" >&2
    return 1
}

sample() {
cat <<'EOF'
# ~/.config/s6c-printing.conf  - keep OUT of git
PRINTER_IP=10.0.0.10
PAPERCUT_IP=10.0.0.20
PAPERCUT_USER=jsmith
TRAY_FLAT=Tray1
TRAY_A3_SEF=Tray2
TRAY_A4_SEF=Tray3
EOF
}

die(){ echo "setup-printing: $*" >&2; exit 1; }

# Run one lpadmin command line, whichever way this machine allows.
#
# Ubuntu 26.04 ships NEITHER `sg` NOR `newgrp` — both were dropped, and the
# runbook's "use `sg lpadmin -c ...` to avoid logging out" trick simply fails
# with `sg: command not found` (hit on ubuntu-craig-office, 2 Sep 2026). So:
#
#   already in the lpadmin group  -> run it directly, no privilege needed
#   sg exists (older releases)    -> use it, picking the group up immediately
#   neither                       -> sudo, which works regardless of group
#
# Takes a single string because the call sites build multi-line commands.
lp_admin() {
    if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
        eval "$1"
    elif command -v sg >/dev/null 2>&1; then
        lp_admin "$1"
    else
        echo "   (not in lpadmin yet and no sg — using sudo)" >&2
        eval "sudo $1"
    fi
}

do_packages() {
  echo "== installing CUPS =="
  sudo apt-get update
  sudo apt-get install -y cups cups-client cups-ipp-utils cups-filters
  sudo systemctl enable --now cups
  sudo usermod -aG lpadmin "$(id -un)"      # NOT $USER; may be unset
  echo "   added to lpadmin - queue creation below adapts (sg is gone on 26.04)"
}

do_ppd() {
  echo "== fetching the Xerox PPD =="
  mkdir -p "$PPD_DIR"; cd "$PPD_DIR"
  local zip; zip=$(basename "$PPD_URL")
  [ -f "$zip" ] || curl -sSLO "$PPD_URL"
  if command -v sha256sum >/dev/null; then
    local got; got=$(sha256sum "$zip" | awk '{print $1}')
    [ "$got" = "$PPD_ZIP_SHA" ] || echo "   WARNING: zip sha256 mismatch (Xerox may have re-released)" >&2
  fi
  command -v unzip >/dev/null || die "unzip not installed"
  unzip -o -q "$zip"
  # Locate the PPD by CONTENT, not by a hardcoded path inside the archive.
  #
  # Two traps here, both hit on ubuntu-craig-office 2 Sep 2026:
  #
  #   1. The 5.709.0.0 archive lays out `Linux/English/xrxC8135.ppd` — there is
  #      NO `ppd/` prefix. An earlier hardcoded `ppd/Linux/English/...` could
  #      never have worked, and `set -e` aborted the whole script at the `cp`.
  #      The archive's own sha256 matches PPD_ZIP_SHA exactly, so this was a
  #      script bug, not a re-release by Xerox.
  #   2. The archive ships the SAME filename in Brazilian, English, French,
  #      German and Italian. A naive `find -print -quit` picks whichever the
  #      filesystem yields first — it chose *Italian*, and only the sha256 pin
  #      caught it.
  #
  # So: gather every candidate and prefer the one whose sha256 matches PPD_SHA.
  # Fall back to an */English/* path, and only then to the first match.
  local cands want got pick=""
  cands=$(find . -type f -name "$PPD_MODEL" -not -path "./$PPD_MODEL" 2>/dev/null | sort || true)
  [ -n "$cands" ] || die "$PPD_MODEL not found anywhere in $zip"

  if command -v sha256sum >/dev/null; then
    while IFS= read -r c; do
      got=$(sha256sum "$c" | awk '{print $1}')
      if [ "$got" = "$PPD_SHA" ]; then pick="$c"; break; fi
    done <<< "$cands"
  fi
  if [ -z "$pick" ]; then
    pick=$(printf '%s\n' "$cands" | grep -m1 '/English/' || true)
    [ -n "$pick" ] || pick=$(printf '%s\n' "$cands" | head -1)
    echo "   WARNING: no candidate matched PPD_SHA; falling back to $pick" >&2
  fi
  echo "   using $pick"
  cp -f "$pick" .
  [ -r "$PPD_DIR/$PPD_MODEL" ] || die "PPD not found after unzip"
  if command -v sha256sum >/dev/null; then
    local g2; g2=$(sha256sum "$PPD_MODEL" | awk '{print $1}')
    [ "$g2" = "$PPD_SHA" ] || echo "   WARNING: PPD sha256 mismatch" >&2
  fi
  echo "   $PPD_DIR/$PPD_MODEL"
}

do_queues() {
  [ -n "$PRINTER_IP" ] || die "PRINTER_IP unset - see --sample"
  local PPD="$PPD_DIR/$PPD_MODEL"
  [ -r "$PPD" ] || die "PPD missing; run with --ppd first"
  local DEV="socket://$PRINTER_IP:9100"
  echo "== creating direct queues on $PRINTER_IP =="

  lp_admin "lpadmin -p ${PREFIX}-Direct-2Sided -E -v $DEV -P '$PPD' \
    -D '2-sided A4, no staple (DIRECT - not PaperCut tracked)' \
    -o InputSlot=$TRAY_FLAT -o PageSize=A4 -o Duplex=DuplexNoTumble \
    -o StapleLocation=None -o XRFold=None -o Collate=True"

  lp_admin "lpadmin -p ${PREFIX}-Direct-2Sided-Stapled -E -v $DEV -P '$PPD' \
    -D '2-sided A4, 1 corner staple, needs 2+ sheets (DIRECT)' \
    -o InputSlot=$TRAY_FLAT -o PageSize=A4 -o Duplex=DuplexNoTumble \
    -o StapleLocation=SinglePortrait -o XRFold=None -o Collate=True"

  # Booklets: the device FOLDS AND STAPLES BUT DOES NOT IMPOSE.
  # Imposition is done by s6c-booklet. Folding needs SHORT-EDGE FEED trays.
  lp_admin "lpadmin -p ${PREFIX}-Booklet-A5 -E -v $DEV -P '$PPD' \
    -D 'Booklet: A4 folded to A5, saddle-stitched (use s6c-booklet)' \
    -o InputSlot=$TRAY_A4_SEF -o PageSize=A4 -o XRFold=BiFoldStaple -o Duplex=DuplexTumble"

  lp_admin "lpadmin -p ${PREFIX}-Booklet-A4 -E -v $DEV -P '$PPD' \
    -D 'Booklet: A3 folded to A4, saddle-stitched (use s6c-booklet)' \
    -o InputSlot=$TRAY_A3_SEF -o PageSize=A3 -o XRFold=BiFoldStaple -o Duplex=DuplexTumble"

  if [ -n "$PAPERCUT_IP" ]; then
    echo "== creating PaperCut queues on $PAPERCUT_IP =="
    local MP="ipps://$PAPERCUT_IP:9164/printers"

    # These are DRIVERLESS (`-m everywhere`) queues, and the option rules are
    # the INVERSE of the vendor-PPD queues above. Learned on
    # ubuntu-craig-office, 2 Sep 2026:
    #
    #   * PPD-style options (`ColorModel`, `Duplex`) are SILENTLY IGNORED at
    #     creation time. `-o ColorModel=RGB` left the colour queue on
    #     `print-color-mode=monochrome` — a queue named "Colour" that prints
    #     mono, reporting success throughout. Re-issuing `ColorModel=RGB` on
    #     the existing queue did not fix it either.
    #   * The IPP attribute defaults DO work: `print-color-mode-default` and
    #     `sides-default`. Once set, `lpoptions -l` correctly shows
    #     `ColorModel=RGB` / `Duplex=DuplexNoTumble`.
    #
    # This is the opposite of the vendor-PPD rule in the runbook ("the PPD uses
    # ColorModel; print-color-mode-default does nothing"). Both are true — the
    # rule depends on whether the queue has a real PPD or a driverless one.
    #
    # Options are also set in a SECOND lpadmin pass, because with
    # `-m everywhere` cupsd generates the queue's PPD from the printer's IPP
    # attributes and driver options set in the creating call can lose the race.
    for _spec in "Colour:Follow_Me_Colour_Secure_Print_for_Mobile:color" \
                 "Mono:Follow_Me_Secure_Print_for_Mobile:monochrome"; do
        local _name="${_spec%%:*}" _rest="${_spec#*:}"
        local _path="${_rest%%:*}" _mode="${_rest##*:}"
        local _q="${PREFIX}-FollowMe-${_name}"

        lp_admin "lpadmin -p $_q -E -v $MP/$_path -m everywhere \
          -D 'PaperCut Follow Me Secure Print ($_name)' \
          -o auth-info-required=username,password"

        wait_for_ppd "$_q" || true

        # Second pass. The working knobs are a MIX, established by testing each
        # one in isolation on ubuntu-craig-office (2 Sep 2026):
        #
        #   colour -> `print-color-mode-default` (IPP attribute).
        #             `ColorModel=RGB` is silently ignored on a driverless
        #             queue and leaves it on monochrome.
        #   duplex -> `Duplex=DuplexNoTumble` (PPD-style option).
        #             `sides-default=two-sided-long-edge` does NOT stick: this
        #             PaperCut server advertises `sides-default=one-sided` and
        #             that wins on refresh. Setting the PPD option instead
        #             makes CUPS write `sides=two-sided-long-edge` itself.
        #
        # So the translation only runs one way (PPD option -> IPP attribute)
        # for duplex, and the other way for colour. Do not "tidy" these into
        # one style; each was verified to fail in the other form.
        lp_admin "lpadmin -p $_q \
          -o media-default=iso_a4_210x297mm \
          -o print-color-mode-default=$_mode \
          -o Duplex=DuplexNoTumble"
    done
    unset _spec _name _rest _path _mode _q

    echo "   NOTE: tracked queues hold every job until a credential is supplied."
    echo "   NOTE: they are deliberately NOT made the default - see below."
  else
    echo "   PAPERCUT_IP unset - skipping tracked queues"
  fi

  # The default queue must be one that actually prints.
  #
  #   * NOT a FollowMe queue: every job on those is held pending a credential
  #     (see the runbook's PaperCut section), so a default of FollowMe-Colour
  #     means every `lp` with no -d silently goes nowhere.
  #   * NOT a Booklet queue: those fold and staple but do not impose, so a raw
  #     job sent to one comes out physically bound in the wrong page order.
  #     Booklets must go through s6c-booklet.
  #
  # That leaves the plain 2-sided direct queue, which is also the sane
  # everyday default.
  lp_admin "lpadmin -d ${PREFIX}-Direct-2Sided"
  echo "== default queue: ${PREFIX}-Direct-2Sided =="
}

do_verify() {
  echo "== verify =="
  lpstat -r || true
  lpstat -a 2>/dev/null || true
  echo; echo "-- default queue --"; lpstat -d 2>/dev/null || true
  echo; echo "-- active options ('*' marks what is in force) --"
  echo "   NOTE: on driverless (-m everywhere) queues the ColorModel line below"
  echo "   is UNRELIABLE - it comes from a generated PPD that lags behind. The"
  echo "   IPP defaults printed under each queue are what actually govern jobs."
  for q in $(lpstat -a 2>/dev/null | awk '{print $1}'); do
    echo "--- $q"
    lpoptions -p "$q" -l 2>/dev/null \
      | grep -E '^(InputSlot|PageSize|Duplex|XRFold|StapleLocation|ColorModel)/' \
      | sed -E 's#^([A-Za-z]+)/[^:]*:#\1:#' \
      | awk '{o=$1;a="";for(i=2;i<=NF;i++)if($i~/^\*/)a=substr($i,2);printf "    %-16s %s\n",o,a}'
    # IPP attribute defaults - authoritative for driverless queues
    lpoptions -p "$q" 2>/dev/null | tr ' ' '\n' \
      | grep -E '^(print-color-mode|sides|media)=' \
      | sed 's/^/      ipp: /' || true
  done
  echo
  echo "Booklets MUST go through s6c-booklet - a booklet queue on its own"
  echo "folds and staples in the wrong page order."
}

[ $# -gt 0 ] || { sed -n '2,16p' "$0"; exit 0; }
for a in "$@"; do
  case "$a" in
    --sample)  sample;;
    --packages) do_packages;;
    --ppd)     do_ppd;;
    --queues)  do_queues;;
    --verify)  do_verify;;
    --all)     do_packages; do_ppd; do_queues; do_verify;;
    -h|--help) sed -n '2,16p' "$0";;
    *) die "unknown option: $a";;
  esac
done
