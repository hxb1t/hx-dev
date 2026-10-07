#!/usr/bin/env bash
#
# steps/make.sh - build tools: make, gcc/g++ (build-essential), cmake,
# pkg-config. Needed to build C/C++ code, native Node modules and Rust crates.
#
# Run through ../setup.sh, or on its own: ./steps/make.sh

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

step_make() {
  log "Installing build tools (make, gcc/g++, cmake, pkg-config)"
  if have make && have gcc && have g++ && have cmake && have pkg-config; then
    info "build tools already installed: $(make --version | sed -n 1p), gcc $(gcc -dumpversion)"
    return 0
  fi
  sudo apt-get install -y build-essential cmake pkg-config
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_make
fi
