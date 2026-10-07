# shellcheck shell=bash
# shellcheck disable=SC2088  # "~/.zshrc" in messages is meant literally
#
# lib/common.sh - shared configuration and helpers for setup.sh and the
# scripts in steps/. Meant to be sourced, not executed.

# Every step script sources this file, and so does setup.sh; load it once.
if [ -n "${HX_DEV_COMMON_LOADED:-}" ]; then
  return 0
fi
HX_DEV_COMMON_LOADED=1

# The ~/.zshrc block markers ("# >>> wsl-setup: ... >>>") and the direct
# install mark file (.wsl-setup-install) keep their original "wsl-setup" name,
# so machines set up before the rename are still recognised and not duplicated.

USER="${USER:-$(id -un)}"
export USER

# Used by both the 'sshkey' and 'ghlogin' steps.
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

ZSHRC="$HOME/.zshrc"

export PROTO_HOME="${PROTO_HOME:-$HOME/.proto}"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------- helpers ---

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

check_not_root() {
  [ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used where needed)."
}

preflight() {
  have sudo || die "sudo is required."
  sudo -v   || die "Could not get sudo access."
  if ! grep -qE '^ID(_LIKE)?=.*\bubuntu\b' /etc/os-release 2>/dev/null; then
    warn "This does not look like Ubuntu (or an Ubuntu-based system); continuing anyway."
  fi
}

# True when running under WSL (Windows Subsystem for Linux).
is_wsl() {
  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

# True when systemd manages services (PID 1). WSL runs it only when
# /etc/wsl.conf has "[boot] systemd=true", the default on new installs.
has_systemd() {
  [ "$(ps -p 1 -o comm= 2>/dev/null)" = systemd ]
}

# How to make a new login shell, PATH or group membership take effect.
relogin_hint() {
  if is_wsl; then
    echo "run 'wsl --shutdown' in PowerShell and reopen Ubuntu"
  else
    echo "log out and back in"
  fi
}

# The Ubuntu release codename (e.g. noble) that vendor apt repositories use.
# Ubuntu-based systems such as Linux Mint report it as UBUNTU_CODENAME.
ubuntu_codename() {
  (
    # shellcheck source=/dev/null
    . /etc/os-release
    printf '%s\n' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  )
}

# Add a vendor apt repository once. The signing key from $2 goes to
# /etc/apt/keyrings/<name>.asc (or .gpg for a binary key) and the source line
# $3 to /etc/apt/sources.list.d/<name>.list, with SIGNED_BY replaced by the key
# path. Runs apt-get update when it adds the repository.
#   add_apt_repo docker https://download.docker.com/linux/ubuntu/gpg \
#     "deb [arch=amd64 signed-by=SIGNED_BY] https://download.docker.com/linux/ubuntu noble stable"
add_apt_repo() {
  local name="$1" key_url="$2" line="$3" list key tmp
  list="/etc/apt/sources.list.d/$name.list"
  if [ -f "$list" ]; then
    info "apt repository already added: $list"
    return 0
  fi
  tmp="$(mktemp)"
  curl -fsSL "$key_url" -o "$tmp" || { rm -f "$tmp"; die "Could not download $key_url"; }
  if grep -q 'BEGIN PGP PUBLIC KEY BLOCK' "$tmp"; then
    key="/etc/apt/keyrings/$name.asc"
  else
    key="/etc/apt/keyrings/$name.gpg"
  fi
  sudo install -d -m 755 /etc/apt/keyrings
  sudo install -m 644 "$tmp" "$key"
  rm -f "$tmp"
  printf '%s\n' "${line//SIGNED_BY/$key}" | sudo tee "$list" >/dev/null
  info "added apt repository: $list"
  sudo apt-get update
}

# Print the installed version of an apt package, or nothing.
apt_installed_version() {
  # shellcheck disable=SC2016  # ${Status} is a dpkg-query field, not a shell var
  dpkg-query -W -f='${Status} ${Version}\n' "$1" 2>/dev/null \
    | awk '$3 == "installed" { print $4 }'
}

# Print the full apt version (e.g. 5:27.3.1-1~ubuntu.24.04~noble) of package
# $1 whose upstream part is $2 (27.3.1), or nothing if apt does not offer it.
apt_full_version() {
  apt-cache madison "$1" 2>/dev/null | awk -v want="$2" '
    {
      up = $3
      sub(/^[0-9]+:/, "", up)
      sub(/-[^-]*$/, "", up)
      if (up == want) { print $3; exit }
    }'
}

# Install apt packages that share one version, from a repository already
# added. "latest" installs the newest and keeps a copy that is installed
# already. An exact upstream version (27.3.1) installs that build, downgrading
# if needed, and holds the packages so apt upgrade leaves them alone; "latest"
# releases the hold again.
#   apt_install_version <latest|version> <pkg> [pkg...]   (the first pkg's
#   version is the one compared)
apt_install_version() {
  local want="$1" installed held full p
  shift
  local -a specs=()
  installed="$(apt_installed_version "$1")"
  held="$(apt-mark showhold "$@" 2>/dev/null || true)"

  if [ "$want" = latest ]; then
    if [ -n "$installed" ] && [ -z "$held" ]; then
      info "$1 already installed: $installed"
      return 0
    fi
    if [ -n "$held" ]; then
      sudo apt-mark unhold "$@" >/dev/null
      info "released the hold on: $(echo "$held" | tr '\n' ' ')"
    fi
    sudo apt-get install -y "$@"
    return 0
  fi

  full="$(apt_full_version "$1" "$want")"
  [ -n "$full" ] || die "$1 $want is not in the apt repository; pick a version from the list."
  if [ "$installed" = "$full" ]; then
    info "$1 $want already installed"
  else
    if [ -n "$held" ]; then sudo apt-mark unhold "$@" >/dev/null; fi
    for p in "$@"; do specs+=("$p=$full"); done
    sudo apt-get install -y --allow-downgrades "${specs[@]}"
  fi
  sudo apt-mark hold "$@" >/dev/null
  info "$* held at $want (apt upgrade leaves them alone; version 'latest' releases them)"
}

# Enable and start systemd services. Without systemd, say how to start them.
enable_service() {
  local unit
  if has_systemd; then
    for unit in "$@"; do
      if systemctl cat "$unit.service" >/dev/null 2>&1; then
        sudo systemctl enable --now "$unit"
      else
        warn "No $unit service was found, so it was not started."
      fi
    done
  elif is_wsl; then
    warn "systemd is not running, so $* will not start on its own. Add '[boot]' and 'systemd=true' to /etc/wsl.conf, run 'wsl --shutdown', or start it now with: sudo service $1 start"
  else
    warn "systemd is not running, so $* will not start on its own. Start it with: sudo service $1 start"
  fi
}

# Clone a git repo only if the target directory does not exist yet.
clone_once() {
  local url="$1" dest="$2"
  if [ -d "$dest" ]; then
    info "already present: $dest"
  else
    git clone --depth=1 "$url" "$dest"
  fi
}

# Append a block to ~/.zshrc once, identified by a marker line.
append_zshrc_block() {
  local marker="$1" content="$2"
  touch "$ZSHRC"
  if grep -qF "$marker" "$ZSHRC"; then
    info "~/.zshrc already contains: $marker"
  else
    printf '\n%s\n%s\n' "$marker" "$content" >> "$ZSHRC"
  fi
}

# Write a block to ~/.zshrc, replacing an older version of it. Use this instead
# of append_zshrc_block when the content holds a value the user can change
# (like an install path). The block runs from the marker line to the next
# "# <<< wsl-setup <<<" line, so the content must end with that line.
set_zshrc_block() {
  local marker="$1" content="$2" end="# <<< wsl-setup <<<" current tmp
  touch "$ZSHRC"
  current="$(awk -v m="$marker" -v e="$end" '
    $0 == m { on = 1; next }
    on      { print }
    on && $0 == e { exit }' "$ZSHRC")"

  if [ "$current" = "$content" ]; then
    info "~/.zshrc already up to date: $marker"
    return 0
  fi

  if grep -qxF "$marker" "$ZSHRC"; then
    case "$current" in
      *"$end") ;;
      *) die "~/.zshrc has '$marker' without a closing '$end' line; fix it by hand." ;;
    esac
    # Drop the old block and the blank line printed before it.
    tmp="$(mktemp)"
    awk -v m="$marker" -v e="$end" '
      skip    { if ($0 == e) skip = 0; next }
      $0 == m { skip = 1; blank = 0; next }
      blank   { print ""; blank = 0 }
      $0 == "" { blank = 1; next }
      { print }
      END     { if (blank) print "" }' "$ZSHRC" > "$tmp"
    cat "$tmp" > "$ZSHRC"   # write in place: keeps a symlinked ~/.zshrc intact
    rm -f "$tmp"
    info "~/.zshrc: replacing $marker"
  fi
  printf '\n%s\n%s\n' "$marker" "$content" >> "$ZSHRC"
}

# True if $1 can be used as an install path: absolute, and free of characters
# that would break it inside double quotes in ~/.zshrc.
valid_install_path() {
  case "$1" in
    /?*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[\"\`\$\\]*) return 1 ;;
  esac
}

# Die unless the variable named $1 holds a valid install path.
check_install_path() {
  valid_install_path "${!1}" \
    || die "$1 must be an absolute path without quotes, \$, \` or \\ (got '${!1}')."
}

# Print a path the way it should appear in ~/.zshrc: as $HOME/... when it is
# under the home directory, otherwise unchanged.
zshrc_path() {
  # shellcheck disable=SC2016  # literal $HOME is intended: expanded by zsh later
  case "$1" in
    "$HOME"/*) printf '%s/%s' '$HOME' "${1#"$HOME"/}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

# Download an installer script, then run it with the given shell. Downloading
# first means a failed download stops the step instead of running an empty or
# partial script.
run_remote_script() {
  local shell="$1" url="$2" tmp rc=0
  shift 2
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; die "Could not download $url"; }
  "$shell" "$tmp" "$@" || rc=$?
  rm -f "$tmp"
  [ "$rc" -eq 0 ] || die "The installer from $url failed (exit code $rc)."
}

# Print this machine's CPU architecture as named by $1's downloads:
# go (amd64, arm64) or node (x64, arm64). Fails on any other CPU.
machine_arch() {
  case "$(uname -m)" in
    x86_64)
      if [ "$1" = go ]; then echo amd64; else echo x64; fi ;;
    aarch64|arm64)
      echo arm64 ;;
    *)
      return 1 ;;
  esac
}

# Die unless the variable named $1 matches the regex $2 (the allowed versions,
# shown to the user as $3).
check_version() {
  [[ "${!1}" =~ $2 ]] || die "$1 must be $3 (got '${!1}')."
}

# Run one step function when its script is executed directly
# (e.g. ./steps/zsh.sh) instead of through setup.sh.
run_standalone() {
  check_not_root
  preflight
  "$1"
  log "Done"
}
