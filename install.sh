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
#   --only PARTS  Install only selected comma-separated sections
#   --skip PARTS  Skip selected comma-separated sections
#   --ai-skills   Install/update AI skills only
#   --ai-rules     Install/update global AI authorization rules only
#   --no-color    Disable colored output
#   --help        Show this help message
#

set -uo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Script directory (where this script resides)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=ai-agent/skills/agent-deck-workflow/scripts/waypost-permission-spec.sh
source "$SCRIPT_DIR/ai-agent/skills/agent-deck-workflow/scripts/waypost-permission-spec.sh"
readonly CONFIG_FILES_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/config_files"
readonly MANAGED_PATHS_FILE="$CONFIG_FILES_STATE_DIR/managed-paths"
readonly MANAGED_COPIES_DIR="$CONFIG_FILES_STATE_DIR/managed-copies"
readonly SHARED_INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/config_files"
readonly SHARED_AI_AGENT_DIR="$SHARED_INSTALL_ROOT/ai-agent"
readonly SHARED_AGENT_SKILLS_DIR="$HOME/.agents/skills"

# Command line flags
DRY_RUN=0
FORCE=0
INTERACTIVE=0
USE_COLOR=1

# Installation selection. The default installs every section and bootstraps
# required tools. Partial selections skip unrelated bootstrap work; skips keep
# the full-install bootstrap and omit only the selected sections.
declare -a SELECTED_COMPONENTS=()
declare -a SKIPPED_COMPONENTS=()
declare -a REQUIRED_SUBMODULE_PATHS=()
INSTALL_ALL=1
ONLY_ALL_REQUESTED=0
SKIP_COMPONENTS_REQUESTED=0

# Interactive mode defaults (for 'all' responses)
ALL_SKIP=0
ALL_BACKUP=0
ALL_REPLACE=0

# Optional integration flags
AGENT_DECK_AVAILABLE=0
WAYPOST_CONFIG_SWITCH_READY=0
AI_RULES_WAYPOST_PREREQUISITES=unknown
CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS='[]'
CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT=0
CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
SHARED_AGENT_SKILLS_DIR_READY=0
CODEX_SKILLS_DIR_READY=0
CLAUDE_CODE_AVAILABLE=0
CODEX_CLI_AVAILABLE=0
CODEX_LEGACY_MCP_CLEANUP_PENDING=0
NODE_NPM_AVAILABLE=0
RUST_CARGO_PLANNED=0
SHARED_AI_AGENT_READY=0
ZSH_STACK_READY=0
CODEX_CLI_COMMAND="codex"
NVM_VERSION="v0.40.3"
NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh"
RUSTUP_INSTALL_URL="https://sh.rustup.rs"
MQ_VERSION="v0.7.0"
MQ_RELEASE_BASE_URL="https://github.com/harehare/mq/releases/download/$MQ_VERSION"
LAZYGIT_RELEASE_API_URL="https://api.github.com/repos/jesseduffield/lazygit/releases/latest"
UV_INSTALL_URL="https://astral.sh/uv/install.sh"
SPACESHIP_PROMPT_REPO="https://github.com/spaceship-prompt/spaceship-prompt.git"
SPACESHIP_VI_MODE_REPO="https://github.com/spaceship-prompt/spaceship-vi-mode.git"
ZSH_AUTOCOMPLETE_REPO="https://github.com/marlonrichert/zsh-autocomplete.git"
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
WAYPOST_CLI_RULE_MARKER="# Managed by config_files: Waypost read-only CLI permissions"

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

normalize_install_component() {
    case "$1" in
        dotfiles)
            printf '%s\n' "home"
            ;;
        skills|ai_skills)
            printf '%s\n' "ai-skills"
            ;;
        rules|ai_rules|agent_rules|agent-rules|waypost-rules|waypost_rules|waypost_cli_rules|waypost-cli-rules)
            printf '%s\n' "ai-rules"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

is_valid_install_component() {
    case "$1" in
        all|home|xdg|bin|ai|ai-skills|ai-rules|serena)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

add_install_component() {
    local component
    local selected_component

    if [[ $SKIP_COMPONENTS_REQUESTED -eq 1 ]]; then
        echo "Cannot combine --only with --skip"
        exit 1
    fi

    component="$(normalize_install_component "$1")"
    if [[ -z "$component" ]] || ! is_valid_install_component "$component"; then
        echo "Unknown install component: $1"
        echo "Valid components: all, home, xdg, bin, ai, ai-skills, ai-rules, serena"
        exit 1
    fi

    if [[ "$component" == "all" ]]; then
        if [[ -n "${SELECTED_COMPONENTS[0]+set}" ]]; then
            echo "Cannot combine 'all' with other install components"
            exit 1
        fi
        INSTALL_ALL=1
        ONLY_ALL_REQUESTED=1
        return 0
    fi

    if [[ $ONLY_ALL_REQUESTED -eq 1 ]]; then
        echo "Cannot combine 'all' with other install components"
        exit 1
    fi

    if [[ $INSTALL_ALL -eq 1 ]]; then
        SELECTED_COMPONENTS=()
        INSTALL_ALL=0
    fi

    for selected_component in ${SELECTED_COMPONENTS[@]+"${SELECTED_COMPONENTS[@]}"}; do
        if [[ "$selected_component" == "$component" ]]; then
            return 0
        fi
    done

    SELECTED_COMPONENTS+=("$component")
}

add_skipped_component() {
    local component
    local skipped_component

    if [[ $INSTALL_ALL -eq 0 || $ONLY_ALL_REQUESTED -eq 1 ]]; then
        echo "Cannot combine --skip with --only"
        exit 1
    fi

    component="$(normalize_install_component "$1")"
    if [[ -z "$component" ]] || ! is_valid_install_component "$component" \
        || [[ "$component" == "all" ]]; then
        echo "Unknown skip component: $1"
        echo "Valid components to skip: home, xdg, bin, ai, ai-skills, ai-rules, serena"
        exit 1
    fi

    for skipped_component in ${SKIPPED_COMPONENTS[@]+"${SKIPPED_COMPONENTS[@]}"}; do
        if [[ "$skipped_component" == "$component" ]]; then
            return 0
        fi
    done

    SKIPPED_COMPONENTS+=("$component")
    SKIP_COMPONENTS_REQUESTED=1
}

add_install_components() {
    local raw_components="$1"
    local component
    local -a components=()

    if [[ -z "$raw_components" ]]; then
        echo "Missing install component after --only"
        exit 1
    fi

    IFS=',' read -r -a components <<< "$raw_components"
    for component in ${components[@]+"${components[@]}"}; do
        component="${component//[[:space:]]/}"
        add_install_component "$component"
    done
}

add_skipped_components() {
    local raw_components="$1"
    local component
    local -a components=()

    if [[ -z "$raw_components" ]]; then
        echo "Missing skip component after --skip"
        exit 1
    fi

    IFS=',' read -r -a components <<< "$raw_components"
    for component in ${components[@]+"${components[@]}"}; do
        component="${component//[[:space:]]/}"
        add_skipped_component "$component"
    done
}

component_is_skipped() {
    local component="$1"
    local skipped_component

    for skipped_component in ${SKIPPED_COMPONENTS[@]+"${SKIPPED_COMPONENTS[@]}"}; do
        if [[ "$skipped_component" == "$component" ]]; then
            return 0
        fi
    done

    # AI skills require the AI configuration snapshot, so skipping AI also
    # skips its skills even when ai-skills was not named explicitly.
    if [[ "$component" == "ai-skills" ]]; then
        for skipped_component in ${SKIPPED_COMPONENTS[@]+"${SKIPPED_COMPONENTS[@]}"}; do
            if [[ "$skipped_component" == "ai" ]]; then
                return 0
            fi
        done
    fi

    return 1
}

component_is_selected() {
    local component="$1"
    local selected_component

    if [[ $INSTALL_ALL -eq 1 ]]; then
        if component_is_skipped "$component"; then
            return 1
        fi
        return 0
    fi

    for selected_component in ${SELECTED_COMPONENTS[@]+"${SELECTED_COMPONENTS[@]}"}; do
        if [[ "$selected_component" == "$component" ]]; then
            return 0
        fi
    done

    return 1
}

selected_components_label() {
    local IFS=','

    if [[ $INSTALL_ALL -eq 1 ]]; then
        printf '%s\n' "all"
    else
        printf '%s\n' "${SELECTED_COMPONENTS[*]}"
    fi
}

skipped_components_label() {
    local IFS=','

    printf '%s\n' "${SKIPPED_COMPONENTS[*]}"
}

# Preserve --only xdg's historical behavior of including ai-agent config.
# In a full install, however, --skip ai must omit that config too.
should_install_ai_agent_config() {
    if [[ $INSTALL_ALL -eq 0 ]]; then
        return 0
    fi

    component_is_selected "ai"
}

should_install_ai_skills() {
    component_is_selected "ai-skills"
}

parse_args() {
    INSTALL_ALL=1
    ONLY_ALL_REQUESTED=0
    SELECTED_COMPONENTS=()
    SKIPPED_COMPONENTS=()
    SKIP_COMPONENTS_REQUESTED=0
    REQUIRED_SUBMODULE_PATHS=()

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
            --only)
                if [[ $# -lt 2 ]]; then
                    echo "Missing install component after --only"
                    exit 1
                fi
                add_install_components "$2"
                shift 2
                ;;
            --only=*)
                add_install_components "${1#--only=}"
                shift
                ;;
            --skip)
                if [[ $# -lt 2 ]]; then
                    echo "Missing skip component after --skip"
                    exit 1
                fi
                add_skipped_components "$2"
                shift 2
                ;;
            --skip=*)
                add_skipped_components "${1#--skip=}"
                shift
                ;;
            --ai-skills)
                add_install_component "ai-skills"
                shift
                ;;
            --ai-rules|--agent-rules|--waypost-rules)
                add_install_component "ai-rules"
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
  --only PARTS      Install only selected comma-separated sections (repeatable)
                    Sections: home, xdg, bin, ai, ai-skills, ai-rules, serena, all
  --skip PARTS      Skip selected comma-separated sections (repeatable)
                    Sections: home, xdg, bin, ai, ai-skills, ai-rules, serena
  --ai-skills       Alias for --only ai-skills
  --ai-rules        Alias for --only ai-rules
  --no-color        Disable colored output
  --help, -h        Show this help message

Partial selections skip unrelated tool/CLI bootstrap, OS setup, and Neovim
checks. "home" and "xdg" initialize their required Git submodules first and
continue if that fails, skipping only their submodule-backed configs. "ai"
installs $XDG_CONFIG_HOME/ai-agent (or $HOME/.config/ai-agent) plus AI skills;
"ai-skills" only updates the shared AI snapshot and per-agent skill links.
"ai-rules" updates installer-managed authorization rules for Codex, Claude
Code, Gemini CLI, and Antigravity without registering MCP servers or installing
skills.
--skip keeps the full-install bootstrap but omits the named sections; it
cannot be combined with --only. Skipping "ai" also skips "ai-skills".

Examples:
  ./install.sh                  # Standard installation
  ./install.sh --dry-run        # Preview changes
  ./install.sh --force          # Replace existing configs (backs them up)
  ./install.sh --interactive    # Prompt for each conflict
  ./install.sh --only home,xdg  # Install selected config sections
  ./install.sh --skip xdg,serena # Full install except selected sections
  ./install.sh --ai-skills      # Install/update AI skills only
  ./install.sh --ai-rules       # Install global AI authorization rules only
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

run_best_effort() {
    local label="$1"
    shift
    local failed_before=$failed
    local status=0

    "$@" || status=$?
    if [[ $status -eq 0 && $failed -eq $failed_before ]]; then
        return 0
    fi

    if [[ $failed -eq $failed_before ]]; then
        failed=$((failed + 1))
    fi
    log_warn "$label failed; continuing"
    return 1
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
    log_info "Ensure future shells include this directory if installed commands are not found"
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
    for component in ${components[@]+"${components[@]}"}; do
        case "$component" in
            ''|.)
                ;;
            ..)
                if [[ -n "${normalized_parts[0]+set}" ]]; then
                    last_index=$((${#normalized_parts[@]} - 1))
                    unset "normalized_parts[$last_index]"
                fi
                ;;
            *)
                normalized_parts+=("$component")
                ;;
        esac
    done

    for component in ${normalized_parts[@]+"${normalized_parts[@]}"}; do
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

merge_managed_file_mode() {
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

merge_managed_regular_file() {
    local base="$1"
    local live="$2"
    local staged="$3"
    local display_path="$4"
    local merged=""
    local staged_mode

    if cmp -s "$base" "$live" || cmp -s "$live" "$staged"; then
        :
    elif cmp -s "$base" "$staged"; then
        staged_mode="$(path_mode "$staged")" || return 1
        cp "$live" "$staged" || return 1
        chmod "$staged_mode" "$staged" || return 1
    elif command -v git &>/dev/null; then
        merged="$(mktemp "${TMPDIR:-/tmp}/config-files-merge.XXXXXX")" || {
            log_error "Failed to create temporary merge file: $display_path"
            return 1
        }
        if ! git merge-file -p "$staged" "$base" "$live" > "$merged"; then
            rm -f "$merged"
            managed_copy_conflict "$display_path" || return 1
            merge_managed_file_mode "$base" "$live" "$staged" "$display_path"
            return $?
        fi
        staged_mode="$(path_mode "$staged")" || {
            rm -f "$merged"
            return 1
        }
        if ! cp "$merged" "$staged" || ! chmod "$staged_mode" "$staged"; then
            rm -f "$merged"
            log_error "Failed to stage merged file: $display_path"
            return 1
        fi
        rm -f "$merged"
        log_info "Merged local and repository changes: $display_path"
    else
        managed_copy_conflict "$display_path" || return 1
    fi

    merge_managed_file_mode "$base" "$live" "$staged" "$display_path"
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
        return 0
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

    if [[ -f "$base" && ! -L "$base" \
        && -f "$live" && ! -L "$live" \
        && -f "$staged" && ! -L "$staged" ]]; then
        merge_managed_regular_file "$base" "$live" "$staged" "$display_path"
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

dry_run_regular_file_merge_is_clean() {
    local base="$1"
    local live="$2"
    local upstream="$3"

    if ! cmp -s "$base" "$live" \
        && ! cmp -s "$live" "$upstream" \
        && ! cmp -s "$base" "$upstream"; then
        if ! command -v git &>/dev/null \
            || ! git merge-file -p "$upstream" "$base" "$live" >/dev/null; then
            return 1
        fi
    fi

    if path_mode_matches "$base" "$live" \
        || path_mode_matches "$base" "$upstream" \
        || path_mode_matches "$live" "$upstream"; then
        return 0
    fi

    return 1
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

    if [[ -f "$base" && ! -L "$base" \
        && -f "$live" && ! -L "$live" \
        && -f "$upstream" && ! -L "$upstream" ]]; then
        if ! dry_run_regular_file_merge_is_clean "$base" "$live" "$upstream"; then
            managed_copy_conflict "$display_path" || return 1
        fi
        DRY_RUN_MERGE_ITEM_EXISTS=1
        mark_dry_run_merge_change
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
        || symlink_points_to_any "$dst" ${legacy_sources[@]+"${legacy_sources[@]}"}; then
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

    SHARED_AI_AGENT_READY=0
    log_info "Installing shared agent assets..."
    freeze_legacy_ai_rule_links || return 1
    if ! install_copy "ai-agent" "$dst"; then
        return 1
    fi

    SHARED_AI_AGENT_READY=1
    return 0
}

# Legacy installers linked authorization policy directly into the mutable
# shared AI snapshot. Freeze only those exact links before refreshing that
# snapshot, so selecting ai/ai-skills cannot silently change authorizations.
# The frozen copy is adopted into normal managed-copy state and is later
# updated only by the ai-rules component.
freeze_legacy_ai_rule_link() {
    local rule_file="$1"
    local tmp_file

    shift
    [[ -L "$rule_file" ]] || return 0
    symlink_points_to_any "$rule_file" "$@" || return 0

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ -f "$rule_file" ]]; then
            log_dry "Would freeze legacy AI authorization link: $rule_file"
        else
            log_dry "Would remove dangling legacy AI authorization link: $rule_file"
        fi
        return 0
    fi

    # A dangling installer-owned link has no active policy to preserve. Remove
    # the link before its target is recreated by the incoming shared snapshot.
    if [[ ! -f "$rule_file" ]]; then
        rm -f "$rule_file" || {
            log_error "Failed to remove dangling legacy AI authorization link: $rule_file"
            return 1
        }
        log_info "Removed dangling legacy AI authorization link: $rule_file"
        return 0
    fi

    tmp_file="$(mktemp "$(dirname "$rule_file")/.ai-rules-freeze.XXXXXX")" || {
        log_error "Failed to stage legacy AI authorization policy: $rule_file"
        return 1
    }
    if ! cp -pL "$rule_file" "$tmp_file" || ! mv "$tmp_file" "$rule_file"; then
        rm -f "$tmp_file"
        log_error "Failed to freeze legacy AI authorization link: $rule_file"
        return 1
    fi

    # Preserve the exact active bytes as the merge base. This avoids treating
    # a frozen legacy policy as user-owned on the next ai-rules update.
    if ! record_managed_copy_snapshot "$rule_file" "$rule_file" \
        || ! record_managed_path "$rule_file"; then
        log_error "Failed to adopt frozen AI authorization policy: $rule_file"
        return 1
    fi

    log_info "Froze legacy AI authorization link: $rule_file"
    return 0
}

freeze_legacy_ai_rule_links() {
    local legacy_gemini_preserved_policy

    legacy_gemini_preserved_policy="$SHARED_INSTALL_ROOT/ai-rules-preserved/gemini/policies/agent-deck-workflow.toml"

    freeze_legacy_ai_rule_link \
        "$HOME/.codex/rules/agent-deck-workflow.rules" \
        "$SHARED_AI_AGENT_DIR/codex/rules/agent-deck-workflow.rules" \
        "$SHARED_AI_AGENT_DIR/.codex/rules/agent-deck-workflow.rules" \
        "$SCRIPT_DIR/ai-agent/codex/rules/agent-deck-workflow.rules" \
        "$SCRIPT_DIR/ai-agent/.codex/rules/agent-deck-workflow.rules" || return 1
    freeze_legacy_ai_rule_link \
        "$HOME/.gemini/policies/agent-deck-workflow.toml" \
        "$SHARED_AI_AGENT_DIR/gemini/policies/agent-deck-workflow.toml" \
        "$SHARED_AI_AGENT_DIR/.gemini/policies/agent-deck-workflow.toml" \
        "$SCRIPT_DIR/ai-agent/gemini/policies/agent-deck-workflow.toml" \
        "$SCRIPT_DIR/ai-agent/.gemini/policies/agent-deck-workflow.toml" \
        "$legacy_gemini_preserved_policy"
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

            if symlink_points_to_any "$dst" ${legacy_sources[@]+"${legacy_sources[@]}"}; then
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

package_is_installed() {
    local package_name="$1"
    local package_status

    case "$PACKAGE_MANAGER" in
        apt-get)
            command -v dpkg-query &>/dev/null || return 1
            package_status="$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null)" || return 1
            [[ "$package_status" == "install ok installed" ]]
            ;;
        brew)
            brew list --formula "$package_name" >/dev/null 2>&1 \
                || brew list --cask "$package_name" >/dev/null 2>&1
            ;;
        dnf|zypper)
            command -v rpm &>/dev/null && rpm -q "$package_name" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Q "$package_name" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

install_package() {
    local package_name="$1"
    local -a install_cmd=()

    if package_is_installed "$package_name"; then
        log_ok "Found package: $package_name"
        if [[ $DRY_RUN -eq 1 ]]; then
            log_error "Required command or library is unavailable, and no package change would be made: $package_name"
            return 1
        fi
        return 0
    fi

    case "$PACKAGE_MANAGER" in
        apt-get)
            install_cmd=(sudo apt-get install -y "$package_name")
            ;;
        brew)
            install_cmd=(env HOMEBREW_NO_AUTO_UPDATE=1 brew install "$package_name")
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

node_npm_are_usable() {
    command -v node &>/dev/null \
        && node --version >/dev/null 2>&1 \
        && command -v npm &>/dev/null \
        && npm --version >/dev/null 2>&1
}

npm_is_available_or_planned() {
    node_npm_are_usable \
        || [[ $DRY_RUN -eq 1 && $NODE_NPM_AVAILABLE -eq 1 ]]
}

ensure_required_command() {
    local command_name="$1"

    if [[ "$command_name" == "npm" ]]; then
        if npm_is_available_or_planned; then
            if command -v npm &>/dev/null; then
                log_ok "Found required command: npm"
            else
                log_dry "Would use required command from NVM: npm"
            fi
            return 0
        fi

        log_error "npm is unavailable; leaving the existing Node.js setup unchanged"
        return 1
    fi

    local package_name="${2:-$(package_name_for_command "$command_name")}"

    if command -v "$command_name" &>/dev/null; then
        log_ok "Found required command: $command_name"
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
        fzf
        git
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
        run_best_effort "Required command: $tool_name" \
            ensure_required_command "$tool_name"
    done

    return 0
}

fd_is_runnable() {
    command -v fd &>/dev/null && fd --version >/dev/null 2>&1
}

install_fd_alias() {
    local fdfind_path
    local target="$HOME/.local/bin/fd"

    fdfind_path="$(command -v fdfind)" || return 1
    if [[ -e "$target" || -L "$target" ]]; then
        if symlink_points_to "$target" "$fdfind_path"; then
            log_ok "Found fd compatibility link"
            return 0
        fi
        log_error "fd install target already exists: $target"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would link: $target -> $fdfind_path"
        return 0
    fi

    mkdir -p "$(dirname "$target")" || return 1
    if ! ln -s "$fdfind_path" "$target"; then
        log_error "Failed to create fd compatibility link: $target"
        return 1
    fi
    hash -r

    if fd_is_runnable; then
        log_ok "Installed fd compatibility link"
        return 0
    fi

    log_error "fd is unavailable after linking: $target"
    return 1
}

install_fd() {
    local package_name="fd"

    log_info "Checking fd..."

    if command -v fd &>/dev/null; then
        if fd_is_runnable; then
            log_ok "Found fd"
            return 0
        fi
        log_error "Found fd but it is not runnable; refusing to replace it"
        return 1
    fi
    if command -v fdfind &>/dev/null; then
        if fdfind --version >/dev/null 2>&1; then
            install_fd_alias
            return $?
        fi
        log_error "Found fdfind but it is not runnable; refusing to replace it"
        return 1
    fi

    case "$PACKAGE_MANAGER" in
        apt-get|dnf)
            package_name="fd-find"
            ;;
    esac
    if ! install_package "$package_name"; then
        log_error "Please install '$package_name' manually and rerun the installer"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ "$PACKAGE_MANAGER" == "apt-get" ]]; then
            log_dry "Would create the fd compatibility link for fdfind"
        fi
        return 0
    fi

    hash -r
    if fd_is_runnable; then
        log_ok "Installed fd"
        return 0
    fi
    if command -v fdfind &>/dev/null && fdfind --version >/dev/null 2>&1; then
        install_fd_alias
        return $?
    fi

    log_error "fd is unavailable after package install: $package_name"
    return 1
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

lazygit_asset_suffix() {
    local architecture

    architecture="$(uname -m)"
    case "$OS:$architecture" in
        linux:x86_64|linux:amd64|wsl:x86_64|wsl:amd64)
            printf '%s\n' "Linux_x86_64"
            ;;
        linux:aarch64|linux:arm64|wsl:aarch64|wsl:arm64)
            printf '%s\n' "Linux_arm64"
            ;;
        macos:x86_64|macos:amd64)
            printf '%s\n' "Darwin_x86_64"
            ;;
        macos:aarch64|macos:arm64)
            printf '%s\n' "Darwin_arm64"
            ;;
        *)
            return 1
            ;;
    esac
}

cleanup_lazygit_temp() {
    local tmp_dir="$1"

    rm -f \
        "$tmp_dir/release.json" \
        "$tmp_dir/lazygit.tar.gz" \
        "$tmp_dir/lazygit"
    rmdir "$tmp_dir" 2>/dev/null || true
}

install_lazygit() {
    local asset_suffix
    local release_tag
    local version
    local archive_name
    local asset_info
    local download_url
    local asset_digest
    local expected_sha256
    local actual_sha256
    local local_bin="$HOME/.local/bin"
    local target="$local_bin/lazygit"
    local tmp_dir
    local release_json
    local archive

    log_info "Checking lazygit..."

    if command -v lazygit &>/dev/null; then
        log_ok "Found lazygit"
        return 0
    fi

    if [[ "$PACKAGE_MANAGER" == "brew" ]]; then
        if ! install_package "lazygit"; then
            return 1
        fi
        if [[ $DRY_RUN -eq 1 ]]; then
            return 0
        fi

        hash -r
        if command -v lazygit &>/dev/null; then
            log_ok "Installed lazygit with Homebrew"
            return 0
        fi

        log_error "lazygit is unavailable after Homebrew install"
        return 1
    fi

    if ! asset_suffix="$(lazygit_asset_suffix)"; then
        log_warn "lazygit automatic install is unavailable on: $OS/$(uname -m)"
        log_info "Install lazygit manually to enable the configured Neovim shortcut"
        return 0
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        log_error "lazygit install target already exists but is not runnable: $target"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would query the latest lazygit release: $LAZYGIT_RELEASE_API_URL"
        log_dry "Would download and verify the latest lazygit $asset_suffix archive"
        log_dry "Would install: $target"
        return 0
    fi

    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/lazygit-install.XXXXXX")" || {
        log_error "Failed to create temporary lazygit directory"
        return 1
    }
    release_json="$tmp_dir/release.json"
    archive="$tmp_dir/lazygit.tar.gz"

    if ! curl -fsSL "$LAZYGIT_RELEASE_API_URL" -o "$release_json"; then
        cleanup_lazygit_temp "$tmp_dir"
        log_error "Failed to query the latest lazygit release"
        return 1
    fi

    release_tag="$(jq -er '.tag_name | strings | select(length > 0)' "$release_json")" || {
        cleanup_lazygit_temp "$tmp_dir"
        log_error "Failed to read the latest lazygit version"
        return 1
    }
    version="${release_tag#v}"
    archive_name="lazygit_${version}_${asset_suffix}.tar.gz"
    asset_info="$(
        jq -er --arg name "$archive_name" \
            '.assets[] | select((.name | ascii_downcase) == ($name | ascii_downcase)) | [.browser_download_url, .digest] | @tsv' \
            "$release_json"
    )" || {
        cleanup_lazygit_temp "$tmp_dir"
        log_error "No lazygit release asset found for: $asset_suffix"
        return 1
    }
    IFS=$'\t' read -r download_url asset_digest <<< "$asset_info"
    expected_sha256="${asset_digest#sha256:}"
    if [[ ! "$expected_sha256" =~ ^[[:xdigit:]]{64}$ ]]; then
        cleanup_lazygit_temp "$tmp_dir"
        log_error "No valid SHA-256 digest found for: $archive_name"
        return 1
    fi

    if ! curl -fsSL "$download_url" -o "$archive"; then
        cleanup_lazygit_temp "$tmp_dir"
        log_error "Failed to download lazygit $release_tag"
        return 1
    fi

    actual_sha256="$(sha256_file "$archive")" || {
        cleanup_lazygit_temp "$tmp_dir"
        log_error "No SHA-256 tool available for lazygit verification"
        return 1
    }
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        cleanup_lazygit_temp "$tmp_dir"
        log_error "lazygit archive SHA-256 mismatch"
        return 1
    fi

    if ! tar -xzf "$archive" -C "$tmp_dir" lazygit; then
        cleanup_lazygit_temp "$tmp_dir"
        log_error "Failed to extract lazygit $release_tag"
        return 1
    fi
    if ! mkdir -p "$local_bin" || ! install -m 0755 "$tmp_dir/lazygit" "$target"; then
        cleanup_lazygit_temp "$tmp_dir"
        log_error "Failed to install lazygit to: $target"
        return 1
    fi
    cleanup_lazygit_temp "$tmp_dir"
    hash -r

    if "$target" --version >/dev/null 2>&1; then
        log_ok "Installed lazygit $release_tag"
        return 0
    fi

    rm -f "$target"
    hash -r
    log_error "lazygit is unavailable after install: $target"
    return 1
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

    if command -v mq &>/dev/null; then
        if mq_is_runnable; then
            log_ok "Found mq"
            return 0
        fi
        log_error "Found mq but it is not runnable; refusing to replace it: $(command -v mq)"
        return 1
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

warn_if_existing_nvm_needs_bash_setup() {
    local profile="$HOME/.bashrc"

    if [[ ! -e "$profile" && ! -L "$profile" ]]; then
        return 0
    fi
    if bash_profile_loads_nvm "$profile"; then
        return 0
    fi

    log_warn "Existing NVM is not initialized by Bash profile: $profile"
    log_info "Add NVM initialization manually if future Bash shells cannot find Node.js"
    return 0
}

set_nvm_default_version() {
    local version="$1"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: nvm alias default $version"
        return 0
    fi

    if nvm alias default "$version" >/dev/null; then
        log_ok "Set the existing Node.js version as NVM default: $version"
        return 0
    fi

    log_error "Failed to persist the NVM default version: $version"
    return 1
}

ensure_nvm_default_version() {
    local version="$1"
    local default_version

    default_version="$(nvm version default 2>/dev/null || true)"
    if [[ -n "$default_version" && "$default_version" != "N/A" ]]; then
        return 0
    fi

    set_nvm_default_version "$version"
}

install_nodejs_with_nvm() {
    local nvm_dir="$HOME/.nvm"
    local nvm_script="$nvm_dir/nvm.sh"
    local ambient_node_or_npm_present=0
    local current_node_path
    local current_nvm_version
    local existing_node_version
    local installed_node_dir
    local found_existing_nvm_node=0
    local nvm_profile_is_installer_owned=0
    local tmp_file

    log_info "Checking Node.js via NVM..."

    if command -v node &>/dev/null || command -v npm &>/dev/null; then
        ambient_node_or_npm_present=1
        if node_npm_are_usable; then
            current_node_path="$(command -v node)"
            if [[ "$current_node_path" == "$nvm_dir"/versions/node/* && -s "$nvm_script" ]]; then
                # shellcheck source=/dev/null
                source "$nvm_script"
                current_nvm_version="$(nvm current 2>/dev/null || true)"
                if [[ -n "$current_nvm_version" \
                    && "$current_nvm_version" != "none" \
                    && "$current_nvm_version" != "system" \
                    && "$current_nvm_version" != "N/A" ]]; then
                    ensure_nvm_default_version "$current_nvm_version" || return 1
                fi
                warn_if_existing_nvm_needs_bash_setup
            fi
            NODE_NPM_AVAILABLE=1
            log_ok "Found Node.js and npm; leaving the existing installation unchanged"
            return 0
        fi

        if [[ ! -s "$nvm_script" ]]; then
            log_error "Existing Node.js/npm setup is incomplete or unusable; refusing to replace it"
            return 1
        fi

        log_warn "Existing Node.js/npm setup is incomplete or unusable; checking existing NVM versions"
    fi

    if [[ -s "$nvm_script" ]]; then
        log_ok "Found NVM"
    else
        nvm_profile_is_installer_owned=1
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

    if [[ $nvm_profile_is_installer_owned -eq 1 ]]; then
        ensure_nvm_bash_profile || return 1
    else
        warn_if_existing_nvm_needs_bash_setup
    fi

    if [[ ! -s "$nvm_script" ]]; then
        log_dry "Would run: nvm install --lts"
        log_dry "Would run: nvm alias default lts/*"
        log_dry "Would run: nvm use default"
        NODE_NPM_AVAILABLE=1
        return 0
    fi

    # shellcheck source=/dev/null
    source "$nvm_script"

    if ! command -v nvm &>/dev/null; then
        log_error "NVM is unavailable after loading: $nvm_script"
        return 1
    fi

    if nvm use default >/dev/null 2>&1 && node_npm_are_usable; then
        NODE_NPM_AVAILABLE=1
        log_ok "Found the existing default Node.js version through NVM"
        return 0
    fi

    existing_node_version="$(nvm version node 2>/dev/null || true)"
    if [[ -n "$existing_node_version" && "$existing_node_version" != "N/A" ]]; then
        if ! nvm use "$existing_node_version" >/dev/null 2>&1 \
            || ! node_npm_are_usable; then
            log_error "Existing NVM Node.js version is incomplete: $existing_node_version"
            return 1
        fi

        set_nvm_default_version "$existing_node_version" || return 1
        NODE_NPM_AVAILABLE=1
        log_ok "Activated the existing NVM Node.js version: $existing_node_version"
        return 0
    fi

    for installed_node_dir in "$nvm_dir"/versions/node/*; do
        [[ -d "$installed_node_dir" ]] || continue
        if [[ -x "$installed_node_dir/bin/node" ]]; then
            found_existing_nvm_node=1
        fi
    done

    if [[ $found_existing_nvm_node -eq 1 ]]; then
        log_error "Existing NVM Node.js versions could not be activated; refusing to replace them"
        return 1
    fi

    if [[ $ambient_node_or_npm_present -eq 1 ]]; then
        log_error "Existing Node.js/npm setup is incomplete, and NVM has no usable installed version; refusing to replace it"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: nvm install --lts"
        log_dry "Would run: nvm alias default lts/*"
        log_dry "Would run: nvm use default"
        NODE_NPM_AVAILABLE=1
        return 0
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

    if node_npm_are_usable; then
        NODE_NPM_AVAILABLE=1
        log_ok "Node.js and npm are available through NVM"
        return 0
    fi

    log_error "Node.js or npm is unavailable after NVM setup"
    return 1
}

npm_global_run() {
    local action="$1"
    shift
    local prefix="$HOME/.local"
    local -a npm_cmd=(npm "$action" -g --prefix "$prefix" "$@")

    ensure_path_contains_local_bin

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${npm_cmd[*]}"
        return 0
    fi

    if ! mkdir -p "$prefix" || [[ ! -d "$prefix" || ! -w "$prefix" ]]; then
        log_error "npm global install prefix is not writable: $prefix"
        return 1
    fi

    log_info "Running: ${npm_cmd[*]}"
    "${npm_cmd[@]}"
}

install_codex_cli() {
    log_info "Checking Codex CLI..."

    if command -v codex &>/dev/null; then
        log_ok "Found Codex CLI"
        return 0
    fi

    if ! npm_is_available_or_planned; then
        log_error "Codex CLI requires npm"
        return 1
    fi

    if ! npm_global_run install @openai/codex; then
        log_error "Failed to install Codex CLI"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
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
        if [[ -n "${installer_args[0]+set}" ]]; then
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

    if ! bash "$tmp_file" ${installer_args[@]+"${installer_args[@]}"}; then
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

install_uv() {
    UV_UNMANAGED_INSTALL="$HOME/.local/bin" \
        install_remote_cli "uv" "uv" "$UV_INSTALL_URL" ""
}

install_bun() {
    log_info "Checking Bun..."

    if command -v bun &>/dev/null; then
        log_ok "Found Bun"
        return 0
    fi

    if ! ensure_required_command "npm"; then
        log_error "Bun requires npm"
        return 1
    fi

    if ! npm_global_run install bun; then
        log_error "Failed to install Bun with npm"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi
    hash -r

    if command -v bun &>/dev/null; then
        log_ok "Installed Bun"
        return 0
    fi

    log_error "Bun is unavailable after npm install"
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

    if [[ -e "$install_dir" || -L "$install_dir" ]]; then
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
        if [[ -e "$install_dir" || -L "$install_dir" ]]; then
            remove_installed_path "$install_dir"
            log_info "Removed incomplete Oh My Zsh install: $install_dir"
        fi
        log_error "Failed to install Oh My Zsh"
        return 1
    fi

    if [[ -f "$entrypoint" ]]; then
        log_ok "Installed Oh My Zsh"
        return 0
    fi

    remove_installed_path "$install_dir"
    log_info "Removed incomplete Oh My Zsh install: $install_dir"
    log_error "Oh My Zsh is incomplete after install"
    return 1
}

install_zsh_checkout() {
    local display_name="$1"
    local repo_url="$2"
    local target="$3"
    local marker="$4"
    local -a clone_cmd=(git clone --depth=1 "$repo_url" "$target")

    if [[ -f "$marker" ]]; then
        log_ok "Found $display_name"
        return 0
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        log_error "$display_name directory exists but is incomplete: $target"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: ${clone_cmd[*]}"
        return 0
    fi

    mkdir -p "$(dirname "$target")" || return 1
    log_info "Running: ${clone_cmd[*]}"
    if ! "${clone_cmd[@]}" || [[ ! -f "$marker" ]]; then
        if [[ -e "$target" || -L "$target" ]]; then
            remove_installed_path "$target"
            log_info "Removed incomplete $display_name install: $target"
        fi
        log_error "Failed to install $display_name"
        return 1
    fi

    log_ok "Installed $display_name"
}

install_zsh_dependencies() {
    local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    local spaceship_dir="$custom_dir/themes/spaceship-prompt"
    local spaceship_theme="$spaceship_dir/spaceship.zsh-theme"
    local theme_link="$custom_dir/themes/spaceship.zsh-theme"

    log_info "Checking Zsh theme and plugins..."

    ensure_required_command "fzf" || return 1
    install_zsh_checkout \
        "Spaceship prompt" "$SPACESHIP_PROMPT_REPO" \
        "$spaceship_dir" "$spaceship_theme" || return 1
    install_zsh_checkout \
        "spaceship-vi-mode" "$SPACESHIP_VI_MODE_REPO" \
        "$custom_dir/plugins/spaceship-vi-mode" \
        "$custom_dir/plugins/spaceship-vi-mode/spaceship-vi-mode.plugin.zsh" || return 1
    install_zsh_checkout \
        "zsh-autocomplete" "$ZSH_AUTOCOMPLETE_REPO" \
        "$custom_dir/plugins/zsh-autocomplete" \
        "$custom_dir/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" || return 1

    if symlink_points_to "$theme_link" "$spaceship_theme"; then
        log_ok "Found Spaceship theme link"
        return 0
    fi
    if [[ -e "$theme_link" || -L "$theme_link" ]]; then
        log_error "Spaceship theme target already exists: $theme_link"
        return 1
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would link: $theme_link -> $spaceship_theme"
        return 0
    fi

    if ln -s "$spaceship_theme" "$theme_link"; then
        log_ok "Linked Spaceship theme"
        return 0
    fi

    log_error "Failed to link Spaceship theme: $theme_link"
    return 1
}

install_zsh_stack() {
    ZSH_STACK_READY=0

    if ! run_best_effort "Oh My Zsh" install_oh_my_zsh; then
        log_warn "Skipping Zsh dependencies; Oh My Zsh is unavailable"
        return 0
    fi

    if run_best_effort "Zsh dependencies" install_zsh_dependencies; then
        ZSH_STACK_READY=1
    fi
    return 0
}

install_agent_browser() {
    log_info "Checking agent-browser..."

    if command -v agent-browser &>/dev/null; then
        log_ok "Found agent-browser; leaving the existing installation unchanged"
        return 0
    fi

    if ! ensure_required_command "npm"; then
        log_error "agent-browser requires npm"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        npm_global_run install agent-browser || return 1
        log_dry "Would run: agent-browser install"
        return 0
    fi

    if ! npm_global_run install agent-browser; then
        log_error "Failed to install agent-browser with npm"
        return 1
    fi
    hash -r

    if ! command -v agent-browser &>/dev/null; then
        log_error "agent-browser is unavailable after npm install"
        return 1
    fi
    log_ok "Installed agent-browser"

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

    if command -v ast-grep &>/dev/null; then
        log_ok "Found ast-grep"
        return 0
    fi

    if ! ensure_required_command "npm"; then
        log_error "ast-grep requires npm"
        return 1
    fi

    if ! npm_global_run install @ast-grep/cli; then
        log_error "Failed to install ast-grep with npm"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
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
    local shared_skills_dir="$SHARED_AGENT_SKILLS_DIR"
    local shared_skill_file="$shared_skills_dir/ast-grep/SKILL.md"
    local -a skill_cmd=(
        npx --yes skills add https://github.com/ast-grep/agent-skill
        --global --agent codex --yes
    )

    log_info "Checking ast-grep skill..."

    if [[ $CODEX_SKILLS_DIR_READY -ne 1 ]]; then
        log_warn "Skipping ast-grep skill install; Codex skills directory was not prepared"
        return 0
    fi

    if [[ -f "$shared_skill_file" ]]; then
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

    if [[ -f "$shared_skill_file" ]]; then
        log_ok "Installed ast-grep skill"
        return 0
    fi

    log_error "Skill still unavailable after install: ast-grep"
    return 1
}

tree_sitter_cli_version() {
    local tree_sitter_command="${1:-tree-sitter}"
    local version_output

    version_output="$("$tree_sitter_command" --version 2>/dev/null)" || return 1
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
    local cargo_command_present=0
    local tmp_file

    log_info "Checking Rust/Cargo..."
    RUST_CARGO_PLANNED=0
    load_cargo_environment

    if command -v cargo &>/dev/null; then
        cargo_command_present=1
        if cargo --version >/dev/null 2>&1; then
            log_ok "Found Cargo; leaving the existing toolchain unchanged"
            return 0
        fi
        log_warn "Found Cargo but it is not directly runnable; checking rustup"
    fi

    if command -v rustup &>/dev/null; then
        if ! rustup --version >/dev/null 2>&1; then
            log_error "Found rustup but it is not runnable; refusing to replace it"
            return 1
        fi

        if rustup run stable cargo --version >/dev/null 2>&1; then
            log_ok "Found the existing Rust stable toolchain"
            return 0
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            RUST_CARGO_PLANNED=1
            log_dry "Would install the missing Rust stable toolchain"
            return 0
        fi

        log_info "Installing missing Rust stable toolchain..."
        if ! rustup toolchain install stable --profile minimal; then
            log_error "Failed to install the Rust stable toolchain"
            return 1
        fi

        if rustup run stable cargo --version >/dev/null 2>&1; then
            log_ok "Installed the missing Rust stable toolchain"
            return 0
        fi

        log_error "Cargo is unavailable from the Rust stable toolchain"
        return 1
    fi

    if [[ $cargo_command_present -eq 1 ]]; then
        log_error "Found Cargo but it is not runnable and no usable rustup toolchain is available"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        RUST_CARGO_PLANNED=1
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

    if command -v cargo &>/dev/null && cargo --version >/dev/null 2>&1; then
        log_ok "Installed Rust/Cargo"
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
    local cargo_root
    local cargo_candidate
    local cargo_label
    local current_version=""
    local direct_cargo_version=""
    local install_target="$HOME/.local/bin/tree-sitter"
    local stable_cargo_version=""
    local staged_target
    local build_succeeded=0
    local -a cargo_candidates=()
    local -a cargo_cmd=()
    local -a install_cmd=()

    if ! ensure_rust_cargo; then
        return 1
    fi

    if ! ensure_libclang; then
        return 1
    fi

    ensure_path_contains_local_bin

    if command -v cargo &>/dev/null \
        && direct_cargo_version="$(cargo --version 2>/dev/null)"; then
        cargo_candidates+=(direct)
    fi
    if command -v rustup &>/dev/null \
        && stable_cargo_version="$(rustup run stable cargo --version 2>/dev/null)"; then
        if [[ -z "$direct_cargo_version" || "$stable_cargo_version" != "$direct_cargo_version" ]]; then
            cargo_candidates+=(stable)
        fi
    elif [[ $DRY_RUN -eq 1 && $RUST_CARGO_PLANNED -eq 1 ]]; then
        cargo_candidates+=(stable)
    fi

    if [[ ${#cargo_candidates[@]} -eq 0 ]]; then
        log_error "Cargo is unavailable after Rust setup"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        cargo_candidate="${cargo_candidates[0]}"
        if [[ "$cargo_candidate" == "direct" ]]; then
            cargo_cmd=(cargo)
        else
            cargo_cmd=(rustup run stable cargo)
        fi
        cargo_root="${TMPDIR:-/tmp}/tree-sitter-cargo.XXXXXX"
        install_cmd=(
            "${cargo_cmd[@]}" install
            --root "$cargo_root"
            tree-sitter-cli
            --locked
        )
        log_dry "Would run: ${install_cmd[*]}"
        if [[ ${#cargo_candidates[@]} -gt 1 ]]; then
            log_dry "Would retry with the existing Rust stable Cargo if the first build fails"
        fi
        log_dry "Would install the verified tree-sitter CLI to: $install_target"
        return 0
    fi

    if [[ -e "$install_target" || -L "$install_target" ]]; then
        log_error "tree-sitter install target already exists; refusing to replace it: $install_target"
        return 1
    fi

    for cargo_candidate in "${cargo_candidates[@]}"; do
        if [[ "$cargo_candidate" == "direct" ]]; then
            cargo_cmd=(cargo)
            cargo_label="Cargo"
        else
            cargo_cmd=(rustup run stable cargo)
            cargo_label="Rust stable Cargo"
        fi

        cargo_root="$(mktemp -d "${TMPDIR:-/tmp}/tree-sitter-cargo.XXXXXX")" || {
            log_error "Failed to create a temporary tree-sitter build directory"
            return 1
        }
        staged_target="$cargo_root/bin/tree-sitter"
        install_cmd=(
            "${cargo_cmd[@]}" install
            --root "$cargo_root"
            tree-sitter-cli
            --locked
        )

        log_info "Building tree-sitter CLI with $cargo_label: ${install_cmd[*]}"
        if ! "${install_cmd[@]}"; then
            rm -rf "$cargo_root"
            log_warn "$cargo_label failed to build tree-sitter CLI"
            continue
        fi

        current_version=""
        if ! current_version="$(tree_sitter_cli_version "$staged_target")"; then
            rm -rf "$cargo_root"
            log_warn "$cargo_label produced an unusable tree-sitter CLI"
            continue
        fi
        if ! tree_sitter_version_is_supported "$current_version" "$required_version"; then
            rm -rf "$cargo_root"
            log_warn "$cargo_label built tree-sitter CLI $current_version; requires $required_version or newer"
            continue
        fi

        build_succeeded=1
        break
    done

    if [[ $build_succeeded -ne 1 ]]; then
        log_error "Failed to build a supported tree-sitter CLI with the available Cargo toolchains"
        return 1
    fi

    if [[ -e "$install_target" || -L "$install_target" ]]; then
        rm -rf "$cargo_root"
        log_error "tree-sitter install target appeared during the Cargo build; refusing to replace it: $install_target"
        return 1
    fi
    if ! mkdir -p "$(dirname "$install_target")" \
        || ! install -m 0755 "$staged_target" "$install_target"; then
        rm -f "$install_target"
        rm -rf "$cargo_root"
        log_error "Failed to install the verified tree-sitter CLI to: $install_target"
        return 1
    fi
    rm -rf "$cargo_root"
    hash -r

    if current_version="$(tree_sitter_cli_version "$install_target")" \
        && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Built supported tree-sitter CLI: $current_version"
        return 0
    fi

    rm -f "$install_target"
    hash -r

    log_error "tree-sitter CLI is unavailable after publishing the Cargo build"
    return 1
}

remove_tree_sitter_install_created_by_npm() {
    local target="$1"
    local package_dir="$HOME/.local/lib/node_modules/tree-sitter-cli"

    if ! npm_global_run uninstall tree-sitter-cli; then
        log_error "Failed to remove npm ownership of tree-sitter-cli"
        return 1
    fi

    if [[ -e "$package_dir" || -L "$package_dir" ]]; then
        log_error "npm package remains after uninstall: $package_dir"
        return 1
    fi

    if [[ ! -e "$target" && ! -L "$target" ]]; then
        hash -r
        log_info "Removed npm ownership of tree-sitter-cli"
        return 0
    fi
    if [[ -d "$target" && ! -L "$target" ]]; then
        log_error "npm created an unexpected tree-sitter directory: $target"
        return 1
    fi
    if rm -f "$target"; then
        hash -r
        log_info "Removed npm-owned tree-sitter-cli and its unusable launcher: $target"
        return 0
    fi

    log_error "Failed to remove the unusable tree-sitter launcher after npm uninstall: $target"
    return 1
}

install_tree_sitter_cli() {
    local required_version="0.26.1"
    local current_version=""
    local install_target="$HOME/.local/bin/tree-sitter"

    log_info "Checking tree-sitter CLI..."
    ensure_path_contains_local_bin

    if command -v tree-sitter &>/dev/null; then
        if current_version="$(tree_sitter_cli_version)"; then
            if tree_sitter_version_is_supported "$current_version" "$required_version"; then
                log_ok "Found supported tree-sitter CLI: $current_version"
                return 0
            fi
            log_error "Found tree-sitter CLI $current_version; requires $required_version or newer and will not be replaced"
            return 1
        else
            log_error "Found tree-sitter CLI but could not read its version; refusing to replace it"
            return 1
        fi
    fi

    if [[ -e "$install_target" || -L "$install_target" ]]; then
        log_error "tree-sitter install target already exists but is unavailable; refusing to replace it: $install_target"
        return 1
    fi

    if ! npm_is_available_or_planned; then
        log_warn "npm is unavailable; building tree-sitter CLI from source with Cargo"
        install_tree_sitter_cli_with_cargo "$required_version"
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        npm_global_run install --allow-scripts=tree-sitter-cli tree-sitter-cli || return 1
        log_dry "Would install Rust/Cargo and libclang, then build tree-sitter-cli from source if the npm binary is unusable"
        return 0
    fi

    # tree-sitter-cli needs install.js to download the actual CLI. npm 11's
    # script policy allows this known package through the per-command flag.
    if ! npm_global_run install --allow-scripts=tree-sitter-cli tree-sitter-cli; then
        log_warn "npm install did not provide a runnable tree-sitter CLI; trying Cargo"
    elif current_version="$(tree_sitter_cli_version)" && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Installed supported tree-sitter CLI: $current_version"
        return 0
    fi

    # A prior install may have added the package while its lifecycle script was
    # blocked. Rebuild only this package to run its now-allowed install script.
    log_info "Re-running tree-sitter-cli install script"
    if ! npm_global_run rebuild --allow-scripts=tree-sitter-cli tree-sitter-cli; then
        log_warn "npm rebuild did not provide a runnable tree-sitter CLI; trying Cargo"
    elif current_version="$(tree_sitter_cli_version)" && tree_sitter_version_is_supported "$current_version" "$required_version"; then
        log_ok "Installed supported tree-sitter CLI: $current_version"
        return 0
    fi

    if ! remove_tree_sitter_install_created_by_npm "$install_target"; then
        return 1
    fi

    install_tree_sitter_cli_with_cargo "$required_version"
}

install_codegraph() {
    log_info "Checking codegraph..."

    if command -v codegraph &>/dev/null; then
        log_ok "Found codegraph"
        return 0
    fi

    if ! ensure_required_command "npm"; then
        log_error "codegraph requires npm"
        return 1
    fi

    if ! npm_global_run install @colbymchenry/codegraph; then
        log_error "Failed to install codegraph with npm"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
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

waypost_find_git_project_root() {
    local directory="$1"

    # Keep the project boundary when Git itself is unavailable: a normal
    # checkout has a .git directory and a linked worktree has a .git file.
    # Do not treat an arbitrary cwd (notably $HOME) as a project merely
    # because the installer was launched there.
    while :; do
        if [[ -d "$directory/.git" || -f "$directory/.git" ]]; then
            printf '%s\n' "$directory"
            return 0
        fi
        [[ "$directory" == "/" ]] && return 1
        directory="$(dirname "$directory")"
    done
}

waypost_global_rejected_roots() {
    local project_root=""
    local working_dir=""

    # Never authorize a binary sourced from this mutable checkout. Also reject
    # the actual root of another checkout: its PATH may put a project-local
    # executable ahead of the installed Waypost command. Do not invoke `git`
    # from that same PATH to discover the boundary; a project-controlled git
    # wrapper or GIT_DIR could report an unrelated root.
    working_dir="$(pwd -P)" || working_dir="$PWD"
    printf '%s\0' "$SCRIPT_DIR"
    project_root="$(waypost_find_git_project_root "$working_dir" 2>/dev/null || true)"
    [[ -n "$project_root" ]] && printf '%s\0' "$project_root"
}

resolve_trusted_waypost_command() {
    local rejected_root
    local -a rejected_roots=()

    while IFS= read -r -d '' rejected_root; do
        rejected_roots+=("$rejected_root")
    done < <(waypost_global_rejected_roots)

    if ! waypost_rule_resolve_cli "${rejected_roots[@]}"; then
        log_error "Cannot use Waypost for installer-managed authorization: $WAYPOST_RULE_RESOLVE_ERROR"
        return 1
    fi

    return 0
}

ensure_waypost_mcp_command() {
    log_info "Checking built-in waypost MCP command..."

    if ! resolve_trusted_waypost_command; then
        log_info "Install Waypost outside the current project, then rerun the installer"
        return 1
    fi

    if ! "$WAYPOST_RULE_COMMAND" mcp --help >/dev/null 2>&1; then
        log_error "Installed Waypost does not expose the built-in MCP server"
        log_info "Update Waypost so 'waypost mcp' is supported, then rerun the installer"
        return 1
    fi

    log_ok "Found built-in Waypost MCP server: $WAYPOST_RULE_COMMAND mcp"
    return 0
}

ensure_waypost_cli_command() {
    log_info "Checking Waypost CLI for read-only permissions..."

    if ! waypost_rule_state_dir >/dev/null; then
        log_error "Waypost state directory must be absolute: ${WAYPOST_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ai-agent/waypost}"
        return 1
    fi

    if ! resolve_trusted_waypost_command; then
        log_info "Install Waypost outside the current project, then rerun the installer"
        return 1
    fi

    if ! waypost_rule_validate_capabilities "$WAYPOST_RULE_COMMAND"; then
        log_error "Installed Waypost does not support state-scoped read/list commands"
        log_info "Update Waypost so 'waypost --state-dir PATH read|list' is supported, then rerun the installer"
        return 1
    fi

    log_ok "Found Waypost CLI for read-only permissions: $WAYPOST_RULE_COMMAND"
    return 0
}

ensure_ai_rules_renderer_dependencies() {
    local dependency

    for dependency in jq perl; do
        if ! command -v "$dependency" &>/dev/null; then
            log_error "Missing required command for AI authorization rules: $dependency"
            log_info "Install $dependency, then rerun the installer"
            return 1
        fi
    done

    return 0
}

ensure_waypost_authorization_prerequisites() {
    ensure_ai_rules_renderer_dependencies \
        && load_claude_waypost_cli_manifest \
        && ensure_waypost_mcp_command \
        && ensure_waypost_cli_command
}

prepare_ai_rules_waypost_prerequisites() {
    if ! component_is_selected "ai-rules"; then
        return 0
    fi

    if ensure_waypost_authorization_prerequisites; then
        AI_RULES_WAYPOST_PREREQUISITES=ready
    else
        AI_RULES_WAYPOST_PREREQUISITES=failed
        log_warn "AI authorization prerequisites failed; existing authorization rules will be preserved"
    fi

    return 0
}

prepare_waypost_config_switch() {
    local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
    local legacy_state_dir="$state_home/ai-agent/mailbox"

    WAYPOST_CONFIG_SWITCH_READY=0

    if ! ensure_waypost_mcp_command; then
        log_warn "Skipping Waypost-dependent config changes"
        return 1
    fi

    if [[ -e "$legacy_state_dir" ]] || [[ -L "$legacy_state_dir" ]]; then
        log_error "Legacy Waypost state requires explicit migration: $legacy_state_dir"
        log_info "Run 'waypost migrate' manually, verify the result, then rerun this installer"
        log_warn "Preserving legacy state and skipping Waypost-dependent config changes"
        return 1
    fi

    WAYPOST_CONFIG_SWITCH_READY=1
    return 0
}

waypost_config_switch_is_ready() {
    local client_name="$1"

    if [[ $WAYPOST_CONFIG_SWITCH_READY -eq 1 ]]; then
        return 0
    fi

    log_warn "Skipping $client_name Waypost MCP switch; preparation did not complete"
    return 1
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

waypost_cli_commands() {
    if [[ -z "$WAYPOST_RULE_COMMAND" ]]; then
        log_error "Waypost CLI rules were requested before trusted command validation"
        return 1
    fi

    waypost_rule_command_forms "$WAYPOST_RULE_COMMAND"
}

waypost_cli_state_dirs() {
    waypost_rule_state_dirs
}

waypost_cli_readonly_prefixes_json() {
    local waypost_path
    local state_dir

    local waypost_action
    local prefixes_json='[]'

    if [[ -z "$WAYPOST_RULE_COMMAND" ]]; then
        log_error "Waypost CLI rules were requested before trusted command validation"
        return 1
    fi

    while IFS= read -r -d '' waypost_path; do
        while IFS= read -r -d '' state_dir; do
            for waypost_action in read list; do
                prefixes_json="$(jq -cn \
                    --argjson prefixes "$prefixes_json" \
                    --arg waypost_path "$waypost_path" \
                    --arg state_dir "$state_dir" \
                    --arg waypost_action "$waypost_action" \
                    '$prefixes + [[$waypost_path, "--state-dir", $state_dir, $waypost_action]] | unique')" \
                    || return 1
            done
        done < <(waypost_cli_state_dirs)
    done < <(waypost_cli_commands)

    printf '%s\n' "$prefixes_json"
}

write_generated_waypost_cli_file() {
    local dst="$1"
    local content="$2"
    local client_name="$3"
    local current_content=""
    local action
    local tmp_file

    if [[ -e "$dst" || -L "$dst" ]]; then
        if [[ -f "$dst" && ! -L "$dst" ]] \
            && [[ "$(head -n 1 "$dst")" == "$WAYPOST_CLI_RULE_MARKER" ]]; then
            current_content="$(<"$dst")"
            if [[ "$current_content" == "$content" ]]; then
                log_warn "Already generated $client_name Waypost CLI permissions: $dst"
                skipped=$((skipped + 1))
                return 0
            fi
        elif [[ $FORCE -eq 1 ]]; then
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
            log_warn "User-managed Waypost CLI permissions exist: $dst"
            skipped=$((skipped + 1))
            return 0
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would generate $client_name Waypost CLI permissions: $dst"
        copied=$((copied + 1))
        return 0
    fi

    ensure_parent_directory "$dst" || {
        failed=$((failed + 1))
        return 1
    }

    tmp_file="$(mktemp "${TMPDIR:-/tmp}/waypost-cli-permissions.XXXXXX")" || {
        log_error "Failed to create temporary $client_name Waypost permissions file"
        failed=$((failed + 1))
        return 1
    }

    if ! printf '%s\n' "$content" > "$tmp_file" || ! mv "$tmp_file" "$dst"; then
        rm -f "$tmp_file"
        log_error "Failed to write $client_name Waypost CLI permissions: $dst"
        failed=$((failed + 1))
        return 1
    fi

    log_ok "Generated $client_name Waypost CLI permissions: $dst"
    copied=$((copied + 1))
    return 0
}

waypost_codex_cli_rules() {
    waypost_cli_readonly_prefixes_json | jq -r --arg marker "$WAYPOST_CLI_RULE_MARKER" '
        $marker + "\n\n" + (
            map(
                "prefix_rule(\n"
                + "    pattern = [" + (map(@json) | join(", ")) + "],\n"
                + "    decision = \"allow\",\n"
                + ")"
            ) | join("\n\n")
        )
    '
}

install_codex_waypost_cli_permissions() {
    local rules_file="$HOME/.codex/rules/waypost-readonly.rules"
    local rules_content

    ensure_waypost_cli_command || return 1
    rules_content="$(waypost_codex_cli_rules)" || {
        log_error "Failed to build Codex Waypost CLI permissions"
        return 1
    }

    write_generated_waypost_cli_file "$rules_file" "$rules_content" "Codex"
}

waypost_claude_cli_permissions_json() {
    local rules_json

    rules_json="$(waypost_claude_cli_rule_records_json)" || return 1
    waypost_rule_claude_cli_permissions_from_rule_records_json "$rules_json"
}

waypost_claude_cli_rule_records_json() {
    local state_dir
    local waypost_command
    local waypost_action
    local wildcard
    local rule_json
    local rules_json='[]'

    while IFS= read -r -d '' waypost_command; do
        while IFS= read -r -d '' state_dir; do
            for waypost_action in read list; do
                for wildcard in false true; do
                    rule_json="$(waypost_rule_claude_cli_rule_json \
                        "$waypost_command" "$state_dir" "$waypost_action" "$wildcard")" || return 1
                    rules_json="$(jq -cn \
                        --argjson rules "$rules_json" \
                        --argjson rule "$rule_json" \
                        '$rules + [$rule] | unique')" || return 1
                done
            done
        done < <(waypost_cli_state_dirs)
    done < <(waypost_cli_commands)

    printf '%s\n' "$rules_json"
}

waypost_gemini_cli_policy() {
    waypost_cli_readonly_prefixes_json | jq -r --arg marker "$WAYPOST_CLI_RULE_MARKER" '
        $marker + "\n\n" + (
            to_entries
            | map(
                .key as $index
                | .value as $prefix
                | "[[rule]]\n"
                  + "name = \"allow_waypost_cli_" + $prefix[-1] + "_" + (($index + 1) | tostring) + "\"\n"
                  + "enabled = true\n"
                  + "decision = \"allow\"\n"
                  + "toolName = \"run_shell_command\"\n"
                  + "commandPrefix = [" + ($prefix | map(@json) | join(", ")) + "]\n"
                  + "priority = 950\n"
                  + "modes = [\"default\", \"autoEdit\", \"yolo\"]"
            ) | join("\n\n")
        )
    '
}

install_gemini_waypost_cli_permissions() {
    local policy_file="$HOME/.gemini/policies/waypost-readonly.toml"
    local policy_content

    ensure_waypost_cli_command || return 1
    policy_content="$(waypost_gemini_cli_policy)" || {
        log_error "Failed to build Gemini Waypost CLI permissions"
        return 1
    }

    write_generated_waypost_cli_file "$policy_file" "$policy_content" "Gemini"
}

install_waypost_cli_rules() {
    local status=0
    local prerequisites_checked=0

    if (($# > 0)); then
        prerequisites_checked="$1"
    fi

    if [[ $prerequisites_checked -ne 1 ]] && ! ensure_waypost_cli_command; then
        log_warn "Skipping Waypost CLI permission rules"
        return 1
    fi

    log_info "Installing read-only Waypost CLI permission rules..."
    install_codex_waypost_cli_permissions || status=1
    ensure_claude_waypost_cli_permissions || status=1
    install_gemini_waypost_cli_permissions || status=1

    return "$status"
}

install_agent_deck_workflow_rules() {
    local status=0

    log_info "Installing Agent Deck authorization rules..."
    # Authorization assets have their own ownership boundary. Do not link
    # them into the shared skill snapshot: ai/ai-skills must never update a
    # live authorization policy when ai-rules was not selected.
    install_copy \
        "ai-agent/codex/rules/agent-deck-workflow.rules" \
        "$HOME/.codex/rules/agent-deck-workflow.rules" \
        0 \
        "$SHARED_AI_AGENT_DIR/codex/rules/agent-deck-workflow.rules" \
        "$SHARED_AI_AGENT_DIR/.codex/rules/agent-deck-workflow.rules" \
        "$SCRIPT_DIR/ai-agent/.codex/rules/agent-deck-workflow.rules" || status=1
    install_copy \
        "ai-agent/gemini/policies/agent-deck-workflow.toml" \
        "$HOME/.gemini/policies/agent-deck-workflow.toml" \
        0 \
        "$SHARED_AI_AGENT_DIR/gemini/policies/agent-deck-workflow.toml" \
        "$SHARED_AI_AGENT_DIR/.gemini/policies/agent-deck-workflow.toml" \
        "$SCRIPT_DIR/ai-agent/.gemini/policies/agent-deck-workflow.toml" \
        "$SHARED_INSTALL_ROOT/ai-rules-preserved/gemini/policies/agent-deck-workflow.toml" || status=1

    return "$status"
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

ensure_regular_or_absent_settings_file() {
    local settings_name="$1"
    local settings_file="$2"

    if [[ -L "$settings_file" || ( -e "$settings_file" && ! -f "$settings_file" ) ]]; then
        log_error "Refusing symlinked or non-file $settings_name: $settings_file"
        return 1
    fi

    return 0
}

rewrite_gemini_waypost_config() {
    local gemini_config="$HOME/.gemini/settings.json"
    local tmp_file

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would rewrite Gemini MCP config in: $gemini_config"
        return 0
    fi

    ensure_regular_or_absent_settings_file "Gemini settings path" "$gemini_config" || return 1
    mkdir -p "$(dirname "$gemini_config")" || {
        log_error "Failed to create Gemini settings directory"
        return 1
    }

    tmp_file="$(mktemp "$(dirname "$gemini_config")/.gemini-mcp-config.XXXXXX")" || {
        log_error "Failed to create temporary file for Gemini MCP config"
        return 1
    }

    if [[ -f "$gemini_config" ]]; then
        if ! jq '
            .general = ((.general // {})
                | .enableAutoUpdate = false)
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

    if ! ensure_regular_or_absent_settings_file "Gemini settings path" "$gemini_config"; then
        rm -f "$tmp_file"
        return 1
    fi
    if waypost_rule_replace_file "$tmp_file" "$gemini_config"; then
        log_ok "Rewrote Gemini MCP config: waypost"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write Gemini MCP config: $gemini_config"
    return 1
}

ensure_gemini_permanent_tool_approval() {
    local gemini_config="$HOME/.gemini/settings.json"
    local tmp_file

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would enable Gemini permanent tool approval in: $gemini_config"
        return 0
    fi

    ensure_regular_or_absent_settings_file "Gemini settings path" "$gemini_config" || return 1
    mkdir -p "$(dirname "$gemini_config")" || {
        log_error "Failed to create Gemini settings directory"
        return 1
    }

    tmp_file="$(mktemp "$(dirname "$gemini_config")/.gemini-permissions.XXXXXX")" || {
        log_error "Failed to create temporary file for Gemini authorization settings"
        return 1
    }

    if [[ -e "$gemini_config" ]]; then
        if ! jq '
            .security = ((.security // {})
                | .enablePermanentToolApproval = true
                | .disableAlwaysAllow = false)
        ' "$gemini_config" > "$tmp_file"; then
            rm -f "$tmp_file"
            log_error "Failed to update Gemini authorization settings: $gemini_config"
            return 1
        fi
    elif ! jq -n '
        {
          "security": {
            "enablePermanentToolApproval": true,
            "disableAlwaysAllow": false
          }
        }
    ' > "$tmp_file"; then
        rm -f "$tmp_file"
        log_error "Failed to create Gemini authorization settings: $gemini_config"
        return 1
    fi

    if ! ensure_regular_or_absent_settings_file "Gemini settings path" "$gemini_config"; then
        rm -f "$tmp_file"
        return 1
    fi
    if waypost_rule_replace_file "$tmp_file" "$gemini_config"; then
        log_ok "Enabled Gemini permanent tool approval"
        return 0
    fi

    rm -f "$tmp_file"
    log_error "Failed to write Gemini authorization settings: $gemini_config"
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
    rewrite_gemini_waypost_config || return 1
    remove_gemini_stale_waypost_mcps
}

json_waypost_mcp_uses_builtin_command() {
    local config_file="$1"

    [[ -f "$config_file" ]] || return 1
    jq -e '
        (.mcpServers.waypost? // null) as $server
        | ($server | type == "object")
          and ($server.command == "waypost")
          and (($server.args | type == "array") and ($server.args[0] == "mcp"))
    ' \
        "$config_file" >/dev/null 2>&1
}

rewrite_antigravity_waypost_config() {
    local antigravity_mcp_config="$HOME/.gemini/config/mcp_config.json"
    local antigravity_settings="$HOME/.gemini/antigravity-cli/settings.json"
    local tmp_file
    local settings_input="$antigravity_settings"
    local settings_input_tmp=""

    if [[ $DRY_RUN -eq 1 ]]; then
        ensure_top_level_mcp_stdio_server "Antigravity" "$antigravity_mcp_config" "waypost" "waypost" '["mcp"]' || return 1
        if [[ ! -s "$antigravity_settings" ]]; then
            log_dry "Would create Antigravity settings file and remove stale MCP servers in: $antigravity_settings"
        else
            log_dry "Would remove stale Antigravity MCP servers in: $antigravity_settings"
        fi
        return 0
    fi

    ensure_regular_or_absent_settings_file "Antigravity settings path" "$antigravity_settings" || return 1
    ensure_top_level_mcp_stdio_server "Antigravity" "$antigravity_mcp_config" "waypost" "waypost" '["mcp"]' || return 1
    mkdir -p "$(dirname "$antigravity_settings")" || {
        log_error "Failed to create Antigravity settings directory"
        return 1
    }
    if [[ ! -s "$antigravity_settings" ]]; then
        settings_input_tmp="$(mktemp "$(dirname "$antigravity_settings")/.antigravity-settings-input.XXXXXX")" || {
            log_error "Failed to stage Antigravity settings input"
            return 1
        }
        if ! printf '{}\n' > "$settings_input_tmp"; then
            rm -f "$settings_input_tmp"
            log_error "Failed to render Antigravity settings input"
            return 1
        fi
        settings_input="$settings_input_tmp"
    fi

    tmp_file="$(mktemp "$(dirname "$antigravity_settings")/.antigravity-settings.XXXXXX")" || {
        rm -f "$settings_input_tmp"
        log_error "Failed to create temporary file for Antigravity settings cleanup"
        return 1
    }

    if ! jq '
            if (.mcpServers | type) == "object" then
                .mcpServers |= del(.workflow_mailbox, .agent_mailbox, ."agent-mailbox", .adwf_mailbox, ."adwf-mailbox")
                | if (.mcpServers == {}) then del(.mcpServers) else . end
            else
                .
            end
        ' "$settings_input" > "$tmp_file"; then
        rm -f "$tmp_file"
        rm -f "$settings_input_tmp"
        log_error "Failed to remove stale Antigravity MCP servers: $antigravity_settings"
        return 1
    fi
    rm -f "$settings_input_tmp"

    if ! ensure_regular_or_absent_settings_file "Antigravity settings path" "$antigravity_settings"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! waypost_rule_replace_file "$tmp_file" "$antigravity_settings"; then
        rm -f "$tmp_file"
        log_error "Failed to write Antigravity MCP settings: $antigravity_settings"
        return 1
    fi

    log_ok "Rewrote Antigravity MCP config: waypost"
    return 0
}

antigravity_waypost_mcp_uses_builtin_command() {
    json_waypost_mcp_uses_builtin_command "$HOME/.gemini/config/mcp_config.json" \
        || json_waypost_mcp_uses_builtin_command "$HOME/.gemini/antigravity-cli/settings.json"
}

ensure_antigravity_waypost_permissions() {
    local antigravity_settings="$HOME/.gemini/antigravity-cli/settings.json"
    local antigravity_permissions_json
    local migrate_legacy=0
    local tmp_file
    local settings_input="$antigravity_settings"
    local settings_input_tmp=""

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would migrate Antigravity Waypost MCP permissions in: $antigravity_settings"
        return 0
    fi

    ensure_regular_or_absent_settings_file "Antigravity settings path" "$antigravity_settings" || return 1
    antigravity_permissions_json="$(waypost_mcp_permissions_json 'mcp(waypost/' ')')" || {
        log_error "Failed to build Antigravity Waypost MCP permissions"
        return 1
    }

    if antigravity_waypost_mcp_uses_builtin_command; then
        migrate_legacy=1
    fi

    mkdir -p "$(dirname "$antigravity_settings")" || {
        log_error "Failed to create Antigravity settings directory"
        return 1
    }
    if [[ ! -s "$antigravity_settings" ]]; then
        settings_input_tmp="$(mktemp "$(dirname "$antigravity_settings")/.antigravity-permissions-input.XXXXXX")" || {
            log_error "Failed to stage Antigravity settings input"
            return 1
        }
        if ! printf '{}\n' > "$settings_input_tmp"; then
            rm -f "$settings_input_tmp"
            log_error "Failed to render Antigravity settings input"
            return 1
        fi
        settings_input="$settings_input_tmp"
    fi

    tmp_file="$(mktemp "$(dirname "$antigravity_settings")/.antigravity-permissions.XXXXXX")" || {
        rm -f "$settings_input_tmp"
        log_error "Failed to create temporary file for Antigravity permissions"
        return 1
    }

    if ! jq --argjson perms "$antigravity_permissions_json" \
        --argjson migrate_legacy "$migrate_legacy" '
        def migrate_permission:
            if type == "string" then
                sub("^mcp\\((workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox)/"; "mcp(waypost/")
                | sub("^mcp\\(waypost/mailbox_"; "mcp(waypost/waypost_")
            else
                .
            end;
        .permissions.allow = (
            (.permissions.allow // [])
            | if $migrate_legacy == 1 then map(migrate_permission) else . end
            | . + $perms
            | unique
        )
    ' "$settings_input" > "$tmp_file"; then
        rm -f "$tmp_file"
        rm -f "$settings_input_tmp"
        log_error "Failed to migrate Antigravity MCP permissions: $antigravity_settings"
        return 1
    fi
    rm -f "$settings_input_tmp"

    if ! ensure_regular_or_absent_settings_file "Antigravity settings path" "$antigravity_settings"; then
        rm -f "$tmp_file"
        return 1
    fi
    if ! waypost_rule_replace_file "$tmp_file" "$antigravity_settings"; then
        rm -f "$tmp_file"
        log_error "Failed to write Antigravity MCP permissions: $antigravity_settings"
        return 1
    fi

    if [[ $migrate_legacy -eq 1 ]]; then
        log_ok "Migrated Antigravity Waypost MCP permissions"
    else
        log_ok "Updated Antigravity Waypost MCP permissions (legacy approvals retained)"
    fi
    return 0
}

install_antigravity_waypost_mcp() {
    rewrite_antigravity_waypost_config || return 1
}

install_kiro_waypost_mcp() {
    ensure_top_level_mcp_stdio_server "Kiro CLI" "$HOME/.kiro/settings/mcp.json" "waypost" "waypost" '["mcp"]'
}

codex_waypost_mcp_uses_builtin_command() {
    local codex_config="$HOME/.codex/config.toml"

    [[ -f "$codex_config" ]] || return 1
    perl -0ne '
        my @lines = split /\n/, $_, -1;
        my $in_waypost_section = 0;
        my $has_command = 0;
        my $has_args = 0;

        for my $line (@lines) {
            if ($line =~ /^\s*\[/) {
                last if $in_waypost_section;
                $in_waypost_section =
                    $line =~ /^\s*\[\s*mcp_servers\.(?:"waypost"|waypost)\s*\]\s*(?:\#.*)?$/;
                next;
            }
            next unless $in_waypost_section;
            $has_command = 1
                if $line =~ /^\s*command\s*=\s*"waypost"\s*(?:\#.*)?$/;
            $has_args = 1
                if $line =~ /^\s*args\s*=\s*\[\s*"mcp"(?:\s*,[^\]]*)?\]\s*(?:\#.*)?$/;
        }

        exit($in_waypost_section && $has_command && $has_args ? 0 : 1);
    ' "$codex_config"
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

    if ! codex_waypost_mcp_uses_builtin_command; then
        log_warn "Retaining Codex legacy MCP tool approvals; a built-in Waypost MCP is not configured"
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
    CODEX_LEGACY_MCP_CLEANUP_PENDING=0

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
        # Tool approvals belong to ai-rules. Keep legacy MCP sections intact
        # until that component has migrated their tool tables successfully.
        CODEX_LEGACY_MCP_CLEANUP_PENDING=1
        log_ok "Ensured Codex MCP env passthrough and Waypost tool timeout: waypost"
        return 0
    fi

    log_error "Failed to update Codex MCP env passthrough and Waypost tool timeout"
    return 1
}

claude_waypost_mcp_uses_builtin_command() {
    json_waypost_mcp_uses_builtin_command "$HOME/.claude.json"
}

claude_waypost_cli_manifest_path() {
    printf '%s\n' "$CONFIG_FILES_STATE_DIR/ai-rules/claude-waypost-cli.json"
}

# Claude settings have no rule IDs. Persist structured CLI argv plus the exact
# rendered entries so future state-dir/path updates remove only installer-owned
# rules without reparsing shell syntax.
load_claude_waypost_cli_manifest() {
    local manifest_path
    local manifest_permissions

    CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS='[]'
    CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT=0
    manifest_path="$(claude_waypost_cli_manifest_path)"

    if [[ ! -e "$manifest_path" && ! -L "$manifest_path" ]]; then
        return 0
    fi
    if [[ ! -f "$manifest_path" || -L "$manifest_path" ]]; then
        log_error "Refusing invalid Claude Waypost ownership manifest: $manifest_path"
        return 1
    fi

    manifest_permissions="$(waypost_rule_claude_cli_manifest_permissions_json "$manifest_path")" || {
        log_error "Refusing malformed Claude Waypost ownership manifest: $manifest_path"
        return 1
    }

    CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS="$manifest_permissions"
    CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT=1
    return 0
}

stage_claude_waypost_cli_manifest() {
    local permissions_json="$1"
    local rules_json="$2"
    local manifest_path

    CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
    manifest_path="$(claude_waypost_cli_manifest_path)"
    ensure_parent_directory "$manifest_path" || return 1

    CLAUDE_WAYPOST_CLI_MANIFEST_TMP="$(mktemp "$(dirname "$manifest_path")/.claude-waypost-cli.XXXXXX")" || {
        log_error "Failed to stage Claude Waypost ownership manifest"
        return 1
    }
    if ! jq -n \
        --argjson permissions "$permissions_json" \
        --argjson rules "$rules_json" \
        '{version: 2, permissions: $permissions, rules: $rules}' \
        > "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP"; then
        rm -f "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP"
        CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
        log_error "Failed to render Claude Waypost ownership manifest"
        return 1
    fi

    return 0
}

commit_claude_waypost_cli_manifest() {
    local manifest_path

    [[ -n "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP" ]] || return 0
    manifest_path="$(claude_waypost_cli_manifest_path)"
    if waypost_rule_replace_file "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP" "$manifest_path"; then
        CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
        return 0
    fi

    rm -f "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP"
    CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
    log_error "Failed to write Claude Waypost ownership manifest: $manifest_path"
    return 1
}

discard_claude_waypost_cli_manifest() {
    if [[ -n "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP" ]]; then
        rm -f "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP"
        CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
    fi
}

ensure_claude_waypost_permissions() {
    local include_mcp="${1:-1}"
    local include_cli="${2:-1}"
    local claude_settings="$HOME/.claude/settings.json"
    local claude_mcp_permissions_json='[]'
    local claude_cli_permissions_json='[]'
    local claude_cli_rule_records_json='[]'
    local migrate_mcp=0
    local migrate_legacy_cli=0
    local tmp_file
    local settings_input="$claude_settings"
    local settings_input_tmp=""
    local settings_backup=""
    local settings_existed=0

    case "$include_mcp:$include_cli" in
        0:1|1:0|1:1) ;;
        *)
            log_error "Invalid Claude Waypost permission scope"
            return 1
            ;;
    esac

    if [[ $include_mcp -eq 1 ]]; then
        claude_mcp_permissions_json="$(waypost_mcp_permissions_json 'mcp__waypost__' '')" || {
            log_error "Failed to build Claude Waypost MCP permissions"
            return 1
        }
        if claude_waypost_mcp_uses_builtin_command; then
            migrate_mcp=1
        fi
    fi

    if [[ $include_cli -eq 1 ]]; then
        load_claude_waypost_cli_manifest || return 1
        if [[ $CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT -eq 0 ]]; then
            migrate_legacy_cli=1
        fi
        claude_cli_rule_records_json="$(waypost_claude_cli_rule_records_json)" || {
            log_error "Failed to build Claude Waypost CLI ownership records"
            return 1
        }
        claude_cli_permissions_json="$(waypost_rule_claude_cli_permissions_from_rule_records_json \
            "$claude_cli_rule_records_json")" || {
            log_error "Failed to build Claude Waypost CLI permissions"
            return 1
        }
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ $include_mcp -eq 1 && $include_cli -eq 1 ]]; then
            log_dry "Would update Claude Waypost MCP and CLI permissions in: $claude_settings"
        elif [[ $include_mcp -eq 1 ]]; then
            log_dry "Would update Claude Waypost MCP permissions in: $claude_settings"
        else
            log_dry "Would update Claude Waypost CLI permissions in: $claude_settings"
        fi
        return 0
    fi

    if [[ -L "$claude_settings" || ( -e "$claude_settings" && ! -f "$claude_settings" ) ]]; then
        log_error "Refusing symlinked or non-file Claude settings path: $claude_settings"
        return 1
    fi

    mkdir -p "$(dirname "$claude_settings")" || {
        log_error "Failed to create Claude settings directory"
        return 1
    }

    if [[ $include_cli -eq 1 && -e "$claude_settings" ]]; then
        settings_existed=1
        settings_backup="$(mktemp "$(dirname "$claude_settings")/.claude-settings-rollback.XXXXXX")" || {
            log_error "Failed to stage Claude settings rollback"
            return 1
        }
        if ! cp -p "$claude_settings" "$settings_backup"; then
            rm -f "$settings_backup"
            log_error "Failed to stage Claude settings rollback"
            return 1
        fi
    fi

    if [[ $include_cli -eq 1 ]]; then
        stage_claude_waypost_cli_manifest \
            "$claude_cli_permissions_json" "$claude_cli_rule_records_json" || {
                rm -f "$settings_backup"
                return 1
            }
    fi

    if [[ ! -s "$claude_settings" ]]; then
        settings_input_tmp="$(mktemp "$(dirname "$claude_settings")/.claude-settings-input.XXXXXX")" || {
            discard_claude_waypost_cli_manifest
            rm -f "$settings_backup"
            log_error "Failed to stage Claude settings input"
            return 1
        }
        if ! printf '{}\n' > "$settings_input_tmp"; then
            rm -f "$settings_input_tmp"
            discard_claude_waypost_cli_manifest
            rm -f "$settings_backup"
            log_error "Failed to render Claude settings input"
            return 1
        fi
        settings_input="$settings_input_tmp"
    fi

    tmp_file="$(mktemp "$(dirname "$claude_settings")/.claude-settings.XXXXXX")" || {
        discard_claude_waypost_cli_manifest
        rm -f "$settings_input_tmp"
        rm -f "$settings_backup"
        log_error "Failed to create temporary file for Claude settings"
        return 1
    }

    if ! jq --argjson mcp_perms "$claude_mcp_permissions_json" \
        --argjson cli_perms "$claude_cli_permissions_json" \
        --argjson prior_cli_perms "$CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS" \
        --argjson include_mcp "$include_mcp" \
        --argjson include_cli "$include_cli" \
        --argjson migrate_mcp "$migrate_mcp" \
        --argjson migrate_legacy_cli "$migrate_legacy_cli" '
        def migrate_permission:
            if type == "string" then
                sub("^mcp__(workflow_mailbox|agent_mailbox|agent-mailbox|adwf_mailbox|adwf-mailbox)__"; "mcp__waypost__")
                | sub("^mcp__waypost__mailbox_"; "mcp__waypost__waypost_")
            else
                .
            end;
        def is_legacy_waypost_broad_permission:
            . == "Bash(waypost)" or . == "Bash(waypost *)";
        .permissions.allow = (
            (.permissions.allow // [])
            | if $include_mcp == 1 then
                (if $migrate_mcp == 1 then map(migrate_permission) else . end)
                | . + $mcp_perms
              else .
              end
            | if $include_cli == 1 then
                map(select(. as $permission | ($prior_cli_perms | index($permission) | not)))
                | if $migrate_legacy_cli == 1 then
                    # Only the historical broad entries are identifiable
                    # without an ownership manifest. Preserve lookalike
                    # state-scoped rules rather than deleting user policy.
                    map(select(is_legacy_waypost_broad_permission | not))
                  else .
                  end
                | . + $cli_perms
              else .
              end
            | unique
        )
    ' "$settings_input" > "$tmp_file"; then
        rm -f "$tmp_file"
        discard_claude_waypost_cli_manifest
        rm -f "$settings_input_tmp"
        rm -f "$settings_backup"
        log_error "Failed to update Claude Waypost permissions: $claude_settings"
        return 1
    fi
    rm -f "$settings_input_tmp"

    if [[ -L "$claude_settings" || ( -e "$claude_settings" && ! -f "$claude_settings" ) ]]; then
        rm -f "$tmp_file"
        discard_claude_waypost_cli_manifest
        rm -f "$settings_backup"
        log_error "Refusing symlinked or non-file Claude settings path: $claude_settings"
        return 1
    fi

    if waypost_rule_replace_file "$tmp_file" "$claude_settings"; then
        if [[ $include_cli -eq 1 ]] && ! commit_claude_waypost_cli_manifest; then
            if [[ $settings_existed -eq 1 ]]; then
                if ! waypost_rule_replace_file "$settings_backup" "$claude_settings"; then
                    rm -f "$settings_backup"
                    log_error "Failed to restore Claude settings after manifest failure: $claude_settings"
                fi
            else
                rm -f "$claude_settings"
            fi
            return 1
        fi
        rm -f "$settings_backup"
        if [[ $include_mcp -eq 1 && $include_cli -eq 1 ]]; then
            if [[ $migrate_mcp -eq 1 ]]; then
                log_ok "Migrated Claude Waypost MCP and CLI permissions"
            else
                log_ok "Updated Claude Waypost MCP and CLI permissions (legacy approvals retained)"
            fi
        elif [[ $include_mcp -eq 1 ]]; then
            if [[ $migrate_mcp -eq 1 ]]; then
                log_ok "Migrated Claude Waypost MCP permissions"
            else
                log_ok "Updated Claude Waypost MCP permissions (legacy approvals retained)"
            fi
        else
            log_ok "Updated Claude Waypost CLI permissions"
        fi
        return 0
    fi

    rm -f "$tmp_file"
    discard_claude_waypost_cli_manifest
    rm -f "$settings_backup"
    log_error "Failed to write Claude Waypost permissions: $claude_settings"
    return 1
}

ensure_claude_waypost_cli_permissions() {
    ensure_waypost_cli_command || return 1
    ensure_claude_waypost_permissions 0 1
}

ensure_claude_waypost_mcp_permissions() {
    ensure_claude_waypost_permissions 1 0
}

install_ai_permission_rules() {
    local status=0

    log_info "Installing global AI authorization rules..."
    if [[ "$AI_RULES_WAYPOST_PREREQUISITES" == unknown ]]; then
        if ensure_waypost_authorization_prerequisites; then
            AI_RULES_WAYPOST_PREREQUISITES=ready
        else
            AI_RULES_WAYPOST_PREREQUISITES=failed
        fi
    fi
    if [[ "$AI_RULES_WAYPOST_PREREQUISITES" != ready ]]; then
        log_warn "Skipping AI authorization rule changes; Waypost prerequisites are unavailable"
        return 1
    fi

    install_agent_deck_workflow_rules || status=1
    if migrate_codex_legacy_waypost_tool_permissions; then
        if [[ $CODEX_LEGACY_MCP_CLEANUP_PENDING -eq 1 ]]; then
            if codex_waypost_mcp_uses_builtin_command; then
                remove_codex_legacy_waypost_mcps || status=1
                CODEX_LEGACY_MCP_CLEANUP_PENDING=0
            else
                log_warn "Retaining Codex legacy MCPs; the Waypost MCP is no longer configured"
                status=1
            fi
        fi
    else
        status=1
    fi
    ensure_claude_waypost_mcp_permissions || status=1
    ensure_gemini_permanent_tool_approval || status=1
    ensure_antigravity_waypost_permissions || status=1
    install_waypost_cli_rules 1 || status=1

    return "$status"
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
        return 0
    fi

    if ! command -v claude &>/dev/null && [[ $CLAUDE_CODE_AVAILABLE -ne 1 ]]; then
        log_warn "Skipping Claude MCP install (claude not found)"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: claude mcp add -s user waypost -- waypost mcp"
        remove_claude_stale_waypost_mcps
        return 0
    fi

    if claude mcp add -s user waypost -- waypost mcp; then
        log_ok "Configured Claude MCP: waypost"
        rewrite_claude_waypost_config || return 1
        remove_claude_stale_waypost_mcps
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

detect_installed_agent_deck() {
    if command -v agent-deck &>/dev/null; then
        AGENT_DECK_AVAILABLE=1
        log_ok "Found agent-deck"
    else
        AGENT_DECK_AVAILABLE=0
        log_warn "agent-deck not found; skipping agent-deck related skills"
    fi
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
    local config_submodules_ready="${1:-1}"
    local zsh_stack_ready="${2:-1}"

    log_info "Installing home directory dotfiles..."

    # Shell configs
    install_copy "bashrc" "$HOME/.bashrc"
    if [[ $zsh_stack_ready -eq 1 ]]; then
        install_copy "zshrc" "$HOME/.zshrc"
    else
        log_warn "Skipping zshrc; the Zsh stack is unavailable"
        skipped=$((skipped + 1))
    fi

    # Screen config
    install_copy "screenrc" "$HOME/.screenrc"

    # Tmux config (file in tmux/ directory)
    install_copy "tmux/tmux.conf" "$HOME/.tmux.conf"
    if [[ $config_submodules_ready -eq 1 ]]; then
        install_copy "tmux/plugins/tpm" "$HOME/.tmux/plugins/tpm"
    else
        log_warn "Skipping TPM config; its Git submodule is unavailable"
    fi

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

install_ai_agent_config() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"

    if [[ $WAYPOST_CONFIG_SWITCH_READY -ne 1 ]]; then
        log_warn "Skipping AI agent config; Waypost preparation did not complete"
        return 0
    fi

    install_copy "ai-agent" "$config_dir/ai-agent"
}

install_xdg_configs() {
    local config_submodules_ready="${1:-1}"

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
    if [[ $config_submodules_ready -eq 1 ]]; then
        install_copy "nvim" "$config_dir/nvim"
    else
        log_warn "Skipping Neovim config; its Git submodules are unavailable"
    fi

    # Individual files
    install_copy "fourmolu.yaml" "$config_dir/fourmolu.yaml"

    # AI-related configs
    if should_install_ai_agent_config; then
        install_ai_agent_config
    fi

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
        if ! skills_directory_is_available "$tool_skills_dir"; then
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

skills_directory_is_available() {
    local skills_dir="$1"

    if [[ -d "$skills_dir" ]] || [[ -L "$skills_dir" ]]; then
        return 0
    fi

    [[ $DRY_RUN -eq 1 ]] \
        && [[ "$skills_dir" == "$SHARED_AGENT_SKILLS_DIR" ]] \
        && [[ $SHARED_AGENT_SKILLS_DIR_READY -eq 1 ]]
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
    if should_install_ai_skills; then
        install_claude_skills
    fi

    # Install workflow permission init script to ~/.local/bin
    local bin_dir="$HOME/.local/bin"
    link_shared_ai_agent_item "skills/agent-deck-workflow/scripts/agent-deck-workflow-init-permissions.sh" "$bin_dir/agent-deck-workflow-init-permissions"
    link_shared_ai_agent_item "skills/agent-deck-workflow/scripts/adwf-send-and-wake.sh" "$bin_dir/adwf-send-and-wake"

    # Link statusline script
    link_shared_ai_agent_item "claude/statusline-command.sh" "$claude_dir/statusline-command.sh"

    if ! waypost_config_switch_is_ready "Claude"; then
        return 0
    fi

    install_claude_waypost_mcp || return 1
    remove_obsolete_waypost_launchers
}

cleanup_duplicate_skill_links() {
    local tool_name="$1"
    local duplicate_skills_dir="$2"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    if [[ ! -d "$duplicate_skills_dir" ]]; then
        return 0
    fi

    cleanup_dead_skill_links "$tool_name" "$duplicate_skills_dir"

    for skill_dir in "$src_skills_dir"/*; do
        if [[ -d "$skill_dir" ]]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            local target_link="$duplicate_skills_dir/$skill_name"

            # Remove only links created by this installer.
            if [[ -L "$target_link" ]] \
                && { symlink_points_to "$target_link" "$src_skills_dir/$skill_name" \
                    || symlink_points_to "$target_link" "$SHARED_AI_AGENT_DIR/skills/$skill_name"; }; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log_dry "Would remove duplicate $tool_name skill link: $target_link"
                else
                    rm "$target_link"
                    log_info "Removed duplicate $tool_name skill link: $target_link"
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
    local agents_skills_dir="$SHARED_AGENT_SKILLS_DIR"
    local gemini_skills_dir="$HOME/.gemini/skills"

    # Newer Gemini setup may load skills from ~/.agents/skills.
    # Installing duplicates in ~/.gemini/skills triggers skill conflict warnings.
    if [[ $SHARED_AGENT_SKILLS_DIR_READY -eq 1 ]] \
        || has_shared_gemini_skill_conflicts "$agents_skills_dir"; then
        log_info "Detected shared Gemini skills path: $agents_skills_dir"
        install_skills_individually "Gemini shared" "$agents_skills_dir" 1 || return 1
        log_warn "Skipping Gemini skill links under $gemini_skills_dir to avoid duplicate skill conflicts"
        cleanup_duplicate_skill_links "Gemini" "$gemini_skills_dir"
        return 0
    fi

    install_skills_individually "Gemini CLI" "$HOME/.gemini/skills"
}

install_antigravity_skills() {
    install_skills_individually "Antigravity CLI" "$HOME/.gemini/antigravity-cli/skills"
}

install_antigravity_config() {
    log_info "Installing Antigravity CLI config..."

    if should_install_ai_skills; then
        install_antigravity_skills
    fi

    if ! waypost_config_switch_is_ready "Antigravity"; then
        return 0
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

    if should_install_ai_skills; then
        install_kiro_skills
    fi

    if ! waypost_config_switch_is_ready "Kiro CLI"; then
        return 0
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
    if should_install_ai_skills; then
        install_gemini_skills
    fi

    if ! waypost_config_switch_is_ready "Gemini"; then
        return 0
    fi

    install_gemini_waypost_mcp || return 1
}

install_codex_skills() {
    local codex_skills_dir="$SHARED_AGENT_SKILLS_DIR"
    local legacy_codex_skills_dir="$HOME/.codex/skills"
    local status=0

    SHARED_AGENT_SKILLS_DIR_READY=0
    CODEX_SKILLS_DIR_READY=0
    if ! prepare_skills_target_dir "Codex" "$codex_skills_dir"; then
        return 0
    fi

    SHARED_AGENT_SKILLS_DIR_READY=1
    CODEX_SKILLS_DIR_READY=1
    install_skills_individually "Codex" "$codex_skills_dir" 0 1 || status=1

    # Codex also discovers ~/.agents/skills. Remove only old installer links
    # from the legacy path so the same skill is not exposed twice.
    if [[ -L "$legacy_codex_skills_dir" ]]; then
        if symlink_points_to "$legacy_codex_skills_dir" "$SCRIPT_DIR/ai-agent/skills" \
            || symlink_points_to "$legacy_codex_skills_dir" "$SHARED_AI_AGENT_DIR/skills"; then
            if [[ $DRY_RUN -eq 1 ]]; then
                log_dry "Would remove legacy Codex skills directory: $legacy_codex_skills_dir"
            else
                rm "$legacy_codex_skills_dir"
                log_info "Removed legacy Codex skills directory: $legacy_codex_skills_dir"
            fi
        fi
    else
        cleanup_duplicate_skill_links "Codex legacy" "$legacy_codex_skills_dir" || status=1
    fi

    return "$status"
}

ensure_codex_tui_usage_limit_resume_prompt() {
    local codex_config="$HOME/.codex/config.toml"
    local prompt="The previous turn stopped because the active account hit a usage limit. You can go on now."

    ensure_toml_string_key "$codex_config" "tui" "usage_limit_resume_prompt" "$prompt"
}

install_opencode_skills() {
    install_skills_individually "OpenCode" "$HOME/.config/opencode/skills"
}

install_all_ai_skills() {
    local status=0

    log_info "Installing AI skills only..."
    install_codex_skills || status=1
    install_claude_skills || status=1
    install_gemini_skills || status=1
    install_antigravity_skills || status=1
    install_kiro_skills || status=1
    install_opencode_skills || status=1

    return "$status"
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

    if should_install_ai_skills; then
        install_codex_skills
    fi
    # ensure_codex_tui_usage_limit_resume_prompt || return 1

    if ! waypost_config_switch_is_ready "Codex"; then
        return 0
    fi

    install_codex_waypost_mcp || return 1
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
    if should_install_ai_skills; then
        install_opencode_skills
    fi

    if ! waypost_config_switch_is_ready "OpenCode"; then
        return 0
    fi

    install_opencode_waypost_mcp
}

install_snapshot_dependent_ai_configs() {
    if ! component_is_selected "ai"; then
        return 0
    fi

    if [[ $SHARED_AI_AGENT_READY -ne 1 ]]; then
        log_warn "Skipping AI client configs; the shared AI agent snapshot is unavailable"
        return 0
    fi

    # Codex prepares the shared ~/.agents/skills path used by Gemini.
    run_best_effort "Codex config" install_codex_config
    run_best_effort "Claude config" install_claude_config
    run_best_effort "Gemini config" install_gemini_config
    run_best_effort "Antigravity config" install_antigravity_config
    run_best_effort "Kiro config" install_kiro_config
    # This installer depends on the Codex skills directory prepared above.
    if component_is_selected "ai-skills"; then
        run_best_effort "ast-grep skill" install_ast_grep_skill
    fi
    run_best_effort "OpenCode config" install_opencode_config
    return 0
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

install_selected_components() {
    local config_submodules_ready="${1:-1}"

    log_info "Installing selected sections: $(selected_components_label)"

    if component_is_selected "xdg" || component_is_selected "ai"; then
        run_best_effort "Waypost preparation" prepare_waypost_config_switch
    fi

    if component_is_selected "home"; then
        run_best_effort "Home configs" \
            install_home_configs "$config_submodules_ready"
    fi

    if component_is_selected "xdg"; then
        run_best_effort "XDG configs" \
            install_xdg_configs "$config_submodules_ready"
    elif component_is_selected "ai"; then
        log_info "Installing AI Agent config..."
        run_best_effort "AI Agent config" install_ai_agent_config
    fi

    if component_is_selected "bin"; then
        run_best_effort "Local bin helpers" install_local_bin_helpers
    fi

    if component_is_selected "ai" \
        || component_is_selected "ai-skills"; then
        run_best_effort "Shared AI agent snapshot" \
            install_shared_ai_agent_snapshot
        if [[ $SHARED_AI_AGENT_READY -eq 1 ]]; then
            detect_installed_agent_deck
            if component_is_selected "ai" || component_is_selected "ai-skills"; then
                run_best_effort "AI skills" install_all_ai_skills
            fi
        elif component_is_selected "ai" || component_is_selected "ai-skills"; then
            log_warn "Skipping AI skills; the shared AI agent snapshot is unavailable"
        fi
    fi

    if component_is_selected "ai-rules"; then
        prepare_ai_rules_waypost_prerequisites
        run_best_effort "AI authorization rules" install_ai_permission_rules
    fi

    if component_is_selected "serena"; then
        run_best_effort "Serena config" install_serena_config
    fi

    return 0
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
        return 0
    fi

    log_error "Failed to initialize some submodules (may require SSH key)"
    log_info "You can manually initialize later with: git submodule update --init --recursive"
    return 1
}

collect_selected_submodule_paths() {
    local gitlinks
    local metadata
    local submodule_path

    REQUIRED_SUBMODULE_PATHS=()

    if [[ $INSTALL_ALL -eq 1 && $SKIP_COMPONENTS_REQUESTED -eq 0 ]]; then
        return 0
    fi
    if ! component_is_selected "home" && ! component_is_selected "xdg"; then
        return 0
    fi
    if [[ ! -e "$SCRIPT_DIR/.git" ]]; then
        return 0
    fi
    if ! command -v git &>/dev/null; then
        log_error "git is required to initialize selected submodules"
        return 1
    fi
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        log_error "Could not inspect Git submodules in: $SCRIPT_DIR"
        return 1
    fi
    if ! gitlinks="$(git -C "$SCRIPT_DIR" ls-files --stage)"; then
        log_error "Could not list Git submodules in: $SCRIPT_DIR"
        return 1
    fi

    while IFS=$'\t' read -r metadata submodule_path; do
        [[ "$metadata" == 160000\ * && -n "$submodule_path" ]] || continue

        if component_is_selected "home" && [[ "$submodule_path" == tmux/* ]]; then
            REQUIRED_SUBMODULE_PATHS+=("$submodule_path")
        elif component_is_selected "xdg" && [[ "$submodule_path" == nvim/* ]]; then
            REQUIRED_SUBMODULE_PATHS+=("$submodule_path")
        fi
    done <<< "$gitlinks"

    return 0
}

init_selected_submodules() {
    local submodule_path
    local submodule_status

    if ! collect_selected_submodule_paths; then
        return 1
    fi
    if [[ -z "${REQUIRED_SUBMODULE_PATHS[0]+set}" ]]; then
        return 0
    fi

    log_info "Initializing selected git submodules..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: git -C $SCRIPT_DIR submodule update --init --recursive -- ${REQUIRED_SUBMODULE_PATHS[*]}"
        return 0
    fi

    if ! git -C "$SCRIPT_DIR" submodule update --init --recursive -- "${REQUIRED_SUBMODULE_PATHS[@]}"; then
        log_error "Failed to initialize required submodules; submodule-backed configs will be skipped"
        return 1
    fi

    for submodule_path in "${REQUIRED_SUBMODULE_PATHS[@]}"; do
        if ! submodule_status="$(git -C "$SCRIPT_DIR" submodule status -- "$submodule_path")"; then
            log_error "Could not verify required submodule: $submodule_path"
            return 1
        fi
        if [[ -z "$submodule_status" || "${submodule_status:0:1}" == "-" || "${submodule_status:0:1}" == "U" ]]; then
            log_error "Required submodule is not initialized: $submodule_path"
            return 1
        fi
    done

    log_ok "Initialized selected git submodules"
    return 0
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
    if [[ $INSTALL_ALL -eq 0 ]]; then
        echo "  Sections: $(selected_components_label)"
    elif [[ $SKIP_COMPONENTS_REQUESTED -eq 1 ]]; then
        echo "  Skipping: $(skipped_components_label)"
    fi
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
    fi

    if [[ $failed -gt 0 ]]; then
        log_error "Some operations failed. Please review the output above."
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi

    log_ok "Installation completed successfully!"
    return 0
}

main() {
    local config_submodules_ready=1

    parse_args "$@"

    print_banner

    log_info "Source directory: $SCRIPT_DIR"
    log_info "Target home: $HOME"

    if [[ $INSTALL_ALL -eq 0 ]]; then
        ensure_path_contains_local_bin
        if ! run_best_effort "Selected submodules" init_selected_submodules; then
            config_submodules_ready=0
        fi
        run_best_effort "Selected components" \
            install_selected_components "$config_submodules_ready"
        print_summary
        return $?
    fi

    install_required_tools

    ensure_path_contains_local_bin

    run_best_effort "fd" install_fd
    run_best_effort "lazygit" install_lazygit
    run_best_effort "uv" install_uv
    run_best_effort "mq" install_mq
    install_zsh_stack
    run_best_effort "Node.js and npm" install_nodejs_with_nvm
    run_best_effort "Bun" install_bun

    if run_best_effort "Codex CLI" install_codex_cli; then
        CODEX_CLI_AVAILABLE=1
    fi

    if run_best_effort "Claude Code" \
        install_remote_cli "Claude Code" "claude" "$CLAUDE_CODE_INSTALL_URL" ""; then
        CLAUDE_CODE_AVAILABLE=1
    fi

    run_best_effort "Antigravity CLI" \
        install_remote_cli "Antigravity CLI" "agy" \
        "$ANTIGRAVITY_INSTALL_URL" "$ANTIGRAVITY_INSTALL_SHA256"

    if run_best_effort "agent-deck" \
        install_remote_cli "agent-deck" "agent-deck" \
        "$AGENT_DECK_INSTALL_URL" "$AGENT_DECK_INSTALL_SHA256" \
        --version "$AGENT_DECK_VERSION" --skip-tmux-config --non-interactive; then
        AGENT_DECK_AVAILABLE=1
    fi

    run_best_effort "agent-browser" install_agent_browser
    run_best_effort "ast-grep" install_ast_grep
    run_best_effort "codegraph" install_codegraph
    run_best_effort "tree-sitter CLI" install_tree_sitter_cli

    if component_is_selected "ai"; then
        run_best_effort "Waypost preparation" prepare_waypost_config_switch
        run_best_effort "agent-deck integration" setup_agent_deck_integration
    fi

    # Initialize only submodules required by enabled sections when skipping.
    if [[ $SKIP_COMPONENTS_REQUESTED -eq 1 ]]; then
        if ! run_best_effort "Enabled Git submodules" init_selected_submodules; then
            config_submodules_ready=0
        fi
    else
        if ! run_best_effort "Git submodules" init_submodules; then
            config_submodules_ready=0
        fi
    fi

    if component_is_selected "ai"; then
        run_best_effort "Shared AI agent snapshot" \
            install_shared_ai_agent_snapshot
    fi

    # Install configs
    if component_is_selected "home"; then
        run_best_effort "Home configs" \
            install_home_configs "$config_submodules_ready" "$ZSH_STACK_READY"
    fi
    if component_is_selected "xdg"; then
        run_best_effort "XDG configs" \
            install_xdg_configs "$config_submodules_ready"
    elif component_is_selected "ai"; then
        log_info "Installing AI Agent config..."
        run_best_effort "AI Agent config" install_ai_agent_config
    fi
    if component_is_selected "bin"; then
        run_best_effort "Local bin helpers" install_local_bin_helpers
    fi
    if component_is_selected "ai"; then
        install_snapshot_dependent_ai_configs
    fi
    if component_is_selected "ai-rules"; then
        prepare_ai_rules_waypost_prerequisites
        run_best_effort "AI authorization rules" install_ai_permission_rules
    fi
    if component_is_selected "serena"; then
        run_best_effort "Serena config" install_serena_config
    fi

    # OS-specific handling
    if component_is_selected "xdg"; then
        case "$OS" in
            linux)
                run_best_effort "Linux-specific config" install_linux_specific
                ;;
            macos)
                run_best_effort "macOS-specific config" install_macos_specific
                ;;
            wsl)
                run_best_effort "WSL-specific config" install_wsl_specific
                ;;
        esac
    fi

    # Setup Neovim (important!)
    if component_is_selected "xdg"; then
        run_best_effort "Neovim setup" setup_nvim
    fi

    print_summary
}

# Run only when executed directly; sourcing is useful for focused installer tests.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
