#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

export HOME="${tmpdir}/home"
install_prefix="${tmpdir}/prefix with space"

"${repo_dir}/setup-agent-dispatch.zsh" \
  --install-prefix "${install_prefix}" \
  --no-update-shell-rc \
  --no-update-tmux-rc \
  --codex-unsandboxed \
  >/dev/null

zsh -n "${install_prefix}/bin/agent"
zsh -n "${install_prefix}/bin/_agent_runner"

grep -Fq -- '--dangerously-bypass-approvals-and-sandbox' "${HOME}/.config/agent-dispatch/config"
grep -Fq -- 'prefix\ with\ space/bin/agent switch-popup' "${HOME}/.config/agent-dispatch/tmux.conf"

cat > "${HOME}/.config/agent-dispatch/config" <<'AGENT_CONFIG'
SESSION="agent-dispatch"
typeset -A AGENT_CMDS
AGENT_CMDS=( test "/bin/echo" )
typeset -A AGENT_FLAGS
AGENT_FLAGS[test]="--default-flag"
AGENT_CONFIG

AGENT_RUN_KEY="smoke.run" "${install_prefix}/bin/_agent_runner" \
  test smoke "${repo_dir}" 1 2 --runtime-one "runtime two" task arg \
  > "${tmpdir}/runner.out"

grep -Fq -- '--default-flag --runtime-one runtime two task arg' "${tmpdir}/runner.out"
grep -Fq -- "RUNTIME_AGENT_FLAGS=( --runtime-one 'runtime two' )" "${HOME}/.cache/agent-dispatch/ctx/smoke.run"

"${install_prefix}/bin/agent" history | grep -Fq smoke

print "smoke ok"
