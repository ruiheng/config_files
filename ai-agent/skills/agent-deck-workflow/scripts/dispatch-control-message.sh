#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  dispatch-control-message.sh
    --task-id <id>
    --planner-session <id|title>
    --to-session <id|title>
    --action <name>
    --artifact-path <path>
    [--from-session <id|title>]
    [--planner-session-id <id|title>]
    [--from-session-id <id|title>]
    [--to-session-id <id|title>]
    [--round <n|final>]
    [--note <text>]
    [--group <group>]
    [--cmd <tool>]
    [--path <project_path>]
    [--profile <profile>]
    [--message-file <path>]
    [--no-ensure-session]
    [--no-start-session]

Examples:
  dispatch-control-message.sh \
    --task-id 20260225-1916-expiry-semantics \
    --planner-session-id planner \
    --to-session-id executor-20260225-1916-expiry-semantics \
    --action execute_delegate_task \
    --artifact-path .agent-artifacts/20260225-1916-expiry-semantics/delegate-task-20260225-1916-expiry-semantics.md \
    --cmd codex

Notes:
  - If the target session does not exist and --group is omitted, the script uses the current session's group.
EOF
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

profile=""
path="."
round="1"
ensure_session=1
start_session=1
task_id=""
planner_session_ref=""
from_session_ref=""
to_session_ref=""
action=""
artifact_path=""
note="Read and follow the artifact file."
group=""
cmd=""
message_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="$2"; shift 2 ;;
    --planner-session|--planner-session-id) planner_session_ref="$2"; shift 2 ;;
    --from-session|--from-session-id) from_session_ref="$2"; shift 2 ;;
    --to-session|--to-session-id) to_session_ref="$2"; shift 2 ;;
    --action) action="$2"; shift 2 ;;
    --artifact-path) artifact_path="$2"; shift 2 ;;
    --round) round="$2"; shift 2 ;;
    --note) note="$2"; shift 2 ;;
    --group) group="$2"; shift 2 ;;
    --cmd) cmd="$2"; shift 2 ;;
    --path) path="$2"; shift 2 ;;
    --profile) profile="$2"; shift 2 ;;
    --message-file) message_file="$2"; shift 2 ;;
    --no-ensure-session) ensure_session=0; shift 1 ;;
    --no-start-session) start_session=0; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$task_id" ]] || die "--task-id is required"
[[ -n "$planner_session_ref" ]] || die "--planner-session (or --planner-session-id) is required"
[[ -n "$to_session_ref" ]] || die "--to-session (or --to-session-id) is required"
[[ -n "$action" ]] || die "--action is required"
[[ -n "$artifact_path" ]] || die "--artifact-path is required"

if [[ -z "$from_session_ref" ]]; then
  from_session_ref="$planner_session_ref"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

resolve_session_id() {
  local ref="$1"
  local shown
  shown="$(ad session show "$ref" --json 2>/dev/null || true)"
  if [[ -z "$shown" ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$shown" | jq -r '.id // empty'
}

resolve_current_group() {
  local current
  current="$(ad session current --json 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$current" | jq -r '.group // empty'
}

created=0
if (( ensure_session )); then
  if ! ad session show "$to_session_ref" --json >/dev/null 2>&1; then
    if [[ -z "$group" ]]; then
      group="$(resolve_current_group)"
    fi
    [[ -n "$group" ]] || die "session missing and failed to resolve group from current session; pass --group explicitly"
    [[ -n "$cmd" ]] || die "session missing and --cmd not provided for creation"
    ad add "$path" --title "$to_session_ref" --group "$group" --cmd "$cmd" >/dev/null
    created=1
  fi
fi

planner_session_id="$(resolve_session_id "$planner_session_ref")"
from_session_id="$(resolve_session_id "$from_session_ref")"
to_session_id="$(resolve_session_id "$to_session_ref")"

[[ -n "$planner_session_id" ]] || die "failed to resolve planner session id from ref: $planner_session_ref"
[[ -n "$from_session_id" ]] || die "failed to resolve from session id from ref: $from_session_ref"
[[ -n "$to_session_id" ]] || die "failed to resolve to session id from ref: $to_session_ref"

if [[ -z "$message_file" ]]; then
  safe_from="${from_session_id//[^a-zA-Z0-9_.-]/_}"
  safe_to="${to_session_id//[^a-zA-Z0-9_.-]/_}"
  message_file=".agent-artifacts/${task_id}/messages/${safe_from}-to-${safe_to}-r${round}.json"
fi

mkdir -p "$(dirname "$message_file")"
cat >"$message_file" <<EOF
{
  "schema_version": "1.0",
  "task_id": "$(json_escape "$task_id")",
  "planner_session_id": "$(json_escape "$planner_session_id")",
  "required_skills": ["agent-deck-workflow"],
  "from_session_id": "$(json_escape "$from_session_id")",
  "to_session_id": "$(json_escape "$to_session_id")",
  "round": "$(json_escape "$round")",
  "action": "$(json_escape "$action")",
  "artifact_path": "$(json_escape "$artifact_path")",
  "note": "$(json_escape "$note")"
}
EOF

started=0
if (( start_session )); then
  if ad session start "$to_session_id" >/dev/null 2>&1; then
    started=1
  fi
fi

ad session send "$to_session_id" "$(cat "$message_file")" >/dev/null
show_json="$(ad session show "$to_session_id" --json)"

id=""
status=""
if command -v jq >/dev/null 2>&1; then
  id="$(printf '%s' "$show_json" | jq -r '.id // empty')"
  status="$(printf '%s' "$show_json" | jq -r '.status // empty')"
fi

echo "dispatch_ok to=${to_session_id} created=${created} started=${started} payload=${message_file}"
if [[ -n "$id" || -n "$status" ]]; then
  echo "session id=${id} status=${status}"
else
  echo "$show_json"
fi
