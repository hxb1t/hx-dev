#!/usr/bin/env bash
#
# steps/runtimes.sh - Go and Node, through proto or as direct downloads
#
# Run through ../setup.sh, or on its own: ./steps/runtimes.sh
#
# With proto (the default), both are installed and pinned globally by proto.
# With RUNTIMES_VIA=direct, the official release tarballs are unpacked into
# GO_DIR and NODE_DIR, and their bin directories are added to PATH in ~/.zshrc.
#
# Optional environment overrides:
#   RUNTIMES_VIA=proto      (default: proto)  or RUNTIMES_VIA=direct
#   NODE_VERSION=lts        (default: lts)    or latest, 22, 22.11 or 22.11.0
#   GO_VERSION=latest       (default: latest) or 1.23 or 1.23.4
#   GO_DIR=~/.local/go                        Go install path (direct only)
#   NODE_DIR=~/.local/node                    Node install path (direct only)

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

RUNTIMES_VIA="${RUNTIMES_VIA:-proto}"
NODE_VERSION="${NODE_VERSION:-lts}"
GO_VERSION="${GO_VERSION:-latest}"
GO_DIR="${GO_DIR:-$HOME/.local/go}"
NODE_DIR="${NODE_DIR:-$HOME/.local/node}"
NODE_VERSION_RE='^(lts|latest|v?[0-9]+(\.[0-9]+){0,2})$'
GO_VERSION_RE='^(latest|(go)?[0-9]+\.[0-9]+(\.[0-9]+)?)$'

# Marks a directory installed by this step, so an upgrade may replace it.
RUNTIMES_MARKER=".wsl-setup-install"

step_runtimes() {
  check_version NODE_VERSION "$NODE_VERSION_RE" "lts, latest or a version like 22, 22.11 or 22.11.0"
  check_version GO_VERSION "$GO_VERSION_RE" "latest or a version like 1.23 or 1.23.4"
  case "$RUNTIMES_VIA" in
    proto)  runtimes_with_proto ;;
    direct) runtimes_direct ;;
    *)      die "RUNTIMES_VIA must be 'proto' or 'direct' (got '$RUNTIMES_VIA')." ;;
  esac
  info "node: $(node --version 2>/dev/null || echo 'not on PATH yet')"
  info "go:   $(go version 2>/dev/null || echo 'not on PATH yet')"
}

runtimes_with_proto() {
  log "Installing Node ($NODE_VERSION) and Go ($GO_VERSION) with proto"
  have proto || die "proto is not installed; run the 'proto' step first."
  proto install node "${NODE_VERSION#v}" --pin global
  proto install go   "${GO_VERSION#go}"  --pin global

  local dir
  for dir in "$GO_DIR" "$NODE_DIR"; do
    if [ -f "$dir/$RUNTIMES_MARKER" ]; then
      warn "$dir holds a direct install from an earlier run, and its ~/.zshrc block puts it ahead of proto. Remove both to use proto's version."
    fi
  done
}

runtimes_direct() {
  log "Installing Node ($NODE_VERSION) and Go ($GO_VERSION) as direct downloads"
  have curl || die "curl is not installed; run the 'packages' step first."
  have tar  || die "tar is not installed; run the 'packages' step first."
  check_install_path GO_DIR
  check_install_path NODE_DIR

  local go_arch node_arch
  go_arch="$(machine_arch go)"     || die "Unsupported CPU architecture: $(uname -m)"
  node_arch="$(machine_arch node)" || die "Unsupported CPU architecture: $(uname -m)"

  install_go "$go_arch"
  install_node "$node_arch"

  export PATH="$GO_DIR/bin:$HOME/go/bin:$NODE_DIR/bin:$PATH"
  # shellcheck disable=SC2016  # literal $ is intended: expanded by zsh later
  set_zshrc_block "# >>> wsl-setup: go >>>" \
"export PATH=\"$(zshrc_path "$GO_DIR")/bin:"'$HOME/go/bin:$PATH"
# <<< wsl-setup <<<'
  # shellcheck disable=SC2016
  set_zshrc_block "# >>> wsl-setup: node >>>" \
"export PATH=\"$(zshrc_path "$NODE_DIR")/bin:"'$PATH"
# <<< wsl-setup <<<'

  if [ -e "$PROTO_HOME/shims/node" ] || [ -e "$PROTO_HOME/shims/go" ]; then
    warn "proto also provides node/go; the direct installs come first on PATH."
  fi
}

install_go() {
  local arch="$1" version current="" file
  version="$(go_release "$GO_VERSION" || true)"
  [ -n "$version" ] || die "Could not find a Go release for GO_VERSION=$GO_VERSION."

  if [ -x "$GO_DIR/bin/go" ]; then
    current="$("$GO_DIR/bin/go" env GOVERSION 2>/dev/null || true)"
  fi
  if [ "$current" = "$version" ]; then
    info "Go $version already installed in $GO_DIR"
    return 0
  fi

  file="$version.linux-$arch.tar.gz"
  install_tarball "https://dl.google.com/go/$file" \
    "$(curl -fsSL "https://dl.google.com/go/$file.sha256")" "$GO_DIR"
  info "installed Go $version in $GO_DIR"
}

install_node() {
  local arch="$1" version current="" base file sums sha
  version="$(node_release "$NODE_VERSION" || true)"
  [ -n "$version" ] || die "Could not find a Node release for NODE_VERSION=$NODE_VERSION."

  if [ -x "$NODE_DIR/bin/node" ]; then
    current="$("$NODE_DIR/bin/node" --version 2>/dev/null || true)"
  fi
  if [ "$current" = "$version" ]; then
    info "Node $version already installed in $NODE_DIR"
    return 0
  fi

  base="https://nodejs.org/dist/$version"
  file="node-$version-linux-$arch.tar.gz"
  sums="$(curl -fsSL "$base/SHASUMS256.txt")" || die "Could not download $base/SHASUMS256.txt"
  sha="$(awk -v f="$file" '$2 == f { print $1 }' <<<"$sums")"
  [ -n "$sha" ] || die "No checksum for $file in $base/SHASUMS256.txt"
  install_tarball "$base/$file" "$sha" "$NODE_DIR"
  info "installed Node $version in $NODE_DIR"
}

# Print the Go release (e.g. go1.23.4) for "latest", a release line like 1.23,
# or an exact version like 1.23.4.
go_release() {
  local want="${1#go}" list
  case "$want" in
    latest)
      curl -fsSL 'https://go.dev/VERSION?m=text' | sed -n 1p ;;
    *[!0-9.]*|'')
      return 1 ;;
    *.*.*)
      printf 'go%s\n' "$want" ;;
    *)
      list="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all')" || return 1
      # Only "goX.Y" or "goX.Y.Z" in quotes: skips betas and release candidates.
      grep -oE "\"go${want//./\\.}(\\.[0-9]+)?\"" <<<"$list" \
        | tr -d '"' | sort -uV | tail -n 1 ;;
  esac
}

# Print the Node release (e.g. v22.11.0) for "lts", "latest", a major version
# like 22, or an exact version like 22.11.0. index.json lists one release per
# line, newest first.
node_release() {
  local want="${1#v}" index line
  case "$want" in
    lts|latest) ;;
    *[!0-9.]*|'') return 1 ;;
    *.*.*) printf 'v%s\n' "$want"; return 0 ;;
  esac

  index="$(curl -fsSL https://nodejs.org/dist/index.json)" || return 1
  case "$want" in
    lts)    line="$(grep -m 1 '"lts":"' <<<"$index")" ;;
    latest) line="$(grep -m 1 '"version":"v' <<<"$index")" ;;
    *)      line="$(grep -m 1 "\"version\":\"v${want//./\\.}\\." <<<"$index")" ;;
  esac
  [ -n "$line" ] || return 1
  sed -E 's/^.*"version":"(v[^"]+)".*$/\1/' <<<"$line"
}

# Download a release tarball, check its sha256 and unpack it into dir,
# replacing an older install made by this step. A non-empty directory that this
# step did not create is never touched.
install_tarball() {
  local url="$1" sha256="$2" dir="$3" parent tmp
  local -a as_owner=()

  if [ -e "$dir" ] && [ ! -d "$dir" ]; then
    die "$dir exists and is not a directory; choose another path."
  fi
  if [ -d "$dir" ] && [ -n "$(ls -A "$dir")" ] && [ ! -f "$dir/$RUNTIMES_MARKER" ]; then
    die "$dir already exists and was not installed by this script; remove it or choose another path."
  fi
  [ -n "$sha256" ] || die "No checksum available for $url"

  # Use sudo only when the install location is not writable by the user.
  parent="$(dirname "$dir")"
  while [ ! -d "$parent" ]; do parent="$(dirname "$parent")"; done
  if [ ! -w "$parent" ]; then as_owner=(sudo); fi

  tmp="$(mktemp -d)"
  info "downloading $url"
  curl -fsSL "$url" -o "$tmp/release.tar.gz" \
    || { rm -rf "$tmp"; die "Could not download $url"; }
  printf '%s  %s\n' "${sha256%% *}" "$tmp/release.tar.gz" | sha256sum -c --quiet - \
    || { rm -rf "$tmp"; die "Checksum mismatch for $url"; }
  mkdir "$tmp/unpacked"
  tar -xzf "$tmp/release.tar.gz" --strip-components=1 -C "$tmp/unpacked" \
    || { rm -rf "$tmp"; die "Could not unpack $url"; }
  touch "$tmp/unpacked/$RUNTIMES_MARKER"

  "${as_owner[@]}" mkdir -p "$(dirname "$dir")"
  "${as_owner[@]}" rm -rf "$dir"
  "${as_owner[@]}" mv "$tmp/unpacked" "$dir"
  rm -rf "$tmp"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_runtimes
fi
