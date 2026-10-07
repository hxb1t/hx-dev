#!/usr/bin/env bash
#
# steps/postgres.sh - PostgreSQL server from the PostgreSQL project's own apt
# repository, PGDG (https://www.postgresql.org/download/linux/ubuntu/)
#
# Run through ../setup.sh, or on its own: ./steps/postgres.sh
#
# Also creates a superuser role and a database named after you, so plain
# `psql` works without sudo. They use peer authentication over the local
# socket: no password, and nothing is opened to the network. Several major
# versions can be installed side by side; each gets its own port.
#
# Optional environment overrides:
#   POSTGRES_VERSION=latest (default: latest) a major version, e.g. 17

set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

POSTGRES_VERSION="${POSTGRES_VERSION:-latest}"
POSTGRES_VERSION_RE='^(latest|[0-9]+)$'

step_postgres() {
  log "Installing PostgreSQL ($POSTGRES_VERSION)"
  check_version POSTGRES_VERSION "$POSTGRES_VERSION_RE" "latest or a major version like 17"
  local codename installed major
  codename="$(ubuntu_codename)"
  [ -n "$codename" ] || die "Could not tell the Ubuntu release from /etc/os-release."

  add_apt_repo pgdg https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    "deb [arch=$(dpkg --print-architecture) signed-by=SIGNED_BY] https://apt.postgresql.org/pub/repos/apt $codename-pgdg main"

  installed="$(pg_installed_majors)"                 # newest first
  if [ "$POSTGRES_VERSION" = latest ] && [ -n "$installed" ]; then
    major="${installed%%$'\n'*}"
    info "PostgreSQL $major already installed"
  else
    if [ "$POSTGRES_VERSION" = latest ]; then
      major="$(pg_newest_major)" || die "Could not find PostgreSQL in the PGDG repository for $codename."
    else
      major="$POSTGRES_VERSION"
    fi
    if [ -n "$(apt_installed_version "postgresql-$major")" ]; then
      info "PostgreSQL $major already installed"
    else
      apt-cache show "postgresql-$major" >/dev/null 2>&1 \
        || die "postgresql-$major is not in the PGDG repository for $codename; pick a version from the list."
      sudo apt-get install -y "postgresql-$major"
    fi
  fi

  enable_service postgresql
  pg_create_user_role "$major"
}

# Print the installed PostgreSQL server major versions, newest first.
pg_installed_majors() {
  # shellcheck disable=SC2016  # ${Status} is a dpkg-query field, not a shell var
  { dpkg-query -W -f='${Status} ${Package}\n' 'postgresql-[0-9]*' 2>/dev/null || true; } \
    | awk '$3 == "installed" && $4 ~ /^postgresql-[0-9]+$/ { sub(/^postgresql-/, "", $4); print $4 }' \
    | sort -rn
}

# Print the newest PostgreSQL major version apt offers.
pg_newest_major() {
  apt-cache search --names-only '^postgresql-[0-9]+$' \
    | awk '{ sub(/^postgresql-/, "", $1); print $1 }' | sort -rn | sed -n 1p | grep .
}

# Run a command as the postgres user, from a directory it can read.
as_postgres() {
  (cd / && sudo -u postgres "$@")
}

# Create a superuser role and a database named after $USER in the cluster of
# major version $1, unless they exist.
pg_create_user_role() {
  local major="$1" port
  if ! [[ "$USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    warn "No PostgreSQL role created: '$USER' is not a plain lowercase name. Create one with: sudo -u postgres createuser --superuser <name>"
    return 0
  fi
  port="$(pg_lsclusters -h 2>/dev/null | awk -v v="$major" '$1 == v && $4 ~ /^online/ { print $3; exit }')"
  if [ -z "$port" ]; then
    warn "PostgreSQL $major is not running, so no role was created for $USER; start it and run this step again."
    return 0
  fi

  if [ "$(as_postgres psql -p "$port" -tAc "SELECT 1 FROM pg_roles WHERE rolname = '$USER'")" = 1 ]; then
    info "PostgreSQL role $USER already exists"
  else
    as_postgres createuser -p "$port" --superuser "$USER"
    info "created PostgreSQL role $USER (superuser, local peer login)"
  fi
  if [ "$(as_postgres psql -p "$port" -tAc "SELECT 1 FROM pg_database WHERE datname = '$USER'")" = 1 ]; then
    info "PostgreSQL database $USER already exists"
  else
    as_postgres createdb -p "$port" -O "$USER" "$USER"
    info "created PostgreSQL database $USER"
  fi
  if [ "$port" != 5432 ]; then
    info "PostgreSQL $major listens on port $port (another version has 5432): psql -p $port"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  run_standalone step_postgres
fi
