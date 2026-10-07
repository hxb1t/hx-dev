#!/usr/bin/env bash
#
# steps/ohmyzsh.sh - Oh My Zsh + autosuggestions / completions /
# syntax-highlighting plugins
#
# Run through ../setup.sh, or on its own: ./steps/ohmyzsh.sh

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
OMZ_CUSTOM="${ZSH_CUSTOM:-$OMZ_DIR/custom}"

step_ohmyzsh() {
  log "Installing Oh My Zsh and plugins"
  have zsh || die "zsh is not installed; run the 'zsh' step first."
  have git || die "git is not installed; run the 'packages' step first."

  if [ -d "$OMZ_DIR" ]; then
    info "Oh My Zsh already installed"
  else
    run_remote_script sh \
      https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh --unattended
  fi

  mkdir -p "$OMZ_CUSTOM/plugins"
  clone_once https://github.com/zsh-users/zsh-autosuggestions \
    "$OMZ_CUSTOM/plugins/zsh-autosuggestions"
  clone_once https://github.com/zsh-users/zsh-completions \
    "$OMZ_CUSTOM/plugins/zsh-completions"
  clone_once https://github.com/zsh-users/zsh-syntax-highlighting \
    "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting"

  # Enable the plugins. zsh-syntax-highlighting should stay last.
  sed -i 's/^plugins=(.*)/plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting)/' "$ZSHRC"

  # zsh-completions must be on fpath BEFORE oh-my-zsh.sh is sourced.
  if ! grep -q 'plugins/zsh-completions/src' "$ZSHRC"; then
    # shellcheck disable=SC2016  # literal $ is intended: expanded by zsh later
    sed -i '/^source \$ZSH\/oh-my-zsh\.sh/i fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src' "$ZSHRC"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_ohmyzsh
fi
