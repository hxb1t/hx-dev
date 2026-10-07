#!/usr/bin/env bash
#
# setup.sh - set up an Ubuntu dev environment (desktop, server or WSL)
#
#   System
#     packages    apt update/upgrade + base packages
#   Shell
#     zsh         zsh (set as default shell)
#     ohmyzsh     Oh My Zsh + autosuggestions / completions / syntax-highlighting
#   Dev tools
#     git         newest git (git-core PPA) + git-lfs
#     make        build tools: make, gcc/g++, cmake, pkg-config
#     claude      Claude Code
#     gh          GitHub CLI (gh, from the official apt repository)
#   Languages & runtimes
#     proto       proto version manager (https://moonrepo.dev/proto), optional
#     runtimes    Go and Node: pinned globally through proto, or direct
#                 downloads of the official releases into a path you choose
#     java        Java JDK (Eclipse Temurin, Adoptium's apt repository)
#     rust        Rust through rustup
#   Containers
#     docker      Docker Engine + Buildx + Compose (Docker's apt repository)
#     podman      Podman (Ubuntu's package)
#   Databases
#     postgres    PostgreSQL (PGDG apt repository) + a role and database for you
#     redis       Redis (Redis's apt repository)
#   GitHub & SSH setup
#     sshkey      SSH key (ed25519) for GitHub
#     ghlogin     GitHub login (gh auth login), SSH key upload, git identity
#
# Run straight from GitHub (no clone needed; takes the same options as below):
#   curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | bash -s -- --all
#
# Usage:
#   ./setup.sh                  # interactive menu (in a terminal)
#   ./setup.sh --all            # run every step, no menu
#   ./setup.sh zsh ohmyzsh      # run only the named steps
#   ./setup.sh --list           # list steps; --help for all options
#   ./steps/zsh.sh              # run a single step script directly
#
# Menu keys: up/down (or j/k) move, space toggles (on a group name: the whole
#            group), a selects all/none, enter confirms, q quits. Nothing is
#            selected at the start.
# In a terminal, setup.sh then asks, for the selected steps, which version of
# each tool to install and choices such as proto or direct download for Go and
# Node (all picked from a list: enter selects, esc keeps the default; long
# lists filter as you type), and which folders to use (typed; enter keeps the
# default). Settings already set in the environment (the overrides below) are
# not asked.
#
# Steps: packages zsh ohmyzsh git make claude gh proto runtimes java rust docker
#        podman postgres redis sshkey ghlogin
#
# Layout:
#   setup.sh          this entry point: options, step selection, dispatch
#   lib/common.sh     shared config and helpers (log, die, clone_once, ...)
#   lib/menu.sh       interactive checkbox menu, install prompts, version picker
#   lib/versions.sh   the installable versions of each tool, for the picker
#   steps/<step>.sh   one script per step, each defining step_<step>
#
# The 'sshkey' step asks for a passphrase and the 'ghlogin' step needs you to
# approve a browser/device login, so the last steps are interactive.
#
# Optional environment overrides:
#   PROTO_VERSION=latest    (default: latest) e.g. PROTO_VERSION=0.45.0
#   PROTO_HOME=~/.proto                       where proto and its tools live
#   RUNTIMES_VIA=proto      (default: proto)  or RUNTIMES_VIA=direct
#   NODE_VERSION=lts        (default: lts)    e.g. NODE_VERSION=22
#   GO_VERSION=latest       (default: latest) e.g. GO_VERSION=1.23
#   GO_DIR=~/.local/go                        Go install path (direct only)
#   NODE_DIR=~/.local/node                    Node install path (direct only)
#   JAVA_VERSION=lts        (default: lts)    e.g. JAVA_VERSION=21
#   RUST_VERSION=stable     (default: stable) or beta, nightly, or e.g. 1.80.0
#   CARGO_HOME=~/.cargo                       Rust install path (cargo, rustup)
#   RUSTUP_HOME=~/.rustup                     Rust toolchains
#   GIT_FROM=ppa            (default: ppa)    or GIT_FROM=ubuntu
#   CLAUDE_VERSION=stable   (default: stable) or latest, or e.g. 1.0.58
#   GH_VERSION=latest       (default: latest) e.g. GH_VERSION=2.63.0
#   DOCKER_VERSION=latest   (default: latest) e.g. DOCKER_VERSION=27.3.1
#   POSTGRES_VERSION=latest (default: latest) a major version, e.g. 17
#   REDIS_VERSION=latest    (default: latest) e.g. REDIS_VERSION=7.4.1
#   SSH_KEY=~/.ssh/id_ed25519                 key path to create/use
#   SSH_KEY_COMMENT="$USER@$(hostname)"       comment embedded in the key
#   SSH_KEY_TITLE="$(hostname)"               title shown on GitHub
#   HX_DEV_REPO=hxb1t/hx-dev                  repo to download when run via curl
#   HX_DEV_REF=main                           branch, tag or commit to download
#
# Safe to re-run: each step skips work that is already done.

set -euo pipefail

# Where to download the scripts from when not run from a checkout.
HX_DEV_REPO="${HX_DEV_REPO:-hxb1t/hx-dev}"
HX_DEV_REF="${HX_DEV_REF:-main}"

bootstrap_fail() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Run through curl, this file has no lib/ and steps/ next to it: download the
# repo into a temp dir and run its setup.sh instead. This must come before
# anything else runs, and it always exits, so when the script is piped into
# bash the rest of it is never read.
bootstrap_remote() {
  local tmp rc=0
  local url="https://github.com/$HX_DEV_REPO/archive/$HX_DEV_REF.tar.gz"

  command -v curl >/dev/null 2>&1 || bootstrap_fail "curl is required."
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand $tmp now; it is local to this function
  trap "rm -rf '$tmp'" EXIT

  printf '\n\033[1;34m==> %s\033[0m\n' "Downloading $HX_DEV_REPO ($HX_DEV_REF)"
  curl -fsSL "$url" -o "$tmp/src.tar.gz" || bootstrap_fail "Could not download $url"
  mkdir "$tmp/src"
  tar -xzf "$tmp/src.tar.gz" --strip-components=1 -C "$tmp/src"
  [ -f "$tmp/src/lib/common.sh" ] || bootstrap_fail "$url has no lib/common.sh"

  # Piped into bash, stdin is the rest of this script and must not reach the
  # steps. Give them the terminal instead (for the menu and the prompts).
  if [ -t 0 ]; then
    bash "$tmp/src/setup.sh" "$@" || rc=$?
  elif { : </dev/tty; } 2>/dev/null; then
    bash "$tmp/src/setup.sh" "$@" </dev/tty || rc=$?
  else
    bash "$tmp/src/setup.sh" "$@" </dev/null || rc=$?
  fi
  exit "$rc"
}

if [ -z "${BASH_SOURCE[0]:-}" ] || [ ! -f "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh" ]; then
  bootstrap_remote "$@"
fi

SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Note which install settings came from the environment, before the defaults
# fill them in: those are used as given and not asked (ask_install_options).
PRESET_VARS=""
for v in GIT_FROM CLAUDE_VERSION GH_VERSION PROTO_VERSION PROTO_HOME RUNTIMES_VIA \
         NODE_VERSION GO_VERSION GO_DIR NODE_DIR JAVA_VERSION RUST_VERSION CARGO_HOME \
         DOCKER_VERSION POSTGRES_VERSION REDIS_VERSION; do
  if [ -n "${!v:-}" ]; then PRESET_VARS+=" $v"; fi
done
unset v

# shellcheck source=lib/common.sh
source "$SETUP_DIR/lib/common.sh"
# shellcheck source=lib/menu.sh
source "$SETUP_DIR/lib/menu.sh"
# shellcheck source=lib/versions.sh
source "$SETUP_DIR/lib/versions.sh"

# Parallel arrays: same index = same step. Array order is run order, and the
# steps of a group must be next to each other (the menu shows them together).
ALL_STEPS=(
  packages
  zsh ohmyzsh
  git make claude gh
  proto runtimes java rust
  docker podman
  postgres redis
  sshkey ghlogin
)
STEP_DESCS=(
  "apt update/upgrade and base packages"
  "zsh, set as default shell"
  "Oh My Zsh + autosuggestions/completions plugins"
  "newest git (git-core PPA) + git-lfs"
  "build tools: make, gcc/g++, cmake, pkg-config"
  "Claude Code"
  "GitHub CLI (gh)"
  "proto version manager (optional)"
  "Node and Go (via proto or direct download)"
  "Java JDK (Eclipse Temurin)"
  "Rust toolchain through rustup"
  "Docker Engine + Buildx + Compose"
  "Podman (rootless containers)"
  "PostgreSQL server + a database role for you"
  "Redis server"
  "SSH key for GitHub (asks for a passphrase)"
  "GitHub login, key upload, git identity"
)
STEP_GROUPS=(
  "System"
  "Shell" "Shell"
  "Dev tools" "Dev tools" "Dev tools" "Dev tools"
  "Languages & runtimes" "Languages & runtimes" "Languages & runtimes" "Languages & runtimes"
  "Containers" "Containers"
  "Databases" "Databases"
  "GitHub & SSH setup" "GitHub & SSH setup"
)

for s in "${ALL_STEPS[@]}"; do
  # shellcheck source=/dev/null
  source "$SETUP_DIR/steps/$s.sh"
done
unset s

SELECTED_STEPS=()

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] [step ...]

With no arguments in a terminal, an interactive menu lets you pick steps.
With no arguments outside a terminal, every step runs.

Options:
  -a, --all     run every step without showing the menu
  -m, --menu    always show the menu
  -l, --list    list the available steps
  -h, --help    show this help

Steps: ${ALL_STEPS[*]}
Each step is also a standalone script: steps/<step>.sh
USAGE
}

list_steps() {
  local i prev=""
  for ((i = 0; i < ${#ALL_STEPS[@]}; i++)); do
    if [ "${STEP_GROUPS[i]}" != "$prev" ]; then
      prev="${STEP_GROUPS[i]}"
      printf '%s\n' "$prev"
    fi
    printf '  %-10s %s\n' "${ALL_STEPS[i]}" "${STEP_DESCS[i]}"
  done
}

is_step() {
  local s
  for s in "${ALL_STEPS[@]}"; do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}

main() {
  local mode="" s
  local -a steps=()

  while [ $# -gt 0 ]; do
    case "$1" in
      -a|--all)  mode="all" ;;
      -m|--menu) mode="menu" ;;
      -l|--list) list_steps; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      -*)        die "Unknown option '$1' (see --help)" ;;
      *)         steps+=("$1") ;;
    esac
    shift
  done

  check_not_root

  local interactive=0
  if [ -t 0 ] && [ -t 1 ]; then interactive=1; fi

  if [ "${#steps[@]}" -gt 0 ] && [ "$mode" != "menu" ]; then
    for s in "${steps[@]}"; do
      is_step "$s" || die "Unknown step '$s'. Valid steps: ${ALL_STEPS[*]}"
    done
    SELECTED_STEPS=("${steps[@]}")
  elif [ "$mode" = "all" ]; then
    SELECTED_STEPS=("${ALL_STEPS[@]}")
  elif [ "$mode" = "menu" ] || [ "$interactive" -eq 1 ]; then
    [ "$interactive" -eq 1 ] || die "The menu needs an interactive terminal."
    select_steps
  else
    SELECTED_STEPS=("${ALL_STEPS[@]}")
  fi

  if [ "${#SELECTED_STEPS[@]}" -eq 0 ]; then
    log "Nothing selected, nothing to do"
    exit 0
  fi

  if [ "$interactive" -eq 1 ]; then
    ask_install_options
  fi

  log "Running: ${SELECTED_STEPS[*]}"
  preflight

  for s in "${SELECTED_STEPS[@]}"; do
    "step_$s"
  done

  log "Done"
  print_next_steps
}

# What to do after a run: start a new login session, then check the tools of
# the steps that ran.
print_next_steps() {
  local s
  local -a checks=()
  # shellcheck disable=SC2016  # these are commands for the user to type
  for s in "${SELECTED_STEPS[@]}"; do
    case "$s" in
      zsh)      checks+=('echo $SHELL') ;;
      git)      checks+=('git --version; git lfs version') ;;
      make)     checks+=('make --version; gcc --version') ;;
      gh)       checks+=('gh --version') ;;
      proto)    checks+=('proto --version') ;;
      runtimes) checks+=('node -v; go version') ;;
      java)     checks+=('java -version; echo $JAVA_HOME') ;;
      rust)     checks+=('rustc --version; cargo --version') ;;
      docker)   checks+=('docker run --rm hello-world') ;;
      podman)   checks+=('podman run --rm docker.io/library/hello-world') ;;
      postgres) checks+=("psql -c 'select version()'") ;;
      redis)    checks+=('redis-cli ping') ;;
    esac
  done

  printf 'Next steps:\n'
  printf '  - To load the new shell, PATH and groups, %s.\n' "$(relogin_hint)"
  if [ "${#checks[@]}" -gt 0 ]; then
    printf '  - Check the tools:\n'
    printf '      %s\n' "${checks[@]}"
  fi
  if is_selected claude; then
    printf "  - Run 'claude' once to sign in.\n"
  fi
  if is_selected ghlogin; then
    printf '  - Check GitHub access: gh auth status; ssh -T git@github.com\n'
    printf "    (If you set an SSH passphrase, the Oh My Zsh 'ssh-agent' plugin can\n"
    printf '     cache it so you are not asked on every git operation.)\n'
  fi
}

# Run main only when executed, not when sourced (lets the functions be tested).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
