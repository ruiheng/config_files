#!/usr/bin/env bash
#
# Config Files Installation Script
# Creates symbolic links for all configuration files
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

# Command line flags
DRY_RUN=0
FORCE=0
INTERACTIVE=0
USE_COLOR=1

# Interactive mode defaults (for 'all' responses)
ALL_SKIP=0
ALL_BACKUP=0
ALL_REPLACE=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters for summary
declare -i linked=0 skipped=0 failed=0 backed_up=0

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
        return 1
    fi
}

# Create a symbolic link
# $1: source (relative to SCRIPT_DIR)
# $2: target (absolute path)
link_file() {
    local src="$SCRIPT_DIR/$1"
    local dst="$2"

    # Check if source exists
    if [[ ! -e "$src" ]]; then
        log_error "Source does not exist: $src"
        failed=$((failed + 1))
        return 1
    fi

    # Create parent directory if needed
    local dst_dir
    dst_dir="$(dirname "$dst")"
    if [[ ! -d "$dst_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $dst_dir"
        else
            mkdir -p "$dst_dir"
            log_info "Created directory: $dst_dir"
        fi
    fi

    # Check if target already exists
    if [[ -e "$dst" ]] || [[ -L "$dst" ]]; then
        if [[ -L "$dst" ]]; then
            # It's already a symlink
            local current_target
            current_target="$(readlink "$dst")"
            # Convert relative target to absolute for comparison
            if [[ "$current_target" != /* ]]; then
                current_target="$(cd "$(dirname "$dst")/$current_target" 2>/dev/null && pwd || echo "$current_target")"
            fi
            local src_normalized
            src_normalized="$(cd "$(dirname "$src")" 2>/dev/null && pwd)/$(basename "$src")"

            if [[ "$current_target" == "$src_normalized" ]]; then
                log_warn "Already linked: $dst"
                skipped=$((skipped + 1))
                return 0
            else
                # Different symlink - handle based on mode
                if [[ $FORCE -eq 1 ]]; then
                    if [[ $DRY_RUN -eq 1 ]]; then
                        log_dry "Would replace symlink: $dst"
                    else
                        rm "$dst"
                        log_info "Removed old symlink: $dst"
                    fi
                elif [[ $INTERACTIVE -eq 1 ]]; then
                    local action
                    prompt_user "$dst"
                    action=$?
                    case "$action" in
                        0) # skip
                            skipped=$((skipped + 1))
                            return 0
                            ;;
                        1) # backup
                            if ! backup_item "$dst"; then
                                failed=$((failed + 1))
                                return 1
                            fi
                            ;;
                        2) # force replace
                            rm "$dst"
                            log_info "Removed old symlink: $dst"
                            ;;
                        3) # cancel
                            log_info "Installation cancelled by user"
                            exit 0
                            ;;
                    esac
                else
                    log_warn "Different symlink exists: $dst -> $(readlink "$dst")"
                    skipped=$((skipped + 1))
                    return 0
                fi
            fi
        else
            # It's a regular file or directory
            if [[ $FORCE -eq 1 ]]; then
                if ! backup_item "$dst"; then
                    failed=$((failed + 1))
                    return 1
                fi
                # If dry run, we just logged, don't continue to actual link creation
                if [[ $DRY_RUN -eq 1 ]]; then
                    log_dry "Would link: $dst -> $src"
                    linked=$((linked + 1))
                    return 0
                fi
            elif [[ $INTERACTIVE -eq 1 ]]; then
                local action
                prompt_user "$dst"
                action=$?
                case "$action" in
                    0) # skip
                        skipped=$((skipped + 1))
                        return 0
                        ;;
                    1) # backup
                        if ! backup_item "$dst"; then
                            failed=$((failed + 1))
                            return 1
                        fi
                        ;;
                    2) # force replace
                        rm -rf "$dst"
                        log_info "Removed existing file: $dst"
                        ;;
                    3) # cancel
                        log_info "Installation cancelled by user"
                        exit 0
                        ;;
                esac
            else
                log_warn "File exists (not a symlink): $dst"
                skipped=$((skipped + 1))
                return 0
            fi
        fi
    fi

    # Create the symlink
    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would link: $dst -> $src"
        linked=$((linked + 1))
        return 0
    fi

    if ln -s "$src" "$dst"; then
        log_ok "Linked: $dst -> $src"
        linked=$((linked + 1))
        return 0
    else
        log_error "Failed to link: $dst"
        failed=$((failed + 1))
        return 1
    fi
}

# =============================================================================
# OS Detection
# =============================================================================

detect_os() {
    local os="unknown"

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
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

# =============================================================================
# Installation Functions
# =============================================================================

install_home_configs() {
    log_info "Installing home directory dotfiles..."

    # Shell configs
    link_file "bashrc" "$HOME/.bashrc"
    link_file "zshrc" "$HOME/.zshrc"

    # Screen config
    link_file "screenrc" "$HOME/.screenrc"

    # Tmux config (file in tmux/ directory)
    link_file "tmux/tmux.conf" "$HOME/.tmux.conf"

    # Git config (OS-specific)
    case "$OS" in
        linux|wsl|macos)
            link_file "gitconfig.ruiheng.unix" "$HOME/.gitconfig"
            ;;
        windows)
            link_file "gitconfig.ruiheng.win" "$HOME/.gitconfig"
            ;;
    esac
}

install_xdg_configs() {
    log_info "Installing XDG config directory files..."

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"

    # Window managers and related (whole directories)
    link_file "i3" "$config_dir/i3"
    link_file "niri" "$config_dir/niri"
    link_file "sway" "$config_dir/sway"
    link_file "waybar" "$config_dir/waybar"

    # Terminal and file manager
    link_file "ranger" "$config_dir/ranger"

    # Application configs (whole directories)
    link_file "nvim" "$config_dir/nvim"
    link_file "systemd" "$config_dir/systemd"

    # Individual files
    link_file "fourmolu.yaml" "$config_dir/fourmolu.yaml"

    # AI-related configs
    link_file "ai-agent" "$config_dir/ai-agent"

    # GRC (Generic Colouriser)
    link_file "grc" "$config_dir/grc"
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
                        rm -rf "$skills_dir"
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
                        rm -rf "$skills_dir"
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

install_skills_individually() {
    local tool_name="$1"
    local tool_skills_dir="$2"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    log_info "Installing $tool_name skills (individually)..."

    if ! prepare_skills_target_dir "$tool_name" "$tool_skills_dir"; then
        return 0
    fi

    if [[ -d "$src_skills_dir" ]]; then
        for skill_dir in "$src_skills_dir"/*; do
            if [[ -d "$skill_dir" ]]; then
                local skill_name
                skill_name=$(basename "$skill_dir")
                link_file "ai-agent/skills/$skill_name" "$tool_skills_dir/$skill_name"
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

    # Link the main CLAUDE.md file
    link_file "ai-agent/CLAUDE.md" "$claude_dir/CLAUDE.md"

    # Link skills individually (required by Claude Code)
    install_claude_skills

    # Note: settings.local.json contains machine-specific permissions
    # and is not automatically linked. Copy manually if needed:
    #   cp .claude/settings.local.json ~/.claude/
}

install_codex_skills() {
    install_skills_individually "Codex" "$HOME/.codex/skills"
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
        link_file ".serena/memories" "$serena_dir/memories"
    fi

    if [[ -f "$SCRIPT_DIR/.serena/project.yml" ]]; then
        link_file ".serena/project.yml" "$serena_dir/project.yml"
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
    if [[ "$(printf '%s\n' "0.9" "$nvim_version" | sort -V | head -n1)" != "0.9" ]]; then
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

    # The nvim config is already linked in install_xdg_configs
    # Just verify it exists
    local nvim_config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
    if [[ -L "$nvim_config" ]]; then
        log_ok "Neovim config linked at: $nvim_config"
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

    log_info "Note: Some Linux-specific configs (i3, sway, niri) won't apply on macOS"
}

install_wsl_specific() {
    log_info "Applying WSL-specific configurations..."

    log_info "Note: Window manager configs (i3, sway, niri, waybar) won't work in WSL"
}

# =============================================================================
# Main
# =============================================================================

print_banner() {
    echo ""
    echo "========================================"
    echo "  Config Files Installation Script"
    echo "  OS detected: $OS"
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

    # Initialize git submodules first
    init_submodules

    # Install configs
    install_home_configs
    install_xdg_configs
    install_claude_config
    install_codex_config
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

# Run main function with all arguments
main "$@"
