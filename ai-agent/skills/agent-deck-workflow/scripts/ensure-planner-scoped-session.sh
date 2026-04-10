#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Ensure a planner-scoped workflow session exists in the planner group recorded for this workspace.

Usage:
  ensure-planner-scoped-session.sh [options]

Options:
  --session-ref <ref>            Required session title/ref
  --session-cmd <command>        Required session command
  --session-workspace <path>     Optional session workspace path (default: current directory)
  --artifact-root <path>         Artifact root (default: .agent-artifacts)
  --profile <name>               Optional agent-deck profile
  -h, --help                     Show help

Outputs:
  - Ensures the session exists, is started, and belongs to the recorded planner group
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

session_ref=""
session_cmd=""
session_workspace=""
artifact_root=".agent-artifacts"
profile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-ref) session_ref="${2:-}"; shift 2 ;;
    --session-cmd) session_cmd="${2:-}"; shift 2 ;;
    --session-workspace) session_workspace="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$session_ref" ]] || die "--session-ref is required"
[[ -n "$session_cmd" ]] || die "--session-cmd is required"
if [[ -z "$session_workspace" ]]; then
  session_workspace="$(pwd -P)"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

session_json() {
  ad session show "$1" --json 2>/dev/null || true
}

record_file="${artifact_root%/}/planner-workspace.json"
[[ -f "$record_file" ]] || die "planner workspace record missing: ${record_file}"

planner_session_id="$(jq -r '.planner_session_id // empty' "$record_file" 2>/dev/null || true)"
planner_group="$(jq -r '.planner_group // empty' "$record_file" 2>/dev/null || true)"
[[ -n "$planner_session_id" ]] || die "planner workspace record missing planner_session_id: ${record_file}"
[[ -n "$planner_group" ]] || die "planner workspace record missing planner_group: ${record_file}"

planner_json="$(session_json "$planner_session_id")"
[[ -n "$planner_json" ]] && jq -e '.id // empty' >/dev/null 2>&1 <<<"$planner_json" || die "planner session recorded in workspace no longer exists: ${planner_session_id}"

existing_json="$(session_json "$session_ref")"
if [[ -n "$existing_json" ]] && jq -e '.id // empty' >/dev/null 2>&1 <<<"$existing_json"; then
  existing_session_id="$(jq -r '.id // empty' <<<"$existing_json")"
  existing_group="$(jq -r '.group // empty' <<<"$existing_json")"
  existing_path="$(jq -r '.path // empty' <<<"$existing_json")"
  existing_status="$(jq -r '.status // empty' <<<"$existing_json")"
  ensure_status="matched"

  [[ "$existing_path" == "$session_workspace" ]] || die "session path mismatch: ref='${session_ref}' existing='${existing_path}' expected='${session_workspace}'"

  if [[ "$existing_group" != "$planner_group" ]]; then
    ad group move "$existing_session_id" "$planner_group" >/dev/null
    ensure_status="moved"
  fi

  case "$existing_status" in
    running|waiting|idle) ;;
    *)
      ad session start "$existing_session_id" >/dev/null
      ensure_status="${ensure_status}_started"
      ;;
  esac

  echo "planner_scoped_session status=${ensure_status} session_id=${existing_session_id} session_ref=${session_ref} planner_group=${planner_group} planner_session_id=${planner_session_id}"
  exit 0
fi

launch_json="$(ad launch "$session_workspace" -t "$session_ref" -g "$planner_group" --no-parent -c "$session_cmd" --no-wait --json 2>/dev/null || true)"
session_id="$(jq -r '.id // empty' <<<"$launch_json" 2>/dev/null || true)"
[[ -n "$session_id" ]] || die "failed to create session '${session_ref}' in planner group '${planner_group}'"

echo "planner_scoped_session status=created session_id=${session_id} session_ref=${session_ref} planner_group=${planner_group} planner_session_id=${planner_session_id}"
