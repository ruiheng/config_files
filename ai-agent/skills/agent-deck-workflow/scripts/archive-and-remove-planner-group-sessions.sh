#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Archive and optionally remove every agent-deck session in one planner group, then delete the group.

Usage:
  archive-and-remove-planner-group-sessions.sh [options]

Options:
  --planner-group <path>         Required planner group path
  --planner-session-id <id>      Optional planner session id to delete even if it is outside planner_group
  --artifact-root <path>         Artifact root (default: .agent-artifacts)
  --profile <name>               Optional agent-deck profile
  --apply                        Remove sessions and delete the group after archiving
  -h, --help                     Show help

Outputs:
  - Writes planner-group archive file under <artifact-root>/planner-groups/
  - Prints summary lines for archive/remove/group-delete results

Exit codes:
  0: archive complete; deletes/group delete also succeeded when --apply is set
  2: usage/runtime validation error
  3: archive written, but one or more deletes/group delete failed
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

planner_group=""
planner_session_id=""
artifact_root=".agent-artifacts"
profile=""
apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-group) planner_group="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_id="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --apply) apply=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$planner_group" ]] || die "--planner-group is required"

command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

group_exists_in_tree() {
  local group_path="$1"
  local groups_json="$2"

  [[ -n "$groups_json" ]] || return 1
  jq -e --arg group_path "$group_path" '
    def group_tree:
      . as $group
      | $group, (($group.children // [])[] | group_tree);

    any(.groups[]? | group_tree; (.path // "") == $group_path)
  ' <<<"$groups_json" >/dev/null 2>&1
}

list_json="$(ad list --json 2>/dev/null || true)"
[[ -n "$list_json" ]] || die "failed to list agent-deck sessions"

session_ids="$(jq -r --arg planner_group "$planner_group" '
  .[]
  | select(
      (.group // "") == $planner_group
      or ((.group // "") | startswith($planner_group + "/"))
    )
  | .id
' <<<"$list_json" 2>/dev/null || true)"

safe_group="$(tr '/ ' '__' <<<"$planner_group")"
archive_dir="${artifact_root%/}/planner-groups/${safe_group}"
archive_file="${archive_dir}/session-archive-$(date -u +%Y%m%dT%H%M%SZ).json"
mkdir -p "$archive_dir"

entries_file="$(mktemp)"
session_cache_dir="$(mktemp -d)"
delete_failed=0
# Under `set -u`, `declare -A name` is still treated as unbound until the first
# assignment, so explicitly initialize the maps before checking their size.
declare -A remaining=() parent_session_id_of=() queued_session_ids=()
ordered_ids=()

cleanup_tmp() {
  rm -f "$entries_file"
  rm -rf "$session_cache_dir"
}
trap cleanup_tmp EXIT

queue_session_for_cleanup() {
  local session_id="${1:-}"
  local shown=""

  [[ -n "$session_id" ]] || return 0
  [[ -z "${queued_session_ids[$session_id]:-}" ]] || return 0
  queued_session_ids["$session_id"]=1

  shown="$(ad session show "$session_id" --json 2>/dev/null || true)"
  if [[ -z "$shown" ]]; then
    jq -nc \
      --arg session_id "$session_id" \
      '{
        found: false,
        session_id: $session_id,
        delete_applied: false,
        deleted: false,
        delete_status: "not_found"
      }' >>"$entries_file"
    return 0
  fi

  printf '%s\n' "$shown" >"${session_cache_dir}/${session_id}.json"
  remaining["$session_id"]=1
  parent_session_id_of["$session_id"]="$(jq -r '.parent_session_id // empty' <<<"$shown" 2>/dev/null || true)"
}

while IFS= read -r session_id; do
  queue_session_for_cleanup "$session_id"
done <<<"$session_ids"

# The planner session is part of planner-run cleanup even when it was created in
# a different group, so accept it as an explicit extra delete target.
queue_session_for_cleanup "$planner_session_id"

while ((${#remaining[@]} > 0)); do
  progressed=0
  for session_id in "${!remaining[@]}"; do
    has_child=0
    for other_id in "${!remaining[@]}"; do
      if [[ "$other_id" != "$session_id" ]] && [[ "${parent_session_id_of[$other_id]:-}" == "$session_id" ]]; then
        has_child=1
        break
      fi
    done
    if (( has_child == 0 )); then
      ordered_ids+=("$session_id")
      unset 'remaining[$session_id]'
      progressed=1
    fi
  done
  if (( progressed == 0 )); then
    for session_id in "${!remaining[@]}"; do
      ordered_ids+=("$session_id")
      unset 'remaining[$session_id]'
    done
  fi
done

for session_id in "${ordered_ids[@]}"; do
  shown="$(cat "${session_cache_dir}/${session_id}.json")"
  delete_status="skipped_no_apply"
  deleted=false
  delete_error=""
  if (( apply )); then
    if remove_output="$(ad remove "$session_id" 2>&1)"; then
      delete_status="deleted"
      deleted=true
    else
      delete_status="delete_failed"
      delete_error="${remove_output}"
      delete_failed=1
    fi
  fi

  jq -nc \
    --argjson shown "$shown" \
    --arg delete_status "$delete_status" \
    --arg delete_error "$delete_error" \
    --argjson deleted "$deleted" \
    --argjson delete_applied "$apply" \
    '{
      found: true,
      session_show: $shown,
      delete_applied: ($delete_applied == 1),
      deleted: $deleted,
      delete_status: $delete_status,
      delete_error: (if $delete_error == "" then null else $delete_error end)
    }' >>"$entries_file"
done

sessions_json="$(jq -s '.' "$entries_file")"

jq -n \
  --arg planner_group "$planner_group" \
  --arg archived_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg mode "$([[ "$apply" -eq 1 ]] && echo archive_and_remove || echo archive_only)" \
  --argjson sessions "$sessions_json" \
  '{
    planner_group: $planner_group,
    archived_at: $archived_at,
    mode: $mode,
    sessions: $sessions
  }' >"$archive_file"

echo "planner_group_archive_ok file=${archive_file} mode=$([[ "$apply" -eq 1 ]] && echo apply || echo preview)"

group_delete_status="skipped_no_apply"
group_delete_error=""
group_delete_exit_code=""
group_exists_after_delete=""
remaining_sessions_json="[]"
if (( apply )); then
  remaining_sessions_json="$(ad list --json 2>/dev/null | jq -c --arg planner_group "$planner_group" '
    [
      .[]
      | select(
          (.group // "") == $planner_group
          or ((.group // "") | startswith($planner_group + "/"))
        )
      | {
          id,
          title: (.title // null),
          group: (.group // null),
          parent_session_id: (.parent_session_id // null)
        }
    ]
  ' 2>/dev/null || echo '[]')"
  remaining_after_delete="$(jq -r 'length' <<<"$remaining_sessions_json" 2>/dev/null || echo -1)"

  if (( remaining_after_delete == 0 )); then
    group_list_json="$(ad group list --json 2>/dev/null || true)"
    if [[ -n "$group_list_json" ]]; then
      if group_exists_in_tree "$planner_group" "$group_list_json"; then
        group_exists_after_delete=1
      else
        group_exists_after_delete=0
      fi
    fi

    # Session removal may already prune the empty planner group, so an absent
    # group here means cleanup is complete rather than a failure.
    if [[ "$group_exists_after_delete" == "0" ]]; then
      group_delete_status="already_absent"
    elif group_delete_output="$(ad group delete "$planner_group" 2>&1)"; then
      group_delete_status="deleted"
    else
      group_delete_exit_code="$?"
      group_delete_status="delete_failed"
      group_delete_error="$group_delete_output"
      delete_failed=1
    fi
  else
    group_delete_status="blocked_nonempty"
    delete_failed=1
  fi
fi

echo "planner_group_cleanup planner_group=${planner_group} group_delete_status=${group_delete_status}"
if (( apply )) && (( delete_failed != 0 )); then
  jq -r '
    .[]
    | select(.delete_status == "delete_failed")
    | "planner_group_delete_failed session_id=\(.session_show.id // "unknown") title=\(.session_show.title // "unknown") parent_session_id=\(.session_show.parent_session_id // "") error=\(.delete_error // "unknown")"
  ' <<<"$sessions_json"
  if [[ "$remaining_sessions_json" != "[]" ]]; then
    jq -r '
      .[]
      | "planner_group_remaining session_id=\(.id) title=\(.title // "unknown") group=\(.group // "") parent_session_id=\(.parent_session_id // "")"
    ' <<<"$remaining_sessions_json"
  fi
  if [[ -n "$group_delete_error" ]]; then
    echo "planner_group_group_delete_failed planner_group=${planner_group} exit_code=${group_delete_exit_code:-unknown} error=${group_delete_error}"
  fi
fi

if (( delete_failed != 0 )); then
  exit 3
fi
