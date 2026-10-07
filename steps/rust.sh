#!/usr/bin/env bash
#
# steps/rust.sh - Rust toolchain through rustup, the official installer
# (https://rustup.rs)
#
# Run through ../setup.sh, or on its own: ./steps/rust.sh
#
# Optional environment overrides:
#   RUST_VERSION=stable     (default: stable) or beta, nightly, or e.g. 1.80.0
#   CARGO_HOME=~/.cargo                       cargo, rustup and installed crates
#   RUSTUP_HOME=~/.rustup                     the toolchains

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RUST_VERSION="${RUST_VERSION:-stable}"
RUST_VERSION_RE='^(stable|beta|nightly|[0-9]+\.[0-9]+(\.[0-9]+)?)$'
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"

step_rust() {
  log "Installing Rust ($RUST_VERSION) with rustup"
  check_version RUST_VERSION "$RUST_VERSION_RE" "stable, beta, nightly or a version like 1.80.0"
  check_install_path CARGO_HOME
  check_install_path RUSTUP_HOME
  have cc || die "A C compiler (cc) is not installed; run the 'make' step first."
  export CARGO_HOME RUSTUP_HOME

  local rustup="$CARGO_HOME/bin/rustup" toolchains
  if [ -x "$rustup" ]; then
    info "rustup already installed: $("$rustup" --version 2>/dev/null)"
    # An installed toolchain is kept (run 'rustup update' to upgrade it).
    toolchains="$("$rustup" toolchain list 2>/dev/null || true)"
    if awk -v t="$RUST_VERSION-" 'index($1, t) == 1 { found = 1 } END { exit !found }' <<<"$toolchains"; then
      info "toolchain $RUST_VERSION already installed"
    else
      "$rustup" toolchain install "$RUST_VERSION" --profile default
    fi
    "$rustup" default "$RUST_VERSION"
  else
    # --no-modify-path: we manage ~/.zshrc ourselves below.
    run_remote_script sh https://sh.rustup.rs -y --no-modify-path \
      --profile default --default-toolchain "$RUST_VERSION"
  fi
  export PATH="$CARGO_HOME/bin:$PATH"

  set_zshrc_block "# >>> wsl-setup: rust >>>" \
"export CARGO_HOME=\"$(zshrc_path "$CARGO_HOME")\"
export RUSTUP_HOME=\"$(zshrc_path "$RUSTUP_HOME")\"
. \"\$CARGO_HOME/env\"
# <<< wsl-setup <<<"
  info "$(rustc --version 2>/dev/null || echo 'rustc not on PATH yet')"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_rust
fi
