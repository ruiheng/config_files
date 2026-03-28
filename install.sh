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

# Optional integration flags
AGENT_DECK_AVAILABLE=0
AGENT_MAILBOX_MCP_READY=0

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

ensure_path_contains_local_bin() {
    local local_bin="$HOME/.local/bin"

    case ":$PATH:" in
        *":$local_bin:"*)
            log_ok "PATH includes: $local_bin"
            return 0
            ;;
    esac

    log_warn "PATH does not include: $local_bin"
    log_info "Add it to your shell config so helper commands like 'adwf-send-and-wake' are directly runnable"
    log_info "Suggested line:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
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
        tmux
        jq
    )
    local tool_name

    log_info "Checking required CLI tools..."

    for tool_name in "${required_tools[@]}"; do
        ensure_required_command "$tool_name" || return 1
    done

    return 0
}

install_agent_browser() {
    log_info "Checking agent-browser..."

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
            log_ok "Installed agent-browser"
        fi
    else
        log_ok "Found agent-browser"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: agent-browser install"
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

install_agent_mailbox_mcp_runtime() {
    if [[ $AGENT_MAILBOX_MCP_READY -eq 1 ]]; then
        log_ok "agent_mailbox MCP runtime already prepared"
        return 0
    fi

    log_info "Checking agent_mailbox MCP runtime..."

    if ! ensure_required_command "node"; then
        log_error "agent_mailbox MCP requires node"
        return 1
    fi

    if ! ensure_required_command "npm"; then
        log_error "agent_mailbox MCP requires npm"
        return 1
    fi

    local mcp_dir="$SCRIPT_DIR/ai-agent/mcp"
    local lockfile="$mcp_dir/package-lock.json"

    if [[ ! -f "$lockfile" ]]; then
        log_error "Missing agent_mailbox MCP lockfile: $lockfile"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: npm ci --prefix $mcp_dir"
        return 0
    fi

    log_info "Running: npm ci --prefix $mcp_dir"
    if npm ci --prefix "$mcp_dir"; then
        AGENT_MAILBOX_MCP_READY=1
        log_ok "Installed agent_mailbox MCP dependencies"
        return 0
    fi

    log_error "Failed to install agent_mailbox MCP dependencies"
    return 1
}

remove_gemini_legacy_workflow_mailbox_mcp() {
    if ! command -v gemini &>/dev/null; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: gemini mcp remove workflow_mailbox"
        return 0
    fi

    gemini mcp remove workflow_mailbox >/dev/null 2>&1 || true
}

install_gemini_agent_mailbox_mcp() {
    local launcher="$HOME/.local/bin/agent-mailbox-mcp"

    if ! command -v gemini &>/dev/null; then
        log_warn "Skipping Gemini MCP install (gemini not found)"
        return 0
    fi

    remove_gemini_legacy_workflow_mailbox_mcp

    if gemini mcp list 2>/dev/null | grep -Fq "agent_mailbox"; then
        log_ok "Gemini MCP already configured: agent_mailbox"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: gemini mcp add -s user agent_mailbox $launcher"
        return 0
    fi

    if gemini mcp add -s user agent_mailbox "$launcher"; then
        log_ok "Configured Gemini MCP: agent_mailbox"
        return 0
    fi

    log_error "Failed to configure Gemini MCP: agent_mailbox"
    return 1
}

remove_codex_legacy_workflow_mailbox_mcp() {
    if ! command -v codex &>/dev/null; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: codex mcp remove workflow_mailbox"
        return 0
    fi

    codex mcp remove workflow_mailbox >/dev/null 2>&1 || true
}

install_codex_agent_mailbox_mcp() {
    local launcher="$HOME/.local/bin/agent-mailbox-mcp"

    if ! command -v codex &>/dev/null; then
        log_warn "Skipping Codex MCP install (codex not found)"
        return 0
    fi

    remove_codex_legacy_workflow_mailbox_mcp

    if ! codex mcp get agent_mailbox >/dev/null 2>&1; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would run: codex mcp add agent_mailbox -- $launcher"
            return 0
        fi

        if ! codex mcp add agent_mailbox -- "$launcher"; then
            log_error "Failed to configure Codex MCP: agent_mailbox"
            return 1
        fi
        log_ok "Configured Codex MCP: agent_mailbox"
    else
        log_ok "Codex MCP already configured: agent_mailbox"
    fi

    local codex_config="$HOME/.codex/config.toml"
    if [[ ! -f "$codex_config" ]]; then
        log_error "Missing Codex config: $codex_config"
        return 1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would ensure TMUX and AGENTDECK_INSTANCE_ID passthrough in: $codex_config"
        return 0
    fi

    if perl -0pi -e '
        my @lines = split /\n/, $_, -1;
        my @out = ();
        my $found = 0;
        my $in_section = 0;
        my $inserted = 0;

        for my $line (@lines) {
          if ($line =~ /^\[mcp_servers\.agent_mailbox\]$/) {
            $found = 1;
            $in_section = 1;
            $inserted = 0;
            push @out, $line;
            next;
          }

          if ($in_section && $line =~ /^\[/) {
            push @out, q{env_vars = [ "TMUX", "AGENTDECK_INSTANCE_ID" ]} unless $inserted;
            $inserted = 1;
            $in_section = 0;
          }

          next if $in_section && $line =~ /^\s*env_vars\s*=/;
          push @out, $line;
        }

        if ($in_section && !$inserted) {
          push @out, q{env_vars = [ "TMUX", "AGENTDECK_INSTANCE_ID" ]};
        }

        die "agent_mailbox section not found\n" unless $found;

        $_ = join("\n", @out);
        $_ .= "\n" unless $_ =~ /\n\z/;
    ' "$codex_config" && perl -0ne '
        exit(
          /\[mcp_servers\.agent_mailbox\][\s\S]*?^env_vars\s*=\s*\[\s*"TMUX"\s*,\s*"AGENTDECK_INSTANCE_ID"\s*\]/m
            ? 0
            : 1
        );
    ' "$codex_config"; then
        log_ok "Ensured Codex MCP TMUX and AGENTDECK_INSTANCE_ID passthrough: agent_mailbox"
        return 0
    fi

    log_error "Failed to update Codex MCP TMUX and AGENTDECK_INSTANCE_ID passthrough: agent_mailbox"
    return 1
}

remove_claude_legacy_workflow_mailbox_mcp() {
    if ! command -v claude &>/dev/null; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: claude mcp remove -s user workflow_mailbox"
        return 0
    fi

    claude mcp remove -s user workflow_mailbox >/dev/null 2>&1 || true
}

install_claude_agent_mailbox_mcp() {
    local launcher="$HOME/.local/bin/agent-mailbox-mcp"

    if ! command -v claude &>/dev/null; then
        log_warn "Skipping Claude MCP install (claude not found)"
        return 0
    fi

    remove_claude_legacy_workflow_mailbox_mcp

    if claude mcp list 2>/dev/null | grep -Fq "agent_mailbox"; then
        log_ok "Claude MCP already configured: agent_mailbox"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: claude mcp add -s user agent_mailbox -- $launcher"
        return 0
    fi

    if claude mcp add -s user agent_mailbox -- "$launcher"; then
        log_ok "Configured Claude MCP: agent_mailbox"
        return 0
    fi

    log_error "Failed to configure Claude MCP: agent_mailbox"
    return 1
}

remove_legacy_agent_mailbox_launcher() {
    local legacy_launcher="$HOME/.local/bin/adwf-mailbox-mcp"

    if [[ ! -e "$legacy_launcher" ]] && [[ ! -L "$legacy_launcher" ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would remove legacy launcher: $legacy_launcher"
        return 0
    fi

    rm -f "$legacy_launcher"
    log_info "Removed legacy launcher: $legacy_launcher"
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
    if ! command -v agent-deck &>/dev/null; then
        AGENT_DECK_AVAILABLE=0
        log_warn "agent-deck not found; skipping agent-deck related skills and policy/rule links"
        return 0
    fi

    AGENT_DECK_AVAILABLE=1
    log_ok "Found agent-deck"

    if ! check_agent_deck_prerequisites; then
        return 1
    fi

    local has_hooks_cmd=0
    if agent-deck hooks status >/dev/null 2>&1; then
        has_hooks_cmd=1
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ $has_hooks_cmd -eq 1 ]]; then
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

migrate_legacy_symlink_source() {
    local dst="$1"
    local legacy_src="$2"
    local new_src="$3"

    # Only migrate existing symlinks that still point to the old source path.
    if [[ ! -L "$dst" ]]; then
        return 0
    fi

    local current_target
    current_target="$(readlink "$dst")"
    if [[ "$current_target" != /* ]]; then
        current_target="$(cd "$(dirname "$dst")/$current_target" 2>/dev/null && pwd || echo "$current_target")"
    fi

    local legacy_src_normalized
    if [[ -e "$legacy_src" ]]; then
        legacy_src_normalized="$(cd "$(dirname "$legacy_src")" 2>/dev/null && pwd)/$(basename "$legacy_src")"
    else
        # Keep absolute legacy path as-is so broken legacy links can still be migrated.
        legacy_src_normalized="$legacy_src"
    fi

    if [[ "$current_target" != "$legacy_src_normalized" ]]; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would migrate legacy symlink: $dst -> $new_src"
        return 0
    fi

    rm "$dst"
    log_info "Removed legacy symlink: $dst"
}

install_home_configs() {
    log_info "Installing home directory dotfiles..."

    # Shell configs
    link_file "bashrc" "$HOME/.bashrc"
    link_file "zshrc" "$HOME/.zshrc"

    # Screen config
    link_file "screenrc" "$HOME/.screenrc"

    # Tmux config (file in tmux/ directory)
    link_file "tmux/tmux.conf" "$HOME/.tmux.conf"
    link_file "tmux/plugins/tpm" "$HOME/.tmux/plugins/tpm"

    # Git config (OS-specific)
    case "$OS" in
        linux|wsl|macos)
            migrate_legacy_symlink_source "$HOME/.gitconfig" "$SCRIPT_DIR/gitconfig.ruiheng.unix" "$SCRIPT_DIR/gitconfig.unix"
            link_file "gitconfig.unix" "$HOME/.gitconfig"
            ;;
        windows)
            migrate_legacy_symlink_source "$HOME/.gitconfig" "$SCRIPT_DIR/gitconfig.ruiheng.win" "$SCRIPT_DIR/gitconfig.win"
            link_file "gitconfig.win" "$HOME/.gitconfig"
            ;;
    esac

    # Global gitignore
    migrate_legacy_symlink_source "$HOME/.gitignore" "$SCRIPT_DIR/.gitignore" "$SCRIPT_DIR/gitignore"
    link_file "gitignore" "$HOME/.gitignore"
    link_file "git-completion.sh" "$HOME/.git-completion.sh"
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

                if is_agent_deck_related_skill "$skill_name" && [[ $AGENT_DECK_AVAILABLE -eq 0 ]]; then
                    log_warn "Skipping $tool_name skill '$skill_name' (agent-deck not installed)"
                    skipped=$((skipped + 1))
                    continue
                fi

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
    # CLAUDE.md uses @modules/* relative imports.
    link_file "ai-agent/modules" "$claude_dir/modules"

    # Link skills individually (required by Claude Code)
    install_claude_skills

    # Install workflow permission init script to ~/.local/bin
    local bin_dir="$HOME/.local/bin"
    if [[ ! -d "$bin_dir" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_dry "Would create directory: $bin_dir"
        else
            mkdir -p "$bin_dir"
            log_info "Created directory: $bin_dir"
        fi
    fi
    link_file "ai-agent/skills/agent-deck-workflow/scripts/agent-deck-workflow-init-permissions.sh" "$bin_dir/agent-deck-workflow-init-permissions"
    link_file "ai-agent/skills/agent-deck-workflow/scripts/adwf-send-and-wake.sh" "$bin_dir/adwf-send-and-wake"
    link_file "ai-agent/mcp/agent-mailbox-mcp" "$bin_dir/agent-mailbox-mcp"
    remove_legacy_agent_mailbox_launcher
    if ! install_agent_mailbox_mcp_runtime; then
        log_error "Failed to prepare agent_mailbox MCP runtime for Claude"
        return 1
    fi
    install_claude_agent_mailbox_mcp

    # Link statusline script
    link_file "ai-agent/claude/statusline-command.sh" "$claude_dir/statusline-command.sh"
}

cleanup_gemini_duplicate_skill_links() {
    local gemini_skills_dir="$1"
    local src_skills_dir="$SCRIPT_DIR/ai-agent/skills"

    if [[ ! -d "$gemini_skills_dir" ]]; then
        return 0
    fi

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
        log_warn "Skipping Gemini skill links under $gemini_skills_dir to avoid duplicate skill conflicts"
        cleanup_gemini_duplicate_skill_links "$gemini_skills_dir"
        return 0
    fi

    install_skills_individually "Gemini CLI" "$HOME/.gemini/skills"
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

    # Link the main GEMINI.md file
    link_file "ai-agent/GEMINI.md" "$gemini_dir/GEMINI.md"
    # GEMINI.md uses @modules/* relative imports.
    link_file "ai-agent/modules" "$gemini_dir/modules"

    # Link skills individually for reliability
    install_gemini_skills

    # Link shell policy rules for workflow automation approvals
    if [[ $AGENT_DECK_AVAILABLE -eq 1 ]]; then
        migrate_legacy_symlink_source "$gemini_dir/policies/agent-deck-workflow.toml" "$SCRIPT_DIR/ai-agent/.gemini/policies/agent-deck-workflow.toml" "$SCRIPT_DIR/ai-agent/gemini/policies/agent-deck-workflow.toml"
        link_file "ai-agent/gemini/policies/agent-deck-workflow.toml" "$gemini_dir/policies/agent-deck-workflow.toml"
    else
        log_warn "Skipping Gemini agent-deck workflow policy link (agent-deck not installed)"
    fi

    if ! install_agent_mailbox_mcp_runtime; then
        log_error "Failed to prepare agent_mailbox MCP runtime for Gemini"
        return 1
    fi

    install_gemini_agent_mailbox_mcp
}

install_codex_skills() {
    install_skills_individually "Codex" "$HOME/.codex/skills"
}

install_opencode_skills() {
    install_skills_individually "OpenCode" "$HOME/.config/opencode/skills"
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

    # Link Codex escalation rules for workflow automation approvals
    if [[ $AGENT_DECK_AVAILABLE -eq 1 ]]; then
        migrate_legacy_symlink_source "$codex_dir/rules/agent-deck-workflow.rules" "$SCRIPT_DIR/ai-agent/.codex/rules/agent-deck-workflow.rules" "$SCRIPT_DIR/ai-agent/codex/rules/agent-deck-workflow.rules"
        link_file "ai-agent/codex/rules/agent-deck-workflow.rules" "$codex_dir/rules/agent-deck-workflow.rules"
    else
        log_warn "Skipping Codex agent-deck workflow rule link (agent-deck not installed)"
    fi

    if ! install_agent_mailbox_mcp_runtime; then
        log_error "Failed to prepare agent_mailbox MCP runtime for Codex"
        return 1
    fi

    install_codex_agent_mailbox_mcp
}

remove_opencode_legacy_workflow_mailbox_mcp() {
    if ! command -v opencode &>/dev/null; then
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: opencode mcp remove workflow_mailbox"
        return 0
    fi

    opencode mcp remove workflow_mailbox >/dev/null 2>&1 || true
}

install_opencode_agent_mailbox_mcp() {
    local launcher="$HOME/.local/bin/agent-mailbox-mcp"

    if ! command -v opencode &>/dev/null; then
        log_warn "Skipping OpenCode MCP install (opencode not found)"
        return 0
    fi

    remove_opencode_legacy_workflow_mailbox_mcp

    if opencode mcp list 2>/dev/null | grep -Fq "agent_mailbox"; then
        log_ok "OpenCode MCP already configured: agent_mailbox"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Would run: opencode mcp add agent_mailbox -- $launcher"
        return 0
    fi

    if opencode mcp add agent_mailbox -- "$launcher"; then
        log_ok "Configured OpenCode MCP: agent_mailbox"
        return 0
    fi

    log_error "Failed to configure OpenCode MCP: agent_mailbox"
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

    # Link the main AGENTS.md file (OpenCode uses AGENTS.md natively)
    link_file "ai-agent/AGENTS.md" "$opencode_dir/AGENTS.md"
    # AGENTS.md uses @modules/* relative imports.
    link_file "ai-agent/modules" "$opencode_dir/modules"

    # Link skills individually for OpenCode
    install_opencode_skills

    if ! install_agent_mailbox_mcp_runtime; then
        log_error "Failed to prepare agent_mailbox MCP runtime for OpenCode"
        return 1
    fi

    install_opencode_agent_mailbox_mcp
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

    if ! install_agent_browser; then
        exit 1
    fi

    if ! setup_agent_deck_integration; then
        exit 1
    fi

    # Initialize git submodules first
    init_submodules

    # Install configs
    install_home_configs
    install_xdg_configs
    install_claude_config
    install_gemini_config
    install_codex_config
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

# Run main function with all arguments
main "$@"
