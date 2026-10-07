#!/usr/bin/env bash
#
# steps/packages.sh - apt update/upgrade + base packages
#
# Run through ../setup.sh, or on its own: ./steps/packages.sh

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step_packages() {
  log "Updating packages and installing base tools"
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update
  sudo apt-get upgrade -y
  # git/unzip/gzip/xz-utils are proto prerequisites (and git is needed to
  # clone); openssh-client provides ssh/ssh-keygen; software-properties-common
  # provides add-apt-repository (for the git PPA). Compilers and make come
  # with the 'make' step.
  sudo apt-get install -y \
    ca-certificates curl wget git unzip zip gzip xz-utils openssh-client \
    software-properties-common
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_packages
fi
