# CLAUDE.md

## What this is

Bash scripts (project name: hx-dev) that set up an Ubuntu dev environment on a desktop, server or WSL: apt packages, zsh + Oh My Zsh, git and build tools, Node/Go (proto or direct), Java, Rust, Docker, Podman, PostgreSQL, Redis, Claude Code, GitHub CLI, SSH key, GitHub login. There is no build and no test suite; the scripts install software on the real machine, so do not run steps to "test" a change.

## Commands

```bash
# Syntax-check every script
for f in setup.sh lib/*.sh steps/*.sh; do bash -n "$f" || echo "FAIL $f"; done

# Lint (run from the repo root: the `# shellcheck source=` directives are relative to it)
shellcheck -x setup.sh lib/*.sh steps/*.sh

# Safe CLI checks (no installs)
./setup.sh --list
./setup.sh --help

# Run one step: through the entry point, or the step script directly
./setup.sh zsh
./steps/zsh.sh

# How end users run it (no clone); options go after `bash -s --`
curl -fsSL https://raw.githubusercontent.com/hxb1t/hx-dev/main/setup.sh | bash -s -- --list
```

To test step selection and dispatch without installing anything, source the entry point (`main` only runs when executed) and stub out the steps:

```bash
bash -c '
  source ./setup.sh
  preflight() { echo "[preflight]"; }
  for s in "${ALL_STEPS[@]}"; do eval "step_$s() { echo \"[step_$s]\"; }"; done
  main gh zsh
'
```

## Architecture

- **curl bootstrap:** the top of `setup.sh` checks whether `lib/common.sh` is next to it. If not (it was piped from curl, or run as `bash <(curl ...)`), `bootstrap_remote` downloads the `HX_DEV_REPO`/`HX_DEV_REF` tarball from GitHub into a temp dir, runs that copy's `setup.sh` with the same args, and exits. Keep this block before any `source` and self-contained (no `lib/` helpers). It must always exit: under `curl | bash` the rest of the file is still unread on stdin. For the same reason it runs the downloaded copy with stdin from `/dev/tty`, or `/dev/null` when there is no terminal, never the inherited stdin. That makes the menu and the `sshkey`/`ghlogin` prompts work when piped.
- `setup.sh` is the entry point. It sources `lib/common.sh`, `lib/menu.sh` and `lib/versions.sh`, then sources **every** `steps/<name>.sh` listed in `ALL_STEPS` up front and dispatches by calling `step_<name>` in the same shell. Because everything shares one shell, exported state carries between steps (e.g. `DEBIAN_FRONTEND` set by `packages`, and `PATH` including proto shims so `runtimes` sees what `proto` just installed).
- `ALL_STEPS`, `STEP_DESCS` and `STEP_GROUPS` are parallel arrays: same index = same step, and array order is run order. The steps of one group must be next to each other, because the menu and `--list` print a group heading whenever the group changes. `lib/menu.sh` reads all three and writes the global `SELECTED_STEPS`. In the menu, the group rows can be selected too: space on one toggles the whole group.
- **Install prompts:** in a terminal, `main` calls `ask_install_options` (`lib/menu.sh`) after the selection and before `preflight`. It asks only about selected steps, and it overwrites the step config vars (`*_VERSION`, `GIT_FROM`, `RUNTIMES_VIA`, `PROTO_HOME`, `GO_DIR`, `NODE_DIR`, `CARGO_HOME`) in place. A var that came from the environment is not asked. `setup.sh` records those in `PRESET_VARS` *before* sourcing anything, because after sourcing the defaults have already filled them in. Without a terminal, nothing is asked. To add a prompt, put the var in that `PRESET_VARS` loop and in `ask_install_options`. A question with a fixed set of answers uses `ask_choice` (a list to pick from), never typed input. Only free-form values (install paths) are typed, with `ask_path`.
- **Versions:** each step that takes a version defines `<NAME>_VERSION_RE` next to its default. The step checks it with `check_version`, and the prompt (`ask_version`) uses the same regex, so the two never disagree. `ask_version` loads `list_versions <tool>` (`lib/versions.sh`, sourced only by `setup.sh`) into `PICK_VALUES`/`PICK_LABELS`, then runs `pick_one`. That is the same single-choice list `ask_choice` uses; it scrolls and gains type-to-filter when the list is longer than its window. Each lister prints `value<TAB>label` lines, aliases first, newest first. It may list only versions the step can really install on this machine: filter by `machine_arch`, and apply `min_version` where old releases don't work. It must use only `curl`, `git ls-remote` (not the rate-limited GitHub API) and text tools. Entries whose value fails the step's regex are dropped. If the list is empty or the fetch fails, the user types the version instead.
- The `step_` function prefix is reserved for steps: tests stub every `step_*` function (`compgen -A function step_`), so name helpers something else (e.g. `is_selected`).
- `lib/common.sh` holds shared config (`USER`, `SSH_KEY`, `ZSHRC`, `PROTO_HOME`/`PATH`) and helpers (`log`/`info`/`warn`/`die`, `have`, `clone_once`, `append_zshrc_block`, `set_zshrc_block`, `valid_install_path`/`check_install_path`, `zshrc_path`, `machine_arch`, `check_version`, `run_remote_script`, `is_wsl`/`has_systemd`/`relogin_hint`, `ubuntu_codename`, `add_apt_repo`, `apt_installed_version`/`apt_full_version`/`apt_install_version`, `enable_service`, `preflight`, `run_standalone`). It has an include guard (`HX_DEV_COMMON_LOADED`) because every step script sources it too. Run vendor installer scripts through `run_remote_script` (download to a temp file, then run), never `sh -c "$(curl ...)"` or `bash <(curl ...)`: those run an empty script and "succeed" when the download fails.
- Each step script is dual-use: sourced by `setup.sh`, or executed directly. The required shape is:
  ```bash
  set -euo pipefail
  # shellcheck source=lib/common.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
  STEP_ONLY_VAR="${STEP_ONLY_VAR:-default}"   # config used only by this step lives here
  step_<name>() { ... }
  if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    run_standalone step_<name>   # check_not_root + preflight (sudo) + the step
  fi
  ```
  Config used by more than one step goes in `lib/common.sh` instead. Step-file config is evaluated when the file is sourced, which for `setup.sh` is at startup for all steps.

## Adding or changing a step

1. Create `steps/<name>.sh` in the shape above and `chmod +x` it.
2. Add `<name>` to `ALL_STEPS`, with its description in `STEP_DESCS` and its group in `STEP_GROUPS` at the same index, in `setup.sh`. Put it next to the other steps of its group.
3. Update the numbered list, `Steps:` line, and env-override list in the `setup.sh` header comment.

Conventions every step follows:
- **Idempotent**: the whole script is documented as safe to re-run, so each step checks before acting (`have <cmd>`, `[ -d ... ]`, `grep` for an existing line) and skips work already done.
- Edit `~/.zshrc` only via `append_zshrc_block` with a unique marker line (or a guarded `sed`), never blind appends. If the block holds a value the user can change (an install path), use `set_zshrc_block` instead: it rewrites the block when the content differs. Write paths with `zshrc_path`, and validate user paths with `check_install_path` first.
- Missing prerequisites fail with `die "<thing> is not installed; run the '<step>' step first."` rather than installing another step's dependency.
- Scripts run as the normal user (root is rejected); use `sudo` only on the commands that need it.
- **Vendor apt repositories:** add them with `add_apt_repo <name> <key-url> "deb [arch=... signed-by=SIGNED_BY] <url> $(ubuntu_codename) ..."`. It adds the repo once, keeps keys in `/etc/apt/keyrings`, and runs `apt-get update` only when it adds something. Never use `apt-key` or `/etc/apt/trusted.gpg.d`. Use `ubuntu_codename`, not `lsb_release`: it also works on Ubuntu-based systems. Prefer the vendor's official repository over Ubuntu's package when the vendor has one (Podman has none, so it uses Ubuntu's).
- **apt versions:** for packages that share one version, use `apt_install_version <latest|X.Y.Z> <pkg>...`. With `latest` it keeps an installed copy; with an exact version it installs that build and holds it (`apt-mark hold`); a later `latest` releases the hold. Its version list in `lib/versions.sh` reads the same repository's `Packages` index (`apt_index_versions`/`apt_index_packages`), so the picker only offers what apt can install.
- **Services:** start them with `enable_service <unit>...`. It enables and starts them under systemd, and only warns (with WSL-specific advice) when systemd isn't running, so a step never fails because of it.
- **Not WSL-only:** the project used to be WSL-only. Use `is_wsl` and `relogin_hint` for anything WSL-specific (e.g. `wsl --shutdown` vs logging out), and never assume WSL. The `wsl-setup` name in the `~/.zshrc` markers and in `.wsl-setup-install` stays as it is: renaming them would make existing machines get duplicate blocks.
- `sshkey` (passphrase prompt) and `ghlogin` (browser/device login) are interactive and must stay last in `ALL_STEPS`.
