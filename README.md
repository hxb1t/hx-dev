# hx-dev

Set up a ready-to-use **Ubuntu** dev environment with one command, on a desktop, a server or WSL. Pick what you want from a menu: zsh + Oh My Zsh, git and build tools, Node, Go, Java and Rust, Docker and Podman, PostgreSQL and Redis, Claude Code, the GitHub CLI, and an SSH key that is already registered with your GitHub account. Everything comes from each project's official source, and you choose the version of each tool from a list.

## Quick start

In a terminal on your Ubuntu machine, as your normal user (not root):

```bash
curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | bash
```

A menu lets you choose which steps to run. Then, for the steps you picked, you choose each tool's version from a list of every version the script can install on your machine, plus choices such as proto or direct download for Go and Node. Folders are typed; press enter to keep the default. To skip the menu and run everything with the defaults:

```bash
curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | bash -s -- --all
```

When it finishes, it prints what to check for the steps that ran. In short:

1. Start a new login session so the new shell, `PATH` and groups (such as `docker`) apply: log out and back in, or on WSL run `wsl --shutdown` in PowerShell and reopen Ubuntu.
2. Check the tools, for example `node -v`, `java -version`, `rustc --version`, `docker run --rm hello-world`, `psql -c 'select version()'`, `redis-cli ping`.
3. Run `claude` once to sign in.
4. Check GitHub access: `gh auth status; ssh -T git@github.com`

If you set an SSH key passphrase, the Oh My Zsh `ssh-agent` plugin can cache it so you are not asked on every git operation.

## Requirements

- Ubuntu 22.04 or newer: desktop, server or WSL. Ubuntu-based systems such as Linux Mint work too. Other systems get a warning and the script carries on.
- A normal user account with `sudo` access (the script refuses to run as root)
- `curl`, which Ubuntu includes by default
- For services (Docker, PostgreSQL, Redis) to start on their own: systemd. It runs on every normal Ubuntu install, and on WSL when `/etc/wsl.conf` has `[boot]` `systemd=true` (the default for new WSL installs). Without it, the script tells you how to start them by hand.

## Steps

The menu shows the steps in groups:

| Group | Step | What it does |
|---|---|---|
| **System** | `packages` | `apt update`/`upgrade`, then installs `ca-certificates curl wget git unzip zip gzip xz-utils openssh-client software-properties-common` |
| **Shell** | `zsh` | Installs zsh and makes it your default shell (from your next login) |
|  | `ohmyzsh` | Installs Oh My Zsh with the `zsh-autosuggestions`, `zsh-completions` and `zsh-syntax-highlighting` plugins |
| **Dev tools** | `git` | Installs the newest git from the official [git-core PPA](https://launchpad.net/~git-core/+archive/ubuntu/ppa) (or keeps Ubuntu's), plus git-lfs |
|  | `make` | Build tools: `make`, gcc/g++ (`build-essential`), `cmake`, `pkg-config`. Needed for Rust and native Node modules |
|  | `claude` | Installs Claude Code with the official installer |
|  | `gh` | Installs the GitHub CLI from GitHub's own apt repository (Ubuntu's version is outdated). A specific version comes from that release's `.deb` on GitHub instead, checked against the release's checksums and held in apt |
| **Languages & runtimes** | `proto` | Optional. Installs the proto version manager in `~/.proto` (or `PROTO_HOME`) and adds it to your `PATH` in `~/.zshrc` |
|  | `runtimes` | Installs Node (LTS) and Go (latest). With proto, they are pinned as your global versions. With direct download, the official release tarballs are checked against their published SHA-256 checksums, unpacked into `~/.local/go` and `~/.local/node` (or the paths you choose) and added to your `PATH` in `~/.zshrc` |
|  | `java` | Installs an Eclipse Temurin JDK (newest LTS by default) from [Adoptium's apt repository](https://adoptium.net/installation/linux/), makes it the default `java`/`javac` and sets `JAVA_HOME` in `~/.zshrc`. Several JDKs can be installed side by side |
|  | `rust` | Installs Rust with [rustup](https://rustup.rs) into `~/.cargo` and `~/.rustup` (or the paths you choose) and loads it from `~/.zshrc` |
| **Containers** | `docker` | Installs Docker Engine, Buildx and Compose from [Docker's apt repository](https://docs.docker.com/engine/install/ubuntu/), starts it, and adds you to the `docker` group. On WSL with Docker Desktop's WSL integration, it does nothing |
|  | `podman` | Installs Podman from Ubuntu's archive, for rootless containers. Works next to Docker |
| **Databases** | `postgres` | Installs PostgreSQL from the [PostgreSQL project's apt repository](https://www.postgresql.org/download/linux/ubuntu/) (PGDG), starts it, and creates a superuser role and database named after you, so `psql` works without sudo |
|  | `redis` | Installs Redis from [Redis's apt repository](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/apt/) and starts it, listening on localhost only |
| **GitHub & SSH setup** | `sshkey` | Creates an ed25519 SSH key at `~/.ssh/id_ed25519` and asks you for a passphrase |
|  | `ghlogin` | Logs in with `gh` through your browser, uploads the SSH key, trusts GitHub's host keys and sets your git name and email |

The menu and `--all` run steps in the order above. Steps named on the command line run in the order you give them. Some need an earlier step to have run at some point:

- `ohmyzsh` needs `zsh` and `packages`
- `git`, `runtimes` (direct download), `sshkey` need `packages`
- `runtimes` (with proto) needs `proto`
- `rust` needs `make` (for the C linker)
- `ghlogin` needs `gh` and `sshkey`

A step whose prerequisite is missing stops and tells you which step to run first.

**Safe to re-run.** Each step skips work that is already done. A direct Go or Node install that already has the requested version is kept, and a newer version replaces only a folder the script installed itself. An apt repository is added once. The PostgreSQL role and database are created only if missing. An existing SSH key is never overwritten, a key already on GitHub is not uploaded twice, and a git name or email you have already set is kept.

**Interactive steps.** `sshkey` asks for a passphrase and `ghlogin` asks you to approve the login in a browser. If no browser opens, visit the URL shown and enter the one-time code. These prompts work even when the script is piped from curl.

## Options

```text
setup.sh [options] [step ...]

  -a, --all     run every step without showing the menu
  -m, --menu    always show the menu
  -l, --list    list the available steps
  -h, --help    show this help
```

With no options in a terminal, the menu opens with nothing selected. Without a terminal, every step runs.

Name steps to run only those, with no menu:

```bash
curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | bash -s -- docker postgres redis
```

Menu keys: <kbd>↑</kbd>/<kbd>↓</kbd> (or <kbd>j</kbd>/<kbd>k</kbd>) move, <kbd>space</kbd> toggles (on a group name, the whole group), <kbd>a</kbd> selects all or none, <kbd>enter</kbd> confirms, <kbd>q</kbd> quits.

## Choosing versions and folders

When you run in a terminal, the versions, choices and folders are asked after the menu, for the selected steps only. Any of the variables below that you already set is used as given and not asked. Without a terminal, the defaults apply.

**Picking from a list.** Each version question, and each choice like proto or direct download, opens a list. Version lists have aliases like `latest`, `lts` and `stable` at the top, then every installable version, newest first. In a long list, start typing to filter. Matches start at a word, so `22.1` finds the 22.1x releases and `jod` finds that Node LTS line. Use <kbd>↑</kbd>/<kbd>↓</kbd>, <kbd>PgUp</kbd>/<kbd>PgDn</kbd> and <kbd>Home</kbd>/<kbd>End</kbd> to move, <kbd>enter</kbd> to select, and <kbd>esc</kbd> to keep the default. If a list cannot be fetched (for example offline), you type the version instead.

The lists come from each project's official source and show only what can be installed on your Ubuntu release and CPU:

| Tool | Source | Listed |
|---|---|---|
| Node | `nodejs.org/dist/index.tab` | Releases with a Linux build for your CPU |
| Go | `go.dev/dl/?mode=json&include=all` | Releases with a Linux tarball for your CPU |
| Java | Adoptium's apt repository (+ its API for LTS) | Temurin JDKs for your Ubuntu release |
| Rust | the `rust-lang/rust` git tags | `stable`, `beta`, `nightly` and every release from 1.0.0 |
| proto | the repo's git tags | 0.43.0 and newer (older releases' setup ignores `PROTO_HOME`) |
| Claude Code | the npm registry | 1.0.37 and newer (the first release with a native build) |
| GitHub CLI | the repo's git tags | Every release |
| Docker | Docker's apt repository | Docker Engine versions for your Ubuntu release |
| PostgreSQL | the PGDG apt repository | Major versions for your Ubuntu release |
| Redis | Redis's apt repository | Redis versions for your Ubuntu release |

The git tags are read with `git ls-remote`, which doesn't count toward GitHub's API rate limit.

When piping from curl, put the variables in front of `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | NODE_VERSION=22 bash -s -- runtimes
curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | POSTGRES_VERSION=17 bash -s -- postgres
```

| Variable | Default | Used by |
|---|---|---|
| `GIT_FROM` | `ppa` | `git`: `ppa` (newest, git-core PPA) or `ubuntu` |
| `CLAUDE_VERSION` | `stable` | `claude`: `stable`, `latest` or a version like `1.0.58` |
| `GH_VERSION` | `latest` | `gh`: `latest` or a version like `2.63.0` |
| `PROTO_VERSION` | `latest` | `proto`: `latest` or a version like `0.45.0` |
| `PROTO_HOME` | `~/.proto` | `proto`, `runtimes`: where proto and the tools it installs live |
| `RUNTIMES_VIA` | `proto` | `runtimes`: `proto`, or `direct` to download the official releases |
| `NODE_VERSION` | `lts` | `runtimes`: `lts`, `latest`, a major version like `22`, or an exact one like `22.11.0` |
| `GO_VERSION` | `latest` | `runtimes`: `latest`, a release line like `1.23`, or an exact one like `1.23.4` |
| `GO_DIR` | `~/.local/go` | `runtimes` with direct download: the Go install folder |
| `NODE_DIR` | `~/.local/node` | `runtimes` with direct download: the Node install folder |
| `JAVA_VERSION` | `lts` | `java`: `lts` (the newest LTS) or a major version like `21` |
| `RUST_VERSION` | `stable` | `rust`: `stable`, `beta`, `nightly` or a version like `1.80.0` |
| `CARGO_HOME` | `~/.cargo` | `rust`: cargo, rustup and installed crates |
| `RUSTUP_HOME` | `~/.rustup` | `rust`: the toolchains |
| `DOCKER_VERSION` | `latest` | `docker`: `latest` or a version like `27.3.1` |
| `POSTGRES_VERSION` | `latest` | `postgres`: `latest` or a major version like `17` |
| `REDIS_VERSION` | `latest` | `redis`: `latest` or a version like `7.4.1` |
| `SSH_KEY` | `~/.ssh/id_ed25519` | `sshkey`, `ghlogin`: the key to create and upload |
| `SSH_KEY_COMMENT` | `$USER@$(hostname)` | `sshkey`: comment stored in the key |
| `SSH_KEY_TITLE` | `$(hostname)` | `ghlogin`: the key's name on GitHub |
| `HX_DEV_REPO` | `hxb1t/hx-dev` | the GitHub repo to download when run through curl |
| `HX_DEV_REF` | `main` | the branch, tag or commit to download when run through curl |

The variables also accept forms the lists don't show, such as `NODE_VERSION=22` (newest 22.x) or `GO_VERSION=1.23` (newest 1.23.x).

**What a version means on re-runs.**

- **`latest` and `stable`** install the tool if it is missing and leave an installed copy alone. This applies to proto, Claude Code, gh, Docker, PostgreSQL and Redis.
- **A specific version** replaces an installed copy that differs, including a downgrade.
- **Docker, Redis and gh pinned to a version** are held with `apt-mark hold`, so `apt upgrade` leaves them alone. Setting the version back to `latest` releases them.
- **PostgreSQL major versions** install side by side, each on its own port.
- **Java** installs the chosen JDK next to any others and makes it the default.
- **Go and Node through proto** follow proto's rules. With direct download, they are updated whenever the requested version (for example the newest LTS) differs from what is installed.
- **Claude Code** updates itself in the background, so a specific version stays put only if you turn its auto-updates off.

## What it changes on your system

- **`~/.zshrc`**: the `ohmyzsh` step replaces the `plugins=(...)` line with `plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting)` and adds `zsh-completions` to `fpath`. `proto`, `runtimes` (direct download), `java` and `rust` each add a block marked `# >>> wsl-setup: <name> >>>`. When you re-run with a different path or version, these blocks are rewritten, not duplicated. The marker keeps the project's original name so machines set up before the rename stay recognised.
- **Go and Node folders** (direct download only): `~/.local/go` and `~/.local/node` by default, each marked with a `.wsl-setup-install` file. The script only ever replaces a folder that carries this mark. It refuses to touch a non-empty folder it did not create. `sudo` is used only if you pick a location your user cannot write to, like `/usr/local/go`.
- **apt repositories**: each is added once, with its signing key in `/etc/apt/keyrings/` and its source in `/etc/apt/sources.list.d/`:

  | Step | Source file |
  |---|---|
  | `gh` | `github-cli.list` |
  | `java` | `adoptium.list` |
  | `docker` | `docker.list` |
  | `postgres` | `pgdg.list` |
  | `redis` | `redis.list` |
  | `git` | the git-core PPA, added with `add-apt-repository` |

- **Services**: `docker`, `postgres` and `redis` enable and start their systemd services.
- **Groups**: `docker` adds you to the `docker` group, which lets you control Docker, and through it the machine, without sudo.
- **PostgreSQL**: a superuser role and a database named after your user, using peer authentication over the local socket. There is no password, and nothing is opened to the network.
- **SSH**: `sshkey` creates the key. `ghlogin` adds GitHub's host keys (fetched over HTTPS from the GitHub API) to `~/.ssh/known_hosts` and uploads your public key to your GitHub account. Logging in requests the `admin:public_key` scope so the key can be uploaded.
- **git**: `git lfs install` adds the LFS filters to `~/.gitconfig`. If they are not set yet, `ghlogin` sets `user.name` to your GitHub name (or username, if no name is set) and `user.email` to your GitHub `noreply` address, so your real email stays private. Change them anytime with `git config --global`.
- **Default shell**: changed to zsh with `chsh`.

## Running from a clone

To read everything before running it, or to work on the scripts, clone the repo and run it locally. Nothing is downloaded in that case.

```bash
git clone https://github.com/hxb1t/hx-dev.git
cd hx-dev
./setup.sh
```

Every step is also a standalone script:

```bash
./steps/docker.sh
```

## How it works

```text
setup.sh          entry point: options, menu, runs the selected steps
lib/common.sh     shared settings and helper functions
lib/menu.sh       the interactive menu, install questions and version picker
lib/versions.sh   fetches the installable versions of each tool for the picker
steps/<step>.sh   one script per step
```

When `setup.sh` is piped from curl, it has no `lib/` or `steps/` next to it. It downloads the repo as a tarball into a temporary folder, runs that copy with the same options, and deletes the folder when done.

To add a step, create `steps/<name>.sh` following the pattern of the existing ones, then add its name, description and group to `ALL_STEPS`, `STEP_DESCS` and `STEP_GROUPS` in `setup.sh`. See [CLAUDE.md](CLAUDE.md) for the conventions each step follows.
