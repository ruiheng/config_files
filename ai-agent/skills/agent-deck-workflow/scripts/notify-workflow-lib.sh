#!/usr/bin/env bash

# Shared best-effort wrapper around notify-workflow-event.sh.
# This stays source-able from workflow scripts so they can emit notifications
# without repeating path lookup and no-fail delivery glue.

adwf_notify_event() {
  local event="${1:-}"
  local severity="${2:-info}"
  local title="${3:-}"
  local message="${4:-}"
  local notify_task_id="${5:-${task_id:-}}"
  local notify_artifact_root="${6:-${artifact_root:-.agent-artifacts}}"
  local notify_script=""

  notify_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify-workflow-event.sh"
  if [[ -x "$notify_script" ]]; then
    "$notify_script" \
      --event "$event" \
      --task-id "$notify_task_id" \
      --title "$title" \
      --message "$message" \
      --severity "$severity" \
      --artifact-root "$notify_artifact_root" >/dev/null 2>&1 || true
  fi
}
