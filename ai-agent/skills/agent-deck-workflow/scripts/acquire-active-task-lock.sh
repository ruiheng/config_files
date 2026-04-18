#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Acquire the workflow active-task lock for one delegated task.

Usage:
  acquire-active-task-lock.sh [options]

Options:
  --workdir <path>               Required workspace path that owns .agent-artifacts/
  --task-id <id>                 Required task id
  --integration-branch <ref>     Required non-task landing branch
  --planner-session-id <id|ref>  Planner session id/ref (default: current session id)
  --coder-session-id <id|ref>    Optional coder session id/ref
  --coder-session-ref <ref>      Optional coder session ref/title
  --task-branch <ref>            Optional task branch for metadata only
  --from-address <address>       Optional sender address (default: agent-deck/<planner-session-id>)
  --to-address <address>         Optional recipient address (default: agent-deck/<coder-session-id> when provided)
  --subject <text>               Optional mailbox subject for metadata
  --artifact-root <path>         Optional artifact root (default: <workdir>/.agent-artifacts)
  -h, --help                     Show help

Exit codes:
  0: lock acquired
  2: usage/runtime validation error
  3: active-task lock exists and is not stale
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

lock_fail() {
  echo "LOCK_EXISTS: $*" >&2
  exit 3
}

resolve_current_session_id() {
  local current_json current_id
  current_json="$(agent-deck session current --json 2>/dev/null || true)"
  current_id="$(jq -r '.id // empty' <<<"$current_json" 2>/dev/null || true)"
  [[ -n "$current_id" ]] || die "failed to resolve current agent-deck session id; pass --planner-session-id"
  echo "$current_id"
}

abs_path() {
  (
    cd "$1"
    pwd -P
  )
}

session_exists() {
  local session_ref="$1"
  local shown session_id
  shown="$(agent-deck session show "$session_ref" --json 2>/dev/null || true)"
  session_id="$(jq -r '.id // empty' <<<"$shown" 2>/dev/null || true)"
  [[ -n "$session_id" ]]
}

agent_deck_address_session_ref() {
  local address="${1:-}"
  case "$address" in
    agent-deck/*) echo "${address#agent-deck/}" ;;
    *) echo "" ;;
  esac
}

read_lock_value() {
  local file="$1"
  local key="$2"
  jq -r --arg key "$key" '.[$key] // empty' "$file" 2>/dev/null || true
}

lock_block_reason() {
  local file="$1"
  local state signal_name interrupted_at

  state="$(read_lock_value "$file" "state")"
  case "$state" in
    send_interrupted_unknown)
      signal_name="$(read_lock_value "$file" "interrupted_by_signal")"
      interrupted_at="$(read_lock_value "$file" "interrupted_at")"
      printf 'prior delegate send was interrupted during mailbox send (state=%s signal=%s interrupted_at=%s); inspect mailbox delivery before deleting this lock' \
        "$state" "${signal_name:-unknown}" "${interrupted_at:-unknown}"
      ;;
    queued_receipt_unknown)
      printf 'prior delegate send succeeded but receipt could not be parsed (state=%s); inspect mailbox delivery before deleting this lock' "$state"
      ;;
    *)
      printf 'delete this directory manually after verifying the prior task is finished'
      ;;
  esac
}

lock_session_refs() {
  local file="$1"
  local refs=()
  local fallback_refs=()
  local to_ref coder_ref planner_ref from_ref ref

  to_ref="$(agent_deck_address_session_ref "$(read_lock_value "$file" "to_address")")"
  coder_ref="$(read_lock_value "$file" "coder_session_ref")"
  planner_ref="$(read_lock_value "$file" "planner_session_id")"
  from_ref="$(agent_deck_address_session_ref "$(read_lock_value "$file" "from_address")")"

  for ref in "$to_ref" "$coder_ref"; do
    if [[ -n "$ref" && ! " ${refs[*]} " =~ " ${ref} " ]]; then
      refs+=("$ref")
    fi
  done
  for ref in "$planner_ref" "$from_ref"; do
    if [[ -n "$ref" && ! " ${fallback_refs[*]} " =~ " ${ref} " ]]; then
      fallback_refs+=("$ref")
    fi
  done

  if (( ${#refs[@]} > 0 )); then
    printf '%s\n' "${refs[@]}"
  else
    printf '%s\n' "${fallback_refs[@]}"
  fi
}

active_task_lock_is_stale() {
  local file="$1"
  local refs=()
  local ref

  [[ -f "$file" ]] || return 1
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && refs+=("$ref")
  done < <(lock_session_refs "$file")
  (( ${#refs[@]} > 0 )) || return 1

  for ref in "${refs[@]}"; do
    if session_exists "$ref"; then
      return 1
    fi
  done
  return 0
}

workdir=""
task_id=""
integration_branch=""
planner_session_ref=""
coder_session_id=""
coder_session_ref=""
task_branch=""
from_address=""
to_address=""
subject=""
artifact_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) workdir="${2:-}"; shift 2 ;;
    --task-id) task_id="${2:-}"; shift 2 ;;
    --integration-branch) integration_branch="${2:-}"; shift 2 ;;
    --planner-session-id) planner_session_ref="${2:-}"; shift 2 ;;
    --coder-session-id) coder_session_id="${2:-}"; shift 2 ;;
    --coder-session-ref) coder_session_ref="${2:-}"; shift 2 ;;
    --task-branch) task_branch="${2:-}"; shift 2 ;;
    --from-address) from_address="${2:-}"; shift 2 ;;
    --to-address) to_address="${2:-}"; shift 2 ;;
    --subject) subject="${2:-}"; shift 2 ;;
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$workdir" ]] || die "--workdir is required"
[[ -d "$workdir" ]] || die "workdir does not exist: ${workdir}"
[[ -n "$task_id" ]] || die "--task-id is required"
[[ -n "$integration_branch" ]] || die "--integration-branch is required"

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v agent-deck >/dev/null 2>&1 || die "agent-deck is required"

workdir="$(abs_path "$workdir")"
if [[ -z "$planner_session_ref" ]]; then
  planner_session_ref="$(resolve_current_session_id)"
fi

if [[ -z "$from_address" ]]; then
  from_address="agent-deck/${planner_session_ref}"
fi
if [[ -z "$to_address" && -n "$coder_session_id" ]]; then
  to_address="agent-deck/${coder_session_id}"
fi
if [[ -z "$artifact_root" ]]; then
  artifact_root="${workdir}/.agent-artifacts"
fi

lock_dir="${artifact_root%/}/active-task.lock"
lock_file="${lock_dir}/lock.json"
mkdir -p "${artifact_root%/}"

stale_lock_replaced=0
if mkdir "$lock_dir" 2>/dev/null; then
  :
elif [[ -d "$lock_dir" ]]; then
  if active_task_lock_is_stale "$lock_file"; then
    rm -rf "$lock_dir" || die "failed to remove stale active-task lock: ${lock_dir}"
    mkdir "$lock_dir" || die "failed to recreate active-task lock dir: ${lock_dir}"
    stale_lock_replaced=1
  else
    existing_task_id="$(read_lock_value "$lock_file" "task_id")"
    existing_state="$(read_lock_value "$lock_file" "state")"
    block_reason="$(lock_block_reason "$lock_file")"
    [[ -n "$existing_task_id" ]] || existing_task_id="<unknown>"
    [[ -n "$existing_state" ]] || existing_state="<unknown>"
    lock_fail "active task lock exists: ${lock_dir} :: task_id=${existing_task_id} :: state=${existing_state} :: ${block_reason}"
  fi
else
  die "active-task lock path exists and is not a directory: ${lock_dir}"
fi

tmp_lock="$(mktemp)"
jq -nc \
  --arg task_id "$task_id" \
  --arg action "execute_delegate_task" \
  --arg planner_session_id "$planner_session_ref" \
  --arg from_address "$from_address" \
  --arg to_address "$to_address" \
  --arg subject "$subject" \
  --arg task_branch "$task_branch" \
  --arg integration_branch "$integration_branch" \
  --arg coder_session_ref "$coder_session_ref" \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    task_id: $task_id,
    action: $action,
    state: "pending_send",
    planner_session_id: (if $planner_session_id == "" then null else $planner_session_id end),
    from_address: (if $from_address == "" then null else $from_address end),
    to_address: (if $to_address == "" then null else $to_address end),
    subject: (if $subject == "" then null else $subject end),
    task_branch: (if $task_branch == "" then null else $task_branch end),
    integration_branch: $integration_branch,
    coder_session_ref: (if $coder_session_ref == "" then null else $coder_session_ref end),
    created_at: $created_at
  }' >"$tmp_lock"
mv "$tmp_lock" "$lock_file"

echo "active_task_lock status=$( (( stale_lock_replaced == 1 )) && printf '%s' 'stale_replaced' || printf '%s' 'acquired' ) lock_dir=${lock_dir} lock_file=${lock_file}"
