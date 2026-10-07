#!/usr/bin/env bash
#
# steps/sshkey.sh - SSH key (ed25519) for GitHub. Interactive: asks for a
# passphrase.
#
# Run through ../setup.sh, or on its own: ./steps/sshkey.sh
#
# Optional environment overrides:
#   SSH_KEY=~/.ssh/id_ed25519                 key path to create/use
#   SSH_KEY_COMMENT="$USER@$(hostname)"       comment embedded in the key

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SSH_KEY_COMMENT="${SSH_KEY_COMMENT:-$USER@$(hostname)}"

step_sshkey() {
  log "Setting up SSH key ($SSH_KEY)"
  have ssh-keygen || die "ssh-keygen not found; run the 'packages' step first."

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ -f "$SSH_KEY" ]; then
    info "key already exists, not overwriting: $SSH_KEY"
  else
    info "Choose a passphrase when prompted (recommended; empty means none)."
    ssh-keygen -t ed25519 -C "$SSH_KEY_COMMENT" -f "$SSH_KEY"
  fi

  # Recreate the public key if only the private key is present.
  [ -f "$SSH_KEY.pub" ] || ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_sshkey
fi
