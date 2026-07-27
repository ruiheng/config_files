#!/usr/bin/env bash
#
# Config Files Installation Script
# Copies configuration files and links shared agent assets from a stable install path
#
# Usage: ./install.sh [OPTIONS]
#
# Options:
#   --dry-run     Show what would be done without making changes
#   --force       Backup and replace existing files (be careful!)
#   --no-color    Disable colored output
#   --help        Show this help message
#

set -uo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Script directory (where this script resides)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILES_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/config_files"
readonly MANAGED_PATHS_FILE="$CONFIG_FILES_STATE_DIR/managed-paths"
readonly MANAGED_COPIES_DIR="$CONFIG_FILES_STATE_DIR/managed-copies"
readonly SHARED_INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/config_files"
readonly SHARED_AI_AGENT_DIR="$SHARED_INSTALL_ROOT/ai-agent"

# Command line flags
DRY_RUN=0
FORCE=0
INTERACTIVE=0
USE_COLOR=1

# Interactive mode defaults (for 'all' responses)
ALL_SKIP=0
ALL_BACKUP=0
ALL_REPLACE=0

# Optional integration flags
AGENT_DECK_AVAILABLE=0
WAYPOST_MCP_AVAILABLE=0
CODEX_SKILLS_DIR_READY=0
CLAUDE_CODE_AVAILABLE=0
CODEX_CLI_AVAILABLE=0
NVM_NODE_AVAILABLE=0
SHARED_AI_AGENT_READY=0
CODEX_CLI_COMMAND="codex"
NVM_VERSION="v0.40.3"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh"
RUSTUP_INSTALL_URL="https://sh.rustup.rs"
MQ_VERSION="v0.7.0"
MQ_RELEASE_BASE_URL="https://github.com/harehare/mq/releases/download/$MQ_VERSION"
CLAUDE_CODE_INSTALL_URL="https://claude.ai/install.sh"
ANTIGRAVITY_INSTALL_URL="https://antigravity.google/cli/install.sh"
ANTIGRAVITY_INSTALL_SHA256="ee1ea43ce4e9e56356c4ab6dad907ef357ae4bdfcaadb682735909fb57c9c640"
AGENT_DECK_VERSION="v1.10.10"
AGENT_DECK_INSTALL_COMMIT="1e879a189afa1d0803485361432ff12c958b6d56"
AGENT_DECK_INSTALL_URL="https://raw.githubusercontent.com/asheshgoplani/agent-deck/$AGENT_DECK_INSTALL_COMMIT/install.sh"
AGENT_DECK_INSTALL_SHA256="ea85297639d0c02ec61a89ac80d40f507a0c9096331c28b777c5ac0123001b11"
# Keep enough MCP time for Waypost operations.
WAYPOST_MCP_TOOL_TIMEOUT_SEC=660
WAYPOST_MCP_TOOL_TIMEOUT_MS=660000

WAYPOST_MCP_TOOL_NAMES=(
    agent_deck_create_session
    agent_deck_require_session
    agent_deck_resolve_session
    waypost_ack
    waypost_address_inspect
    waypost_bind
    waypost_claim_history
    waypost_debug
    waypost_defer
    waypost_fail
    waypost_forward
    waypost_group_add_member
    waypost_group_add_subscriber
    waypost_group_create
    waypost_group_members
    waypost_group_remove_member
    waypost_group_remove_subscriber
    waypost_group_subscribers
    waypost_list
    waypost_read
    waypost_recv
    waypost_release
    waypost_send
    waypost_status
    waypost_undefer
    waypost_wait
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters for summary
declare -i copied=0 linked=0 skipped=0 failed=0 backed_up=0

# =============================================================================
# Command Line Parsing
# =============================================================================

parse_args() {
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
            --interactive|-i)
                INTERACTIVE=1
                shift
                ;;
            --no-color)
                USE_COLOR=0
                RED='' GREEN='' YELLOW='' BLUE='' NC=''
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << 'EOF'
Config Files Installation Script

Usage: ./install.sh [OPTIONS]

Options:
  --dry-run         Show what would be done without making changes
  --force           Backup and replace existing files (be careful!)
  --interactive, -i Prompt when target exists (asks: skip/backup/replace/all)
  --no-color        Disable colored output
  --help, -h        Show this help message

Examples:
  ./install.sh                  # Standard installation
  ./install.sh --dry-run        # Preview changes
  ./install.sh --force          # Replace existing configs (backs them up)
  ./install.sh --interactive    # Prompt for each conflict
EOF
}

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERR]${NC} $1"
}

log_dry() {
    echo -e "${BLUE}[DRY RUN]${NC} $1"
}

ensure_path_contains_local_bin() {
    local local_bin="$HOME/.local/bin"

    case ":$PATH:" in
        *":$local_bin:"*)
            log_ok "PATH includes: $local_bin"
            return 0
            ;;
    esac

    export PATH="$local_bin:$PATH"
    log_info "Added to installer PATH: $local_bin"
    return 0
}

# Prompt user for action when target exists
# $1: target path
# Returns: 0=skip, 1=backup, 2=replace, 3=cancel
prompt_user() {
    local target="$1"
    local response

    # Check if 'all' defaults have been set
    if [[ $ALL_SKIP -eq 1 ]]; then
        return 0
    elif [[ $ALL_BACKUP -eq 1 ]]; then
        return 1
    elif [[ $ALL_REPLACE -eq 1 ]]; then
        return 2
    fi

    echo ""
    log_warn "Target already exists: $target"

    while true; do
        echo -ne "${BLUE}[PROMPT]${NC} [s]kip, [b]ackup & replace, [f]orce replace, [S]kip all, [B]ackup all, [F]orce all, [c]ancel: "
        read -r response

        case "$response" in
            s|skip|"")
                return 0
                ;;
            b|backup)
                return 1
                ;;
            f|force)
                return 2
                ;;
            S|"skip all")
                ALL_SKIP=1
                return 0
                ;;
            B|"backup all")
                ALL_BACKUP=1
                return 1
                ;;
            F|"force all")
                ALL_REPLACE=1
                return 2
                ;;
            c|cancel)
                return 3
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
}

# Backup a file/directory before replacing it
# $1: path to backup
backup_item() {
    local item="$1"
    local backup_name="${item}.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would backup: $item -> $backup_name"
        return 0
    fi

    if mv "$item" "$backup_name"; then
        log_info "Backed up: $item -> $backup_name"
        backed_up=$((backed_up + 1))
        return 0
    else
        log_error "Failed to backup: $item"
        failed=$((failed + 1))
        return 1
    fi
}

resolve_symlink_target_path() {
    local link_path="$1"
    local target
    local candidate
    local candidate_dir

    target="$(readlink "$link_path")" || return 1
    if [[ "$target" == /* ]]; then
        candidate="$target"
    else
        candidate="$(dirname "$link_path")/$target"
    fi

    candidate_dir="$(dirname "$candidate")"
    if [[ -d "$candidate_dir" ]]; then
        printf '%s/%s\n' "$(cd "$candidate_dir" && pwd -P)" "$(basename "$candidate")"
    else
        printf '%s\n' "$candidate"
    fi
}

normalize_path() {
    local path="$1"
    local path_dir

    path_dir="$(dirname "$path")"
    if [[ -d "$path_dir" ]]; then
        printf '%s/%s\n' "$(cd "$path_dir" && pwd -P)" "$(basename "$path")"
    else
        printf '%s\n' "$path"
    fi
}

symlink_points_to() {
    local link_path="$1"
    local expected_path="$2"
    local actual_target
    local expected_target

    [[ -L "$link_path" ]] || return 1
    actual_target="$(resolve_symlink_target_path "$link_path")" || return 1
    expected_target="$(normalize_path "$expected_path")" || return 1
    [[ "$actual_target" == "$expected_target" ]]
}

symlink_points_to_any() {
    local link_path="$1"
    local expected_path

    shift
    for expected_path in "$@"; do
        if symlink_points_to "$link_path" "$expected_path"; then
            return 0
        fi
    done

    return 1
}

normalize_absolute_path_lexically() {
    local path="$1"
    local component
    local last_index
    local result=""
    local -a components=()
    local -a normalized_parts=()

    [[ "$path" == /* ]] || return 1
    IFS='/' read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        case "$component" in
            ''|.)
                ;;
            ..)
                if [[ ${#normalized_parts[@]} -gt 0 ]]; then
                    last_index=$((${#normalized_parts[@]} - 1))
                    unset "normalized_parts[$last_index]"
                fi
                ;;
            *)
                normalized_parts+=("$component")
                ;;
        esac
    done

    for component in "${normalized_parts[@]}"; do
        result="$result/$component"
    done
    printf '%s\n' "${result:-/}"
}

canonicalize_path_allow_missing() {
    local input_path="$1"
    local depth="${2:-0}"
    local path
    local probe
    local suffix=""
    local canonical_root
    local probe_parent
    local target
    local target_path

    if (( depth >= 40 )); then
        return 1
    fi

    path="$(normalize_absolute_path_lexically "$input_path")" || return 1
    probe="$path"
    while [[ "$probe" != / && ! -e "$probe" && ! -L "$probe" ]]; do
        suffix="/$(basename "$probe")$suffix"
        probe="$(dirname "$probe")"
    done

    if [[ -d "$probe" ]]; then
        canonical_root="$(cd "$probe" && pwd -P)" || return 1
    elif [[ -L "$probe" ]]; then
        target="$(readlink "$probe")" || return 1
        if [[ "$target" == /* ]]; then
            target_path="$target"
        else
            target_path="$(dirname "$probe")/$target"
        fi
        canonical_root="$(canonicalize_path_allow_missing "$target_path" "$((depth + 1))")" \
            || return 1
    elif [[ "$probe" == / ]]; then
        canonical_root=/
    else
        probe_parent="$(dirname "$probe")"
        canonical_root="$(cd "$probe_parent" && pwd -P)/$(basename "$probe")" || return 1
    fi

    if [[ "$canonical_root" == / ]]; then
        printf '/%s\n' "${suffix#/}"
    else
        printf '%s%s\n' "$canonical_root" "$suffix"
    fi
}

projected_symlink_target_path() {
    local staged_link="$1"
    local staged_root="$2"
    local dst_root="$3"
    local target
    local projected_link
    local relative_path
    local candidate

    target="$(readlink "$staged_link")" || return 1
    if [[ "$staged_link" == "$staged_root" ]]; then
        projected_link="$dst_root"
    else
        relative_path="${staged_link#"$staged_root"/}"
        projected_link="$dst_root/$relative_path"
    fi

    if [[ "$target" == /* ]]; then
        candidate="$target"
    else
        candidate="$(dirname "$projected_link")/$target"
    fi
    canonicalize_path_allow_missing "$candidate"
}

path_is_within() {
    local path="$1"
    local root="$2"

    [[ "$path" == "$root" || "$path" == "$root/"* ]]
}

projected_symlink_points_into() {
    local staged_link="$1"
    local staged_root="$2"
    local dst_root="$3"
    local root="$4"
    local target
    local canonical_root

    [[ -L "$staged_link" ]] || return 1
    target="$(projected_symlink_target_path "$staged_link" "$staged_root" "$dst_root")" || return 1
    canonical_root="$(canonicalize_path_allow_missing "$root")" || return 1
    path_is_within "$target" "$canonical_root"
}

ensure_parent_directory() {
    local path="$1"
    local parent

    parent="$(dirname "$path")"
    if [[ -d "$parent" ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would create directory: $parent"
        return 0
    fi

    if mkdir -p "$parent"; then
        log_info "Created directory: $parent"
        return 0
    fi

    log_error "Failed to create directory: $parent"
    return 1
}

managed_path_is_recorded() {
    local path="$1"

    [[ -f "$MANAGED_PATHS_FILE" ]] && grep -Fqx "$path" "$MANAGED_PATHS_FILE"
}

record_managed_path() {
    local path="$1"

    if [[ $DRY_RUN -eq 1 ]] || managed_path_is_recorded "$path"; then
        return 0
    fi

    if ! mkdir -p "$CONFIG_FILES_STATE_DIR"; then
        log_error "Failed to create installer state directory: $CONFIG_FILES_STATE_DIR"
        return 1
    fi

    if printf '%s\n' "$path" >> "$MANAGED_PATHS_FILE"; then
        return 0
    fi

    log_error "Failed to record managed path: $path"
    return 1
}

managed_copy_snapshot_path() {
    local path="$1"

    if [[ "$path" != /* ]]; then
        log_error "Managed copy path must be absolute: $path"
        return 1
    fi

    printf '%s%s\n' "$MANAGED_COPIES_DIR" "$path"
}

remove_installed_path() {
    local path="$1"

    if [[ -d "$path" && ! -L "$path" ]]; then
        rm -rf "$path"
    else
        rm -f "$path"
    fi
}

path_mode() {
    local path="$1"

    case "$OS" in
        macos)
            stat -f '%Lp' "$path"
            ;;
        *)
            stat -c '%a' "$path"
            ;;
    esac
}

path_mode_matches() {
    local source_path="$1"
    local target_path="$2"
    local source_mode
    local target_mode

    source_mode="$(path_mode "$source_path")" || return 1
    target_mode="$(path_mode "$target_path")" || return 1
    [[ "$source_mode" == "$target_mode" ]]
}

source_copy_path_is_excluded() {
    local source_root="$1"
    local source_path="$2"
    local relative_path

    [[ -n "$source_root" && "$source_path" == "$source_root/"* ]] || return 1
    relative_path="${source_path#"$source_root"/}"

    case "/$relative_path/" in
        */.git/*|*/node_modules/*)
            return 0
            ;;
    esac
    return 1
}

source_copy_path_exists() {
    local source_root="$1"
    local source_path="$2"

    ! source_copy_path_is_excluded "$source_root" "$source_path" \
        && installed_path_exists "$source_path"
}

# $3: source root used to omit paths excluded by stage_copy_item (optional)
source_matches_installed_copy() {
    local src="$1"
    local dst="$2"
    local source_root="${3:-}"
    local src_item
    local dst_item
    local relative_path
    local matches=1

    if [[ -L "$src" ]]; then
        [[ -L "$dst" ]] && [[ "$(readlink "$src")" == "$(readlink "$dst")" ]]
        return $?
    fi

    if [[ -d "$src" && -d "$dst" && ! -L "$dst" ]]; then
        if ! path_mode_matches "$src" "$dst"; then
            matches=0
        fi

        while IFS= read -r -d '' src_item; do
            if [[ "$src_item" == "$src" ]]; then
                continue
            fi

            if source_copy_path_is_excluded "$source_root" "$src_item"; then
                continue
            fi

            relative_path="${src_item#"$src"/}"
            dst_item="$dst/$relative_path"

            if [[ -L "$src_item" ]]; then
                if [[ ! -L "$dst_item" ]] \
                    || [[ "$(readlink "$src_item")" != "$(readlink "$dst_item")" ]]; then
                    matches=0
                fi
            elif [[ -d "$src_item" ]]; then
                if [[ ! -d "$dst_item" || -L "$dst_item" ]] \
                    || ! path_mode_matches "$src_item" "$dst_item"; then
                    matches=0
                fi
            elif [[ -f "$src_item" ]]; then
                if [[ ! -f "$dst_item" || -L "$dst_item" ]] \
                    || ! cmp -s "$src_item" "$dst_item" \
                    || ! path_mode_matches "$src_item" "$dst_item"; then
                    matches=0
                fi
            fi
        done < <(find "$src" -print0)

        while IFS= read -r -d '' dst_item; do
            if [[ "$dst_item" == "$dst" ]]; then
                continue
            fi

            relative_path="${dst_item#"$dst"/}"
            src_item="$src/$relative_path"
            if source_copy_path_is_excluded "$source_root" "$src_item" \
                || [[ ! -e "$src_item" && ! -L "$src_item" ]]; then
                matches=0
            fi
        done < <(find "$dst" -print0)

        [[ $matches -eq 1 ]]
        return
    fi

    if [[ -f "$src" && -f "$dst" && ! -L "$dst" ]]; then
        cmp -s "$src" "$dst" && path_mode_matches "$src" "$dst"
        return $?
    fi

    return 1
}

copy_installed_item() {
    local src="$1"
    local dst="$2"

    ensure_parent_directory "$dst" || return 1
    if [[ -e "$dst" || -L "$dst" ]]; then
        remove_installed_path "$dst"
    fi

    if cp -pPR "$src" "$dst"; then
        return 0
    fi

    log_error "Failed to preserve user-managed path: $src"
    return 1
}

MANAGED_COPY_BACKUP_REQUIRED=0

managed_copy_conflict() {
    local path="$1"

    if [[ $FORCE -eq 1 ]]; then
        MANAGED_COPY_BACKUP_REQUIRED=1
        log_warn "Replacing conflicting managed path because --force was used: $path"
        return 0
    fi

    log_error "Managed copy conflict: $path"
    log_error "Both the installed path and repository source changed; rerun with --force to back up and replace the conflict"
    return 1
}

merge_managed_directory_mode() {
    local base="$1"
    local live="$2"
    local staged="$3"
    local display_path="$4"
    local live_mode

    if path_mode_matches "$base" "$live"; then
        return 0
    fi

    if path_mode_matches "$base" "$staged"; then
        live_mode="$(path_mode "$live")" || return 1
        chmod "$live_mode" "$staged"
        return $?
    fi

    if path_mode_matches "$live" "$staged"; then
        return 0
    fi

    managed_copy_conflict "$display_path"
}

installed_path_exists() {
    [[ -e "$1" || -L "$1" ]]
}

find_immediate_children() {
    find "$1" ! -path "$1" -prune -print0
}

directory_has_children() {
    local child

    IFS= read -r -d '' child < <(find_immediate_children "$1")
}

merge_managed_directory_children() {
    local base="$1"
    local live="$2"
    local staged="$3"
    local display_path="$4"
    local child
    local child_name

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        merge_managed_item \
            "$child" \
            "$live/$child_name" \
            "$staged/$child_name" \
            "$display_path/$child_name" || return 1
    done < <(find_immediate_children "$base")

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        if installed_path_exists "$base/$child_name"; then
            continue
        fi
        merge_managed_item \
            "$base/$child_name" \
            "$child" \
            "$staged/$child_name" \
            "$display_path/$child_name" || return 1
    done < <(find_immediate_children "$live")

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        if installed_path_exists "$base/$child_name" \
            || installed_path_exists "$live/$child_name"; then
            continue
        fi
        merge_managed_item \
            "$base/$child_name" \
            "$live/$child_name" \
            "$child" \
            "$display_path/$child_name" || return 1
    done < <(find_immediate_children "$staged")
}

merge_deleted_managed_directory() {
    local base="$1"
    local live="$2"
    local staged="$3"
    local display_path="$4"
    local live_mode

    if ! mkdir "$staged"; then
        log_error "Failed to stage locally retained directory: $display_path"
        return 1
    fi

    live_mode="$(path_mode "$live")" || return 1
    chmod "$live_mode" "$staged" || return 1

    merge_managed_directory_children \
        "$base" "$live" "$staged" "$display_path" || return 1

    # If no target-only content survived, honor the upstream directory deletion.
    if ! directory_has_children "$staged"; then
        if ! rmdir "$staged"; then
            log_error "Failed to remove empty staged directory: $display_path"
            return 1
        fi
    fi
    return 0
}

# Three-way merge: previous installed snapshot, live target, current staged source.
# Presence is part of the state: local and upstream deletions are changes, and
# conflicting changes require --force just like content or type conflicts.
merge_managed_item() {
    local base="$1"
    local live="$2"
    local staged="$3"
    local display_path="$4"
    local base_exists=0
    local live_exists=0
    local staged_exists=0

    installed_path_exists "$base" && base_exists=1
    installed_path_exists "$live" && live_exists=1
    installed_path_exists "$staged" && staged_exists=1

    if [[ $base_exists -eq 0 ]]; then
        if [[ $live_exists -eq 0 ]]; then
            return 0
        fi
        if [[ $staged_exists -eq 0 ]]; then
            copy_installed_item "$live" "$staged"
            return $?
        fi
        if source_matches_installed_copy "$live" "$staged"; then
            return 0
        fi
        managed_copy_conflict "$display_path"
        return $?
    fi

    if [[ $live_exists -eq 0 ]]; then
        if [[ $staged_exists -eq 0 ]]; then
            return 0
        fi
        if source_matches_installed_copy "$base" "$staged"; then
            remove_installed_path "$staged"
            return 0
        fi
        managed_copy_conflict "$display_path"
        return $?
    fi

    if [[ $staged_exists -eq 0 ]]; then
        if source_matches_installed_copy "$live" "$base"; then
            return 0
        fi

        if [[ -d "$base" && ! -L "$base" \
            && -d "$live" && ! -L "$live" ]]; then
            merge_deleted_managed_directory \
                "$base" "$live" "$staged" "$display_path"
            return $?
        fi

        managed_copy_conflict "$display_path"
        return $?
    fi

    if source_matches_installed_copy "$live" "$base"; then
        return 0
    fi

    if source_matches_installed_copy "$live" "$staged"; then
        return 0
    fi

    if source_matches_installed_copy "$base" "$staged"; then
        copy_installed_item "$live" "$staged"
        return $?
    fi

    if [[ -d "$base" && ! -L "$base" \
        && -d "$live" && ! -L "$live" \
        && -d "$staged" && ! -L "$staged" ]]; then
        merge_managed_directory_mode "$base" "$live" "$staged" "$display_path" || return 1
        merge_managed_directory_children "$base" "$live" "$staged" "$display_path"
        return $?
    fi

    managed_copy_conflict "$display_path"
}

# Dry-run merge analysis mirrors merge_managed_item without creating a staged copy.
DRY_RUN_MERGE_CHANGED=0
DRY_RUN_MERGE_ITEM_EXISTS=0

mark_dry_run_merge_change() {
    DRY_RUN_MERGE_CHANGED=1
}

dry_run_merge_managed_directory_mode() {
    local base="$1"
    local live="$2"
    local upstream="$3"
    local display_path="$4"

    if path_mode_matches "$base" "$live"; then
        if ! path_mode_matches "$live" "$upstream"; then
            mark_dry_run_merge_change
        fi
        return 0
    fi

    if path_mode_matches "$base" "$upstream" \
        || path_mode_matches "$live" "$upstream"; then
        return 0
    fi

    managed_copy_conflict "$display_path" || return 1
    mark_dry_run_merge_change
}

dry_run_merge_directory_children() {
    local base="$1"
    local live="$2"
    local upstream="$3"
    local display_path="$4"
    local source_root="$5"
    local child
    local child_name

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        dry_run_merge_item \
            "$child" \
            "$live/$child_name" \
            "$upstream/$child_name" \
            "$display_path/$child_name" \
            "$source_root" || return 1
    done < <(find_immediate_children "$base")

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        if installed_path_exists "$base/$child_name"; then
            continue
        fi
        dry_run_merge_item \
            "$base/$child_name" \
            "$child" \
            "$upstream/$child_name" \
            "$display_path/$child_name" \
            "$source_root" || return 1
    done < <(find_immediate_children "$live")

    while IFS= read -r -d '' child; do
        if source_copy_path_is_excluded "$source_root" "$child"; then
            continue
        fi
        child_name="${child##*/}"
        if installed_path_exists "$base/$child_name" \
            || installed_path_exists "$live/$child_name"; then
            continue
        fi
        dry_run_merge_item \
            "$base/$child_name" \
            "$live/$child_name" \
            "$child" \
            "$display_path/$child_name" \
            "$source_root" || return 1
    done < <(find_immediate_children "$upstream")
}

dry_run_merge_deleted_managed_directory() {
    local base="$1"
    local live="$2"
    local upstream="$3"
    local display_path="$4"
    local source_root="$5"
    local child
    local child_name
    local child_exists
    local retained_child=0

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        dry_run_merge_item \
            "$child" \
            "$live/$child_name" \
            "$upstream/$child_name" \
            "$display_path/$child_name" \
            "$source_root" || return 1
        child_exists=$DRY_RUN_MERGE_ITEM_EXISTS
        if [[ $child_exists -eq 1 ]]; then
            retained_child=1
        fi
    done < <(find_immediate_children "$base")

    while IFS= read -r -d '' child; do
        child_name="${child##*/}"
        if installed_path_exists "$base/$child_name"; then
            continue
        fi
        dry_run_merge_item \
            "$base/$child_name" \
            "$child" \
            "$upstream/$child_name" \
            "$display_path/$child_name" \
            "$source_root" || return 1
        child_exists=$DRY_RUN_MERGE_ITEM_EXISTS
        if [[ $child_exists -eq 1 ]]; then
            retained_child=1
        fi
    done < <(find_immediate_children "$live")

    if [[ $retained_child -eq 1 ]]; then
        DRY_RUN_MERGE_ITEM_EXISTS=1
        return 0
    fi

    DRY_RUN_MERGE_ITEM_EXISTS=0
    mark_dry_run_merge_change
}

dry_run_merge_item() {
    local base="$1"
    local live="$2"
    local upstream="$3"
    local display_path="$4"
    local source_root="$5"
    local base_exists=0
    local live_exists=0
    local upstream_exists=0

    DRY_RUN_MERGE_ITEM_EXISTS=0
    installed_path_exists "$base" && base_exists=1
    installed_path_exists "$live" && live_exists=1
    source_copy_path_exists "$source_root" "$upstream" && upstream_exists=1

    if [[ $base_exists -eq 0 ]]; then
        if [[ $live_exists -eq 0 ]]; then
            if [[ $upstream_exists -eq 1 ]]; then
                DRY_RUN_MERGE_ITEM_EXISTS=1
                mark_dry_run_merge_change
            fi
            return 0
        fi
        if [[ $upstream_exists -eq 0 ]]; then
            DRY_RUN_MERGE_ITEM_EXISTS=1
            return 0
        fi
        if source_matches_installed_copy "$upstream" "$live" "$source_root"; then
            DRY_RUN_MERGE_ITEM_EXISTS=1
            return 0
        fi
        managed_copy_conflict "$display_path" || return 1
        DRY_RUN_MERGE_ITEM_EXISTS=1
        mark_dry_run_merge_change
        return 0
    fi

    if [[ $live_exists -eq 0 ]]; then
        if [[ $upstream_exists -eq 0 ]]; then
            return 0
        fi
        if source_matches_installed_copy "$upstream" "$base" "$source_root"; then
            return 0
        fi
        managed_copy_conflict "$display_path" || return 1
        DRY_RUN_MERGE_ITEM_EXISTS=1
        mark_dry_run_merge_change
        return 0
    fi

    if [[ $upstream_exists -eq 0 ]]; then
        if source_matches_installed_copy "$base" "$live"; then
            mark_dry_run_merge_change
            return 0
        fi

        if [[ -d "$base" && ! -L "$base" \
            && -d "$live" && ! -L "$live" ]]; then
            dry_run_merge_deleted_managed_directory \
                "$base" "$live" "$upstream" "$display_path" "$source_root"
            return $?
        fi

        managed_copy_conflict "$display_path" || return 1
        mark_dry_run_merge_change
        return 0
    fi

    if source_matches_installed_copy "$base" "$live"; then
        DRY_RUN_MERGE_ITEM_EXISTS=1
        if ! source_matches_installed_copy "$upstream" "$live" "$source_root"; then
            mark_dry_run_merge_change
        fi
        return 0
    fi

    if source_matches_installed_copy "$upstream" "$live" "$source_root" \
        || source_matches_installed_copy "$upstream" "$base" "$source_root"; then
        DRY_RUN_MERGE_ITEM_EXISTS=1
        return 0
    fi

    if [[ -d "$base" && ! -L "$base" \
        && -d "$live" && ! -L "$live" \
        && -d "$upstream" && ! -L "$upstream" ]]; then
        dry_run_merge_managed_directory_mode \
            "$base" "$live" "$upstream" "$display_path" || return 1
        dry_run_merge_directory_children \
            "$base" "$live" "$upstream" "$display_path" "$source_root" || return 1
        DRY_RUN_MERGE_ITEM_EXISTS=1
        return 0
    fi

    managed_copy_conflict "$display_path" || return 1
    DRY_RUN_MERGE_ITEM_EXISTS=1
    mark_dry_run_merge_change
}

plan_copy_deployment() {
    local src="$1"
    local dst="$2"
    local base="${3:-}"
    local final_exists=1

    MANAGED_COPY_CHANGED=0
    MANAGED_COPY_BACKUP_REQUIRED=0

    if [[ -n "$base" ]]; then
        DRY_RUN_MERGE_CHANGED=0
        dry_run_merge_item "$base" "$dst" "$src" "$dst" "$src" || return 1
        final_exists=$DRY_RUN_MERGE_ITEM_EXISTS
        MANAGED_COPY_CHANGED=$DRY_RUN_MERGE_CHANGED
    elif [[ -e "$dst" || -L "$dst" ]] \
        && source_matches_installed_copy "$src" "$dst" "$src"; then
        return 0
    else
        MANAGED_COPY_CHANGED=1
    fi

    if [[ $final_exists -eq 0 ]]; then
        if ! installed_path_exists "$dst"; then
            return 0
        fi
        if [[ $MANAGED_COPY_BACKUP_REQUIRED -eq 1 ]]; then
            backup_item "$dst" || return 1
        fi
        MANAGED_COPY_CHANGED=1
        return 0
    fi

    if [[ $MANAGED_COPY_BACKUP_REQUIRED -eq 1 \
        && ( -e "$dst" || -L "$dst" ) ]]; then
        backup_item "$dst" || return 1
    fi

    return 0
}

stage_copy_item() {
    local src="$1"
    local staged_item="$2"
    local archive="$3"

    if [[ -d "$src" ]]; then
        mkdir "$staged_item" \
            && tar -C "$src" \
                --exclude='.git' --exclude='*/.git' \
                --exclude='node_modules' --exclude='*/node_modules' \
                -cf "$archive" . \
            && tar -C "$staged_item" -xf "$archive"
        return $?
    fi

    cp -pL "$src" "$staged_item"
}

MANAGED_COPY_CHANGED=0

# $3: previous installed snapshot used for three-way merge (optional)
# $4: final runtime path used to validate staged symlinks (optional)
deploy_copy() {
    local src="$1"
    local dst="$2"
    local base="${3:-}"
    local validation_dst="${4:-$dst}"
    local dst_dir
    local staging_dir
    local staged_item
    local archive
    local previous_item
    local staged_link

    if [[ $DRY_RUN -eq 1 ]]; then
        plan_copy_deployment "$src" "$dst" "$base"
        return $?
    fi

    dst_dir="$(dirname "$dst")"
    staging_dir="$(mktemp -d "$dst_dir/.config-files-install.XXXXXX")" || {
        log_error "Failed to create staging directory for: $dst"
        return 1
    }
    staged_item="$staging_dir/item"
    archive="$staging_dir/source.tar"
    previous_item="$staging_dir/previous"
    MANAGED_COPY_CHANGED=0
    MANAGED_COPY_BACKUP_REQUIRED=0

    if ! stage_copy_item "$src" "$staged_item" "$archive"; then
        rm -rf "$staging_dir"
        log_error "Failed to stage copy: $src"
        return 1
    fi
    rm -f "$archive"

    if [[ -n "$base" ]]; then
        if ! merge_managed_item "$base" "$dst" "$staged_item" "$dst"; then
            rm -rf "$staging_dir"
            return 1
        fi
    fi

    if ! installed_path_exists "$staged_item"; then
        if ! installed_path_exists "$dst"; then
            rm -rf "$staging_dir"
            return 0
        fi

        if [[ $MANAGED_COPY_BACKUP_REQUIRED -eq 1 ]]; then
            if ! backup_item "$dst"; then
                rm -rf "$staging_dir"
                return 1
            fi
        fi

        if installed_path_exists "$dst" && ! mv "$dst" "$previous_item"; then
            rm -rf "$staging_dir"
            log_error "Failed to move existing path out of the way: $dst"
            return 1
        fi
        remove_installed_path "$previous_item"
        rm -rf "$staging_dir"
        MANAGED_COPY_CHANGED=1
        return 0
    fi

    while IFS= read -r -d '' staged_link; do
        if projected_symlink_points_into \
            "$staged_link" \
            "$staged_item" \
            "$validation_dst" \
            "$SCRIPT_DIR"; then
            rm -rf "$staging_dir"
            log_error "Refusing to install symlink that points into the repository: $staged_link"
            return 1
        fi
    done < <(find "$staged_item" -type l -print0 2>/dev/null)

    if [[ -e "$dst" || -L "$dst" ]] \
        && source_matches_installed_copy "$staged_item" "$dst"; then
        rm -rf "$staging_dir"
        return 0
    fi

    if [[ $MANAGED_COPY_BACKUP_REQUIRED -eq 1 && ( -e "$dst" || -L "$dst" ) ]]; then
        if ! backup_item "$dst"; then
            rm -rf "$staging_dir"
            return 1
        fi
    fi

    if [[ -e "$dst" || -L "$dst" ]]; then
        if ! mv "$dst" "$previous_item"; then
            rm -rf "$staging_dir"
            log_error "Failed to move existing path out of the way: $dst"
            return 1
        fi
    fi

    if mv "$staged_item" "$dst"; then
        remove_installed_path "$previous_item"
        rmdir "$staging_dir" 2>/dev/null || true
        MANAGED_COPY_CHANGED=1
        return 0
    fi

    if [[ -e "$previous_item" || -L "$previous_item" ]]; then
        mv "$previous_item" "$dst" 2>/dev/null || true
    fi
    rm -rf "$staging_dir"
    log_error "Failed to deploy copy: $dst"
    return 1
}

record_managed_copy_snapshot() {
    local src="$1"
    local dst="$2"
    local snapshot_path
    local snapshot_parent

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi

    snapshot_path="$(managed_copy_snapshot_path "$dst")" || return 1
    snapshot_parent="$(dirname "$snapshot_path")"
    if ! mkdir -p "$snapshot_parent"; then
        log_error "Failed to create managed copy state directory: $snapshot_parent"
        return 1
    fi

    if deploy_copy "$src" "$snapshot_path" "" "$dst"; then
        return 0
    fi

    log_error "Failed to record managed copy snapshot: $dst"
    return 1
}

# Copy a repository path into its runtime location.
# $1: source (relative to SCRIPT_DIR)
# $2: target (absolute path)
# $3: replace existing user path without requiring --force (optional, default: 0)
# $4+: known legacy symlink sources (optional)
install_copy() {
    local src="$SCRIPT_DIR/$1"
    local dst="$2"
    local replace_existing="${3:-0}"
    local -a legacy_sources=()
    local installer_managed=0
    local managed_symlink=0
    local snapshot_path
    local merge_base=""
    local copy_changed=0
    local failed_before=$failed
    local action

    if [[ $# -gt 3 ]]; then
        shift 3
        legacy_sources=("$@")
    fi

    if [[ ! -e "$src" ]]; then
        log_error "Source does not exist: $src"
        failed=$((failed + 1))
        return 1
    fi

    ensure_parent_directory "$dst" || {
        failed=$((failed + 1))
        return 1
    }

    snapshot_path="$(managed_copy_snapshot_path "$dst")" || {
        failed=$((failed + 1))
        return 1
    }

    if symlink_points_to "$dst" "$src" \
        || symlink_points_to_any "$dst" "${legacy_sources[@]}"; then
        managed_symlink=1
    fi

    if [[ -e "$snapshot_path" || -L "$snapshot_path" ]] \
        || { managed_path_is_recorded "$dst" && [[ ! -L "$dst" ]]; } \
        || [[ $managed_symlink -eq 1 ]]; then
        installer_managed=1
    fi

    if [[ $installer_managed -eq 1 ]]; then
        if [[ $managed_symlink -eq 1 ]]; then
            merge_base=""
        elif [[ -e "$snapshot_path" || -L "$snapshot_path" ]]; then
            merge_base="$snapshot_path"
        elif [[ ! -L "$dst" ]]; then
            merge_base="$src"
            log_info "Establishing per-entry state for legacy managed copy: $dst"
        fi
    fi

    if [[ -e "$dst" || -L "$dst" ]]; then
        if [[ $installer_managed -eq 1 ]]; then
            :
        elif [[ $FORCE -eq 1 || $replace_existing -eq 1 ]]; then
            backup_item "$dst" || return 1
            if [[ $DRY_RUN -eq 1 ]]; then
                log_dry "Would copy: $src -> $dst"
                copied=$((copied + 1))
                return 0
            fi
        elif [[ $INTERACTIVE -eq 1 ]]; then
            prompt_user "$dst"
            action=$?
            case "$action" in
                0)
                    skipped=$((skipped + 1))
                    return 0
                    ;;
                1)
                    backup_item "$dst" || return 1
                    ;;
                2)
                    if [[ $DRY_RUN -eq 1 ]]; then
                        log_dry "Would remove existing path: $dst"
                    else
                        remove_installed_path "$dst"
                        log_info "Removed existing path: $dst"
                    fi
                    ;;
                3)
                    log_info "Installation cancelled by user"
                    exit 0
                    ;;
            esac
            if [[ $DRY_RUN -eq 1 ]]; then
                log_dry "Would copy: $src -> $dst"
                copied=$((copied + 1))
                return 0
            fi
        else
            log_warn "User-managed path exists: $dst"
            skipped=$((skipped + 1))
            return 0
        fi
    elif [[ $DRY_RUN -eq 1 && $installer_managed -eq 0 ]]; then
        log_dry "Would copy: $src -> $dst"
        copied=$((copied + 1))
        return 0
    fi

    if ! deploy_copy "$src" "$dst" "$merge_base"; then
        if [[ $failed -eq $failed_before ]]; then
            failed=$((failed + 1))
        fi
        return 1
    fi
    copy_changed=$MANAGED_COPY_CHANGED

    if ! record_managed_copy_snapshot "$src" "$dst" \
        || ! record_managed_path "$dst"; then
        if [[ $failed -eq $failed_before ]]; then
            failed=$((failed + 1))
        fi
        return 1
    fi

    if [[ $copy_changed -eq 0 ]]; then
        log_warn "Already copied: $dst"
        skipped=$((skipped + 1))
    elif [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would copy: $src -> $dst"
        copied=$((copied + 1))
    else
        log_ok "Copied: $src -> $dst"
        copied=$((copied + 1))
    fi

    return 0
}

install_shared_ai_agent_snapshot() {
    local dst="$SHARED_AI_AGENT_DIR"

    log_info "Installing shared agent assets..."
    if ! install_copy "ai-agent" "$dst"; then
        return 1
    fi

    SHARED_AI_AGENT_READY=1
    return 0
}

link_path() {
    local src="$1"
    local dst="$2"
    local replace_existing="${3:-0}"
    local -a legacy_sources=()
    local installer_managed=0
    local action

    if [[ $# -gt 3 ]]; then
        shift 3
        legacy_sources=("$@")
    fi

    if [[ ! -e "$src" ]]; then
        if [[ $DRY_RUN -ne 1 || $SHARED_AI_AGENT_READY -ne 1 ]]; then
            log_error "Shared source does not exist: $src"
            failed=$((failed + 1))
            return 1
        fi
    fi

    ensure_parent_directory "$dst" || {
        failed=$((failed + 1))
        return 1
    }

    if [[ -e "$dst" || -L "$dst" ]]; then
        if [[ -L "$dst" ]]; then
            if symlink_points_to "$dst" "$src"; then
                log_warn "Already linked: $dst"
                skipped=$((skipped + 1))
                return 0
            fi

            if symlink_points_to_any "$dst" "${legacy_sources[@]}"; then
                installer_managed=1
            fi

            if [[ $installer_managed -eq 1 || $FORCE -eq 1 || $replace_existing -eq 1 ]]; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log_dry "Would repoint symlink: $dst -> $src"
                else
                    rm -f "$dst"
                    log_info "Removed old symlink: $dst"
                fi
            elif [[ $INTERACTIVE -eq 1 ]]; then
                prompt_user "$dst"
                action=$?
                case "$action" in
                    0)
                        skipped=$((skipped + 1))
                        return 0
                        ;;
                    1)
                        backup_item "$dst" || return 1
                        ;;
                    2)
                        if [[ $DRY_RUN -eq 1 ]]; then
                            log_dry "Would remove existing symlink: $dst"
                        else
                            rm -f "$dst"
                        fi
                        ;;
                    3)
                        log_info "Installation cancelled by user"
                        exit 0
                        ;;
                esac
            else
                log_warn "Different symlink exists: $dst -> $(readlink "$dst")"
                skipped=$((skipped + 1))
                return 0
            fi
        elif [[ $FORCE -eq 1 || $replace_existing -eq 1 ]]; then
            backup_item "$dst" || return 1
        elif [[ $INTERACTIVE -eq 1 ]]; then
            prompt_user "$dst"
            action=$?
            case "$action" in
                0)
                    skipped=$((skipped + 1))
                    return 0
                    ;;
                1)
                    backup_item "$dst" || return 1
                    ;;
                2)
                    if [[ $DRY_RUN -eq 1 ]]; then
                        log_dry "Would remove existing path: $dst"
                    else
                        remove_installed_path "$dst"
                    fi
                    ;;
                3)
                    log_info "Installation cancelled by user"
                    exit 0
                    ;;
            esac
        else
            log_warn "User-managed path exists: $dst"
            skipped=$((skipped + 1))
            return 0
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would link: $dst -> $src"
        linked=$((linked + 1))
        return 0
    fi

    if ln -s "$src" "$dst"; then
        log_ok "Linked: $dst -> $src"
        linked=$((linked + 1))
        return 0
    fi

    log_error "Failed to link: $dst"
    failed=$((failed + 1))
    return 1
}

link_shared_ai_agent_item() {
    local relative_path="$1"
    local dst="$2"
    local catalog_source="$SCRIPT_DIR/ai-agent/$relative_path"
    local -a legacy_sources=("$catalog_source")
    local legacy_relative_path

    if [[ $# -gt 2 ]]; then
        shift 2
        for legacy_relative_path in "$@"; do
            legacy_sources+=("$SCRIPT_DIR/ai-agent/$legacy_relative_path")
        done
    fi

    if [[ ! -e "$catalog_source" ]]; then
        log_error "Shared source does not exist: $catalog_source"
        failed=$((failed + 1))
        return 1
    fi

    link_path \
        "$SHARED_AI_AGENT_DIR/$relative_path" \
        "$dst" \
        0 \
        "${legacy_sources[@]}"
}

# =============================================================================
# OS Detection
# =============================================================================

detect_os() {
    local os="unknown"

    if [[ "$OSTYPE" == linux-* ]]; then
        os="linux"
        # Check for WSL
        if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
            os="wsl"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os="macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        os="windows"
    fi

    echo "$os"
}

readonly OS="$(detect_os)"

detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt-get"
    elif command -v brew &>/dev/null; then
        echo "brew"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

readonly PACKAGE_MANAGER="$(detect_package_manager)"

# =============================================================================
# Installation Functions
# =============================================================================

install_package() {
    local package_name="$1"
    local -a install_cmd=()

    case "$PACKAGE_MANAGER" in
        apt-get)
            install_cmd=(sudo apt-get install -y "$package_name")
            ;;
        brew)
            install_cmd=(brew install "$package_name")
            ;;
        dnf)
            install_cmd=(sudo dnf install -y "$package_name")
            ;;
        pacman)
            install_cmd=(sudo pacman -S --noconfirm "$package_name")
            ;;
        zypper)
            install_cmd=(sudo zypper --non-interactive install "$package_name")
            ;;
        *)
            log_error "No supported package manager found for automatic install"
            return 1
            ;;
    esac

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${install_cmd[*]}"
        return 0
    fi

    log_info "Running: ${install_cmd[*]}"
    if "${install_cmd[@]}"; then
        return 0
    fi

    log_error "Package install failed: $package_name"
    return 1
}

package_name_for_command() {
    local command_name="$1"

    case "$command_name:$PACKAGE_MANAGER" in
        npm:brew)
            echo "node"
            ;;
        sqlite3:brew|sqlite3:dnf|sqlite3:pacman)
            echo "sqlite"
            ;;
        *)
            echo "$command_name"
            ;;
    esac
}

ensure_required_command() {
    local command_name="$1"
    local package_name="${2:-$(package_name_for_command "$command_name")}"

    if command -v "$command_name" &>/dev/null; then
        log_ok "Found required command: $command_name"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 && "$command_name" == "npm" && $NVM_NODE_AVAILABLE -eq 1 ]]; then
        log_dry "Would use required command from NVM: npm"
        return 0
    fi

    log_warn "Missing required command: $command_name"
    if ! install_package "$package_name"; then
        log_error "Please install '$package_name' manually and rerun the installer"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi

    if command -v "$command_name" &>/dev/null; then
        log_ok "Installed required command: $command_name"
        return 0
    fi

    log_error "Command still unavailable after install: $command_name"
    return 1
}

install_required_tools() {
    local required_tools=(
        curl
        tmux
        lsof
        jq
        sqlite3
        yq
        zsh
    )
    local tool_name

    log_info "Checking required CLI tools..."

    for tool_name in "${required_tools[@]}"; do
        ensure_required_command "$tool_name" || return 1
    done

    return 0
}

sha256_file() {
    local file_path="$1"
    local hash_output

    if command -v sha256sum &>/dev/null; then
        hash_output="$(sha256sum "$file_path")" || return 1
    elif command -v shasum &>/dev/null; then
        hash_output="$(shasum -a 256 "$file_path")" || return 1
    else
        return 1
    fi

    printf '%s\n' "${hash_output%% *}"
}

mq_is_runnable() {
    command -v mq &>/dev/null && mq --version >/dev/null 2>&1
}

mq_install_target_is_free() {
    local target="$1"

    if [[ -e "$target" || -L "$target" ]]; then
        log_error "mq install target already exists but is not runnable: $target"
        return 1
    fi

    return 0
}

finish_mq_target_install() {
    local target="$1"

    if "$target" --version >/dev/null 2>&1; then
        log_ok "Installed mq $MQ_VERSION"
        return 0
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        if ! rm -f "$target"; then
            log_error "mq is unavailable after install and could not remove: $target"
            return 1
        fi
    fi
    hash -r

    log_error "mq is unavailable after install: $target"
    return 1
}

mq_linux_libc() {
    local ldd_output

    if command -v ldd &>/dev/null; then
        ldd_output="$(ldd --version 2>&1 || true)"
        if [[ "$ldd_output" == *musl* || "$ldd_output" == *Musl* ]]; then
            printf '%s\n' "musl"
            return 0
        fi
    fi

    printf '%s\n' "gnu"
}

# Prints: <release asset><TAB><SHA-256>
mq_release_info() {
    local architecture
    local libc

    architecture="$(uname -m)"
    case "$OS:$architecture" in
        linux:x86_64|linux:amd64|wsl:x86_64|wsl:amd64)
            libc="$(mq_linux_libc)"
            if [[ "$libc" == "musl" ]]; then
                printf '%s\t%s\n' \
                    "mq-x86_64-unknown-linux-musl" \
                    "55078ec75f6be6092a3cd72d9bcb5a88ad700c98465b2907a3d146c600e02227"
            else
                printf '%s\t%s\n' \
                    "mq-x86_64-unknown-linux-gnu" \
                    "88ac9db1a62e3cc5213224a4cbe75ab8924dbca6cc6a988ecb9cafa538ed02cf"
            fi
            ;;
        linux:aarch64|linux:arm64|wsl:aarch64|wsl:arm64)
            libc="$(mq_linux_libc)"
            if [[ "$libc" == "musl" ]]; then
                printf '%s\t%s\n' \
                    "mq-aarch64-unknown-linux-musl" \
                    "f8abfa7238ff4a322cbd90b5f00843e9c8939d98dac0064b484498607137fb22"
            else
                printf '%s\t%s\n' \
                    "mq-aarch64-unknown-linux-gnu" \
                    "8b567fd2a0360de8ce8c82397d2ee260ff1fa5c73535a07cf75aac43588660ff"
            fi
            ;;
        macos:arm64|macos:aarch64)
            printf '%s\t%s\n' \
                "mq-aarch64-apple-darwin" \
                "ee11cee3d6855a8d23005a56d77013b14738838abe4a656bd82aeb884ee06645"
            ;;
        *)
            return 1
            ;;
    esac
}

install_mq_with_cargo() {
    local target="$1"
    local cargo_root="$HOME/.local"
    local -a install_cmd=(
        cargo install
        --root "$cargo_root"
        mq-run
        --version "${MQ_VERSION#v}"
        --locked
    )

    if ! command -v cargo &>/dev/null || ! cargo --version >/dev/null 2>&1; then
        log_warn "mq $MQ_VERSION has no official Intel macOS binary and Cargo is unavailable"
        log_info "Install Homebrew or Cargo, then rerun the installer"
        return 0
    fi

    if ! mq_install_target_is_free "$target"; then
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${install_cmd[*]}"
        return 0
    fi

    log_info "Running: ${install_cmd[*]}"
    if ! "${install_cmd[@]}"; then
        log_error "Failed to install mq with Cargo"
        return 1
    fi
    hash -r

    finish_mq_target_install "$target"
}

install_mq() {
    local release_info
    local asset_name
    local expected_sha256
    local download_url
    local architecture
    local local_bin="$HOME/.local/bin"
    local target="$local_bin/mq"
    local tmp_file
    local actual_sha256

    log_info "Checking mq Markdown processor..."

    if mq_is_runnable; then
        log_ok "Found mq"
        return 0
    fi

    if command -v mq &>/dev/null; then
        log_warn "Found mq but it is not runnable: $(command -v mq)"
    fi

    # Homebrew ships mq for both Apple Silicon and Intel macOS.
    if [[ "$PACKAGE_MANAGER" == "brew" ]]; then
        log_info "Installing mq with Homebrew"
        if ! install_package "mq"; then
            return 1
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            return 0
        fi

        hash -r
        if mq_is_runnable; then
            log_ok "Installed mq with Homebrew"
            return 0
        fi

        log_error "mq is unavailable after Homebrew install"
        return 1
    fi

    architecture="$(uname -m)"
    if ! release_info="$(mq_release_info)"; then
        case "$OS:$architecture" in
            macos:x86_64|macos:amd64)
                install_mq_with_cargo "$target"
                return $?
                ;;
        esac

        log_warn "mq automatic install is unavailable on: $OS/$architecture"
        log_info "Install manually: cargo install mq-run --version ${MQ_VERSION#v} --locked --root $HOME/.local"
        return 0
    fi
    IFS=$'\t' read -r asset_name expected_sha256 <<< "$release_info"
    download_url="$MQ_RELEASE_BASE_URL/$asset_name"

    if ! mq_install_target_is_free "$target"; then
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would download mq $MQ_VERSION from: $download_url"
        log_dry "Would verify mq SHA-256: $expected_sha256"
        log_dry "Would install: $target"
        return 0
    fi

    if ! mkdir -p "$local_bin"; then
        log_error "Failed to create mq install directory: $local_bin"
        return 1
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/mq-install.XXXXXX")" || {
        log_error "Failed to create temporary mq download"
        return 1
    }

    if ! curl -fsSL "$download_url" -o "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to download mq $MQ_VERSION"
        return 1
    fi

    actual_sha256="$(sha256_file "$tmp_file")" || {
        rm -f "$tmp_file"
        log_error "No SHA-256 tool available for mq verification"
        return 1
    }
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        rm -f "$tmp_file"
        log_error "mq binary SHA-256 mismatch"
        return 1
    fi

    if ! install -m 0755 "$tmp_file" "$target"; then
        rm -f "$tmp_file"
        log_error "Failed to install mq to: $target"
        return 1
    fi
    rm -f "$tmp_file"
    hash -r

    finish_mq_target_install "$target"
}

bash_profile_loads_nvm() {
    local profile="$1"

    grep -Fq 'NVM_DIR' "$profile" 2>/dev/null && grep -Fq 'nvm.sh' "$profile" 2>/dev/null
}

ensure_nvm_bash_profile() {
    local profile="$HOME/.bashrc"

    if [[ ! -e "$profile" && ! -L "$profile" ]]; then
        log_info "Bash NVM setup will be provided by the installed bashrc"
        return 0
    fi

    if [[ ! -f "$profile" ]]; then
        log_error "Bash profile is not a regular file: $profile"
        return 1
    fi

    if bash_profile_loads_nvm "$profile"; then
        log_ok "Bash profile loads NVM: $profile"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would append NVM initialization to: $profile"
        return 0
    fi

    if printf '\n# NVM managed by config_files\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' >> "$profile"; then
        log_ok "Added NVM initialization to: $profile"
        return 0
    fi

    log_error "Failed to update Bash profile: $profile"
    return 1
}

install_nodejs_with_nvm() {
    local nvm_dir="$HOME/.nvm"
    local nvm_script="$nvm_dir/nvm.sh"
    local tmp_file

    log_info "Checking Node.js via NVM..."

    if [[ -s "$nvm_script" ]]; then
        log_ok "Found NVM"
    else
        if [[ -e "$nvm_dir" ]]; then
            log_error "NVM directory exists but is incomplete: $nvm_dir"
            return 1
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would install NVM $NVM_VERSION from: $NVM_INSTALL_URL"
        else
            tmp_file="$(mktemp "${TMPDIR:-/tmp}/nvm-install.XXXXXX")" || {
                log_error "Failed to create temporary NVM installer"
                return 1
            }

            if ! curl -fsSL "$NVM_INSTALL_URL" -o "$tmp_file"; then
                rm -f "$tmp_file"
                log_error "Failed to download NVM installer"
                return 1
            fi

            if ! PROFILE=/dev/null NVM_DIR="$nvm_dir" bash "$tmp_file"; then
                rm -f "$tmp_file"
                log_error "Failed to install NVM"
                return 1
            fi
            rm -f "$tmp_file"

            if [[ ! -s "$nvm_script" ]]; then
                log_error "NVM is unavailable after install: $nvm_script"
                return 1
            fi
            log_ok "Installed NVM $NVM_VERSION"
        fi
    fi

    ensure_nvm_bash_profile || return 1

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: nvm install --lts"
        log_dry "Would run: nvm alias default lts/*"
        log_dry "Would run: nvm use default"
        NVM_NODE_AVAILABLE=1
        return 0
    fi

    # shellcheck source=/dev/null
    source "$nvm_script"

    if ! command -v nvm &>/dev/null; then
        log_error "NVM is unavailable after loading: $nvm_script"
        return 1
    fi

    if ! nvm install --lts; then
        log_error "Failed to install the latest Node.js LTS release"
        return 1
    fi
    if ! nvm alias default 'lts/*'; then
        log_error "Failed to set the default Node.js version"
        return 1
    fi
    if ! nvm use default; then
        log_error "Failed to activate the default Node.js version"
        return 1
    fi

    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        NVM_NODE_AVAILABLE=1
        log_ok "Node.js and npm are available through NVM"
        return 0
    fi

    log_error "Node.js or npm is unavailable after NVM setup"
    return 1
}

install_codex_cli() {
    log_info "Checking Codex CLI..."

    if command -v codex &>/dev/null; then
        log_ok "Found Codex CLI"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: npm install -g @openai/codex"
        return 0
    fi

    if ! command -v npm &>/dev/null; then
        log_error "Codex CLI requires npm"
        return 1
    fi

    log_info "Running: npm install -g @openai/codex"
    if ! npm install -g @openai/codex; then
        log_error "Failed to install Codex CLI"
        return 1
    fi

    if command -v codex &>/dev/null; then
        log_ok "Installed Codex CLI"
        return 0
    fi

    log_error "Codex CLI is unavailable after install"
    return 1
}

install_remote_cli() {
    local display_name="$1"
    local command_name="$2"
    local install_url="$3"
    local expected_sha256="$4"
    shift 4
    local -a installer_args=("$@")
    local tmp_file
    local actual_sha256

    log_info "Checking $display_name..."

    if command -v "$command_name" &>/dev/null; then
        log_ok "Found $display_name"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ ${#installer_args[@]} -gt 0 ]]; then
            log_dry "Would install $display_name from: $install_url ${installer_args[*]}"
        else
            log_dry "Would install $display_name from: $install_url"
        fi
        if [[ -n "$expected_sha256" ]]; then
            log_dry "Would verify $display_name installer SHA-256: $expected_sha256"
        fi
        return 0
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/${command_name}-install.XXXXXX")" || {
        log_error "Failed to create temporary installer for $display_name"
        return 1
    }

    if ! curl -fsSL "$install_url" -o "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to download installer for $display_name"
        return 1
    fi

    if [[ -n "$expected_sha256" ]]; then
        actual_sha256="$(sha256_file "$tmp_file")" || {
            rm -f "$tmp_file"
            log_error "No SHA-256 tool available for $display_name installer verification"
            return 1
        }

        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            rm -f "$tmp_file"
            log_error "$display_name installer SHA-256 mismatch"
            return 1
        fi
        log_ok "Verified $display_name installer SHA-256"
    fi

    if ! bash "$tmp_file" "${installer_args[@]}"; then
        rm -f "$tmp_file"
        log_error "Failed to install $display_name"
        return 1
    fi
    rm -f "$tmp_file"
    hash -r

    if command -v "$command_name" &>/dev/null; then
        log_ok "Installed $display_name"
        return 0
    fi

    log_error "$display_name is unavailable after install: $command_name"
    return 1
}

install_oh_my_zsh() {
    local install_dir="$HOME/.oh-my-zsh"
    local entrypoint="$install_dir/oh-my-zsh.sh"

    log_info "Checking Oh My Zsh..."

    if [[ -f "$entrypoint" ]]; then
        log_ok "Found Oh My Zsh"
        return 0
    fi

    if [[ -e "$install_dir" ]]; then
        log_error "Oh My Zsh directory exists but is incomplete: $install_dir"
        return 1
    fi

    if ! ensure_required_command "git"; then
        log_error "Oh My Zsh requires git"
        return 1
    fi

    local -a install_cmd=(
        git clone --depth=1
        https://github.com/ohmyzsh/ohmyzsh.git
        "$install_dir"
    )

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${install_cmd[*]}"
        return 0
    fi

    log_info "Running: ${install_cmd[*]}"
    if ! "${install_cmd[@]}"; then
        log_error "Failed to install Oh My Zsh"
        return 1
    fi

    if [[ -f "$entrypoint" ]]; then
        log_ok "Installed Oh My Zsh"
        return 0
    fi

    log_error "Oh My Zsh is incomplete after install: $install_dir"
    return 1
}

install_agent_browser() {
    log_info "Checking agent-browser..."
    local installed_agent_browser=0

    if ! ensure_required_command "npm"; then
        log_error "agent-browser requires npm"
        return 1
    fi

    if ! command -v agent-browser &>/dev/null; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would run: npm install -g agent-browser"
        else
            log_info "Running: npm install -g agent-browser"
            if ! npm install -g agent-browser; then
                log_error "Failed to install agent-browser with npm"
                return 1
            fi
            installed_agent_browser=1
            log_ok "Installed agent-browser"
        fi
    else
        log_ok "Found agent-browser"
    fi

    if [[ $DRY_RUN -eq 0 && $installed_agent_browser -eq 0 ]]; then
        log_ok "Skipping agent-browser browser install; agent-browser is already installed"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: agent-browser install if agent-browser is newly installed"
        return 0
    fi

    log_info "Running: agent-browser install"
    if agent-browser install; then
        log_ok "agent-browser Chromium setup complete"
        return 0
    fi

    log_error "Failed to install agent-browser Chromium bundle"
    return 1
}

install_ast_grep() {
    log_info "Checking ast-grep..."

    if ! ensure_required_command "npm"; then
        log_error "ast-grep requires npm"
        return 1
    fi

    if command -v ast-grep &>/dev/null; then
        log_ok "Found ast-grep"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: npm install -g @ast-grep/cli"
        return 0
    fi

    log_info "Running: npm install -g @ast-grep/cli"
    if ! npm install -g @ast-grep/cli; then
        log_error "Failed to install ast-grep with npm"
        return 1
    fi

    if command -v ast-grep &>/dev/null; then
        log_ok "Installed ast-grep"
        return 0
    fi

    log_error "Command still unavailable after install: ast-grep"
    return 1
}

install_ast_grep_skill() {
    # skills uses the shared directory as Codex's global canonical path.
    local shared_skills_dir="$HOME/.agents/skills"
    local shared_skill_file="$shared_skills_dir/ast-grep/SKILL.md"
    local codex_skill_file="$HOME/.codex/skills/ast-grep/SKILL.md"
    local -a skill_cmd=(
        npx --yes skills add https://github.com/ast-grep/agent-skill
        --global --agent codex --yes
    )

    log_info "Checking ast-grep skill..."

    if [[ $CODEX_SKILLS_DIR_READY -ne 1 ]]; then
        log_warn "Skipping ast-grep skill install; Codex skills directory was not prepared"
        return 0
    fi

    if [[ -f "$shared_skill_file" || -f "$codex_skill_file" ]]; then
        log_ok "Found ast-grep skill"
        return 0
    fi

    if ! prepare_skills_target_dir "Shared agent" "$shared_skills_dir"; then
        log_warn "Skipping ast-grep skill install; shared agent skills directory was not prepared"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${skill_cmd[*]}"
        return 0
    fi

    if ! command -v npx &>/dev/null; then
        log_error "ast-grep skill requires npx (provided by npm)"
        return 1
    fi

    log_info "Running: ${skill_cmd[*]}"
    if ! "${skill_cmd[@]}"; then
        log_error "Failed to install ast-grep skill"
        return 1
    fi

    if [[ -f "$shared_skill_file" || -f "$codex_skill_file" ]]; then
        log_ok "Installed ast-grep skill"
        return 0
    fi

    log_error "Skill still unavailable after install: ast-grep"
    return 1
}

tree_sitter_cli_version() {
    local version_output

    version_output="$(tree-sitter --version 2>/dev/null)" || return 1
    if [[ "$version_output" =~ ^tree-sitter[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

tree_sitter_version_is_supported() {
    local actual_version="$1"
    local required_version="$2"
    local actual_major actual_minor actual_patch
    local required_major required_minor required_patch
    local IFS='.'

    read -r actual_major actual_minor actual_patch <<< "$actual_version"
    read -r required_major required_minor required_patch <<< "$required_version"

    [[ "$actual_major" =~ ^[0-9]+$ && "$actual_minor" =~ ^[0-9]+$ && "$actual_patch" =~ ^[0-9]+$ ]] || return 1
    [[ "$required_major" =~ ^[0-9]+$ && "$required_minor" =~ ^[0-9]+$ && "$required_patch" =~ ^[0-9]+$ ]] || return 1

    if (( 10#$actual_major != 10#$required_major )); then
        (( 10#$actual_major > 10#$required_major ))
        return
    fi
    if (( 10#$actual_minor != 10#$required_minor )); then
        (( 10#$actual_minor > 10#$required_minor ))
        return
    fi

    (( 10#$actual_patch >= 10#$required_patch ))
}

load_cargo_environment() {
    local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
    local cargo_env="$cargo_home/env"

    if [[ -f "$cargo_env" ]]; then
        # shellcheck source=/dev/null
        source "$cargo_env"
    else
        export PATH="$cargo_home/bin:$PATH"
    fi
}

ensure_rust_cargo() {
    local tmp_file

    log_info "Checking Rust/Cargo..."
    load_cargo_environment

    if ! command -v rustup &>/dev/null || ! rustup --version >/dev/null 2>&1; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would install the minimal Rust toolchain from: $RUSTUP_INSTALL_URL"
            return 0
        fi

        if ! command -v curl &>/dev/null; then
            log_error "Rust/Cargo installation requires curl"
            return 1
        fi

        tmp_file="$(mktemp "${TMPDIR:-/tmp}/rustup-init.XXXXXX")" || {
            log_error "Failed to create temporary Rust installer"
            return 1
        }

        log_info "Installing minimal Rust toolchain..."
        if ! curl --proto '=https' --tlsv1.2 -fsSL "$RUSTUP_INSTALL_URL" -o "$tmp_file"; then
            rm -f "$tmp_file"
            log_error "Failed to download Rust installer"
            return 1
        fi

        if ! bash "$tmp_file" -y --profile minimal --default-toolchain stable; then
            rm -f "$tmp_file"
            log_error "Failed to install Rust toolchain"
            return 1
        fi
        rm -f "$tmp_file"

        load_cargo_environment
        hash -r
    fi

    if ! command -v rustup &>/dev/null || ! rustup --version >/dev/null 2>&1; then
        log_error "rustup is unavailable after Rust installation"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: rustup toolchain install stable --profile minimal"
        return 0
    fi

    log_info "Ensuring current Rust stable toolchain..."
    if ! rustup toolchain install stable --profile minimal; then
        log_error "Failed to install the Rust stable toolchain"
        return 1
    fi

    if rustup run stable cargo --version >/dev/null 2>&1; then
        log_ok "Rust stable toolchain is available"
        return 0
    fi

    log_error "Cargo is unavailable from the Rust stable toolchain"
    return 1
}

find_libclang_dir() {
    local -a search_dirs=()
    local search_dir
    local libclang_file

    if [[ -n "${LIBCLANG_PATH:-}" ]]; then
        search_dirs+=("$LIBCLANG_PATH")
    fi

    case "$OS" in
        macos)
            search_dirs+=(
                /opt/homebrew/opt/llvm/lib
                /usr/local/opt/llvm/lib
                /Library/Developer/CommandLineTools/usr/lib
                /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib
            )
            ;;
        *)
            search_dirs+=(/usr/lib /usr/local/lib /usr/lib64 /usr/local/lib64 /lib /lib64)
            ;;
    esac

    for search_dir in "${search_dirs[@]}"; do
        [[ -d "$search_dir" ]] || continue
        libclang_file="$(find "$search_dir" -maxdepth 4 \( -type f -o -type l \) \( -name 'libclang.so*' -o -name 'libclang.dylib' \) -print -quit 2>/dev/null)"
        if [[ -n "$libclang_file" ]]; then
            dirname "$libclang_file"
            return 0
        fi
    done

    return 1
}

libclang_package_name() {
    case "$PACKAGE_MANAGER" in
        apt-get)
            printf '%s\n' "libclang-dev"
            ;;
        brew)
            printf '%s\n' "llvm"
            ;;
        dnf|zypper)
            printf '%s\n' "clang-devel"
            ;;
        pacman)
            printf '%s\n' "clang"
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_libclang() {
    local libclang_dir
    local package_name

    log_info "Checking libclang..."
    if libclang_dir="$(find_libclang_dir)"; then
        export LIBCLANG_PATH="$libclang_dir"
        log_ok "Found libclang: $libclang_dir"
        return 0
    fi

    if ! package_name="$(libclang_package_name)"; then
        log_error "No supported package is known for libclang"
        return 1
    fi

    log_info "Installing libclang package: $package_name"
    if ! install_package "$package_name"; then
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi

    if libclang_dir="$(find_libclang_dir)"; then
        export LIBCLANG_PATH="$libclang_dir"
        log_ok "Installed libclang: $libclang_dir"
        return 0
    fi

    log_error "libclang is unavailable after installation"
    return 1
}

install_tree_sitter_cli_with_cargo() {
    local required_version="$1"
    local cargo_root="$HOME/.local"
    local current_version=""
    local -a install_cmd=(
        rustup run stable cargo install
        --root "$cargo_root"
        tree-sitter-cli
        --locked
        --force
    )

    if ! ensure_rust_cargo; then
        return 1
    fi

    if ! ensure_libclang; then
        return 1
    fi

    ensure_path_contains_local_bin

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${install_cmd[*]}"
        return 0
    fi

    log_info "Building tree-sitter CLI from source: ${install_cmd[*]}"
    if ! "${install_cmd[@]}"; then
        log_error "Failed to build tree-sitter CLI with Cargo"
        return 1
    fi
    hash -r

    if current_version="$(tree_sitter_cli_version)" && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Built supported tree-sitter CLI: $current_version"
        return 0
    fi

    log_error "tree-sitter CLI is unavailable after Cargo build"
    return 1
}

install_tree_sitter_cli() {
    local required_version="0.26.1"
    local current_version=""

    log_info "Checking tree-sitter CLI..."

    if current_version="$(tree_sitter_cli_version)" && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Found supported tree-sitter CLI: $current_version"
        return 0
    fi

    if [[ -n "$current_version" ]]; then
        log_warn "tree-sitter CLI $current_version is unsupported; requires $required_version or newer"
    fi

    if ! command -v npm &>/dev/null; then
        log_warn "npm is unavailable; building tree-sitter CLI from source with Cargo"
        install_tree_sitter_cli_with_cargo "$required_version"
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: npm install -g --allow-scripts=tree-sitter-cli tree-sitter-cli (requires $required_version or newer)"
        log_dry "Would install Rust/Cargo and libclang, then build tree-sitter-cli from source if the npm binary is unusable"
        return 0
    fi

    # tree-sitter-cli needs install.js to download the actual CLI. npm 11's
    # script policy allows this known package through the per-command flag.
    log_info "Running: npm install -g --allow-scripts=tree-sitter-cli tree-sitter-cli"
    if ! npm install -g --allow-scripts=tree-sitter-cli tree-sitter-cli; then
        log_warn "npm install did not provide a runnable tree-sitter CLI; trying Cargo"
    elif current_version="$(tree_sitter_cli_version)" && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Installed supported tree-sitter CLI: $current_version"
        return 0
    fi

    # A prior install may have added the package while its lifecycle script was
    # blocked. Rebuild only this package to run its now-allowed install script.
    log_info "Re-running tree-sitter-cli install script"
    if ! npm rebuild -g --allow-scripts=tree-sitter-cli tree-sitter-cli; then
        log_warn "npm rebuild did not provide a runnable tree-sitter CLI; trying Cargo"
    elif current_version="$(tree_sitter_cli_version)" && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Installed supported tree-sitter CLI: $current_version"
        return 0
    fi

    install_tree_sitter_cli_with_cargo "$required_version"
}

install_codegraph() {
    log_info "Checking codegraph..."

    if ! ensure_required_command "npm"; then
        log_error "codegraph requires npm"
        return 1
    fi

    if command -v codegraph &>/dev/null; then
        log_ok "Found codegraph"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: npm install -g @colbymchenry/codegraph"
        return 0
    fi

    log_info "Running: npm install -g @colbymchenry/codegraph"
    if ! npm install -g @colbymchenry/codegraph; then
        log_error "Failed to install codegraph with npm"
        return 1
    fi

    if command -v codegraph &>/dev/null; then
        log_ok "Installed codegraph"
        return 0
    fi

    log_error "Command still unavailable after install: codegraph"
    return 1
}

ensure_toml_string_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would ensure [$section] $key in: $file"
        return 0
    fi

    mkdir -p "$(dirname "$file")" || {
        log_error "Failed to create config directory for: $file"
        return 1
    }
    touch "$file" || {
        log_error "Failed to create config file: $file"
        return 1
    }

    TOML_SECTION="$section" TOML_KEY="$key" TOML_VALUE="$value" perl -0pi -e '
        my $section = $ENV{TOML_SECTION};
        my $key = $ENV{TOML_KEY};
        my $value = $ENV{TOML_VALUE};

        my $section_re = quotemeta($section);
        my $key_re = quotemeta($key);
        $value =~ s/\\/\\\\/g;
        $value =~ s/"/\\"/g;
        my $entry = "$key = \"$value\"";

        my @lines = split /\n/, $_, -1;
        pop @lines if @lines && $lines[-1] eq "";

        my @out = ();
        my $in_section = 0;
        my $found_section = 0;
        my $found_key = 0;

        for my $line (@lines) {
          if ($line =~ /^\s*\[$section_re\]\s*$/) {
            $in_section = 1;
            $found_section = 1;
            push @out, $line;
            next;
          }

          if ($in_section && $line =~ /^\s*\[/) {
            push @out, $entry unless $found_key;
            $in_section = 0;
          }

          if ($in_section && $line =~ /^\s*$key_re\s*=/) {
            push @out, $entry;
            $found_key = 1;
            next;
          }

          push @out, $line;
        }

        if ($found_section && $in_section && !$found_key) {
          push @out, $entry;
        }

        if (!$found_section) {
          push @out, "" if @out && $out[-1] ne "";
          push @out, "[$section]", $entry;
        }

        $_ = join("\n", @out);
        $_ .= "\n";
    ' "$file" || {
        log_error "Failed to update TOML config: $file"
        return 1
    }

    log_ok "Ensured [$section] $key in: $file"
    return 0
}

ensure_toml_literal_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would ensure [$section] $key in: $file"
        return 0
    fi

    mkdir -p "$(dirname "$file")" || {
        log_error "Failed to create config directory for: $file"
        return 1
    }
    touch "$file" || {
        log_error "Failed to create config file: $file"
        return 1
    }

    TOML_SECTION="$section" TOML_KEY="$key" TOML_VALUE="$value" perl -0pi -e '
        my $section = $ENV{TOML_SECTION};
        my $key = $ENV{TOML_KEY};
        my $value = $ENV{TOML_VALUE};

        my $section_re = quotemeta($section);
        my $key_re = quotemeta($key);
        my $entry = "$key = $value";

        my @lines = split /\n/, $_, -1;
        pop @lines if @lines && $lines[-1] eq "";

        my @out = ();
        my $in_section = 0;
        my $found_section = 0;
        my $found_key = 0;

        for my $line (@lines) {
          if ($line =~ /^\s*\[$section_re\]\s*$/) {
            $in_section = 1;
            $found_section = 1;
            push @out, $line;
            next;
          }

          if ($in_section && $line =~ /^\s*\[/) {
            push @out, $entry unless $found_key;
            $in_section = 0;
          }

          if ($in_section && $line =~ /^\s*$key_re\s*=/) {
            push @out, $entry;
            $found_key = 1;
            next;
          }

          push @out, $line;
        }

        if ($found_section && $in_section && !$found_key) {
          push @out, $entry;
        }

        if (!$found_section) {
          push @out, "" if @out && $out[-1] ne "";
          push @out, "[$section]", $entry;
        }

        $_ = join("\n", @out);
        $_ .= "\n";
    ' "$file" || {
        log_error "Failed to update TOML config: $file"
        return 1
    }

    log_ok "Ensured [$section] $key in: $file"
    return 0
}

ensure_waypost_mcp_command() {
    if [[ $WAYPOST_MCP_AVAILABLE -eq 1 ]]; then
        log_ok "waypost MCP command already available"
        return 0
    fi

    log_info "Checking built-in waypost MCP command..."

    if ! command -v waypost &>/dev/null; then
        log_error "Missing required command: waypost"
        log_info "Install or update waypost so 'waypost mcp' is available, then rerun the installer"
        return 1
    fi

    if ! waypost mcp --help >/dev/null 2>&1; then
        log_error "Installed waypost does not expose the built-in MCP server"
        log_info "Update waypost so 'waypost mcp' is supported, then rerun the installer"
        return 1
    fi

    WAYPOST_MCP_AVAILABLE=1
    log_ok "Found built-in waypost MCP server: waypost mcp"
    return 0
}

migrate_legacy_waypost_state_if_present() {
    local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
    local legacy_state_dir="$state_home/ai-agent/mailbox"

    if [[ ! -e "$legacy_state_dir" ]] && [[ ! -L "$legacy_state_dir" ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: waypost migrate"
        return 0
    fi

    if command -v pgrep &>/dev/null && pgrep -f 'agent-mailbox[[:space:]]+mcp([[:space:]]|$)' >/dev/null 2>&1; then
        log_warn "Legacy agent-mailbox MCP process detected; stop it before migration to avoid state divergence"
    fi

    log_info "Migrating legacy Waypost state: $legacy_state_dir"
    if ! waypost migrate; then
        log_error "Failed to migrate legacy Waypost state"
        return 1
    fi

    log_ok "Migrated legacy Waypost state"
    return 0
}

waypost_mcp_permissions_json() {
    local prefix="$1"
    local suffix="$2"

    printf '%s\n' "${WAYPOST_MCP_TOOL_NAMES[@]}" \
        | jq -Rsc --arg prefix "$prefix" --arg suffix "$suffix" '
            split("\n")
            | map(select(length > 0) | ($prefix + . + $suffix))
        '
}

ensure_top_level_mcp_stdio_server() {
    local tool_name="$1"
    local config_file="$2"
    local server_name="$3"
    local command_name="$4"
    local args_json="$5"
    local tmp_file

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would ensure $tool_name MCP config in: $config_file"
        return 0
    fi

    mkdir -p "$(dirname "$config_file")"

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/mcp-config.XXXXXX")" || {
        log_error "Failed to create temporary file for $tool_name MCP config"
        return 1
    }

    if [[ -s "$config_file" ]]; then
        if ! MCP_SERVER_NAME="$server_name" MCP_COMMAND="$command_name" MCP_ARGS_JSON="$args_json" jq '
            .mcpServers = ((.mcpServers // {})
                | del(.workflow_mailbox, .agent_mailbox, ."agent-mailbox", ."adwf-mailbox")
                | .[$ENV.MCP_SERVER_NAME] = ((.[$ENV.MCP_SERVER_NAME] // {})
                    | . + {
                        "command": $ENV.MCP_COMMAND,
                        "args": ($ENV.MCP_ARGS_JSON | fromjson)
                    }
                    | del(.env)))
        ' "$config_file" > "$tmp_file"; then
            rm -f "$tmp_file"
            log_error "Failed to update $tool_name MCP config: $config_file"
            return 1
        fi
    elif ! MCP_SERVER_NAME="$server_name" MCP_COMMAND="$command_name" MCP_ARGS_JSON="$args_json" jq -n '
        {
            "mcpServers": {
                ($ENV.MCP_SERVER_NAME): {
                    "command": $ENV.MCP_COMMAND,
                    "args": ($ENV.MCP_ARGS_JSON | fromjson)
                }
            }
        }
    ' > "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to create $tool_name MCP config: $config_file"
        return 1
    fi

    if mv "$tmp_file" "$config_file"; then
        log_ok "Ensured $tool_name MCP config: $server_name"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write $tool_name MCP config: $config_file"
    return 1
}

rewrite_gemini_waypost_config() {
    local gemini_config="$HOME/.gemini/settings.json"
    local tmp_file

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would rewrite Gemini MCP config in: $gemini_config"
        return 0
    fi

    mkdir -p "$(dirname "$gemini_config")"

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/gemini-mcp-config.XXXXXX")" || {
        log_error "Failed to create temporary file for Gemini MCP config"
        return 1
    }

    if [[ -f "$gemini_config" ]]; then
        if ! jq '
            .general = ((.general // {})
                | .enableAutoUpdate = false)
            | .security = ((.security // {})
                | .enablePermanentToolApproval = true
                | .disableAlwaysAllow = false)
            | .mcpServers as $mcpServers
            | .mcpServers = (($mcpServers // {})
                | del(.workflow_mailbox, .agent_mailbox, ."agent-mailbox", ."adwf-mailbox")
                | ."waypost" = ((($mcpServers // {})["waypost"] // {})
                  | . + {
                    "command": "waypost",
                    "args": ["mcp"],
                    "env": {
                      "TMUX": "$TMUX",
                      "AGENTDECK_INSTANCE_ID": "$AGENTDECK_INSTANCE_ID",
                      "GEMINI_CLI": "$GEMINI_CLI"
                    }
                  }))
        ' "$gemini_config" > "$tmp_file"; then
            rm -f "$tmp_file"
            log_error "Failed to rewrite Gemini MCP config: $gemini_config"
            return 1
        fi
    elif ! jq -n '
        {
          "general": {
            "enableAutoUpdate": false
          },
          "security": {
            "enablePermanentToolApproval": true,
            "disableAlwaysAllow": false
          },
          "mcpServers": {
            "waypost": {
              "command": "waypost",
              "args": ["mcp"],
              "env": {
                "TMUX": "$TMUX",
                "AGENTDECK_INSTANCE_ID": "$AGENTDECK_INSTANCE_ID",
                "GEMINI_CLI": "$GEMINI_CLI"
              }
            }
          }
        }
    ' > "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to rewrite Gemini MCP config: $gemini_config"
        return 1
    fi

    if mv "$tmp_file" "$gemini_config"; then
        log_ok "Rewrote Gemini MCP config: waypost"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write Gemini MCP config: $gemini_config"
    return 1
}

remove_gemini_stale_waypost_mcps() {
    local legacy_server
    local -a legacy_servers=(workflow_mailbox agent_mailbox agent-mailbox adwf-mailbox)

    if ! command -v gemini &>/dev/null; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        for legacy_server in "${legacy_servers[@]}"; do
            log_dry "Would run: gemini mcp remove $legacy_server"
        done
        return 0
    fi

    for legacy_server in "${legacy_servers[@]}"; do
        gemini mcp remove "$legacy_server" >/dev/null 2>&1 || true
    done
}

install_gemini_waypost_mcp() {
    remove_gemini_stale_waypost_mcps
    rewrite_gemini_waypost_config || return 1
}

rewrite_antigravity_waypost_config() {
    local antigravity_mcp_config="$HOME/.gemini/config/mcp_config.json"
    local antigravity_settings="$HOME/.gemini/antigravity-cli/settings.json"
    local antigravity_permissions_json
    local tmp_file

    antigravity_permissions_json="$(waypost_mcp_permissions_json 'mcp(waypost/' ')')" || {
        log_error "Failed to build Antigravity Waypost MCP permissions"
        return 1
    }

    ensure_top_level_mcp_stdio_server "Antigravity" "$antigravity_mcp_config" "waypost" "waypost" '["mcp"]' || return 1

    if [[ $DRY_RUN -eq 1 && ! -s "$antigravity_settings" ]]; then
        log_dry "Would create Antigravity settings file and merge Waypost MCP permissions into: $antigravity_settings"
    fi

    if [[ $DRY_RUN -eq 0 ]]; then
        mkdir -p "$(dirname "$antigravity_settings")" || {
            log_error "Failed to create Antigravity settings directory"
            return 1
        }
        if [[ ! -s "$antigravity_settings" ]]; then
            printf '{}\n' > "$antigravity_settings" || {
                log_error "Failed to create Antigravity settings file: $antigravity_settings"
                return 1
            }
        fi
    fi

    if [[ -s "$antigravity_settings" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would migrate Antigravity MCP permissions to waypost in: $antigravity_settings"
            return 0
        fi

        tmp_file="$(mktemp "${TMPDIR:-/tmp}/antigravity-settings.XXXXXX")" || {
            log_error "Failed to create temporary file for Antigravity settings cleanup"
            return 1
        }

        if ! jq --argjson perms "$antigravity_permissions_json" '
            def migrate_permission:
                if type == "string" then
                    sub("^mcp\\((workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox)/"; "mcp(waypost/")
                    | sub("^mcp\\(waypost/mailbox_"; "mcp(waypost/waypost_")
                else
                    .
                end;
            def is_waypost_permission:
                type == "string" and startswith("mcp(waypost/");
            if (.mcpServers | type) == "object" then
                .mcpServers |= del(.workflow_mailbox, .agent_mailbox, ."agent-mailbox", .adwf_mailbox, ."adwf-mailbox")
                | if (.mcpServers == {}) then del(.mcpServers) else . end
            else
                .
            end
            | .permissions.allow = (
                (.permissions.allow // [])
                | map(migrate_permission)
                | if any(.[]?; is_waypost_permission) then . else . + $perms end
                | unique
            )
        ' "$antigravity_settings" > "$tmp_file"; then
            rm -f "$tmp_file"
            log_error "Failed to migrate Antigravity MCP permissions: $antigravity_settings"
            return 1
        fi

        if ! mv "$tmp_file" "$antigravity_settings"; then
            rm -f "$tmp_file"
            log_error "Failed to write Antigravity MCP permissions: $antigravity_settings"
            return 1
        fi
    fi

    log_ok "Rewrote Antigravity MCP config and permissions: waypost"
    return 0
}

install_antigravity_waypost_mcp() {
    rewrite_antigravity_waypost_config || return 1
}

install_kiro_waypost_mcp() {
    ensure_top_level_mcp_stdio_server "Kiro CLI" "$HOME/.kiro/settings/mcp.json" "waypost" "waypost" '["mcp"]'
}

migrate_codex_legacy_waypost_tool_permissions() {
    local codex_config="$HOME/.codex/config.toml"

    if [[ ! -f "$codex_config" ]]; then
        return 0
    fi

    if ! perl -0ne '
        exit(/\[mcp_servers\.("?(?:workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox)"?)\.tools\./m ? 0 : 1);
    ' "$codex_config"; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would migrate Codex MCP tool approvals to waypost in: $codex_config"
        return 0
    fi

    if ! perl -0pi -e '
        my @lines = split /\n/, $_, -1;
        my $legacy_server = qr/(?:"(?:workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox)"|(?:workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox))/;
        my %waypost_tools;

        for my $line (@lines) {
          if ($line =~ /^\[mcp_servers\.waypost\.tools\.(?:"?([A-Za-z0-9_-]+)"?)\]\s*(?:\#.*)?$/) {
            $waypost_tools{$1} = 1;
          }
        }

        my @out;
        my $skip_section = 0;
        for my $line (@lines) {
          if ($line =~ /^\[/) {
            $skip_section = 0;
            if ($line =~ /^\[mcp_servers\.$legacy_server\.tools\.(?:"?([A-Za-z0-9_-]+)"?)\](\s*(?:\#.*)?)$/) {
              my $target_tool = $1;
              my $trailing_comment = $2;
              $target_tool =~ s/^mailbox_/waypost_/;
              if ($waypost_tools{$target_tool}) {
                $skip_section = 1;
                next;
              }
              $waypost_tools{$target_tool} = 1;
              $line = "[mcp_servers.waypost.tools.$target_tool]$trailing_comment";
            }
          }
          push @out, $line unless $skip_section;
        }

        $_ = join "\n", @out;
    ' "$codex_config"; then
        log_error "Failed to migrate Codex MCP tool approvals: $codex_config"
        return 1
    fi

    log_ok "Migrated Codex MCP tool approvals to waypost"
    return 0
}

remove_codex_legacy_waypost_mcps() {
    local legacy_server
    local -a legacy_servers=(workflow_mailbox agent_mailbox agent-mailbox adwf-mailbox)

    if ! command -v "$CODEX_CLI_COMMAND" &>/dev/null && [[ $CODEX_CLI_AVAILABLE -ne 1 ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        for legacy_server in "${legacy_servers[@]}"; do
            log_dry "Would run: $CODEX_CLI_COMMAND mcp remove $legacy_server"
        done
        return 0
    fi

    for legacy_server in "${legacy_servers[@]}"; do
        "$CODEX_CLI_COMMAND" mcp remove "$legacy_server" >/dev/null 2>&1 || true
    done
}

codex_waypost_uses_builtin_command() {
    local mcp_config

    mcp_config="$("$CODEX_CLI_COMMAND" mcp get waypost 2>/dev/null)" || return 1
    [[ "$mcp_config" == *"command: waypost"* ]] && [[ "$mcp_config" == *"args: mcp"* ]]
}

install_codex_waypost_mcp() {
    if ! command -v "$CODEX_CLI_COMMAND" &>/dev/null && [[ $CODEX_CLI_AVAILABLE -ne 1 ]]; then
        log_warn "Skipping Codex MCP install ($CODEX_CLI_COMMAND not found)"
        return 0
    fi

    if codex_waypost_uses_builtin_command; then
        log_ok "Codex MCP already configured: waypost"
    else
        if "$CODEX_CLI_COMMAND" mcp get waypost >/dev/null 2>&1; then
            if [[ $DRY_RUN -eq 1 ]]; then
                log_dry "Would run: $CODEX_CLI_COMMAND mcp remove waypost"
            else
                "$CODEX_CLI_COMMAND" mcp remove waypost >/dev/null 2>&1 || true
            fi
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would run: $CODEX_CLI_COMMAND mcp add waypost -- waypost mcp"
        elif ! "$CODEX_CLI_COMMAND" mcp add waypost -- waypost mcp; then
            log_error "Failed to configure Codex MCP: waypost"
            return 1
        fi

        if [[ $DRY_RUN -ne 1 ]]; then
            log_ok "Configured Codex MCP: waypost"
        fi
    fi

    migrate_codex_legacy_waypost_tool_permissions || return 1
    remove_codex_legacy_waypost_mcps

    local codex_config="$HOME/.codex/config.toml"
    if [[ ! -f "$codex_config" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create Codex config: $codex_config"
            return 0
        fi
        log_error "Missing Codex config: $codex_config"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would ensure TMUX, AGENTDECK_INSTANCE_ID, CODEX_SESSION_ID passthrough and Waypost tool timeout in: $codex_config"
        return 0
    fi

    if WAYPOST_MCP_TOOL_TIMEOUT_SEC="$WAYPOST_MCP_TOOL_TIMEOUT_SEC" perl -0pi -e '
        my $tool_timeout_sec = $ENV{WAYPOST_MCP_TOOL_TIMEOUT_SEC};
        my $env_vars_line = q{env_vars = [ "TMUX", "AGENTDECK_INSTANCE_ID", "CODEX_SESSION_ID" ]};
        my $tool_timeout_line = "tool_timeout_sec = $tool_timeout_sec";
        my @lines = split /\n/, $_, -1;
        my @out = ();
        my $found = 0;
        my $in_section = 0;
        my $inserted = 0;

        for my $line (@lines) {
          if ($line =~ /^\[mcp_servers\.waypost\]$/) {
            $found = 1;
            $in_section = 1;
            $inserted = 0;
            push @out, $line;
            next;
          }

          if ($in_section && $line =~ /^\[/) {
            push @out, $tool_timeout_line unless $inserted;
            push @out, $env_vars_line unless $inserted;
            $inserted = 1;
            $in_section = 0;
          }

          next if $in_section && $line =~ /^\s*(env_vars|tool_timeout_sec)\s*=/;
          push @out, $line;
        }

        if ($in_section && !$inserted) {
          push @out, $tool_timeout_line;
          push @out, $env_vars_line;
        }

        die "waypost section not found\n" unless $found;

        $_ = join("\n", @out);
        $_ .= "\n" unless $_ =~ /\n\z/;
    ' "$codex_config" && WAYPOST_MCP_TOOL_TIMEOUT_SEC="$WAYPOST_MCP_TOOL_TIMEOUT_SEC" perl -0ne '
        my $tool_timeout_sec = quotemeta $ENV{WAYPOST_MCP_TOOL_TIMEOUT_SEC};
        exit(
          /\[mcp_servers\.waypost\][\s\S]*?^env_vars\s*=\s*\[\s*"TMUX"\s*,\s*"AGENTDECK_INSTANCE_ID"\s*,\s*"CODEX_SESSION_ID"\s*\]/m
          && /\[mcp_servers\.waypost\][\s\S]*?^tool_timeout_sec\s*=\s*$tool_timeout_sec\s*$/m
            ? 0
            : 1
        );
    ' "$codex_config"; then
        log_ok "Ensured Codex MCP env passthrough and Waypost tool timeout: waypost"
        return 0
    fi

    log_error "Failed to update Codex MCP env passthrough and Waypost tool timeout"
    return 1
}

ensure_claude_waypost_permissions() {
    local claude_settings="$HOME/.claude/settings.json"
    local claude_permissions_json
    local tmp_file

    claude_permissions_json="$(waypost_mcp_permissions_json 'mcp__waypost__' '')" || {
        log_error "Failed to build Claude Waypost MCP permissions"
        return 1
    }

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would migrate Claude MCP permissions to waypost in: $claude_settings"
        return 0
    fi

    mkdir -p "$(dirname "$claude_settings")" || {
        log_error "Failed to create Claude settings directory"
        return 1
    }

    if [[ ! -s "$claude_settings" ]]; then
        printf '{}\n' > "$claude_settings" || {
            log_error "Failed to create Claude settings file: $claude_settings"
            return 1
        }
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/claude-settings.XXXXXX")" || {
        log_error "Failed to create temporary file for Claude settings"
        return 1
    }

    if ! jq --argjson perms "$claude_permissions_json" '
        def migrate_permission:
            if type == "string" then
                sub("^mcp__(workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox)__"; "mcp__waypost__")
                | sub("^mcp__waypost__mailbox_"; "mcp__waypost__waypost_")
            else
                .
            end;
        def is_waypost_permission:
            type == "string" and startswith("mcp__waypost__");
        .permissions.allow = (
            (.permissions.allow // [])
            | map(migrate_permission)
            | if any(.[]?; is_waypost_permission) then . else . + $perms end
            | unique
        )
    ' "$claude_settings" > "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to migrate Claude MCP permissions: $claude_settings"
        return 1
    fi

    if mv "$tmp_file" "$claude_settings"; then
        log_ok "Migrated Claude MCP permissions to waypost"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write Claude MCP permissions: $claude_settings"
    return 1
}

rewrite_claude_waypost_config() {
    local claude_config="$HOME/.claude.json"
    local tmp_file

    if [[ ! -f "$claude_config" ]]; then
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would rewrite Claude MCP config with Waypost tool timeout in: $claude_config"
        return 0
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/claude-mcp-config.XXXXXX")" || {
        log_error "Failed to create temporary file for Claude MCP config"
        return 1
    }

    if ! jq --argjson timeout "$WAYPOST_MCP_TOOL_TIMEOUT_MS" '
        .mcpServers = ((.mcpServers // {})
            | del(.workflow_mailbox, .agent_mailbox, ."agent-mailbox", ."adwf-mailbox")
            | .waypost = (
                (.waypost // {})
                | .type = (.type // "stdio")
                | .command = "waypost"
                | .args = ["mcp"]
                | .timeout = $timeout
                | .env = {}
            ))
    ' "$claude_config" > "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to rewrite Claude MCP config: $claude_config"
        return 1
    fi

    if mv "$tmp_file" "$claude_config"; then
        log_ok "Rewrote Claude MCP config with Waypost tool timeout"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write Claude MCP config: $claude_config"
    return 1
}

remove_claude_stale_waypost_mcps() {
    local legacy_server
    local -a legacy_servers=(workflow_mailbox agent_mailbox agent-mailbox adwf-mailbox)

    if ! command -v claude &>/dev/null && [[ $CLAUDE_CODE_AVAILABLE -ne 1 ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        for legacy_server in "${legacy_servers[@]}"; do
            log_dry "Would run: claude mcp remove -s user $legacy_server"
        done
        return 0
    fi

    for legacy_server in "${legacy_servers[@]}"; do
        claude mcp remove -s user "$legacy_server" >/dev/null 2>&1 || true
    done
}

install_claude_waypost_mcp() {
    if [[ -f "$HOME/.claude.json" ]]; then
        rewrite_claude_waypost_config || return 1
        ensure_claude_waypost_permissions || return 1
        return 0
    fi

    if ! command -v claude &>/dev/null && [[ $CLAUDE_CODE_AVAILABLE -ne 1 ]]; then
        log_warn "Skipping Claude MCP install (claude not found)"
        return 0
    fi

    remove_claude_stale_waypost_mcps

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: claude mcp add -s user waypost -- waypost mcp"
        return 0
    fi

    if claude mcp add -s user waypost -- waypost mcp; then
        log_ok "Configured Claude MCP: waypost"
        rewrite_claude_waypost_config || return 1
        ensure_claude_waypost_permissions || return 1
        return 0
    fi

    log_error "Failed to configure Claude MCP: waypost"
    return 1
}

remove_obsolete_waypost_launchers() {
    local legacy_launchers=(
        "$HOME/.local/bin/adwf-mailbox-mcp"
        "$HOME/.local/bin/agent-mailbox-mcp"
    )
    local legacy_launcher

    for legacy_launcher in "${legacy_launchers[@]}"; do
        if [[ ! -e "$legacy_launcher" ]] && [[ ! -L "$legacy_launcher" ]]; then
            continue
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would remove obsolete launcher: $legacy_launcher"
            continue
        fi

        rm -f "$legacy_launcher"
        log_info "Removed obsolete launcher: $legacy_launcher"
    done
}

suggest_lsof_install() {
    echo ""
    log_info "agent-deck requires 'lsof'. Install it with:"
    echo ""
    case "$OS" in
        linux|wsl)
            echo "  # Debian/Ubuntu:"
            echo "  sudo apt install lsof"
            ;;
        macos)
            echo "  # Using Homebrew:"
            echo "  brew install lsof"
            ;;
        *)
            echo "  Install 'lsof' using your system package manager."
            ;;
    esac
    echo ""
}

check_agent_deck_prerequisites() {
    log_info "Checking agent-deck prerequisites..."

    # agent-deck depends on lsof on supported Unix-like hosts.
    case "$OS" in
        linux|wsl|macos)
            if ! command -v lsof &>/dev/null; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log_dry "Would use lsof installed with required CLI tools"
                    return 0
                fi
                log_error "Missing required command: lsof"
                suggest_lsof_install
                return 1
            fi
            log_ok "Found required command: lsof"
            ;;
        *)
            log_warn "Skipping lsof check on unsupported OS: $OS"
            ;;
    esac

    return 0
}

remove_agent_deck_codext_command() {
    local agent_deck_config="$HOME/.agent-deck/config.toml"

    if ! command -v agent-deck &>/dev/null && [[ $AGENT_DECK_AVAILABLE -ne 1 ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would remove obsolete [codex] command = \"codext\" references from: $agent_deck_config"
        return 0
    fi

    if [[ ! -f "$agent_deck_config" ]]; then
        return 0
    fi

    perl -0pi -e '
        my @lines = split /\n/, $_, -1;
        pop @lines if @lines && $lines[-1] eq "";

        my @out = ();
        my $in_codex = 0;

        for my $line (@lines) {
          if ($line =~ /^\s*\[codex\]\s*$/) {
            $in_codex = 1;
            push @out, $line;
            next;
          }

          if ($in_codex && $line =~ /^\s*\[/) {
            $in_codex = 0;
          }

          if ($in_codex && $line =~ /^\s*#?\s*command\s*=\s*"codext"\s*$/) {
            next;
          }

          push @out, $line;
        }

        $_ = join("\n", @out);
        $_ .= "\n";
    ' "$agent_deck_config" || {
        log_error "Failed to remove obsolete Codex command from: $agent_deck_config"
        return 1
    }

    log_ok "Removed obsolete [codex] codext command references when present"
    return 0
}

configure_agent_deck_updates() {
    local agent_deck_config="$HOME/.agent-deck/config.toml"

    ensure_toml_literal_key "$agent_deck_config" "updates" "auto_update" "false" || return 1
    ensure_toml_literal_key "$agent_deck_config" "updates" "check_enabled" "false" || return 1
    ensure_toml_literal_key "$agent_deck_config" "updates" "notify_in_cli" "false" || return 1
}

configure_agent_deck_kiro_tool() {
    local agent_deck_config="$HOME/.agent-deck/config.toml"

    ensure_toml_string_key "$agent_deck_config" "tools.kiro" "command" "kiro-cli" || return 1
    ensure_toml_literal_key "$agent_deck_config" "tools.kiro" "busy_patterns" '["thinking...", "processing..."]' || return 1
}

is_agent_deck_related_skill() {
    local skill_name="$1"
    case "$skill_name" in
        agent-deck|agent-deck-workflow)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

setup_agent_deck_integration() {
    local agent_deck_planned=0

    if ! command -v agent-deck &>/dev/null; then
        if [[ $DRY_RUN -eq 1 && $AGENT_DECK_AVAILABLE -eq 1 ]]; then
            agent_deck_planned=1
            log_dry "Would use newly installed agent-deck"
        else
            AGENT_DECK_AVAILABLE=0
            log_warn "agent-deck not found; skipping agent-deck related skills and policy/rule links"
            return 0
        fi
    else
        AGENT_DECK_AVAILABLE=1
        log_ok "Found agent-deck"
    fi

    if ! check_agent_deck_prerequisites; then
        return 1
    fi

    if ! remove_agent_deck_codext_command; then
        return 1
    fi

    if ! configure_agent_deck_updates; then
        return 1
    fi

    if ! configure_agent_deck_kiro_tool; then
        return 1
    fi

    local has_hooks_cmd=0
    if [[ $agent_deck_planned -eq 0 ]] && agent-deck hooks status >/dev/null 2>&1; then
        has_hooks_cmd=1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ $agent_deck_planned -eq 1 ]]; then
            log_dry "Would run: agent-deck hooks install if supported"
        elif [[ $has_hooks_cmd -eq 1 ]]; then
            log_dry "Would run: agent-deck hooks install"
        else
            log_warn "agent-deck hooks command not available; skipping Claude hook install"
        fi
        log_dry "Would run: agent-deck codex-hooks install"
        return 0
    fi

    if [[ $has_hooks_cmd -eq 1 ]]; then
        if agent-deck hooks install >/dev/null 2>&1; then
            log_ok "Configured agent-deck Claude hooks"
        else
            log_warn "Failed to configure agent-deck Claude hooks (continue)"
            log_info "You can retry manually: agent-deck hooks install"
        fi
    else
        log_warn "agent-deck hooks command not available; skipping Claude hook install"
    fi

    if agent-deck codex-hooks install >/dev/null 2>&1; then
        log_ok "Configured agent-deck Codex hooks"
    else
        log_warn "Failed to configure agent-deck Codex hooks (continue)"
        log_info "You can retry manually: agent-deck codex-hooks install"
    fi

    return 0
}

install_home_configs() {
    log_info "Installing home directory dotfiles..."

    # Shell configs
    install_copy "bashrc" "$HOME/.bashrc"
    install_copy "zshrc" "$HOME/.zshrc"

    # Screen config
    install_copy "screenrc" "$HOME/.screenrc"

    # Tmux config (file in tmux/ directory)
    install_copy "tmux/tmux.conf" "$HOME/.tmux.conf"
    install_copy "tmux/plugins/tpm" "$HOME/.tmux/plugins/tpm"

    # Git config (OS-specific)
    case "$OS" in
        linux|wsl|macos)
            install_copy \
                "gitconfig.unix" \
                "$HOME/.gitconfig" \
                0 \
                "$SCRIPT_DIR/gitconfig.ruiheng.unix"
            ;;
        windows)
            install_copy \
                "gitconfig.win" \
                "$HOME/.gitconfig" \
                0 \
                "$SCRIPT_DIR/gitconfig.ruiheng.win"
            ;;
    esac

    # Global gitignore
    install_copy "gitignore" "$HOME/.gitignore" 0 "$SCRIPT_DIR/.gitignore"
    install_copy "git-completion.sh" "$HOME/.git-completion.sh"
}

install_xdg_configs() {
    log_info "Installing XDG config directory files..."

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"

    if [[ "$OS" == linux ]]; then
        # Linux desktop configs and user services.
        install_copy "i3" "$config_dir/i3"
        install_copy "niri" "$config_dir/niri"
        install_copy "sway" "$config_dir/sway"
        install_copy "waybar" "$config_dir/waybar"
        install_copy "systemd" "$config_dir/systemd"
    else
        log_warn "Skipping Linux desktop configs on: $OS"
        skipped=$((skipped + 5))
    fi

    # Terminal and file manager
    install_copy "ranger" "$config_dir/ranger"

    # Cross-platform application configs.
    install_copy "nvim" "$config_dir/nvim"

    # Individual files
    install_copy "fourmolu.yaml" "$config_dir/fourmolu.yaml"

    # AI-related configs
    install_copy "ai-agent" "$config_dir/ai-agent"

    # GRC (Generic Colouriser)
    install_copy "grc" "$config_dir/grc"
}

install_local_bin_helpers() {
    log_info "Installing local bin helper scripts..."

    local bin_dir="$HOME/.local/bin"

    if [[ "$OS" != linux ]]; then
        log_warn "Skipping Linux desktop helper scripts on: $OS"
        skipped=$((skipped + 2))
        return 0
    fi

    if [[ ! -d "$bin_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $bin_dir"
        else
            mkdir -p "$bin_dir"
            log_info "Created directory: $bin_dir"
        fi
    fi

    install_copy "niri/scripts/foot-auto-font" "$bin_dir/foot-auto-font"
    install_copy \
        "scripts/x11-wayland-clipboard-bridge" \
        "$bin_dir/x11-wayland-clipboard-bridge"
}

prepare_skills_target_dir() {
    local tool_name="$1"
    local skills_dir="$2"
    local action

    # Ensure parent directory exists
    local skills_parent
    skills_parent="$(dirname "$skills_dir")"
    if [[ ! -d "$skills_parent" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $skills_parent"
        else
            mkdir -p "$skills_parent"
            log_info "Created directory: $skills_parent"
        fi
    fi

    # If skills path is a symlink, convert it to a real directory first.
    # This prevents accidental operations on the symlink target.
    if [[ -L "$skills_dir" ]]; then
        log_warn "$tool_name skills path is a symlink: $skills_dir -> $(readlink "$skills_dir")"

        if symlink_points_to "$skills_dir" "$SCRIPT_DIR/ai-agent/skills" \
            || symlink_points_to "$skills_dir" "$SHARED_AI_AGENT_DIR/skills"; then
            if [[ $DRY_RUN -eq 1 ]]; then
                log_dry "Would migrate installer-managed skills directory: $skills_dir"
            else
                rm -f "$skills_dir"
                log_info "Removed installer-managed skills directory symlink: $skills_dir"
            fi
        elif [[ $FORCE -eq 1 ]]; then
            if ! backup_item "$skills_dir"; then
                return 1
            fi
        elif [[ $INTERACTIVE -eq 1 ]]; then
            prompt_user "$skills_dir"
            action=$?
            case "$action" in
                0) # skip
                    return 1
                    ;;
                1) # backup
                    if ! backup_item "$skills_dir"; then
                        return 1
                    fi
                    ;;
                2) # force replace
                    if [[ $DRY_RUN -eq 1 ]]; then
                        log_dry "Would remove existing path: $skills_dir"
                    else
                        remove_installed_path "$skills_dir"
                        log_info "Removed existing path: $skills_dir"
                    fi
                    ;;
                3) # cancel
                    log_info "Installation cancelled by user"
                    exit 0
                    ;;
            esac
        else
            log_warn "Skipping $tool_name skills setup. Use --force or --interactive to migrate $skills_dir."
            return 1
        fi
    elif [[ -e "$skills_dir" ]] && [[ ! -d "$skills_dir" ]]; then
        log_warn "$tool_name skills path exists but is not a directory: $skills_dir"
        if [[ $FORCE -eq 1 ]]; then
            if ! backup_item "$skills_dir"; then
                return 1
            fi
        elif [[ $INTERACTIVE -eq 1 ]]; then
            prompt_user "$skills_dir"
            action=$?
            case "$action" in
                0) # skip
                    return 1
                    ;;
                1) # backup
                    if ! backup_item "$skills_dir"; then
                        return 1
                    fi
                    ;;
                2) # force replace
                    if [[ $DRY_RUN -eq 1 ]]; then
                        log_dry "Would remove existing path: $skills_dir"
                    else
                        remove_installed_path "$skills_dir"
                        log_info "Removed existing path: $skills_dir"
                    fi
                    ;;
                3) # cancel
                    log_info "Installation cancelled by user"
                    exit 0
                    ;;
            esac
        else
            log_warn "Skipping $tool_name skills setup. Use --force or --interactive to replace $skills_dir."
            return 1
        fi
    fi

    if [[ ! -d "$skills_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $skills_dir"
        else
            mkdir -p "$skills_dir"
            log_info "Created directory: $skills_dir"
        fi
    fi

    return 0
}

cleanup_dead_skill_links() {
    local tool_name="$1"
    local tool_skills_dir="$2"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    if [[ ! -d "$tool_skills_dir" ]]; then
        return 0
    fi

    for installed_skill in "$tool_skills_dir"/*; do
        if [[ ! -e "$installed_skill" ]] && [[ ! -L "$installed_skill" ]]; then
            continue
        fi
        if [[ ! -L "$installed_skill" ]]; then
            continue
        fi

        local skill_name
        skill_name=$(basename "$installed_skill")
        local src_skill_dir="$src_skills_dir/$skill_name"
        if [[ -e "$src_skill_dir" ]]; then
            continue
        fi

        if ! symlink_points_to "$installed_skill" "$src_skill_dir" \
            && ! symlink_points_to "$installed_skill" "$SHARED_AI_AGENT_DIR/skills/$skill_name"; then
            continue
        fi
        if [[ -e "$installed_skill" ]]; then
            continue
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would remove dead $tool_name skill link: $installed_skill -> $(readlink "$installed_skill")"
        else
            rm "$installed_skill"
            log_info "Removed dead $tool_name skill link: $installed_skill"
        fi
    done
}

install_skills_individually() {
    local tool_name="$1"
    local tool_skills_dir="$2"
    local missing_only="${3:-0}"
    local target_prepared="${4:-0}"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    if [[ $missing_only -eq 1 ]]; then
        log_info "Installing missing $tool_name skills..."
        if [[ ! -d "$tool_skills_dir" ]] && [[ ! -L "$tool_skills_dir" ]]; then
            log_error "$tool_name skills path is missing: $tool_skills_dir"
            return 1
        fi
    else
        log_info "Installing $tool_name skills (individually)..."

        if [[ $target_prepared -eq 0 ]]; then
            if ! prepare_skills_target_dir "$tool_name" "$tool_skills_dir"; then
                return 0
            fi
        fi
    fi

    # The shared Gemini directory can contain user-managed skills and links.
    # Missing-only sync must not alter its existing entries.
    if [[ $missing_only -ne 1 ]]; then
        cleanup_dead_skill_links "$tool_name" "$tool_skills_dir"
    fi

    if [[ -d "$src_skills_dir" ]]; then
        for skill_dir in "$src_skills_dir"/*; do
            if [[ -d "$skill_dir" ]]; then
                local skill_name
                skill_name=$(basename "$skill_dir")
                local target_skill="$tool_skills_dir/$skill_name"

                if is_agent_deck_related_skill "$skill_name" && [[ $AGENT_DECK_AVAILABLE -eq 0 ]]; then
                    log_warn "Skipping $tool_name skill '$skill_name' (agent-deck not installed)"
                    skipped=$((skipped + 1))
                    continue
                fi

                if [[ $missing_only -eq 1 ]] && [[ -e "$target_skill" || -L "$target_skill" ]]; then
                    continue
                fi

                link_shared_ai_agent_item "skills/$skill_name" "$target_skill"
            fi
        done
    fi
}

install_claude_skills() {
    install_skills_individually "Claude Code" "$HOME/.claude/skills"
}

install_claude_config() {
    log_info "Installing Claude Code config..."

    local claude_dir="$HOME/.claude"

    # Create .claude directory if needed
    if [[ ! -d "$claude_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $claude_dir"
        else
            mkdir -p "$claude_dir"
            log_info "Created directory: $claude_dir"
        fi
    fi

    # Link shared instructions from the stable installed snapshot.
    link_shared_ai_agent_item "CLAUDE.md" "$claude_dir/CLAUDE.md"
    # CLAUDE.md uses @modules/* relative imports.
    link_shared_ai_agent_item "modules" "$claude_dir/modules"

    # Link skills individually (required by Claude Code)
    install_claude_skills

    # Install workflow permission init script to ~/.local/bin
    local bin_dir="$HOME/.local/bin"
    link_shared_ai_agent_item "skills/agent-deck-workflow/scripts/agent-deck-workflow-init-permissions.sh" "$bin_dir/agent-deck-workflow-init-permissions"
    link_shared_ai_agent_item "skills/agent-deck-workflow/scripts/adwf-send-and-wake.sh" "$bin_dir/adwf-send-and-wake"
    remove_obsolete_waypost_launchers
    if ! ensure_waypost_mcp_command; then
        log_error "Failed to verify built-in waypost MCP command for Claude"
        return 1
    fi
    install_claude_waypost_mcp

    # Link statusline script
    link_shared_ai_agent_item "claude/statusline-command.sh" "$claude_dir/statusline-command.sh"
}

cleanup_gemini_duplicate_skill_links() {
    local gemini_skills_dir="$1"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    if [[ ! -d "$gemini_skills_dir" ]]; then
        return 0
    fi

    cleanup_dead_skill_links "Gemini CLI" "$gemini_skills_dir"

    for skill_dir in "$src_skills_dir"/*; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            local target_link="$gemini_skills_dir/$skill_name"

            # Remove only symlink entries to avoid deleting user-managed directories/files.
            if [[ -L "$target_link" ]]; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log_dry "Would remove duplicate Gemini skill link: $target_link"
                else
                    rm "$target_link"
                    log_info "Removed duplicate Gemini skill link: $target_link"
                fi
            fi
        fi
    done
}

has_shared_gemini_skill_conflicts() {
    local agents_skills_dir="$1"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    if [[ ! -d "$agents_skills_dir" ]] && [[ ! -L "$agents_skills_dir" ]]; then
        return 1
    fi

    for skill_dir in "$src_skills_dir"/*; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            if [[ -f "$agents_skills_dir/$skill_name/SKILL.md" ]]; then
                return 0
            fi
        fi
    done

    return 1
}

install_gemini_skills() {
    local agents_skills_dir="$HOME/.agents/skills"
    local gemini_skills_dir="$HOME/.gemini/skills"

    # Newer Gemini setup may load skills from ~/.agents/skills.
    # Installing duplicates in ~/.gemini/skills triggers skill conflict warnings.
    if has_shared_gemini_skill_conflicts "$agents_skills_dir"; then
        log_info "Detected shared Gemini skills path: $agents_skills_dir"
        install_skills_individually "Gemini shared" "$agents_skills_dir" 1 || return 1
        log_warn "Skipping Gemini skill links under $gemini_skills_dir to avoid duplicate skill conflicts"
        cleanup_gemini_duplicate_skill_links "$gemini_skills_dir"
        return 0
    fi

    install_skills_individually "Gemini CLI" "$HOME/.gemini/skills"
}

install_antigravity_skills() {
    install_skills_individually "Antigravity CLI" "$HOME/.gemini/antigravity-cli/skills"
}

install_antigravity_config() {
    log_info "Installing Antigravity CLI config..."

    install_antigravity_skills

    if ! ensure_waypost_mcp_command; then
        log_error "Failed to verify built-in waypost MCP command for Antigravity"
        return 1
    fi

    install_antigravity_waypost_mcp
}

install_kiro_skills() {
    install_skills_individually "Kiro CLI" "$HOME/.kiro/skills"
}

install_kiro_config() {
    log_info "Installing Kiro CLI config..."

    if command -v kiro-cli &>/dev/null; then
        log_ok "Found kiro-cli"
    else
        log_warn "kiro-cli not found; writing Kiro config files only"
    fi

    install_kiro_skills

    if ! ensure_waypost_mcp_command; then
        log_error "Failed to verify built-in waypost MCP command for Kiro CLI"
        return 1
    fi

    install_kiro_waypost_mcp
}

install_gemini_config() {
    log_info "Installing Gemini CLI config..."

    local gemini_dir="$HOME/.gemini"

    if [[ ! -d "$gemini_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $gemini_dir"
        else
            mkdir -p "$gemini_dir"
            log_info "Created directory: $gemini_dir"
        fi
    fi

    # Link shared instructions from the stable installed snapshot.
    link_shared_ai_agent_item "GEMINI.md" "$gemini_dir/GEMINI.md"
    # GEMINI.md uses @modules/* relative imports.
    link_shared_ai_agent_item "modules" "$gemini_dir/modules"

    # Link skills individually for reliability
    install_gemini_skills

    # Link shell policy rules for workflow automation approvals
    if [[ $AGENT_DECK_AVAILABLE -eq 1 ]]; then
        link_shared_ai_agent_item \
            "gemini/policies/agent-deck-workflow.toml" \
            "$gemini_dir/policies/agent-deck-workflow.toml" \
            ".gemini/policies/agent-deck-workflow.toml"
    else
        log_warn "Skipping Gemini agent-deck workflow policy link (agent-deck not installed)"
    fi

    if ! ensure_waypost_mcp_command; then
        log_error "Failed to verify built-in waypost MCP command for Gemini"
        return 1
    fi

    install_gemini_waypost_mcp
}

install_codex_skills() {
    local codex_skills_dir="$HOME/.codex/skills"

    CODEX_SKILLS_DIR_READY=0
    if ! prepare_skills_target_dir "Codex" "$codex_skills_dir"; then
        return 0
    fi

    CODEX_SKILLS_DIR_READY=1
    install_skills_individually "Codex" "$codex_skills_dir" 0 1
}

ensure_codex_tui_usage_limit_resume_prompt() {
    local codex_config="$HOME/.codex/config.toml"
    local prompt="The previous turn stopped because the active account hit a usage limit. You can go on now."

    ensure_toml_string_key "$codex_config" "tui" "usage_limit_resume_prompt" "$prompt"
}

install_opencode_skills() {
    install_skills_individually "OpenCode" "$HOME/.config/opencode/skills"
}

opencode_config_file_path() {
    local opencode_dir="$1"

    if [[ -f "$opencode_dir/opencode.json" ]]; then
        echo "$opencode_dir/opencode.json"
        return 0
    fi

    if [[ -f "$opencode_dir/config.json" ]]; then
        echo "$opencode_dir/config.json"
        return 0
    fi

    echo "$opencode_dir/opencode.json"
}

install_codex_config() {
    log_info "Installing Codex config..."

    local codex_dir="$HOME/.codex"

    if [[ ! -d "$codex_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $codex_dir"
        else
            mkdir -p "$codex_dir"
            log_info "Created directory: $codex_dir"
        fi
    fi

    install_codex_skills
    # ensure_codex_tui_usage_limit_resume_prompt || return 1

    # Link Codex escalation rules for workflow automation approvals
    if [[ $AGENT_DECK_AVAILABLE -eq 1 ]]; then
        link_shared_ai_agent_item \
            "codex/rules/agent-deck-workflow.rules" \
            "$codex_dir/rules/agent-deck-workflow.rules" \
            ".codex/rules/agent-deck-workflow.rules"
    else
        log_warn "Skipping Codex agent-deck workflow rule link (agent-deck not installed)"
    fi

    if ! ensure_waypost_mcp_command; then
        log_error "Failed to verify built-in waypost MCP command for Codex"
        return 1
    fi

    install_codex_waypost_mcp
}

install_opencode_waypost_mcp() {
    local opencode_dir="$HOME/.config/opencode"
    local config_file
    local tmp_file

    config_file="$(opencode_config_file_path "$opencode_dir")"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would ensure OpenCode MCP config in: $config_file"
        return 0
    fi

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/opencode-mcp-config.XXXXXX")" || {
        log_error "Failed to create temporary file for OpenCode MCP config"
        return 1
    }

    if [[ -f "$config_file" ]]; then
        if ! jq '
            .["$schema"] //= "https://opencode.ai/config.json"
            | .mcp = ((.mcp // {})
                | del(.workflow_mailbox, .agent_mailbox, ."agent-mailbox", ."adwf-mailbox")
                | .waypost = {
                    type: "local",
                    command: ["waypost", "mcp"],
                    environment: {
                        AGENTDECK_INSTANCE_ID: "{env:AGENTDECK_INSTANCE_ID}",
                        TMUX: "{env:TMUX}"
                    }
                })
        ' "$config_file" > "$tmp_file"; then
            rm -f "$tmp_file"
            log_error "Failed to update OpenCode MCP config: $config_file"
            return 1
        fi
    elif ! jq -n '
        {
            "$schema": "https://opencode.ai/config.json",
            mcp: {
                waypost: {
                    type: "local",
                    command: ["waypost", "mcp"],
                    environment: {
                        AGENTDECK_INSTANCE_ID: "{env:AGENTDECK_INSTANCE_ID}",
                        TMUX: "{env:TMUX}"
                    }
                }
            }
        }
    ' > "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to create OpenCode MCP config: $config_file"
        return 1
    fi

    if mv "$tmp_file" "$config_file"; then
        log_ok "Ensured OpenCode MCP config: waypost"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write OpenCode MCP config: $config_file"
    return 1
}

install_opencode_config() {
    log_info "Installing OpenCode config..."

    local opencode_dir="$HOME/.config/opencode"

    if [[ ! -d "$opencode_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $opencode_dir"
        else
            mkdir -p "$opencode_dir"
            log_info "Created directory: $opencode_dir"
        fi
    fi

    # Link shared instructions from the stable installed snapshot.
    link_shared_ai_agent_item "AGENTS.md" "$opencode_dir/AGENTS.md"
    # AGENTS.md uses @modules/* relative imports.
    link_shared_ai_agent_item "modules" "$opencode_dir/modules"

    # Link skills individually for OpenCode
    install_opencode_skills

    if ! ensure_waypost_mcp_command; then
        log_error "Failed to verify built-in waypost MCP command for OpenCode"
        return 1
    fi

    install_opencode_waypost_mcp
}

install_serena_config() {
    log_info "Installing Serena config..."

    local serena_dir="$HOME/.serena"

    # Create .serena directory if needed
    if [[ ! -d "$serena_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $serena_dir"
        else
            mkdir -p "$serena_dir"
            log_info "Created directory: $serena_dir"
        fi
    fi

    # Link project.yml and memories if they exist
    if [[ -d "$SCRIPT_DIR/.serena/memories" ]]; then
        install_copy ".serena/memories" "$serena_dir/memories"
    fi

    if [[ -f "$SCRIPT_DIR/.serena/project.yml" ]]; then
        install_copy ".serena/project.yml" "$serena_dir/project.yml"
    fi
}

# =============================================================================
# Git Submodules
# =============================================================================

init_submodules() {
    log_info "Initializing git submodules..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: git submodule update --init --recursive"
        return 0
    fi

    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        log_warn "Not a git repository, skipping submodule initialization"
        return 0
    fi

    # Check if there are any submodules defined
    if [[ ! -f "$SCRIPT_DIR/.gitmodules" ]]; then
        log_info "No .gitmodules found, skipping submodule initialization"
        return 0
    fi

    # Initialize and update submodules
    if git -C "$SCRIPT_DIR" submodule update --init --recursive; then
        log_ok "Submodules initialized successfully"
    else
        log_warn "Failed to initialize some submodules (may require SSH key)"
        log_info "You can manually initialize later with: git submodule update --init --recursive"
    fi
}

# =============================================================================
# Neovim Setup
# =============================================================================

check_nvim_installed() {
    if command -v nvim &>/dev/null; then
        return 0
    else
        return 1
    fi
}

get_nvim_version() {
    nvim --version | head -1 | grep -Eo '[0-9]+\.[0-9]+' | head -1
}

nvim_version_is_supported() {
    local version="$1"
    local major
    local minor

    major="${version%%.*}"
    minor="${version#*.}"
    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    (( 10#$major > 0 || 10#$minor >= 9 ))
}

install_nvim_prerequisites() {
    log_info "Checking Neovim prerequisites..."

    if ! check_nvim_installed; then
        log_warn "Neovim not found in PATH"
        return 1
    fi

    local nvim_version
    nvim_version=$(get_nvim_version)
    log_info "Found Neovim version: $nvim_version"

    # Check if version is at least 0.9
    if ! nvim_version_is_supported "$nvim_version"; then
        log_warn "Neovim version should be 0.9 or higher for this configuration"
    fi

    return 0
}

suggest_nvim_install() {
    echo ""
    log_info "To install Neovim:"
    echo ""
    case "$OS" in
        linux)
            echo "  # Debian/Ubuntu:"
            echo "  sudo apt install neovim"
            echo ""
            echo "  # Or install latest from GitHub:"
            echo "  curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
            echo "  sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz"
            echo "  ln -s /opt/nvim-linux-x86_64/bin/nvim ~/.local/bin/nvim"
            ;;
        macos)
            echo "  # Using Homebrew:"
            echo "  brew install neovim"
            ;;
        wsl)
            echo "  # Debian/Ubuntu:"
            echo "  sudo apt install neovim"
            echo ""
            echo "  # Or install latest from GitHub:"
            echo "  curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
            echo "  sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz"
            echo "  ln -s /opt/nvim-linux-x86_64/bin/nvim ~/.local/bin/nvim"
            ;;
        *)
            echo "  See: https://github.com/neovim/neovim/blob/master/INSTALL.md"
            ;;
    esac
    echo ""
}

setup_nvim() {
    log_info "Setting up Neovim configuration..."

    if ! install_nvim_prerequisites; then
        log_warn "Neovim setup incomplete - Neovim not found"
        suggest_nvim_install
        return 1
    fi

    # The nvim config is installed by install_xdg_configs; just verify it exists.
    local nvim_config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    if [[ -d "$nvim_config" ]]; then
        log_ok "Neovim config installed at: $nvim_config"
    fi

    log_info "Neovim setup complete."
    log_info "  - Lazy.nvim will bootstrap itself on first nvim start"
    log_info "  - All plugins will be automatically installed"
    log_info "  - Run 'nvim' to complete setup"
}

# =============================================================================
# OS-Specific Installations
# =============================================================================

install_linux_specific() {
    log_info "Applying Linux-specific configurations..."

    # Check if systemd user directory should be enabled
    if [[ -d "$SCRIPT_DIR/systemd" ]]; then
        local systemd_user_dir="$HOME/.config/systemd/user"
        if [[ ! -d "$systemd_user_dir" ]]; then
            if [[ $DRY_RUN -eq 1 ]]; then
                log_dry "Would create directory: $systemd_user_dir"
            else
                mkdir -p "$systemd_user_dir"
                log_info "Created systemd user directory: $systemd_user_dir"
            fi
        fi
    fi
}

install_macos_specific() {
    log_info "Applying macOS-specific configurations..."

    log_info "Linux desktop configs, helper scripts, and systemd services were skipped on macOS"
}

install_wsl_specific() {
    log_info "Applying WSL-specific configurations..."

    log_info "Linux desktop configs, helper scripts, and systemd services were skipped on WSL"
}

# =============================================================================
# Main
# =============================================================================

print_banner() {
    echo ""
    echo "========================================"
    echo "  Config Files Installation Script"
    echo "  OS detected: $OS"
    echo "  Package manager: $PACKAGE_MANAGER"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  MODE: DRY RUN (no changes will be made)"
    elif [[ $FORCE -eq 1 ]]; then
        echo "  MODE: FORCE (existing files will be backed up)"
    elif [[ $INTERACTIVE -eq 1 ]]; then
        echo "  MODE: INTERACTIVE (will prompt on conflicts)"
    fi
    echo "========================================"
    echo ""
}

print_summary() {
    echo ""
    echo "========================================"
    echo "  Installation Summary"
    echo "========================================"
    echo -e "  ${GREEN}Copied:${NC}   $copied"
    echo -e "  ${GREEN}Linked:${NC}   $linked"
    echo -e "  ${YELLOW}Skipped:${NC}  $skipped"
    if [[ $backed_up -gt 0 ]]; then
        echo -e "  ${BLUE}Backed up:${NC} $backed_up"
    fi
    echo -e "  ${RED}Failed:${NC}   $failed"
    echo ""

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "Dry run complete. No changes were made."
        log_info "Run without --dry-run to apply changes."
        return 0
    fi

    if [[ $failed -gt 0 ]]; then
        log_error "Some operations failed. Please review the output above."
        return 1
    else
        log_ok "Installation completed successfully!"
        return 0
    fi
}

main() {
    parse_args "$@"

    print_banner

    log_info "Source directory: $SCRIPT_DIR"
    log_info "Target home: $HOME"

    if ! install_required_tools; then
        exit 1
    fi

    ensure_path_contains_local_bin

    if ! install_mq; then
        exit 1
    fi

    if ! install_oh_my_zsh; then
        exit 1
    fi

    if ! install_nodejs_with_nvm; then
        exit 1
    fi

    if ! install_codex_cli; then
        exit 1
    fi
    CODEX_CLI_AVAILABLE=1

    if ! install_remote_cli "Claude Code" "claude" "$CLAUDE_CODE_INSTALL_URL" ""; then
        exit 1
    fi
    CLAUDE_CODE_AVAILABLE=1

    if ! install_remote_cli "Antigravity CLI" "agy" "$ANTIGRAVITY_INSTALL_URL" "$ANTIGRAVITY_INSTALL_SHA256"; then
        exit 1
    fi

    if ! install_remote_cli "agent-deck" "agent-deck" "$AGENT_DECK_INSTALL_URL" "$AGENT_DECK_INSTALL_SHA256" --version "$AGENT_DECK_VERSION" --skip-tmux-config --non-interactive; then
        exit 1
    fi
    AGENT_DECK_AVAILABLE=1

    if ! install_agent_browser; then
        exit 1
    fi

    if ! install_ast_grep; then
        exit 1
    fi

    if ! install_codegraph; then
        exit 1
    fi

    if ! install_tree_sitter_cli; then
        exit 1
    fi

    if ! ensure_waypost_mcp_command; then
        exit 1
    fi

    if ! migrate_legacy_waypost_state_if_present; then
        exit 1
    fi

    if ! setup_agent_deck_integration; then
        exit 1
    fi

    # Initialize git submodules first
    init_submodules

    if ! install_shared_ai_agent_snapshot; then
        exit 1
    fi

    # Install configs
    install_home_configs
    install_xdg_configs
    install_local_bin_helpers
    install_claude_config
    install_gemini_config
    install_antigravity_config
    install_kiro_config
    install_codex_config
    if ! install_ast_grep_skill; then
        exit 1
    fi
    install_opencode_config
    install_serena_config

    # OS-specific handling
    case "$OS" in
        linux)
            install_linux_specific
            ;;
        macos)
            install_macos_specific
            ;;
        wsl)
            install_wsl_specific
            ;;
    esac

    # Setup Neovim (important!)
    setup_nvim

    print_summary
}

# Run only when executed directly; sourcing is useful for focused installer tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
