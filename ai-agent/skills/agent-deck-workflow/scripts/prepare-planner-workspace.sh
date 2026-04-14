#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Prepare the planner workspace record and detached integration snapshot for this git worktree.

Usage:
  prepare-planner-workspace.sh [options]

Options:
  --integration-branch <ref>      Required non-task landing branch for prepare/refresh mode
  --planner-session-id <id|title> Planner session ref (default: current agent-deck session id)
  --supervisor-session-id <id|title> Optional supervisor session id/ref for this planner workspace
  --artifact-root <path>          Artifact root (default: .agent-artifacts)
  --allow-dirty                   Allow detaching HEAD with local changes
  --release-planner-workspace     Delete existing planner-workspace.json owned by this planner
  --override-planner-workspace    Replace existing planner-workspace.json; use only after user confirmation
  -h, --help                      Show help

Outputs:
  - Writes, validates, or deletes <artifact-root>/planner-workspace.json
  - For prepare/refresh mode, detaches HEAD at the recorded integration branch tip commit
  - Prints a detached-HEAD notice plus one summary line with the resulting status

Exit codes:
  0: workspace prepared, refreshed, matched, or released
  2: usage/argument/runtime validation error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

require_clean_worktree() {
  local integration_branch="$1"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    die "dirty worktree/index; commit or stash first before detaching to integration commit '${integration_branch}'"
  fi
}

require_closeout_attachable_integration_branch() {
  local integration_branch="$1"
  local current_worktree="$2"
  local branch_ref record_worktree="" record_branch=""
  local line

  branch_ref="$(git rev-parse --verify --symbolic-full-name "$integration_branch" 2>/dev/null || true)"
  case "$branch_ref" in
    refs/heads/*) ;;
    *)
      # Only local branches participate in the multi-worktree "already checked out"
      # restriction. Keep existing behavior for other ref shapes.
      return 0
      ;;
  esac

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      if [[ -n "$record_worktree" && "$record_worktree" != "$current_worktree" && "$record_branch" == "$branch_ref" ]]; then
        die "integration branch '${integration_branch}' is already checked out in worktree '${record_worktree}'; planner closeout later needs to attach that branch here, so stop before prepare mutates this workspace"
      fi
      record_worktree=""
      record_branch=""
      continue
    fi
    case "$line" in
      worktree\ *) record_worktree="${line#worktree }" ;;
      branch\ *) record_branch="${line#branch }" ;;
    esac
  done < <(git worktree list --porcelain)

  if [[ -n "$record_worktree" && "$record_worktree" != "$current_worktree" && "$record_branch" == "$branch_ref" ]]; then
    die "integration branch '${integration_branch}' is already checked out in worktree '${record_worktree}'; planner closeout later needs to attach that branch here, so stop before prepare mutates this workspace"
  fi
}

emit_detached_head_notice() {
  # Keep the notice plain so both humans and agents can immediately see that
  # the current workspace state must not be mistaken for an attached branch.
  echo "workspace git state: detached HEAD"
}

resolve_current_session_json() {
  agent-deck session current --json 2>/dev/null || true
}

resolve_current_session_id() {
  local current_json current_id
  current_json="$(resolve_current_session_json)"
  current_id="$(jq -r '.id // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_id" ]] || die "failed to resolve current agent-deck session id; pass --planner-session-id"
  echo "$current_id"
}

resolve_current_session_group() {
  local current_json current_group
  current_json="$(resolve_current_session_json)"
  current_group="$(jq -r '.group // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_group" ]] || die "failed to resolve current agent-deck session group; planner session must belong to a non-root group"
  echo "$current_group"
}

resolve_session_group() {
  local shown session_group
  shown="$(agent-deck session show "$1" --json 2>/dev/null || true)"
  session_group="$(jq -r '.group // empty' <<<"$shown" 2>/dev/null || true)"
  [[ -n "$session_group" ]] || die "failed to resolve agent-deck session group for '${1}'; planner session must belong to a non-root group"
  echo "$session_group"
}

session_exists() {
  local session_ref="$1"
  local shown
  shown="$(agent-deck session show "$session_ref" --json 2>/dev/null || true)"
  [[ -n "$shown" ]] && jq -e '.id // empty' >/dev/null 2>&1 <<<"$shown"
}

is_task_branch_ref() {
  case "$1" in
    task/*|refs/heads/task/*|refs/remotes/*/task/*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_commit_oid() {
  local ref="$1"
  local oid
  oid="$(git rev-parse --verify "${ref}^{commit}" 2>/dev/null || true)"
  [[ -n "$oid" ]] || die "integration branch does not exist: $ref"
  echo "$oid"
}

ensure_detached_integration_head() {
  local integration_branch="$1"
  local integration_commit="$2"
  local allow_dirty="$3"
  local current_commit current_branch switch_output

  current_commit="$(git rev-parse --verify HEAD 2>/dev/null || true)"
  current_branch="$(git symbolic-ref --quiet --short HEAD || true)"

  if (( allow_dirty == 0 )); then
    require_clean_worktree "$integration_branch"
  fi

  # Detach on purpose: the workspace may have been left on any branch/revision,
  # and we want an obvious neutral git state before any later branch creation.
  if [[ -z "$current_branch" && "$current_commit" == "$integration_commit" ]]; then
    echo "matched"
    return 0
  fi

  switch_output="$(git switch --detach "$integration_commit" 2>&1)" || {
    echo "$switch_output" >&2
    die "failed to detach HEAD at integration branch '${integration_branch}'"
  }

  if [[ -n "$switch_output" ]]; then
    echo "$switch_output" >&2
  fi
  echo "detached"
}

write_record() {
  local output_file="$1"
  local planner_session_id="$2"
  local planner_group="$3"
  local integration_branch="$4"
  local supervisor_session_id="$5"
  local status="$6"
  local tmp_record

  tmp_record="$(mktemp)"
  jq -nc \
    --arg planner_session_id "$planner_session_id" \
    --arg planner_group "$planner_group" \
    --arg integration_branch "$integration_branch" \
    --arg supervisor_session_id "$supervisor_session_id" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    '{
      planner_session_id: $planner_session_id,
      planner_group: $planner_group,
      integration_branch: $integration_branch,
      updated_at: $updated_at
    } + (
      if $supervisor_session_id == "" then
        {}
      else
        {supervisor_session_id: $supervisor_session_id}
      end
    ) + (
      if $status == "created" then
        {created_at: $updated_at}
      else
        {}
      end
    )' >"$tmp_record"
  mv "$tmp_record" "$output_file"
}

planner_session_ref=""
integration_branch=""
supervisor_session_ref=""
artifact_root=".agent-artifacts"
allow_dirty=0
release_planner_workspace=0
override_planner_workspace=0
planner_session_ref_inferred=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --supervisor-session-id) supervisor_session_ref="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift 1 ;;
    --release-planner-workspace) release_planner_workspace=1; shift 1 ;;
    --override-planner-workspace) override_planner_workspace=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

if (( release_planner_workspace == 1 && override_planner_workspace == 1 )); then
  die "--release-planner-workspace cannot be combined with --override-planner-workspace"
fi

if (( release_planner_workspace == 0 )); then
  [[ -n "$integration_branch" ]] || die "--integration-branch is required"
else
  [[ -z "$integration_branch" ]] || die "--integration-branch is not allowed with --release-planner-workspace"
  [[ -z "$supervisor_session_ref" ]] || die "--supervisor-session-id is not allowed with --release-planner-workspace"
  (( allow_dirty == 0 )) || die "--allow-dirty is not allowed with --release-planner-workspace"
fi

command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "must run inside a git repository"
fi

record_file="${artifact_root%/}/planner-workspace.json"
mkdir -p "$(dirname "$record_file")"

if [[ -z "$planner_session_ref" ]]; then
  planner_session_ref="$(resolve_current_session_id)"
  planner_session_ref_inferred=1
fi

if (( release_planner_workspace == 1 )); then
  if [[ ! -f "$record_file" ]]; then
    echo "planner_workspace_prepared status=already_absent file=${record_file} planner=${planner_session_ref}"
    exit 0
  fi

  record_planner_session_id="$(jq -r '.planner_session_id // empty' "$record_file" 2>/dev/null || true)"
  [[ -n "$record_planner_session_id" ]] || die "planner workspace record missing planner_session_id: ${record_file}"
  [[ "$record_planner_session_id" == "$planner_session_ref" ]] || die "planner workspace planner mismatch: record='${record_planner_session_id}' expected='${planner_session_ref}' file='${record_file}'"

  rm -f "$record_file" || die "failed to remove planner workspace record: ${record_file}"
  echo "planner_workspace_prepared status=released file=${record_file} planner=${planner_session_ref}"
  exit 0
fi

if (( planner_session_ref_inferred == 1 )); then
  planner_group="$(resolve_current_session_group)"
else
  planner_group="$(resolve_session_group "$planner_session_ref")"
fi

is_task_branch_ref "$integration_branch" && die "--integration-branch must be a non-task landing branch, got: ${integration_branch}"
integration_commit="$(resolve_commit_oid "$integration_branch")"
# Detached HEAD is only useful if the planner can still complete closeout later.
# Fail here when another worktree already owns the integration branch instead of
# letting the whole plan run and only exploding at the final merge step.
require_closeout_attachable_integration_branch "$integration_branch" "$(pwd -P)"

if [[ ! -f "$record_file" ]]; then
  checkout_status="$(ensure_detached_integration_head "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "$supervisor_session_ref" "created"
  emit_detached_head_notice "$integration_branch" "$integration_commit"
  echo "planner_workspace_prepared status=created checkout_status=${checkout_status} file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit}"
  exit 0
fi

if (( override_planner_workspace == 1 )); then
  checkout_status="$(ensure_detached_integration_head "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "$supervisor_session_ref" "overridden"
  emit_detached_head_notice "$integration_branch" "$integration_commit"
  echo "planner_workspace_prepared status=overridden checkout_status=${checkout_status} file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit}"
  exit 0
fi

record_planner_session_id="$(jq -r '.planner_session_id // empty' "$record_file" 2>/dev/null || true)"
record_planner_group="$(jq -r '.planner_group // empty' "$record_file" 2>/dev/null || true)"
record_integration_branch="$(jq -r '.integration_branch // empty' "$record_file" 2>/dev/null || true)"
record_supervisor_session_id="$(jq -r '.supervisor_session_id // empty' "$record_file" 2>/dev/null || true)"

[[ -n "$record_planner_session_id" ]] || die "planner workspace record missing planner_session_id: ${record_file}"
[[ -n "$record_integration_branch" ]] || die "planner workspace record missing integration_branch: ${record_file}"

if ! session_exists "$record_planner_session_id"; then
  checkout_status="$(ensure_detached_integration_head "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "$supervisor_session_ref" "stale_replaced"
  emit_detached_head_notice "$integration_branch" "$integration_commit"
  echo "planner_workspace_prepared status=stale_replaced checkout_status=${checkout_status} file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit}"
  exit 0
fi

[[ "$record_planner_session_id" == "$planner_session_ref" ]] || die "planner workspace planner mismatch: record='${record_planner_session_id}' expected='${planner_session_ref}' file='${record_file}'"
[[ "$record_integration_branch" == "$integration_branch" ]] || die "planner workspace integration branch mismatch: record='${record_integration_branch}' expected='${integration_branch}' file='${record_file}'"
if [[ -n "$record_supervisor_session_id" && -n "$supervisor_session_ref" ]]; then
  [[ "$record_supervisor_session_id" == "$supervisor_session_ref" ]] || die "planner workspace supervisor mismatch: record='${record_supervisor_session_id}' expected='${supervisor_session_ref}' file='${record_file}'"
fi

if [[ -z "$record_planner_group" || "$record_planner_group" != "$planner_group" || ( -n "$supervisor_session_ref" && "$record_supervisor_session_id" != "$supervisor_session_ref" ) ]]; then
  checkout_status="$(ensure_detached_integration_head "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record "$record_file" "$planner_session_ref" "$planner_group" "$integration_branch" "${supervisor_session_ref:-$record_supervisor_session_id}" "matched_refreshed"
  emit_detached_head_notice "$integration_branch" "$integration_commit"
  echo "planner_workspace_prepared status=matched_refreshed checkout_status=${checkout_status} file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit}"
  exit 0
fi

checkout_status="$(ensure_detached_integration_head "$integration_branch" "$integration_commit" "$allow_dirty")"
emit_detached_head_notice "$integration_branch" "$integration_commit"
echo "planner_workspace_prepared status=matched checkout_status=${checkout_status} file=${record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit}"
