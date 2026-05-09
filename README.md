# agent-dispatch

`agent-dispatch` is a small tmux-based dispatcher for running AI agent tasks in the background.

It installs an `agent` command that opens each task in its own tmux window, keeps lightweight status files, lets you inspect logs, and can rerun a previous task with its original working directory and arguments.

## What It Does

- Starts agent jobs in a dedicated tmux session named `agent-dispatch`.
- Creates one tmux window per task.
- Tracks recent task status in `~/.cache/agent-dispatch/status.*`.
- Stores rerun context in `~/.cache/agent-dispatch/ctx/`.
- Supports multiple agent backends through `~/.config/agent-dispatch/config`.
- Installs zsh completion for the `agent` command.

## Requirements

- macOS or another Unix-like system with zsh.
- `tmux` installed and available on `PATH`.
- `fzf` installed and available on `PATH` for the interactive agent switcher.
- At least one configured agent command. The default config uses `codex`.

On macOS, install tmux with Homebrew if needed:

```zsh
brew install tmux fzf
```

## Install

Install directly with `curl`:

```zsh
curl -fsSL https://raw.githubusercontent.com/imthor/dispatch/main/setup-agent-dispatch.zsh | zsh
```

Or clone this repository, then run:

```zsh
./setup-agent-dispatch.zsh
```

The installer writes:

```text
~/.local/bin/agent
~/.local/bin/_agent_runner
~/.config/agent-dispatch/config.example
~/.config/agent-dispatch/config
~/.config/agent-dispatch/tmux.conf
~/.config/agent-dispatch/hooks/on_done.example
~/.local/share/zsh/site-functions/_agent
```

Existing generated files at those paths are backed up with a `.bak.<timestamp>`
suffix before being replaced. `~/.config/agent-dispatch/config` is created only
if it does not already exist; future installs refresh `config.example` and keep
your active config.

The installer can prompt for optional defaults when run interactively. Every
prompt also has a CLI flag for automation:

```zsh
./setup-agent-dispatch.zsh \
  --install-prefix ~/.local \
  --no-codex-unsandboxed \
  --update-shell-rc \
  --update-tmux-rc
```

Installer options:

```text
--install-prefix <dir>       Install binaries and completion under dir.
--update-shell-rc            Add install bin dir to the shell rc file.
--no-update-shell-rc         Do not edit the shell rc file.
--update-tmux-rc             Source the tmux fragment from ~/.tmux.conf.
--no-update-tmux-rc          Do not edit ~/.tmux.conf.
--codex-unsandboxed          Default codex runs bypass approvals/sandbox.
--no-codex-unsandboxed       Keep codex defaults sandboxed.
-y, --yes                    Use defaults for unanswered prompts.
```

The installer also adds this to your zsh startup file if it is not already present:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

Restart your terminal or run:

```zsh
source ~/.zshrc
```

## Basic Usage

Dispatch a task:

```zsh
agent "summarize this repo"
```

Dispatch with an explicit label:

```zsh
agent --label repo-summary "summarize this repo"
```

Dispatch from a different working directory:

```zsh
agent --cwd ~/projects/my-app "fix the failing tests"
```

Run the selected agent through Docker Sandbox for one dispatch:

```zsh
agent --docker --type codex --cwd ~/projects/my-app "fix the failing tests"
agent --docker --type claude --cwd ~/projects/my-app "implement the requested change"
agent --docker --type gemini --cwd ~/projects/my-app "review the latest changes"
```

Use a specific configured agent type:

```zsh
agent --type codex "review the latest changes"
```

Pass an extra flag to the selected agent for one run:

```zsh
agent --agent-flag --dangerously-bypass-approvals-and-sandbox "fix the failing tests"
```

Skip configured `AGENT_FLAGS` for one run:

```zsh
agent --no-agent-flags "review this change without extra defaults"
```

## Viewing Agents

Show recent status:

```zsh
agent status
```

Show saved rerun contexts:

```zsh
agent history
```

Open an interactive agent switcher:

```zsh
agent switch
```

Jump directly to the whole dispatcher tmux session:

```zsh
agent attach
```

Show logs for the most recently active dispatched agent:

```zsh
agent logs
```

Show logs for a matching tmux window:

```zsh
agent logs repo-summary
```

Focus an agent window:

```zsh
agent focus repo-summary
```

You can also attach to the whole tmux session:

```zsh
tmux attach -t agent-dispatch
```

Useful tmux keys after attaching:

```text
Ctrl-b n    next window
Ctrl-b p    previous window
Ctrl-b w    window list
Ctrl-b a    agent-dispatch switcher
Ctrl-b A    jump to the agent-dispatch session
Ctrl-b b    return to previous tmux session
```

## Rerunning a Task

Rerun a previous task by matching its tmux window name or saved context:

```zsh
agent rerun repo-summary
```

Rerun uses the saved context from `~/.cache/agent-dispatch/ctx/`, including:

- agent type
- task label
- original working directory
- per-run agent flags
- original task arguments

Status files expire based on `STATUS_TTL_MINS`, but rerun context is preserved
and visible through `agent history`.

## Stopping Agents

Kill a matching agent window:

```zsh
agent kill repo-summary
```

Kill the entire dispatcher tmux session:

```zsh
tmux kill-session -t agent-dispatch
```

## Configuration

Edit:

```zsh
~/.config/agent-dispatch/config
```

Default config:

```zsh
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

typeset -A AGENT_FLAGS
# AGENT_FLAGS[codex]="--model gpt-5.3-codex"
# AGENT_FLAGS[codex]="--dangerously-bypass-approvals-and-sandbox"
```

Configure per-agent default flags:

```zsh
typeset -A AGENT_CMDS
AGENT_CMDS=(
  codex "codex"
  claude "claude"
  gemini "gemini"
  opencode "opencode"
)

typeset -A AGENT_DOCKER_CMDS
AGENT_DOCKER_CMDS=(
  codex "docker sandbox run codex"
  claude "docker sandbox run claude"
  gemini "docker sandbox run gemini"
)

typeset -A AGENT_FLAGS
AGENT_FLAGS=(
  codex "--model gpt-5.3-codex"
  claude "--model claude-opus-4-7"
  gemini "--model gemini-2.5-pro"
)
```

Then run:

```zsh
agent --type claude "implement the requested change"
agent --type gemini "review the latest changes"
agent --type opencode "fix the failing test"
```

Docker Sandbox mode is opt-in. `agent --docker ...` creates or reuses a Docker
Sandbox for the selected agent and working directory, then executes the agent
inside that sandbox with the configured flags and task arguments, equivalent to:

```zsh
docker sandbox create claude ~/projects/my-app
docker sandbox exec -it claude-my-app claude <agent-flags> <task...>
```

To default one agent type to Docker Sandbox, enable it in the config:

```zsh
AGENT_DOCKER_DEFAULTS[codex]=1
```

Use `--no-docker` on an individual dispatch to force the local command path.

## Notifications

By default, desktop notifications are enabled only on macOS:

```zsh
AGENT_NOTIFY="${AGENT_NOTIFY:-auto}"
AGENT_NOTIFY_CLICK="${AGENT_NOTIFY_CLICK:-focus}"
AGENT_NOTIFY_TERMINAL_APP="${AGENT_NOTIFY_TERMINAL_APP:-Terminal}"
```

Set `AGENT_NOTIFY="off"` to disable notifications, or `AGENT_NOTIFY="always"`
to try sending notifications on any system that has `osascript` available.
Linux installs do not require notification tooling and will silently skip
notifications with the default `auto` setting.

Clickable notifications require `terminal-notifier` on macOS:

```zsh
brew install terminal-notifier
```

When `terminal-notifier` is available and `AGENT_NOTIFY_CLICK="focus"`, clicking
an agent notification opens Terminal attached to the corresponding
`agent-dispatch` tmux window using tmux's stable window id. Without
`terminal-notifier`, notifications fall back to macOS `osascript` notifications,
which are display-only.

The click action uses AppleScript's Terminal `do script` command by default:

```zsh
AGENT_NOTIFY_TERMINAL_APP="${AGENT_NOTIFY_TERMINAL_APP:-Terminal}"
```

Notifications are attention-based rather than process-exit-based. While an agent
window is still open, `_agent_runner` watches the tmux pane and sends an `Agent
ready` notification after the pane has stopped changing for
`AGENT_NOTIFY_IDLE_SECS` seconds. This catches both completed interactive work
and cases where the agent is waiting for your input.

```zsh
AGENT_NOTIFY_IDLE_SECS="${AGENT_NOTIFY_IDLE_SECS:-30}"
AGENT_NOTIFY_POLL_SECS="${AGENT_NOTIFY_POLL_SECS:-2}"
```

Exit notifications are off by default because interactive agents often keep the
process open until you quit the session. Enable them only if your configured
agent command exits when work is complete:

```zsh
AGENT_NOTIFY_ON_EXIT=1
```

## Tmux Status Bar

The installer creates a tmux status fragment:

```zsh
~/.config/agent-dispatch/tmux.conf
```

To enable it, add this to `~/.tmux.conf`:

```tmux
source-file ~/.config/agent-dispatch/tmux.conf
```

Reload tmux config:

```zsh
tmux source-file ~/.tmux.conf
```

The dispatcher visually marks only the agent-dispatch tmux session. Its status
bar uses a warm Claude-logo-inspired palette, its left status gets an `AGENT`
badge, and agent status appears on the right. Newly dispatched agent windows also
get a subtle pane background color by default so they are easy to tell apart from
your normal tmux windows.

When the agent-dispatch session does not exist yet, the first dispatched task is
created as window 0. The dispatcher does not create a placeholder `dispatch`
window.

Customize the agent-dispatch session and window styling in:

```zsh
~/.config/agent-dispatch/config
```

```zsh
AGENT_TMUX_WINDOW_STYLE="bg=colour235"
AGENT_TMUX_ACTIVE_WINDOW_STYLE="bg=colour235"
AGENT_TMUX_STATUS_STYLE="bg=#2b211d,fg=#f4efe7"
AGENT_TMUX_STATUS_LEFT_STYLE="bg=#d97757,fg=#fff7ed,bold"
AGENT_TMUX_STATUS_LEFT=" AGENT #S "
AGENT_TMUX_BADGE_STYLE="bg=#d97757,fg=#fff7ed,bold"

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

# Disable pane background styling while keeping the AGENT status badge:
AGENT_TMUX_WINDOW_STYLE=""
AGENT_TMUX_ACTIVE_WINDOW_STYLE=""
```

`AGENT_TMUX_STATUS_STYLE`, `AGENT_TMUX_STATUS_LEFT_STYLE`, and
`AGENT_TMUX_STATUS_LEFT` control the agent-dispatch session status bar.
`AGENT_TMUX_WINDOW_STYLE` and `AGENT_TMUX_ACTIVE_WINDOW_STYLE` control the pane
background for dispatched windows. The `AGENT_TMUX_*_STYLES` associative arrays
let you override those defaults for a specific agent type.

After sourcing the fragment, `Ctrl-b a` opens a top-aligned `fzf` picker in a tmux popup. It lists active dispatcher-managed agent windows with status, type, label, and working directory. Press Enter to switch to the selected agent window, or Escape to close the popup. Use `Ctrl-b b` to return to the tmux session you came from.

## Completion

The installer writes zsh completion to:

```zsh
~/.local/share/zsh/site-functions/_agent
```

If completions do not load, make sure this appears in `~/.zshrc` before `compinit`:

```zsh
fpath=(~/.local/share/zsh/site-functions $fpath)
autoload -Uz compinit
compinit
```

## Development

Run the smoke test:

```zsh
tests/smoke.zsh
```

The smoke test installs into a temporary home directory, checks generated script
syntax, verifies install-prefix handling, and exercises runner flag persistence.

## Uninstall

Remove the installed files:

```zsh
rm -f ~/.local/bin/agent
rm -f ~/.local/bin/_agent_runner
rm -f ~/.local/share/zsh/site-functions/_agent
rm -rf ~/.config/agent-dispatch
rm -rf ~/.cache/agent-dispatch
```

Then remove the `agent-dispatch` PATH block from `~/.zshrc` if you no longer need `~/.local/bin` on `PATH`.
