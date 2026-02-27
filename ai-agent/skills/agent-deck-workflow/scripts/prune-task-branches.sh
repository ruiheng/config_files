#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Prune stale task branches using "keep recent N + ancestor of current base" policy.

Policy:
1) Sort local task branches by committer date (newest first).
2) Keep the most recent N branches.
3) For branches outside top-N, delete only if branch tip is an ancestor of base ref
   (default base is HEAD, meaning already fast-forward absorbed by current branch line).

Usage:
  ai-agent/skills/agent-deck-workflow/scripts/prune-task-branches.sh [options]

Options:
  --keep N          Keep newest N task branches (default: 10)
  --prefix PREFIX   Branch prefix to scan (default: task/)
  --base REF        Base ref for ancestor check (default: HEAD)
  --apply           Execute deletion (default: dry-run only)
  -h, --help        Show this help

Examples:
  # Preview only
  ai-agent/skills/agent-deck-workflow/scripts/prune-task-branches.sh --keep 12

  # Delete with default base (HEAD)
  ai-agent/skills/agent-deck-workflow/scripts/prune-task-branches.sh --keep 12 --apply

  # Use an explicit base branch
  ai-agent/skills/agent-deck-workflow/scripts/prune-task-branches.sh --keep 12 --base master --apply
EOF
}

KEEP=10
PREFIX="task/"
BASE_REF="HEAD"
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --base)
      BASE_REF="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$KEEP" =~ ^[0-9]+$ ]]; then
  echo "[ERR] --keep must be a non-negative integer, got: $KEEP" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERR] Not inside a git repository." >&2
  exit 1
fi

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "[ERR] Base ref does not exist: $BASE_REF" >&2
  exit 1
fi

CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"

mapfile -t BRANCH_LINES < <(
  git for-each-ref \
    --sort=-committerdate \
    --format='%(refname:short)|%(committerdate:short)|%(committerdate:unix)' \
    "refs/heads/${PREFIX}*"
)

TOTAL="${#BRANCH_LINES[@]}"

echo "[INFO] prefix=${PREFIX} keep=${KEEP} base=${BASE_REF} mode=$([[ $APPLY -eq 1 ]] && echo apply || echo dry-run)"
echo "[INFO] matched task branches: $TOTAL"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "[OK] Nothing to do."
  exit 0
fi

DELETE_CANDIDATES=()
TABLE_ROWS=()

idx=0
for line in "${BRANCH_LINES[@]}"; do
  idx=$((idx + 1))
  IFS='|' read -r branch date_short _ <<<"$line"

  action="keep"
  reason="recent_top_${KEEP}"

  if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
    action="keep"
    reason="current_branch"
  elif [[ "$idx" -gt "$KEEP" ]]; then
    if git merge-base --is-ancestor "$branch" "$BASE_REF"; then
      action="delete"
      reason="ancestor_of_${BASE_REF}"
      DELETE_CANDIDATES+=("$branch")
    else
      action="keep"
      reason="not_ancestor_of_${BASE_REF}"
    fi
  fi

  TABLE_ROWS+=("${action}|${branch}|${date_short}|${reason}")
done

printf '\n%-8s  %-40s  %-10s  %s\n' "ACTION" "BRANCH" "DATE" "REASON"
printf '%-8s  %-40s  %-10s  %s\n' "------" "------" "----" "------"
for row in "${TABLE_ROWS[@]}"; do
  IFS='|' read -r action branch date_short reason <<<"$row"
  printf '%-8s  %-40s  %-10s  %s\n' "$action" "$branch" "$date_short" "$reason"
done

echo
echo "[INFO] delete candidates: ${#DELETE_CANDIDATES[@]}"

if [[ "$APPLY" -ne 1 ]]; then
  echo "[DRY-RUN] No branches deleted. Re-run with --apply to execute."
  exit 0
fi

deleted=0
failed=0
for branch in "${DELETE_CANDIDATES[@]}"; do
  if git branch -d "$branch" >/dev/null 2>&1; then
    echo "[DEL] $branch"
    deleted=$((deleted + 1))
  else
    echo "[WARN] Failed to delete with -d: $branch (left unchanged)"
    failed=$((failed + 1))
  fi
done

echo "[OK] deletion complete: deleted=$deleted failed=$failed"
