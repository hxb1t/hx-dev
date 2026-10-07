#!/usr/bin/env bash
#
# steps/proto.sh - proto version manager (https://moonrepo.dev/proto)
#
# Run through ../setup.sh, or on its own: ./steps/proto.sh
#
# Optional environment overrides:
#   PROTO_VERSION=latest    (default: latest) e.g. PROTO_VERSION=0.45.0
#   PROTO_HOME=~/.proto                       where proto and its tools live

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

PROTO_VERSION="${PROTO_VERSION:-latest}"
PROTO_VERSION_RE='^(latest|v?[0-9]+\.[0-9]+\.[0-9]+)$'

step_proto() {
  log "Installing proto ($PROTO_VERSION)"
  check_version PROTO_VERSION "$PROTO_VERSION_RE" "latest or a version like 0.45.0"
  check_install_path PROTO_HOME
  export PROTO_HOME

  local want="${PROTO_VERSION#v}" current=""
  if [ -x "$PROTO_HOME/bin/proto" ]; then
    current="$("$PROTO_HOME/bin/proto" --version 2>/dev/null | awk '{ print $2 }' || true)"
  fi

  # latest keeps any installed copy; an exact version replaces a different one.
  if [ -n "$current" ] && { [ "$want" = latest ] || [ "$want" = "$current" ]; }; then
    info "proto already installed: $current"
  else
    if [ -n "$current" ]; then
      info "replacing proto $current with $want"
    elif have proto; then
      warn "Another proto is on PATH ($(command -v proto)); installing a separate copy in $PROTO_HOME."
    fi
    # The installer puts proto in $PROTO_HOME/bin. --yes: no prompts;
    # --no-profile: we manage ~/.zshrc ourselves below.
    run_remote_script bash https://moonrepo.dev/install/proto.sh "$want" --yes --no-profile
  fi
  export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

  # shellcheck disable=SC2016  # literal $ is intended: expanded by zsh later
  set_zshrc_block "# >>> wsl-setup: proto / local bin >>>" \
"export PROTO_HOME=\"$(zshrc_path "$PROTO_HOME")\"
"'export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$HOME/.local/bin:$PATH"
# <<< wsl-setup <<<'
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_proto
fi
