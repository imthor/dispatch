# agent-dispatch v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden and extend the tmux-based AI agent dispatcher with bug fixes, concurrent status tracking, new subcommands (`status`, `logs`, `rerun`), per-agent flags, and zsh shell completion.

**Architecture:** Logic lives in `agent` and `_agent_runner`. Status is ephemeral (TTL-based, default `STATUS_TTL_MINS=5`, configurable in `~/.config/agent-dispatch/config`). Task context (CWD, agent type, label, and original arguments) is preserved indefinitely in `~/.cache/agent-dispatch/ctx/` — a separate subdirectory excluded from TTL cleanup — to support the `rerun` command.

**Identity contract:** Every dispatched agent gets one stable generated key, `run_key`, for example `run_key="$(date +%s).${$}.${RANDOM}"`. After creating the tmux window, the dispatcher stores it on that window with `tmux set-option -w -t "${SESSION}:${win_idx}" @agent_run_key "${run_key}"`. The tmux window index is only a live tmux target and may be reused after a window closes; it must not be used as persistent identity. The tmux window name remains human-readable and may contain punctuation, so it must not be used as a filesystem key either. Files use this convention:

| File | Purpose |
|---|---|
| `~/.cache/agent-dispatch/status.${run_key}` | TTL-managed status summary |
| `~/.cache/agent-dispatch/ctx/${run_key}` | Persistent rerun context |

The dispatcher passes `AGENT_RUN_KEY="${run_key}"` into `_agent_runner`. All status, context, log, and rerun code must use that same key. Code that starts from a live window index must retrieve the key with:

```zsh
run_key="$(tmux show-option -wqv -t "${SESSION}:${win_idx}" @agent_run_key)"
```

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `~/.local/bin/agent` | Modify | Dispatcher CLI — bug fixes + new subcommands + shared `_find_window` helper |
| `~/.local/bin/_agent_runner` | Modify | Internal runner — per-agent status/context files, `AGENT_FLAGS`, osascript fix |
| `~/.local/share/zsh/site-functions/_agent` | **Create** | Zsh completion for `agent` (must be in `$fpath`, not `$PATH`) |
| `~/.config/agent-dispatch/config` | Modify | Add `AGENT_FLAGS` associative array and `STATUS_TTL_MINS` |
| `~/.config/agent-dispatch/hooks/on_done.example` | Modify | Uncomment TSV history log |
| `~/.config/agent-dispatch/tmux.conf` | Modify | Fix `xargs -r`; aggregate per-agent status files |

---

## Part 1: Critical Bug Fixes

### Fix 1: Tmux Window Targeting (Colon Bug)

**File:** `~/.local/bin/agent` — `_cmd_dispatch` function

- [ ] **Step 1: Replace tmux lines to capture the window index at creation**

Find:
```zsh
  _ensure_session
  tmux new-window -t "${SESSION}" -n "${win_name}" -c "${work_dir}"

  local runner="_agent_runner ${(q)agent_type} ${(q)task_label} ${(q)work_dir}"
  for a in "${extra_args[@]}"; do runner+=" ${(q)a}"; done

  tmux send-keys -t "${SESSION}:${win_name}" "${runner}" Enter
```

Replace with:
```zsh
  _ensure_session
  local win_idx
  win_idx="$(tmux new-window -t "${SESSION}" -n "${win_name}" -c "${work_dir}" \
             -P -F "#{window_index}")"

  local run_key="$(date +%s).${$}.${RANDOM}"
  tmux set-option -w -t "${SESSION}:${win_idx}" @agent_run_key "${run_key}"
  local runner="AGENT_RUN_KEY=${(q)run_key} _agent_runner ${(q)agent_type} ${(q)task_label} ${(q)work_dir}"
  for a in "${extra_args[@]}"; do runner+=" ${(q)a}"; done

  tmux send-keys -t "${SESSION}:${win_idx}" "${runner}" Enter
```

---

### Fix 2: Agent Type Validation + Minor Issues

**Files:** `~/.local/bin/agent` — `_cmd_dispatch`, `_auto_label` · `~/.config/agent-dispatch/tmux.conf`

- [ ] **Step 1: Add agent type validation in `_cmd_dispatch`**

After resolving the label, insert:
```zsh
  if [[ -z "${AGENT_CMDS[${agent_type}]+_}" ]]; then
    print "error: Unknown agent type '${agent_type}'." >&2
    print "Available types: ${(k)AGENT_CMDS}" >&2
    return 1
  fi
```

- [ ] **Step 2: Remove redundant double redirect in `_auto_label`**

Find:
```zsh
  &>/dev/null 2>&1
```
Replace with:
```zsh
  &>/dev/null
```

- [ ] **Step 3: Remove `xargs -r` from `tmux.conf` for macOS compatibility**

Find:
```
xargs -r
```
Replace the surrounding pipeline with an explicit empty-input guard instead of a blind `xargs -I{}` substitution. `xargs -r` means “do not run the command when stdin is empty”; `-I{}` changes batching and command construction, so it is not equivalent.

Preferred pattern:
```zsh
files=( "${HOME}"/.cache/agent-dispatch/status.*(N) )
if (( ${#files} )); then
  printf '%s\n' "${files[@]}" | xargs ...
fi
```

If this is embedded in tmux shell syntax rather than zsh, use a POSIX shell guard:
```sh
set -- "$HOME"/.cache/agent-dispatch/status.*
[ -e "$1" ] || exit 0
printf '%s\n' "$@" | xargs ...
```

---

### Fix 3: osascript Injection

**File:** `~/.local/bin/_agent_runner` — `_notify` function

- [ ] **Step 1: Replace inline osascript string interpolation with argument-based heredoc**

Find (approximate — interpolates shell vars directly into AppleScript string):
```zsh
_notify() {
  osascript -e "display notification \"${2}\" with title \"${1}\""
}
```

Replace with:
```zsh
_notify() {
  local title="${1}" body="${2}"
  osascript - "${title}" "${body}" <<'OSASCRIPT'
    on run argv
      display notification (item 2 of argv) with title (item 1 of argv)
    end run
OSASCRIPT
}
```

> Shell variables are passed as AppleScript `run` arguments, never interpolated into the script body. This prevents injection via crafted task labels (e.g., a label containing `" & do shell script "rm -rf ~"`).

---

## Part 2: Refined Infrastructure

### Task 1: Shared `_find_window` (with Ambiguity Protection)

- [ ] **Step 1: Add `_find_window` to `agent`**
```zsh
_find_window() {
  local pattern="${1}"
  local -a matches
  matches=( ${(f)"$(tmux list-windows -t "${SESSION}" -F "#{window_index}\t#{window_name}" 2>/dev/null | grep -iF -- "${pattern}")"} )

  if (( ${#matches} == 0 )); then
    print "error: No window matching '${pattern}'." >&2
    return 1
  fi
  if (( ${#matches} > 1 )); then
    print "error: Ambiguous pattern '${pattern}'. Matches:" >&2
    print -l "  ${matches[@]}" >&2
    return 1
  fi
  print -r -- "${matches[1]%%$'\t'*}"
}
```

- [ ] **Step 2: Update `_cmd_focus` and `_cmd_kill` to use `_find_window` and exit on error.**

`_find_window` returns only a live tmux window index. Any caller that needs a run key must read `@agent_run_key` from that window; callers must not parse or reuse the human-readable window name as a key.

---

### Task 2: Robust Flag Parsing

- [ ] **Step 1: Use `(z)` splitting in `_agent_runner`**

When splitting `AGENT_FLAGS` from config, use:
```zsh
_agent_flags=( ${(z)AGENT_FLAGS[${AGENT_TYPE}]} )
```
This correctly handles quoted strings within flag values.

---

### Task 3: Context Preservation for Rerun

- [ ] **Step 1: Save full context in `_agent_runner`**

Before writing status or context files, validate that the dispatcher provided a run key:
```zsh
if [[ -z "${AGENT_RUN_KEY:-}" ]]; then
  print "error: AGENT_RUN_KEY is not set." >&2
  exit 2
fi
```

Store `AGENT_TYPE`, `TASK_LABEL`, `WORK_DIR`, and `EXTRA_ARGS` in a dedicated subdirectory. Use zsh's own `typeset -p` serialization so argument boundaries, spaces, quotes, and newlines survive round trips:
```zsh
local _ctx_dir="${HOME}/.cache/agent-dispatch/ctx"
mkdir -p "${_ctx_dir}"
{
  typeset -p AGENT_TYPE
  typeset -p TASK_LABEL
  typeset -p WORK_DIR
  typeset -p EXTRA_ARGS
} > "${_ctx_dir}/${AGENT_RUN_KEY}"
chmod 600 "${_ctx_dir}/${AGENT_RUN_KEY}"
```

Restore with:
```zsh
local AGENT_TYPE TASK_LABEL WORK_DIR
local -a EXTRA_ARGS restored_args
source "${ctx_file}" || return 1
agent_type="${AGENT_TYPE}"
task_label="${TASK_LABEL}"
saved_dir="${WORK_DIR}"
restored_args=( "${EXTRA_ARGS[@]}" )
```

- [ ] **Step 2: Exclude `ctx/` from TTL cleanup**

The TTL cleanup logic must target only `~/.cache/agent-dispatch/status.*` files, not `~/.cache/agent-dispatch/ctx/`. Verify the cleanup `find` command uses a path or name pattern that excludes the `ctx/` subdirectory — for example:
```zsh
find "${HOME}/.cache/agent-dispatch" -maxdepth 1 -name 'status.*' \
  -mmin "+${STATUS_TTL_MINS}" -delete
```

---

## Part 3: New Subcommands & UX

### Task 4: `agent status` (Truncated)

- [ ] **Step 1: Implement `_cmd_status` in `agent`.**
Read only `~/.cache/agent-dispatch/status.*` files. Use `printf '  %-33.33s ...'` to ensure display names are truncated at 33 chars, maintaining column alignment. The display name should come from the status file content or tmux metadata, not from the status filename.

---

### Task 5: `agent logs [<pattern>]`

- [ ] **Step 1: Implement `_cmd_logs` in `agent`.**

UX: `agent logs [<pattern>]`
- With no argument: target the most-recently-active dispatcher-managed agent window, not any arbitrary tmux window.
- With a pattern: resolve via `_find_window`; exit on ambiguity.

```zsh
_cmd_logs() {
  local pattern="${1:-}"
  local win_idx

  if [[ -n "${pattern}" ]]; then
    win_idx="$(_find_window "${pattern}")" || return 1
  else
    win_idx="$(tmux list-windows -t "${SESSION}" -F "#{window_last_activity} #{window_index}" \
               2>/dev/null \
               | while read -r last idx; do
                   run_key="$(tmux show-option -wqv -t "${SESSION}:${idx}" @agent_run_key 2>/dev/null)"
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
```

---

### Task 6: `agent rerun <pattern>` (Full Restoration)

- [ ] **Step 1: Implement `_cmd_rerun` in `agent`.**

Read context, validate CWD still exists, restore the original agent type, label, and arguments, then re-dispatch. `_cmd_dispatch` must support `--cwd <dir>` and `--label <label>` as dispatcher options before the task arguments. If it does not yet support those options, add them before implementing `rerun`.
```zsh
_cmd_rerun() {
  local pattern="${1:-}"
  local win_idx run_key ctx_file

  if [[ -z "${pattern}" ]]; then
    print "usage: agent rerun <pattern>" >&2
    return 2
  fi

  win_idx="$(_find_window "${pattern}")" || return 1
  run_key="$(tmux show-option -wqv -t "${SESSION}:${win_idx}" @agent_run_key 2>/dev/null)"
  if [[ -z "${run_key}" ]]; then
    print "error: Window '${pattern}' is not a dispatcher-managed agent window." >&2
    return 1
  fi
  ctx_file="${HOME}/.cache/agent-dispatch/ctx/${run_key}"
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
```

---

### Task 7: Status Bar Safety

- [ ] **Step 1: Update `tmux.conf` status-right.**
Aggregate `status.*` files but use `head -n 3` and `cut -c 1-80` to prevent overflowing the tmux bar.

---

### Task 8: Shell Completion

- [ ] **Step 1: Create `~/.local/share/zsh/site-functions/_agent` zsh completion file.**

> **Important:** The file must live in a `$fpath` directory, not `$PATH`. Add `~/.local/share/zsh/site-functions` to `fpath` in `.zshrc` before `compinit` if not already present:
> ```zsh
> fpath=(~/.local/share/zsh/site-functions $fpath)
> ```

Include subcommand completion and live window name completion via `tmux list-windows`.

---

## Config Additions

**File:** `~/.config/agent-dispatch/config`

Add the following:
```zsh
# TTL (in minutes) after which status.* files are purged. Context files in ctx/ are never purged.
STATUS_TTL_MINS=5

# Per-agent extra flags. Values are (z)-split, so quoted strings are preserved.
typeset -A AGENT_FLAGS
# AGENT_FLAGS[claude]="--model claude-opus-4-7"
# AGENT_FLAGS[cursor]="--headless"
```

---

## TSV History Log Schema

**File:** `~/.config/agent-dispatch/hooks/on_done.example`

Uncomment and document the TSV log. Columns (tab-separated):

| Column | Value |
|---|---|
| `timestamp` | ISO-8601 UTC, e.g. `2026-05-09T14:23:00Z` |
| `agent_type` | e.g. `claude`, `cursor` |
| `task_label` | human-readable label passed at dispatch |
| `work_dir` | absolute path of working directory |
| `exit_code` | numeric exit code from the agent process |
| `duration_s` | wall-clock seconds from dispatch to exit |

Example row:
```
2026-05-09T14:23:00Z	claude	fix-auth-bug	/home/user/myapp	0	42
```
