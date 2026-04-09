#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Ensure the planner workspace record for this git worktree.

Usage:
  ensure-planner-workspace.sh [options]

Options:
  --integration-branch <ref>      Required non-task landing branch for this workspace
  --planner-session-id <id|title> Planner session ref (default: current agent-deck session id)
  --artifact-root <path>          Artifact root (default: .agent-artifacts)
  -h, --help                      Show help

Outputs:
  - Writes or validates <artifact-root>/planner-workspace.json
  - Prints one summary line with the resulting status

Exit codes:
  0: record created or matched
  2: usage/argument/runtime validation error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

resolve_current_session_id() {
  local current_json current_id
  current_json="$(agent-deck session current --json 2>/dev/null || true)"
  current_id="$(jq -r '.id // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_id" ]] || die "failed to resolve current agent-deck session id; pass --planner-session-id"
  echo "$current_id"
}

is_task_branch_ref() {
  case "$1" in
    task/*|refs/heads/task/*|refs/remotes/*/task/*) return 0 ;;
    *) return 1 ;;
  esac
}

planner_session_ref=""
integration_branch=""
artifact_root=".agent-artifacts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$integration_branch" ]] || die "--integration-branch is required"

command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "must run inside a git repository"
fi

if [[ -z "$planner_session_ref" ]]; then
  planner_session_ref="$(resolve_current_session_id)"
fi

is_task_branch_ref "$integration_branch" && die "--integration-branch must be a non-task landing branch, got: ${integration_branch}"
git rev-parse --verify "$integration_branch" >/dev/null 2>&1 || die "integration branch does not exist: $integration_branch"

record_file="${artifact_root%/}/planner-workspace.json"
mkdir -p "$(dirname "$record_file")"

if [[ ! -f "$record_file" ]]; then
  tmp_record="$(mktemp)"
  jq -nc \
    --arg planner_session_id "$planner_session_ref" \
    --arg integration_branch "$integration_branch" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      planner_session_id: $planner_session_id,
      integration_branch: $integration_branch,
      created_at: $created_at
    }' >"$tmp_record"
  mv "$tmp_record" "$record_file"
  echo "planner_workspace_record status=created file=${record_file} planner=${planner_session_ref} integration_branch=${integration_branch}"
  exit 0
fi

record_planner_session_id="$(jq -r '.planner_session_id // empty' "$record_file" 2>/dev/null || true)"
record_integration_branch="$(jq -r '.integration_branch // empty' "$record_file" 2>/dev/null || true)"

[[ -n "$record_planner_session_id" ]] || die "planner workspace record missing planner_session_id: ${record_file}"
[[ -n "$record_integration_branch" ]] || die "planner workspace record missing integration_branch: ${record_file}"

[[ "$record_planner_session_id" == "$planner_session_ref" ]] || die "planner workspace planner mismatch: record='${record_planner_session_id}' expected='${planner_session_ref}' file='${record_file}'"
[[ "$record_integration_branch" == "$integration_branch" ]] || die "planner workspace integration branch mismatch: record='${record_integration_branch}' expected='${integration_branch}' file='${record_file}'"

echo "planner_workspace_record status=matched file=${record_file} planner=${planner_session_ref} integration_branch=${integration_branch}"
