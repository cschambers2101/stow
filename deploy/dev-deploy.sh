#!/usr/bin/env bash
# Copies a ref of this repository into the dev container, replacing the last copy.
# Installer sections are then run there by hand, as the ubuntu user:
#   lxc exec stow-dev -- sudo -iu ubuntu bash ~/stow-beta/install_programs/ubuntu_26.04_niri_install.sh --only <ids>
#
#   deploy/dev-deploy.sh [ref] [container]      defaults: origin/beta stow-dev
set -euo pipefail

ref="${1:-origin/beta}"
container="${2:-stow-dev}"
dest=/home/ubuntu/stow-beta

root="$(git rev-parse --show-toplevel)"
git -C "${root}" fetch -q origin
commit="$(git -C "${root}" rev-parse --short "${ref}")"

lxc exec "${container}" -- rm -rf "${dest}"
lxc exec "${container}" -- mkdir -p "${dest}"
git -C "${root}" archive "${commit}" | lxc exec "${container}" -- tar -x -C "${dest}"
lxc exec "${container}" -- chown -R ubuntu:ubuntu "${dest}"

echo "deployed ${commit} to ${container}:${dest}"
