#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/archive-and-remove-planner-group-sessions.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="${1:-}" needle="${2:-}"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="${1:-}" needle="${2:-}"
  [[ "$haystack" != *"$needle"* ]] || fail "did not expect output to contain: $needle"
}

make_stub_agent_deck() {
  local stub_path="$1" state_file="$2" groups_file="$3"
  cat >"$stub_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state_file="$state_file"
groups_file="$groups_file"
cmd="\$1"
shift || true
case "\$cmd" in
  list)
    jq -c '[.sessions[] | {id, title, path, group, status}]' "\$state_file"
    ;;
  session)
    sub="\$1"
    shift || true
    case "\$sub" in
      show)
        sid="\$1"
        hit="\$(jq -c --arg sid "\$sid" '.sessions[] | select(.id == \$sid)' "\$state_file")"
        if [[ -n "\$hit" ]]; then
          printf '%s\n' "\$hit"
        else
          printf "session '%s' not found\n" "\$sid" >&2
          exit 1
        fi
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  remove)
    sid="\$1"
    if jq -e --arg sid "\$sid" '.sessions[] | select(.id == \$sid)' "\$state_file" >/dev/null; then
      tmp="\${state_file}.tmp"
      jq --arg sid "\$sid" 'del(.sessions[] | select(.id == \$sid))' "\$state_file" >"\$tmp"
      mv "\$tmp" "\$state_file"
    else
      printf "session '%s' not found\n" "\$sid" >&2
      exit 1
    fi
    ;;
  group)
    sub="\$1"
    shift || true
    case "\$sub" in
      list)
        cat "\$groups_file"
        ;;
      delete)
        group_path="\$1"
        tmp="\${groups_file}.tmp"
        jq --arg g "\$group_path" '
          def drop_groups(\$nodes; \$g):
            [ \$nodes[] | select(.path != \$g) | .children = drop_groups((.children // []); \$g) ];
          .groups = drop_groups(.groups; \$g)
        ' "\$groups_file" >"\$tmp"
        mv "\$tmp" "\$groups_file"
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$stub_path"
}

run_case_live_planner_subgroup_is_not_used_for_session_cleanup_scope() {
  local tmpdir work state groups stub output
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"super-1","title":"supervisor","group":"real/scope","parent_session_id":"","path":"/tmp/s","status":"waiting"},{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1","path":"/tmp/p","status":"waiting"},{"id":"coder-1","title":"coder","group":"real/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"real","path":"real","session_count":0,"children":[{"name":"scope","path":"real/scope","session_count":0,"children":[]}]}]}' >"$groups"
  printf '%s\n' '{"planner_group":"stale/scope","planner_session_id":"planner-1","archived_at":"2026-04-20T23:59:00Z","mode":"archive_and_remove","sessions":[{"found":false,"session_id":"planner-1","delete_applied":false,"deleted":false,"delete_status":"not_found"}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260420T235900Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply
  )"

  assert_contains "$output" "planner_group_cleanup planner_group=real/scope"
  assert_not_contains "$output" "planner_group_cleanup planner_group=stale/scope"
  [[ "$(jq -r '.sessions | length' "$state")" == "2" ]] || fail "expected planner cleanup to leave supervisor-group siblings untouched"
  [[ "$(jq -r '.sessions[0].id' "$state")" == "super-1" ]] || fail "expected supervisor session to remain"
  [[ "$(jq -r '.sessions[1].id' "$state")" == "coder-1" ]] || fail "expected sibling session in the same group to remain"
  [[ -n "$(find "${work}/.agent-artifacts/planner-groups/session_planner-1" -maxdepth 1 -name 'session-archive-*.json' -type f -print -quit)" ]] || fail "expected session-keyed archive output"
  rm -rf "$tmpdir"
}

run_case_missing_live_scope_is_best_effort_noop() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"coder-1","title":"coder","group":"legacy/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"legacy","path":"legacy","session_count":0,"children":[{"name":"scope","path":"legacy/scope","session_count":0,"children":[]}]}]}' >"$groups"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected missing live scope to stay best-effort no-op, got ${rc}"
  assert_contains "$output" "planner_group_cleanup planner_group="
  assert_contains "$output" "group_delete_status=not_applicable"
  assert_contains "$output" "planner session not found; planner lane cleanup scope unavailable"
  [[ "$(jq -r '.sessions | length' "$state")" == "1" ]] || fail "expected first cleanup attempt without archive scope to leave unrelated sessions untouched"
  rm -rf "$tmpdir"
}

run_case_removed_group_hint_arg_is_rejected() {
  local tmpdir work output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"

  set +e
  output="$(
    cd "$work"
    "$TARGET_SCRIPT" --planner-session-id planner-1 --planner-group-hint stale/scope --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 2 ]] || fail "expected removed --planner-group-hint arg to be rejected, got ${rc}"
  assert_contains "$output" "unknown arg: --planner-group-hint"
  rm -rf "$tmpdir"
}

run_case_archived_scope_is_ignored_without_live_planner() {
  local tmpdir work state groups stub output
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"coder-1","title":"coder","group":"legacy/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"legacy","path":"legacy","session_count":0,"children":[{"name":"scope","path":"legacy/scope","session_count":0,"children":[]}]}]}' >"$groups"
  printf '%s\n' '{"planner_group":"legacy/scope","planner_session_id":"planner-1","archived_at":"2026-04-20T23:59:00Z","mode":"archive_and_remove","sessions":[{"found":true,"session_show":{"id":"planner-1","title":"planner-x","group":"","parent_session_id":"super-1"},"delete_applied":false,"deleted":false,"delete_status":"skipped_no_apply","delete_error":null}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260420T235900Z.json"
  printf '%s\n' '{"planner_group":null,"planner_session_id":"planner-1","archived_at":"2026-04-21T00:00:00Z","mode":"archive_and_remove","sessions":[{"found":true,"session_show":{"id":"planner-1","title":"planner-x","group":"","parent_session_id":"super-1"},"delete_applied":false,"deleted":false,"delete_status":"skipped_no_apply","delete_error":null}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260421T000000Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected archived scope to be ignored without live planner via best-effort no-op, got ${rc}"
  assert_contains "$output" "group_delete_status=not_applicable"
  assert_not_contains "$output" "planner_group_cleanup planner_group=legacy/scope"
  rm -rf "$tmpdir"
}

run_case_missing_live_scope_after_session_cleanup_is_best_effort_noop() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[]}' >"$state"
  printf '%s\n' '{"groups":[]}' >"$groups"
  printf '%s\n' '{"planner_group":null,"planner_session_id":"planner-1","archived_at":"2026-04-21T00:00:00Z","mode":"archive_and_remove","sessions":[{"found":true,"session_show":{"id":"planner-1","title":"planner-x","group":"","parent_session_id":"super-1"},"delete_applied":false,"deleted":false,"delete_status":"skipped_no_apply","delete_error":null}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260421T000000Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected missing live scope without remaining sessions to stay best-effort no-op, got ${rc}"
  assert_contains "$output" "group_delete_status=not_applicable"
  rm -rf "$tmpdir"
}

run_case_archived_planner_session_group_is_ignored_without_live_planner() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"coder-1","title":"coder","group":"real/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"stale","path":"stale","session_count":0,"children":[{"name":"scope","path":"stale/scope","session_count":0,"children":[]}]},{"name":"real","path":"real","session_count":0,"children":[{"name":"scope","path":"real/scope","session_count":0,"children":[]}]}]}' >"$groups"
  printf '%s\n' '{"planner_group":"stale/scope","planner_session_id":"planner-1","archived_at":"2026-04-20T23:59:00Z","mode":"archive_and_remove","sessions":[{"found":true,"session_show":{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1"},"delete_applied":false,"deleted":false,"delete_status":"skipped_no_apply","delete_error":null}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260420T235900Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected archived planner session group to be ignored without live planner via best-effort no-op, got ${rc}"
  assert_contains "$output" "group_delete_status=not_applicable"
  [[ "$(jq -r '.sessions | length' "$state")" == "1" ]] || fail "expected archive-derived session scope to avoid deleting live group sessions"
  rm -rf "$tmpdir"
}

run_case_archived_scope_does_not_override_missing_live_planner() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"coder-1","title":"coder","group":"real/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"stale","path":"stale","session_count":0,"children":[{"name":"scope","path":"stale/scope","session_count":0,"children":[]}]},{"name":"real","path":"real","session_count":0,"children":[{"name":"scope","path":"real/scope","session_count":0,"children":[]}]}]}' >"$groups"
  printf '%s\n' '{"planner_group":"real/scope","planner_session_id":"planner-1","archived_at":"2026-04-20T23:59:00Z","mode":"archive_and_remove","sessions":[{"found":true,"session_show":{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1"},"delete_applied":false,"deleted":false,"delete_status":"skipped_no_apply","delete_error":null}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260420T235900Z.json"
  printf '%s\n' '{"planner_group":"stale/scope","planner_session_id":"planner-1","archived_at":"2026-04-21T00:00:00Z","mode":"archive_and_remove","sessions":[{"found":false,"session_id":"planner-1","delete_applied":false,"deleted":false,"delete_status":"not_found"}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260421T000000Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected archived scope to stay ignored without live planner via best-effort no-op, got ${rc}"
  assert_contains "$output" "group_delete_status=not_applicable"
  [[ "$(jq -r '.sessions | length' "$state")" == "1" ]] || fail "expected archive-derived session scope to avoid deleting live group sessions"
  rm -rf "$tmpdir"
}

run_case_archived_planner_group_is_ignored_without_live_planner() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"coder-1","title":"coder","group":"real/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"stale","path":"stale","session_count":0,"children":[{"name":"scope","path":"stale/scope","session_count":0,"children":[]}]},{"name":"real","path":"real","session_count":0,"children":[{"name":"scope","path":"real/scope","session_count":0,"children":[]}]}]}' >"$groups"
  printf '%s\n' '{"planner_group":"real/scope","planner_group_source":"live_planner","planner_session_id":"planner-1","archived_at":"2026-04-20T23:59:00Z","mode":"archive_and_remove","sessions":[{"found":false,"session_id":"planner-1","delete_applied":false,"deleted":false,"delete_status":"not_found"}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260420T235900Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected archived planner_group to be ignored without live planner via best-effort no-op, got ${rc}"
  assert_contains "$output" "group_delete_status=not_applicable"
  [[ "$(jq -r '.sessions | length' "$state")" == "1" ]] || fail "expected archive-derived planner_group evidence to avoid deleting live group sessions"
  rm -rf "$tmpdir"
}

run_case_removed_cleanup_group_override_arg_is_rejected() {
  local tmpdir work output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"

  set +e
  output="$(
    cd "$work"
    "$TARGET_SCRIPT" --planner-session-id planner-1 --cleanup-group-override real/scope --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 2 ]] || fail "expected removed --cleanup-group-override arg to be rejected, got ${rc}"
  assert_contains "$output" "unknown arg: --cleanup-group-override"
  rm -rf "$tmpdir"
}

run_case_archive_scope_is_ignored_for_unrelated_live_sessions() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work/.agent-artifacts/planner-groups/session_planner-1"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"other-1","title":"unrelated","group":"stale/scope","parent_session_id":"","path":"/tmp/w","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"stale","path":"stale","session_count":0,"children":[{"name":"scope","path":"stale/scope","session_count":1,"children":[]}]}]}' >"$groups"
  printf '%s\n' '{"planner_group":"stale/scope","planner_session_id":"planner-1","archived_at":"2026-04-20T23:59:00Z","mode":"archive_and_remove","sessions":[{"found":false,"session_id":"planner-1","delete_applied":false,"deleted":false,"delete_status":"not_found"}]}' >"$work/.agent-artifacts/planner-groups/session_planner-1/session-archive-20260420T235900Z.json"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected archive-derived cleanup scope to be ignored without live planner via best-effort no-op, got ${rc}"
  assert_contains "$output" "group_delete_status=not_applicable"
  [[ "$(jq -r '.sessions | length' "$state")" == "1" ]] || fail "expected unrelated live session in archive-derived scope to remain"
  [[ "$(jq -r '.sessions[0].id' "$state")" == "other-1" ]] || fail "expected unrelated live session to stay untouched"
  rm -rf "$tmpdir"
}

run_case_missing_planner_session_id_is_rejected() {
  local tmpdir work output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"

  set +e
  output="$(
    cd "$work"
    "$TARGET_SCRIPT" --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 2 ]] || fail "expected missing planner-session-id to be rejected, got ${rc}"
  assert_contains "$output" "pass --planner-session-id"
  rm -rf "$tmpdir"
}

run_case_inferred_scope_remaining_group_warns_without_failing() {
  local tmpdir work state groups stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1","path":"/tmp/p","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"real","path":"real","session_count":0,"children":[{"name":"scope","path":"real/scope","session_count":0,"children":[{"name":"orphan","path":"real/scope/orphan","session_count":0,"children":[]}]}]}]}' >"$groups"
  make_stub_agent_deck "$stub" "$state" "$groups"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected inferred-scope residual group to warn without failing, got ${rc}"
  assert_contains "$output" "group_delete_status=best_effort_group_remaining"
  assert_contains "$output" "planner_group_group_delete_warning planner_group=real/scope warning=group=real/scope remained after best-effort cleanup"
  rm -rf "$tmpdir"
}

run_case_inferred_scope_group_list_failure_warns_without_failing() {
  local tmpdir work state stub output rc
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"
  state="${tmpdir}/state.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"present":true}' >"$state"
  cat >"$stub" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state_file="$state"
present="\$(jq -r '.present' "\$state_file")"
cmd="\$1"
shift || true
case "\$cmd" in
  list)
    if [[ "\$present" == "true" ]]; then
      printf '%s\n' '[{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1","path":"/tmp/p","status":"waiting"}]'
    else
      printf '%s\n' '[]'
    fi
    ;;
  session)
    if [[ "\${1:-}" == "show" && "\${2:-}" == "planner-1" && "\$present" == "true" ]]; then
      printf '%s\n' '{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1","path":"/tmp/p","status":"waiting"}'
    else
      exit 1
    fi
    ;;
  remove)
    tmp="\${state_file}.tmp"
    jq '.present = false' "\$state_file" >"\$tmp"
    mv "\$tmp" "\$state_file"
    ;;
  group)
    if [[ "\${1:-}" == "list" ]]; then
      printf 'group list failed\n' >&2
      exit 1
    fi
    exit 2
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$stub"

  set +e
  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply 2>&1
  )"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || fail "expected inferred-scope cleanup to warn without failing when final group inspection is unavailable, got ${rc}"
  assert_contains "$output" "group_delete_status=best_effort_"
  assert_contains "$output" "planner_group_group_delete_warning planner_group=real/scope"
  rm -rf "$tmpdir"
}

run_case_empty_fallback_worker_subgroup_is_deleted() {
  local tmpdir work state groups stub output
  tmpdir="$(mktemp -d)"
  work="${tmpdir}/work"
  mkdir -p "$work"
  state="${tmpdir}/state.json"
  groups="${tmpdir}/groups.json"
  stub="${tmpdir}/agent-deck"

  printf '%s\n' '{"sessions":[{"id":"super-1","title":"supervisor","group":"real/scope","parent_session_id":"","path":"/tmp/s","status":"waiting"},{"id":"planner-1","title":"planner-x","group":"real/scope","parent_session_id":"super-1","path":"/tmp/p","status":"waiting"}]}' >"$state"
  printf '%s\n' '{"groups":[{"name":"real","path":"real","session_count":0,"children":[{"name":"scope","path":"real/scope","session_count":1,"children":[{"name":"planner-x","path":"real/scope/planner-x","session_count":0,"children":[]}]}]}]}' >"$groups"
  make_stub_agent_deck "$stub" "$state" "$groups"

  output="$(
    cd "$work"
    PATH="${tmpdir}:$PATH" "$TARGET_SCRIPT" --planner-session-id planner-1 --apply
  )"

  assert_contains "$output" "planner_group_cleanup planner_group=real/scope"
  if jq -e '
    def group_tree:
      . as $group
      | $group, (($group.children // [])[] | group_tree);
    any(.groups[]? | group_tree; (.path // "") == "real/scope/planner-x")
  ' "$groups" >/dev/null; then
    fail "expected empty fallback worker subgroup to be deleted"
  fi
  rm -rf "$tmpdir"
}

run_case_live_planner_subgroup_is_not_used_for_session_cleanup_scope
run_case_missing_live_scope_is_best_effort_noop
run_case_removed_group_hint_arg_is_rejected
run_case_archived_scope_is_ignored_without_live_planner
run_case_missing_live_scope_after_session_cleanup_is_best_effort_noop
run_case_archived_planner_session_group_is_ignored_without_live_planner
run_case_archived_scope_does_not_override_missing_live_planner
run_case_archived_planner_group_is_ignored_without_live_planner
run_case_removed_cleanup_group_override_arg_is_rejected
run_case_archive_scope_is_ignored_for_unrelated_live_sessions
run_case_missing_planner_session_id_is_rejected
run_case_inferred_scope_remaining_group_warns_without_failing
run_case_inferred_scope_group_list_failure_warns_without_failing
run_case_empty_fallback_worker_subgroup_is_deleted

echo "PASS: archive-and-remove-planner-group-sessions"
