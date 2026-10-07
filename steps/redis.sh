#!/usr/bin/env bash
#
# steps/redis.sh - Redis server from Redis's official apt repository
# (https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/apt/)
#
# Run through ../setup.sh, or on its own: ./steps/redis.sh
#
# Redis listens on localhost only (the package default).
#
# Optional environment overrides:
#   REDIS_VERSION=latest    (default: latest) e.g. REDIS_VERSION=7.4.1

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

REDIS_VERSION="${REDIS_VERSION:-latest}"
REDIS_VERSION_RE='^(latest|[0-9]+\.[0-9]+\.[0-9]+)$'

step_redis() {
  log "Installing Redis ($REDIS_VERSION)"
  check_version REDIS_VERSION "$REDIS_VERSION_RE" "latest or a version like 7.4.1"
  local codename
  codename="$(ubuntu_codename)"
  [ -n "$codename" ] || die "Could not tell the Ubuntu release from /etc/os-release."

  add_apt_repo redis https://packages.redis.io/gpg \
    "deb [arch=$(dpkg --print-architecture) signed-by=SIGNED_BY] https://packages.redis.io/deb $codename main"
  apt_install_version "$REDIS_VERSION" redis-server redis-tools
  enable_service redis-server
  info "$(redis-server --version 2>/dev/null | cut -d' ' -f1-3)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_redis
fi
