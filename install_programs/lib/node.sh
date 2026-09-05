#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

install_node_lts() {
    export NVM_DIR="$NVM_HOME"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        mkdir -p "$NVM_DIR"
        if ! curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | PROFILE=/dev/null bash; then
            warn "nvm install failed - Node.js not installed."
            return 0
        fi
    fi
    # shellcheck source=/dev/null
    . "$NVM_DIR/nvm.sh"
    nvm install --lts >/dev/null
    nvm alias default 'lts/*' >/dev/null
    log "Node $(node --version) via nvm at $NVM_DIR"
}
