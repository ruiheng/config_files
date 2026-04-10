#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Ensure a planner session exists in a child group of the current supervisor group.

Usage:
  ensure-supervised-planner-session.sh [options]

Options:
  --planner-session-ref <ref>     Required planner session title/ref
  --planner-cmd <command>         Required planner command
  --planner-workspace <path>      Required planner workspace path
  --supervisor-session-id <id>    Optional supervisor session id/ref (default: current session)
  --planner-group-name <name>     Optional child-group name (default: sanitized planner-session-ref)
  --profile <name>                Optional agent-deck profile
  -h, --help                      Show help

Outputs:
  - Ensures the planner session exists, is started, and belongs to the target planner group
  - Prints one summary line with `session_id=` and `planner_group=`

Exit codes:
  0: session ensured
  2: usage/runtime validation error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

planner_session_ref=""
planner_cmd=""
planner_workspace=""
supervisor_session_ref=""
planner_group_name=""
profile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-session-ref) planner_session_ref="${2:-}"; shift 2 ;;
    --planner-cmd) planner_cmd="${2:-}"; shift 2 ;;
    --planner-workspace) planner_workspace="${2:-}"; shift 2 ;;
    --supervisor-session-id) supervisor_session_ref="${2:-}"; shift 2 ;;
    --planner-group-name) planner_group_name="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$planner_session_ref" ]] || die "--planner-session-ref is required"
[[ -n "$planner_cmd" ]] || die "--planner-cmd is required"
[[ -n "$planner_workspace" ]] || die "--planner-workspace is required"

command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

sanitize_group_name() {
  LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"$1" | LC_ALL=C tr -cs '[:alnum:].@_-' '-'
}

group_exists() {
  local group_path="$1"
  local groups_json
  groups_json="$(ad group list --json 2>/dev/null || true)"
  jq -e --arg group_path "$group_path" '.groups[]? | select(.path == $group_path)' >/dev/null 2>&1 <<<"$groups_json"
}

session_json() {
  ad session show "$1" --json 2>/dev/null || true
}

resolve_supervisor_json() {
  if [[ -n "$supervisor_session_ref" ]]; then
    session_json "$supervisor_session_ref"
  else
    ad session current --json 2>/dev/null || true
  fi
}

supervisor_json="$(resolve_supervisor_json)"
[[ -n "$supervisor_json" ]] || die "failed to resolve supervisor session; pass --supervisor-session-id"

supervisor_session_id="$(jq -r '.id // empty' <<<"$supervisor_json" 2>/dev/null || true)"
supervisor_group="$(jq -r '.group // empty' <<<"$supervisor_json" 2>/dev/null || true)"
[[ -n "$supervisor_session_id" ]] || die "supervisor session id is missing"
[[ -n "$supervisor_group" ]] || die "supervisor group is missing; supervisor session must belong to a non-root group"

if [[ -z "$planner_group_name" ]]; then
  planner_group_name="$(sanitize_group_name "$planner_session_ref")"
fi
[[ -n "$planner_group_name" ]] || die "failed to derive planner group name"

planner_group_path="${supervisor_group}/${planner_group_name}"

if ! group_exists "$planner_group_path"; then
  ad group create "$planner_group_name" --parent "$supervisor_group" >/dev/null
fi

existing_planner_json="$(session_json "$planner_session_ref")"
if [[ -n "$existing_planner_json" ]] && jq -e '.id // empty' >/dev/null 2>&1 <<<"$existing_planner_json"; then
  planner_session_id="$(jq -r '.id // empty' <<<"$existing_planner_json")"
  existing_group="$(jq -r '.group // empty' <<<"$existing_planner_json")"
  existing_path="$(jq -r '.path // empty' <<<"$existing_planner_json")"
  existing_status="$(jq -r '.status // empty' <<<"$existing_planner_json")"
  ensure_status="matched"

  [[ "$existing_path" == "$planner_workspace" ]] || die "planner session path mismatch: ref='${planner_session_ref}' existing='${existing_path}' expected='${planner_workspace}'"

  if [[ "$existing_group" != "$planner_group_path" ]]; then
    ad group move "$planner_session_id" "$planner_group_path" >/dev/null
    ensure_status="moved"
  fi

  case "$existing_status" in
    running|waiting|idle) ;;
    *)
      ad session start "$planner_session_id" >/dev/null
      ensure_status="${ensure_status}_started"
      ;;
  esac

  echo "planner_session status=${ensure_status} session_id=${planner_session_id} session_ref=${planner_session_ref} planner_group=${planner_group_path} supervisor_session_id=${supervisor_session_id}"
  exit 0
fi

launch_json="$(ad launch "$planner_workspace" -t "$planner_session_ref" -g "$planner_group_path" --no-parent -c "$planner_cmd" --no-wait --json 2>/dev/null || true)"
planner_session_id="$(jq -r '.id // empty' <<<"$launch_json" 2>/dev/null || true)"
[[ -n "$planner_session_id" ]] || die "failed to create planner session '${planner_session_ref}' in group '${planner_group_path}'"

echo "planner_session status=created session_id=${planner_session_id} session_ref=${planner_session_ref} planner_group=${planner_group_path} supervisor_session_id=${supervisor_session_id}"
