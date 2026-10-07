#!/usr/bin/env bash
#
# steps/java.sh - Java JDK: Eclipse Temurin from Adoptium's official apt
# repository (https://adoptium.net/installation/linux/)
#
# Run through ../setup.sh, or on its own: ./steps/java.sh
#
# The chosen JDK becomes the default java/javac, and JAVA_HOME points at it in
# ~/.zshrc. Several JDKs can be installed side by side; re-run with another
# JAVA_VERSION to switch.
#
# Optional environment overrides:
#   JAVA_VERSION=lts        (default: lts, the newest LTS) e.g. JAVA_VERSION=21

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

JAVA_VERSION="${JAVA_VERSION:-lts}"
JAVA_VERSION_RE='^(lts|[0-9]+)$'

step_java() {
  log "Installing Java (Eclipse Temurin $JAVA_VERSION)"
  check_version JAVA_VERSION "$JAVA_VERSION_RE" "lts or a major version like 21"
  local codename major pkg java_home tool alternatives
  codename="$(ubuntu_codename)"
  [ -n "$codename" ] || die "Could not tell the Ubuntu release from /etc/os-release."

  add_apt_repo adoptium https://packages.adoptium.net/artifactory/api/gpg/key/public \
    "deb [arch=$(dpkg --print-architecture) signed-by=SIGNED_BY] https://packages.adoptium.net/artifactory/deb $codename main"

  if [ "$JAVA_VERSION" = lts ]; then
    major=""
    for tool in $(java_lts_majors); do          # newest first
      if apt-cache show "temurin-$tool-jdk" >/dev/null 2>&1; then major="$tool"; break; fi
    done
    [ -n "$major" ] || die "Could not find a Temurin LTS release for $codename (api.adoptium.net)."
  else
    major="$JAVA_VERSION"
  fi
  pkg="temurin-$major-jdk"

  if [ -n "$(apt_installed_version "$pkg")" ]; then
    info "$pkg already installed"
  else
    apt-cache show "$pkg" >/dev/null 2>&1 \
      || die "$pkg is not in the Adoptium repository for $codename; pick a version from the list."
    sudo apt-get install -y "$pkg"
  fi

  # Make it the default java/javac and point JAVA_HOME at it.
  java_home="$(dpkg -L "$pkg" | awk '/\/bin\/javac$/ && !found { sub(/\/bin\/javac$/, ""); print; found = 1 }')"
  [ -n "$java_home" ] || die "Could not find javac in $pkg."
  for tool in java javac; do
    alternatives="$(update-alternatives --list "$tool" 2>/dev/null || true)"
    if grep -qx "$java_home/bin/$tool" <<<"$alternatives"; then
      sudo update-alternatives --set "$tool" "$java_home/bin/$tool" >/dev/null
    fi
  done
  export JAVA_HOME="$java_home"
  set_zshrc_block "# >>> wsl-setup: java >>>" "export JAVA_HOME=\"$(zshrc_path "$java_home")\"
# <<< wsl-setup <<<"
  info "$("$java_home/bin/java" -version 2>&1 | sed -n 1p)"
}

# Print the LTS major versions Adoptium publishes, newest first.
java_lts_majors() {
  local json
  json="$(curl -fsSL https://api.adoptium.net/v3/info/available_releases)" || return 0
  tr -d ' \n' <<<"$json" | sed -nE 's/.*"available_lts_releases":\[([0-9,]*)\].*/\1/p' \
    | tr ',' '\n' | sort -rn
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_java
fi
