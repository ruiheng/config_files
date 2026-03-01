#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Best-effort desktop notifications for agent-deck workflow events.

Usage:
  notify-workflow-event.sh [options]

Options:
  --event <name>             Required event name
  --task-id <id>             Required task id
  --title <text>             Required notification title
  --message <text>           Required notification message
  --severity <level>         info|warn|error (default: info)
  --artifact-root <path>     Artifact root for state/log files (default: .agent-artifacts)
  --dedupe-seconds <n>       Dedupe window in seconds (default from env or 30)
  -h, --help                 Show help

Env:
  ADWF_NOTIFY                auto|off|force (default: auto)
  ADWF_NOTIFY_MIN_SEVERITY   info|warn|error (default: info)
  ADWF_NOTIFY_LOG            Log file path (default: <artifact-root>/workflow-health/notifications.log)
  ADWF_NOTIFY_STATE          State file path (default: <artifact-root>/workflow-health/notify-state.json)
  ADWF_NOTIFY_DEDUPE_SECONDS Dedupe window seconds (default: 30)

Notes:
  - Never fails caller workflow; exits 0 on all paths.
  - Uses best-effort platform backends:
    Linux: notify-send or dunstify
    macOS: osascript
    other platforms: log-only fallback
EOF
}

event=""
task_id=""
title=""
message=""
severity="info"
artifact_root=".agent-artifacts"
dedupe_seconds=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event) event="${2:-}"; shift 2 ;;
    --task-id) task_id="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --message) message="${2:-}"; shift 2 ;;
    --severity) severity="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --dedupe-seconds) dedupe_seconds="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) shift 1 ;;
  esac
done

severity_rank() {
  case "$1" in
    info) echo 0 ;;
    warn) echo 1 ;;
    error) echo 2 ;;
    *) echo 0 ;;
  esac
}

esc_osascript() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

mode="${ADWF_NOTIFY:-auto}"
min_severity="${ADWF_NOTIFY_MIN_SEVERITY:-info}"
if [[ -z "$dedupe_seconds" ]]; then
  dedupe_seconds="${ADWF_NOTIFY_DEDUPE_SECONDS:-30}"
fi

if [[ -z "$event" || -z "$task_id" || -z "$title" || -z "$message" ]]; then
  exit 0
fi

case "$mode" in
  auto|off|force) ;;
  *) mode="auto" ;;
esac

case "$severity" in
  info|warn|error) ;;
  *) severity="info" ;;
esac

case "$min_severity" in
  info|warn|error) ;;
  *) min_severity="info" ;;
esac

event_rank="$(severity_rank "$severity")"
min_rank="$(severity_rank "$min_severity")"
if (( event_rank < min_rank )); then
  exit 0
fi

if [[ "$mode" == "off" ]]; then
  exit 0
fi

health_dir="${artifact_root%/}/workflow-health"
mkdir -p "$health_dir"
notify_log="${ADWF_NOTIFY_LOG:-${health_dir}/notifications.log}"
notify_state="${ADWF_NOTIFY_STATE:-${health_dir}/notify-state.json}"

if [[ ! "$dedupe_seconds" =~ ^[0-9]+$ ]]; then
  dedupe_seconds=30
fi

now_epoch="$(date +%s)"
dedupe_key="${event}|${task_id}|${severity}"
skip_due_dedupe=0

if (( dedupe_seconds > 0 )) && [[ -f "$notify_state" ]]; then
  last_ts="$(jq -r --arg key "$dedupe_key" '.[$key] // 0' "$notify_state" 2>/dev/null || echo 0)"
  if [[ "$last_ts" =~ ^[0-9]+$ ]]; then
    if (( now_epoch - last_ts < dedupe_seconds )); then
      skip_due_dedupe=1
    fi
  fi
fi

if (( skip_due_dedupe )); then
  printf '%s event=%s task_id=%s severity=%s backend=dedupe_skip title=%q message=%q\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$task_id" "$severity" "$title" "$message" >>"$notify_log" 2>/dev/null || true
  exit 0
fi

tmp_state="$(mktemp)"
if [[ -f "$notify_state" ]] && jq -e 'type == "object"' "$notify_state" >/dev/null 2>&1; then
  jq --arg key "$dedupe_key" --argjson ts "$now_epoch" '. + {($key): $ts}' "$notify_state" >"$tmp_state" 2>/dev/null || true
else
  jq -nc --arg key "$dedupe_key" --argjson ts "$now_epoch" '{($key): $ts}' >"$tmp_state" 2>/dev/null || true
fi
if [[ -s "$tmp_state" ]]; then
  mv "$tmp_state" "$notify_state"
else
  rm -f "$tmp_state"
fi

backend="log_only"
delivered=0

if [[ "$(uname -s)" == "Linux" ]]; then
  urgency="normal"
  if [[ "$severity" == "warn" ]]; then
    urgency="normal"
  elif [[ "$severity" == "error" ]]; then
    urgency="critical"
  fi
  if command -v notify-send >/dev/null 2>&1; then
    backend="notify-send"
    if notify-send -a "agent-deck-workflow" -u "$urgency" "$title" "$message" >/dev/null 2>&1; then
      delivered=1
    fi
  elif command -v dunstify >/dev/null 2>&1; then
    backend="dunstify"
    if dunstify -a "agent-deck-workflow" -u "$urgency" "$title" "$message" >/dev/null 2>&1; then
      delivered=1
    fi
  fi
elif [[ "$(uname -s)" == "Darwin" ]]; then
  if command -v osascript >/dev/null 2>&1; then
    backend="osascript"
    title_e="$(esc_osascript "$title")"
    message_e="$(esc_osascript "$message")"
    if osascript -e "display notification \"${message_e}\" with title \"${title_e}\"" >/dev/null 2>&1; then
      delivered=1
    fi
  fi
fi

if [[ "$mode" == "force" ]]; then
  delivered=1
fi

printf '%s event=%s task_id=%s severity=%s backend=%s delivered=%s title=%q message=%q\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$task_id" "$severity" "$backend" "$delivered" "$title" "$message" >>"$notify_log" 2>/dev/null || true

exit 0
