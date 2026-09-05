#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_oakford_ca() {
    local tmp got
    tmp="$(mktemp)"
    if ! wget -q --tries=3 --retry-connrefused --waitretry=5 --timeout=20 "$OAKFORD_CA_URL" -O "$tmp"; then
        rm -f "$tmp"
        warn "could not download the Oakford CA. On the school network every later third-party download will fail TLS validation; off site this is harmless."
        return 0
    fi
    got="$(openssl x509 -in "$tmp" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true)"
    if [ "$got" != "$OAKFORD_SHA256" ]; then
        rm -f "$tmp"
        warn "Oakford CA fingerprint did NOT match. Certificate NOT installed."
        warn "  expected: $OAKFORD_SHA256"
        warn "  received: ${got:-<not a certificate>}"
        warn "  Confirm the new fingerprint with Oakford before changing OAKFORD_SHA256 in lib/common.sh."
        return 0
    fi
    sudo install -m 0644 -o root -g root "$tmp" "$OAKFORD_CA_PATH"
    rm -f "$tmp"
    sudo update-ca-certificates
    if have_cmd certutil; then
        mkdir -p "$HOME/.pki/nssdb"
        certutil -d sql:"$HOME/.pki/nssdb" -N -f /dev/null 2>/dev/null || true
        certutil -d sql:"$HOME/.pki/nssdb" -A -t "CT,," -n "Oakford CA" -f /dev/null -i "$OAKFORD_CA_PATH" || true
    fi
    log "Oakford CA trusted."
}
