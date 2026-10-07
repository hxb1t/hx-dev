#!/usr/bin/env bash
#
# steps/claude.sh - Claude Code, with the official native installer
#
# Run through ../setup.sh, or on its own: ./steps/claude.sh
#
# Optional environment overrides:
#   CLAUDE_VERSION=stable   (default: stable) or latest, or e.g. 1.0.58

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

CLAUDE_VERSION="${CLAUDE_VERSION:-stable}"
CLAUDE_VERSION_RE='^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?)$'

step_claude() {
  log "Installing Claude Code ($CLAUDE_VERSION)"
  check_version CLAUDE_VERSION "$CLAUDE_VERSION_RE" "stable, latest or a version like 1.0.58"

  local current=""
  if have claude; then
    current="$(claude --version 2>/dev/null | awk '{ print $1 }' || true)"
  fi
  # stable/latest keep any installed copy (Claude Code updates itself); an
  # exact version is installed unless it is the one installed already.
  if [ -n "$current" ]; then
    case "$CLAUDE_VERSION" in
      stable|latest|"$current")
        info "claude already installed: $current"
        return 0 ;;
    esac
  fi

  run_remote_script bash https://claude.ai/install.sh "$CLAUDE_VERSION"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_claude
fi
