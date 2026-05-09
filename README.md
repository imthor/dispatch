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
~/.config/agent-dispatch/config
~/.config/agent-dispatch/tmux.conf
~/.config/agent-dispatch/hooks/on_done.example
~/.local/share/zsh/site-functions/_agent
```

Existing files at those paths are backed up with a `.bak.<timestamp>` suffix before being replaced.

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

Use a specific configured agent type:

```zsh
agent --type codex "review the latest changes"
```

## Viewing Agents

Show recent status:

```zsh
agent status
```

Open an interactive agent switcher:

```zsh
agent switch
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
Ctrl-b b    return to previous tmux session
```

## Rerunning a Task

Rerun a previous task by matching its tmux window name:

```zsh
agent rerun repo-summary
```

Rerun uses the saved context from `~/.cache/agent-dispatch/ctx/`, including:

- agent type
- task label
- original working directory
- original task arguments

Status files expire based on `STATUS_TTL_MINS`, but rerun context is preserved.

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
)

typeset -A AGENT_FLAGS
# AGENT_FLAGS[codex]="--model gpt-5.3-codex"
```

Add another agent type:

```zsh
typeset -A AGENT_CMDS
AGENT_CMDS=(
  codex "codex"
  claude "claude"
)

typeset -A AGENT_FLAGS
AGENT_FLAGS=(
  codex "--model gpt-5.3-codex"
  claude "--model claude-opus-4-7"
)
```

Then run:

```zsh
agent --type claude "implement the requested change"
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

After sourcing the fragment, `Ctrl-b a` opens an `fzf` picker in a tmux popup. It lists active dispatcher-managed agent windows with status, type, label, and working directory. Press Enter to switch to the selected agent window, or Escape to close the popup. Use `Ctrl-b b` to return to the tmux session you came from.

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
