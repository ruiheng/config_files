#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Send one delegated task with workflow-owned active-task lock protection.

Usage:
  send-delegate-with-active-task-lock.sh [options]

Required:
  --workdir <path>                Worker workspace that owns .agent-artifacts/
  --task-id <id>                  Task id
  --integration-branch <ref>      Non-task landing branch
  --planner-session-id <id>       Planner sender session id
  --coder-session-id <id>         Coder target session id
  --coder-session-ref <ref>       Coder session ref/title
  --task-branch <ref>             Task branch
  --subject <text>                Mailbox subject
  --body-file <path|->            Body source, or "-" for stdin

Optional:
  --artifact-root <path>          Artifact root (default: <workdir>/.agent-artifacts)
  --content-type <type>           Mailbox content type (default: text/markdown)
  --schema-version <value>        Mailbox schema version (default: 1)
  --wake-delay-seconds <n>        Delay before active-session wake send (default: 10)
  --json                          Emit JSON summary
  -h, --help                      Show help

Behavior:
  - Acquires active-task.lock before send.
  - Rolls the lock back only if mailbox send fails before a delivery is queued.
  - Marks the lock as sent and records delivery_id after send succeeds.
  - Marks send interruptions as send_interrupted_unknown instead of leaving pending_send behind.
  - Keeps the lock if post-delivery wakeup fails.
  - Returns success after a queued delivery even if post-delivery wakeup fails.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

send_fail() {
  echo "SEND_FAILED: $*" >&2
  exit 3
}

receipt_fail() {
  echo "SEND_RECEIPT_UNKNOWN: $*" >&2
  exit 5
}

wake_fail() {
  echo "WAKE_FAILED: $*" >&2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly fixed_wake_message="Use the check-agent-mail skill now. Receive the pending message and execute its requested action."

workdir=""
task_id=""
integration_branch=""
planner_session_id=""
coder_session_id=""
coder_session_ref=""
task_branch=""
subject=""
body_file=""
artifact_root=""
content_type="text/markdown"
schema_version="1"
wake_delay_seconds="10"
json_output=0
lock_acquired=0
rollback_allowed=0
send_in_progress=0
send_completed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) workdir="${2:-}"; shift 2 ;;
    --task-id) task_id="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_id="${2:-}"; shift 2 ;;
    --coder-session-id) coder_session_id="${2:-}"; shift 2 ;;
    --coder-session-ref) coder_session_ref="${2:-}"; shift 2 ;;
    --task-branch) task_branch="${2:-}"; shift 2 ;;
    --subject) subject="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --content-type) content_type="${2:-}"; shift 2 ;;
    --schema-version) schema_version="${2:-}"; shift 2 ;;
    --wake-delay-seconds) wake_delay_seconds="${2:-}"; shift 2 ;;
    --json) json_output=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$workdir" ]] || die "--workdir is required"
[[ -n "$task_id" ]] || die "--task-id is required"
[[ -n "$integration_branch" ]] || die "--integration-branch is required"
[[ -n "$planner_session_id" ]] || die "--planner-session-id is required"
[[ -n "$coder_session_id" ]] || die "--coder-session-id is required"
[[ -n "$coder_session_ref" ]] || die "--coder-session-ref is required"
[[ -n "$task_branch" ]] || die "--task-branch is required"
[[ -n "$subject" ]] || die "--subject is required"
[[ -n "$body_file" ]] || die "--body-file is required"

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v agent-mailbox >/dev/null 2>&1 || die "agent-mailbox is required"
command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"

abs_path() {
  (
    cd "$1"
    pwd -P
  )
}

[[ -d "$workdir" ]] || die "workdir does not exist: ${workdir}"
workdir="$(abs_path "$workdir")"

if [[ -z "$artifact_root" ]]; then
  artifact_root="${workdir%/}/.agent-artifacts"
fi
lock_dir="${artifact_root%/}/active-task.lock"
lock_file="${lock_dir}/lock.json"

rollback_lock() {
  local lock_task_id lock_state
  if (( lock_acquired == 0 || rollback_allowed == 0 || send_completed == 1 )); then
    return 0
  fi
  if [[ ! -f "$lock_file" ]]; then
    return 0
  fi
  lock_task_id="$(jq -r '.task_id // empty' "$lock_file" 2>/dev/null || true)"
  lock_state="$(jq -r '.state // empty' "$lock_file" 2>/dev/null || true)"
  if [[ "$lock_task_id" == "$task_id" && "$lock_state" == "pending_send" ]]; then
    rm -rf "$lock_dir" || true
  fi
}

on_exit() {
  rollback_lock
}

on_signal() {
  local status="$1"
  local signal_name="$2"

  if (( send_in_progress == 1 )); then
    mark_lock_send_interrupted "$signal_name"
    rollback_allowed=0
  fi
  rollback_lock
  trap - EXIT INT TERM
  exit "$status"
}

trap on_exit EXIT
trap 'on_signal 130 INT' INT
trap 'on_signal 143 TERM' TERM

read_body() {
  if [[ "$body_file" == "-" ]]; then
    cat
  else
    [[ -f "$body_file" ]] || die "body file not found: $body_file"
    cat "$body_file"
  fi
}

trim_whitespace() {
  local value="$1"

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

normalize_scalar() {
  local value

  value="$(trim_whitespace "$1")"
  if [[ "$value" == \`*\` && ${#value} -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  fi
  trim_whitespace "$value"
}

extract_body_scalar() {
  local body="$1"
  local prefix="$2"
  local line trimmed_line

  while IFS= read -r line; do
    trimmed_line="$(trim_whitespace "$line")"
    if [[ "$trimmed_line" == "$prefix"* ]]; then
      normalize_scalar "${trimmed_line#"$prefix"}"
      return 0
    fi
  done <<<"$body"
  return 1
}

validate_delegate_body() {
  local body="$1"
  local body_task_id body_action body_from body_to body_integration_branch body_task_branch

  body_task_id="$(extract_body_scalar "$body" "Task:")" || die "delegate body is missing matching task header: Task: ${task_id}"
  [[ "$body_task_id" == "$task_id" ]] || die "delegate body task header mismatch: expected ${task_id}, got ${body_task_id}"

  body_action="$(extract_body_scalar "$body" "Action:")" || die "delegate body is missing Action: execute_delegate_task"
  [[ "$body_action" == "execute_delegate_task" ]] || die "delegate body action mismatch: expected execute_delegate_task, got ${body_action}"

  body_from="$(extract_body_scalar "$body" "From:")" || die "delegate body is missing matching sender header: From: planner ${planner_session_id}"
  [[ "$body_from" == "planner ${planner_session_id}" ]] || die "delegate body sender mismatch: expected planner ${planner_session_id}, got ${body_from}"

  body_to="$(extract_body_scalar "$body" "To:")" || die "delegate body is missing matching recipient header: To: coder ${coder_session_id}"
  [[ "$body_to" == "coder ${coder_session_id}" ]] || die "delegate body recipient mismatch: expected coder ${coder_session_id}, got ${body_to}"

  body_integration_branch="$(extract_body_scalar "$body" "- Integration branch:")" || die "delegate body is missing matching integration branch: ${integration_branch}"
  [[ "$body_integration_branch" == "$integration_branch" ]] || die "delegate body integration branch mismatch: expected ${integration_branch}, got ${body_integration_branch}"

  body_task_branch="$(extract_body_scalar "$body" "- Task branch:")" || die "delegate body is missing matching task branch: ${task_branch}"
  [[ "$body_task_branch" == "$task_branch" ]] || die "delegate body task branch mismatch: expected ${task_branch}, got ${body_task_branch}"
}

mark_lock_sent() {
  local delivery_id="$1"
  local message_id="$2"
  local tmp_lock

  tmp_lock="$(mktemp)"
  jq \
    --arg delivery_id "$delivery_id" \
    --arg message_id "$message_id" \
    --arg sent_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.state = "sent"
     | .delivery_id = $delivery_id
     | .message_id = (if $message_id == "" then null else $message_id end)
     | .sent_at = $sent_at' \
    "$lock_file" >"$tmp_lock"
  mv "$tmp_lock" "$lock_file"
}

mark_lock_receipt_unknown() {
  local send_output="$1"
  local tmp_lock

  tmp_lock="$(mktemp)"
  jq \
    --arg send_output "$send_output" \
    --arg queued_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.state = "queued_receipt_unknown"
     | .queued_at = $queued_at
     | .send_receipt_raw = $send_output' \
    "$lock_file" >"$tmp_lock"
  mv "$tmp_lock" "$lock_file"
}

mark_lock_send_interrupted() {
  local signal_name="$1"
  local tmp_lock

  if [[ ! -f "$lock_file" ]]; then
    return 0
  fi

  tmp_lock="$(mktemp)"
  jq \
    --arg signal_name "$signal_name" \
    --arg interrupted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.state = "send_interrupted_unknown"
     | .interrupted_by_signal = $signal_name
     | .interrupted_at = $interrupted_at' \
    "$lock_file" >"$tmp_lock"
  mv "$tmp_lock" "$lock_file"
}

validate_target_session() {
  local show_json shown_id session_path session_workdir

  if ! show_json="$(agent-deck session show "$coder_session_id" --json 2>/dev/null)"; then
    die "coder session is not reachable: ${coder_session_id}"
  fi
  shown_id="$(jq -r 'if type == "object" then .id // empty else empty end' <<<"$show_json" 2>/dev/null || true)"
  [[ -n "$shown_id" ]] || die "coder session did not resolve to an id: ${coder_session_id}"
  [[ "$shown_id" == "$coder_session_id" ]] || die "--coder-session-id must be a resolved session id; got ${coder_session_id}, resolved to ${shown_id}"

  session_path="$(jq -r 'if type == "object" then .path // empty else empty end' <<<"$show_json" 2>/dev/null || true)"
  [[ -n "$session_path" ]] || die "coder session has no workspace path: ${coder_session_id}"
  [[ -d "$session_path" ]] || die "coder session workspace does not exist: ${session_path}"
  session_workdir="$(abs_path "$session_path")"
  [[ "$session_workdir" == "$workdir" ]] || die "coder session workspace mismatch: --workdir=${workdir}, session.path=${session_workdir}"
}

validate_target_session

lock_output="$(
  "${script_dir}/acquire-active-task-lock.sh" \
    --workdir "$workdir" \
    --task-id "$task_id" \
    --integration-branch "$integration_branch" \
    --planner-session-id "$planner_session_id" \
    --coder-session-id "$coder_session_id" \
    --coder-session-ref "$coder_session_ref" \
    --task-branch "$task_branch" \
    --from-address "agent-deck/${planner_session_id}" \
    --to-address "agent-deck/${coder_session_id}" \
    --subject "$subject" \
    --artifact-root "$artifact_root"
)"
lock_acquired=1
rollback_allowed=1

body="$(read_body)"
body="${body//\{\{FROM_SESSION_ID\}\}/$planner_session_id}"
body="${body//\{\{TO_SESSION_ID\}\}/$coder_session_id}"
body="${body//\{\{TO_SESSION_REF\}\}/$coder_session_ref}"
validate_delegate_body "$body"

send_in_progress=1
set +e
send_output="$(
  printf '%s' "$body" | agent-mailbox send \
    --to "agent-deck/${coder_session_id}" \
    --from "agent-deck/${planner_session_id}" \
    --subject "$subject" \
    --content-type "$content_type" \
    --schema-version "$schema_version" \
    --body-file - 2>&1
)"
send_rc=$?
set -e
send_in_progress=0
if (( send_rc != 0 )); then
  send_fail "agent-mailbox send failed: ${send_output:-exit code ${send_rc}}"
fi
send_completed=1
rollback_allowed=0
mark_lock_receipt_unknown "$send_output"

delivery_id=""
message_id=""
blob_id=""
for token in $send_output; do
  case "$token" in
    delivery_id=*) delivery_id="${token#delivery_id=}" ;;
    message_id=*) message_id="${token#message_id=}" ;;
    blob_id=*) blob_id="${token#blob_id=}" ;;
  esac
done
[[ -n "$delivery_id" ]] || receipt_fail "delegate send succeeded but no delivery_id was returned; lock retained in queued_receipt_unknown for recovery"

mark_lock_sent "$delivery_id" "$message_id"

wakeup_status="skipped"
if [[ -n "$wake_delay_seconds" && "$wake_delay_seconds" != "0" ]]; then
  sleep "$wake_delay_seconds"
fi

set +e
wake_output="$(agent-deck session send --no-wait "$coder_session_id" "$fixed_wake_message" 2>&1)"
wake_rc=$?
set -e
if (( wake_rc == 0 )); then
  wakeup_status="sent"
else
  wakeup_status="failed"
fi

trap - EXIT INT TERM

if (( json_output )); then
  jq -n \
    --arg task_id "$task_id" \
    --arg planner_session_id "$planner_session_id" \
    --arg coder_session_id "$coder_session_id" \
    --arg coder_session_ref "$coder_session_ref" \
    --arg subject "$subject" \
    --arg delivery_id "$delivery_id" \
    --arg message_id "$message_id" \
    --arg blob_id "$blob_id" \
    --arg wakeup_status "$wakeup_status" \
    --arg wake_output "$wake_output" \
    --arg lock_dir "$lock_dir" \
    --arg lock_file "$lock_file" \
    --arg lock_output "$lock_output" \
    '{
      status: "sent",
      task_id: $task_id,
      from_session_id: $planner_session_id,
      to_session_id: $coder_session_id,
      to_session_ref: $coder_session_ref,
      subject: $subject,
      delivery_id: $delivery_id,
      message_id: (if $message_id == "" then null else $message_id end),
      blob_id: (if $blob_id == "" then null else $blob_id end),
      wakeup_status: $wakeup_status,
      wake_output: (if $wake_output == "" then null else $wake_output end),
      lock_dir: $lock_dir,
      lock_file: $lock_file,
      lock_output: $lock_output
    }'
else
  printf 'delegate_dispatch_ok task_id=%s delivery_id=%s wakeup_status=%s lock_dir=%s\n' "$task_id" "$delivery_id" "$wakeup_status" "$lock_dir"
fi

if [[ "$wakeup_status" == "failed" ]]; then
  wake_fail "delegate delivery ${delivery_id} was queued but target wakeup failed: ${wake_output:-exit code ${wake_rc}}"
fi
