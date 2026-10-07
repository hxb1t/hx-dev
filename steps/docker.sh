#!/usr/bin/env bash
#
# steps/docker.sh - Docker Engine, Buildx and Compose from Docker's official
# apt repository (https://docs.docker.com/engine/install/ubuntu/)
#
# Run through ../setup.sh, or on its own: ./steps/docker.sh
#
# Adds you to the docker group so docker runs without sudo (after you log in
# again). On WSL with Docker Desktop's WSL integration, docker is already
# provided and this step does nothing.
#
# Optional environment overrides:
#   DOCKER_VERSION=latest   (default: latest) e.g. DOCKER_VERSION=27.3.1

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

DOCKER_VERSION="${DOCKER_VERSION:-latest}"
DOCKER_VERSION_RE='^(latest|[0-9]+\.[0-9]+\.[0-9]+)$'

step_docker() {
  log "Installing Docker Engine ($DOCKER_VERSION)"
  check_version DOCKER_VERSION "$DOCKER_VERSION_RE" "latest or a version like 27.3.1"
  local codename pkg

  if is_wsl && have docker && [[ "$(readlink -f "$(command -v docker)")" == /mnt/* ]]; then
    info "docker comes from Docker Desktop's WSL integration; nothing to install"
    return 0
  fi
  # Ubuntu's own docker packages conflict with Docker's (see the install docs).
  # Ubuntu's containerd/runc are replaced by apt itself when it installs
  # containerd.io, so they are not listed.
  for pkg in docker.io docker-compose docker-compose-v2 podman-docker; do
    if [ -n "$(apt_installed_version "$pkg")" ]; then
      die "Ubuntu's '$pkg' package conflicts with Docker's packages; remove it first: sudo apt-get remove $pkg"
    fi
  done

  codename="$(ubuntu_codename)"
  [ -n "$codename" ] || die "Could not tell the Ubuntu release from /etc/os-release."
  add_apt_repo docker https://download.docker.com/linux/ubuntu/gpg \
    "deb [arch=$(dpkg --print-architecture) signed-by=SIGNED_BY] https://download.docker.com/linux/ubuntu $codename stable"

  apt_install_version "$DOCKER_VERSION" docker-ce docker-ce-cli
  local -a extras=()
  for pkg in containerd.io docker-buildx-plugin docker-compose-plugin; do
    if [ -z "$(apt_installed_version "$pkg")" ]; then extras+=("$pkg"); fi
  done
  if [ "${#extras[@]}" -gt 0 ]; then sudo apt-get install -y "${extras[@]}"; fi

  enable_service docker containerd

  if [[ " $(id -nG "$USER") " == *" docker "* ]]; then
    info "$USER is already in the docker group"
  else
    sudo usermod -aG docker "$USER"
    info "added $USER to the docker group; to use docker without sudo, $(relogin_hint)"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_docker
fi
