#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Archive and optionally remove one planner cleanup scope.

Usage:
  archive-and-remove-planner-group-sessions.sh [options]

Options:
  --planner-session-id <id>      Planner session id; required cleanup scope source
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

planner_session_id=""
artifact_root=".agent-artifacts"
profile=""
apply=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-session-id) planner_session_id="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --profile) profile="${2:-}"; shift 2 ;;
    --apply) apply=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

if [[ -z "$planner_session_id" ]]; then
  die "pass --planner-session-id"
fi

command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

ad() {
  if [[ -n "$profile" ]]; then
    agent-deck -p "$profile" "$@"
  else
    agent-deck "$@"
  fi
}

derive_lane_group_from_session_json() {
  local session_json="${1:-}"
  local group_path=""

  [[ -n "$session_json" ]] || return 0
  group_path="$(jq -r '.group // ""' <<<"$session_json" 2>/dev/null || true)"
  if [[ -n "$group_path" ]]; then
    printf '%s\n' "$group_path"
  fi
  return 0
}

list_archive_files() {
  local archive_root=""

  archive_root="${artifact_root%/}/planner-groups"
  {
    find "$archive_dir" -maxdepth 1 -name 'session-archive-*.json' -type f 2>/dev/null || true
    if [[ -d "$archive_root" ]]; then
      find "$archive_root" -mindepth 2 -maxdepth 2 -name 'session-archive-*.json' -type f 2>/dev/null || true
    fi
  } | sort -u
}

resolve_cleanup_group_scope() {
  cleanup_group_scope=""
  cleanup_group_scope_source=""
  scope_warning=""

  if [[ -n "$planner_live_json" ]]; then
    cleanup_group_scope="$(derive_lane_group_from_session_json "$planner_live_json")"
    if [[ -n "$cleanup_group_scope" ]]; then
      cleanup_group_scope_source="live_planner"
      return 0
    fi
  fi

  if [[ -n "$planner_live_json" ]]; then
    scope_warning="live planner session has no group; planner lane cleanup scope unavailable"
  else
    scope_warning="planner session not found; planner lane cleanup scope unavailable"
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

group_is_empty_leaf() {
  local group_path="$1"
  local groups_json="$2"

  [[ -n "$groups_json" ]] || return 1
  jq -e --arg group_path "$group_path" '
    def group_tree:
      . as $group
      | $group, (($group.children // [])[] | group_tree);

    first(.groups[]? | group_tree | select((.path // "") == $group_path))
    | ((.session_count // 0) == 0 and ((.children // []) | length) == 0)
  ' <<<"$groups_json" >/dev/null 2>&1
}

collect_archived_scope_groups() {
  local sessions_json="$1"
  local group_path current_group
  local source_groups_json

  [[ -n "$cleanup_group_scope" ]] || return 0

  source_groups_json="$(
    {
      printf '%s\n' "$cleanup_group_scope"
      jq -r '
        .[]
        | select(.found == true)
        | (.session_show.group // empty)
        | select(length > 0)
      ' <<<"$sessions_json" 2>/dev/null || true

      list_archive_files \
        | while IFS= read -r archive_path; do
            [[ -f "$archive_path" ]] || continue
            jq -r '
              .sessions[]?
              | select(.found == true)
              | (.session_show.group // empty)
              | select(length > 0)
            ' "$archive_path" 2>/dev/null || true
          done
    } | jq -Rcs 'split("\n") | map(select(length > 0))'
  )"

  jq -r '.[]' <<<"$source_groups_json" 2>/dev/null \
    | while IFS= read -r group_path; do
        [[ -n "$group_path" ]] || continue
        if [[ "$group_path" != "$cleanup_group_scope" && "$group_path" != "$cleanup_group_scope"/* ]]; then
          continue
        fi
        current_group="$group_path"
        while :; do
          printf '%s\n' "$current_group"
          [[ "$current_group" == "$cleanup_group_scope" ]] && break
          current_group="${current_group%/*}"
          [[ -n "$current_group" ]] || break
        done
      done \
    | jq -Rrs -r 'split("\n") | map(select(length > 0)) | unique | sort_by(length) | reverse[]'
}

delete_empty_scope_groups() {
  local sessions_json="$1"
  local group_path delete_output current_group_list_json

  [[ -n "$cleanup_group_scope" ]] || return 0

  while IFS= read -r group_path; do
    [[ -n "$group_path" ]] || continue
    current_group_list_json="$(ad group list --json 2>/dev/null || true)"
    if [[ -z "$current_group_list_json" ]]; then
      derived_group_warning="failed to inspect group tree before inferred cleanup for group=${group_path}"
      return 0
    fi
    if ! group_exists_in_tree "$group_path" "$current_group_list_json"; then
      continue
    fi
    if ! group_is_empty_leaf "$group_path" "$current_group_list_json"; then
      continue
    fi
    if delete_output="$(ad group delete "$group_path" 2>&1)"; then
      derived_group_delete_count=$((derived_group_delete_count + 1))
    else
      derived_group_warning="group=${group_path} error=${delete_output}"
      return 0
    fi
  done < <(collect_archived_scope_groups "$sessions_json")
}

build_session_inventory_json() {
  local raw_list tmp_dir ids_file inventory_file session_id shown

  raw_list="$(ad list --json 2>/dev/null || true)"
  if [[ -z "$raw_list" ]]; then
    echo "ERROR: failed to list agent-deck sessions" >&2
    return 1
  fi
  if ! jq -e 'type == "array"' <<<"$raw_list" >/dev/null 2>&1; then
    echo "ERROR: agent-deck session list is not a JSON array" >&2
    return 1
  fi

  tmp_dir="$(mktemp -d)"
  ids_file="${tmp_dir}/ids"
  inventory_file="${tmp_dir}/inventory.jsonl"

  if ! jq -r '.[] | .id // empty' <<<"$raw_list" >"$ids_file"; then
    rm -rf "$tmp_dir"
    echo "ERROR: failed to extract agent-deck session ids" >&2
    return 1
  fi

  : >"$inventory_file"
  while IFS= read -r session_id; do
    [[ -n "$session_id" ]] || continue
    shown="$(ad session show "$session_id" --json 2>/dev/null || true)"
    if [[ -z "$shown" ]] || ! jq -e '.id // empty' <<<"$shown" >/dev/null 2>&1; then
      rm -rf "$tmp_dir"
      echo "ERROR: failed to inspect listed agent-deck session: ${session_id}" >&2
      return 1
    fi
    printf '%s\n' "$shown" >>"$inventory_file"
  done <"$ids_file"

  if ! jq -s '.' "$inventory_file"; then
    rm -rf "$tmp_dir"
    echo "ERROR: failed to build agent-deck session inventory" >&2
    return 1
  fi

  rm -rf "$tmp_dir"
}

safe_archive_key="session_$(tr '/ ' '__' <<<"$planner_session_id")"
archive_dir="${artifact_root%/}/planner-groups/${safe_archive_key}"
archive_file="${archive_dir}/session-archive-$(date -u +%Y%m%dT%H%M%SZ).json"
mkdir -p "$archive_dir"

planner_live_json=""
cleanup_group_scope=""
cleanup_group_scope_source=""
scope_warning=""

if [[ -n "$planner_session_id" ]]; then
  planner_live_json="$(ad session show "$planner_session_id" --json 2>/dev/null || true)"
  if ! jq -e '.id // empty' <<<"$planner_live_json" >/dev/null 2>&1; then
    planner_live_json=""
  fi
fi

resolve_cleanup_group_scope

session_inventory_json="$(build_session_inventory_json)" || die "failed to build agent-deck session inventory"

entries_file="$(mktemp)"
session_cache_dir="$(mktemp -d)"
delete_failed=0
# Under `set -u`, `declare -A name` is still treated as unbound until the first
# assignment, so explicitly initialize the maps before checking their size.
declare -A remaining=() parent_session_id_of=() queued_session_ids=() traversed_session_ids=()
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

queue_descendants_for_cleanup() {
  local root_session_id="${1:-}"
  local current child_id
  local -a pending=()

  [[ -n "$root_session_id" ]] || return 0
  traversed_session_ids["$root_session_id"]=1
  pending=("$root_session_id")
  while ((${#pending[@]} > 0)); do
    current="${pending[0]}"
    pending=("${pending[@]:1}")
    while IFS= read -r child_id; do
      [[ -n "$child_id" ]] || continue
      queue_session_for_cleanup "$child_id"
      if [[ -z "${traversed_session_ids[$child_id]:-}" ]]; then
        traversed_session_ids["$child_id"]=1
        pending+=("$child_id")
      fi
    done < <(
      jq -r --arg parent_session_id "$current" '
        .[]
        | select((.parent_session_id // "") == $parent_session_id)
        | .id
      ' <<<"$session_inventory_json" 2>/dev/null || true
    )
  done
}

remaining_sessions_json_for_scope() {
  local current_session_inventory_json="$1"
  local remaining_json

  remaining_json="$(
    jq -c \
      --arg planner_session_id "$planner_session_id" \
      '
        def direct_child_ids($sessions; $root):
          [ $sessions[] | select((.parent_session_id // "") == $root) | .id ];

        def descendant_ids($sessions; $root):
          direct_child_ids($sessions; $root) as $children
          | $children + [ $children[]? | descendant_ids($sessions; .)[]? ];

        if type != "array" then
          []
        else
          (if $planner_session_id == "" then [] else descendant_ids(.; $planner_session_id) end) as $descendants
          | [
              .[]
              | (.id // "") as $session_id
              | select(
                  (($planner_session_id != "") and (
                    $session_id == $planner_session_id
                    or ($descendants | index($session_id)) != null
                  ))
                )
              | {
                  id,
                  title: (.title // null),
                  group: (.group // null),
                  parent_session_id: (.parent_session_id // null)
                }
            ]
        end
      ' <<<"$current_session_inventory_json" 2>/dev/null
  )" || die "failed to compute remaining planner cleanup scope"

  echo "$remaining_json"
}

# The planner session is part of planner-run cleanup even when it was created in
# a different group, so accept it as an explicit extra delete target.
queue_session_for_cleanup "$planner_session_id"
queue_descendants_for_cleanup "$planner_session_id"

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
    elif [[ "$remove_output" == *"not found"* ]]; then
      delete_status="already_absent"
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
  --arg planner_group "$cleanup_group_scope" \
  --arg planner_group_source "$cleanup_group_scope_source" \
  --arg planner_session_id "$planner_session_id" \
  --arg archived_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg mode "$([[ "$apply" -eq 1 ]] && echo archive_and_remove || echo archive_only)" \
  --argjson sessions "$sessions_json" \
  '{
    planner_group: (if $planner_group == "" then null else $planner_group end),
    planner_group_source: (if $planner_group_source == "" then null else $planner_group_source end),
    planner_session_id: (if $planner_session_id == "" then null else $planner_session_id end),
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
derived_group_delete_count=0
derived_group_warning=""
best_effort_group_warning=""
if (( apply )); then
  if ! current_session_inventory_json="$(build_session_inventory_json)"; then
    group_delete_status="blocked_inventory_failed"
    delete_failed=1
  else
    remaining_sessions_json="$(remaining_sessions_json_for_scope "$current_session_inventory_json")"
    remaining_after_delete="$(jq -r 'length' <<<"$remaining_sessions_json" 2>/dev/null || echo -1)"
  fi

  if (( delete_failed != 0 )); then
    [[ "$group_delete_status" != "blocked_inventory_failed" ]] && group_delete_status="blocked_session_delete_failed"
  elif (( remaining_after_delete == 0 )); then
    delete_empty_scope_groups "$sessions_json"
    if (( delete_failed != 0 )); then
      :
    elif (( derived_group_delete_count > 0 )); then
      group_delete_status="deleted_derived_groups"
    elif [[ -n "$derived_group_warning" ]]; then
      group_delete_status="best_effort_derived_groups_skipped"
    fi
    group_list_json="$(ad group list --json 2>/dev/null || true)"
    if [[ -n "$cleanup_group_scope" && -n "$group_list_json" ]]; then
      if group_exists_in_tree "$cleanup_group_scope" "$group_list_json"; then
        group_exists_after_delete=1
      else
        group_exists_after_delete=0
      fi
    fi

    if (( delete_failed != 0 )); then
      :
    elif [[ -z "$cleanup_group_scope" ]]; then
      group_delete_status="not_applicable"
    elif [[ -z "$group_list_json" ]]; then
      [[ "$group_delete_status" == "skipped_no_apply" ]] && group_delete_status="best_effort_group_inspection_failed"
      best_effort_group_warning="failed to inspect group tree after cleanup for group=${cleanup_group_scope}"
    elif [[ "$group_exists_after_delete" == "1" ]]; then
      [[ "$group_delete_status" == "skipped_no_apply" ]] && group_delete_status="best_effort_group_remaining"
      best_effort_group_warning="group=${cleanup_group_scope} remained after best-effort cleanup"
    else
      [[ "$group_delete_status" == "skipped_no_apply" ]] && group_delete_status="not_applicable"
    fi
  else
    group_delete_status="blocked_nonempty"
    delete_failed=1
  fi
fi

echo "planner_group_cleanup planner_group=${cleanup_group_scope} planner_session_id=${planner_session_id} group_delete_status=${group_delete_status}"
if (( apply )) && (( delete_failed != 0 )); then
  jq -r '
    .[]
    | select(.delete_status == "delete_failed")
    | "planner_group_delete_failed session_id=\(.session_show.id // .session_id // "unknown") title=\(.session_show.title // "unknown") parent_session_id=\(.session_show.parent_session_id // "") error=\(.delete_error // "unknown")"
  ' <<<"$sessions_json"
  if [[ "$remaining_sessions_json" != "[]" ]]; then
    jq -r '
      .[]
      | "planner_group_remaining session_id=\(.id) title=\(.title // "unknown") group=\(.group // "") parent_session_id=\(.parent_session_id // "")"
    ' <<<"$remaining_sessions_json"
  fi
  if [[ -n "$group_delete_error" ]]; then
    echo "planner_group_group_delete_failed planner_group=${cleanup_group_scope} exit_code=${group_delete_exit_code:-unknown} error=${group_delete_error}"
  fi
fi

if [[ -n "$scope_warning" ]]; then
  echo "planner_group_cleanup_warning planner_group=${cleanup_group_scope} planner_session_id=${planner_session_id} warning=${scope_warning}"
fi

if [[ -n "$derived_group_warning" ]]; then
  echo "planner_group_group_delete_warning planner_group=${cleanup_group_scope} warning=${derived_group_warning}"
fi

if [[ -n "$best_effort_group_warning" ]]; then
  echo "planner_group_group_delete_warning planner_group=${cleanup_group_scope} warning=${best_effort_group_warning}"
fi

if (( delete_failed != 0 )); then
  exit 3
fi
