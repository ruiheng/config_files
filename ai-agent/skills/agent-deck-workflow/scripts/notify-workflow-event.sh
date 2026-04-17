#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Best-effort desktop notifications for agent-deck workflow events.

Usage:
  notify-workflow-event.sh [options]

Options:
  --event <name>             Required event name
  --task-id <id>             Optional task id
  --title <text>             Required notification title
  --message <text>           Required notification message
  --severity <level>         info|warn|error (default: info)
  --artifact-root <path>     Accepted for compatibility; ignored
  --dedupe-seconds <n>       Accepted for compatibility; ignored
  -h, --help                 Show help

Env:
  ADWF_NOTIFY                auto|off|force (default: auto)
  ADWF_NOTIFY_MIN_SEVERITY   info|warn|error (default: info)

Notes:
  - Never fails caller workflow; exits 0 on all paths.
  - Uses best-effort platform backends:
    Linux: notify-send or dunstify
    macOS: osascript
    other platforms: no-op
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

if [[ -z "$event" || -z "$title" || -z "$message" ]]; then
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

backend="noop"
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

exit 0
