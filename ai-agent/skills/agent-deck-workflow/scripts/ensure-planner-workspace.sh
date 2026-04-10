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
  --supervisor-session-id <id|title> Optional supervisor session id/ref for this planner workspace
  --artifact-root <path>          Artifact root (default: .agent-artifacts)
  -h, --help                      Show help

Outputs:
  - Writes or validates <artifact-root>/planner-workspace.json
  - Prints one summary line with the resulting status

Exit codes:
  0: record created, refreshed, or matched
  2: usage/argument/runtime validation error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

resolve_current_session_json() {
  agent-deck session current --json 2>/dev/null || true
}

resolve_current_session_id() {
  local current_json current_id
  current_json="$(resolve_current_session_json)"
  current_id="$(jq -r '.id // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_id" ]] || die "failed to resolve current agent-deck session id; pass --planner-session-id"
  echo "$current_id"
}

resolve_current_session_group() {
  local current_json current_group
  current_json="$(resolve_current_session_json)"
  current_group="$(jq -r '.group // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_group" ]] || die "failed to resolve current agent-deck session group; planner session must belong to a non-root group"
  echo "$current_group"
}

resolve_session_group() {
  local shown session_group
  shown="$(agent-deck session show "$1" --json 2>/dev/null || true)"
  session_group="$(jq -r '.group // empty' <<<"$shown" 2>/dev/null || true)"
  [[ -n "$session_group" ]] || die "failed to resolve agent-deck session group for '${1}'; planner session must belong to a non-root group"
  echo "$session_group"
}

session_exists() {
  local session_ref="$1"
  local shown
  shown="$(agent-deck session show "$session_ref" --json 2>/dev/null || true)"
  [[ -n "$shown" ]] && jq -e '.id // empty' >/dev/null 2>&1 <<<"$shown"
}

is_task_branch_ref() {
  case "$1" in
    task/*|refs/heads/task/*|refs/remotes/*/task/*) return 0 ;;
    *) return 1 ;;
  esac
}

write_record() {
  local output_file="$1"
  local planner_session_id="$2"
  local planner_group="$3"
  local integration_branch="$4"
  local supervisor_session_id="$5"
  local status="$6"
  local tmp_record

  tmp_record="$(mktemp)"
  jq -nc \
    --arg planner_session_id "$planner_session_id" \
    --arg planner_group "$planner_group" \
    --arg integration_branch "$integration_branch" \
    --arg supervisor_session_id "$supervisor_session_id" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    '{
      planner_session_id: $planner_session_id,
      planner_group: $planner_group,
      integration_branch: $integration_branch,
      updated_at: $updated_at
    } + (
      if $supervisor_session_id == "" then
        {}
      else
        {supervisor_session_id: $supervisor_session_id}
      end
    ) + (
      if $status == "created" then
        {created_at: $updated_at}
      else
        {}
      end
    )' >"$tmp_record"
  mv "$tmp_record" "$output_file"
}

planner_session_ref=""
integration_branch=""
supervisor_session_ref=""
artifact_root=".agent-artifacts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --supervisor-session-id) supervisor_session_ref="${2:-}"; shift 2 ;;
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
  planner_group="$(resolve_current_session_group)"
else
  planner_group="$(resolve_session_group "$planner_session_ref")"
fi

is_task_branch_ref "$integration_branch" && die "--integration-branch must be a non-task landing branch, got: ${integration_branch}"
git rev-parse --verify "$integration_branch" >/dev/null 2>&1 || die "integration branch does not exist: $integration_branch"

record_file="${artifact_root%/}/planner-workspace.json"
mkdir -p "$(dirname "$record_file")"

if [[ ! -f "$record_file" ]]; then
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "$supervisor_session_ref" "created"
  echo "planner_workspace_record status=created file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch}"
  exit 0
fi

record_planner_session_id="$(jq -r '.planner_session_id // empty' "$record_file" 2>/dev/null || true)"
record_planner_group="$(jq -r '.planner_group // empty' "$record_file" 2>/dev/null || true)"
record_integration_branch="$(jq -r '.integration_branch // empty' "$record_file" 2>/dev/null || true)"
record_supervisor_session_id="$(jq -r '.supervisor_session_id // empty' "$record_file" 2>/dev/null || true)"

[[ -n "$record_planner_session_id" ]] || die "planner workspace record missing planner_session_id: ${record_file}"
[[ -n "$record_integration_branch" ]] || die "planner workspace record missing integration_branch: ${record_file}"

if ! session_exists "$record_planner_session_id"; then
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "$supervisor_session_ref" "stale_replaced"
  echo "planner_workspace_record status=stale_replaced file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch}"
  exit 0
fi

[[ "$record_planner_session_id" == "$planner_session_ref" ]] || die "planner workspace planner mismatch: record='${record_planner_session_id}' expected='${planner_session_ref}' file='${record_file}'"
[[ "$record_integration_branch" == "$integration_branch" ]] || die "planner workspace integration branch mismatch: record='${record_integration_branch}' expected='${integration_branch}' file='${record_file}'"
if [[ -n "$record_supervisor_session_id" && -n "$supervisor_session_ref" ]]; then
  [[ "$record_supervisor_session_id" == "$supervisor_session_ref" ]] || die "planner workspace supervisor mismatch: record='${record_supervisor_session_id}' expected='${supervisor_session_ref}' file='${record_file}'"
fi

if [[ -z "$record_planner_group" || "$record_planner_group" != "$planner_group" || ( -n "$supervisor_session_ref" && "$record_supervisor_session_id" != "$supervisor_session_ref" ) ]]; then
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "${supervisor_session_ref:-$record_supervisor_session_id}" "matched_refreshed"
  echo "planner_workspace_record status=matched_refreshed file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch}"
  exit 0
fi

echo "planner_workspace_record status=matched file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch}"
