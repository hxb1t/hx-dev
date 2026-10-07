#!/usr/bin/env bash
#
# steps/git.sh - git and git-lfs
#
# Run through ../setup.sh, or on its own: ./steps/git.sh
#
# GIT_FROM=ppa installs the newest git from the official git-core PPA
# (https://launchpad.net/~git-core/+archive/ubuntu/ppa); Ubuntu's own git is
# often a few releases behind. GIT_FROM=ubuntu keeps Ubuntu's git.
#
# Optional environment overrides:
#   GIT_FROM=ppa            (default: ppa)    or GIT_FROM=ubuntu

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

GIT_FROM="${GIT_FROM:-ppa}"

step_git() {
  log "Installing git and git-lfs (from: $GIT_FROM)"
  case "$GIT_FROM" in
    ppa)
      if grep -rqs 'git-core/ppa' /etc/apt/sources.list.d/; then
        info "git-core PPA already added"
      else
        have add-apt-repository \
          || die "add-apt-repository is not installed; run the 'packages' step first."
        sudo add-apt-repository -y ppa:git-core/ppa
      fi
      # Upgrades a git that is already installed to the PPA's version.
      sudo apt-get install -y git git-lfs
      ;;
    ubuntu)
      if have git && have git-lfs; then
        info "git already installed: $(git --version)"
      else
        sudo apt-get install -y git git-lfs
      fi
      ;;
    *)
      die "GIT_FROM must be 'ppa' or 'ubuntu' (got '$GIT_FROM')."
      ;;
  esac

  # Adds the LFS filters to ~/.gitconfig; safe to repeat.
  git lfs install --skip-repo >/dev/null
  info "$(git --version), $(git lfs version | cut -d' ' -f1)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_git
fi
