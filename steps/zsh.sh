#!/usr/bin/env bash
#
# steps/zsh.sh - install zsh and set it as the default shell
#
# Run through ../setup.sh, or on its own: ./steps/zsh.sh

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step_zsh() {
  log "Installing zsh and setting it as the default shell"
  sudo apt-get install -y zsh
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [ "$(getent passwd "$USER" | cut -d: -f7)" = "$zsh_path" ]; then
    info "zsh is already the default shell"
  else
    sudo chsh -s "$zsh_path" "$USER"
    info "default shell set to $zsh_path (to start using it, $(relogin_hint))"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_zsh
fi
