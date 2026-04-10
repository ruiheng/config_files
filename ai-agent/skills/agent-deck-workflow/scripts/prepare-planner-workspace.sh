#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Prepare a planner workspace before local plan execution starts.

Usage:
  prepare-planner-workspace.sh [options]

Options:
  --integration-branch <ref>      Required non-task landing branch for this workspace
  --planner-session-id <id|title> Planner session ref (default: current agent-deck session id)
  --supervisor-session-id <id|title> Optional supervisor session id/ref for this planner workspace
  --artifact-root <path>          Artifact root (default: .agent-artifacts)
  --allow-dirty                   Allow dirty worktree when switching branches
  -h, --help                      Show help

Outputs:
  - Ensures or validates <artifact-root>/planner-workspace.json
  - Switches the worktree to the required integration branch when needed
  - Prints one summary line with the resulting status

Exit codes:
  0: workspace prepared
  2: usage/argument/runtime validation error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

integration_branch=""
planner_session_ref=""
supervisor_session_ref=""
artifact_root=".agent-artifacts"
allow_dirty=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --supervisor-session-id) supervisor_session_ref="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$integration_branch" ]] || die "--integration-branch is required"

command -v git >/dev/null 2>&1 || die "git is required"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "must run inside a git repository"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ensure_cmd=(
  "${script_dir}/ensure-planner-workspace.sh"
  --integration-branch "$integration_branch"
  --artifact-root "$artifact_root"
)
if [[ -n "$planner_session_ref" ]]; then
  ensure_cmd+=(--planner-session-id "$planner_session_ref")
fi
if [[ -n "$supervisor_session_ref" ]]; then
  ensure_cmd+=(--supervisor-session-id "$supervisor_session_ref")
fi

"${ensure_cmd[@]}" >/dev/null

git rev-parse --verify "$integration_branch" >/dev/null 2>&1 || die "integration branch does not exist: $integration_branch"

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
[[ -n "$current_branch" ]] || die "failed to resolve current branch"

if (( allow_dirty == 0 )); then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "dirty worktree/index; commit or stash first (or pass --allow-dirty)"
  fi
fi

if [[ "$current_branch" == "$integration_branch" ]]; then
  echo "planner_workspace_prepared status=already_on_integration current_branch=${current_branch} integration_branch=${integration_branch}"
  exit 0
fi

switch_output="$(git switch "$integration_branch" 2>&1)" || {
  echo "$switch_output" >&2
  die "failed to switch to integration branch '${integration_branch}'"
}

echo "$switch_output"
echo "planner_workspace_prepared status=switched current_branch=${current_branch} integration_branch=${integration_branch}"
