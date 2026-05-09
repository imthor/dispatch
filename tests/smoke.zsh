#!/usr/bin/env zsh

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

grep -Fq -- '#!/usr/bin/env zsh' "${install_prefix}/bin/agent"
grep -Fq -- '#!/usr/bin/env zsh' "${install_prefix}/bin/_agent_runner"
grep -Fq -- '--dangerously-bypass-approvals-and-sandbox' "${HOME}/.config/agent-dispatch/config"
grep -Fq -- 'prefix\ with\ space/bin/agent switch-popup' "${HOME}/.config/agent-dispatch/tmux.conf"

cat > "${HOME}/.config/agent-dispatch/config" <<'AGENT_CONFIG'
SESSION="agent-dispatch"
AGENT_NOTIFY_IDLE_SECS=0
AGENT_GIT_WORKTREE=0
typeset -A AGENT_CMDS
AGENT_CMDS=( test "/bin/echo" codex "/bin/echo" )
typeset -A AGENT_DOCKER_CMDS
AGENT_DOCKER_CMDS=( test "docker sandbox run test" )
typeset -A AGENT_FLAGS
AGENT_FLAGS[test]="--default-flag"
AGENT_CONFIG

AGENT_RUN_KEY="smoke.run" "${install_prefix}/bin/_agent_runner" \
  test smoke "${repo_dir}" 1 0 2 --runtime-one "runtime two" task arg \
  > "${tmpdir}/runner.out"

grep -Fq -- '--default-flag --runtime-one runtime two task arg' "${tmpdir}/runner.out"
grep -Fq -- "RUNTIME_AGENT_FLAGS=( --runtime-one 'runtime two' )" "${HOME}/.cache/agent-dispatch/ctx/smoke.run"
grep -Fq -- 'USE_DOCKER=0' "${HOME}/.cache/agent-dispatch/ctx/smoke.run"

cat > "${HOME}/.config/agent-dispatch/config" <<'AGENT_CONFIG_OLD_DEFAULT'
SESSION="agent-dispatch"
AGENT_NOTIFY_IDLE_SECS=0
AGENT_GIT_WORKTREE=0
typeset -A AGENT_CMDS
AGENT_CMDS=( test "/bin/echo" codex "/bin/echo" )
AGENT_DOCKER_DEFAULTS[test]=1
AGENT_CONFIG_OLD_DEFAULT

AGENT_RUN_KEY="smoke.old-default" "${install_prefix}/bin/_agent_runner" \
  test old-default "${repo_dir}" 1 0 0 compat-task \
  > "${tmpdir}/runner-old-default.out"

grep -Fq -- 'compat-task' "${tmpdir}/runner-old-default.out"

cat > "${HOME}/.config/agent-dispatch/config" <<'AGENT_CONFIG'
SESSION="agent-dispatch"
AGENT_NOTIFY_IDLE_SECS=0
AGENT_GIT_WORKTREE=0
typeset -A AGENT_CMDS
AGENT_CMDS=( test "/bin/echo" codex "/bin/echo" )
typeset -A AGENT_DOCKER_CMDS
AGENT_DOCKER_CMDS=( test "docker sandbox run test" codex "docker sandbox run codex" )
typeset -A AGENT_FLAGS
AGENT_FLAGS[test]="--default-flag"
AGENT_CONFIG

mkdir -p "${tmpdir}/bin"
cat > "${tmpdir}/bin/docker" <<'DOCKER'
#!/bin/sh
state="${DOCKER_STATE:?}"
if [ "$1" = sandbox ] && [ "$2" = create ]; then
  if [ -f "$state" ]; then
    printf 'sandbox with name test-dispatch already exists. Use '\''docker sandbox run test-dispatch'\'' to connect to it\n' >&2
    exit 1
  fi
  printf '%s\n' "$4" > "$state"
  printf '<create>\n'
  printf '<%s>\n' "$3"
  printf '<%s>\n' "$4"
  printf 'Created sandbox test-sandbox in VM test-dispatch\n'
  exit 0
fi
if [ "$1" = sandbox ] && [ "$2" = exec ]; then
  shift 2
  if [ "${1:-}" = -i ] && [ -n "${DOCKER_SYNC_LOG:-}" ]; then
    printf 'auth-sync\n' >> "${DOCKER_SYNC_LOG}"
  fi
  for arg in "$@"; do
    printf '<%s>\n' "$arg"
  done
  exit 0
fi
printf 'unexpected docker command: %s\n' "$*" >&2
exit 1
DOCKER
chmod +x "${tmpdir}/bin/docker"

DOCKER_STATE="${tmpdir}/docker.state" PATH="${tmpdir}/bin:${PATH}" AGENT_RUN_KEY="smoke.docker" "${install_prefix}/bin/_agent_runner" \
  test smoke-docker "${repo_dir}" 1 1 1 --runtime-docker "task arg" \
  > "${tmpdir}/runner-docker.out"

grep -Fq -- "<test-dispatch>" "${tmpdir}/runner-docker.out"
grep -Fq -- "<--workdir>" "${tmpdir}/runner-docker.out"
grep -Fq -- "<${repo_dir}>" "${tmpdir}/runner-docker.out"
grep -Fq -- "<test>" "${tmpdir}/runner-docker.out"
grep -Fq -- "<--default-flag>" "${tmpdir}/runner-docker.out"
grep -Fq -- "<--runtime-docker>" "${tmpdir}/runner-docker.out"
grep -Fq -- "<task arg>" "${tmpdir}/runner-docker.out"
grep -Fq -- 'USE_DOCKER=1' "${HOME}/.cache/agent-dispatch/ctx/smoke.docker"

mkdir -p "${HOME}/.codex"
printf '{"auth_mode":"chatgpt","OPENAI_API_KEY":null}\n' > "${HOME}/.codex/auth.json"

DOCKER_STATE="${tmpdir}/codex-docker.state" DOCKER_SYNC_LOG="${tmpdir}/codex-sync.log" PATH="${tmpdir}/bin:${PATH}" AGENT_RUN_KEY="smoke.codex-docker" "${install_prefix}/bin/_agent_runner" \
  codex smoke-codex-docker "${repo_dir}" 1 1 0 "codex task" \
  > "${tmpdir}/runner-codex-docker.out"

grep -Fq -- "auth-sync" "${tmpdir}/codex-sync.log"
grep -Fq -- "<codex>" "${tmpdir}/runner-codex-docker.out"
grep -Fq -- "<codex task>" "${tmpdir}/runner-codex-docker.out"

cat > "${tmpdir}/bin/tmux" <<'TMUX'
#!/bin/sh
log="${TMUX_LOG:?}"
case "$1" in
  has-session)
    exit 1
    ;;
  new-session|new-window)
    printf '1\n'
    ;;
  send-keys)
    printf '%s\n' "$4" >> "$log"
    PATH="${AGENT_TEST_PATH:?}" zsh -c "$4"
    ;;
  set-option)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUX
chmod +x "${tmpdir}/bin/tmux"

mkdir -p "${tmpdir}/path-no-tmux"
ln -s "${commands[zsh]}" "${tmpdir}/path-no-tmux/zsh"

PATH="${install_prefix}/bin:${tmpdir}/path-no-tmux" "${install_prefix}/bin/agent" switch \
  > "${tmpdir}/agent-switch-no-tmux.out" 2>&1 && {
    cat "${tmpdir}/agent-switch-no-tmux.out" >&2
    exit 1
  }
grep -Fq -- "requires 'tmux' on PATH" "${tmpdir}/agent-switch-no-tmux.out"

TMUX_LOG="${tmpdir}/tmux.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  DOCKER_STATE="${tmpdir}/docker.state" PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --docker --type test --cwd "${repo_dir}" --agent-flag --runtime-cli "cli task with spaces" \
  > "${tmpdir}/agent-docker.out"

grep -Fq -- "using Docker" "${tmpdir}/agent-docker.out"
grep -Fq -- "<test-dispatch>" "${tmpdir}/agent-docker.out"
grep -Fq -- "<--workdir>" "${tmpdir}/agent-docker.out"
grep -Fq -- "<${repo_dir}>" "${tmpdir}/agent-docker.out"
grep -Fq -- "<test>" "${tmpdir}/agent-docker.out"
grep -Fq -- "<--runtime-cli>" "${tmpdir}/agent-docker.out"
grep -Fq -- "<cli task with spaces>" "${tmpdir}/agent-docker.out"

git_repo="${tmpdir}/git-repo"
mkdir -p "${git_repo}"
git -C "${git_repo}" init >/dev/null
git -C "${git_repo}" config user.email smoke@example.invalid
git -C "${git_repo}" config user.name "Smoke Test"
printf 'hello\n' > "${git_repo}/README.md"
git -C "${git_repo}" add README.md
git -C "${git_repo}" commit -m initial >/dev/null

cat > "${HOME}/.config/agent-dispatch/config" <<'AGENT_CONFIG'
SESSION="agent-dispatch"
AGENT_NOTIFY_IDLE_SECS=0
AGENT_GIT_WORKTREE=1
typeset -A AGENT_CMDS
AGENT_CMDS=( test "/bin/echo" codex "/bin/echo" )
AGENT_CONFIG

TMUX_LOG="${tmpdir}/tmux-worktree.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --type test --cwd "${git_repo}" --task-name smoke-branch "git task" \
  > "${tmpdir}/agent-worktree.out"

worktree_dir="${git_repo}/.agent-worktrees/smoke-branch"
grep -Fq -- "dispatched test 'smoke-branch'" "${tmpdir}/agent-worktree.out"
test -e "${worktree_dir}/.git"
grep -R -Fq -- "${worktree_dir}" "${HOME}/.cache/agent-dispatch/ctx"
grep -R -Fq -- "TASK_LABEL=smoke-branch" "${HOME}/.cache/agent-dispatch/ctx"
grep -Fq -- ".agent-worktrees/" "${git_repo}/.git/info/exclude"

git -C "${git_repo}" worktree remove "${worktree_dir}"
TMUX_LOG="${tmpdir}/tmux-worktree-recreate.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --type test --cwd "${git_repo}" --task-name smoke-branch "git task again" \
  > "${tmpdir}/agent-worktree-recreate.out"

grep -Fq -- "dispatched test 'smoke-branch'" "${tmpdir}/agent-worktree-recreate.out"
test -e "${worktree_dir}/.git"

mkdir -p "${git_repo}/scratch"
TMUX_LOG="${tmpdir}/tmux-worktree-subdir.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --type test --cwd "${git_repo}/scratch" --task-name subdir-task "subdir git task" \
  > "${tmpdir}/agent-worktree-subdir.out"

subdir_worktree="${git_repo}/.agent-worktrees/subdir-task/scratch"
test -d "${subdir_worktree}"
grep -R -Fq -- "${subdir_worktree}" "${HOME}/.cache/agent-dispatch/ctx"

other_repo="${tmpdir}/other/git-repo"
mkdir -p "${other_repo}"
git -C "${other_repo}" init >/dev/null
git -C "${other_repo}" config user.email smoke@example.invalid
git -C "${other_repo}" config user.name "Smoke Test"
printf 'other\n' > "${other_repo}/README.md"
git -C "${other_repo}" add README.md
git -C "${other_repo}" commit -m initial >/dev/null

shared_worktrees="${tmpdir}/shared-worktrees"
TMUX_LOG="${tmpdir}/tmux-worktree-shared-a.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  AGENT_GIT_WORKTREE_PARENT="${shared_worktrees}" PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --type test --cwd "${git_repo}" --task-name shared-task "shared task" \
  > "${tmpdir}/agent-worktree-shared-a.out"

TMUX_LOG="${tmpdir}/tmux-worktree-shared-b.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  AGENT_GIT_WORKTREE_PARENT="${shared_worktrees}" PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --type test --cwd "${other_repo}" --task-name shared-task "shared task" \
  > "${tmpdir}/agent-worktree-shared-b.out" 2>&1 && {
    cat "${tmpdir}/agent-worktree-shared-b.out" >&2
    exit 1
  }
grep -Fq -- "belongs to a different repository" "${tmpdir}/agent-worktree-shared-b.out"

custom_worktree_dir="${tmpdir}/custom-worktrees"
TMUX_LOG="${tmpdir}/tmux-worktree-custom-dir.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --type test --cwd "${git_repo}" --worktree-dir "${custom_worktree_dir}" --task-name custom-dir-task "custom dir task" \
  > "${tmpdir}/agent-worktree-custom-dir.out"

test -e "${custom_worktree_dir}/git-repo-custom-dir-task/.git"
grep -R -Fq -- "${custom_worktree_dir}/git-repo-custom-dir-task" "${HOME}/.cache/agent-dispatch/ctx"

TMUX_LOG="${tmpdir}/tmux-no-worktree.log" AGENT_TEST_PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  PATH="${tmpdir}/bin:${install_prefix}/bin:${PATH}" \
  "${install_prefix}/bin/agent" --no-worktree --type test --cwd "${git_repo}" "plain git task" \
  > "${tmpdir}/agent-no-worktree.out"

grep -R -Fq -- "${git_repo}" "${HOME}/.cache/agent-dispatch/ctx"

"${install_prefix}/bin/agent" history | grep -Fq smoke

print "smoke ok"
