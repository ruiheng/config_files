#!/usr/bin/env bash
#
# Initialize agent-deck-workflow permissions for AI agent tools
# Configures Claude Code, Codex, and Gemini CLI with required permissions
#
# Usage: ./init-workflow-permissions.sh [project-dir]
#
# Maintenance rules:
# - Any generated path under HOME must be emitted in both tilde and absolute forms.
# - Never emit rules based on the current repository path; use installed paths only.
#

set -euo pipefail

INSTALLED_SKILLS_DIR="$HOME/.config/ai-agent/skills"
INSTALLED_SKILLS_DIR_TILDE="~/.config/ai-agent/skills"
INSTALLED_LOCAL_BIN="$HOME/.local/bin"
INSTALLED_LOCAL_BIN_TILDE="~/.local/bin"

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

resolve_jq_cmd() {
    local candidate

    for candidate in jq.exe jq; do
        if ! command -v "$candidate" &>/dev/null; then
            continue
        fi
        if "$candidate" --version &>/dev/null; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

show_usage() {
    cat <<'EOF'
Initialize agent-deck-workflow permissions for AI agent tools.

Usage:
  agent-deck-workflow-init-permissions.sh [project-dir]

Options:
  -h, --help    Show help
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
fi

# Determine project directory
PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

log_info "Initializing agent-deck-workflow permissions for: $PROJECT_DIR"

resolve_abs_path() {
    local base_dir="$1"
    local maybe_relative_path="$2"

    if [[ -z "$maybe_relative_path" ]]; then
        return 1
    fi

    if [[ "$maybe_relative_path" == /* ]]; then
        printf '%s\n' "$maybe_relative_path"
    else
        (cd "$base_dir" && cd "$maybe_relative_path" && pwd -P)
    fi
}

path_is_within() {
    local candidate="$1"
    local parent="$2"

    case "$candidate" in
        "$parent"|"$parent"/*) return 0 ;;
        *) return 1 ;;
    esac
}

configure_codex_worktree_writable_roots() {
    local codex_dir="$1"
    local config_file="$codex_dir/config.toml"
    local git_common_dir_raw=""
    local git_common_dir=""

    if [[ "$(uname -s)" != "Linux" ]]; then
        log_info "Skipping Codex worktree writable root detection on non-Linux host"
        return 0
    fi

    if ! command -v git &>/dev/null; then
        log_warn "git not found; skipping Codex worktree writable root detection"
        return 0
    fi

    git_common_dir_raw="$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
    if [[ -z "$git_common_dir_raw" ]]; then
        log_info "Project is not a git repository; no extra Codex writable roots needed"
        return 0
    fi

    git_common_dir="$(resolve_abs_path "$PROJECT_DIR" "$git_common_dir_raw" 2>/dev/null || true)"
    if [[ -z "$git_common_dir" ]]; then
        log_warn "Failed to resolve git common dir '$git_common_dir_raw'; skipping Codex writable root update"
        return 0
    fi

    if path_is_within "$git_common_dir" "$PROJECT_DIR"; then
        log_info "Git common dir is inside project; no extra Codex writable roots needed"
        return 0
    fi

    mkdir -p "$codex_dir"

    if ! command -v uv &>/dev/null; then
        log_warn "uv not found; cannot safely edit $config_file as TOML"
        log_info "Add this path manually under [sandbox_workspace_write].writable_roots: $git_common_dir"
        return 0
    fi

    if [[ ! -f "$config_file" ]]; then
        printf '%s\n' '[sandbox_workspace_write]' > "$config_file"
        printf '%s\n' 'writable_roots = []' >> "$config_file"
    fi

    if ! uv run --with tomlkit python - "$config_file" "$git_common_dir" <<'PY2'
from pathlib import Path
import sys
import tomlkit

config_path, git_common_dir = sys.argv[1:]
path = Path(config_path)
doc = tomlkit.parse(path.read_text())

table = doc.get("sandbox_workspace_write")
if table is None or not isinstance(table, tomlkit.items.Table):
    table = tomlkit.table()
    doc["sandbox_workspace_write"] = table

roots = table.get("writable_roots")
if roots is None or not isinstance(roots, tomlkit.items.Array):
    roots = tomlkit.array().multiline(True)
    table["writable_roots"] = roots
else:
    roots.multiline(True)

existing = [item for item in roots]
if git_common_dir not in existing:
    roots.append(git_common_dir)

path.write_text(tomlkit.dumps(doc))
PY2
    then
        log_warn "uv/tomlkit edit failed for $config_file"
        log_info "Add this path manually under [sandbox_workspace_write].writable_roots: $git_common_dir"
        return 0
    fi

    log_ok "Configured Codex writable roots for external git metadata: $git_common_dir"
}

# =============================================================================
# Claude Code Configuration
# =============================================================================

configure_claude() {
    local claude_dir="$PROJECT_DIR/.claude"
    local settings_file="$claude_dir/settings.json"
    local installed_skills_read_permission_tilde="Read(${INSTALLED_SKILLS_DIR_TILDE}/**)"
    local installed_skills_read_permission_abs="Read(${INSTALLED_SKILLS_DIR}/**)"
    local git_readonly_permissions_json
    local script_name

    git_readonly_permissions_json=$(cat <<'EOF'
  "Bash(git diff)",
  "Bash(git diff *)",
  "Bash(git show)",
  "Bash(git show *)",
  "Bash(git status)",
  "Bash(git status *)",
  "Bash(git log)",
  "Bash(git log *)",
  "Bash(git rev-parse)",
  "Bash(git rev-parse *)",
EOF
)

    log_info "Configuring Claude Code permissions..."

    mkdir -p "$claude_dir"

    if [[ -f "$settings_file" ]]; then
        log_info "Merging permissions into existing settings.json"

        # Backup existing file
        cp "$settings_file" "$settings_file.backup.$(date +%Y%m%d_%H%M%S)"

        local new_permissions
        new_permissions=$(cat <<EOF
[
  "Bash(agent-deck)",
  "Bash(agent-deck *)",
  "Bash(agent-mailbox)",
  "Bash(agent-mailbox *)",
  "Bash(jq)",
  "Bash(jq *)",
$git_readonly_permissions_json
  "Bash(adwf *)",
  "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf *)",
  "Bash(${INSTALLED_LOCAL_BIN}/adwf *)",
  "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf.cmd *)",
  "Bash(${INSTALLED_LOCAL_BIN}/adwf.cmd *)",
  "$installed_skills_read_permission_tilde",
  "$installed_skills_read_permission_abs",
  "Write(/.agent-artifacts/**)"
]
EOF
)

        # Use jq to merge permissions, or Node when jq is not executable in Git Bash.
        local jq_cmd
        if jq_cmd="$(resolve_jq_cmd)"; then
            "$jq_cmd" --argjson perms "$new_permissions" '
                .permissions.allow = ((.permissions.allow // []) + $perms | unique)
            ' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"

            log_ok "Merged permissions into $settings_file"
        elif command -v node &>/dev/null; then
            PERMS_JSON="$new_permissions" node - "$settings_file" <<'NODE'
const fs = require("node:fs");

const settingsFile = process.argv[2];
const permissions = JSON.parse(process.env.PERMS_JSON || "[]");
const settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));

settings.permissions ||= {};
const existing = Array.isArray(settings.permissions.allow)
  ? settings.permissions.allow
  : [];
settings.permissions.allow = Array.from(new Set([...existing, ...permissions])).sort();

fs.writeFileSync(settingsFile, `${JSON.stringify(settings, null, 2)}\n`);
NODE

            log_ok "Merged permissions into $settings_file"
        else
            log_warn "jq/node not found, cannot merge automatically"
            log_info "Please manually add these permissions to $settings_file:"
            cat <<EOF
{
  "permissions": {
    "allow": [
      "Bash(agent-deck)",
      "Bash(agent-deck *)",
      "Bash(agent-mailbox)",
      "Bash(agent-mailbox *)",
      "Bash(jq)",
      "Bash(jq *)",
$git_readonly_permissions_json
      "Bash(adwf *)",
      "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf *)",
      "Bash(${INSTALLED_LOCAL_BIN}/adwf *)",
      "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf.cmd *)",
      "Bash(${INSTALLED_LOCAL_BIN}/adwf.cmd *)",
      "$installed_skills_read_permission_tilde",
      "$installed_skills_read_permission_abs",
      "Write(/.agent-artifacts/**)"
    ]
  }
}
EOF
            return 1
        fi
    else
        log_info "Creating new settings.json"
        cat > "$settings_file" <<EOF
{
  "permissions": {
    "allow": [
      "Bash(agent-deck)",
      "Bash(agent-deck *)",
      "Bash(agent-mailbox)",
      "Bash(agent-mailbox *)",
      "Bash(jq)",
      "Bash(jq *)",
$git_readonly_permissions_json
      "Bash(adwf *)",
      "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf *)",
      "Bash(${INSTALLED_LOCAL_BIN}/adwf *)",
      "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf.cmd *)",
      "Bash(${INSTALLED_LOCAL_BIN}/adwf.cmd *)",
      "$installed_skills_read_permission_tilde",
      "$installed_skills_read_permission_abs",
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

    cat > "$rules_file" << EOF
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

# Allow all agent-mailbox commands
prefix_rule(
    pattern = ["agent-mailbox"],
    decision = "allow",
    justification = "Mailbox workflow transport commands",
)

# Allow shell formatting helper used in workflow wrappers
prefix_rule(
    pattern = ["printf"],
    decision = "allow",
    justification = "Shell printf helper commands",
)

# Allow jq for JSON inspection and transformation in workflow scripts
prefix_rule(
    pattern = ["jq"],
    decision = "allow",
    justification = "jq JSON processing commands",
)

prefix_rule(
    pattern = ["adwf"],
    decision = "allow",
    justification = "Agent Deck workflow dispatcher",
)

prefix_rule(
    pattern = ["$INSTALLED_LOCAL_BIN_TILDE/adwf.cmd"],
    decision = "allow",
    justification = "Agent Deck workflow dispatcher (installed local bin, tilde)",
)

prefix_rule(
    pattern = ["$INSTALLED_LOCAL_BIN/adwf.cmd"],
    decision = "allow",
    justification = "Agent Deck workflow dispatcher (installed local bin, absolute)",
)

prefix_rule(
    pattern = ["$INSTALLED_LOCAL_BIN_TILDE/adwf"],
    decision = "allow",
    justification = "Agent Deck workflow dispatcher (installed local bin, tilde)",
)

prefix_rule(
    pattern = ["$INSTALLED_LOCAL_BIN/adwf"],
    decision = "allow",
    justification = "Agent Deck workflow dispatcher (installed local bin, absolute)",
)
EOF

    cat >> "$rules_file" << 'EOF'

# Note: Codex file write permissions are controlled separately
# and may still require manual approval for .agent-artifacts writes
EOF

    log_ok "Created $rules_file"
    configure_codex_worktree_writable_roots "$codex_dir"
    log_info "Included installed workflow script paths in tilde and absolute forms"
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
# Agent Deck Workflow - Gemini policy rules

[[rule]]
name = "allow_agent_deck_cli"
enabled = true
decision = "allow"
toolName = "run_shell_command"
commandPrefix = ["agent-deck"]
priority = 950
modes = ["default", "autoEdit", "yolo"]

[[rule]]
name = "allow_agent_mailbox_cli"
enabled = true
decision = "allow"
toolName = "run_shell_command"
commandPrefix = ["agent-mailbox"]
priority = 950
modes = ["default", "autoEdit", "yolo"]

[[rule]]
name = "allow_agent_mailbox_mcp"
enabled = true
decision = "allow"
toolName = "*"
mcpName = "agent-mailbox"
priority = 950
modes = ["default", "autoEdit", "yolo"]

[[rule]]
name = "allow_agent_deck_workflow_dispatch"
enabled = true
decision = "allow"
toolName = "run_shell_command"
commandPrefix = ["adwf"]
priority = 950
modes = ["default", "autoEdit", "yolo"]

[[rule]]
name = "allow_agent_deck_workflow_dispatch_cmd"
enabled = true
decision = "allow"
toolName = "run_shell_command"
commandPrefix = ["~/.local/bin/adwf.cmd"]
priority = 950
modes = ["default", "autoEdit", "yolo"]

[[rule]]
name = "allow_agent_deck_workflow_dispatch_local_bin"
enabled = true
decision = "allow"
toolName = "run_shell_command"
commandPrefix = ["~/.local/bin/adwf"]
priority = 950
modes = ["default", "autoEdit", "yolo"]

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
    echo "  3. Use Claude launch command with permission mode:"
    echo "     --cmd \"claude --permission-mode acceptEdits\""
    echo "  4. Start using /agent-deck-workflow skill"
    echo ""
}

main "$@"
