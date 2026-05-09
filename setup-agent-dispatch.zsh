#!/bin/zsh

set -euo pipefail

INSTALL_PREFIX="${INSTALL_PREFIX:-${HOME}/.local}"
BIN_DIR="${INSTALL_PREFIX}/bin"
ZSH_FUNC_DIR="${INSTALL_PREFIX}/share/zsh/site-functions"
CONFIG_DIR="${HOME}/.config/agent-dispatch"
CACHE_DIR="${HOME}/.cache/agent-dispatch"
HOOK_DIR="${CONFIG_DIR}/hooks"
SHELL_RC_FILE="${SHELL_RC_FILE:-${ZDOTDIR:-${HOME}}/.zshrc}"
UPDATE_SHELL_RC="${UPDATE_SHELL_RC:-1}"
TMUX_RC_FILE="${TMUX_RC_FILE:-${HOME}/.tmux.conf}"
UPDATE_TMUX_RC="${UPDATE_TMUX_RC:-1}"

backup_file() {
  local target="${1}"
  if [[ -e "${target}" || -L "${target}" ]]; then
    local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${target}" "${backup}"
    print "backed up ${target} -> ${backup}"
  fi
}

install_file() {
  local target="${1}" mode="${2}"
  backup_file "${target}"
  umask 022
  cat > "${target}"
  chmod "${mode}" "${target}"
  print "installed ${target}"
}

ensure_shell_path() {
  local rc_file="${1}" bin_dir="${2}"

  if [[ "${UPDATE_SHELL_RC}" != "1" ]]; then
    print "skipped shell PATH update because UPDATE_SHELL_RC=${UPDATE_SHELL_RC}"
    return 0
  fi

  if [[ -f "${rc_file}" ]] && grep -Fq "${bin_dir}" "${rc_file}"; then
    print "${bin_dir} is already referenced in ${rc_file}"
    return 0
  fi

  mkdir -p "${rc_file:h}"
  backup_file "${rc_file}"
  {
    print ""
    print "# agent-dispatch"
    print "export PATH=\"${bin_dir}:\$PATH\""
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
chmod 700 "${CACHE_DIR}" "${CACHE_DIR}/ctx"

install_file "${CONFIG_DIR}/config" 0644 <<'AGENT_CONFIG'
# agent-dispatch configuration

# Tmux session used for dispatched agents.
SESSION="${SESSION:-agent-dispatch}"

# Default agent type used when --type is omitted.
DEFAULT_AGENT="${DEFAULT_AGENT:-codex}"

# TTL in minutes after which status.* files are purged.
# Context files in ctx/ are intentionally never purged.
STATUS_TTL_MINS="${STATUS_TTL_MINS:-5}"

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
)

# Per-agent extra flags. Values are zsh (z)-split, so quoted strings are preserved.
typeset -A AGENT_FLAGS
# AGENT_FLAGS[codex]="--model gpt-5.3-codex"
# AGENT_FLAGS[claude]="--model claude-opus-4-7"
# AGENT_FLAGS[cursor]="--headless"
AGENT_CONFIG

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
AGENT_CMDS=( codex "codex" )
typeset -A AGENT_FLAGS

[[ -r "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"

_usage() {
  cat <<'USAGE'
usage:
  agent [--type <type>] [--label <label>] [--cwd <dir>] <task...>
  agent dispatch [--type <type>] [--label <label>] [--cwd <dir>] <task...>
  agent status
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

  tmux list-windows -t "${SESSION}" -F "#{window_index}|#{window_name}|#{window_last_activity}" 2>/dev/null \
    | while IFS='|' read -r idx name last; do
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
  local -a extra_args

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

  runner="AGENT_RUN_KEY=${(q)run_key} _agent_runner ${(q)agent_type} ${(q)task_label} ${(q)work_dir}"
  local a
  for a in "${extra_args[@]}"; do
    runner+=" ${(q)a}"
  done

  tmux send-keys -t "${SESSION}:${win_idx}" "${runner}" Enter
  print "dispatched ${agent_type} '${task_label}' in ${SESSION}:${win_idx}"
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

  win_idx="$(_find_window "${pattern}")" || return 1
  run_key="$(_run_key_for_window "${win_idx}")"
  if [[ -z "${run_key}" ]]; then
    print "error: Window '${pattern}' is not a dispatcher-managed agent window." >&2
    return 1
  fi

  ctx_file="${CTX_DIR}/${run_key}"
  if [[ ! -f "${ctx_file}" ]]; then
    print "error: No saved context for '${pattern}'. Cannot rerun." >&2
    return 1
  fi

  local AGENT_TYPE TASK_LABEL WORK_DIR
  local -a EXTRA_ARGS restored_args
  local agent_type task_label saved_dir
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
  restored_args=( "${EXTRA_ARGS[@]}" )

  if [[ ! -d "${saved_dir}" ]]; then
    print "error: Original work dir '${saved_dir}' no longer exists." >&2
    return 1
  fi

  _cmd_dispatch --type "${agent_type}" --label "${task_label}" --cwd "${saved_dir}" "${restored_args[@]}"
}

_cmd_focus() {
  local win_idx
  win_idx="$(_find_window "${1:-}")" || return 1
  tmux switch-client -t "${SESSION}:${win_idx}" 2>/dev/null || tmux attach-session -t "${SESSION}:${win_idx}"
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
typeset -A AGENT_CMDS
AGENT_CMDS=( codex "codex" )
typeset -A AGENT_FLAGS

[[ -r "${CONFIG_FILE}" ]] && source "${CONFIG_FILE}"

if (( $# < 3 )); then
  print "usage: _agent_runner <agent_type> <task_label> <work_dir> [args...]" >&2
  exit 2
fi

AGENT_TYPE="${1}"
TASK_LABEL="${2}"
WORK_DIR="${3}"
shift 3
EXTRA_ARGS=( "$@" )

if [[ -z "${AGENT_RUN_KEY:-}" ]]; then
  print "error: AGENT_RUN_KEY is not set." >&2
  exit 2
fi
if [[ -z "${AGENT_CMDS[${AGENT_TYPE}]+_}" ]]; then
  print "error: Unknown agent type '${AGENT_TYPE}'." >&2
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
    typeset -p EXTRA_ARGS
  } > "${CTX_FILE}"
  chmod 600 "${CTX_FILE}"
}

_notify() {
  local title="${1}" body="${2}"
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

_save_context
_status_line "running" "" 0
cd "${WORK_DIR}"

cmd=( ${(z)AGENT_CMDS[${AGENT_TYPE}]} )
agent_flags=( ${(z)AGENT_FLAGS[${AGENT_TYPE}]:-} )

set +e
"${cmd[@]}" "${agent_flags[@]}" "${EXTRA_ARGS[@]}"
exit_code=$?
set -e

duration=$(( $(_epoch_seconds) - START_EPOCH ))
if (( exit_code == 0 )); then
  _status_line "done" "${exit_code}" "${duration}"
  _notify "Agent done" "${AGENT_TYPE}:${TASK_LABEL}"
else
  _status_line "failed:${exit_code}" "${exit_code}" "${duration}"
  _notify "Agent failed" "${AGENT_TYPE}:${TASK_LABEL} exited ${exit_code}"
fi
_run_done_hook "${exit_code}" "${duration}"
exit "${exit_code}"
AGENT_RUNNER

install_file "${CONFIG_DIR}/tmux.conf" 0644 <<'TMUX_CONF'
# agent-dispatch tmux status fragment.
# Source this from ~/.tmux.conf with:
#   source-file ~/.config/agent-dispatch/tmux.conf

unbind-key -q A
bind-key a display-popup -E -w 85% -h 70% "$HOME/.local/bin/agent switch-popup"
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
      source "${config}" >/dev/null 2>&1
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
print "${BIN_DIR} is configured in ${SHELL_RC_FILE}."
print "For zsh completion, add this before compinit if needed:"
print "  fpath=(${ZSH_FUNC_DIR} \$fpath)"
print "${CONFIG_DIR}/tmux.conf is configured in ${TMUX_RC_FILE}."
