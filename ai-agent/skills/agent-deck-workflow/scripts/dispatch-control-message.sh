#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  dispatch-control-message.sh
    --task-id <id>
    --planner-session <name>
    --to-session <name>
    --action <name>
    --artifact-path <path>
    [--from-session <name>]
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
    --planner-session planner \
    --to-session executor-20260225-1916-expiry-semantics \
    --action execute_delegate_task \
    --artifact-path .agent-artifacts/20260225-1916-expiry-semantics/delegate-task-20260225-1916-expiry-semantics.md \
    --group lyceum \
    --cmd codex
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
planner_session=""
from_session=""
to_session=""
action=""
artifact_path=""
note="Read and follow the artifact file."
group=""
cmd=""
message_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="$2"; shift 2 ;;
    --planner-session) planner_session="$2"; shift 2 ;;
    --from-session) from_session="$2"; shift 2 ;;
    --to-session) to_session="$2"; shift 2 ;;
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
[[ -n "$planner_session" ]] || die "--planner-session is required"
[[ -n "$to_session" ]] || die "--to-session is required"
[[ -n "$action" ]] || die "--action is required"
[[ -n "$artifact_path" ]] || die "--artifact-path is required"

if [[ -z "$from_session" ]]; then
  from_session="$planner_session"
fi

if [[ -z "$message_file" ]]; then
  safe_from="${from_session//[^a-zA-Z0-9_.-]/_}"
  safe_to="${to_session//[^a-zA-Z0-9_.-]/_}"
  message_file=".agent-artifacts/${task_id}/messages/${safe_from}-to-${safe_to}-r${round}.json"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

mkdir -p "$(dirname "$message_file")"
cat >"$message_file" <<EOF
{
  "schema_version": "1.0",
  "task_id": "$(json_escape "$task_id")",
  "planner_session": "$(json_escape "$planner_session")",
  "from_session": "$(json_escape "$from_session")",
  "to_session": "$(json_escape "$to_session")",
  "round": "$(json_escape "$round")",
  "action": "$(json_escape "$action")",
  "artifact_path": "$(json_escape "$artifact_path")",
  "note": "$(json_escape "$note")"
}
EOF

created=0
if (( ensure_session )); then
  if ! ad session show "$to_session" --json >/dev/null 2>&1; then
    [[ -n "$group" ]] || die "session missing and --group not provided for creation"
    [[ -n "$cmd" ]] || die "session missing and --cmd not provided for creation"
    ad add "$path" --title "$to_session" --group "$group" --cmd "$cmd" >/dev/null
    created=1
  fi
fi

started=0
if (( start_session )); then
  if ad session start "$to_session" >/dev/null 2>&1; then
    started=1
  fi
fi

ad session send "$to_session" "$(cat "$message_file")" >/dev/null
show_json="$(ad session show "$to_session" --json)"

id=""
status=""
if command -v jq >/dev/null 2>&1; then
  id="$(printf '%s' "$show_json" | jq -r '.id // empty')"
  status="$(printf '%s' "$show_json" | jq -r '.status // empty')"
fi

echo "dispatch_ok to=${to_session} created=${created} started=${started} payload=${message_file}"
if [[ -n "$id" || -n "$status" ]]; then
  echo "session id=${id} status=${status}"
else
  echo "$show_json"
fi
