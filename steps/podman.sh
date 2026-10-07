#!/usr/bin/env bash
#
# steps/podman.sh - Podman (rootless containers) from Ubuntu's archive
#
# Run through ../setup.sh, or on its own: ./steps/podman.sh
#
# Ubuntu's package is used because Podman publishes no apt repository of its
# own for Ubuntu. It works next to Docker; podman-docker (which replaces the
# docker command) is not installed.

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step_podman() {
  log "Installing Podman"
  if have podman; then
    info "podman already installed: $(podman --version)"
    return 0
  fi
  # uidmap provides newuidmap/newgidmap for rootless containers.
  sudo apt-get install -y podman uidmap
  info "$(podman --version)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_podman
fi
