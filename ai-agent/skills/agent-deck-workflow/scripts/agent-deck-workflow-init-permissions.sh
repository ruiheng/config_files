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

resolve_script_path() {
    local path="$1"
    local target
    local depth=0
    local parent

    while [[ -L "$path" ]]; do
        if ((depth >= 40)); then
            return 1
        fi
        target="$(readlink "$path")" || return 1
        if [[ "$target" == /* ]]; then
            path="$target"
        else
            path="$(dirname "$path")/$target"
        fi
        depth=$((depth + 1))
    done

    [[ -f "$path" ]] || return 1
    parent="$(cd -P "$(dirname "$path")" && pwd -P)" || return 1
    printf '%s/%s\n' "$parent" "$(basename "$path")"
}

SCRIPT_PATH="$(resolve_script_path "${BASH_SOURCE[0]}")" || {
    printf 'Could not resolve initializer script path: %s\n' "${BASH_SOURCE[0]}" >&2
    exit 1
}
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
# shellcheck source=waypost-permission-spec.sh
source "$SCRIPT_DIR/waypost-permission-spec.sh"

INSTALLED_SKILLS_DIR="$HOME/.config/ai-agent/skills"
INSTALLED_SKILLS_DIR_TILDE="~/.config/ai-agent/skills"
INSTALLED_WORKFLOW_SCRIPTS="$INSTALLED_SKILLS_DIR/agent-deck-workflow/scripts"
INSTALLED_WORKFLOW_SCRIPTS_TILDE="$INSTALLED_SKILLS_DIR_TILDE/agent-deck-workflow/scripts"
INSTALLED_LOCAL_BIN="$HOME/.local/bin"
INSTALLED_LOCAL_BIN_TILDE="~/.local/bin"
WORKFLOW_HELPER_SCRIPTS=(
    "acquire-active-task-lock.sh"
    "send-delegate-with-active-task-lock.sh"
    "planner-closeout-batch.sh"
    "prepare-workspaces.sh"
    "prepare-planner-workspace.sh"
    "ensure-supervised-planner-session.sh"
    "ensure-planner-scoped-session.sh"
    "archive-and-remove-planner-group-sessions.sh"
)

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
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

# Waypost permissions are emitted only after one trusted executable has passed
# the exact MCP/read/list capability checks. Other workflow rules remain usable
# when Waypost is absent or unsuitable.
WAYPOST_CLI_RULES_READY=0
CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS='[]'
CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT=0
CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""

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

prepare_waypost_cli_rules() {
    if ! waypost_rule_state_dir >/dev/null; then
        log_warn "Skipping Waypost permissions: state directory must be absolute: ${WAYPOST_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ai-agent/waypost}"
        return 1
    fi

    if ! waypost_rule_resolve_cli "$PROJECT_DIR"; then
        log_warn "Skipping Waypost permissions: $WAYPOST_RULE_RESOLVE_ERROR"
        return 1
    fi

    if ! waypost_rule_validate_capabilities "$WAYPOST_RULE_COMMAND"; then
        log_warn "Skipping Waypost permissions: $WAYPOST_RULE_COMMAND lacks mcp/read/list support"
        return 1
    fi

    WAYPOST_CLI_RULES_READY=1
    return 0
}

waypost_cli_commands() {
    [[ $WAYPOST_CLI_RULES_READY -eq 1 ]] || return 0
    waypost_rule_command_forms "$WAYPOST_RULE_COMMAND"
}

waypost_cli_state_dirs() {
    waypost_rule_state_dirs
}

append_json_array_literal() {
    local array_name="$1"
    local value="$2"
    local current_value="${!array_name}"

    if [[ "$current_value" == '[]' ]]; then
        printf -v "$array_name" '[%s]' "$value"
    else
        printf -v "$array_name" '%s,%s]' "${current_value%]}" "$value"
    fi
}

claude_waypost_cli_manifest_path() {
    printf '%s\n' "$PROJECT_DIR/.claude/.agent-deck-workflow-waypost-cli.json"
}

# The project initializer owns only the structured CLI argv recorded here.
# Version-1 manifests are accepted only for a narrow migration; later runs
# verify the exact permissions reconstructed from version-2 records.
load_claude_waypost_cli_manifest() {
    local manifest_path
    local permissions

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

    permissions="$(waypost_rule_claude_cli_manifest_permissions_json "$manifest_path")" || {
        log_error "Refusing malformed Claude Waypost ownership manifest: $manifest_path"
        return 1
    }

    CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS="$permissions"
    CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT=1
    return 0
}

stage_claude_waypost_cli_manifest() {
    local permissions_json="$1"
    local rules_json="$2"
    local manifest_path

    CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
    manifest_path="$(claude_waypost_cli_manifest_path)"
    if [[ -e "$manifest_path" || -L "$manifest_path" ]]; then
        if [[ ! -f "$manifest_path" || -L "$manifest_path" ]]; then
            log_error "Refusing to overwrite invalid Claude Waypost ownership manifest: $manifest_path"
            return 1
        fi
    fi

    CLAUDE_WAYPOST_CLI_MANIFEST_TMP="$(mktemp "$(dirname "$manifest_path")/.agent-deck-waypost-cli.XXXXXX")" || {
        log_error "Failed to stage Claude Waypost ownership manifest"
        return 1
    }
    if ! printf '{"version":2,"permissions":%s,"rules":%s}\n' \
        "$permissions_json" "$rules_json" > "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP"; then
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
    if [[ -L "$manifest_path" || ( -e "$manifest_path" && ! -f "$manifest_path" ) ]]; then
        rm -f "$CLAUDE_WAYPOST_CLI_MANIFEST_TMP"
        CLAUDE_WAYPOST_CLI_MANIFEST_TMP=""
        log_error "Refusing invalid Claude Waypost ownership manifest: $manifest_path"
        return 1
    fi
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
    local workflow_script_permissions_json=""
    local waypost_cli_permissions_json=""
    local waypost_cli_permissions_array='[]'
    local waypost_cli_rule_records='[]'
    local waypost_command
    local waypost_action
    local waypost_state_dir
    local waypost_permission
    local waypost_rule_record
    local waypost_wildcard
    local script_name
    local migrate_legacy_waypost=0
    local settings_rollback=""
    local settings_existed=0
    local settings_tmp=""

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

    for script_name in "${WORKFLOW_HELPER_SCRIPTS[@]}"; do
        workflow_script_permissions_json+="  \"Bash(${INSTALLED_WORKFLOW_SCRIPTS_TILDE}/${script_name} *)\","$'\n'
        workflow_script_permissions_json+="  \"Bash(${INSTALLED_WORKFLOW_SCRIPTS}/${script_name} *)\","$'\n'
    done

    while IFS= read -r -d '' waypost_command; do
        while IFS= read -r -d '' waypost_state_dir; do
            for waypost_action in read list; do
                for waypost_wildcard in false true; do
                    waypost_permission="$(waypost_rule_claude_cli_permission \
                        "$waypost_command" "$waypost_state_dir" "$waypost_action" "$waypost_wildcard")" || return 1
                    waypost_permission="$(waypost_rule_json_string_literal "$waypost_permission")" || return 1
                    waypost_cli_permissions_json+="  ${waypost_permission},"$'\n'
                    append_json_array_literal waypost_cli_permissions_array "$waypost_permission"
                    waypost_rule_record="$(waypost_rule_claude_cli_rule_json \
                        "$waypost_command" "$waypost_state_dir" "$waypost_action" "$waypost_wildcard")" || return 1
                    append_json_array_literal waypost_cli_rule_records "$waypost_rule_record"
                done
            done
        done < <(waypost_cli_state_dirs)
    done < <(waypost_cli_commands)

    log_info "Configuring Claude Code permissions..."

    mkdir -p "$claude_dir"
    # Validate any prior ownership record before changing settings, including
    # when settings.json does not exist yet. This avoids leaving fresh
    # approvals beside an invalid or symlinked manifest that prevents retry.
    load_claude_waypost_cli_manifest || return 1
    if [[ $CLAUDE_WAYPOST_CLI_MANIFEST_PRESENT -eq 0 ]]; then
        migrate_legacy_waypost=1
    fi
    if [[ -e "$settings_file" || -L "$settings_file" ]]; then
        settings_existed=1
    fi
    if [[ -L "$settings_file" || ( $settings_existed -eq 1 && ! -f "$settings_file" ) ]]; then
        discard_claude_waypost_cli_manifest
        log_error "Refusing symlinked or non-file Claude settings path: $settings_file"
        return 1
    fi
    if [[ $WAYPOST_CLI_RULES_READY -eq 1 ]]; then
        stage_claude_waypost_cli_manifest \
            "$waypost_cli_permissions_array" "$waypost_cli_rule_records" || return 1
    fi

    if [[ -f "$settings_file" ]]; then
        log_info "Merging permissions into existing settings.json"

        # Use jq to merge permissions
        if command -v jq &>/dev/null; then
            local new_permissions
            settings_tmp="$(mktemp "$claude_dir/.settings.XXXXXX")" || {
                discard_claude_waypost_cli_manifest
                log_error "Failed to stage Claude settings"
                return 1
            }
            settings_rollback="$(mktemp "$claude_dir/.settings-rollback.XXXXXX")" || {
                rm -f "$settings_tmp"
                discard_claude_waypost_cli_manifest
                log_error "Failed to stage Claude settings rollback"
                return 1
            }
            if ! cp -p "$settings_file" "$settings_rollback"; then
                rm -f "$settings_tmp"
                rm -f "$settings_rollback"
                discard_claude_waypost_cli_manifest
                log_error "Failed to stage Claude settings rollback"
                return 1
            fi
            new_permissions=$(cat <<EOF
[
  "Bash(agent-deck)",
  "Bash(agent-deck *)",
$waypost_cli_permissions_json
  "Bash(jq)",
  "Bash(jq *)",
$git_readonly_permissions_json
  "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf-send-and-wake *)",
  "Bash(${INSTALLED_LOCAL_BIN}/adwf-send-and-wake *)",
$workflow_script_permissions_json
  "$installed_skills_read_permission_tilde",
  "$installed_skills_read_permission_abs",
  "Write(/.agent-artifacts/**)"
]
EOF
)

            if ! jq --argjson perms "$new_permissions" \
                --argjson owned_waypost "$CLAUDE_WAYPOST_CLI_MANIFEST_PERMISSIONS" \
                --argjson migrate_legacy_waypost "$migrate_legacy_waypost" '
                def is_legacy_waypost_broad_permission:
                    . == "Bash(waypost)" or . == "Bash(waypost *)";
                .permissions.allow = (
                    (.permissions.allow // [])
                    | map(select(. as $permission | ($owned_waypost | index($permission) | not)))
                    | if $migrate_legacy_waypost == 1 then
                        # Only legacy broad entries can be recognized without
                        # a manifest. Preserve state-scoped user policy.
                        map(select(is_legacy_waypost_broad_permission | not))
                      else .
                      end
                    | . + $perms
                    | unique
                )
            ' "$settings_file" > "$settings_tmp"; then
                rm -f "$settings_tmp"
                rm -f "$settings_rollback"
                discard_claude_waypost_cli_manifest
                log_error "Failed to merge permissions into $settings_file"
                return 1
            fi
            if [[ -L "$settings_file" || ! -f "$settings_file" ]]; then
                rm -f "$settings_tmp"
                rm -f "$settings_rollback"
                discard_claude_waypost_cli_manifest
                log_error "Refusing symlinked or non-file Claude settings path: $settings_file"
                return 1
            fi
            if ! waypost_rule_replace_file "$settings_tmp" "$settings_file"; then
                rm -f "$settings_tmp"
                rm -f "$settings_rollback"
                discard_claude_waypost_cli_manifest
                log_error "Failed to write Claude settings: $settings_file"
                return 1
            fi
            if [[ $WAYPOST_CLI_RULES_READY -eq 1 ]] \
                && ! commit_claude_waypost_cli_manifest; then
                if ! waypost_rule_replace_file "$settings_rollback" "$settings_file"; then
                    rm -f "$settings_rollback"
                    log_error "Failed to restore Claude settings after manifest failure: $settings_file"
                fi
                return 1
            fi
            rm -f "$settings_rollback"
            log_ok "Merged permissions into $settings_file"
        else
            discard_claude_waypost_cli_manifest
            log_warn "jq not found, cannot merge automatically"
            log_info "Please manually add these permissions to $settings_file:"
            cat <<EOF
{
  "permissions": {
    "allow": [
      "Bash(agent-deck)",
      "Bash(agent-deck *)",
$waypost_cli_permissions_json
      "Bash(jq)",
      "Bash(jq *)",
$git_readonly_permissions_json
      "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf-send-and-wake *)",
      "Bash(${INSTALLED_LOCAL_BIN}/adwf-send-and-wake *)",
$workflow_script_permissions_json
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
        settings_tmp="$(mktemp "$claude_dir/.settings.XXXXXX")" || {
            discard_claude_waypost_cli_manifest
            log_error "Failed to stage Claude settings"
            return 1
        }
        if ! cat > "$settings_tmp" <<EOF
{
  "permissions": {
    "allow": [
      "Bash(agent-deck)",
      "Bash(agent-deck *)",
$waypost_cli_permissions_json
      "Bash(jq)",
      "Bash(jq *)",
$git_readonly_permissions_json
      "Bash(${INSTALLED_LOCAL_BIN_TILDE}/adwf-send-and-wake *)",
      "Bash(${INSTALLED_LOCAL_BIN}/adwf-send-and-wake *)",
$workflow_script_permissions_json
      "$installed_skills_read_permission_tilde",
      "$installed_skills_read_permission_abs",
      "Write(/.agent-artifacts/**)"
    ]
  }
}
EOF
        then
            rm -f "$settings_tmp"
            discard_claude_waypost_cli_manifest
            log_error "Failed to render Claude settings: $settings_file"
            return 1
        fi
        if [[ -e "$settings_file" || -L "$settings_file" ]]; then
            rm -f "$settings_tmp"
            discard_claude_waypost_cli_manifest
            log_error "Refusing unexpected Claude settings path: $settings_file"
            return 1
        fi
        if ! waypost_rule_replace_file "$settings_tmp" "$settings_file"; then
            rm -f "$settings_tmp"
            discard_claude_waypost_cli_manifest
            log_error "Failed to write Claude settings: $settings_file"
            return 1
        fi
        if [[ $WAYPOST_CLI_RULES_READY -eq 1 ]] \
            && ! commit_claude_waypost_cli_manifest; then
            if [[ $settings_existed -eq 0 ]]; then
                rm -f "$settings_file"
            fi
            return 1
        fi
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
    local workflow_script_prefix_rules=""
    local waypost_cli_prefix_rules=""
    local waypost_command
    local waypost_action
    local waypost_state_dir
    local waypost_command_literal
    local waypost_state_dir_literal
    local waypost_action_literal
    local script_name

    log_info "Configuring Codex escalation rules..."

    mkdir -p "$rules_dir"

    for script_name in "${WORKFLOW_HELPER_SCRIPTS[@]}"; do
        workflow_script_prefix_rules+="prefix_rule(
    pattern = [\"$INSTALLED_WORKFLOW_SCRIPTS_TILDE/${script_name}\"],
    decision = \"allow\",
    justification = \"Workflow helper script (installed path, tilde)\",
)

prefix_rule(
    pattern = [\"$INSTALLED_WORKFLOW_SCRIPTS/${script_name}\"],
    decision = \"allow\",
    justification = \"Workflow helper script (installed path, absolute)\",
)

"
    done

    while IFS= read -r -d '' waypost_command; do
        while IFS= read -r -d '' waypost_state_dir; do
            waypost_command_literal="$(waypost_rule_json_string_literal "$waypost_command")" || return 1
            waypost_state_dir_literal="$(waypost_rule_json_string_literal "$waypost_state_dir")" || return 1
            for waypost_action in read list; do
                waypost_action_literal="$(waypost_rule_json_string_literal "$waypost_action")" || return 1
                waypost_cli_prefix_rules+="prefix_rule(
    pattern = [${waypost_command_literal}, \"--state-dir\", ${waypost_state_dir_literal}, ${waypost_action_literal}],
    decision = \"allow\",
    justification = \"Read-only Waypost query\",
)

"
            done
        done < <(waypost_cli_state_dirs)
    done < <(waypost_cli_commands)

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

# Allow read-only Waypost queries
$waypost_cli_prefix_rules

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
    pattern = ["$INSTALLED_LOCAL_BIN_TILDE/adwf-send-and-wake"],
    decision = "allow",
    justification = "Workflow send+wakeup helper (installed local bin, tilde)",
)

prefix_rule(
    pattern = ["$INSTALLED_LOCAL_BIN/adwf-send-and-wake"],
    decision = "allow",
    justification = "Workflow send+wakeup helper (installed local bin, absolute)",
)

$workflow_script_prefix_rules
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
    local workflow_script_rules=""
    local waypost_cli_policy_rules=""
    local waypost_mcp_policy_rule=""
    local waypost_command
    local waypost_action
    local waypost_state_dir
    local waypost_command_literal
    local waypost_state_dir_literal
    local waypost_action_literal
    local waypost_rule_index=0
    local script_name

    log_info "Configuring Gemini CLI shell policies..."

    mkdir -p "$policies_dir"

    for script_name in "${WORKFLOW_HELPER_SCRIPTS[@]}"; do
        workflow_script_rules+="[[rule]]
name = \"allow_${script_name//[^A-Za-z0-9]/_}_tilde\"
enabled = true
decision = \"allow\"
toolName = \"run_shell_command\"
commandPrefix = [\"${INSTALLED_WORKFLOW_SCRIPTS_TILDE}/${script_name}\"]
priority = 950
modes = [\"default\", \"autoEdit\", \"yolo\"]

"
        workflow_script_rules+="[[rule]]
name = \"allow_${script_name//[^A-Za-z0-9]/_}_absolute\"
enabled = true
decision = \"allow\"
toolName = \"run_shell_command\"
commandPrefix = [\"${HOME}/.config/ai-agent/skills/agent-deck-workflow/scripts/${script_name}\"]
priority = 950
modes = [\"default\", \"autoEdit\", \"yolo\"]

"
    done

    while IFS= read -r -d '' waypost_command; do
        while IFS= read -r -d '' waypost_state_dir; do
            waypost_command_literal="$(waypost_rule_json_string_literal "$waypost_command")" || return 1
            waypost_state_dir_literal="$(waypost_rule_json_string_literal "$waypost_state_dir")" || return 1
            for waypost_action in read list; do
                waypost_action_literal="$(waypost_rule_json_string_literal "$waypost_action")" || return 1
                waypost_rule_index=$((waypost_rule_index + 1))
                waypost_cli_policy_rules+="[[rule]]
name = \"allow_waypost_cli_${waypost_action}_${waypost_rule_index}\"
enabled = true
decision = \"allow\"
toolName = \"run_shell_command\"
commandPrefix = [${waypost_command_literal}, \"--state-dir\", ${waypost_state_dir_literal}, ${waypost_action_literal}]
priority = 950
modes = [\"default\", \"autoEdit\", \"yolo\"]

"
            done
        done < <(waypost_cli_state_dirs)
    done < <(waypost_cli_commands)

    if [[ $WAYPOST_CLI_RULES_READY -eq 1 ]]; then
        waypost_mcp_policy_rule=$(cat <<'EOF'
[[rule]]
name = "allow_waypost_mcp"
enabled = true
decision = "allow"
toolName = "*"
mcpName = "waypost"
priority = 950
modes = ["default", "autoEdit", "yolo"]

EOF
)
    fi

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
EOF

    if [[ -n "$waypost_mcp_policy_rule" ]]; then
        printf '%s\n' "$waypost_mcp_policy_rule" >> "$policy_file"
    fi
    cat >> "$policy_file" << 'EOF'
[[rule]]
name = "allow_agent_deck_workflow_dispatch"
enabled = true
decision = "allow"
toolName = "run_shell_command"
commandPrefix = ["~/.local/bin/adwf-send-and-wake"]
priority = 950
modes = ["default", "autoEdit", "yolo"]
EOF

    printf '%s' "$waypost_cli_policy_rules" >> "$policy_file"
    printf '%s' "$workflow_script_rules" >> "$policy_file"
    cat >> "$policy_file" << 'EOF'

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

    if ! prepare_waypost_cli_rules; then
        log_warn "Waypost-specific permissions will be omitted"
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
