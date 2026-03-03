#!/usr/bin/env bash
#
# Initialize agent-deck-workflow permissions for AI agent tools
# Configures Claude Code, Codex, and Gemini CLI with required permissions
#
# Usage: ./init-workflow-permissions.sh [project-dir]
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Determine project directory
PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

log_info "Initializing agent-deck-workflow permissions for: $PROJECT_DIR"

# =============================================================================
# Claude Code Configuration
# =============================================================================

configure_claude() {
    local claude_dir="$PROJECT_DIR/.claude"
    local settings_file="$claude_dir/settings.json"

    log_info "Configuring Claude Code permissions..."

    mkdir -p "$claude_dir"

    if [[ -f "$settings_file" ]]; then
        log_info "Merging permissions into existing settings.json"

        # Backup existing file
        cp "$settings_file" "$settings_file.backup.$(date +%Y%m%d_%H%M%S)"

        # Use jq to merge permissions
        if command -v jq &>/dev/null; then
            local new_permissions='[
              "Bash(agent-deck)",
              "Bash(agent-deck *)",
              "Bash(*/.claude/skills/agent-deck-workflow/scripts/dispatch-control-message.sh *)",
              "Write(/.agent-artifacts/**)"
            ]'

            jq --argjson perms "$new_permissions" '
                .permissions.allow = ((.permissions.allow // []) + $perms | unique)
            ' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"

            log_ok "Merged permissions into $settings_file"
        else
            log_warn "jq not found, cannot merge automatically"
            log_info "Please manually add these permissions to $settings_file:"
            cat << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(agent-deck)",
      "Bash(agent-deck *)",
      "Bash(*/.claude/skills/agent-deck-workflow/scripts/dispatch-control-message.sh *)",
      "Write(/.agent-artifacts/**)"
    ]
  }
}
EOF
            return 1
        fi
    else
        log_info "Creating new settings.json"
        cat > "$settings_file" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(agent-deck)",
      "Bash(agent-deck *)",
      "Bash(*/.claude/skills/agent-deck-workflow/scripts/dispatch-control-message.sh *)",
      "Write(/.agent-artifacts/**)"
    ]
  }
}
EOF
        log_ok "Created $settings_file"
    fi
}

# =============================================================================
# Codex Configuration
# =============================================================================

configure_codex() {
    local codex_dir="$PROJECT_DIR/.codex"
    local rules_dir="$codex_dir/rules"
    local rules_file="$rules_dir/agent-deck-workflow.rules"

    log_info "Configuring Codex escalation rules..."

    mkdir -p "$rules_dir"

    cat > "$rules_file" << 'EOF'
# Agent Deck Workflow - Auto-approve rules
# These commands are required for the workflow to function

# Allow all agent-deck commands
prefix_rule(
    pattern = ["agent-deck"],
    decision = "allow",
    justification = "Agent deck workflow commands",
    match = [
        "agent-deck",
        "agent-deck status",
        "agent-deck session current",
        "agent-deck workflow dispatch",
    ],
)

# Allow workflow dispatch script
prefix_rule(
    pattern = ["bash"],
    decision = "allow",
    justification = "Workflow dispatch script",
    match = [
        "bash ~/.claude/skills/agent-deck-workflow/scripts/dispatch-control-message.sh",
    ],
)

# Note: Codex file write permissions are controlled separately
# and may still require manual approval for .agent-artifacts writes
EOF

    log_ok "Created $rules_file"
    log_warn "Note: Codex file write permissions may still require manual approval"
}

# =============================================================================
# Gemini CLI Configuration
# =============================================================================

configure_gemini() {
    local gemini_dir="$PROJECT_DIR/.gemini"
    local policies_dir="$gemini_dir/policies"
    local policy_file="$policies_dir/agent-deck-workflow.toml"

    log_info "Configuring Gemini CLI shell policies..."

    mkdir -p "$policies_dir"

    cat > "$policy_file" << 'EOF'
# Agent Deck Workflow - Shell policy rules
# Auto-approve commands required for the workflow

[[rules]]
pattern = "^agent-deck( .*)?$"
action = "allow"
description = "Agent deck commands"

[[rules]]
pattern = ".*/\\.claude/skills/agent-deck-workflow/scripts/dispatch-control-message\\.sh .*"
action = "allow"
description = "Workflow dispatch script"

# Note: Gemini file write permissions are controlled separately
# and may still require approval for .agent-artifacts writes
EOF

    log_ok "Created $policy_file"
    log_warn "Note: Gemini file write permissions may still require manual approval"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo "========================================"
    echo "  Agent Deck Workflow Permission Setup"
    echo "========================================"
    echo ""

    # Check if agent-deck is available
    if ! command -v agent-deck &>/dev/null; then
        log_warn "agent-deck not found in PATH"
        log_info "Install it from: https://github.com/your-org/agent-deck"
        echo ""
    fi

    # Configure each tool
    configure_claude
    echo ""
    configure_codex
    echo ""
    configure_gemini

    echo ""
    echo "========================================"
    echo "  Configuration Complete"
    echo "========================================"
    echo ""
    log_ok "Permissions configured for agent-deck-workflow"
    echo ""
    log_info "Next steps:"
    echo "  1. Restart your AI agent session to load new permissions"
    echo "  2. Run 'agent-deck workflow init' to set up workflow state"
    echo "  3. Start using /agent-deck-workflow skill"
    echo ""
}

main "$@"
