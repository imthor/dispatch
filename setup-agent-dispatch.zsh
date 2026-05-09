#!/bin/zsh

set -euo pipefail

CONFIG_DIR="${HOME}/.config/agent-dispatch"
CACHE_DIR="${HOME}/.cache/agent-dispatch"
HOOK_DIR="${CONFIG_DIR}/hooks"
SHELL_RC_FILE="${SHELL_RC_FILE:-${ZDOTDIR:-${HOME}}/.zshrc}"
UPDATE_SHELL_RC="${UPDATE_SHELL_RC:-1}"
TMUX_RC_FILE="${TMUX_RC_FILE:-${HOME}/.tmux.conf}"
UPDATE_TMUX_RC="${UPDATE_TMUX_RC:-1}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${HOME}/.local}"
INSTALL_ASSUME_YES="${INSTALL_ASSUME_YES:-0}"
INSTALL_INTERACTIVE="${INSTALL_INTERACTIVE:-auto}"
INSTALL_CODEX_UNSANDBOXED="${INSTALL_CODEX_UNSANDBOXED:-}"

_usage() {
  cat <<'USAGE'
usage:
  setup-agent-dispatch.zsh [options]

options:
  --install-prefix <dir>       Install binaries and completion under dir.
  --update-shell-rc            Add install bin dir to the shell rc file.
  --no-update-shell-rc         Do not edit the shell rc file.
  --update-tmux-rc             Source the tmux fragment from ~/.tmux.conf.
  --no-update-tmux-rc          Do not edit ~/.tmux.conf.
  --codex-unsandboxed          Default codex runs bypass approvals/sandbox.
  --no-codex-unsandboxed       Keep codex defaults sandboxed.
  -y, --yes                    Use defaults for unanswered prompts.
  -h, --help                   Show this help.

environment:
  INSTALL_PREFIX, UPDATE_SHELL_RC, UPDATE_TMUX_RC, INSTALL_ASSUME_YES,
  INSTALL_INTERACTIVE, INSTALL_CODEX_UNSANDBOXED
USAGE
}

while (( $# )); do
  case "${1}" in
    --install-prefix)
      (( $# >= 2 )) || { print "error: --install-prefix requires a value." >&2; exit 2; }
      INSTALL_PREFIX="${2}"
      shift 2
      ;;
    --update-shell-rc)
      UPDATE_SHELL_RC=1
      shift
      ;;
    --no-update-shell-rc)
      UPDATE_SHELL_RC=0
      shift
      ;;
    --update-tmux-rc)
      UPDATE_TMUX_RC=1
      shift
      ;;
    --no-update-tmux-rc)
      UPDATE_TMUX_RC=0
      shift
      ;;
    --codex-unsandboxed)
      INSTALL_CODEX_UNSANDBOXED=1
      shift
      ;;
    --no-codex-unsandboxed)
      INSTALL_CODEX_UNSANDBOXED=0
      shift
      ;;
    -y|--yes)
      INSTALL_ASSUME_YES=1
      shift
      ;;
    -h|--help)
      _usage
      exit 0
      ;;
    *)
      print "error: Unknown option '${1}'." >&2
      _usage >&2
      exit 2
      ;;
  esac
done

BIN_DIR="${INSTALL_PREFIX}/bin"
ZSH_FUNC_DIR="${INSTALL_PREFIX}/share/zsh/site-functions"

_is_interactive_install() {
  [[ "${INSTALL_INTERACTIVE}" == "1" ]] && return 0
  [[ "${INSTALL_INTERACTIVE}" == "0" ]] && return 1
  [[ -r /dev/tty && -w /dev/tty && "${INSTALL_ASSUME_YES}" != "1" ]]
}

_prompt_yes_no() {
  local prompt="${1}" default="${2}" answer
  if ! _is_interactive_install; then
    [[ "${default}" == "yes" ]]
    return
  fi

  while true; do
    if [[ "${default}" == "yes" ]]; then
      print -n "${prompt} [Y/n] " > /dev/tty
    else
      print -n "${prompt} [y/N] " > /dev/tty
    fi
    read -r answer < /dev/tty
    answer="${answer:l}"
    [[ -z "${answer}" ]] && answer="${default}"
    case "${answer}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) print "Please answer yes or no." > /dev/tty ;;
    esac
  done
}

if [[ -z "${INSTALL_CODEX_UNSANDBOXED}" ]]; then
  if _prompt_yes_no "Default codex runs should bypass approvals and sandboxing?" "no"; then
    INSTALL_CODEX_UNSANDBOXED=1
  else
    INSTALL_CODEX_UNSANDBOXED=0
  fi
fi

backup_file() {
  local target="${1}"
  if [[ -e "${target}" || -L "${target}" ]]; then
    local backup="${target}.bak.$(date +%Y%m%d%H%M%S).$$"
    cp -p "${target}" "${backup}"
    print "backed up ${target} -> ${backup}"
  fi
}

install_file() {
  local target="${1}" mode="${2}"
  local tmp="${target}.tmp.$$"
  backup_file "${target}"
  umask 022
  cat > "${tmp}"
  chmod "${mode}" "${tmp}"
  mv -f "${tmp}" "${target}"
  print "installed ${target}"
}

ensure_shell_path() {
  local rc_file="${1}" bin_dir="${2}"
  local quoted_bin_dir

  if [[ "${UPDATE_SHELL_RC}" != "1" ]]; then
    print "skipped shell PATH update because UPDATE_SHELL_RC=${UPDATE_SHELL_RC}"
    return 0
  fi

  if [[ "${bin_dir}" == *$'\n'* ]]; then
    print "error: INSTALL_PREFIX must not contain newlines." >&2
    return 1
  fi
  quoted_bin_dir="${(qqqq)bin_dir}"

  if [[ -f "${rc_file}" ]] && grep -Fq "${bin_dir}" "${rc_file}"; then
    print "${bin_dir} is already referenced in ${rc_file}"
    return 0
  fi

  mkdir -p "${rc_file:h}"
  backup_file "${rc_file}"
  {
    print ""
    print "# agent-dispatch"
    print -r -- "export PATH=${quoted_bin_dir}:\$PATH"
  } >> "${rc_file}"
  print "added ${bin_dir} to PATH in ${rc_file}"
}

ensure_tmux_source() {
  local rc_file="${1}" fragment="${2}"
  local source_line="source-file ${fragment}"

  if [[ "${UPDATE_TMUX_RC}" != "1" ]]; then
    print "skipped tmux source update because UPDATE_TMUX_RC=${UPDATE_TMUX_RC}"
    return 0
  fi

  if [[ -f "${rc_file}" ]] && grep -Fxq "${source_line}" "${rc_file}"; then
    print "${fragment} is already sourced in ${rc_file}"
    return 0
  fi

  mkdir -p "${rc_file:h}"
  backup_file "${rc_file}"
  {
    print ""
    print "# agent-dispatch"
    print "${source_line}"
  } >> "${rc_file}"
  print "added ${fragment} source to ${rc_file}"
}

mkdir -p "${BIN_DIR}" "${ZSH_FUNC_DIR}" "${CONFIG_DIR}" "${CACHE_DIR}/ctx" "${HOOK_DIR}"
chmod 700 "${CACHE_DIR}" "${CACHE_DIR}/ctx" "${CONFIG_DIR}" "${HOOK_DIR}"

install_file "${CONFIG_DIR}/config.example" 0644 <<'AGENT_CONFIG'
# agent-dispatch configuration

# Tmux session used for dispatched agents.
SESSION="${SESSION:-agent-dispatch}"

# Default agent type used when --type is omitted.
DEFAULT_AGENT="${DEFAULT_AGENT:-codex}"

# TTL in minutes after which status.* files are purged.
# Context files in ctx/ are intentionally never purged.
STATUS_TTL_MINS="${STATUS_TTL_MINS:-5}"

# Desktop notifications: auto, always, or off.
# auto sends notifications on macOS only. Idle notifications fire when the
# agent pane has stopped changing for AGENT_NOTIFY_IDLE_SECS while still open.
AGENT_NOTIFY="${AGENT_NOTIFY:-auto}"
AGENT_NOTIFY_CLICK="${AGENT_NOTIFY_CLICK:-focus}"
AGENT_NOTIFY_TERMINAL_APP="${AGENT_NOTIFY_TERMINAL_APP:-Terminal}"
AGENT_NOTIFY_IDLE_SECS="${AGENT_NOTIFY_IDLE_SECS:-30}"
AGENT_NOTIFY_POLL_SECS="${AGENT_NOTIFY_POLL_SECS:-2}"
AGENT_NOTIFY_ON_EXIT="${AGENT_NOTIFY_ON_EXIT:-0}"

# Tmux styles applied to dispatcher-managed agent windows.
# Set either value to an empty string to disable pane background styling.
AGENT_TMUX_WINDOW_STYLE="${AGENT_TMUX_WINDOW_STYLE:-bg=colour235}"
AGENT_TMUX_ACTIVE_WINDOW_STYLE="${AGENT_TMUX_ACTIVE_WINDOW_STYLE:-bg=colour235}"
AGENT_TMUX_STATUS_STYLE="${AGENT_TMUX_STATUS_STYLE:-bg=#2b211d,fg=#f4efe7}"
AGENT_TMUX_STATUS_LEFT_STYLE="${AGENT_TMUX_STATUS_LEFT_STYLE:-bg=#d97757,fg=#fff7ed,bold}"
AGENT_TMUX_STATUS_LEFT="${AGENT_TMUX_STATUS_LEFT:- AGENT #S }"
AGENT_TMUX_BADGE_STYLE="${AGENT_TMUX_BADGE_STYLE:-bg=#d97757,fg=#fff7ed,bold}"

# Optional per-agent tmux styles. Claude uses a warm accent inspired by the
# Claude mark; add entries here for other agent types as needed.
typeset -A AGENT_TMUX_WINDOW_STYLES
AGENT_TMUX_WINDOW_STYLES=(
  claude "bg=colour236"
)

typeset -A AGENT_TMUX_ACTIVE_WINDOW_STYLES
AGENT_TMUX_ACTIVE_WINDOW_STYLES=(
  claude "bg=colour236"
)

typeset -A AGENT_TMUX_BADGE_STYLES
AGENT_TMUX_BADGE_STYLES=(
  claude "bg=#d97757,fg=#fff7ed,bold"
)

typeset -A AGENT_CMDS
AGENT_CMDS=(
  codex "codex"
  claude "claude"
  gemini "gemini"
  opencode "opencode"
)

# Optional Docker Sandbox commands. Enable per run with `agent --docker ...`,
# or per agent by setting AGENT_DOCKER_DEFAULTS[<type>]=1 below.
typeset -A AGENT_DOCKER_CMDS
AGENT_DOCKER_CMDS=(
  codex "docker sandbox run codex"
  claude "docker sandbox run claude"
  gemini "docker sandbox run gemini"
)

typeset -A AGENT_DOCKER_DEFAULTS
# AGENT_DOCKER_DEFAULTS[codex]=1
# AGENT_DOCKER_DEFAULTS[claude]=1
# AGENT_DOCKER_DEFAULTS[gemini]=1

# Per-agent extra flags. Values are zsh (z)-split, so quoted strings are preserved.
typeset -A AGENT_FLAGS
# AGENT_FLAGS[claude]="--model claude-opus-4-7"
# AGENT_FLAGS[gemini]="--model gemini-2.5-pro"
# AGENT_FLAGS[cursor]="--headless"
AGENT_CONFIG

if [[ ! -e "${CONFIG_DIR}/config" ]]; then
  cp -p "${CONFIG_DIR}/config.example" "${CONFIG_DIR}/config"
  print "installed ${CONFIG_DIR}/config"
else
  print "kept existing ${CONFIG_DIR}/config"
fi

if [[ "${INSTALL_CODEX_UNSANDBOXED}" == "1" ]] && ! grep -Eq '^[[:space:]]*AGENT_FLAGS\[codex\]=' "${CONFIG_DIR}/config"; then
  {
    print ""
    print "# Enabled during install. This bypasses Codex approvals and sandboxing."
    print 'AGENT_FLAGS[codex]="--dangerously-bypass-approvals-and-sandbox"'
  } >> "${CONFIG_DIR}/config"
  print "enabled unsandboxed Codex default in ${CONFIG_DIR}/config"
fi

install_file "${BIN_DIR}/agent" 0755 <<'AGENT_CLI'
#!/bin/zsh

set -euo pipefail
setopt no_nomatch

CONFIG_FILE="${HOME}/.config/agent-dispatch/config"
CACHE_DIR="${HOME}/.cache/agent-dispatch"
CTX_DIR="${CACHE_DIR}/ctx"

SESSION="${SESSION:-agent-dispatch}"
DEFAULT_AGENT="${DEFAULT_AGENT:-codex}"
STATUS_TTL_MINS="${STATUS_TTL_MINS:-5}"
AGENT_NOTIFY="${AGENT_NOTIFY:-auto}"
AGENT_NOTIFY_CLICK="${AGENT_NOTIFY_CLICK:-focus}"
AGENT_NOTIFY_TERMINAL_APP="${AGENT_NOTIFY_TERMINAL_APP:-Terminal}"
AGENT_NOTIFY_IDLE_SECS="${AGENT_NOTIFY_IDLE_SECS:-30}"
AGENT_NOTIFY_POLL_SECS="${AGENT_NOTIFY_POLL_SECS:-2}"
AGENT_NOTIFY_ON_EXIT="${AGENT_NOTIFY_ON_EXIT:-0}"
AGENT_TMUX_WINDOW_STYLE="${AGENT_TMUX_WINDOW_STYLE:-bg=colour235}"
AGENT_TMUX_ACTIVE_WINDOW_STYLE="${AGENT_TMUX_ACTIVE_WINDOW_STYLE:-bg=colour235}"
AGENT_TMUX_STATUS_STYLE="${AGENT_TMUX_STATUS_STYLE:-bg=#2b211d,fg=#f4efe7}"
AGENT_TMUX_STATUS_LEFT_STYLE="${AGENT_TMUX_STATUS_LEFT_STYLE:-bg=#d97757,fg=#fff7ed,bold}"
AGENT_TMUX_STATUS_LEFT="${AGENT_TMUX_STATUS_LEFT:- AGENT #S }"
AGENT_TMUX_BADGE_STYLE="${AGENT_TMUX_BADGE_STYLE:-bg=#d97757,fg=#fff7ed,bold}"
typeset -A AGENT_TMUX_WINDOW_STYLES
typeset -A AGENT_TMUX_ACTIVE_WINDOW_STYLES
typeset -A AGENT_TMUX_BADGE_STYLES
typeset -A AGENT_CMDS
AGENT_CMDS=( codex "codex" claude "claude" gemini "gemini" opencode "opencode" )
typeset -A AGENT_DOCKER_CMDS
AGENT_DOCKER_CMDS=( codex "docker sandbox run codex" claude "docker sandbox run claude" gemini "docker sandbox run gemini" )
typeset -A AGENT_DOCKER_DEFAULTS
typeset -A AGENT_FLAGS

[[ -r "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"

_usage() {
  cat <<'USAGE'
usage:
  agent [--type <type>] [--label <label>] [--cwd <dir>] [--docker|--no-docker] [--agent-flag <flag>] [--no-agent-flags] <task...>
  agent dispatch [--type <type>] [--label <label>] [--cwd <dir>] [--docker|--no-docker] [--agent-flag <flag>] [--no-agent-flags] <task...>
  agent status
  agent history
  agent attach
  agent switch
  agent switch-popup
  agent logs [<pattern>]
  agent rerun <pattern>
  agent focus <pattern>
  agent kill <pattern>

config:
  ~/.config/agent-dispatch/config
USAGE
}

_style_session() {
  tmux set-option -t "${SESSION}" status-interval 5
  tmux set-option -t "${SESSION}" status-style "${AGENT_TMUX_STATUS_STYLE}"
  tmux set-option -t "${SESSION}" status-left-style "${AGENT_TMUX_STATUS_LEFT_STYLE}"
  tmux set-option -t "${SESSION}" status-left "${AGENT_TMUX_STATUS_LEFT}"
  tmux set-option -t "${SESSION}" status-right '#(set -- "$HOME"/.cache/agent-dispatch/status.*; [ -e "$1" ] || exit 0; printf "%s\n" "$@" | xargs cat 2>/dev/null | head -n 3 | cut -c 1-80)'
  tmux set-option -t "${SESSION}" @agent_badge_style "${AGENT_TMUX_BADGE_STYLE}"
  tmux set-option -t "${SESSION}" window-status-current-format '#[#{@agent_badge_style}] AGENT #{window_index}:#{window_name} #[default]'
}

_cleanup_status() {
  mkdir -p "${CACHE_DIR}" "${CTX_DIR}"
  find "${CACHE_DIR}" -maxdepth 1 -name 'status.*' -mmin "+${STATUS_TTL_MINS}" -delete 2>/dev/null || true
}

_auto_label() {
  local raw="${*:-agent}"
  raw="${raw:l}"
  raw="${raw//[^a-z0-9._-]/-}"
  raw="${raw##-}"
  raw="${raw%%-}"
  print -r -- "${raw[1,40]:-agent}"
}

_find_window() {
  local pattern="${1:-}"
  local -a matches

  if [[ -z "${pattern}" ]]; then
    print "error: Missing window pattern." >&2
    return 2
  fi

  matches=( ${(f)"$(tmux list-windows -t "${SESSION}" -F "#{window_index}|#{window_name}" 2>/dev/null | grep -iF -- "${pattern}" || true)"} )

  if (( ${#matches} == 0 )); then
    print "error: No window matching '${pattern}'." >&2
    return 1
  fi
  if (( ${#matches} > 1 )); then
    print "error: Ambiguous pattern '${pattern}'. Matches:" >&2
    print -l "  ${matches[@]}" >&2
    return 1
  fi
  print -r -- "${matches[1]%%|*}"
}

_run_key_for_window() {
  local win_idx="${1}"
  tmux show-option -wqv -t "${SESSION}:${win_idx}" @agent_run_key 2>/dev/null
}

_trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  print -r -- "${value}"
}

_agent_window_rows() {
  local idx name last run_key ctx_file status_file status_line
  local agent_type task_label work_dir state
  local AGENT_TYPE TASK_LABEL WORK_DIR
  local sep='|'

  tmux list-windows -t "${SESSION}" -F "#{window_index}${sep}#{window_name}${sep}#{window_last_activity}" 2>/dev/null \
    | while IFS="${sep}" read -r idx name last; do
        run_key="$(_run_key_for_window "${idx}")"
        [[ -n "${run_key}" ]] || continue

        agent_type="${name%%:*}"
        task_label="${name#*:}"
        [[ "${task_label}" != "${name}" ]] || task_label="${name}"
        work_dir=""
        state="active"

        ctx_file="${CTX_DIR}/${run_key}"
        if [[ -r "${ctx_file}" ]]; then
          AGENT_TYPE=""
          TASK_LABEL=""
          WORK_DIR=""
          source "${ctx_file}" 2>/dev/null || true
          [[ -n "${AGENT_TYPE}" ]] && agent_type="${AGENT_TYPE}"
          [[ -n "${TASK_LABEL}" ]] && task_label="${TASK_LABEL}"
          [[ -n "${WORK_DIR}" ]] && work_dir="${WORK_DIR}"
        fi

        status_file="${CACHE_DIR}/status.${run_key}"
        if [[ -r "${status_file}" ]]; then
          status_line="$(head -n 1 "${status_file}")"
          state="$(_trim "${status_line[37,46]}")"
          [[ -n "${state}" ]] || state="active"
        fi

        if [[ -z "${work_dir}" ]]; then
          work_dir="$(tmux display-message -p -t "${SESSION}:${idx}" "#{pane_current_path}" 2>/dev/null || true)"
        fi

        printf '%s\t%-10.10s\t%-8.8s\t%-33.33s\t%s\n' \
          "${idx}" "${state}" "${agent_type}" "${task_label}" "${work_dir}"
      done
}

_epoch_seconds() {
  date +%s
}

_cmd_dispatch() {
  local agent_type="${DEFAULT_AGENT}"
  local task_label=""
  local work_dir="${PWD}"
  local use_default_agent_flags=1
  local use_docker=""
  local -a extra_args runtime_agent_flags

  while (( $# )); do
    case "${1}" in
      --type|-t)
        (( $# >= 2 )) || { print "error: --type requires a value." >&2; return 2; }
        agent_type="${2}"
        shift 2
        ;;
      --label|-l)
        (( $# >= 2 )) || { print "error: --label requires a value." >&2; return 2; }
        task_label="${2}"
        shift 2
        ;;
      --cwd|-C)
        (( $# >= 2 )) || { print "error: --cwd requires a value." >&2; return 2; }
        work_dir="${2}"
        shift 2
        ;;
      --agent-flag)
        (( $# >= 2 )) || { print "error: --agent-flag requires a value." >&2; return 2; }
        runtime_agent_flags+=( "${2}" )
        shift 2
        ;;
      --docker)
        use_docker=1
        shift
        ;;
      --no-docker)
        use_docker=0
        shift
        ;;
      --no-agent-flags)
        use_default_agent_flags=0
        shift
        ;;
      --)
        shift
        extra_args+=( "$@" )
        break
        ;;
      -*)
        print "error: Unknown option '${1}'." >&2
        return 2
        ;;
      *)
        extra_args+=( "${1}" )
        shift
        ;;
    esac
  done

  if (( ${#extra_args} == 0 )); then
    print "error: Missing task arguments." >&2
    return 2
  fi
  if [[ ! -d "${work_dir}" ]]; then
    print "error: Work dir '${work_dir}' does not exist." >&2
    return 1
  fi
  if [[ -z "${AGENT_CMDS[${agent_type}]+_}" ]]; then
    print "error: Unknown agent type '${agent_type}'." >&2
    print "Available types: ${(k)AGENT_CMDS}" >&2
    return 1
  fi
  if [[ -z "${use_docker}" ]]; then
    use_docker="${AGENT_DOCKER_DEFAULTS[${agent_type}]:-0}"
  fi
  case "${use_docker:l}" in
    1|true|yes|on) use_docker=1 ;;
    0|false|no|off|"") use_docker=0 ;;
    *)
      print "error: Invalid Docker setting '${use_docker}' for agent type '${agent_type}'." >&2
      return 2
      ;;
  esac
  if [[ "${use_docker}" == "1" && -z "${AGENT_DOCKER_CMDS[${agent_type}]+_}" ]]; then
    print "error: Docker sandbox is not configured for agent type '${agent_type}'." >&2
    return 1
  fi

  [[ -n "${task_label}" ]] || task_label="$(_auto_label "${extra_args[@]}")"
  local win_name="${agent_type}:${task_label}"

  mkdir -p "${CACHE_DIR}" "${CTX_DIR}"

  local win_idx run_key runner window_style active_window_style badge_style
  if tmux has-session -t "${SESSION}" 2>/dev/null; then
    win_idx="$(tmux new-window -t "${SESSION}" -n "${win_name}" -c "${work_dir}" -P -F "#{window_index}")"
  else
    win_idx="$(tmux new-session -d -s "${SESSION}" -n "${win_name}" -c "${work_dir}" -P -F "#{window_index}")"
  fi
  _style_session
  run_key="$(_epoch_seconds).${$}.${RANDOM}"
  window_style="${AGENT_TMUX_WINDOW_STYLES[${agent_type}]:-${AGENT_TMUX_WINDOW_STYLE}}"
  active_window_style="${AGENT_TMUX_ACTIVE_WINDOW_STYLES[${agent_type}]:-${AGENT_TMUX_ACTIVE_WINDOW_STYLE}}"
  badge_style="${AGENT_TMUX_BADGE_STYLES[${agent_type}]:-${AGENT_TMUX_BADGE_STYLE}}"
  tmux set-option -w -t "${SESSION}:${win_idx}" @agent_run_key "${run_key}"
  [[ -n "${badge_style}" ]] && tmux set-option -w -t "${SESSION}:${win_idx}" @agent_badge_style "${badge_style}"
  [[ -n "${window_style}" ]] && tmux set-option -w -t "${SESSION}:${win_idx}" window-style "${window_style}"
  [[ -n "${active_window_style}" ]] && tmux set-option -w -t "${SESSION}:${win_idx}" window-active-style "${active_window_style}"

  runner="AGENT_RUN_KEY=${(q)run_key} _agent_runner ${(q)agent_type} ${(q)task_label} ${(q)work_dir} ${(q)use_default_agent_flags} ${(q)use_docker} ${(q)#runtime_agent_flags}"
  for a in "${runtime_agent_flags[@]}"; do
    runner+=" ${(q)a}"
  done
  local a
  for a in "${extra_args[@]}"; do
    runner+=" ${(q)a}"
  done

  tmux send-keys -t "${SESSION}:${win_idx}" "${runner}" Enter
  if [[ "${use_docker}" == "1" ]]; then
    print "dispatched ${agent_type} '${task_label}' in ${SESSION}:${win_idx} using Docker"
  else
    print "dispatched ${agent_type} '${task_label}' in ${SESSION}:${win_idx}"
  fi
}

_cmd_status() {
  _cleanup_status
  local -a files
  files=( "${CACHE_DIR}"/status.*(N) )
  if (( ${#files} == 0 )); then
    print "No agent status files."
    return 0
  fi
  local file
  for file in "${files[@]}"; do
    cut -c 1-160 "${file}"
  done
}

_ctx_rows() {
  local ctx_file run_key
  local AGENT_TYPE TASK_LABEL WORK_DIR USE_DEFAULT_AGENT_FLAGS
  local -a EXTRA_ARGS RUNTIME_AGENT_FLAGS

  for ctx_file in "${CTX_DIR}"/*(Nom); do
    [[ -r "${ctx_file}" ]] || continue
    run_key="${ctx_file:t}"
    AGENT_TYPE=""
    TASK_LABEL=""
    WORK_DIR=""
    USE_DEFAULT_AGENT_FLAGS=1
    EXTRA_ARGS=()
    RUNTIME_AGENT_FLAGS=()
    source "${ctx_file}" 2>/dev/null || continue
    printf '%s\t%-8.8s\t%-33.33s\t%s\n' "${run_key}" "${AGENT_TYPE:-?}" "${TASK_LABEL:-?}" "${WORK_DIR:-?}"
  done
}

_find_context() {
  local pattern="${1:-}"
  local -a matches

  if [[ -z "${pattern}" ]]; then
    print "error: Missing context pattern." >&2
    return 2
  fi

  matches=( ${(f)"$(_ctx_rows | grep -iF -- "${pattern}" || true)"} )
  if (( ${#matches} == 0 )); then
    print "error: No saved context matching '${pattern}'." >&2
    return 1
  fi
  if (( ${#matches} > 1 )); then
    print "error: Ambiguous context pattern '${pattern}'. Matches:" >&2
    print -l "  ${matches[@]}" >&2
    return 1
  fi
  print -r -- "${CTX_DIR}/${matches[1]%%$'\t'*}"
}

_cmd_history() {
  mkdir -p "${CTX_DIR}"
  local -a rows
  rows=( ${(f)"$(_ctx_rows)"} )
  if (( ${#rows} == 0 )); then
    print "No saved agent contexts."
    return 0
  fi
  printf '%s\t%s\t%s\t%s\n' "RUN_KEY" "TYPE" "LABEL" "CWD"
  print -l "${rows[@]}"
}

_cmd_switch() {
  if ! command -v fzf >/dev/null 2>&1; then
    print "error: agent switch requires fzf. Install with: brew install fzf" >&2
    return 1
  fi

  local -a rows
  rows=( ${(f)"$(_agent_window_rows)"} )
  if (( ${#rows} == 0 )); then
    print "error: No active agent windows." >&2
    return 1
  fi

  local selected win_idx
  selected="$(printf '%s\n' "${rows[@]}" \
    | fzf --delimiter=$'\t' --with-nth=2.. \
        --layout=reverse \
        --prompt='agent> ' \
        --header=$'STATE      TYPE     LABEL                             CWD')" || return 0

  win_idx="${selected%%$'\t'*}"
  [[ -n "${win_idx}" ]] || return 0
  tmux switch-client -t "${SESSION}:${win_idx}" 2>/dev/null || tmux attach-session -t "${SESSION}:${win_idx}"
}

_cmd_switch_popup() {
  local code
  set +e
  _cmd_switch
  code=$?
  set -e

  if (( code != 0 )); then
    print ""
    print "agent switch exited with status ${code}."
    print "Press Enter to close."
    read -r
  fi
  return "${code}"
}

_cmd_logs() {
  local pattern="${1:-}"
  local win_idx run_key

  if [[ -n "${pattern}" ]]; then
    win_idx="$(_find_window "${pattern}")" || return 1
  else
    win_idx="$(tmux list-windows -t "${SESSION}" -F "#{window_last_activity} #{window_index}" 2>/dev/null \
      | while read -r last idx; do
          run_key="$(_run_key_for_window "${idx}")"
          [[ -n "${run_key}" ]] && print -r -- "${last} ${idx}"
        done \
      | sort -rn | head -1 | awk '{print $2}')"
    if [[ -z "${win_idx}" ]]; then
      print "error: No active agent windows." >&2
      return 1
    fi
  fi

  tmux capture-pane -t "${SESSION}:${win_idx}" -p -S - | ${PAGER:-less}
}

_cmd_rerun() {
  local pattern="${1:-}"
  local win_idx run_key ctx_file

  if [[ -z "${pattern}" ]]; then
    print "usage: agent rerun <pattern>" >&2
    return 2
  fi

  if win_idx="$(_find_window "${pattern}" 2>/dev/null)"; then
    run_key="$(_run_key_for_window "${win_idx}")"
    if [[ -z "${run_key}" ]]; then
      print "error: Window '${pattern}' is not a dispatcher-managed agent window." >&2
      return 1
    fi
    ctx_file="${CTX_DIR}/${run_key}"
  else
    ctx_file="$(_find_context "${pattern}")" || return 1
  fi
  if [[ ! -f "${ctx_file}" ]]; then
    print "error: No saved context for '${pattern}'. Cannot rerun." >&2
    return 1
  fi

  local AGENT_TYPE TASK_LABEL WORK_DIR USE_DEFAULT_AGENT_FLAGS USE_DOCKER
  local -a EXTRA_ARGS RUNTIME_AGENT_FLAGS restored_args restored_flags dispatch_args
  local agent_type task_label saved_dir use_default_flags use_docker
  USE_DEFAULT_AGENT_FLAGS=1
  USE_DOCKER=0
  RUNTIME_AGENT_FLAGS=()
  source "${ctx_file}" || {
    print "error: Could not read context for '${pattern}'." >&2
    return 1
  }
  if [[ -z "${AGENT_TYPE}" || -z "${TASK_LABEL}" || -z "${WORK_DIR}" ]]; then
    print "error: Context for '${pattern}' is corrupt." >&2
    return 1
  fi

  agent_type="${AGENT_TYPE}"
  task_label="${TASK_LABEL}"
  saved_dir="${WORK_DIR}"
  use_default_flags="${USE_DEFAULT_AGENT_FLAGS:-1}"
  use_docker="${USE_DOCKER:-0}"
  restored_args=( "${EXTRA_ARGS[@]}" )
  restored_flags=( "${RUNTIME_AGENT_FLAGS[@]}" )

  if [[ ! -d "${saved_dir}" ]]; then
    print "error: Original work dir '${saved_dir}' no longer exists." >&2
    return 1
  fi

  dispatch_args=( --type "${agent_type}" --label "${task_label}" --cwd "${saved_dir}" )
  [[ "${use_default_flags}" == "1" ]] || dispatch_args+=( --no-agent-flags )
  [[ "${use_docker}" == "1" ]] && dispatch_args+=( --docker )
  local flag
  for flag in "${restored_flags[@]}"; do
    dispatch_args+=( --agent-flag "${flag}" )
  done
  _cmd_dispatch "${dispatch_args[@]}" "${restored_args[@]}"
}

_cmd_focus() {
  local win_idx
  win_idx="$(_find_window "${1:-}")" || return 1
  tmux switch-client -t "${SESSION}:${win_idx}" 2>/dev/null || tmux attach-session -t "${SESSION}:${win_idx}"
}

_cmd_attach() {
  if ! tmux has-session -t "${SESSION}" 2>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
      tmux display-message "No ${SESSION} session is running."
    fi
    print "error: No ${SESSION} session is running." >&2
    return 1
  fi

  tmux switch-client -t "${SESSION}" 2>/dev/null || tmux attach-session -t "${SESSION}"
}

_cmd_kill() {
  local win_idx
  win_idx="$(_find_window "${1:-}")" || return 1
  tmux kill-window -t "${SESSION}:${win_idx}"
}

cmd="${1:-}"
case "${cmd}" in
  ""|-h|--help|help)
    _usage
    ;;
  dispatch)
    shift
    _cmd_dispatch "$@"
    ;;
  status)
    shift
    _cmd_status "$@"
    ;;
  history)
    shift
    _cmd_history "$@"
    ;;
  attach)
    shift
    _cmd_attach "$@"
    ;;
  switch)
    shift
    _cmd_switch "$@"
    ;;
  switch-popup)
    shift
    _cmd_switch_popup "$@"
    ;;
  logs)
    shift
    _cmd_logs "$@"
    ;;
  rerun)
    shift
    _cmd_rerun "$@"
    ;;
  focus)
    shift
    _cmd_focus "$@"
    ;;
  kill)
    shift
    _cmd_kill "$@"
    ;;
  *)
    _cmd_dispatch "$@"
    ;;
esac
AGENT_CLI

install_file "${BIN_DIR}/_agent_runner" 0755 <<'AGENT_RUNNER'
#!/bin/zsh

set -euo pipefail
setopt no_nomatch

CONFIG_FILE="${HOME}/.config/agent-dispatch/config"
CACHE_DIR="${HOME}/.cache/agent-dispatch"
CTX_DIR="${CACHE_DIR}/ctx"
HOOK_DIR="${HOME}/.config/agent-dispatch/hooks"

SESSION="${SESSION:-agent-dispatch}"
STATUS_TTL_MINS="${STATUS_TTL_MINS:-5}"
AGENT_NOTIFY="${AGENT_NOTIFY:-auto}"
AGENT_NOTIFY_CLICK="${AGENT_NOTIFY_CLICK:-focus}"
AGENT_NOTIFY_TERMINAL_APP="${AGENT_NOTIFY_TERMINAL_APP:-Terminal}"
AGENT_NOTIFY_IDLE_SECS="${AGENT_NOTIFY_IDLE_SECS:-30}"
AGENT_NOTIFY_POLL_SECS="${AGENT_NOTIFY_POLL_SECS:-2}"
AGENT_NOTIFY_ON_EXIT="${AGENT_NOTIFY_ON_EXIT:-0}"
typeset -A AGENT_CMDS
AGENT_CMDS=( codex "codex" claude "claude" gemini "gemini" opencode "opencode" )
typeset -A AGENT_DOCKER_CMDS
AGENT_DOCKER_CMDS=( codex "docker sandbox run codex" claude "docker sandbox run claude" gemini "docker sandbox run gemini" )
typeset -A AGENT_DOCKER_DEFAULTS
typeset -A AGENT_FLAGS

[[ -r "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"

if (( $# < 6 )); then
  print "usage: _agent_runner <agent_type> <task_label> <work_dir> <use_default_flags> <use_docker> <runtime_flag_count> [runtime_flags...] [args...]" >&2
  exit 2
fi

AGENT_TYPE="${1}"
TASK_LABEL="${2}"
WORK_DIR="${3}"
USE_DEFAULT_AGENT_FLAGS="${4}"
USE_DOCKER="${5}"
RUNTIME_AGENT_FLAG_COUNT="${6}"
shift 6

if [[ "${RUNTIME_AGENT_FLAG_COUNT}" != <-> ]]; then
  print "error: runtime flag count must be numeric." >&2
  exit 2
fi
if (( $# < RUNTIME_AGENT_FLAG_COUNT )); then
  print "error: runtime flag count exceeds provided arguments." >&2
  exit 2
fi

RUNTIME_AGENT_FLAGS=()
while (( RUNTIME_AGENT_FLAG_COUNT > 0 )); do
  RUNTIME_AGENT_FLAGS+=( "${1}" )
  shift
  RUNTIME_AGENT_FLAG_COUNT=$(( RUNTIME_AGENT_FLAG_COUNT - 1 ))
done
EXTRA_ARGS=( "$@" )

if [[ -z "${AGENT_RUN_KEY:-}" ]]; then
  print "error: AGENT_RUN_KEY is not set." >&2
  exit 2
fi
if [[ ! "${AGENT_RUN_KEY}" =~ ^[[:alnum:]._-]+$ ]]; then
  print "error: AGENT_RUN_KEY contains invalid characters." >&2
  exit 2
fi
if [[ -z "${AGENT_CMDS[${AGENT_TYPE}]+_}" ]]; then
  print "error: Unknown agent type '${AGENT_TYPE}'." >&2
  exit 2
fi
case "${USE_DOCKER:l}" in
  1|true|yes|on) USE_DOCKER=1 ;;
  0|false|no|off|"") USE_DOCKER=0 ;;
  *)
    print "error: Invalid Docker setting '${USE_DOCKER}'." >&2
    exit 2
    ;;
esac
if [[ "${USE_DOCKER}" == "1" && -z "${AGENT_DOCKER_CMDS[${AGENT_TYPE}]+_}" ]]; then
  print "error: Docker sandbox is not configured for agent type '${AGENT_TYPE}'." >&2
  exit 2
fi
if [[ ! -d "${WORK_DIR}" ]]; then
  print "error: Work dir '${WORK_DIR}' does not exist." >&2
  exit 1
fi

mkdir -p "${CACHE_DIR}" "${CTX_DIR}"
chmod 700 "${CACHE_DIR}" "${CTX_DIR}"

STATUS_FILE="${CACHE_DIR}/status.${AGENT_RUN_KEY}"
CTX_FILE="${CTX_DIR}/${AGENT_RUN_KEY}"

_epoch_seconds() {
  date +%s
}

START_EPOCH="$(_epoch_seconds)"

_status_line() {
  local state="${1}" exit_code="${2:-}" duration="${3:-0}"
  local stamp
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  %-33.33s %-10s %-8s %ss %s %s\n' "${TASK_LABEL}" "${state}" "${AGENT_TYPE}" "${duration}" "${stamp}" "${WORK_DIR}" > "${STATUS_FILE}"
}

_save_context() {
  {
    typeset -p AGENT_TYPE
    typeset -p TASK_LABEL
    typeset -p WORK_DIR
    typeset -p USE_DEFAULT_AGENT_FLAGS
    typeset -p USE_DOCKER
    typeset -p RUNTIME_AGENT_FLAGS
    typeset -p EXTRA_ARGS
  } > "${CTX_FILE}"
  chmod 600 "${CTX_FILE}"
}

_notify() {
  local title="${1}" body="${2}"
  local pane="${TMUX_PANE:-}"
  local target="" click_cmd="" activate_event="" do_script_event="" execute_cmd=""

  _applescript_string() {
    local value="${1}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    print -r -- "\"${value}\""
  }

  case "${AGENT_NOTIFY:l}" in
    0|false|no|off|none|never)
      return 0
      ;;
    auto)
      [[ "$(uname -s)" == "Darwin" ]] || return 0
      ;;
    1|true|yes|on|always)
      ;;
    *)
      print "warning: Unknown AGENT_NOTIFY='${AGENT_NOTIFY}', skipping notification." >&2
      return 0
      ;;
  esac

  if [[ "${AGENT_NOTIFY_CLICK:l}" == (focus|tmux|attach) && -n "${pane}" ]]; then
    target="$(tmux display-message -p -t "${pane}" '#{session_name}:#{window_id}' 2>/dev/null || true)"
    if [[ -n "${target}" ]]; then
      click_cmd="tmux attach-session -t ${(q)target}"
      if command -v terminal-notifier >/dev/null 2>&1 && command -v osascript >/dev/null 2>&1; then
        local safe_app="$(_applescript_string "${AGENT_NOTIFY_TERMINAL_APP}")"
        local safe_cmd="$(_applescript_string "${click_cmd}")"
        activate_event="tell application ${safe_app} to activate"
        do_script_event="tell application ${safe_app} to do script ${safe_cmd}"
        execute_cmd="/usr/bin/osascript -e ${(q)activate_event} -e ${(q)do_script_event}"
        terminal-notifier \
          -title "${title}" \
          -message "${body}" \
          -group "agent-dispatch.${AGENT_RUN_KEY}" \
          -execute "${execute_cmd}" \
          >/dev/null 2>&1 || true
        return 0
      fi
    fi
  fi

  command -v osascript >/dev/null 2>&1 || return 0
  osascript - "${title}" "${body}" <<'OSASCRIPT' >/dev/null 2>&1 || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
OSASCRIPT
}

_run_done_hook() {
  local exit_code="${1}" duration="${2}"
  local hook="${HOOK_DIR}/on_done"
  [[ -x "${hook}" ]] || return 0
  AGENT_TYPE="${AGENT_TYPE}" \
  TASK_LABEL="${TASK_LABEL}" \
  WORK_DIR="${WORK_DIR}" \
  EXIT_CODE="${exit_code}" \
  DURATION_S="${duration}" \
  "${hook}" || true
}

_start_idle_notifier() {
  local pane="${TMUX_PANE:-}"
  local idle_secs="${AGENT_NOTIFY_IDLE_SECS:-0}"
  local poll_secs="${AGENT_NOTIFY_POLL_SECS:-2}"
  local parent_pid="${$}"

  [[ -n "${pane}" ]] || return 0
  [[ "${idle_secs}" == <-> ]] || return 0
  (( idle_secs > 0 )) || return 0
  [[ "${poll_secs}" == <-> ]] || poll_secs=2
  (( poll_secs > 0 )) || poll_secs=2

  (
    local last_sig sig now last_change notified
    last_sig=""
    last_change="$(_epoch_seconds)"
    notified=0

    while kill -0 "${parent_pid}" 2>/dev/null; do
      sig="$(tmux capture-pane -p -t "${pane}" -S -200 2>/dev/null | cksum 2>/dev/null || true)"
      now="$(_epoch_seconds)"

      if [[ -n "${sig}" && "${sig}" != "${last_sig}" ]]; then
        last_sig="${sig}"
        last_change="${now}"
        notified=0
      elif (( notified == 0 && now - last_change >= idle_secs )); then
        _notify "Agent ready" "${AGENT_TYPE}:${TASK_LABEL} has been idle for ${idle_secs}s"
        notified=1
      fi

      sleep "${poll_secs}"
    done
  ) >/dev/null 2>&1 &
  IDLE_NOTIFIER_PID="${!}"
}

_stop_idle_notifier() {
  [[ -n "${IDLE_NOTIFIER_PID:-}" ]] || return 0
  kill "${IDLE_NOTIFIER_PID}" >/dev/null 2>&1 || true
  wait "${IDLE_NOTIFIER_PID}" >/dev/null 2>&1 || true
}

_docker_sandbox_create_or_find() {
  local agent="${1}" workspace="${2}" output code
  output="$(docker sandbox create "${agent}" "${workspace}" 2>&1)"
  code=$?
  if (( code == 0 )); then
    print -r -- "${output}" >&2
    if [[ "${output}" =~ in\ VM\ ([^[:space:]]+) ]]; then
      print -r -- "${match[1]}"
      return 0
    fi
    print "error: Could not read Docker sandbox name from create output." >&2
    return 1
  fi
  if [[ "${output}" =~ sandbox\ with\ name\ ([^[:space:]]+)\ already\ exists ]]; then
    print -r -- "${match[1]}"
    return 0
  fi
  print -r -- "${output}" >&2
  return "${code}"
}

_sync_codex_auth_to_sandbox() {
  local sandbox="${1}" host_auth="${HOME}/.codex/auth.json"
  [[ "${AGENT_TYPE}" == "codex" ]] || return 0
  [[ -r "${host_auth}" ]] || return 0

  docker sandbox exec -i "${sandbox}" sh -lc 'umask 077; mkdir -p "${HOME}/.codex"; cat > "${HOME}/.codex/auth.json"' < "${host_auth}" >/dev/null
}

_save_context
_status_line "running" "" 0
cd "${WORK_DIR}"

if [[ "${USE_DOCKER}" == "1" ]]; then
  cmd=( ${(z)AGENT_DOCKER_CMDS[${AGENT_TYPE}]} )
else
  cmd=( ${(z)AGENT_CMDS[${AGENT_TYPE}]} )
fi
agent_flags=()
if [[ "${USE_DEFAULT_AGENT_FLAGS}" == "1" ]]; then
  agent_flags=( ${(z)AGENT_FLAGS[${AGENT_TYPE}]:-} )
fi
agent_flags+=( "${RUNTIME_AGENT_FLAGS[@]}" )

IDLE_NOTIFIER_PID=""
_start_idle_notifier

set +e
if [[ "${USE_DOCKER}" == "1" ]] && ! command -v docker >/dev/null 2>&1; then
  print "error: Docker is not installed or not on PATH." >&2
  exit_code=127
elif [[ "${USE_DOCKER}" == "1" ]]; then
  sandbox_name="$(_docker_sandbox_create_or_find "${AGENT_TYPE}" "${WORK_DIR}")"
  create_code=$?
  if (( create_code != 0 )); then
    exit_code="${create_code}"
  else
    _sync_codex_auth_to_sandbox "${sandbox_name}"
    docker sandbox exec -it --workdir "${WORK_DIR}" "${sandbox_name}" "${AGENT_TYPE}" "${agent_flags[@]}" "${EXTRA_ARGS[@]}"
    exit_code=$?
  fi
else
  "${cmd[@]}" "${agent_flags[@]}" "${EXTRA_ARGS[@]}"
  exit_code=$?
fi
set -e
_stop_idle_notifier

duration=$(( $(_epoch_seconds) - START_EPOCH ))
if (( exit_code == 0 )); then
  _status_line "done" "${exit_code}" "${duration}"
  case "${AGENT_NOTIFY_ON_EXIT:l}" in
    1|true|yes|on|always) _notify "Agent done" "${AGENT_TYPE}:${TASK_LABEL}" ;;
  esac
else
  _status_line "failed:${exit_code}" "${exit_code}" "${duration}"
  case "${AGENT_NOTIFY_ON_EXIT:l}" in
    1|true|yes|on|always) _notify "Agent failed" "${AGENT_TYPE}:${TASK_LABEL} exited ${exit_code}" ;;
  esac
fi
_run_done_hook "${exit_code}" "${duration}"
exit "${exit_code}"
AGENT_RUNNER

AGENT_BIN_QUOTED="${(q)BIN_DIR}/agent"
install_file "${CONFIG_DIR}/tmux.conf" 0644 <<TMUX_CONF
# agent-dispatch tmux status fragment.
# Source this from ~/.tmux.conf with:
#   source-file ~/.config/agent-dispatch/tmux.conf

unbind-key -q A
bind-key a display-popup -E -w 85% -h 70% "${AGENT_BIN_QUOTED} switch-popup"
bind-key A run-shell "${AGENT_BIN_QUOTED} attach"
bind-key b switch-client -l
TMUX_CONF

install_file "${HOOK_DIR}/on_done.example" 0755 <<'ON_DONE'
#!/bin/sh
# Example completion hook for agent-dispatch.
# To enable it:
#   cp ~/.config/agent-dispatch/hooks/on_done.example ~/.config/agent-dispatch/hooks/on_done

log_dir="${HOME}/.cache/agent-dispatch"
mkdir -p "${log_dir}"

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "${timestamp}" \
  "${AGENT_TYPE}" \
  "${TASK_LABEL}" \
  "${WORK_DIR}" \
  "${EXIT_CODE}" \
  "${DURATION_S}" >> "${log_dir}/history.tsv"
ON_DONE

install_file "${ZSH_FUNC_DIR}/_agent" 0644 <<'ZSH_COMPLETION'
#compdef agent

_agent_windows() {
  local session="${SESSION:-agent-dispatch}"
  tmux list-windows -t "${session}" -F "#{window_name}" 2>/dev/null
}

_agent_types() {
  local config="${HOME}/.config/agent-dispatch/config"
  if [[ -r "${config}" ]]; then
    (
      typeset -A AGENT_CMDS
      source "${config}" >/dev/null 2>&1 || true
      print -l ${(k)AGENT_CMDS}
    )
  else
    print codex
  fi
}

_agent() {
  local -a commands
  commands=(
    'dispatch:dispatch a new agent task'
    'status:show active and recent agent status'
    'history:show saved rerun contexts'
    'attach:focus the agent-dispatch tmux session'
    'switch:open an fzf picker for agent windows'
    'switch-popup:open the tmux popup switcher'
    'logs:show captured tmux pane logs'
    'rerun:rerun a saved agent context'
    'focus:focus an agent window'
    'kill:kill an agent window'
    'help:show help'
  )

  local context state line
  _arguments -C \
    '1:command:->cmds' \
    '*::arg:->args'

  case "${state}" in
    cmds)
      _describe -t commands 'agent command' commands
      ;;
    args)
      case "${words[2]}" in
        dispatch)
          _arguments \
            '--type[agent type]:type:($(_agent_types))' \
            '--label[task label]:label:' \
            '--cwd[working directory]:directory:_directories' \
            '--docker[run the selected agent through docker sandbox]' \
            '--no-docker[run the selected agent locally]' \
            '--agent-flag[extra flag passed to the selected agent]:flag:' \
            '--no-agent-flags[do not use configured AGENT_FLAGS for this run]' \
            '*:task argument:_normal'
          ;;
        --type|-t|--label|-l|--cwd|-C|--docker|--no-docker|--agent-flag|--no-agent-flags)
          _arguments \
            '--type[agent type]:type:($(_agent_types))' \
            '--label[task label]:label:' \
            '--cwd[working directory]:directory:_directories' \
            '--docker[run the selected agent through docker sandbox]' \
            '--no-docker[run the selected agent locally]' \
            '--agent-flag[extra flag passed to the selected agent]:flag:' \
            '--no-agent-flags[do not use configured AGENT_FLAGS for this run]' \
            '*:task argument:_normal'
          ;;
        logs|rerun|focus|kill)
          _arguments '1:window:($(_agent_windows))'
          ;;
      esac
      ;;
  esac
}

_agent "$@"
ZSH_COMPLETION

ensure_shell_path "${SHELL_RC_FILE}" "${BIN_DIR}"
ensure_tmux_source "${TMUX_RC_FILE}" "${CONFIG_DIR}/tmux.conf"

print ""
print "agent-dispatch setup complete."
if [[ "${UPDATE_SHELL_RC}" == "1" ]]; then
  print "${BIN_DIR} is configured in ${SHELL_RC_FILE}."
else
  print "${BIN_DIR} was not added to ${SHELL_RC_FILE}."
fi
print "For zsh completion, add this before compinit if needed:"
print "  fpath=(${ZSH_FUNC_DIR} \$fpath)"
if [[ "${UPDATE_TMUX_RC}" == "1" ]]; then
  print "${CONFIG_DIR}/tmux.conf is configured in ${TMUX_RC_FILE}."
else
  print "${CONFIG_DIR}/tmux.conf was not added to ${TMUX_RC_FILE}."
fi
