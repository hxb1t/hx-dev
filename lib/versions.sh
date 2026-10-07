# shellcheck shell=bash
#
# lib/versions.sh - the versions setup.sh offers in its version picker. Meant
# to be sourced, not executed.
#
# list_versions <tool> prints one "value<TAB>label" line per choice: aliases
# such as latest/lts/stable first, then every version this script can install
# on this machine, newest first. It only uses curl, git and text tools. It
# fails (prints nothing) when the list cannot be fetched.

list_versions() {
  case "$1" in
    proto)    versions_proto ;;
    node)     versions_node ;;
    go)       versions_go ;;
    java)     versions_java ;;
    rust)     versions_rust ;;
    claude)   versions_claude ;;
    gh)       versions_gh ;;
    docker)   versions_docker ;;
    postgres) versions_postgres ;;
    redis)    versions_redis ;;
    *)        return 1 ;;
  esac
}

# Node: every release with a Linux build for this CPU, from index.tab (one
# release per line, newest first; column 3 lists the builds, column 10 the LTS
# codename or "-").
versions_node() {
  local arch tab
  arch="$(machine_arch node)" || return 1
  tab="$(curl -fsSL https://nodejs.org/dist/index.tab)" || return 1
  awk -F'\t' -v build="linux-$arch" '
    NR == 1 { next }
    index("," $3 ",", "," build ",") {
      v = substr($1, 2)
      lts = ($10 == "-") ? "" : "LTS " $10
      if (!latest) latest = v
      if (lts && !newest_lts) newest_lts = v
      rows[++n] = v "\t" sprintf("%-9s %s  %s", v, $2, lts)
    }
    END {
      if (!n) exit 1
      printf "lts\tlts       newest LTS (%s)\n", newest_lts
      printf "latest\tlatest    newest release (%s)\n", latest
      for (i = 1; i <= n; i++) print rows[i]
    }' <<<"$tab"
}

# Go: every release with a Linux tarball for this CPU. Releases before 1.21
# started a line as "go1.20" rather than "go1.20.0"; those are left out because
# GO_VERSION=1.20 means "newest 1.20.x" (which is listed as its own version).
versions_go() {
  local arch json
  arch="$(machine_arch go)" || return 1
  json="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all')" || return 1
  grep -oE "\"go[0-9]+\.[0-9]+\.[0-9]+\.linux-$arch\.tar\.gz\"" <<<"$json" \
    | sed -E 's/^"go([0-9.]+)\.linux-.*$/\1/' | sort -urV | with_latest_alias
}

# proto: release tags from 0.43.0 on. Older releases' "proto setup" (which the
# installer runs) ignores PROTO_HOME, so they break a custom install path.
versions_proto() {
  git_release_tags https://github.com/moonrepo/proto | min_version 0.43.0 \
    | with_latest_alias
}

# Claude Code: versions published on npm from 1.0.37 on, the first release
# with a native build (the installer only installs native builds).
versions_claude() {
  local meta tags stable latest
  meta="$(curl -fsSL -H 'Accept: application/vnd.npm.install-v1+json' \
    https://registry.npmjs.org/@anthropic-ai/claude-code)" || return 1
  tags="$(grep -oE '"dist-tags":\{[^}]*\}' <<<"$meta")" || return 1
  stable="$(sed -nE 's/.*"stable":"([^"]+)".*/\1/p' <<<"$tags")"
  latest="$(sed -nE 's/.*"latest":"([^"]+)".*/\1/p' <<<"$tags")"
  [ -n "$latest" ] || return 1
  if [ -n "$stable" ]; then
    printf 'stable\tstable    tested release (%s)\n' "$stable"
  fi
  printf 'latest\tlatest    newest release (%s)\n' "$latest"
  # Version keys are the only "X.Y.Z":{ in the document.
  grep -oE '"[0-9]+\.[0-9]+\.[0-9]+":\{' <<<"$meta" | tr -d '":{' \
    | sort -urV | min_version 1.0.37 | awk '{ print $0 "\t" $0 }'
}

# gh: every release tag. Each release publishes .deb packages.
versions_gh() {
  git_release_tags https://github.com/cli/cli | with_latest_alias
}

# Java: the Temurin JDKs in Adoptium's apt repository for this Ubuntu release
# and CPU, with the LTS releases marked (from Adoptium's API).
versions_java() {
  local codename arch majors lts=""
  codename="$(ubuntu_codename)"; arch="$(dpkg --print-architecture)"
  majors="$(apt_index_packages \
    "https://packages.adoptium.net/artifactory/deb/dists/$codename/main/binary-$arch/Packages" \
    '^temurin-[0-9]+-jdk$' | sed -E 's/^temurin-([0-9]+)-jdk$/\1/' | sort -urn)" || return 1
  [ -n "$majors" ] || return 1
  lts=" $(java_lts_majors | tr '\n' ' ') "
  awk -v lts="$lts" '
    { v[++n] = $1; if (index(lts, " " $1 " ") && !newest_lts) newest_lts = $1 }
    END {
      if (newest_lts) printf "lts\tlts       newest LTS (%s)\n", newest_lts
      for (i = 1; i <= n; i++)
        printf "%s\t%-9s %s\n", v[i], v[i], (index(lts, " " v[i] " ") ? "LTS" : "")
    }' <<<"$majors"
}

# Rust: the release channels, then every release tag of rust-lang/rust from
# 1.0.0 on (rustup does not install the pre-1.0 releases).
versions_rust() {
  local tags
  tags="$(git_release_tags https://github.com/rust-lang/rust '' | min_version 1.0.0)" || return 1
  [ -n "$tags" ] || return 1
  printf 'stable\tstable    newest release (%s)\n' "${tags%%$'\n'*}"
  printf 'beta\tbeta      next release, for testing\n'
  printf 'nightly\tnightly   built every night\n'
  awk '{ print $0 "\t" $0 }' <<<"$tags"
}

# Docker Engine: the docker-ce versions in Docker's apt repository for this
# Ubuntu release and CPU.
versions_docker() {
  local codename arch
  codename="$(ubuntu_codename)"; arch="$(dpkg --print-architecture)"
  apt_index_versions \
    "https://download.docker.com/linux/ubuntu/dists/$codename/stable/binary-$arch/Packages" \
    docker-ce | with_latest_alias
}

# PostgreSQL: the server major versions in the PGDG repository for this Ubuntu
# release and CPU.
versions_postgres() {
  local codename arch
  codename="$(ubuntu_codename)"; arch="$(dpkg --print-architecture)"
  apt_index_packages \
    "https://apt.postgresql.org/pub/repos/apt/dists/$codename-pgdg/main/binary-$arch/Packages.gz" \
    '^postgresql-[0-9]+$' | sed 's/^postgresql-//' | sort -urn | with_latest_alias
}

# Redis: the redis-server versions in Redis's apt repository for this Ubuntu
# release and CPU.
versions_redis() {
  local codename arch
  codename="$(ubuntu_codename)"; arch="$(dpkg --print-architecture)"
  apt_index_versions \
    "https://packages.redis.io/deb/dists/$codename/main/binary-$arch/Packages" \
    redis-server | with_latest_alias
}

# Print a GitHub repo's release tags as X.Y.Z, newest first. $2 is the tag
# prefix (default "v", as in v1.2.3; rust-lang/rust uses none). Reads the tags
# with git instead of the GitHub API, which allows only 60 calls an hour.
git_release_tags() {
  local refs prefix="${2-v}"
  have git || return 1
  refs="$(GIT_TERMINAL_PROMPT=0 git ls-remote --tags --refs "$1")" || return 1
  sed -nE "s|.*refs/tags/${prefix}([0-9]+\.[0-9]+\.[0-9]+)$|\1|p" <<<"$refs" | sort -urV
}

# Fetch an apt Packages index (plain, or .gz when the URL ends in .gz).
apt_index() {
  case "$1" in
    *.gz) curl -fsSL "$1" | gzip -dc ;;
    *)    curl -fsSL "$1" ;;
  esac
}

# Print the names of the packages in index $1 that match the regex $2.
apt_index_packages() {
  local index
  index="$(apt_index "$1")" || return 1
  awk -v re="$2" '/^Package: / && $2 ~ re { print $2 }' <<<"$index" | sort -u
}

# Print the upstream versions of package $2 in index $1, newest first: the
# apt version without its epoch and Debian revision (5:27.3.1-1~ubuntu → 27.3.1).
apt_index_versions() {
  local index
  index="$(apt_index "$1")" || return 1
  awk -v p="$2" '
    /^Package: / { on = ($2 == p) }
    on && /^Version: / { v = $2; sub(/^[0-9]+:/, "", v); sub(/-[^-]*$/, "", v); print v }' <<<"$index" \
    | sort -urV
}

# Keep the X.Y.Z versions on stdin that are at least $1.
min_version() {
  awk -F. -v min="$1" '
    BEGIN { split(min, m, ".") }
    {
      for (i = 1; i <= 3; i++) {
        if ($i + 0 > m[i] + 0) { print; next }
        if ($i + 0 < m[i] + 0) next
      }
      print
    }'
}

# Turn a newest-first list of versions into picker lines, led by "latest".
with_latest_alias() {
  awk '
    { v[++n] = $0 }
    END {
      if (!n) exit 1
      printf "latest\tlatest    newest release (%s)\n", v[1]
      for (i = 1; i <= n; i++) print v[i] "\t" v[i]
    }'
}
