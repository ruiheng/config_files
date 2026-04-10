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
delete_failed=0

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

  delete_status="skipped_no_apply"
  deleted=false
  if (( apply )); then
    if ad remove "$session_id" >/dev/null 2>&1; then
      delete_status="deleted"
      deleted=true
    else
      delete_status="delete_failed"
      delete_failed=1
    fi
  fi

  jq -nc \
    --argjson shown "$shown" \
    --arg delete_status "$delete_status" \
    --argjson deleted "$deleted" \
    --argjson delete_applied "$apply" \
    '{
      found: true,
      session_show: $shown,
      delete_applied: ($delete_applied == 1),
      deleted: $deleted,
      delete_status: $delete_status
    }' >>"$entries_file"
done <<<"$session_ids"

sessions_json="$(jq -s '.' "$entries_file")"
rm -f "$entries_file"

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
if (( apply )); then
  remaining_after_delete="$(ad list --json 2>/dev/null | jq -r --arg planner_group "$planner_group" '
    [
      .[]
      | select(
          (.group // "") == $planner_group
          or ((.group // "") | startswith($planner_group + "/"))
        )
    ] | length
  ' 2>/dev/null || echo -1)"

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

if (( delete_failed != 0 )); then
  exit 3
fi
