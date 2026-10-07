#!/usr/bin/env bash
#
# steps/ghlogin.sh - GitHub login (gh auth login), SSH key upload,
# known_hosts, git identity. Interactive: needs you to approve a
# browser/device login.
#
# Run through ../setup.sh, or on its own: ./steps/ghlogin.sh
#
# Optional environment overrides:
#   SSH_KEY=~/.ssh/id_ed25519                 key path to upload
#   SSH_KEY_TITLE="$(hostname)"               title shown on GitHub

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SSH_KEY_TITLE="${SSH_KEY_TITLE:-$(hostname)}"

step_ghlogin() {
  log "Logging in to GitHub and registering the SSH key"
  have gh || die "gh is not installed; run the 'gh' step first."
  [ -f "$SSH_KEY.pub" ] || die "Missing $SSH_KEY.pub; run the 'sshkey' step first."

  # 1. Log in (browser or one-time device code). SSH is the git protocol;
  #    admin:public_key lets us upload the key. The key itself is uploaded
  #    below, so gh's own generate/upload prompt is skipped.
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    info "already logged in to github.com"
  else
    info "If no browser opens, visit the URL shown and enter the one-time code."
    gh auth login --hostname github.com --git-protocol ssh --web \
      --skip-ssh-key --scopes admin:public_key
  fi

  # 2. Upload the public key unless GitHub already has it.
  local pub existing
  pub="$(cut -d' ' -f1,2 "$SSH_KEY.pub")"
  existing="$(gh api user/keys --jq '.[].key' 2>/dev/null || true)"
  if grep -qxF "$pub" <<<"$existing"; then
    info "SSH key is already registered on GitHub"
  else
    if ! gh ssh-key add "$SSH_KEY.pub" --title "$SSH_KEY_TITLE"; then
      warn "Upload failed; requesting the admin:public_key scope and retrying"
      gh auth refresh --hostname github.com --scopes admin:public_key
      gh ssh-key add "$SSH_KEY.pub" --title "$SSH_KEY_TITLE"
    fi
  fi

  # 3. Trust GitHub's SSH host keys, fetched over HTTPS from the GitHub API
  #    (avoids blindly accepting the key on first connect).
  if ssh-keygen -F github.com >/dev/null 2>&1; then
    info "github.com already in known_hosts"
  else
    local hostkeys
    if hostkeys="$(gh api meta --jq '.ssh_keys[] | "github.com " + .')"; then
      printf '%s\n' "$hostkeys" >> "$HOME/.ssh/known_hosts"
      chmod 600 "$HOME/.ssh/known_hosts"
    else
      warn "Could not fetch GitHub host keys; ssh will ask you to confirm on first use."
    fi
  fi

  # 4. Git identity, only if not already set. Uses GitHub's noreply address so
  #    your real email is not exposed; change it later with `git config --global`.
  if ! git config --global user.name >/dev/null 2>&1; then
    git config --global user.name "$(gh api user --jq '.name // .login')"
  fi
  if ! git config --global user.email >/dev/null 2>&1; then
    git config --global user.email \
      "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
  fi

  # 5. Verify. GitHub exits with status 1 on a successful "no shell" login.
  local out
  out="$(ssh -T -o StrictHostKeyChecking=yes git@github.com 2>&1 || true)"
  if grep -q 'successfully authenticated' <<<"$out"; then
    info "$out"
  else
    warn "SSH test did not confirm authentication: $out"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_ghlogin
fi
