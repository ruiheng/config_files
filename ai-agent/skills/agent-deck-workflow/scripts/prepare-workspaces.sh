#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Prepare worker/planner workspace records and the detached worker snapshot for one workflow.

Usage:
  prepare-workspaces.sh [options]

Options:
  --worker-workspace <path>       Required worker/shared workspace path
  --planner-workspace <path>      Required planner closeout workspace path
  --integration-branch <ref>      Required non-task landing branch for prepare/refresh mode
  --planner-session-id <id|title> Planner session ref (default: current agent-deck session id)
  --supervisor-session-id <id|title>
                                  Optional supervisor session id/ref for this workflow
  --worker-artifact-root <path>   Worker artifact root (default: <worker-workspace>/.agent-artifacts)
  --planner-artifact-root <path>  Planner artifact root (default: <planner-workspace>/.agent-artifacts)
  --allow-dirty                   Allow detaching worker workspace HEAD with local changes
  --release-workspaces            Delete planner-workspace.json owned by this planner from both roots
  --override-workspaces           Replace planner-workspace.json in both roots; use only after user confirmation
  -h, --help                      Show help

Outputs:
  - Writes, validates, or deletes planner-workspace.json in both workspace artifact roots
  - For prepare/refresh mode, detaches worker workspace HEAD at the integration branch tip commit
  - Validates that planner workspace can later run closeout on the integration branch
  - Prints a detached-HEAD notice plus one summary line with the resulting status

Exit codes:
  0: workspaces prepared, refreshed, matched, or released
  2: usage/argument/runtime validation error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/notify-workflow-lib.sh"

prepare_blocker() {
  local event="$1"
  local message="$2"
  adwf_notify_event "$event" "warn" "Workspace prepare blocked" "$message"
  die "$message"
}

abs_path() {
  (
    cd "$1"
    pwd -P
  )
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

require_git_workspace() {
  local workspace="$1"
  [[ -d "$workspace" ]] || die "workspace does not exist: ${workspace}"
  git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "workspace is not inside a git repository: ${workspace}"
}

resolve_commit_oid() {
  local workspace="$1"
  local ref="$2"
  local oid
  oid="$(git -C "$workspace" rev-parse --verify "${ref}^{commit}" 2>/dev/null || true)"
  [[ -n "$oid" ]] || die "integration branch does not exist: $ref"
  echo "$oid"
}

require_clean_worktree() {
  local workspace="$1"
  local integration_branch="$2"
  if ! git -C "$workspace" diff --quiet || ! git -C "$workspace" diff --cached --quiet; then
    prepare_blocker "worker_workspace_dirty_worktree" "dirty worker worktree/index at '${workspace}'; commit or stash first before detaching to integration commit '${integration_branch}'"
  fi
}

validate_planner_closeout_workspace() {
  local planner_workspace="$1"
  local integration_branch="$2"

  git -C "$planner_workspace" rev-parse --verify "$integration_branch" >/dev/null 2>&1 || {
    prepare_blocker "planner_workspace_missing_integration_branch" "planner workspace '${planner_workspace}' does not have integration branch '${integration_branch}'; closeout would fail later, so stop during prepare"
  }
}

require_allowed_integration_branch_owner() {
  local integration_branch="$1"
  local worker_workspace="$2"
  local planner_workspace="$3"
  local branch_ref record_worktree="" record_branch=""
  local line

  branch_ref="$(git -C "$worker_workspace" rev-parse --verify --symbolic-full-name "$integration_branch" 2>/dev/null || true)"
  case "$branch_ref" in
    refs/heads/*) ;;
    *)
      return 0
      ;;
  esac

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      if [[ -n "$record_worktree" && "$record_branch" == "$branch_ref" && "$record_worktree" != "$worker_workspace" && "$record_worktree" != "$planner_workspace" ]]; then
        prepare_blocker "workspace_branch_in_use" "integration branch '${integration_branch}' is already checked out in worktree '${record_worktree}'; only worker workspace '${worker_workspace}' and planner workspace '${planner_workspace}' may own it for this workflow"
      fi
      record_worktree=""
      record_branch=""
      continue
    fi
    case "$line" in
      worktree\ *) record_worktree="${line#worktree }" ;;
      branch\ *) record_branch="${line#branch }" ;;
    esac
  done < <(git -C "$worker_workspace" worktree list --porcelain)

  if [[ -n "$record_worktree" && "$record_branch" == "$branch_ref" && "$record_worktree" != "$worker_workspace" && "$record_worktree" != "$planner_workspace" ]]; then
    prepare_blocker "workspace_branch_in_use" "integration branch '${integration_branch}' is already checked out in worktree '${record_worktree}'; only worker workspace '${worker_workspace}' and planner workspace '${planner_workspace}' may own it for this workflow"
  fi
}

ensure_detached_worker_head() {
  local worker_workspace="$1"
  local integration_branch="$2"
  local integration_commit="$3"
  local allow_dirty="$4"
  local current_commit current_branch switch_output

  current_commit="$(git -C "$worker_workspace" rev-parse --verify HEAD 2>/dev/null || true)"
  current_branch="$(git -C "$worker_workspace" symbolic-ref --quiet --short HEAD || true)"

  if (( allow_dirty == 0 )); then
    require_clean_worktree "$worker_workspace" "$integration_branch"
  fi

  if [[ -z "$current_branch" && "$current_commit" == "$integration_commit" ]]; then
    echo "matched"
    return 0
  fi

  switch_output="$(git -C "$worker_workspace" switch --detach "$integration_commit" 2>&1)" || {
    echo "$switch_output" >&2
    die "failed to detach worker workspace '${worker_workspace}' at integration branch '${integration_branch}'"
  }

  if [[ -n "$switch_output" ]]; then
    echo "$switch_output" >&2
  fi
  echo "detached"
}

emit_detached_head_notice() {
  echo "worker workspace git state: detached HEAD"
}

record_field() {
  local file="$1"
  local field="$2"
  jq -r --arg field "$field" '.[$field] // empty' "$file" 2>/dev/null || true
}

record_summary() {
  local file="$1"
  local planner_session_id planner_group integration_branch supervisor_session_id worker_workspace planner_workspace

  planner_session_id="$(record_field "$file" "planner_session_id")"
  planner_group="$(record_field "$file" "planner_group")"
  integration_branch="$(record_field "$file" "integration_branch")"
  supervisor_session_id="$(record_field "$file" "supervisor_session_id")"
  worker_workspace="$(record_field "$file" "worker_workspace")"
  planner_workspace="$(record_field "$file" "planner_workspace")"

  printf "file='%s' planner_session_id='%s' planner_group='%s' integration_branch='%s' supervisor_session_id='%s' worker_workspace='%s' planner_workspace='%s'" \
    "$file" "$planner_session_id" "$planner_group" "$integration_branch" "$supervisor_session_id" "$worker_workspace" "$planner_workspace"
}

mismatch_detail() {
  local field="$1"
  local canonical_file="$2"
  local canonical_value="$3"
  local file="$4"
  local file_value="$5"

  prepare_blocker \
    "workspace_record_set_mismatch" \
    "workspace record set mismatch: ${field} differs between mirrored records. current_planner_session='${planner_session_ref}'. canonical { $(record_summary "$canonical_file") }. conflicting { $(record_summary "$file") }. If you intend to replace both mirrored records for this planner, rerun with --override-workspaces after explicit user confirmation."
}

validate_record_set() {
  local canonical_file="$1"
  shift
  local canonical_planner_session_id canonical_planner_group canonical_integration_branch canonical_supervisor_session_id canonical_worker_workspace canonical_planner_workspace
  local file
  local file_planner_session_id file_planner_group file_integration_branch file_supervisor_session_id file_worker_workspace file_planner_workspace

  canonical_planner_session_id="$(record_field "$canonical_file" "planner_session_id")"
  canonical_planner_group="$(record_field "$canonical_file" "planner_group")"
  canonical_integration_branch="$(record_field "$canonical_file" "integration_branch")"
  canonical_supervisor_session_id="$(record_field "$canonical_file" "supervisor_session_id")"
  canonical_worker_workspace="$(record_field "$canonical_file" "worker_workspace")"
  canonical_planner_workspace="$(record_field "$canonical_file" "planner_workspace")"

  for file in "$@"; do
    [[ "$file" == "$canonical_file" ]] && continue
    [[ -f "$file" ]] || continue
    file_planner_session_id="$(record_field "$file" "planner_session_id")"
    file_planner_group="$(record_field "$file" "planner_group")"
    file_integration_branch="$(record_field "$file" "integration_branch")"
    file_supervisor_session_id="$(record_field "$file" "supervisor_session_id")"
    file_worker_workspace="$(record_field "$file" "worker_workspace")"
    file_planner_workspace="$(record_field "$file" "planner_workspace")"
    [[ "$file_planner_session_id" == "$canonical_planner_session_id" ]] || mismatch_detail "planner_session_id" "$canonical_file" "$canonical_planner_session_id" "$file" "$file_planner_session_id"
    [[ "$file_planner_group" == "$canonical_planner_group" ]] || mismatch_detail "planner_group" "$canonical_file" "$canonical_planner_group" "$file" "$file_planner_group"
    [[ "$file_integration_branch" == "$canonical_integration_branch" ]] || mismatch_detail "integration_branch" "$canonical_file" "$canonical_integration_branch" "$file" "$file_integration_branch"
    [[ "$file_supervisor_session_id" == "$canonical_supervisor_session_id" ]] || mismatch_detail "supervisor_session_id" "$canonical_file" "$canonical_supervisor_session_id" "$file" "$file_supervisor_session_id"
    if [[ -n "$canonical_worker_workspace" || -n "$file_worker_workspace" ]]; then
      [[ "$file_worker_workspace" == "$canonical_worker_workspace" ]] || mismatch_detail "worker_workspace" "$canonical_file" "$canonical_worker_workspace" "$file" "$file_worker_workspace"
    fi
    if [[ -n "$canonical_planner_workspace" || -n "$file_planner_workspace" ]]; then
      [[ "$file_planner_workspace" == "$canonical_planner_workspace" ]] || mismatch_detail "planner_workspace" "$canonical_file" "$canonical_planner_workspace" "$file" "$file_planner_workspace"
    fi
  done
}

write_record() {
  local output_file="$1"
  local planner_session_id="$2"
  local planner_group="$3"
  local integration_branch="$4"
  local supervisor_session_id="$5"
  local worker_workspace="$6"
  local planner_workspace="$7"
  local status="$8"
  local tmp_record

  mkdir -p "$(dirname "$output_file")"
  tmp_record="$(mktemp)"
  jq -nc \
    --arg planner_session_id "$planner_session_id" \
    --arg planner_group "$planner_group" \
    --arg integration_branch "$integration_branch" \
    --arg supervisor_session_id "$supervisor_session_id" \
    --arg worker_workspace "$worker_workspace" \
    --arg planner_workspace "$planner_workspace" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg status "$status" \
    '{
      planner_session_id: $planner_session_id,
      planner_group: $planner_group,
      integration_branch: $integration_branch,
      worker_workspace: $worker_workspace,
      planner_workspace: $planner_workspace,
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

write_record_set() {
  local status="$1"
  local file

  for file in "${record_files[@]}"; do
    write_record "$file" "$planner_session_ref" "$planner_group" "$integration_branch" "$supervisor_session_ref" "$worker_workspace" "$planner_workspace" "$status"
  done
}

worker_workspace=""
planner_workspace=""
integration_branch=""
planner_session_ref=""
supervisor_session_ref=""
worker_artifact_root=""
planner_artifact_root=""
allow_dirty=0
release_workspaces=0
override_workspaces=0
planner_session_ref_inferred=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker-workspace) worker_workspace="${2:-}"; shift 2 ;;
    --planner-workspace) planner_workspace="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --supervisor-session-id) supervisor_session_ref="${2:-}"; shift 2 ;;
    --worker-artifact-root) worker_artifact_root="${2:-}"; shift 2 ;;
    --planner-artifact-root) planner_artifact_root="${2:-}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift 1 ;;
    --release-workspaces|--release-planner-workspace) release_workspaces=1; shift 1 ;;
    --override-workspaces|--override-planner-workspace) override_workspaces=1; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$worker_workspace" ]] || die "--worker-workspace is required"
[[ -n "$planner_workspace" ]] || die "--planner-workspace is required"

if (( release_workspaces == 1 && override_workspaces == 1 )); then
  die "--release-workspaces cannot be combined with --override-workspaces"
fi

if (( release_workspaces == 0 )); then
  [[ -n "$integration_branch" ]] || die "--integration-branch is required"
else
  [[ -z "$integration_branch" ]] || die "--integration-branch is not allowed with --release-workspaces"
  [[ -z "$supervisor_session_ref" ]] || die "--supervisor-session-id is not allowed with --release-workspaces"
  (( allow_dirty == 0 )) || die "--allow-dirty is not allowed with --release-workspaces"
fi

command -v git >/dev/null 2>&1 || die "git is required"
command -v jq >/dev/null 2>&1 || die "jq is required"
command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"

require_git_workspace "$worker_workspace"
require_git_workspace "$planner_workspace"
worker_workspace="$(abs_path "$worker_workspace")"
planner_workspace="$(abs_path "$planner_workspace")"

if [[ -z "$worker_artifact_root" ]]; then
  worker_artifact_root="${worker_workspace}/.agent-artifacts"
fi
if [[ -z "$planner_artifact_root" ]]; then
  planner_artifact_root="${planner_workspace}/.agent-artifacts"
fi

worker_record_file="${worker_artifact_root%/}/planner-workspace.json"
planner_record_file="${planner_artifact_root%/}/planner-workspace.json"
record_files=("$worker_record_file")
if [[ "$planner_record_file" != "$worker_record_file" ]]; then
  record_files+=("$planner_record_file")
fi

if [[ -z "$planner_session_ref" ]]; then
  planner_session_ref="$(resolve_current_session_id)"
  planner_session_ref_inferred=1
fi

if (( release_workspaces == 1 )); then
  removed_any=0
  for record_file in "${record_files[@]}"; do
    if [[ ! -f "$record_file" ]]; then
      continue
    fi
    record_planner_session_id="$(record_field "$record_file" "planner_session_id")"
    [[ -n "$record_planner_session_id" ]] || die "workspace record missing planner_session_id: ${record_file}"
    [[ "$record_planner_session_id" == "$planner_session_ref" ]] || die "workspace record planner mismatch: record='${record_planner_session_id}' expected='${planner_session_ref}' file='${record_file}'"
    rm -f "$record_file" || die "failed to remove workspace record: ${record_file}"
    removed_any=1
  done
  if (( removed_any == 0 )); then
    echo "workspaces_prepared status=already_absent worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref}"
  else
    echo "workspaces_prepared status=released worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref}"
  fi
  exit 0
fi

if (( planner_session_ref_inferred == 1 )); then
  planner_group="$(resolve_current_session_group)"
else
  planner_group="$(resolve_session_group "$planner_session_ref")"
fi

is_task_branch_ref "$integration_branch" && die "--integration-branch must be a non-task landing branch, got: ${integration_branch}"
integration_commit="$(resolve_commit_oid "$worker_workspace" "$integration_branch")"
validate_planner_closeout_workspace "$planner_workspace" "$integration_branch"
require_allowed_integration_branch_owner "$integration_branch" "$worker_workspace" "$planner_workspace"

existing_record_file=""
missing_record_file=0
for record_file in "${record_files[@]}"; do
  if [[ -f "$record_file" ]]; then
    if [[ -z "$existing_record_file" ]]; then
      existing_record_file="$record_file"
    fi
  else
    missing_record_file=1
  fi
done

if (( override_workspaces == 1 )); then
  checkout_status="$(ensure_detached_worker_head "$worker_workspace" "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record_set "overridden"
  emit_detached_head_notice
  echo "workspaces_prepared status=overridden checkout_status=${checkout_status} worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit} worker_workspace=${worker_workspace} planner_workspace=${planner_workspace}"
  exit 0
fi

if [[ -z "$existing_record_file" ]]; then
  checkout_status="$(ensure_detached_worker_head "$worker_workspace" "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record_set "created"
  emit_detached_head_notice
  echo "workspaces_prepared status=created checkout_status=${checkout_status} worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit} worker_workspace=${worker_workspace} planner_workspace=${planner_workspace}"
  exit 0
fi

validate_record_set "$existing_record_file" "${record_files[@]}"

record_planner_session_id="$(record_field "$existing_record_file" "planner_session_id")"
record_planner_group="$(record_field "$existing_record_file" "planner_group")"
record_integration_branch="$(record_field "$existing_record_file" "integration_branch")"
record_supervisor_session_id="$(record_field "$existing_record_file" "supervisor_session_id")"
record_worker_workspace="$(record_field "$existing_record_file" "worker_workspace")"
record_planner_workspace="$(record_field "$existing_record_file" "planner_workspace")"

[[ -n "$record_planner_session_id" ]] || die "workspace record missing planner_session_id: ${existing_record_file}"
[[ -n "$record_integration_branch" ]] || die "workspace record missing integration_branch: ${existing_record_file}"

if ! session_exists "$record_planner_session_id"; then
  checkout_status="$(ensure_detached_worker_head "$worker_workspace" "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record_set "stale_replaced"
  emit_detached_head_notice
  echo "workspaces_prepared status=stale_replaced checkout_status=${checkout_status} worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit} worker_workspace=${worker_workspace} planner_workspace=${planner_workspace}"
  exit 0
fi

[[ "$record_planner_session_id" == "$planner_session_ref" ]] || die "workspace record planner mismatch: record='${record_planner_session_id}' expected='${planner_session_ref}' file='${existing_record_file}'"
[[ "$record_integration_branch" == "$integration_branch" ]] || die "workspace record integration branch mismatch: record='${record_integration_branch}' expected='${integration_branch}' file='${existing_record_file}'"
if [[ -n "$record_supervisor_session_id" && -n "$supervisor_session_ref" ]]; then
  [[ "$record_supervisor_session_id" == "$supervisor_session_ref" ]] || die "workspace record supervisor mismatch: record='${record_supervisor_session_id}' expected='${supervisor_session_ref}' file='${existing_record_file}'"
fi
if [[ -n "$record_worker_workspace" ]]; then
  [[ "$record_worker_workspace" == "$worker_workspace" ]] || die "workspace record worker path mismatch: record='${record_worker_workspace}' expected='${worker_workspace}' file='${existing_record_file}'"
fi
if [[ -n "$record_planner_workspace" ]]; then
  [[ "$record_planner_workspace" == "$planner_workspace" ]] || die "workspace record planner path mismatch: record='${record_planner_workspace}' expected='${planner_workspace}' file='${existing_record_file}'"
fi

if [[ -z "$record_planner_group" || "$record_planner_group" != "$planner_group" || ( -n "$supervisor_session_ref" && "$record_supervisor_session_id" != "$supervisor_session_ref" ) || -z "$record_worker_workspace" || -z "$record_planner_workspace" || $missing_record_file -eq 1 ]]; then
  checkout_status="$(ensure_detached_worker_head "$worker_workspace" "$integration_branch" "$integration_commit" "$allow_dirty")"
  write_record_set "matched_refreshed"
  emit_detached_head_notice
  echo "workspaces_prepared status=matched_refreshed checkout_status=${checkout_status} worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit} worker_workspace=${worker_workspace} planner_workspace=${planner_workspace}"
  exit 0
fi

checkout_status="$(ensure_detached_worker_head "$worker_workspace" "$integration_branch" "$integration_commit" "$allow_dirty")"
emit_detached_head_notice
echo "workspaces_prepared status=matched checkout_status=${checkout_status} worker_record=${worker_record_file} planner_record=${planner_record_file} planner=${planner_session_ref} planner_group=${planner_group} integration_branch=${integration_branch} integration_commit=${integration_commit} worker_workspace=${worker_workspace} planner_workspace=${planner_workspace}"
