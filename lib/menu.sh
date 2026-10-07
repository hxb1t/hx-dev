# shellcheck shell=bash
#
# lib/menu.sh - interactive checkbox menu and install prompts for setup.sh.
# Meant to be sourced, not executed. Reads ALL_STEPS / STEP_DESCS / STEP_GROUPS
# and fills SELECTED_STEPS; ask_install_options sets the install method, paths
# and versions (the step config vars listed in PRESET_VARS in setup.sh).

# Interactive checkbox menu, with the steps listed under their group. Fills
# SELECTED_STEPS (in canonical order). A group's own row toggles the group.
#   up/down or j/k  move      space  toggle      a  all/none
#   enter           confirm   q      quit
select_steps() {
  local n=${#ALL_STEPS[@]} cursor=0 i j r key rest on mark prev="" picked
  local -a checked=() row_step=() row_is_group=()
  for ((i = 0; i < n; i++)); do
    checked[i]=0                                      # nothing pre-selected
    if [ "${STEP_GROUPS[i]}" != "$prev" ]; then       # a group row, then its steps
      prev="${STEP_GROUPS[i]}"
      row_step+=("$i"); row_is_group+=(1)
    fi
    row_step+=("$i"); row_is_group+=(0)
  done
  local rows=${#row_step[@]}

  printf '\033[?25l'                                  # hide cursor
  trap 'printf "\033[?25h"' EXIT
  trap 'printf "\033[?25h\n"; exit 130' INT TERM

  printf '\n\033[1mSelect the steps to run\033[0m\n'
  printf '  ↑/↓ move   space toggle   a all/none   enter confirm   q quit\n'
  printf '  space on a group name toggles the whole group\n\n'

  while true; do
    picked=0
    for ((i = 0; i < n; i++)); do picked=$(( picked + checked[i] )); done

    for ((r = 0; r < rows; r++)); do
      i=${row_step[r]}
      if [ "${row_is_group[r]}" -eq 1 ]; then
        group_counts "$i"                             # sets GROUP_ON / GROUP_SIZE
        if [ "$GROUP_ON" -eq 0 ]; then mark="[ ]"
        elif [ "$GROUP_ON" -eq "$GROUP_SIZE" ]; then mark="[x]"
        else mark="[-]"; fi
        if [ "$r" -eq "$cursor" ]; then
          printf '\033[K \033[1;36m>\033[0m %s \033[1;4m%s\033[0m\n' "$mark" "${STEP_GROUPS[i]}"
        else
          printf '\033[K   %s \033[1;4m%s\033[0m\n' "$mark" "${STEP_GROUPS[i]}"
        fi
      else
        if [ "${checked[i]}" -eq 1 ]; then mark="[x]"; else mark="[ ]"; fi
        if [ "$r" -eq "$cursor" ]; then
          printf '\033[K \033[1;36m>\033[0m     %s \033[1m%-10s\033[0m %s\n' \
            "$mark" "${ALL_STEPS[i]}" "${STEP_DESCS[i]}"
        else
          printf '\033[K       %s %-10s %s\n' \
            "$mark" "${ALL_STEPS[i]}" "${STEP_DESCS[i]}"
        fi
      fi
    done
    printf '\033[K\n\033[K  \033[2m%d of %d steps selected\033[0m\n' "$picked" "$n"

    key=""
    IFS= read -rsn1 key || key="q"                    # EOF behaves like quit
    if [ "$key" = $'\x1b' ]; then                     # arrow keys: ESC [ A/B
      rest=""
      IFS= read -rsn2 -t 0.1 rest || true
      key+="$rest"
    fi

    case "$key" in
      $'\x1b[A'|k) cursor=$(( (cursor - 1 + rows) % rows )) ;;
      $'\x1b[B'|j) cursor=$(( (cursor + 1) % rows )) ;;
      ' ')
        i=${row_step[cursor]}
        if [ "${row_is_group[cursor]}" -eq 1 ]; then  # all on, unless all are on
          group_counts "$i"
          on=$(( GROUP_ON < GROUP_SIZE ? 1 : 0 ))
          for ((j = 0; j < n; j++)); do
            if [ "${STEP_GROUPS[j]}" = "${STEP_GROUPS[i]}" ]; then checked[j]=$on; fi
          done
        else
          checked[i]=$(( 1 - checked[i] ))
        fi
        ;;
      a)
        on=$(( picked < n ? 1 : 0 ))
        for ((i = 0; i < n; i++)); do checked[i]=$on; done
        ;;
      '')          break ;;                           # enter
      q)           printf '\033[?25h\nAborted.\n'; exit 0 ;;
    esac

    printf '\033[%dA' $(( rows + 2 ))                 # redraw in place
  done

  printf '\033[?25h'
  trap - INT TERM

  SELECTED_STEPS=()
  for ((i = 0; i < n; i++)); do
    if [ "${checked[i]}" -eq 1 ]; then SELECTED_STEPS+=("${ALL_STEPS[i]}"); fi
  done
}

# For the group of step $1, set GROUP_SIZE (its steps) and GROUP_ON (how many
# of them are checked). Reads select_steps' checked array: bash locals are
# visible to the functions a function calls.
group_counts() {
  local j
  GROUP_ON=0
  GROUP_SIZE=0
  for ((j = 0; j < ${#ALL_STEPS[@]}; j++)); do
    if [ "${STEP_GROUPS[j]}" = "${STEP_GROUPS[$1]}" ]; then
      GROUP_SIZE=$(( GROUP_SIZE + 1 ))
      GROUP_ON=$(( GROUP_ON + checked[j] ))
    fi
  done
}

# Ask how and where to install, for the selected steps only, in run order.
# Settings that came from the environment (PRESET_VARS, filled by setup.sh)
# are not asked.
ask_install_options() {
  if is_selected git; then
    ask_choice GIT_FROM "Install git" \
      ppa    "newest git       from the official git-core PPA" \
      ubuntu "Ubuntu's git     the version your Ubuntu release ships"
  fi
  if is_selected claude; then
    ask_version CLAUDE_VERSION "Claude Code" claude "$CLAUDE_VERSION_RE" "stable, latest or e.g. 1.0.58"
  fi
  if is_selected gh; then
    ask_version GH_VERSION "GitHub CLI" gh "$GH_VERSION_RE" "latest or e.g. 2.63.0"
  fi

  if is_selected proto; then
    ask_version PROTO_VERSION proto proto "$PROTO_VERSION_RE" "latest or e.g. 0.45.0"
    if ! have proto && ! is_preset PROTO_HOME; then
      ask_path PROTO_HOME "proto install path"
    fi
  fi

  if is_selected runtimes; then
    ask_choice RUNTIMES_VIA "Install Go and Node" \
      proto  "with proto       pinned globally; switch versions any time with proto" \
      direct "direct download  official releases, unpacked into a folder you choose"
    ask_version NODE_VERSION Node node "$NODE_VERSION_RE" "lts, latest, 22 or 22.11.0"
    ask_version GO_VERSION Go go "$GO_VERSION_RE" "latest, 1.23 or 1.23.4"
    if [ "$RUNTIMES_VIA" = direct ]; then
      is_preset GO_DIR   || ask_path GO_DIR "Go install path"
      is_preset NODE_DIR || ask_path NODE_DIR "Node install path"
    fi
  fi
  if is_selected java; then
    ask_version JAVA_VERSION Java java "$JAVA_VERSION_RE" "lts or e.g. 21"
  fi
  if is_selected rust; then
    ask_version RUST_VERSION Rust rust "$RUST_VERSION_RE" "stable, beta, nightly or e.g. 1.80.0"
    if [ ! -x "$CARGO_HOME/bin/rustup" ] && ! is_preset CARGO_HOME; then
      ask_path CARGO_HOME "Rust (cargo) install path"
    fi
  fi

  if is_selected docker; then
    ask_version DOCKER_VERSION Docker docker "$DOCKER_VERSION_RE" "latest or e.g. 27.3.1"
  fi
  if is_selected postgres; then
    ask_version POSTGRES_VERSION PostgreSQL postgres "$POSTGRES_VERSION_RE" "latest or e.g. 17"
  fi
  if is_selected redis; then
    ask_version REDIS_VERSION Redis redis "$REDIS_VERSION_RE" "latest or e.g. 7.4.1"
  fi
}

# Print the heading once, before the first question.
ask_header() {
  if [ -z "${ASKED_HEADER:-}" ]; then
    printf '\n\033[1mInstall options\033[0m for the selected steps\n'
    ASKED_HEADER=1
  fi
}

# Ask the user to choose one of a fixed set of options and store the value in
# the variable named $1, unless that variable came from the environment.
#   ask_choice VAR "Title" value "label" [value "label" ...]
ask_choice() {
  local var="$1" title="$2"
  shift 2
  is_preset "$var" && return 0
  ask_header
  PICK_VALUES=()
  PICK_LABELS=()
  while [ "$#" -ge 2 ]; do
    PICK_VALUES+=("$1")
    PICK_LABELS+=("$2")
    shift 2
  done
  if pick_one "$title" "${!var}"; then
    printf -v "$var" '%s' "$PICKED"
  fi
}

# Ask which version of a tool to install and store it in the variable named $1,
# unless that variable came from the environment.
#   ask_version VAR "Name" tool REGEX "typed examples"
# Shows a picker of every installable version (lib/versions.sh). If the list
# cannot be fetched, the version is typed instead; enter keeps the current
# value either way. Only values matching REGEX (the step's own check) are used.
ask_version() {
  local var="$1" name="$2" tool="$3" re="$4" hint="$5" ans
  is_preset "$var" && return 0
  ask_header

  if load_versions "$name" "$tool" "$re"; then
    if pick_one "$name version" "${!var}"; then
      printf -v "$var" '%s' "$PICKED"
    fi
    return 0
  fi

  printf '  Could not fetch the list of %s versions; type one instead.\n' "$name"
  while true; do
    ans=""
    read -rp "$name version ($hint) [${!var}]: " ans || { printf '\n'; return 0; }
    [ -n "$ans" ] || return 0
    if [[ "$ans" =~ $re ]]; then
      printf -v "$var" '%s' "$ans"
      return 0
    fi
    printf '  Not a version this accepts; see the examples.\n'
  done
}

# Fill PICK_VALUES / PICK_LABELS with the versions of tool $2 (named $1 in
# messages) whose value matches regex $3. Fails if there are none.
load_versions() {
  local name="$1" tool="$2" re="$3" value label
  PICK_VALUES=()
  PICK_LABELS=()
  printf '\033[K  fetching the %s versions...\r' "$name"
  while IFS=$'\t' read -r value label; do
    if [[ "$value" =~ $re ]]; then
      PICK_VALUES+=("$value")
      PICK_LABELS+=("$label")
    fi
  done < <(list_versions "$tool" 2>/dev/null || true)
  printf '\033[K'
  [ "${#PICK_VALUES[@]}" -gt 0 ]
}

# Single-choice picker over PICK_VALUES / PICK_LABELS. Sets PICKED and prints
# the choice; returns 1 when the user keeps the current value ($2) with esc.
# A list longer than the window scrolls and can be filtered by typing: the
# filter matches the start of any word in a label, so "22.1" finds 22.1x.x
# (not 22.22.1) and "jod" an LTS name. A short list is shown whole, no filter.
#   up/down (j/k in a short list)  move     pgup/pgdn  page   home/end
#   letters, digits  filter        backspace  unfilter
#   enter    select                esc        keep current
pick_one() {
  local title="$1" current="$2"
  local n=${#PICK_VALUES[@]} rows cols height hint i r m=0 cursor=0 top=0
  local filter="" refilter=1 first=1 key rest c result="" filterable=1
  local -a match=() lower=()

  cols="$(tput cols 2>/dev/null || echo 80)"
  rows="$(( $(tput lines 2>/dev/null || echo 24) - 6 ))"
  if [ "$rows" -gt 10 ]; then rows=10; fi
  if [ "$rows" -lt 3 ]; then rows=3; fi
  if [ "$n" -le "$rows" ]; then rows=$n; filterable=0; fi
  height=$(( rows + 2 + filterable ))
  if [ "$filterable" -eq 1 ]; then
    hint="  ↑/↓ PgUp/PgDn move · type to filter · enter select · esc keep $current"
  else
    hint="  ↑/↓ move · enter select · esc keep $current"
  fi
  hint="${hint:0:cols-1}"
  for ((i = 0; i < n; i++)); do lower[i]="${PICK_LABELS[i],,}"; done

  printf '\033[?25l'                                  # hide cursor
  trap 'printf "\033[?25h\n"; exit 130' INT TERM

  while true; do
    if [ "$refilter" -eq 1 ]; then
      match=()
      for ((i = 0; i < n; i++)); do
        if [ -z "$filter" ] || [[ " ${lower[i]}" == *" $filter"* ]]; then
          match+=("$i")
        fi
      done
      m=${#match[@]}
      cursor=0
      if [ "$first" -eq 1 ]; then                     # start on the current value
        for ((i = 0; i < m; i++)); do
          if [ "${PICK_VALUES[match[i]]}" = "$current" ]; then cursor=$i; break; fi
        done
        first=0
      fi
      refilter=0
    fi

    if [ "$cursor" -ge "$m" ]; then cursor=$(( m > 0 ? m - 1 : 0 )); fi
    if [ "$cursor" -lt 0 ]; then cursor=0; fi
    if [ "$cursor" -lt "$top" ]; then top=$cursor; fi
    if [ "$cursor" -ge $(( top + rows )) ]; then top=$(( cursor - rows + 1 )); fi
    if [ "$top" -gt $(( m > rows ? m - rows : 0 )) ]; then top=$(( m > rows ? m - rows : 0 )); fi

    printf '\033[K\033[1m%s\033[0m\n' "$title"
    printf '\033[K\033[2m%s\033[0m\n' "$hint"
    if [ "$filterable" -eq 0 ]; then
      :
    elif [ "$m" -eq 0 ]; then
      printf '\033[K  filter: %s_   no match\n' "$filter"
    else
      printf '\033[K  filter: %s_   %d of %d\n' "$filter" "$m" "$n"
    fi
    for ((r = 0; r < rows; r++)); do
      i=$(( top + r ))
      if [ "$i" -lt "$m" ]; then
        c="${PICK_LABELS[match[i]]}"
        c="${c:0:cols-4}"
        if [ "$i" -eq "$cursor" ]; then
          printf '\033[K \033[1;36m>\033[0m \033[1m%s\033[0m\n' "$c"
        else
          printf '\033[K   %s\n' "$c"
        fi
      else
        printf '\033[K\n'
      fi
    done

    key=""
    IFS= read -rsn1 key || key=$'\x1b'                # EOF keeps the current value
    case "$key" in
      $'\x1b')
        rest=""
        IFS= read -rsn1 -t 0.05 rest || true
        if [ -z "$rest" ]; then
          result=keep                                 # esc on its own
        else
          c=""
          IFS= read -rsn1 -t 0.05 c || true
          rest+="$c"
          case "$rest" in                             # PgUp/PgDn/Home/End end in "~"
            '[1'|'[4'|'[5'|'[6'|'[7'|'[8') IFS= read -rsn1 -t 0.05 c || true ;;
          esac
          case "$rest" in
            '[A'|'OA')                cursor=$(( cursor - 1 )) ;;
            '[B'|'OB')                cursor=$(( cursor + 1 )) ;;
            '[5')                     cursor=$(( cursor - rows )) ;;
            '[6')                     cursor=$(( cursor + rows )) ;;
            '[H'|'OH'|'[1'|'[7')      cursor=0 ;;
            '[F'|'OF'|'[4'|'[8')      cursor=$(( m - 1 )) ;;
          esac
        fi
        ;;
      '')
        if [ "$m" -gt 0 ]; then result=pick; fi       # enter
        ;;
      $'\x7f'|$'\b')
        if [ -n "$filter" ]; then filter="${filter%?}"; refilter=1; fi
        ;;
      *)
        if [ "$filterable" -eq 0 ]; then
          case "$key" in
            k) cursor=$(( cursor - 1 )) ;;
            j) cursor=$(( cursor + 1 )) ;;
          esac
        elif [[ "$key" == [[:print:]] ]]; then
          filter+="${key,,}"; refilter=1
        fi
        ;;
    esac

    printf '\033[%dA' "$height"                       # back to the top of the list
    if [ -n "$result" ]; then break; fi
  done

  printf '\033[J\033[?25h'                            # clear the list, show cursor
  trap - INT TERM
  if [ "$result" = pick ]; then
    PICKED="${PICK_VALUES[match[cursor]]}"
    printf '%s: %s\n' "$title" "$PICKED"
    return 0
  fi
  printf '%s: %s (kept)\n' "$title" "$current"
  return 1
}

# Ask for a path and store it in the variable named $1; enter keeps its value.
ask_path() {
  local var="$1" label="$2" ans shown="${!1}"
  ask_header
  # shellcheck disable=SC2088  # show the default as "~/..." on purpose
  case "$shown" in
    "$HOME"/*) shown="~/${shown#"$HOME"/}" ;;
  esac
  while true; do
    ans=""
    read -erp "$label [$shown]: " ans || { printf '\n'; return 0; }
    [ -n "$ans" ] || return 0
    # shellcheck disable=SC2088  # match a typed "~", then expand it by hand
    case "$ans" in
      '~')   ans="$HOME" ;;
      '~/'*) ans="$HOME/${ans#'~/'}" ;;
    esac
    ans="${ans%/}"
    if valid_install_path "$ans"; then
      printf -v "$var" '%s' "$ans"
      return 0
    fi
    printf '  Use an absolute path (or ~/...) without quotes, $, ` or \\.\n'
  done
}

is_selected() {
  local s
  for s in "${SELECTED_STEPS[@]}"; do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}

is_preset() {
  case " ${PRESET_VARS:-} " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}
