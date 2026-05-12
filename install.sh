#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
FORCE=0
BIN_DIR="${HOME}/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Install POSIX agent workflow entrypoints.

Usage:
  ./install.sh [options]

Options:
  --dry-run        Show actions without changing files
  --force          Backup and replace existing targets
  --bin-dir <dir>  Command shim directory (default: ~/.local/bin)
  -h, --help       Show help
EOF
}

log() {
  printf '[%s] %s\n' "$1" "$2"
}

backup_path() {
  local path="$1"
  local backup="${path}.backup.$(date +%Y%m%d_%H%M%S)"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY RUN" "Would backup: $path -> $backup"
    return 0
  fi
  mv "$path" "$backup"
  log "INFO" "Backed up: $path -> $backup"
}

link_path() {
  local source="$1"
  local target="$2"
  local target_dir
  target_dir="$(dirname "$target")"

  if [[ ! -e "$source" ]]; then
    log "ERR" "Source does not exist: $source"
    return 1
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY RUN" "Would create directory: $target_dir"
  else
    mkdir -p "$target_dir"
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ -L "$target" ]]; then
      local current
      current="$(readlink "$target")"
      if [[ "$current" != /* ]]; then
        current="$(cd "$(dirname "$target")" >/dev/null 2>&1 && cd "$(dirname "$current")" >/dev/null 2>&1 && pwd)/$(basename "$current")"
      fi
      if [[ "$current" == "$source" ]]; then
        log "SKIP" "Already linked: $target"
        return 0
      fi
    fi

    if [[ $FORCE -ne 1 ]]; then
      log "SKIP" "Exists: $target"
      return 0
    fi
    backup_path "$target"
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY RUN" "Would link: $target -> $source"
    return 0
  fi

  ln -s "$source" "$target"
  log "OK" "Linked: $target -> $source"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --bin-dir)
      BIN_DIR="${2:?--bin-dir requires a path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "ERR" "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
AI_AGENT_TARGET="$CONFIG_HOME/ai-agent"
ADWF_TARGET="$BIN_DIR/adwf"

link_path "$SCRIPT_DIR/ai-agent" "$AI_AGENT_TARGET"
link_path "$SCRIPT_DIR/ai-agent/bin/adwf" "$ADWF_TARGET"

case ":$PATH:" in
  *":$BIN_DIR:"*) log "OK" "PATH includes: $BIN_DIR" ;;
  *)
    log "SKIP" "PATH does not include: $BIN_DIR"
    log "INFO" "Add this to your shell config: export PATH=\"$BIN_DIR:\$PATH\""
    ;;
esac
