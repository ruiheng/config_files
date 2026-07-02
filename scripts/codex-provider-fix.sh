#!/usr/bin/env bash
set -euo pipefail

# Fix Codex resume visibility when a session was created under one
# model_provider (for example "openai") but you now normally run Codex under
# another provider (for example "dongdong").
#
# Why this script touches two places:
#   1. ~/.codex/state_5.sqlite keeps the indexed thread row used by Codex.
#   2. The first line of the rollout JSONL file is a session_meta record. Codex
#      may rebuild/refresh SQLite state from that file, so changing only SQLite
#      can be reverted back to the old provider.
#
# This script intentionally edits only:
#   - threads.model_provider in state_5.sqlite
#   - payload.model_provider in the rollout file's first JSON line
#
# It does not rewrite conversation history, prompts, messages, or tool output.

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
DB="$CODEX_HOME/state_5.sqlite"
BACKUP_DIR="${TMPDIR:-/tmp}/codex-provider-fix-backups"

usage() {
  cat <<'EOF'
Usage:
  ./codex-provider-fix.sh list [--cwd PATH] [--provider NAME] [--limit N]
  ./codex-provider-fix.sh mismatches [--cwd PATH] [--limit N]
  ./codex-provider-fix.sh show SESSION_ID
  ./codex-provider-fix.sh fix SESSION_ID PROVIDER
  ./codex-provider-fix.sh fix-all --from OLD_PROVIDER --to NEW_PROVIDER [--cwd PATH] --yes

Examples:
  ./codex-provider-fix.sh list --cwd /home/ruiheng/clash-docker
  ./codex-provider-fix.sh mismatches --cwd /home/ruiheng/clash-docker
  ./codex-provider-fix.sh fix 019de903-31c5-7010-acb0-51ec3310cbfb dongdong
  ./codex-provider-fix.sh fix-all --from openai --to dongdong --cwd /home/ruiheng/clash-docker --yes

Notes:
  - Requires sqlite3 and jq.
  - Backups are written under /tmp/codex-provider-fix-backups by default.
  - Stop active Codex sessions for the target thread before fixing, so Codex
    does not rewrite metadata while this script is editing it.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

quote_sql() {
  # SQLite string literal quoting: single quote becomes two single quotes.
  printf "%s" "$1" | sed "s/'/''/g"
}

db() {
  sqlite3 "$DB" "$@"
}

ensure_ready() {
  need sqlite3
  need jq
  [[ -f "$DB" ]] || die "Codex state DB not found: $DB"
  mkdir -p "$BACKUP_DIR"
}

rollout_path_for_id() {
  local id="$1"
  db "select rollout_path from threads where id='$(quote_sql "$id")';"
}

provider_in_rollout() {
  local path="$1"
  [[ -f "$path" ]] || {
    echo ""
    return
  }
  head -n 1 "$path" | jq -r '.payload.model_provider // ""'
}

show_one() {
  local id="$1"
  local path file_provider
  path="$(rollout_path_for_id "$id")"
  [[ -n "$path" ]] || die "session not found in $DB: $id"
  file_provider="$(provider_in_rollout "$path")"

  db -header -column "
    select
      id,
      model_provider as db_provider,
      source,
      thread_source,
      cwd,
      substr(replace(title, char(10), ' '), 1, 120) as title,
      archived,
      datetime(recency_at,'unixepoch','localtime') as recency
    from threads
    where id='$(quote_sql "$id")';
  "
  echo "rollout_path: $path"
  echo "rollout_provider: ${file_provider:-<missing>}"
}

list_sessions() {
  local cwd_filter="" provider_filter="" limit="80"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd) cwd_filter="${2:-}"; shift 2 ;;
      --provider) provider_filter="${2:-}"; shift 2 ;;
      --limit) limit="${2:-}"; shift 2 ;;
      *) die "unknown list option: $1" ;;
    esac
  done

  [[ "$limit" =~ ^[0-9]+$ ]] || die "--limit must be a number"

  local where="archived=0"
  [[ -z "$cwd_filter" ]] || where="$where and cwd='$(quote_sql "$cwd_filter")'"
  [[ -z "$provider_filter" ]] || where="$where and model_provider='$(quote_sql "$provider_filter")'"

  db -header -column "
    select
      id,
      model_provider,
      source,
      thread_source,
      cwd,
      substr(replace(title, char(10), ' '), 1, 120) as title,
      datetime(recency_at,'unixepoch','localtime') as recency
    from threads
    where $where
    order by recency_at_ms desc
    limit $limit;
  "
}

mismatches() {
  local cwd_filter="" limit="200"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cwd) cwd_filter="${2:-}"; shift 2 ;;
      --limit) limit="${2:-}"; shift 2 ;;
      *) die "unknown mismatches option: $1" ;;
    esac
  done

  [[ "$limit" =~ ^[0-9]+$ ]] || die "--limit must be a number"

  local where="archived=0"
  [[ -z "$cwd_filter" ]] || where="$where and cwd='$(quote_sql "$cwd_filter")'"

  # Use SQLite JSON output here because titles may contain tabs/newlines. Plain
  # TSV looks tempting, then breaks exactly on the weird transcripts this tool
  # exists to repair.
  sqlite3 -json "$DB" "
    select
      id,
      model_provider,
      rollout_path,
      cwd,
      substr(replace(title, char(10), ' '), 1, 120) as title
    from threads
    where $where
    order by recency_at_ms desc
    limit $limit;
  " | jq -c '.[]' | while IFS= read -r row; do
    id="$(printf '%s' "$row" | jq -r '.id')"
    db_provider="$(printf '%s' "$row" | jq -r '.model_provider // ""')"
    rollout="$(printf '%s' "$row" | jq -r '.rollout_path // ""')"
    cwd="$(printf '%s' "$row" | jq -r '.cwd // ""')"
    title="$(printf '%s' "$row" | jq -r '.title // ""')"
    file_provider="$(provider_in_rollout "$rollout")"
    if [[ "$db_provider" != "$file_provider" ]]; then
      printf '%s\tDB=%s\tFILE=%s\t%s\t%s\n' \
        "$id" "${db_provider:-<empty>}" "${file_provider:-<missing>}" "$cwd" "$title"
    fi
  done
}

backup_one() {
  local id="$1" rollout="$2"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"

  # SQLite .backup gives a consistent DB copy even when WAL mode is active.
  sqlite3 "$DB" ".backup '$BACKUP_DIR/state_5.$id.$stamp.sqlite'"

  if [[ -f "$rollout" ]]; then
    cp "$rollout" "$BACKUP_DIR/$(basename "$rollout").$stamp.bak"
  fi

  echo "backup_dir: $BACKUP_DIR"
}

fix_one() {
  local id="$1" provider="$2"
  local rollout tmp
  rollout="$(rollout_path_for_id "$id")"
  [[ -n "$rollout" ]] || die "session not found in $DB: $id"
  [[ -f "$rollout" ]] || die "rollout file not found: $rollout"

  backup_one "$id" "$rollout"

  # Rewrite only line 1. The remaining JSONL lines can be very large; leaving
  # them byte-for-byte alone avoids changing conversation history.
  tmp="$(mktemp "${TMPDIR:-/tmp}/codex-provider-fix.XXXXXX")"
  {
    head -n 1 "$rollout" | jq -c --arg provider "$provider" '.payload.model_provider = $provider'
    tail -n +2 "$rollout"
  } > "$tmp"
  chmod --reference="$rollout" "$tmp"
  mv "$tmp" "$rollout"

  db "update threads set model_provider='$(quote_sql "$provider")' where id='$(quote_sql "$id")';"

  echo "fixed: $id -> $provider"
  show_one "$id"
}

fix_all() {
  local from="" to="" cwd_filter="" yes="no"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --to) to="${2:-}"; shift 2 ;;
      --cwd) cwd_filter="${2:-}"; shift 2 ;;
      --yes) yes="yes"; shift ;;
      *) die "unknown fix-all option: $1" ;;
    esac
  done

  [[ -n "$from" ]] || die "fix-all requires --from OLD_PROVIDER"
  [[ -n "$to" ]] || die "fix-all requires --to NEW_PROVIDER"
  [[ "$yes" == "yes" ]] || die "fix-all requires --yes"

  local where="archived=0 and model_provider='$(quote_sql "$from")'"
  [[ -z "$cwd_filter" ]] || where="$where and cwd='$(quote_sql "$cwd_filter")'"

  mapfile -t ids < <(db "select id from threads where $where order by recency_at_ms desc;")
  [[ "${#ids[@]}" -gt 0 ]] || {
    echo "no matching sessions"
    return
  }

  echo "fixing ${#ids[@]} session(s): $from -> $to"
  for id in "${ids[@]}"; do
    fix_one "$id" "$to"
  done
}

main() {
  ensure_ready

  local cmd="${1:-}"
  [[ -n "$cmd" ]] || {
    usage
    exit 0
  }
  shift

  case "$cmd" in
    list) list_sessions "$@" ;;
    mismatches) mismatches "$@" ;;
    show)
      [[ $# -eq 1 ]] || die "show requires SESSION_ID"
      show_one "$1"
      ;;
    fix)
      [[ $# -eq 2 ]] || die "fix requires SESSION_ID PROVIDER"
      fix_one "$1" "$2"
      ;;
    fix-all) fix_all "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
