#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Archive task-session resume metadata, then optionally remove executor/reviewer sessions.

Usage:
  ai-agent/skills/agent-deck-workflow/scripts/archive-and-remove-task-sessions.sh [options]

Options:
  --task-id <id>                 Required task id (YYYYMMDD-HHMM-<slug>)
  --planner-session <id|title>   Planner session ref (default: planner)
  --executor-session <id|title>  Executor session ref (default: executor-<task_id>)
  --reviewer-session <id|title>  Reviewer session ref (default: reviewer-<task_id>)
  --artifact-root <path>         Artifact root (default: .agent-artifacts)
  --profile <name>               Agent-deck profile
  --apply                        Remove executor/reviewer sessions after archiving
  -h, --help                     Show help

Outputs:
  - Writes task archive file:
      <artifact-root>/<task_id>/session-archive-<task_id>.json
  - Writes catalog copy:
      <artifact-root>/session-archives/<task_id>.json
  - Updates catalog index:
      <artifact-root>/session-archives/index.json
  - Updates latest pointer copy:
      <artifact-root>/session-archives/latest.json
  - Prints summary lines for archive/remove results.

Notes:
  - Default mode is archive-only (no deletion).
  - Provider resume IDs are read from agent-deck state DB (`instances.tool_data`).
  - If expected provider ID is missing in DB, fallback reads `~/.agent-deck/hooks/<instance_id>.json`.
  - For Codex sessions, if DB/hook still has no ID, fallback probes live process open files from the session tmux pane process tree.
  - Archive always includes raw `session show --json` payload for future recovery.
  - Use catalog files for quick lookup without navigating per-task directories.
  - Deletion guard is tool-aware in --apply mode:
    - codex/claude/gemini/opencode sessions require matching provider session id.
    - other tools (for example shell) are not blocked by provider-id guard.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

task_id=""
planner_session_ref="planner"
executor_session_ref=""
reviewer_session_ref=""
artifact_root=".agent-artifacts"
profile=""
apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id) task_id="${2:-}"; shift 2 ;;
    --planner-session) planner_session_ref="${2:-}"; shift 2 ;;
    --executor-session) executor_session_ref="${2:-}"; shift 2 ;;
    --reviewer-session) reviewer_session_ref="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --apply) apply=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$task_id" ]] || die "--task-id is required"

if [[ -z "$executor_session_ref" ]]; then
  executor_session_ref="executor-${task_id}"
fi
if [[ -z "$reviewer_session_ref" ]]; then
  reviewer_session_ref="reviewer-${task_id}"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

resolve_profile_name() {
  if [[ -n "$profile" ]]; then
    echo "$profile"
    return 0
  fi

  local current
  local detected_profile=""
  current="$(agent-deck session current --json 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    detected_profile="$(jq -r '.profile // empty' <<<"$current" 2>/dev/null || true)"
    if [[ -n "$detected_profile" ]]; then
      echo "$detected_profile"
      return 0
    fi
  fi

  echo "default"
}

extract_provider_resume_ids() {
  local session_id="$1"
  local db_path="$2"
  local tool_data
  local extracted

  if [[ -z "$session_id" || -z "$db_path" || ! -f "$db_path" ]]; then
    echo "{}"
    return 0
  fi

  tool_data="$(sqlite3 -batch -noheader "$db_path" "SELECT tool_data FROM instances WHERE id = '$session_id' LIMIT 1;" 2>/dev/null || true)"
  if [[ -z "$tool_data" ]]; then
    echo "{}"
    return 0
  fi

  extracted="$(jq -c '
    if type != "object" then
      {}
    else
      {
        claude_session_id: .claude_session_id,
        gemini_session_id: .gemini_session_id,
        opencode_session_id: .opencode_session_id,
        codex_session_id: .codex_session_id,
        claude_detected_at: .claude_detected_at,
        gemini_detected_at: .gemini_detected_at,
        opencode_detected_at: .opencode_detected_at,
        codex_detected_at: .codex_detected_at
      }
      | with_entries(select(.value != null and .value != ""))
    end
  ' <<<"$tool_data" 2>/dev/null || true)"

  if [[ -z "$extracted" ]]; then
    echo "{}"
    return 0
  fi

  if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$extracted"; then
    jq -c '.' <<<"$extracted"
  else
    echo "{}"
  fi
}

extract_provider_resume_ids_from_hook_file() {
  local session_id="$1"
  local tool_name="$2"
  local hook_file
  local expected_key
  local detected_key
  local hook_session_id
  local hook_ts

  if [[ -z "$session_id" ]]; then
    echo "{}"
    return 0
  fi

  expected_key="$(expected_provider_key_for_tool "$tool_name")"
  if [[ -z "$expected_key" ]]; then
    echo "{}"
    return 0
  fi

  hook_file="$HOME/.agent-deck/hooks/${session_id}.json"
  if [[ ! -f "$hook_file" ]]; then
    echo "{}"
    return 0
  fi

  hook_session_id="$(jq -r '.session_id // empty' "$hook_file" 2>/dev/null || true)"
  if [[ -z "$hook_session_id" ]]; then
    echo "{}"
    return 0
  fi

  hook_ts="$(jq -r '.ts // empty' "$hook_file" 2>/dev/null || true)"
  detected_key="${expected_key%_session_id}_detected_at"

  jq -nc \
    --arg expected_key "$expected_key" \
    --arg detected_key "$detected_key" \
    --arg hook_session_id "$hook_session_id" \
    --arg hook_ts "$hook_ts" \
    '{
      ($expected_key): $hook_session_id
    } + (
      if ($hook_ts | test("^[0-9]+$")) then
        {($detected_key): ($hook_ts | tonumber)}
      else
        {}
      end
    )'
}

has_provider_resume_session_id() {
  local provider_resume_ids="$1"
  jq -e '
    (.codex_session_id // "") != "" or
    (.claude_session_id // "") != "" or
    (.gemini_session_id // "") != "" or
    (.opencode_session_id // "") != ""
  ' >/dev/null 2>&1 <<<"$provider_resume_ids"
}

expected_provider_key_for_tool() {
  local tool_name="$1"
  case "$tool_name" in
    codex) echo "codex_session_id" ;;
    claude|claude-code) echo "claude_session_id" ;;
    gemini|gemini-cli) echo "gemini_session_id" ;;
    opencode) echo "opencode_session_id" ;;
    *) echo "" ;;
  esac
}

has_expected_provider_resume_id() {
  local provider_resume_ids="$1"
  local expected_key="$2"
  if [[ -z "$expected_key" ]]; then
    return 0
  fi
  jq -e --arg expected_key "$expected_key" '(.[$expected_key] // "") != ""' >/dev/null 2>&1 <<<"$provider_resume_ids"
}

extract_codex_session_id_from_path() {
  local path="$1"
  local normalized="${path% (deleted)}"
  if [[ "$normalized" != *"/.codex/sessions/"* || "$normalized" != *"rollout-"* || "$normalized" != *".jsonl"* ]]; then
    return 1
  fi
  grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$normalized" | head -n1
}

is_likely_codex_process_pid() {
  local pid="$1"
  local args
  args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  [[ "$args" =~ [Cc][Oo][Dd][Ee][Xx] ]]
}

extract_codex_session_id_from_proc_fd() {
  local pid="$1"
  local fd_dir="/proc/${pid}/fd"
  local fd target sid
  [[ -d "$fd_dir" ]] || return 1
  for fd in "$fd_dir"/*; do
    [[ -e "$fd" ]] || continue
    target="$(readlink "$fd" 2>/dev/null || true)"
    [[ -n "$target" ]] || continue
    sid="$(extract_codex_session_id_from_path "$target" || true)"
    if [[ -n "$sid" ]]; then
      echo "$sid"
      return 0
    fi
  done
  return 1
}

extract_codex_session_id_from_lsof_pid() {
  local pid="$1"
  local sid
  command -v lsof >/dev/null 2>&1 || return 1
  while IFS= read -r line; do
    sid="$(extract_codex_session_id_from_path "$line" || true)"
    if [[ -n "$sid" ]]; then
      echo "$sid"
      return 0
    fi
  done < <(lsof -p "$pid" 2>/dev/null || true)
  return 1
}

collect_process_tree_pids() {
  local root_pid="$1"
  local -a queue all
  local pid child line
  queue=("$root_pid")
  all=()
  while [[ ${#queue[@]} -gt 0 ]]; do
    pid="${queue[0]}"
    queue=("${queue[@]:1}")
    all+=("$pid")
    while IFS= read -r line; do
      child="$(tr -d '[:space:]' <<<"$line")"
      [[ "$child" =~ ^[0-9]+$ ]] || continue
      queue+=("$child")
    done < <(pgrep -P "$pid" 2>/dev/null || true)
  done
  printf '%s\n' "${all[@]}"
}

extract_codex_session_id_from_tmux_process_tree() {
  local tmux_session_name="$1"
  local pane_pid pid sid
  command -v tmux >/dev/null 2>&1 || return 1
  pane_pid="$(tmux list-panes -t "$tmux_session_name" -F '#{pane_pid}' 2>/dev/null | head -n1 | tr -d '[:space:]')"
  [[ "$pane_pid" =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    is_likely_codex_process_pid "$pid" || continue
    sid="$(extract_codex_session_id_from_proc_fd "$pid" || true)"
    if [[ -z "$sid" ]]; then
      sid="$(extract_codex_session_id_from_lsof_pid "$pid" || true)"
    fi
    if [[ -n "$sid" ]]; then
      echo "$sid"
      return 0
    fi
  done < <(collect_process_tree_pids "$pane_pid")
  return 1
}

extract_provider_resume_ids_from_process_probe() {
  local tool_name="$1"
  local tmux_session_name="$2"
  local expected_key sid detected_key now_ts

  expected_key="$(expected_provider_key_for_tool "$tool_name")"
  [[ "$expected_key" == "codex_session_id" ]] || { echo "{}"; return 0; }
  [[ -n "$tmux_session_name" ]] || { echo "{}"; return 0; }

  sid="$(extract_codex_session_id_from_tmux_process_tree "$tmux_session_name" || true)"
  if [[ -z "$sid" ]]; then
    echo "{}"
    return 0
  fi

  detected_key="${expected_key%_session_id}_detected_at"
  now_ts="$(date +%s)"
  jq -nc \
    --arg expected_key "$expected_key" \
    --arg detected_key "$detected_key" \
    --arg sid "$sid" \
    --arg now_ts "$now_ts" \
    '{
      ($expected_key): $sid
    } + (
      if ($now_ts | test("^[0-9]+$")) then
        {($detected_key): ($now_ts | tonumber)}
      else
        {}
      end
    )'
}

artifact_dir="${artifact_root%/}/${task_id}"
archive_file="${artifact_dir}/session-archive-${task_id}.json"
catalog_dir="${artifact_root%/}/session-archives"
catalog_file="${catalog_dir}/${task_id}.json"
catalog_index_file="${catalog_dir}/index.json"
latest_catalog_file="${catalog_dir}/latest.json"
mkdir -p "$artifact_dir"
mkdir -p "$catalog_dir"

profile_name="$(resolve_profile_name)"
state_db_path="$HOME/.agent-deck/profiles/${profile_name}/state.db"
if [[ ! -f "$state_db_path" ]]; then
  state_db_path=""
fi

planner_shown="$(ad session show "$planner_session_ref" --json 2>/dev/null || true)"
planner_session_id=""
if [[ -n "$planner_shown" ]]; then
  planner_session_id="$(jq -r '.id // empty' <<<"$planner_shown")"
fi

entries_file="$(mktemp)"
blocked_delete_count=0

process_session() {
  local role="$1"
  local ref="$2"
  local shown
  local entry
  local session_id
  local provider_resume_ids
  local provider_resume_ids_db="{}"
  local provider_resume_ids_hook="{}"
  local provider_resume_ids_probe="{}"
  local provider_resume_source="state_db_tool_data"
  local has_provider_resume_id=false
  local tool_name=""
  local tmux_session_name=""
  local expected_provider_key=""
  local provider_guard_required=false
  local provider_guard_passed=false
  local delete_status
  local deleted=false
  local delete_block_reason=""

  shown="$(ad session show "$ref" --json 2>/dev/null || true)"
  session_id="$(jq -r 'if type == "object" then .id // empty else empty end' <<<"$shown" 2>/dev/null || true)"
  tool_name="$(jq -r 'if type == "object" then .tool // "" else "" end' <<<"$shown" 2>/dev/null || true)"
  tmux_session_name="$(jq -r 'if type == "object" then .tmux_session // "" else "" end' <<<"$shown" 2>/dev/null || true)"
  expected_provider_key="$(expected_provider_key_for_tool "$tool_name")"

  provider_resume_ids_db="$(extract_provider_resume_ids "$session_id" "$state_db_path")"
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$provider_resume_ids_db"; then
    provider_resume_ids_db="{}"
  fi
  provider_resume_ids="$provider_resume_ids_db"

  if [[ -n "$expected_provider_key" ]]; then
    if ! has_expected_provider_resume_id "$provider_resume_ids" "$expected_provider_key"; then
      provider_resume_ids_hook="$(extract_provider_resume_ids_from_hook_file "$session_id" "$tool_name")"
      if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$provider_resume_ids_hook"; then
        provider_resume_ids_hook="{}"
      fi
      if has_expected_provider_resume_id "$provider_resume_ids_hook" "$expected_provider_key"; then
        provider_resume_ids="$(jq -cn --argjson db "$provider_resume_ids_db" --argjson hook "$provider_resume_ids_hook" '$db + $hook')"
        if has_provider_resume_session_id "$provider_resume_ids_db"; then
          provider_resume_source="state_db_tool_data+hook_status_file"
        else
          provider_resume_source="hook_status_file"
        fi
      fi
    fi

    if ! has_expected_provider_resume_id "$provider_resume_ids" "$expected_provider_key"; then
      provider_resume_ids_probe="$(extract_provider_resume_ids_from_process_probe "$tool_name" "$tmux_session_name")"
      if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$provider_resume_ids_probe"; then
        provider_resume_ids_probe="{}"
      fi
      if has_expected_provider_resume_id "$provider_resume_ids_probe" "$expected_provider_key"; then
        provider_resume_ids="$(jq -cn --argjson prior "$provider_resume_ids" --argjson probe "$provider_resume_ids_probe" '$prior + $probe')"
        if [[ "$provider_resume_source" == "state_db_tool_data" ]]; then
          provider_resume_source="process_open_files"
        else
          provider_resume_source="${provider_resume_source}+process_open_files"
        fi
      fi
    fi
  fi

  if has_provider_resume_session_id "$provider_resume_ids"; then
    has_provider_resume_id=true
  fi

  if [[ -n "$expected_provider_key" ]]; then
    provider_guard_required=true
  fi
  if has_expected_provider_resume_id "$provider_resume_ids" "$expected_provider_key"; then
    provider_guard_passed=true
  fi

  if [[ -z "$shown" || -z "$session_id" ]]; then
    delete_status="not_found"
    entry="$(jq -nc \
      --arg role "$role" \
      --arg ref "$ref" \
      --arg raw_show "$shown" \
      --argjson provider_resume_ids "$provider_resume_ids" \
      --argjson has_provider_resume_id "$has_provider_resume_id" \
      --arg tool_name "$tool_name" \
      --arg expected_provider_key "$expected_provider_key" \
      --argjson provider_guard_required "$provider_guard_required" \
      --argjson provider_guard_passed "$provider_guard_passed" \
      --arg provider_resume_source "$provider_resume_source" \
      --arg delete_status "$delete_status" \
      --arg delete_block_reason "$delete_block_reason" \
      --argjson apply_flag "$apply" \
      '{
        role: $role,
        ref: $ref,
        found: false,
        tool: (if $tool_name == "" then null else $tool_name end),
        provider_resume_ids: $provider_resume_ids,
        has_provider_resume_id: $has_provider_resume_id,
        provider_guard_expected_key: (if $expected_provider_key == "" then null else $expected_provider_key end),
        provider_guard_required: $provider_guard_required,
        provider_guard_passed: $provider_guard_passed,
        provider_resume_source: $provider_resume_source,
        raw_session_show: (if $raw_show == "" then null else $raw_show end),
        delete_applied: ($apply_flag == 1),
        deleted: false,
        delete_status: $delete_status,
        delete_block_reason: (if $delete_block_reason == "" then null else $delete_block_reason end)
      }'
    )"
    echo "$entry" >>"$entries_file"
    echo "session role=${role} ref=${ref} found=0 delete_status=${delete_status}"
    return 0
  fi

  if (( apply )); then
    if [[ "$provider_guard_required" == "true" && "$provider_guard_passed" != "true" ]]; then
      delete_status="blocked_missing_provider_session_id"
      delete_block_reason="missing_provider_session_id"
      blocked_delete_count=$((blocked_delete_count + 1))
      echo "manual_close_required role=${role} ref=${ref} id=${session_id} tool=${tool_name} expected_key=${expected_provider_key} reason=${delete_block_reason}"
      echo "manual_close_suggestion command='agent-deck remove ${session_id}'"
    elif [[ -n "$session_id" ]] && ad remove "$session_id" >/dev/null 2>&1; then
        delete_status="deleted"
        deleted=true
    else
      delete_status="delete_failed"
    fi
  else
    delete_status="skipped_no_apply"
  fi

  entry="$(jq -nc \
    --arg role "$role" \
    --arg ref "$ref" \
    --argjson shown "$shown" \
    --argjson provider_resume_ids "$provider_resume_ids" \
    --argjson has_provider_resume_id "$has_provider_resume_id" \
    --arg expected_provider_key "$expected_provider_key" \
    --argjson provider_guard_required "$provider_guard_required" \
    --argjson provider_guard_passed "$provider_guard_passed" \
    --arg provider_resume_source "$provider_resume_source" \
    --arg delete_status "$delete_status" \
    --arg delete_block_reason "$delete_block_reason" \
    --argjson apply_flag "$apply" \
    --argjson deleted "$deleted" \
    '{
      role: $role,
      ref: $ref,
      found: true,
      agent_deck_session_id: ($shown.id // empty),
      session_title: ($shown.title // empty),
      tool: ($shown.tool // empty),
      status: ($shown.status // empty),
      group: ($shown.group // empty),
      path: ($shown.path // empty),
      provider_resume_ids: $provider_resume_ids,
      has_provider_resume_id: $has_provider_resume_id,
      provider_guard_expected_key: (if $expected_provider_key == "" then null else $expected_provider_key end),
      provider_guard_required: $provider_guard_required,
      provider_guard_passed: $provider_guard_passed,
      provider_resume_source: $provider_resume_source,
      session_show: $shown,
      delete_applied: ($apply_flag == 1),
      deleted: $deleted,
      delete_status: $delete_status,
      delete_block_reason: (if $delete_block_reason == "" then null else $delete_block_reason end)
    }'
  )"

  echo "$entry" >>"$entries_file"
  echo "session role=${role} ref=${ref} found=1 id=${session_id} delete_status=${delete_status}"
}

process_session "executor" "$executor_session_ref"
process_session "reviewer" "$reviewer_session_ref"

sessions_json="$(jq -s '.' "$entries_file")"
archived_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mode="$([[ "$apply" -eq 1 ]] && echo "archive_and_remove" || echo "archive_only")"

jq -n \
  --arg task_id "$task_id" \
  --arg archived_at "$archived_at" \
  --arg planner_session_ref "$planner_session_ref" \
  --arg planner_session_id "$planner_session_id" \
  --arg profile_name "$profile_name" \
  --arg state_db_path "$state_db_path" \
  --arg mode "$mode" \
  --argjson sessions "$sessions_json" \
  '{
    task_id: $task_id,
    archived_at: $archived_at,
    mode: $mode,
    planner_session_ref: $planner_session_ref,
    planner_session_id: (if $planner_session_id == "" then null else $planner_session_id end),
    profile_name: $profile_name,
    state_db_path: (if $state_db_path == "" then null else $state_db_path end),
    sessions: $sessions
  }' >"$archive_file"

cp "$archive_file" "$catalog_file"
cp "$archive_file" "$latest_catalog_file"

index_entry="$(jq -n \
  --arg task_id "$task_id" \
  --arg archived_at "$archived_at" \
  --arg mode "$mode" \
  --arg archive_file "$archive_file" \
  --arg catalog_file "$catalog_file" \
  --arg planner_session_id "$planner_session_id" \
  --arg profile_name "$profile_name" \
  '{
    task_id: $task_id,
    archived_at: $archived_at,
    mode: $mode,
    archive_file: $archive_file,
    catalog_file: $catalog_file,
    planner_session_id: (if $planner_session_id == "" then null else $planner_session_id end),
    profile_name: $profile_name
  }')"

tmp_index="$(mktemp)"
if [[ -f "$catalog_index_file" ]]; then
  if jq -e 'type == "array"' "$catalog_index_file" >/dev/null 2>&1; then
    jq -c \
      --arg task_id "$task_id" \
      --argjson entry "$index_entry" \
      'map(select(.task_id != $task_id)) + [$entry] | sort_by(.archived_at)' \
      "$catalog_index_file" >"$tmp_index"
  else
    jq -nc --argjson entry "$index_entry" '[$entry]' >"$tmp_index"
  fi
else
  jq -nc --argjson entry "$index_entry" '[$entry]' >"$tmp_index"
fi
mv "$tmp_index" "$catalog_index_file"

rm -f "$entries_file"

echo "archive_ok file=${archive_file} mode=$([[ "$apply" -eq 1 ]] && echo apply || echo preview)"
echo "catalog_ok file=${catalog_file} latest=${latest_catalog_file} index=${catalog_index_file}"

if (( blocked_delete_count > 0 )); then
  echo "delete_guard_blocked count=${blocked_delete_count} reason=missing_provider_session_id"
  echo "delete_guard_action=manual_close_required"
  exit 3
fi
