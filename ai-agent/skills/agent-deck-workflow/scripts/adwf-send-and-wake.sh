#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  adwf-send-and-wake.sh [options]

Required:
  --from-session-id <id>         Sender session id
  --subject <text>               Mailbox subject
  --body-file <path|->           Body source, or "-" for stdin

Target selection:
  --to-session-id <id>           Existing target session id
  --to-session-ref <ref>         Existing target session ref/title

Optional target creation:
  --ensure-target-title <title>  Create target session with this title if missing
  --ensure-target-cmd <cmd>      Full command for target session launch
  --parent-session-id <id>       Parent session id for target session creation
  --workdir <path>               Workdir for `agent-deck launch` (default: cwd)

Optional:
  --content-type <type>          Mailbox content type (default: text/markdown)
  --schema-version <value>       Mailbox schema version (default: 1)
  --listener-message <text>      Override session-start listener instruction
  --wake-message <text>          Override active-session wake instruction
  --wake-delay-seconds <n>       Delay before active-session wake send (default: 10)
  --json                         Emit JSON summary
  -h, --help                     Show help

Body placeholder replacement:
  {{FROM_SESSION_ID}}
  {{TO_SESSION_ID}}
  {{TO_SESSION_REF}}
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run_capture() {
  local step="$1"
  shift
  local output=""
  local status=0
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if (( status != 0 )); then
    if [[ -n "$output" ]]; then
      die "$step failed: $output"
    fi
    die "$step failed with exit code $status"
  fi
  printf '%s' "$output"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found in PATH"
}

json_get_field() {
  jq -r "$1 // empty"
}

from_session_id=""
to_session_id=""
to_session_ref=""
ensure_target_title=""
ensure_target_cmd=""
parent_session_id=""
workdir="$(pwd)"
subject=""
body_file=""
content_type="text/markdown"
schema_version="1"
listener_message=""
wake_message=""
wake_delay_seconds="10"
json_output=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-session-id) from_session_id="${2:-}"; shift 2 ;;
    --to-session-id) to_session_id="${2:-}"; shift 2 ;;
    --to-session-ref) to_session_ref="${2:-}"; shift 2 ;;
    --ensure-target-title) ensure_target_title="${2:-}"; shift 2 ;;
    --ensure-target-cmd) ensure_target_cmd="${2:-}"; shift 2 ;;
    --parent-session-id) parent_session_id="${2:-}"; shift 2 ;;
    --workdir) workdir="${2:-}"; shift 2 ;;
    --subject) subject="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --content-type) content_type="${2:-}"; shift 2 ;;
    --schema-version) schema_version="${2:-}"; shift 2 ;;
    --listener-message) listener_message="${2:-}"; shift 2 ;;
    --wake-message) wake_message="${2:-}"; shift 2 ;;
    --wake-delay-seconds) wake_delay_seconds="${2:-}"; shift 2 ;;
    --json) json_output=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ -n "$from_session_id" ]] || die "--from-session-id is required"
[[ -n "$subject" ]] || die "--subject is required"
[[ -n "$body_file" ]] || die "--body-file is required"

require_cmd agent-deck
require_cmd agent-mailbox
require_cmd jq

created_target=0

resolve_session_id() {
  local ref="$1"
  local show_json
  if ! show_json="$(agent-deck session show "$ref" --json 2>/dev/null)"; then
    return 1
  fi
  if [[ "$(printf '%s' "$show_json" | json_get_field '.success')" == "false" ]]; then
    return 1
  fi
  printf '%s' "$show_json" | json_get_field '.id'
}

get_session_status() {
  local session="$1"
  local show_json
  if ! show_json="$(agent-deck session show "$session" --json 2>/dev/null)"; then
    return 1
  fi
  if [[ "$(printf '%s' "$show_json" | json_get_field '.success')" == "false" ]]; then
    return 1
  fi
  printf '%s' "$show_json" | json_get_field '.status'
}

if [[ -z "$to_session_id" ]]; then
  if [[ -n "$to_session_ref" ]]; then
    if resolved_id="$(resolve_session_id "$to_session_ref")" && [[ -n "$resolved_id" ]]; then
      to_session_id="$resolved_id"
    fi
  fi

  if [[ -z "$to_session_id" ]]; then
    [[ -n "$ensure_target_title" ]] || die "target session missing: provide --to-session-id, --to-session-ref, or --ensure-target-title"
    [[ -n "$ensure_target_cmd" ]] || die "--ensure-target-cmd is required when creating target session"
    [[ -n "$parent_session_id" ]] || die "--parent-session-id is required when creating target session"
    [[ -d "$workdir" ]] || die "workdir does not exist: $workdir"

    if [[ -z "$listener_message" ]]; then
      listener_message="Use the check-workflow-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
    fi
    create_json="$(run_capture "agent-deck launch" agent-deck launch --json --title "$ensure_target_title" --parent "$parent_session_id" --cmd "$ensure_target_cmd" --message "$listener_message" "$workdir")"
    to_session_id="$(printf '%s' "$create_json" | json_get_field '.id')"
    [[ -n "$to_session_id" ]] || die "failed to parse created target session id"
    if [[ -z "$to_session_ref" ]]; then
      to_session_ref="$ensure_target_title"
    fi
    created_target=1
  fi
fi

if [[ -z "$to_session_ref" ]]; then
  to_session_ref="$to_session_id"
fi

body=""
restore_tty_echo() {
  if [[ -n "${stty_state:-}" ]]; then
    stty "$stty_state"
    unset stty_state
  fi
}

if [[ "$body_file" == "-" ]]; then
  if [[ -t 0 ]]; then
    stty_state="$(stty -g)"
    trap restore_tty_echo EXIT
    stty -echo
  fi
  body="$(cat)"
  restore_tty_echo
  trap - EXIT
else
  [[ -f "$body_file" ]] || die "body file not found: $body_file"
  body="$(cat "$body_file")"
fi

body="${body//\{\{FROM_SESSION_ID\}\}/$from_session_id}"
body="${body//\{\{TO_SESSION_ID\}\}/$to_session_id}"
body="${body//\{\{TO_SESSION_REF\}\}/$to_session_ref}"

from_address="agent-deck/${from_session_id}"
to_address="agent-deck/${to_session_id}"

current_session_id="$(agent-deck session current --json 2>/dev/null | json_get_field '.id' || true)"
start_status="skipped_same_session"
listener_status="skipped_same_session"
wakeup_status="skipped_same_session"
nudge_after_send=0

if [[ "$current_session_id" != "$to_session_id" ]]; then
  if (( created_target )); then
    start_status="started"
    listener_status="started"
    nudge_after_send=1
  else
    target_status="$(get_session_status "$to_session_id" || true)"
    case "$target_status" in
      running|waiting|idle)
        start_status="already_${target_status}"
        listener_status="not_needed_existing_session"
        nudge_after_send=1
        ;;
      *)
        if [[ -z "$listener_message" ]]; then
          listener_message="Use the check-workflow-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
        fi
        run_capture "agent-deck session start (${to_session_id})" agent-deck session start --json -m "$listener_message" "$to_session_id" >/dev/null
        start_status="started"
        listener_status="started"
        nudge_after_send=1
        ;;
    esac
  fi
fi

set +e
send_output="$(
  printf '%s' "$body" | agent-mailbox send \
    --to "$to_address" \
    --from "$from_address" \
    --subject "$subject" \
    --content-type "$content_type" \
    --schema-version "$schema_version" \
    --body-file - 2>&1
)"
send_status=$?
set -e
if (( send_status != 0 )); then
  if [[ -n "$send_output" ]]; then
    die "agent-mailbox send failed: $send_output"
  fi
  die "agent-mailbox send failed with exit code $send_status"
fi

message_id=""
delivery_id=""
blob_id=""
for token in $send_output; do
  case "$token" in
    message_id=*) message_id="${token#message_id=}" ;;
    delivery_id=*) delivery_id="${token#delivery_id=}" ;;
    blob_id=*) blob_id="${token#blob_id=}" ;;
  esac
done

if (( nudge_after_send )); then
  if [[ -n "$wake_delay_seconds" && "$wake_delay_seconds" != "0" ]]; then
    sleep "$wake_delay_seconds"
  fi
  if [[ -z "$wake_message" ]]; then
    wake_message="Use the check-workflow-mail skill now. Receive the pending message for your current agent-deck session and execute its requested action."
  fi
  run_capture "agent-deck session send (${to_session_id})" agent-deck session send --no-wait "$to_session_id" "$wake_message" >/dev/null
  wakeup_status="sent"
fi

if (( json_output )); then
  jq -n \
    --arg from_session_id "$from_session_id" \
    --arg to_session_id "$to_session_id" \
    --arg to_session_ref "$to_session_ref" \
    --arg subject "$subject" \
    --arg message_id "$message_id" \
    --arg delivery_id "$delivery_id" \
    --arg blob_id "$blob_id" \
    --arg start_status "$start_status" \
    --arg listener_status "$listener_status" \
    --arg wakeup_status "$wakeup_status" \
    --argjson created_target "$created_target" \
    --argjson wake_delay_seconds "$wake_delay_seconds" \
    '{
      from_session_id: $from_session_id,
      to_session_id: $to_session_id,
      to_session_ref: $to_session_ref,
      created_target: $created_target,
      subject: $subject,
      message_id: (if $message_id == "" then null else $message_id end),
      delivery_id: (if $delivery_id == "" then null else $delivery_id end),
      blob_id: (if $blob_id == "" then null else $blob_id end),
      start_status: $start_status,
      listener_status: $listener_status,
      wakeup_status: $wakeup_status,
      wake_delay_seconds: $wake_delay_seconds
    }'
else
  printf 'dispatch_ok to_session_id=%s to_session_ref=%s created_target=%s message_id=%s delivery_id=%s start_status=%s listener_status=%s wakeup_status=%s wake_delay_seconds=%s\n' \
    "$to_session_id" \
    "$to_session_ref" \
    "$created_target" \
    "${message_id:-none}" \
    "${delivery_id:-none}" \
    "$start_status" \
    "$listener_status" \
    "$wakeup_status" \
    "$wake_delay_seconds"
fi
