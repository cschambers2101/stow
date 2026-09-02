#!/usr/bin/env bash
# setup-printing.sh - build the CUPS queues for a Xerox AltaLink finisher + PaperCut
#
# PUBLIC REPO: no site addresses are hardcoded. Supply them by env var or in a
# config file that is NOT in git:
#
#     ~/.config/s6c-printing.conf        (see the sample this script prints with --sample)
#
# Site-specific values for S6C live in the private workspace notes:
#     projects/linux-device-build-2026/notes/printing-runbook.md
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

do_packages() {
  echo "== installing CUPS =="
  sudo apt-get update
  sudo apt-get install -y cups cups-client cups-ipp-utils cups-filters
  sudo systemctl enable --now cups
  sudo usermod -aG lpadmin "$(id -un)"      # NOT $USER; may be unset
  echo "   added to lpadmin - use 'sg lpadmin -c ...' to avoid logging out"
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
  cp -f "ppd/Linux/English/$PPD_MODEL" .
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

  sg lpadmin -c "lpadmin -p ${PREFIX}-Direct-2Sided -E -v $DEV -P '$PPD' \
    -D '2-sided A4, no staple (DIRECT - not PaperCut tracked)' \
    -o InputSlot=$TRAY_FLAT -o PageSize=A4 -o Duplex=DuplexNoTumble \
    -o StapleLocation=None -o XRFold=None -o Collate=True"

  sg lpadmin -c "lpadmin -p ${PREFIX}-Direct-2Sided-Stapled -E -v $DEV -P '$PPD' \
    -D '2-sided A4, 1 corner staple, needs 2+ sheets (DIRECT)' \
    -o InputSlot=$TRAY_FLAT -o PageSize=A4 -o Duplex=DuplexNoTumble \
    -o StapleLocation=SinglePortrait -o XRFold=None -o Collate=True"

  # Booklets: the device FOLDS AND STAPLES BUT DOES NOT IMPOSE.
  # Imposition is done by s6c-booklet. Folding needs SHORT-EDGE FEED trays.
  sg lpadmin -c "lpadmin -p ${PREFIX}-Booklet-A5 -E -v $DEV -P '$PPD' \
    -D 'Booklet: A4 folded to A5, saddle-stitched (use s6c-booklet)' \
    -o InputSlot=$TRAY_A4_SEF -o PageSize=A4 -o XRFold=BiFoldStaple -o Duplex=DuplexTumble"

  sg lpadmin -c "lpadmin -p ${PREFIX}-Booklet-A4 -E -v $DEV -P '$PPD' \
    -D 'Booklet: A3 folded to A4, saddle-stitched (use s6c-booklet)' \
    -o InputSlot=$TRAY_A3_SEF -o PageSize=A3 -o XRFold=BiFoldStaple -o Duplex=DuplexTumble"

  if [ -n "$PAPERCUT_IP" ]; then
    echo "== creating PaperCut queues on $PAPERCUT_IP =="
    local MP="ipps://$PAPERCUT_IP:9164/printers"
    sg lpadmin -c "lpadmin -p ${PREFIX}-FollowMe-Colour -E \
      -v $MP/Follow_Me_Colour_Secure_Print_for_Mobile -m everywhere \
      -D 'PaperCut Follow Me Secure Print (Colour)' \
      -o media-default=iso_a4_210x297mm -o ColorModel=RGB \
      -o Duplex=DuplexNoTumble -o auth-info-required=username,password"
    sg lpadmin -c "lpadmin -p ${PREFIX}-FollowMe-Mono -E \
      -v $MP/Follow_Me_Secure_Print_for_Mobile -m everywhere \
      -D 'PaperCut Follow Me Secure Print (Mono)' \
      -o media-default=iso_a4_210x297mm -o ColorModel=Gray \
      -o Duplex=DuplexNoTumble -o auth-info-required=username,password"
    sg lpadmin -c "lpadmin -d ${PREFIX}-FollowMe-Colour"
    echo "   NOTE: tracked queues hold every job until a credential is supplied."
  else
    echo "   PAPERCUT_IP unset - skipping tracked queues"
  fi
}

do_verify() {
  echo "== verify =="
  lpstat -r || true
  lpstat -a 2>/dev/null || true
  echo; echo "-- active options ('*' marks what is in force) --"
  for q in $(lpstat -a 2>/dev/null | awk '{print $1}'); do
    echo "--- $q"
    lpoptions -p "$q" -l 2>/dev/null \
      | grep -E '^(InputSlot|PageSize|Duplex|XRFold|StapleLocation|ColorModel)/' \
      | sed -E 's#^([A-Za-z]+)/[^:]*:#\1:#' \
      | awk '{o=$1;a="";for(i=2;i<=NF;i++)if($i~/^\*/)a=substr($i,2);printf "    %-16s %s\n",o,a}'
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
