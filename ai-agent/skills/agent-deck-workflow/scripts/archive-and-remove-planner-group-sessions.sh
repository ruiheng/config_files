#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Archive and optionally remove every agent-deck session in one planner group, then delete the group.

Usage:
  archive-and-remove-planner-group-sessions.sh [options]

Options:
  --planner-group <path>         Required planner group path
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
artifact_root=".agent-artifacts"
profile=""
apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-group) planner_group="${2:-}"; shift 2 ;;
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
declare -A remaining parent_session_id_of
ordered_ids=()

cleanup_tmp() {
  rm -f "$entries_file"
  rm -rf "$session_cache_dir"
}
trap cleanup_tmp EXIT

while IFS= read -r session_id; do
  [[ -n "$session_id" ]] || continue
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
    continue
  fi

  printf '%s\n' "$shown" >"${session_cache_dir}/${session_id}.json"
  remaining["$session_id"]=1
  parent_session_id_of["$session_id"]="$(jq -r '.parent_session_id // empty' <<<"$shown" 2>/dev/null || true)"
done <<<"$session_ids"

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
    if ad group delete "$planner_group" >/dev/null 2>&1; then
      group_delete_status="deleted"
    else
      group_delete_status="delete_failed"
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
fi

if (( delete_failed != 0 )); then
  exit 3
fi
