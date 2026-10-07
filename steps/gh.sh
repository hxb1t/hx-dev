#!/usr/bin/env bash
#
# steps/gh.sh - GitHub CLI (gh)
#
# Run through ../setup.sh, or on its own: ./steps/gh.sh
#
# GH_VERSION=latest installs gh from GitHub's official apt repository, so
# `apt upgrade` keeps it current. An exact version installs that release's .deb
# from GitHub (checked against the release's checksums) and holds it in apt.
#
# Optional environment overrides:
#   GH_VERSION=latest       (default: latest) e.g. GH_VERSION=2.63.0

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

GH_VERSION="${GH_VERSION:-latest}"
GH_VERSION_RE='^(latest|v?[0-9]+\.[0-9]+\.[0-9]+)$'

step_gh() {
  log "Installing GitHub CLI ($GH_VERSION)"
  check_version GH_VERSION "$GH_VERSION_RE" "latest or a version like 2.63.0"

  local want="${GH_VERSION#v}" current="" held
  if have gh; then
    current="$(gh --version | awk 'NR == 1 { print $3 }')"
  fi
  held="$(apt-mark showhold gh 2>/dev/null || true)"

  if [ "$want" = latest ]; then
    gh_from_apt_repo "$current" "$held"
  else
    gh_release_deb "$want" "$current" "$held"
  fi
}

# Latest gh from the official apt repository (the Ubuntu archive version is old).
gh_from_apt_repo() {
  local current="$1" held="$2"
  if [ -n "$current" ] && [ -z "$held" ]; then
    info "gh already installed: $current"
    return 0
  fi
  if [ -n "$held" ]; then
    sudo apt-mark unhold gh >/dev/null
    info "gh was held at $current; unheld so it follows the apt repository"
  fi

  add_apt_repo github-cli https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    "deb [arch=$(dpkg --print-architecture) signed-by=SIGNED_BY] https://cli.github.com/packages stable main"
  sudo apt-get install -y gh
}

# One exact gh release: its .deb from GitHub, checked against the release's
# checksums file, then held so `apt upgrade` does not replace it.
gh_release_deb() {
  local want="$1" current="$2" held="$3" base file sums sha tmp
  if [ "$current" = "$want" ]; then
    info "gh $want already installed"
  else
    base="https://github.com/cli/cli/releases/download/v$want"
    file="gh_${want}_linux_$(dpkg --print-architecture).deb"
    sums="$(curl -fsSL "$base/gh_${want}_checksums.txt")" \
      || die "Could not download the checksums for gh $want; is $want a gh release?"
    sha="$(awk -v f="$file" '$2 == f { print $1 }' <<<"$sums")"
    [ -n "$sha" ] || die "gh $want has no $file."

    tmp="$(mktemp -d)"
    info "downloading $base/$file"
    curl -fsSL "$base/$file" -o "$tmp/$file" \
      || { rm -rf "$tmp"; die "Could not download $base/$file"; }
    printf '%s  %s\n' "$sha" "$tmp/$file" | sha256sum -c --quiet - \
      || { rm -rf "$tmp"; die "Checksum mismatch for $base/$file"; }
    if [ -n "$held" ]; then sudo apt-mark unhold gh >/dev/null; fi
    sudo dpkg -i "$tmp/$file" || { rm -rf "$tmp"; die "Could not install $file"; }
    rm -rf "$tmp"
  fi
  sudo apt-mark hold gh >/dev/null
  info "gh held at $want (apt upgrade leaves it alone; GH_VERSION=latest releases it)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_gh
fi
