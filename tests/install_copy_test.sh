#!/usr/bin/env bash

set -uo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/config-files-install-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_DATA_HOME="$TEST_ROOT/data"
mkdir -p "$HOME"

source "$REPO_ROOT/install.sh"

USE_COLOR=0
RED=''
GREEN=''
YELLOW=''
BLUE=''
NC=''
DRY_RUN=0
FORCE=0
INTERACTIVE=0

fail_test() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_file_content() {
    local path="$1"
    local expected="$2"
    local actual

    [[ -f "$path" && ! -L "$path" ]] || fail_test "expected regular file: $path"
    actual="$(head -n 1 "$path")"
    [[ "$actual" == "$expected" ]] || fail_test "unexpected content at $path: $actual"
}

assert_path_mode() {
    local path="$1"
    local expected="$2"
    local actual

    actual="$(path_mode "$path")" || fail_test "could not read mode: $path"
    [[ "$actual" == "$expected" ]] \
        || fail_test "unexpected mode at $path: $actual (expected $expected)"
}

test_best_effort_continues_and_counts_failures() {
    local case_dir="$TEST_ROOT/best-effort"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        ACTION_LOG="$case_dir/actions" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            failed=0
            failing_step() {
                printf "%s\n" "failing" >> "$ACTION_LOG"
                return 1
            }
            successful_step() {
                printf "%s\n" "successful" >> "$ACTION_LOG"
            }
            run_best_effort "failing step" failing_step
            run_best_effort "successful step" successful_step
            [[ $failed -eq 1 ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "best-effort runner did not continue after a failure"

    [[ "$(<"$case_dir/actions")" == $'failing\nsuccessful' ]] \
        || fail_test "best-effort runner skipped a later action"
}

test_dry_run_summary_propagates_best_effort_failure() {
    local case_dir="$TEST_ROOT/dry-run-best-effort-status"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            bash -c '
                source "$1/install.sh"
                DRY_RUN=1
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                failed=0
                run_best_effort "forced failure" false
                if print_summary; then exit 10; fi
                [[ $failed -eq 1 ]]
            ' _ "$REPO_ROOT"
    )" || fail_test "dry-run summary did not propagate a best-effort failure"

    [[ "$output" == *"Dry run complete. No changes were made."* ]] \
        || fail_test "failed dry run did not complete its summary"
    [[ "$output" == *"Some operations failed"* ]] \
        || fail_test "failed dry run did not report its aggregate status"
}

test_waypost_preparation_requires_explicit_migration() {
    local case_dir="$TEST_ROOT/waypost-preparation-gate"

    mkdir -p "$case_dir/home" "$case_dir/state/ai-agent/mailbox"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        MIGRATION_CALLED="$case_dir/migration-called" \
        LAUNCHERS_REMOVED="$case_dir/launchers-removed" \
        MCP_SWITCHED="$case_dir/mcp-switched" \
        LINK_LOG="$case_dir/links" \
        TEST_FRESH_STATE="$case_dir/fresh-state" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""

            ensure_waypost_mcp_command() { return 1; }
            if prepare_waypost_config_switch; then exit 10; fi
            [[ $WAYPOST_CONFIG_SWITCH_READY -eq 0 ]]
            [[ ! -e "$MIGRATION_CALLED" ]]

            ensure_waypost_mcp_command() { return 0; }
            waypost() {
                touch "$MIGRATION_CALLED"
                return 0
            }
            if prepare_waypost_config_switch; then exit 11; fi
            [[ $WAYPOST_CONFIG_SWITCH_READY -eq 0 ]]
            [[ -d "$XDG_STATE_HOME/ai-agent/mailbox" ]]
            [[ ! -e "$MIGRATION_CALLED" ]]

            link_shared_ai_agent_item() {
                printf "%s\\n" "$1" >> "$LINK_LOG"
            }
            install_claude_skills() { :; }
            remove_obsolete_waypost_launchers() { touch "$LAUNCHERS_REMOVED"; }
            install_claude_waypost_mcp() { touch "$MCP_SWITCHED"; }
            install_claude_config
            [[ ! -e "$LAUNCHERS_REMOVED" ]]
            [[ ! -e "$MCP_SWITCHED" ]]
            grep -Fqx "claude/statusline-command.sh" "$LINK_LOG"

            XDG_STATE_HOME="$TEST_FRESH_STATE"
            prepare_waypost_config_switch
            [[ $WAYPOST_CONFIG_SWITCH_READY -eq 1 ]]

            install_claude_waypost_mcp() { return 1; }
            if install_claude_config; then exit 12; fi
            [[ ! -e "$LAUNCHERS_REMOVED" ]]

            install_claude_waypost_mcp() { touch "$MCP_SWITCHED"; }
            install_claude_config
            [[ -e "$LAUNCHERS_REMOVED" ]]
            [[ -e "$MCP_SWITCHED" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "Waypost prerequisites did not gate client configuration switching"
}

test_waypost_preparation_gates_dependent_assets() {
    local case_dir="$TEST_ROOT/waypost-asset-gate"

    mkdir -p "$case_dir/home" "$case_dir/state/ai-agent/mailbox"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        MIGRATION_CALLED="$case_dir/migration-called" \
        COPY_CALLED="$case_dir/copy-called" \
        SNAPSHOT_CALLED="$case_dir/snapshot-called" \
        SKILLS_CALLED="$case_dir/skills-called" \
        SERENA_CALLED="$case_dir/serena-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""

            WAYPOST_CONFIG_SWITCH_READY=0
            SHARED_AI_AGENT_READY=1
            install_copy() { touch "$COPY_CALLED"; }
            install_ai_agent_config
            install_waypost_ready_shared_ai_agent_snapshot
            [[ $SHARED_AI_AGENT_READY -eq 0 ]]
            [[ ! -e "$COPY_CALLED" ]]

            failed=0
            parse_args --only ai-skills,serena
            ensure_waypost_mcp_command() { return 0; }
            waypost() { touch "$MIGRATION_CALLED"; }
            install_shared_ai_agent_snapshot() {
                touch "$SNAPSHOT_CALLED"
                SHARED_AI_AGENT_READY=1
            }
            install_all_ai_skills() { touch "$SKILLS_CALLED"; }
            install_serena_config() { touch "$SERENA_CALLED"; }

            install_selected_components
            [[ $failed -eq 1 ]]
            [[ $SHARED_AI_AGENT_READY -eq 0 ]]
            [[ -d "$XDG_STATE_HOME/ai-agent/mailbox" ]]
            [[ ! -e "$MIGRATION_CALLED" ]]
            [[ ! -e "$SNAPSHOT_CALLED" ]]
            [[ ! -e "$SKILLS_CALLED" ]]
            [[ -e "$SERENA_CALLED" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "failed Waypost preparation allowed dependent AI assets to change"
}

test_zsh_stack_gates_dependencies_after_core_failure() {
    local case_dir="$TEST_ROOT/zsh-stack-gate"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        ZSH_DEPENDENCIES_CALLED="$case_dir/dependencies-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            failed=0
            install_oh_my_zsh() { return 1; }
            install_zsh_dependencies() { touch "$ZSH_DEPENDENCIES_CALLED"; }
            install_zsh_stack
            [[ $failed -eq 1 ]]
            [[ ! -e "$ZSH_DEPENDENCIES_CALLED" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "Zsh dependencies ran after Oh My Zsh failed"
}

test_zsh_stack_readiness_gates_only_zshrc() {
    local case_dir="$TEST_ROOT/zsh-stack-home-gate"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            failed=0
            skipped=0
            install_oh_my_zsh() { return 0; }
            install_zsh_dependencies() { return 1; }

            install_zsh_stack
            [[ $failed -eq 1 ]]
            [[ $ZSH_STACK_READY -eq 0 ]]

            install_home_configs 0 "$ZSH_STACK_READY"
            [[ ! -e "$HOME/.zshrc" ]]
            [[ -f "$HOME/.bashrc" ]]
            [[ -f "$HOME/.screenrc" ]]

            install_zsh_dependencies() { return 0; }
            install_zsh_stack
            [[ $ZSH_STACK_READY -eq 1 ]]
            install_home_configs 0 "$ZSH_STACK_READY"
            [[ -f "$HOME/.zshrc" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "Zsh stack readiness did not gate only zshrc deployment"
}

test_failed_zsh_clones_leave_retryable_targets() {
    local case_dir="$TEST_ROOT/zsh-clone-cleanup"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_required_command() { return 0; }
            git() {
                local target="${!#}"
                mkdir -p "$target"
                return 1
            }

            if install_oh_my_zsh; then exit 10; fi
            [[ ! -e "$HOME/.oh-my-zsh" ]]

            target="$HOME/.oh-my-zsh/custom/themes/test-theme"
            marker="$target/test.zsh-theme"
            if install_zsh_checkout "test theme" "https://example.invalid/theme.git" "$target" "$marker"; then
                exit 11
            fi
            [[ ! -e "$target" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "failed Zsh clones left incomplete targets"
}

test_dangling_oh_my_zsh_symlink_is_preserved() {
    local case_dir="$TEST_ROOT/dangling-oh-my-zsh"

    mkdir -p "$case_dir/home"
    ln -s "$case_dir/missing-oh-my-zsh" "$case_dir/home/.oh-my-zsh"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        DANGLING_TARGET="$case_dir/missing-oh-my-zsh" \
        GIT_CHECK_CALLED="$case_dir/git-check-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_required_command() {
                touch "$GIT_CHECK_CALLED"
                return 99
            }

            if install_oh_my_zsh; then exit 10; fi
            [[ -L "$HOME/.oh-my-zsh" ]]
            [[ "$(readlink "$HOME/.oh-my-zsh")" == "$DANGLING_TARGET" ]]
            [[ ! -e "$GIT_CHECK_CALLED" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "dangling Oh My Zsh symlink was not preserved"
}

test_dry_run_rejects_installed_package_with_missing_resource() {
    local case_dir="$TEST_ROOT/dry-run-installed-package-missing-resource"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            bash -c '
                source "$1/install.sh"
                DRY_RUN=1
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                package_is_installed() { return 0; }

                if ensure_required_command "config-files-missing-command" "existing-package"; then
                    exit 10
                fi

                find_libclang_dir() { return 1; }
                libclang_package_name() { printf "%s\\n" "existing-libclang"; }
                if ensure_libclang; then exit 11; fi
            ' _ "$REPO_ROOT"
    )" || fail_test "dry-run accepted an installed package with a missing resource"

    [[ "$output" == *"no package change would be made"* ]] \
        || fail_test "dry-run did not explain the installed-package mismatch"
}

test_required_tools_check_every_item_best_effort() {
    local case_dir="$TEST_ROOT/required-tools-best-effort"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        ACTION_LOG="$case_dir/actions" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            failed=0
            ensure_required_command() {
                printf "%s\n" "$1" >> "$ACTION_LOG"
                [[ "$1" != "git" && "$1" != "yq" ]]
            }
            install_required_tools
            [[ $failed -eq 2 ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "required tool checks stopped after a failure"

    [[ "$(head -n 1 "$case_dir/actions")" == "curl" ]] \
        || fail_test "required tool checks did not start with curl"
    [[ "$(tail -n 1 "$case_dir/actions")" == "zsh" ]] \
        || fail_test "required tool checks did not reach the final item"
    [[ "$(wc -l < "$case_dir/actions")" -eq 9 ]] \
        || fail_test "required tool checks did not attempt every item"
}

test_local_bin_path_injection_reports_persistence_limit() {
    local case_dir="$TEST_ROOT/local-bin-path-warning"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="/usr/bin:/bin" \
            bash -c '
                source "$1/install.sh"
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                ensure_path_contains_local_bin
            ' _ "$REPO_ROOT"
    )" || fail_test "local bin PATH setup failed"

    [[ "$output" == *"Ensure future shells include this directory"* ]] \
        || fail_test "local bin PATH setup did not report its persistence limit"
}

test_shared_agent_snapshot_preserves_local_content() {
    local shared_dir="$SHARED_AI_AGENT_DIR"
    local snapshot

    install_shared_ai_agent_snapshot \
        || fail_test "initial shared agent asset install failed"
    snapshot="$(managed_copy_snapshot_path "$shared_dir")"
    [[ -d "$snapshot" ]] || fail_test "shared agent snapshot was not recorded"
    managed_path_is_recorded "$shared_dir" \
        || fail_test "shared agent path was not recorded"

    printf 'local agent instructions\n' > "$shared_dir/AGENTS.md"
    rm "$shared_dir/GEMINI.md"
    printf 'local skill\n' > "$shared_dir/local-skill.md"

    install_shared_ai_agent_snapshot \
        || fail_test "shared agent asset update failed"

    assert_file_content "$shared_dir/AGENTS.md" "local agent instructions"
    [[ ! -e "$shared_dir/GEMINI.md" ]] \
        || fail_test "locally deleted shared asset was restored"
    assert_file_content "$shared_dir/local-skill.md" "local skill"
    cmp -s "$REPO_ROOT/ai-agent/AGENTS.md" "$snapshot/AGENTS.md" \
        || fail_test "shared agent snapshot did not retain the repository baseline"
    [[ -e "$snapshot/GEMINI.md" ]] \
        || fail_test "shared agent snapshot retained a local deletion"
    [[ ! -e "$snapshot/local-skill.md" ]] \
        || fail_test "shared agent snapshot retained a target-only file"
}

test_failed_shared_snapshot_preserves_existing_consumer_links() {
    local case_dir="$TEST_ROOT/shared-snapshot-consumer-gate"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        CONSUMER_CALLED="$case_dir/consumer-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""

            mkdir -p "$SHARED_AI_AGENT_DIR" "$HOME/.claude"
            cp "$SCRIPT_DIR/README.md" "$SHARED_AI_AGENT_DIR/CLAUDE.md"
            ln -s "$SCRIPT_DIR/ai-agent/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

            SHARED_AI_AGENT_READY=1
            install_copy() { return 1; }
            if install_shared_ai_agent_snapshot; then exit 10; fi
            [[ $SHARED_AI_AGENT_READY -eq 0 ]]

            install_claude_config() { touch "$CONSUMER_CALLED"; }
            install_gemini_config() { touch "$CONSUMER_CALLED"; }
            install_antigravity_config() { touch "$CONSUMER_CALLED"; }
            install_kiro_config() { touch "$CONSUMER_CALLED"; }
            install_codex_config() { touch "$CONSUMER_CALLED"; }
            install_ast_grep_skill() { touch "$CONSUMER_CALLED"; }
            install_opencode_config() { touch "$CONSUMER_CALLED"; }

            install_snapshot_dependent_ai_configs
            [[ ! -e "$CONSUMER_CALLED" ]]
            symlink_points_to \
                "$HOME/.claude/CLAUDE.md" \
                "$SCRIPT_DIR/ai-agent/CLAUDE.md"
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "failed shared snapshot allowed stale snapshot consumers to run"
}

test_selected_snapshot_failure_skips_ai_skills_and_continues() {
    local case_dir="$TEST_ROOT/selected-shared-snapshot-gate"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        DETECT_CALLED="$case_dir/detect-called" \
        SKILLS_CALLED="$case_dir/skills-called" \
        SERENA_CALLED="$case_dir/serena-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            failed=0
            parse_args --only ai-skills,serena

            prepare_waypost_config_switch() {
                WAYPOST_CONFIG_SWITCH_READY=1
            }
            SHARED_AI_AGENT_READY=1
            install_copy() { return 1; }
            detect_installed_agent_deck() { touch "$DETECT_CALLED"; }
            install_all_ai_skills() { touch "$SKILLS_CALLED"; }
            install_serena_config() { touch "$SERENA_CALLED"; }

            install_selected_components
            [[ $failed -eq 1 ]]
            [[ $SHARED_AI_AGENT_READY -eq 0 ]]
            [[ ! -e "$DETECT_CALLED" ]]
            [[ ! -e "$SKILLS_CALLED" ]]
            [[ -e "$SERENA_CALLED" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "selected snapshot failure did not gate skills and continue"
}

test_zshrc_uses_managed_copy_merge() {
    local case_dir="$TEST_ROOT/zshrc-merge"
    local zshrc="$case_dir/home/.zshrc"

    mkdir -p "$(dirname "$zshrc")"
    printf 'local zsh config\n' > "$zshrc"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_home_configs
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "install_home_configs failed while checking zshrc mode"

    assert_file_content "$zshrc" "local zsh config"
}

test_shell_configs_clean_path() {
    local bash_path

    grep -Fq 'source "$NVM_DIR/nvm.sh" --no-use' "$REPO_ROOT/bashrc" \
        || fail_test "bashrc does not preserve an existing Node.js runtime when loading NVM"
    grep -Fq 'source "$NVM_DIR/nvm.sh" --no-use' "$REPO_ROOT/zshrc" \
        || fail_test "zshrc does not preserve an existing Node.js runtime when loading NVM"
    grep -Fq 'path=("$HOME/.local/bin"' "$REPO_ROOT/zshrc" \
        || fail_test "zshrc does not prioritize the home-relative local bin path"
    grep -Fq '${path:#/usr/local/games}' "$REPO_ROOT/zshrc" \
        || fail_test "zshrc does not remove /usr/local/games"
    grep -Fq '${path:#/usr/games}' "$REPO_ROOT/zshrc" \
        || fail_test "zshrc does not remove /usr/games"
    ! grep -Fq '/home/ruiheng/.local/bin' "$REPO_ROOT/zshrc" \
        || fail_test "zshrc contains a machine-specific local bin path"

    bash_path="$(
        HOME="$TEST_ROOT/path-home" \
        PATH="$TEST_ROOT/path-home/.local/bin:/usr/bin:$TEST_ROOT/path-home/.local/bin:/usr/local/games:/usr/games:/bin" \
        bash --noprofile --norc -c '
            source "$1/bashrc"
            source "$1/bashrc"
            printf "%s\\n" "$PATH"
        ' _ "$REPO_ROOT"
    )" || fail_test "bashrc PATH cleanup failed"
    [[ "$bash_path" == "$TEST_ROOT/path-home/.local/bin:/usr/bin:/bin" ]] \
        || fail_test "bashrc PATH cleanup was incorrect: $bash_path"
}

test_bashrc_preserves_ambient_node_when_loading_nvm() {
    local case_dir="$TEST_ROOT/bashrc-preserves-node"
    local system_bin="$case_dir/system-bin"
    local nvm_bin="$case_dir/home/.nvm/versions/node/v99.0.0/bin"

    mkdir -p "$system_bin" "$nvm_bin"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "v20.0.0"' > "$system_bin/node"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "10.0.0"' > "$system_bin/npm"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "v99.0.0"' > "$nvm_bin/node"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "99.0.0"' > "$nvm_bin/npm"
    printf '%s\n' \
        'printf "%s\n" "${1:-}" > "$NVM_SOURCE_ARG"' \
        'if [ "${1:-}" != "--no-use" ]; then' \
        '    export PATH="$NVM_DEFAULT_BIN:$PATH"' \
        'fi' > "$case_dir/home/.nvm/nvm.sh"
    chmod +x "$system_bin/node" "$system_bin/npm" "$nvm_bin/node" "$nvm_bin/npm"

    HOME="$case_dir/home" \
        PATH="$system_bin:/usr/bin:/bin" \
        NVM_DEFAULT_BIN="$nvm_bin" \
        NVM_SOURCE_ARG="$case_dir/nvm-source-arg" \
        SYSTEM_NODE_BIN="$system_bin" \
        bash --noprofile --norc -c '
            source "$1/bashrc"
            [[ "$(command -v node)" == "$SYSTEM_NODE_BIN/node" ]]
            [[ "$(command -v npm)" == "$SYSTEM_NODE_BIN/npm" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "bashrc switched away from an existing usable Node.js runtime"

    [[ "$(<"$case_dir/nvm-source-arg")" == "--no-use" ]] \
        || fail_test "bashrc did not load NVM with --no-use for an existing Node.js runtime"
}

test_component_selection_parsing() {
    parse_args --only "home, ai-skills" --only serena

    [[ $INSTALL_ALL -eq 0 ]] \
        || fail_test "--only did not enable selective installation"
    component_is_selected "home" \
        || fail_test "--only did not select home"
    component_is_selected "ai-skills" \
        || fail_test "--only did not select ai-skills"
    component_is_selected "serena" \
        || fail_test "repeated --only did not select serena"
    ! component_is_selected "xdg" \
        || fail_test "unselected component was treated as selected"

    parse_args --only all
    [[ $INSTALL_ALL -eq 1 ]] \
        || fail_test "--only all did not restore full installation"

    parse_args
}

test_selected_submodule_paths_follow_components() {
    local submodule_path

    parse_args --only home
    collect_selected_submodule_paths \
        || fail_test "could not collect home submodule paths"
    [[ ${#REQUIRED_SUBMODULE_PATHS[@]} -gt 0 ]] \
        || fail_test "home selection did not require any submodules"
    for submodule_path in "${REQUIRED_SUBMODULE_PATHS[@]}"; do
        [[ "$submodule_path" == tmux/* ]] \
            || fail_test "home selected unrelated submodule: $submodule_path"
    done
    [[ " ${REQUIRED_SUBMODULE_PATHS[*]} " == *" tmux/plugins/tpm "* ]] \
        || fail_test "home did not select tmux/plugins/tpm"

    parse_args --only xdg
    collect_selected_submodule_paths \
        || fail_test "could not collect XDG submodule paths"
    [[ ${#REQUIRED_SUBMODULE_PATHS[@]} -gt 0 ]] \
        || fail_test "XDG selection did not require any submodules"
    for submodule_path in "${REQUIRED_SUBMODULE_PATHS[@]}"; do
        [[ "$submodule_path" == nvim/* ]] \
            || fail_test "XDG selected unrelated submodule: $submodule_path"
    done
    [[ " ${REQUIRED_SUBMODULE_PATHS[*]} " == *" nvim/jinja-mixed "* ]] \
        || fail_test "XDG did not select nvim/jinja-mixed"
    [[ " ${REQUIRED_SUBMODULE_PATHS[*]} " == *" nvim/lua/buffer-nexus "* ]] \
        || fail_test "XDG did not select nvim/lua/buffer-nexus"

    parse_args
}

test_partial_home_and_xdg_initialize_submodules_before_copy() {
    local events

    events="$(
        bash -c '
            source "$1/install.sh"
            events=""
            init_selected_submodules() { events="${events}submodules "; }
            install_home_configs() { events="${events}home "; }
            install_xdg_configs() { events="${events}xdg "; }
            print_summary() { :; }
            main --only home,xdg >/dev/null
            printf "%s\\n" "$events"
        ' _ "$REPO_ROOT"
    )" || fail_test "partial home/XDG installation failed"

    [[ "$events" == "submodules home xdg " ]] \
        || fail_test "partial home/XDG installation copied before initializing submodules"
}

test_partial_submodule_failure_skips_gitlink_configs_and_continues() {
    local output

    if output="$(
        bash -c '
            source "$1/install.sh"
            init_selected_submodules() { return 1; }
            install_home_configs() {
                printf "home submodules ready=%s\\n" "$1"
            }
            install_local_bin_helpers() { printf "%s\\n" "bin copy ran"; }
            main --only home,bin
        ' _ "$REPO_ROOT" 2>&1
    )"; then
        fail_test "partial installation did not report the submodule failure"
    fi

    [[ "$output" == *"home submodules ready=0"* ]] \
        || fail_test "partial installation did not disable submodule-backed Home configs"
    [[ "$output" == *"bin copy ran"* ]] \
        || fail_test "partial installation stopped before an independent component"
    [[ "$output" == *"Selected submodules failed; continuing"* ]] \
        || fail_test "partial installation did not report best-effort continuation"
}

test_config_installers_skip_unavailable_submodule_sources() {
    local case_dir="$TEST_ROOT/unavailable-config-submodules"
    local action_log="$case_dir/actions"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        ACTION_LOG="$action_log" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_copy() { printf "%s\\n" "$1" >> "$ACTION_LOG"; }
            install_home_configs 0
            install_xdg_configs 0
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "config installers failed while skipping unavailable submodules"

    [[ "$(<"$action_log")" != *"tmux/plugins/tpm"* ]] \
        || fail_test "Home config copied an unavailable TPM submodule"
    [[ "$(<"$action_log")" != *$'\nnvim\n'* ]] \
        || fail_test "XDG config copied unavailable Neovim submodules"
    [[ "$(<"$action_log")" == *"tmux/tmux.conf"* ]] \
        || fail_test "Home config skipped an independent Tmux config"
    [[ "$(<"$action_log")" == *"ranger"* ]] \
        || fail_test "XDG config skipped an independent config"
}

test_full_submodule_failure_is_reported() {
    local output

    if output="$(
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            git() { return 1; }
            init_submodules
        ' _ "$REPO_ROOT" 2>&1
    )"; then
        fail_test "full submodule initialization failure was reported as success"
    fi

    [[ "$output" == *"Failed to initialize some submodules"* ]] \
        || fail_test "full submodule initialization failure was not visible"
}

test_partial_ai_skills_detects_agent_deck_from_local_bin() {
    local case_dir="$TEST_ROOT/ai-skills-local-bin"

    mkdir -p "$case_dir/home/.local/bin"
    ln -s /usr/bin/true "$case_dir/home/.local/bin/agent-deck"

    HOME="$case_dir/home" PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            prepare_waypost_config_switch() { WAYPOST_CONFIG_SWITCH_READY=1; }
            install_shared_ai_agent_snapshot() { SHARED_AI_AGENT_READY=1; }
            install_all_ai_skills() { :; }
            print_summary() { :; }
            main --ai-skills >/dev/null
            [[ $AGENT_DECK_AVAILABLE -eq 1 ]]
            case ":$PATH:" in
                *":$HOME/.local/bin:"*) ;;
                *) exit 1 ;;
            esac
        ' _ "$REPO_ROOT" \
        || fail_test "partial AI skills install did not detect agent-deck from local bin"
}

test_ai_skills_only_skips_unrelated_bootstrap() {
    local case_dir="$TEST_ROOT/ai-skills-only"
    local fake_bin="$case_dir/bin"
    local output

    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        '[ "$1 $2" = "mcp --help" ]' > "$fake_bin/waypost"
    chmod +x "$fake_bin/waypost"
    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="$fake_bin:/usr/bin:/bin" \
            bash "$REPO_ROOT/install.sh" --dry-run --no-color --ai-skills
    )" || fail_test "--ai-skills dry run failed"

    [[ "$output" == *"Sections: ai-skills"* ]] \
        || fail_test "--ai-skills did not select the AI skills section"
    [[ "$output" == *"Installing shared agent assets..."* ]] \
        || fail_test "--ai-skills did not update the shared AI snapshot"
    [[ "$output" == *"Installing Codex skills (individually)..."* ]] \
        || fail_test "--ai-skills did not update per-agent skill links"
    [[ "$output" != *"Checking required CLI tools..."* ]] \
        || fail_test "--ai-skills ran the general CLI bootstrap"
    [[ "$output" != *"Initializing git submodules..."* ]] \
        || fail_test "--ai-skills initialized git submodules"
    [[ "$output" != *"Installing home directory dotfiles..."* ]] \
        || fail_test "--ai-skills installed home directory dotfiles"
    [[ "$output" != *"Installing XDG config directory files..."* ]] \
        || fail_test "--ai-skills installed XDG configs"
}

test_managed_copy_dry_run_is_read_only() {
    local case_dir="$TEST_ROOT/dry-run-managed-copy"
    local dst="$case_dir/bashrc"
    local snapshot
    local fake_bin="$case_dir/bin"
    local saved_path="$PATH"
    local saved_dry_run="$DRY_RUN"

    mkdir -p "$case_dir" "$fake_bin"
    cp "$REPO_ROOT/bashrc" "$dst"
    snapshot="$(managed_copy_snapshot_path "$dst")"
    mkdir -p "$(dirname "$snapshot")"
    cp "$REPO_ROOT/bashrc" "$snapshot"

    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_bin/mktemp"
    chmod +x "$fake_bin/mktemp"

    DRY_RUN=1
    PATH="$fake_bin:$saved_path"
    if ! install_copy "bashrc" "$dst"; then
        PATH="$saved_path"
        DRY_RUN="$saved_dry_run"
        fail_test "managed dry-run invoked mktemp or failed to plan the copy"
    fi
    PATH="$saved_path"
    DRY_RUN="$saved_dry_run"

    cmp -s "$REPO_ROOT/bashrc" "$dst" \
        || fail_test "managed dry-run changed the target"
    [[ $MANAGED_COPY_CHANGED -eq 0 ]] \
        || fail_test "unchanged managed copy was reported as a planned update"
}

test_managed_copy_dry_run_plans_updates_without_staging() {
    local case_dir="$TEST_ROOT/dry-run-managed-update"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"
    local fake_bin="$case_dir/bin"
    local saved_path="$PATH"
    local saved_dry_run="$DRY_RUN"

    mkdir -p "$case_dir" "$fake_bin"
    printf 'old\n' > "$base"
    printf 'new\n' > "$src"
    printf 'old\n' > "$dst"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_bin/mktemp"
    chmod +x "$fake_bin/mktemp"

    DRY_RUN=1
    PATH="$fake_bin:$saved_path"
    if ! deploy_copy "$src" "$dst" "$base"; then
        PATH="$saved_path"
        DRY_RUN="$saved_dry_run"
        fail_test "managed dry-run failed to plan an upstream update"
    fi
    PATH="$saved_path"
    DRY_RUN="$saved_dry_run"

    assert_file_content "$dst" "old"
    [[ $MANAGED_COPY_CHANGED -eq 1 ]] \
        || fail_test "managed dry-run did not report the planned update"
}

test_unrelated_repository_symlink_is_preserved() {
    local case_dir="$TEST_ROOT/unrelated-symlink"
    local dst="$case_dir/bashrc"

    mkdir -p "$case_dir"
    ln -s "$REPO_ROOT/zshrc" "$dst"
    install_copy "bashrc" "$dst" || fail_test "install_copy rejected user symlink"

    [[ -L "$dst" ]] || fail_test "user symlink was replaced"
    symlink_points_to "$dst" "$REPO_ROOT/zshrc" \
        || fail_test "user symlink target changed"
}

test_expected_repository_symlink_is_migrated() {
    local case_dir="$TEST_ROOT/expected-symlink"
    local dst="$case_dir/bashrc"
    local snapshot

    mkdir -p "$case_dir"
    ln -s "$REPO_ROOT/bashrc" "$dst"
    install_copy "bashrc" "$dst" || fail_test "expected symlink migration failed"

    [[ -f "$dst" && ! -L "$dst" ]] || fail_test "expected symlink was not migrated"
    cmp -s "$REPO_ROOT/bashrc" "$dst" || fail_test "migrated bashrc differs from source"
    snapshot="$(managed_copy_snapshot_path "$dst")"
    source_matches_installed_copy "$REPO_ROOT/bashrc" "$snapshot" \
        || fail_test "managed snapshot was not recorded"
}

test_shared_link_migration_is_exact() {
    local case_dir="$TEST_ROOT/shared-links"
    local shared_source="$SHARED_AI_AGENT_DIR/example"
    local unrelated="$case_dir/unrelated"
    local legacy="$case_dir/legacy"

    mkdir -p "$case_dir" "$(dirname "$shared_source")"
    printf 'shared\n' > "$shared_source"

    ln -s "$REPO_ROOT/zshrc" "$unrelated"
    link_path "$shared_source" "$unrelated" 0 "$REPO_ROOT/bashrc" \
        || fail_test "link_path rejected unrelated symlink"
    symlink_points_to "$unrelated" "$REPO_ROOT/zshrc" \
        || fail_test "link_path repointed an unrelated repository symlink"

    ln -s "$REPO_ROOT/bashrc" "$legacy"
    link_path "$shared_source" "$legacy" 0 "$REPO_ROOT/bashrc" \
        || fail_test "legacy shared link migration failed"
    symlink_points_to "$legacy" "$shared_source" \
        || fail_test "legacy shared link was not repointed"
}

test_unmodified_directory_to_file_transition() {
    local case_dir="$TEST_ROOT/type-transition"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base/x" "$src" "$dst/x"
    printf 'old\n' > "$base/x/managed"
    printf 'old\n' > "$dst/x/managed"
    printf 'new-file\n' > "$src/x"

    deploy_copy "$src" "$dst" "$base" || fail_test "directory-to-file update failed"
    assert_file_content "$dst/x" "new-file"
}

test_source_deletion_and_user_addition() {
    local case_dir="$TEST_ROOT/source-deletion"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf 'old\n' > "$base/managed"
    printf 'stale\n' > "$base/removed-upstream"
    printf 'old\n' > "$dst/managed"
    printf 'stale\n' > "$dst/removed-upstream"
    printf 'local\n' > "$dst/local.conf"
    printf 'new\n' > "$src/managed"

    deploy_copy "$src" "$dst" "$base" || fail_test "three-way directory update failed"
    assert_file_content "$dst/managed" "new"
    [[ ! -e "$dst/removed-upstream" ]] || fail_test "removed managed file was preserved"
    assert_file_content "$dst/local.conf" "local"
}

test_non_overlapping_file_changes_merge() {
    local case_dir="$TEST_ROOT/file-merge"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"
    local dry_dst="$case_dir/dry-dst"

    mkdir -p "$case_dir"
    printf 'first=old\nmiddle=same\nlast=old\n' > "$base"
    printf 'first=old\nmiddle=same\nlast=upstream\n' > "$src"
    printf 'first=local\nmiddle=same\nlast=old\n' > "$dst"
    cp "$dst" "$dry_dst"

    DRY_RUN=1
    deploy_copy "$src" "$dry_dst" "$base" \
        || fail_test "non-overlapping file dry-run merge failed"
    DRY_RUN=0
    [[ "$(<"$dry_dst")" == $'first=local\nmiddle=same\nlast=old' ]] \
        || fail_test "file dry-run merge changed the target"
    [[ $MANAGED_COPY_CHANGED -eq 1 ]] \
        || fail_test "file dry-run merge did not report a change"

    deploy_copy "$src" "$dst" "$base" || fail_test "non-overlapping file merge failed"
    [[ "$(<"$dst")" == $'first=local\nmiddle=same\nlast=upstream' ]] \
        || fail_test "non-overlapping file merge produced the wrong content"
}

test_overlapping_file_changes_conflict() {
    local case_dir="$TEST_ROOT/file-merge-conflict"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$case_dir"
    printf 'value=old\n' > "$base"
    printf 'value=upstream\n' > "$src"
    printf 'value=local\n' > "$dst"

    if deploy_copy "$src" "$dst" "$base"; then
        fail_test "overlapping file changes did not conflict"
    fi
    assert_file_content "$dst" "value=local"
}

test_merge_scratch_does_not_collide_with_sibling() {
    local case_dir="$TEST_ROOT/merge-scratch-collision"
    local base="$case_dir/base"
    local live="$case_dir/live"
    local staged_dir="$case_dir/staged"
    local staged="$staged_dir/foo"
    local sibling="$staged.config-files-merge"

    mkdir -p "$staged_dir"
    printf 'first=old\nmiddle=same\nlast=old\n' > "$base"
    printf 'first=local\nmiddle=same\nlast=old\n' > "$live"
    printf 'first=old\nmiddle=same\nlast=upstream\n' > "$staged"
    printf 'keep sibling\n' > "$sibling"

    merge_managed_regular_file "$base" "$live" "$staged" "$staged" \
        || fail_test "merge scratch collision test failed"
    assert_file_content "$sibling" "keep sibling"
}

test_deleted_directory_preserves_target_only_content() {
    local case_dir="$TEST_ROOT/deleted-directory-local-content"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base/obsolete/nested" "$src" "$dst/obsolete/nested"
    printf 'old root\n' > "$base/obsolete/config"
    printf 'old nested\n' > "$base/obsolete/nested/config"
    printf 'old root\n' > "$dst/obsolete/config"
    printf 'old nested\n' > "$dst/obsolete/nested/config"
    printf 'local root\n' > "$dst/obsolete/local.conf"
    printf 'local nested\n' > "$dst/obsolete/nested/local.conf"

    deploy_copy "$src" "$dst" "$base" \
        || fail_test "deleted directory merge failed"

    [[ ! -e "$dst/obsolete/config" ]] \
        || fail_test "deleted managed file survived in retained directory"
    [[ ! -e "$dst/obsolete/nested/config" ]] \
        || fail_test "deleted nested managed file survived"
    assert_file_content "$dst/obsolete/local.conf" "local root"
    assert_file_content "$dst/obsolete/nested/local.conf" "local nested"
}

test_deleted_unmodified_directory_is_removed() {
    local case_dir="$TEST_ROOT/deleted-unmodified-directory"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base/obsolete" "$src" "$dst/obsolete"
    printf 'old\n' > "$base/obsolete/config"
    printf 'old\n' > "$dst/obsolete/config"

    deploy_copy "$src" "$dst" "$base" \
        || fail_test "deleted unmodified directory merge failed"
    [[ ! -e "$dst/obsolete" ]] \
        || fail_test "unmodified deleted directory was retained"
}

test_deleted_directory_modified_managed_content_conflicts() {
    local case_dir="$TEST_ROOT/deleted-directory-conflict"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base/obsolete" "$src" "$dst/obsolete"
    printf 'old\n' > "$base/obsolete/config"
    printf 'local modification\n' > "$dst/obsolete/config"
    printf 'local addition\n' > "$dst/obsolete/local.conf"

    if deploy_copy "$src" "$dst" "$base"; then
        fail_test "modified managed content in deleted directory did not conflict"
    fi
    assert_file_content "$dst/obsolete/config" "local modification"
    assert_file_content "$dst/obsolete/local.conf" "local addition"
}

test_local_deletion_is_restored() {
    local case_dir="$TEST_ROOT/local-deletion"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf 'old\n' > "$base/deleted-locally"
    printf 'old\n' > "$base/changed-upstream"
    printf 'old\n' > "$src/deleted-locally"
    printf 'new\n' > "$src/changed-upstream"
    printf 'old\n' > "$dst/changed-upstream"

    deploy_copy "$src" "$dst" "$base" || fail_test "local deletion merge failed"
    assert_file_content "$dst/deleted-locally" "old"
    assert_file_content "$dst/changed-upstream" "new"
}

test_upstream_deletion_local_modification_conflicts() {
    local case_dir="$TEST_ROOT/upstream-delete-conflict"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"
    local forced_dst="$case_dir/dst-force"
    local backup_path

    mkdir -p "$base" "$src" "$dst" "$forced_dst"
    printf 'old\n' > "$base/removed-upstream"
    printf 'local\n' > "$dst/removed-upstream"
    printf 'local\n' > "$forced_dst/removed-upstream"

    if deploy_copy "$src" "$dst" "$base"; then
        fail_test "upstream deletion overwrote a local modification without conflict"
    fi
    assert_file_content "$dst/removed-upstream" "local"

    FORCE=1
    deploy_copy "$src" "$forced_dst" "$base" \
        || fail_test "--force upstream deletion conflict failed"
    FORCE=0
    [[ ! -e "$forced_dst/removed-upstream" ]] \
        || fail_test "--force did not apply upstream deletion"

    backup_path="$(find "$case_dir" ! -path "$case_dir" -prune -name 'dst-force.backup.*' -print -quit)"
    [[ -n "$backup_path" && -f "$backup_path/removed-upstream" ]] \
        || fail_test "--force did not back up the locally modified deleted source"
}

test_local_deletion_upstream_modification_is_restored() {
    local case_dir="$TEST_ROOT/local-delete-update"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf 'old\n' > "$base/changed-upstream"
    printf 'new\n' > "$src/changed-upstream"

    deploy_copy "$src" "$dst" "$base" \
        || fail_test "local deletion and upstream modification restore failed"
    assert_file_content "$dst/changed-upstream" "new"
}

test_root_local_deletion_is_restored() {
    local case_dir="$TEST_ROOT/root-local-deletion"
    local dst="$case_dir/bashrc"
    local snapshot

    mkdir -p "$case_dir"
    snapshot="$(managed_copy_snapshot_path "$dst")"
    mkdir -p "$(dirname "$snapshot")"
    cp "$REPO_ROOT/bashrc" "$snapshot"

    install_copy "bashrc" "$dst" || fail_test "root local deletion merge failed"
    cmp -s "$REPO_ROOT/bashrc" "$dst" \
        || fail_test "deleted managed root was not restored"
}

test_root_local_deletion_upstream_modification_is_restored() {
    local case_dir="$TEST_ROOT/root-delete-conflict"
    local dst="$case_dir/bashrc"
    local snapshot

    mkdir -p "$case_dir"
    snapshot="$(managed_copy_snapshot_path "$dst")"
    mkdir -p "$(dirname "$snapshot")"
    printf 'old\n' > "$snapshot"

    install_copy "bashrc" "$dst" \
        || fail_test "root deletion and upstream modification restore failed"
    cmp -s "$REPO_ROOT/bashrc" "$dst" \
        || fail_test "upstream-modified deleted root was not restored"
}

test_excluded_target_directories_are_preserved() {
    local case_dir="$TEST_ROOT/excluded-target-dirs"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst/node_modules" "$dst/.git"
    printf 'old\n' > "$base/managed"
    printf 'new\n' > "$src/managed"
    printf 'old\n' > "$dst/managed"
    printf 'local\n' > "$dst/node_modules/local"
    printf 'metadata\n' > "$dst/.git/local"

    deploy_copy "$src" "$dst" "$base" || fail_test "excluded target directory merge failed"
    assert_file_content "$dst/managed" "new"
    assert_file_content "$dst/node_modules/local" "local"
    assert_file_content "$dst/.git/local" "metadata"
}

test_target_only_symlink_is_preserved() {
    local case_dir="$TEST_ROOT/target-only-symlink"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf 'upstream\n' > "$src/managed"
    printf 'local\n' > "$dst/local-target"
    ln -s local-target "$dst/local-link"

    deploy_copy "$src" "$dst" "$base" || fail_test "target-only symlink merge failed"
    [[ -L "$dst/local-link" ]] || fail_test "target-only symlink became a regular file"
    [[ "$(readlink "$dst/local-link")" == local-target ]] \
        || fail_test "target-only symlink target changed"
    assert_file_content "$dst/local-target" "local"
}

test_relative_repository_symlink_is_rejected_at_final_path() {
    local case_dir="$TEST_ROOT/relative-repository-link"
    local src="$case_dir/src"
    local dst="$case_dir/dst"
    local path_tail="${dst#/}"
    local relative_target=""

    mkdir -p "$src"
    while [[ -n "$path_tail" ]]; do
        relative_target="../$relative_target"
        if [[ "$path_tail" == */* ]]; then
            path_tail="${path_tail#*/}"
        else
            path_tail=""
        fi
    done
    relative_target="$relative_target${REPO_ROOT#/}/bashrc"
    ln -s "$relative_target" "$src/repo-link"

    if deploy_copy "$src" "$dst"; then
        fail_test "relative link into the repository was installed"
    fi
    [[ ! -e "$dst" && ! -L "$dst" ]] || fail_test "rejected relative link created a target"
}

test_indirect_repository_symlink_is_rejected() {
    local case_dir="$TEST_ROOT/indirect-repository-link"
    local src="$case_dir/src"
    local dst="$case_dir/runtime/config"
    local redirect="$case_dir/runtime/repository-redirect"

    mkdir -p "$src" "$(dirname "$dst")"
    ln -s "$REPO_ROOT/bashrc" "$redirect"
    ln -s ../repository-redirect "$src/repo-link"

    if deploy_copy "$src" "$dst"; then
        fail_test "indirect link into the repository was installed"
    fi
    [[ ! -e "$dst" && ! -L "$dst" ]] || fail_test "rejected indirect link created a target"
}

test_safe_relative_symlink_is_preserved_in_snapshot() {
    local case_dir="$TEST_ROOT/safe-relative-link"
    local src="$case_dir/src"
    local dst="$case_dir/runtime/config"
    local snapshot

    mkdir -p "$src/links" "$(dirname "$dst")"
    printf 'target\n' > "$src/target"
    ln -s ../target "$src/links/target-link"

    deploy_copy "$src" "$dst" || fail_test "safe relative link deployment failed"
    record_managed_copy_snapshot "$src" "$dst" \
        || fail_test "safe relative link snapshot failed"

    snapshot="$(managed_copy_snapshot_path "$dst")"
    [[ -L "$dst/links/target-link" ]] || fail_test "runtime relative link was not preserved"
    [[ "$(readlink "$dst/links/target-link")" == ../target ]] \
        || fail_test "runtime relative link target changed"
    [[ -L "$snapshot/links/target-link" ]] || fail_test "snapshot relative link was not preserved"
    [[ "$(readlink "$snapshot/links/target-link")" == ../target ]] \
        || fail_test "snapshot relative link target changed"
}

test_platform_specific_configs_skip_cleanly() {
    local case_dir="$TEST_ROOT/platform-skips"
    local mac_output
    local linux_output

    mkdir -p "$case_dir/mac-home" "$case_dir/linux-home"
    mac_output="$(
        OSTYPE=darwin23 \
        HOME="$case_dir/mac-home" \
        XDG_STATE_HOME="$case_dir/mac-state" \
        XDG_DATA_HOME="$case_dir/mac-data" \
        bash -c '
            source "$1/install.sh"
            DRY_RUN=1
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_xdg_configs
            install_local_bin_helpers
        ' _ "$REPO_ROOT"
    )" || fail_test "macOS platform skip path failed"

    [[ "$mac_output" == *"Skipping Linux desktop configs on: macos"* ]] \
        || fail_test "macOS did not report skipped desktop configs"
    [[ "$mac_output" == *"Skipping Linux desktop helper scripts on: macos"* ]] \
        || fail_test "macOS did not report skipped helper scripts"
    [[ "$mac_output" != *"$REPO_ROOT/systemd ->"* ]] \
        || fail_test "macOS planned a systemd install"
    [[ "$mac_output" != *"x11-wayland-clipboard-bridge"* ]] \
        || fail_test "macOS planned the X11/Wayland bridge"
    [[ "$mac_output" == *"$REPO_ROOT/nvim ->"* ]] \
        || fail_test "macOS skipped cross-platform configs"

    linux_output="$(
        OSTYPE=linux-gnu \
        HOME="$case_dir/linux-home" \
        XDG_STATE_HOME="$case_dir/linux-state" \
        XDG_DATA_HOME="$case_dir/linux-data" \
        bash -c '
            source "$1/install.sh"
            DRY_RUN=1
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_xdg_configs
            install_local_bin_helpers
        ' _ "$REPO_ROOT"
    )" || fail_test "Linux desktop install path failed"

    [[ "$linux_output" == *"$REPO_ROOT/systemd ->"* ]] \
        || fail_test "Linux skipped systemd configs"
    [[ "$linux_output" == *"x11-wayland-clipboard-bridge"* ]] \
        || fail_test "Linux skipped the X11/Wayland bridge"
}

test_systemd_bridge_uses_stable_executable() {
    local unit="$REPO_ROOT/systemd/user/x11-wayland-clipboard-bridge.service"

    grep -Fqx 'ExecStart=%h/.local/bin/x11-wayland-clipboard-bridge' "$unit" \
        || fail_test "systemd bridge unit does not use the stable executable"
    [[ -x "$REPO_ROOT/scripts/x11-wayland-clipboard-bridge" ]] \
        || fail_test "clipboard bridge source is not executable"
}

test_nvim_version_check_is_portable() {
    nvim_version_is_supported 0.9 || fail_test "Neovim 0.9 was rejected"
    nvim_version_is_supported 0.10 || fail_test "Neovim 0.10 was rejected"
    nvim_version_is_supported 1.0 || fail_test "Neovim 1.0 was rejected"
    if nvim_version_is_supported 0.8; then
        fail_test "Neovim 0.8 was accepted"
    fi
    if nvim_version_is_supported unknown; then
        fail_test "invalid Neovim version was accepted"
    fi
}

test_known_legacy_links_are_migrated() {
    local case_dir="$TEST_ROOT/known-legacy-links"
    local git_unix_dst="$case_dir/gitconfig-unix"
    local git_win_dst="$case_dir/gitconfig-win"
    local gitignore_dst="$case_dir/gitignore"
    local gemini_dst="$case_dir/gemini-policy"
    local codex_dst="$case_dir/codex-rule"
    local gemini_shared="$SHARED_AI_AGENT_DIR/gemini/policies/agent-deck-workflow.toml"
    local codex_shared="$SHARED_AI_AGENT_DIR/codex/rules/agent-deck-workflow.rules"

    mkdir -p "$case_dir" "$(dirname "$gemini_shared")" "$(dirname "$codex_shared")"

    ln -s "$REPO_ROOT/gitconfig.ruiheng.unix" "$git_unix_dst"
    install_copy "gitconfig.unix" "$git_unix_dst" 0 "$REPO_ROOT/gitconfig.ruiheng.unix" \
        || fail_test "legacy Unix gitconfig migration failed"
    cmp -s "$REPO_ROOT/gitconfig.unix" "$git_unix_dst" \
        || fail_test "legacy Unix gitconfig was not replaced"

    ln -s "$REPO_ROOT/gitconfig.ruiheng.win" "$git_win_dst"
    install_copy "gitconfig.win" "$git_win_dst" 0 "$REPO_ROOT/gitconfig.ruiheng.win" \
        || fail_test "legacy Windows gitconfig migration failed"
    cmp -s "$REPO_ROOT/gitconfig.win" "$git_win_dst" \
        || fail_test "legacy Windows gitconfig was not replaced"

    ln -s "$REPO_ROOT/.gitignore" "$gitignore_dst"
    install_copy "gitignore" "$gitignore_dst" 0 "$REPO_ROOT/.gitignore" \
        || fail_test "legacy gitignore migration failed"
    cmp -s "$REPO_ROOT/gitignore" "$gitignore_dst" \
        || fail_test "legacy gitignore was not replaced"

    printf 'gemini\n' > "$gemini_shared"
    ln -s "$REPO_ROOT/ai-agent/.gemini/policies/agent-deck-workflow.toml" "$gemini_dst"
    link_shared_ai_agent_item \
        "gemini/policies/agent-deck-workflow.toml" \
        "$gemini_dst" \
        ".gemini/policies/agent-deck-workflow.toml" \
        || fail_test "legacy Gemini policy migration failed"
    symlink_points_to "$gemini_dst" "$gemini_shared" \
        || fail_test "legacy Gemini policy was not repointed"

    printf 'codex\n' > "$codex_shared"
    ln -s "$REPO_ROOT/ai-agent/.codex/rules/agent-deck-workflow.rules" "$codex_dst"
    link_shared_ai_agent_item \
        "codex/rules/agent-deck-workflow.rules" \
        "$codex_dst" \
        ".codex/rules/agent-deck-workflow.rules" \
        || fail_test "legacy Codex rule migration failed"
    symlink_points_to "$codex_dst" "$codex_shared" \
        || fail_test "legacy Codex rule was not repointed"
}

test_conflicting_user_addition_requires_force() {
    local case_dir="$TEST_ROOT/conflict"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"
    local backup_path

    mkdir -p "$base" "$src" "$dst"
    printf 'upstream\n' > "$src/collision"
    mkdir -p "$dst/collision"
    printf 'local\n' > "$dst/collision/local"

    if deploy_copy "$src" "$dst" "$base"; then
        fail_test "conflicting user addition was overwritten without --force"
    fi
    [[ -d "$dst/collision" ]] || fail_test "failed conflict changed the live target"

    FORCE=1
    deploy_copy "$src" "$dst" "$base" || fail_test "--force conflict update failed"
    FORCE=0
    assert_file_content "$dst/collision" "upstream"

    backup_path="$(find "$case_dir" ! -path "$case_dir" -prune -name 'dst.backup.*' -print -quit)"
    [[ -n "$backup_path" && -f "$backup_path/collision/local" ]] \
        || fail_test "--force did not back up conflicting user content"
}

test_executable_mode_update() {
    local case_dir="$TEST_ROOT/executable-mode"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf '#!/bin/sh\n' > "$base/tool"
    printf '#!/bin/sh\n' > "$src/tool"
    printf '#!/bin/sh\n' > "$dst/tool"
    chmod 0644 "$base/tool" "$dst/tool"
    chmod 0755 "$src/tool"

    deploy_copy "$src" "$dst" "$base" || fail_test "executable mode update failed"
    [[ -x "$dst/tool" ]] || fail_test "executable mode was not synchronized"
}

test_non_executable_mode_update() {
    local case_dir="$TEST_ROOT/non-executable-mode"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf 'private\n' > "$base/settings"
    printf 'private\n' > "$src/settings"
    printf 'private\n' > "$dst/settings"
    chmod 0644 "$base/settings" "$dst/settings"
    chmod 0600 "$src/settings"

    deploy_copy "$src" "$dst" "$base" \
        || fail_test "non-executable mode update failed"
    assert_path_mode "$dst/settings" 600
}

test_local_directory_mode_is_preserved_with_upstream_update() {
    local case_dir="$TEST_ROOT/directory-mode"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"

    mkdir -p "$base" "$src" "$dst"
    printf 'old\n' > "$base/managed"
    printf 'new\n' > "$src/managed"
    printf 'old\n' > "$dst/managed"
    chmod 0755 "$base" "$src"
    chmod 0700 "$dst"

    deploy_copy "$src" "$dst" "$base" \
        || fail_test "directory mode merge failed"
    assert_file_content "$dst/managed" "new"
    assert_path_mode "$dst" 700
}

test_macos_path_mode_uses_bsd_stat() {
    local case_dir="$TEST_ROOT/macos-mode"
    local fake_bin="$case_dir/bin"
    local mode

    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1" = "-f" ] && [ "$2" = "%Lp" ]; then' \
        '    printf "600\\n"' \
        '    exit 0' \
        'fi' \
        'exit 1' > "$fake_bin/stat"
    chmod +x "$fake_bin/stat"

    mode="$(
        OSTYPE=darwin23 \
        PATH="$fake_bin:$PATH" \
        bash -c 'source "$1/install.sh"; path_mode "$2"' _ "$REPO_ROOT" "$case_dir/file"
    )" || fail_test "macOS mode lookup failed"
    [[ "$mode" == 600 ]] || fail_test "macOS mode lookup used the wrong stat format: $mode"
}

test_lazygit_asset_selection() {
    local linux_x86
    local linux_arm
    local macos_x86
    local macos_arm

    linux_x86="$(
        OSTYPE=linux-gnu bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" x86_64; }
            lazygit_asset_suffix
        ' _ "$REPO_ROOT"
    )" || fail_test "lazygit Linux x86 asset selection failed"
    [[ "$linux_x86" == "Linux_x86_64" ]] \
        || fail_test "lazygit Linux x86 asset selection was incorrect"

    linux_arm="$(
        OSTYPE=linux-gnu bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" aarch64; }
            lazygit_asset_suffix
        ' _ "$REPO_ROOT"
    )" || fail_test "lazygit Linux ARM asset selection failed"
    [[ "$linux_arm" == "Linux_arm64" ]] \
        || fail_test "lazygit Linux ARM asset selection was incorrect"

    macos_x86="$(
        OSTYPE=darwin23 bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" x86_64; }
            lazygit_asset_suffix
        ' _ "$REPO_ROOT"
    )" || fail_test "lazygit macOS x86 asset selection failed"
    [[ "$macos_x86" == "Darwin_x86_64" ]] \
        || fail_test "lazygit macOS x86 asset selection was incorrect"

    macos_arm="$(
        OSTYPE=darwin23 bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" arm64; }
            lazygit_asset_suffix
        ' _ "$REPO_ROOT"
    )" || fail_test "lazygit macOS ARM asset selection failed"
    [[ "$macos_arm" == "Darwin_arm64" ]] \
        || fail_test "lazygit macOS ARM asset selection was incorrect"
}

test_fd_links_existing_fdfind() {
    local case_dir="$TEST_ROOT/fd-alias"
    local fake_bin="$case_dir/bin"

    mkdir -p "$case_dir/home" "$fake_bin"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$fake_bin/fdfind"
    chmod +x "$fake_bin/fdfind"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_path_contains_local_bin
            install_fd
            [[ -L "$HOME/.local/bin/fd" ]]
            [[ "$(readlink "$HOME/.local/bin/fd")" == "$2/fdfind" ]]
            fd --version
        ' _ "$REPO_ROOT" "$fake_bin" \
        || fail_test "existing fdfind was not linked as fd"
}

test_existing_unrunnable_tools_fail_without_replacement() {
    local case_dir="$TEST_ROOT/unrunnable-tools"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_bin/fd"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_bin/mq"
    chmod +x "$fake_bin/fd" "$fake_bin/mq"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        REPLACEMENT_ATTEMPTED="$case_dir/replacement-attempted" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_package() { touch "$REPLACEMENT_ATTEMPTED"; return 99; }
            curl() { touch "$REPLACEMENT_ATTEMPTED"; return 99; }
            if install_fd; then exit 10; fi
            if install_mq; then exit 11; fi
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "unrunnable existing tools were not reported as blocking"

    [[ ! -e "$case_dir/replacement-attempted" ]] \
        || fail_test "unrunnable existing tool triggered a replacement install"
}

test_lazygit_installs_verified_release() {
    local case_dir="$TEST_ROOT/lazygit-install"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        OSTYPE=linux-gnu \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            curl_calls=0
            curl() {
                local output="${!#}"

                curl_calls=$((curl_calls + 1))
                if [[ "$*" == *"api.github.com"* ]]; then
                    printf "%s\\n" \
                        "{\"tag_name\":\"v1.2.3\",\"assets\":[{\"name\":\"lazygit_1.2.3_Linux_x86_64.tar.gz\",\"browser_download_url\":\"https://example.invalid/lazygit.tar.gz\",\"digest\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}]}" \
                        > "$output"
                    return 0
                fi

                mkdir -p "$HOME/payload"
                printf "%s\\n" "#!/bin/sh" "exit 0" > "$HOME/payload/lazygit"
                chmod +x "$HOME/payload/lazygit"
                tar -czf "$output" -C "$HOME/payload" lazygit
            }
            sha256_file() {
                printf "%s\\n" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            }

            ensure_path_contains_local_bin
            install_lazygit
            [[ $curl_calls -eq 2 ]]
            [[ -x "$HOME/.local/bin/lazygit" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "verified lazygit release install failed"
}

test_lazygit_unsupported_architecture_skips_cleanly() {
    local case_dir="$TEST_ROOT/lazygit-unsupported"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        OSTYPE=linux-gnu \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && "${2:-}" == "lazygit" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            uname() { printf "%s\\n" armv7l; }
            install_lazygit
        ' _ "$REPO_ROOT"
    )" || fail_test "unsupported lazygit architecture aborted installation"

    [[ "$output" == *"automatic install is unavailable"* ]] \
        || fail_test "unsupported lazygit architecture was not reported"
}

test_installed_package_is_not_reinstalled() {
    local case_dir="$TEST_ROOT/existing-package"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'touch "$PACKAGE_INSTALL_CALLED"' \
        'exit 99' > "$fake_bin/apt-get"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s" "install ok installed"' > "$fake_bin/dpkg-query"
    chmod +x "$fake_bin/apt-get" "$fake_bin/dpkg-query"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        PACKAGE_INSTALL_CALLED="$case_dir/package-install-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            [[ "$PACKAGE_MANAGER" == "apt-get" ]]
            install_package existing-package
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "installed package was not preserved"

    [[ ! -e "$case_dir/package-install-called" ]] \
        || fail_test "installed package was passed to the package manager again"
}

test_uv_uses_unmanaged_local_bin_install() {
    local case_dir="$TEST_ROOT/uv-install"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            curl() {
                local output="${!#}"

                printf "%s\\n" \
                    "#!/usr/bin/env bash" \
                    "[[ \"\${UV_UNMANAGED_INSTALL:-}\" == \"\$HOME/.local/bin\" ]] || exit 20" \
                    "mkdir -p \"\$UV_UNMANAGED_INSTALL\"" \
                    "cp /bin/true \"\$UV_UNMANAGED_INSTALL/uv\"" \
                    > "$output"
            }

            ensure_path_contains_local_bin
            install_uv
            [[ -x "$HOME/.local/bin/uv" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "uv unmanaged local bin install failed"
}

test_existing_node_and_ai_clis_are_not_reinstalled() {
    local case_dir="$TEST_ROOT/existing-node-ai-clis"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin" "$case_dir/home/.nvm"
    cp /bin/true "$fake_bin/node"
    cp /bin/true "$fake_bin/codex"
    cp /bin/true "$fake_bin/claude"
    cp /bin/true "$fake_bin/gemini"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1" = "--version" ]; then printf "%s\n" "10.0.0"; exit 0; fi' \
        'touch "$NPM_INSTALL_CALLED"' \
        'exit 99' > "$fake_bin/npm"
    printf '%s\n' \
        '#!/bin/sh' \
        'touch "$CURL_CALLED"' \
        'exit 99' > "$fake_bin/curl"
    printf '%s\n' \
        'touch "$NVM_SOURCED"' \
        'nvm() { return 99; }' > "$case_dir/home/.nvm/nvm.sh"
    chmod +x "$fake_bin/npm" "$fake_bin/curl"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        NPM_INSTALL_CALLED="$case_dir/npm-install-called" \
        CURL_CALLED="$case_dir/curl-called" \
        NVM_SOURCED="$case_dir/nvm-sourced" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_nodejs_with_nvm
            install_codex_cli
            install_remote_cli "Claude Code" "claude" "https://example.invalid/claude" ""
            install_remote_cli "Gemini CLI" "gemini" "https://example.invalid/gemini" ""
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "existing Node.js AI CLIs were not preserved"

    [[ ! -e "$case_dir/npm-install-called" ]] \
        || fail_test "existing Node.js setup invoked an npm install"
    [[ ! -e "$case_dir/curl-called" ]] \
        || fail_test "existing AI CLI triggered a remote installer"
    [[ ! -e "$case_dir/nvm-sourced" ]] \
        || fail_test "existing Node.js setup loaded NVM and could switch versions"
}

test_system_node_uses_user_prefix_for_missing_npm_tool() {
    local case_dir="$TEST_ROOT/system-node-user-prefix"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin" "$case_dir/home"
    cp /bin/true "$fake_bin/node"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1" = "--version" ]; then printf "%s\n" "10.0.0"; exit 0; fi' \
        'printf "%s\n" "$*" > "$NPM_ARGS"' \
        '[ "$*" = "install -g --prefix $HOME/.local bun" ] || exit 21' \
        'mkdir -p "$HOME/.local/bin"' \
        'cp /bin/true "$HOME/.local/bin/bun"' \
        'cp /bin/true "$HOME/.local/bin/bunx"' > "$fake_bin/npm"
    chmod +x "$fake_bin/npm"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        NPM_ARGS="$case_dir/npm-args" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && "${2:-}" == "bun" && ! -x "$HOME/.local/bin/bun" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            install_nodejs_with_nvm
            install_bun
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "system Node.js did not install a missing npm tool to the user prefix"

    [[ "$(<"$case_dir/npm-args")" == "install -g --prefix $case_dir/home/.local bun" ]] \
        || fail_test "npm global install did not use the user-owned prefix"
    [[ -x "$case_dir/home/.local/bin/bun" ]] \
        || fail_test "user-prefix npm install did not expose the installed command"
}

test_broken_existing_node_and_npm_are_rejected_without_replacement() {
    local case_dir="$TEST_ROOT/broken-existing-node-npm"
    local fake_bin="$case_dir/bin"
    local output

    mkdir -p "$fake_bin" "$case_dir/home"
    cp /bin/false "$fake_bin/node"
    cp /bin/false "$fake_bin/npm"
    printf '%s\n' \
        '#!/bin/sh' \
        'touch "$CURL_CALLED"' \
        'exit 99' > "$fake_bin/curl"
    chmod +x "$fake_bin/curl"

    if output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="$fake_bin:/usr/bin:/bin" \
            CURL_CALLED="$case_dir/curl-called" \
            bash -c '
                source "$1/install.sh"
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                install_nodejs_with_nvm
            ' _ "$REPO_ROOT" 2>&1
    )"; then
        fail_test "broken existing Node.js/npm setup was accepted"
    fi

    [[ "$output" == *"incomplete or unusable; refusing to replace it"* ]] \
        || fail_test "broken existing Node.js/npm setup was not reported"
    [[ ! -e "$case_dir/curl-called" ]] \
        || fail_test "broken existing Node.js/npm setup triggered a replacement install"
}

test_active_existing_nvm_warns_without_modifying_bashrc() {
    local case_dir="$TEST_ROOT/active-existing-nvm-bash-warning"
    local nvm_dir="$case_dir/home/.nvm"
    local version_bin="$nvm_dir/versions/node/v20.0.0/bin"
    local output

    mkdir -p "$version_bin"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "v20.0.0"' > "$version_bin/node"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "10.0.0"' > "$version_bin/npm"
    chmod +x "$version_bin/node" "$version_bin/npm"
    printf '%s\n' \
        'nvm() {' \
        '    case "$1:$2" in' \
        '        current:) printf "%s\n" "v20.0.0" ;;' \
        '        version:default) printf "%s\n" "v20.0.0" ;;' \
        '        *) return 0 ;;' \
        '    esac' \
        '}' > "$nvm_dir/nvm.sh"
    printf '%s\n' '# user-managed bashrc' > "$case_dir/home/.bashrc"
    cp "$case_dir/home/.bashrc" "$case_dir/bashrc.before"

    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="$version_bin:/usr/bin:/bin" \
            bash -c '
                source "$1/install.sh"
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                install_nodejs_with_nvm
            ' _ "$REPO_ROOT"
    )" || fail_test "active existing NVM setup was not preserved"

    cmp -s "$case_dir/bashrc.before" "$case_dir/home/.bashrc" \
        || fail_test "active existing NVM setup modified a user-managed bashrc"
    [[ "$output" == *"Existing NVM is not initialized by Bash profile"* ]] \
        || fail_test "active existing NVM setup did not warn about future Bash shells"
}

test_inactive_existing_nvm_is_tried_before_rejecting_ambient_node() {
    local case_dir="$TEST_ROOT/inactive-existing-nvm"
    local fake_bin="$case_dir/bin"
    local nvm_dir="$case_dir/home/.nvm"
    local version_bin="$nvm_dir/versions/node/v20.0.0/bin"

    mkdir -p "$fake_bin" "$version_bin"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "system-node"' > "$fake_bin/node"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "v20.0.0"' > "$version_bin/node"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "10.0.0"' > "$version_bin/npm"
    chmod +x "$fake_bin/node" "$version_bin/node" "$version_bin/npm"
    printf '%s\n' \
        'touch "$NVM_SOURCED"' \
        'nvm() {' \
        '    case "$1:$2" in' \
        '        use:default) export PATH="$NVM_VERSION_BIN:$PATH" ;;' \
        '        version:default) printf "%s\n" "v20.0.0" ;;' \
        '        install:*) touch "$NVM_INSTALL_CALLED"; return 99 ;;' \
        '        *) return 0 ;;' \
        '    esac' \
        '}' > "$nvm_dir/nvm.sh"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        NVM_VERSION_BIN="$version_bin" \
        NVM_SOURCED="$case_dir/nvm-sourced" \
        NVM_INSTALL_CALLED="$case_dir/nvm-install-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && "${2:-}" == "npm" ]]; then
                    case ":$PATH:" in
                        *":$NVM_VERSION_BIN:"*) ;;
                        *) return 1 ;;
                    esac
                fi
                builtin command "$@"
            }

            install_nodejs_with_nvm
            [[ $NODE_NPM_AVAILABLE -eq 1 ]]
            [[ "$(command -v node)" == "$NVM_VERSION_BIN/node" ]]
            [[ "$(command -v npm)" == "$NVM_VERSION_BIN/npm" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "inactive existing NVM was not tried after ambient Node failed validation"

    [[ -e "$case_dir/nvm-sourced" ]] \
        || fail_test "inactive existing NVM was not sourced"
    [[ ! -e "$case_dir/nvm-install-called" ]] \
        || fail_test "inactive existing NVM triggered a new Node.js install"
}

test_new_nvm_dry_run_plans_bash_setup() {
    local case_dir="$TEST_ROOT/new-nvm-bash-setup-dry-run"
    local output

    mkdir -p "$case_dir/home"
    printf '%s\n' '# user-managed bashrc' > "$case_dir/home/.bashrc"

    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="/usr/bin:/bin" \
            bash -c '
                source "$1/install.sh"
                DRY_RUN=1
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                command() {
                    if [[ "$1" == "-v" && ( "${2:-}" == "node" || "${2:-}" == "npm" ) ]]; then
                        return 1
                    fi
                    builtin command "$@"
                }
                install_nodejs_with_nvm
            ' _ "$REPO_ROOT"
    )" || fail_test "new NVM dry-run setup failed"

    [[ "$output" == *"Would append NVM initialization"* ]] \
        || fail_test "new NVM setup did not retain installer-owned Bash initialization"
}

test_node_setup_failure_does_not_install_npm_for_consumers() {
    local case_dir="$TEST_ROOT/node-failure-npm-consumer"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin" "$case_dir/home"
    cp /bin/true "$fake_bin/node"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        PACKAGE_INSTALL_CALLED="$case_dir/package-install-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && ( "${2:-}" == "npm" || "${2:-}" == "bun" ) ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            install_package() {
                touch "$PACKAGE_INSTALL_CALLED"
                return 99
            }
            if install_nodejs_with_nvm; then exit 10; fi
            if install_bun; then exit 11; fi
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "npm consumer handling failed after Node.js setup failure"

    [[ ! -e "$case_dir/package-install-called" ]] \
        || fail_test "npm consumer attempted to install npm through the package manager"
}

test_existing_nvm_version_becomes_persistent_default() {
    local case_dir="$TEST_ROOT/nvm-persistent-default"
    local nvm_dir="$case_dir/home/.nvm"
    local version_bin="$nvm_dir/versions/node/v20.11.1/bin"

    mkdir -p "$version_bin"
    cp /bin/true "$version_bin/node"
    cp /bin/true "$version_bin/npm"
    printf '%s\n' \
        'export NVM_DIR="$HOME/.nvm"' \
        'nvm() {' \
        '    case "$1:$2" in' \
        '        use:default) return 3 ;;' \
        '        use:v20.11.1) export PATH="$NVM_DIR/versions/node/v20.11.1/bin:$PATH" ;;' \
        '        version:node) printf "%s\n" "v20.11.1" ;;' \
        '        alias:default) printf "%s\n" "$3" > "$NVM_DEFAULT_SET" ;;' \
        '        current:) printf "%s\n" "none" ;;' \
        '        *) return 4 ;;' \
        '    esac' \
        '}' > "$nvm_dir/nvm.sh"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="/usr/bin:/bin" \
        NVM_DEFAULT_SET="$case_dir/default-version" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && ( "${2:-}" == "node" || "${2:-}" == "npm" ) ]]; then
                    case ":$PATH:" in
                        *":$HOME/.nvm/versions/node/v20.11.1/bin:"*) ;;
                        *) return 1 ;;
                    esac
                fi
                builtin command "$@"
            }
            install_nodejs_with_nvm
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "existing NVM version was not activated and persisted"

    [[ "$(<"$case_dir/default-version")" == "v20.11.1" ]] \
        || fail_test "reused NVM version was not saved as the default"
}

test_planned_npm_is_reused_by_dry_run_installers() {
    local case_dir="$TEST_ROOT/planned-npm-dry-run"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="/usr/bin:/bin" \
            CARGO_FALLBACK_CALLED="$case_dir/cargo-fallback-called" \
            bash -c '
                source "$1/install.sh"
                DRY_RUN=1
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                command() {
                    if [[ "$1" == "-v" ]]; then
                        case "${2:-}" in
                            node|npm|codex|tree-sitter) return 1 ;;
                        esac
                    fi
                    builtin command "$@"
                }
                install_nodejs_with_nvm
                install_codex_cli
                install_tree_sitter_cli_with_cargo() {
                    touch "$CARGO_FALLBACK_CALLED"
                    return 99
                }
                install_tree_sitter_cli
            ' _ "$REPO_ROOT"
    )" || fail_test "dry-run installers did not reuse the planned npm command"

    [[ "$output" == *"npm install -g --prefix $case_dir/home/.local @openai/codex"* ]] \
        || fail_test "Codex dry-run did not plan its npm install"
    [[ "$output" == *"npm install -g --prefix $case_dir/home/.local --allow-scripts=tree-sitter-cli tree-sitter-cli"* ]] \
        || fail_test "tree-sitter dry-run did not reuse the planned npm command"
    [[ ! -e "$case_dir/cargo-fallback-called" ]] \
        || fail_test "tree-sitter dry-run chose Cargo despite npm being planned"
}

test_existing_npm_tools_skip_prerequisite_installers() {
    local case_dir="$TEST_ROOT/existing-npm-tools"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin"
    cp /bin/true "$fake_bin/agent-browser"
    cp /bin/true "$fake_bin/ast-grep"
    cp /bin/true "$fake_bin/codegraph"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        PREREQUISITE_CALLED="$case_dir/prerequisite-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_required_command() {
                touch "$PREREQUISITE_CALLED"
                return 99
            }
            install_agent_browser
            install_ast_grep
            install_codegraph
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "existing npm tools did not skip their installers"

    [[ ! -e "$case_dir/prerequisite-called" ]] \
        || fail_test "existing npm tool checked or installed npm"
}

test_bun_installs_with_npm() {
    local case_dir="$TEST_ROOT/bun-install"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            npm_checked=0
            ensure_required_command() {
                [[ "$1" == "npm" ]] || return 1
                npm_checked=1
            }
            npm() {
                [[ "$*" == "install -g --prefix $HOME/.local bun" ]] || return 1
                mkdir -p "$HOME/.local/bin"
                cp /bin/true "$HOME/.local/bin/bun"
                cp /bin/true "$HOME/.local/bin/bunx"
            }

            ensure_path_contains_local_bin
            install_bun
            [[ $npm_checked -eq 1 ]]
            [[ -x "$HOME/.local/bin/bun" ]]
            [[ -x "$HOME/.local/bin/bunx" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "Bun npm install failed"
}

test_zsh_dependencies_are_installed() {
    local case_dir="$TEST_ROOT/zsh-dependencies"

    mkdir -p "$case_dir/home/.oh-my-zsh/custom"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_required_command() {
                [[ "$1" == "fzf" ]]
            }
            git() {
                local target="${!#}"

                [[ "$1" == "clone" ]] || return 1
                mkdir -p "$target"
                case "$target" in
                    */themes/spaceship-prompt)
                        printf "%s\\n" "theme" > "$target/spaceship.zsh-theme"
                        ;;
                    */plugins/spaceship-vi-mode)
                        printf "%s\\n" "plugin" > "$target/spaceship-vi-mode.plugin.zsh"
                        ;;
                    */plugins/zsh-autocomplete)
                        printf "%s\\n" "plugin" > "$target/zsh-autocomplete.plugin.zsh"
                        ;;
                    *)
                        return 1
                        ;;
                esac
            }

            install_zsh_dependencies
            custom="$HOME/.oh-my-zsh/custom"
            [[ -f "$custom/themes/spaceship-prompt/spaceship.zsh-theme" ]]
            [[ -L "$custom/themes/spaceship.zsh-theme" ]]
            [[ -f "$custom/plugins/spaceship-vi-mode/spaceship-vi-mode.plugin.zsh" ]]
            [[ -f "$custom/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "Zsh dependencies were not installed"
}

test_mq_release_selection() {
    local linux_gnu
    local linux_musl
    local linux_arm
    local macos_arm

    linux_gnu="$(
        OSTYPE=linux-gnu \
        bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" x86_64; }
            ldd() { printf "%s\\n" "ldd (GNU libc)"; }
            mq_release_info
        ' _ "$REPO_ROOT"
    )" || fail_test "mq Linux GNU release selection failed"
    [[ "$linux_gnu" == $'mq-x86_64-unknown-linux-gnu\t88ac9db1a62e3cc5213224a4cbe75ab8924dbca6cc6a988ecb9cafa538ed02cf' ]] \
        || fail_test "mq Linux GNU release selection was incorrect"

    linux_musl="$(
        OSTYPE=linux-musl \
        bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" x86_64; }
            ldd() { printf "%s\\n" "musl libc"; }
            mq_release_info
        ' _ "$REPO_ROOT"
    )" || fail_test "mq Linux musl release selection failed"
    [[ "$linux_musl" == $'mq-x86_64-unknown-linux-musl\t55078ec75f6be6092a3cd72d9bcb5a88ad700c98465b2907a3d146c600e02227' ]] \
        || fail_test "mq Linux musl release selection was incorrect"

    linux_arm="$(
        OSTYPE=linux-gnu \
        bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" aarch64; }
            ldd() { printf "%s\\n" "ldd (GNU libc)"; }
            mq_release_info
        ' _ "$REPO_ROOT"
    )" || fail_test "mq Linux ARM release selection failed"
    [[ "$linux_arm" == $'mq-aarch64-unknown-linux-gnu\t8b567fd2a0360de8ce8c82397d2ee260ff1fa5c73535a07cf75aac43588660ff' ]] \
        || fail_test "mq Linux ARM release selection was incorrect"

    macos_arm="$(
        OSTYPE=darwin23 \
        bash -c '
            source "$1/install.sh"
            uname() { printf "%s\\n" arm64; }
            mq_release_info
        ' _ "$REPO_ROOT"
    )" || fail_test "mq macOS release selection failed"
    [[ "$macos_arm" == $'mq-aarch64-apple-darwin\tee11cee3d6855a8d23005a56d77013b14738838abe4a656bd82aeb884ee06645' ]] \
        || fail_test "mq macOS release selection was incorrect"
}

test_mq_dry_run_plans_pinned_binary() {
    local case_dir="$TEST_ROOT/mq-dry-run"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        OSTYPE=linux-gnu \
        bash -c '
            source "$1/install.sh"
            command() {
                if [[ "$1" == "-v" && "${2:-}" == "mq" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            uname() { printf "%s\\n" x86_64; }
            DRY_RUN=1
            install_mq
        ' _ "$REPO_ROOT"
    )" || fail_test "mq dry-run plan failed"

    [[ "$output" == *"mq-x86_64-unknown-linux-gnu"* ]] \
        || fail_test "mq dry-run did not select the pinned Linux binary"
    [[ "$output" == *"88ac9db1a62e3cc5213224a4cbe75ab8924dbca6cc6a988ecb9cafa538ed02cf"* ]] \
        || fail_test "mq dry-run did not show the binary checksum"
    [[ ! -e "$case_dir/home/.local/bin/mq" ]] \
        || fail_test "mq dry-run created the binary target"
}

test_mq_intel_macos_uses_pinned_cargo_install() {
    local case_dir="$TEST_ROOT/mq-intel-macos-cargo"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        OSTYPE=darwin23 \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            [[ "$OS" == "macos" ]] || exit 10
            uname() { printf "%s\\n" x86_64; }
            curl() { return 99; }
            cargo() {
                local root=""
                local expected

                if [[ "$1" == "--version" ]]; then
                    printf "%s\\n" "cargo 1.0.0"
                    return 0
                fi

                printf "%s\\n" "$*" > "$HOME/cargo-args"
                while [[ $# -gt 0 ]]; do
                    if [[ "$1" == "--root" ]]; then
                        root="$2"
                        shift 2
                    else
                        shift
                    fi
                done
                [[ -n "$root" ]] || return 1
                mkdir -p "$root/bin"
                printf "%s\\n" "#!/bin/sh" "exit 0" > "$root/bin/mq"
                chmod +x "$root/bin/mq"
                expected="install --root $HOME/.local mq-run --version 0.7.0 --locked"
                [[ "$(<"$HOME/cargo-args")" == "$expected" ]]
            }

            ensure_path_contains_local_bin
            DRY_RUN=1
            install_mq
            [[ ! -e "$HOME/.local/bin/mq" ]]
            [[ ! -e "$HOME/cargo-args" ]]
            DRY_RUN=0
            install_mq
            [[ -x "$HOME/.local/bin/mq" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "mq Intel macOS Cargo install failed"
}

test_mq_intel_macos_without_cargo_skips_cleanly() {
    local case_dir="$TEST_ROOT/mq-intel-macos-no-cargo"
    local output

    mkdir -p "$case_dir/home"
    output="$(
        HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        OSTYPE=darwin23 \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            [[ "$OS" == "macos" ]] || exit 10
            command() {
                if [[ "$1" == "-v" && ( "${2:-}" == "cargo" || "${2:-}" == "mq" ) ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            uname() { printf "%s\\n" x86_64; }
            install_mq
            [[ ! -e "$HOME/.local/bin/mq" ]]
        ' _ "$REPO_ROOT"
    )" || fail_test "mq Intel macOS missing-Cargo path did not skip cleanly"

    [[ "$output" == *"Cargo is unavailable"* ]] \
        || fail_test "mq Intel macOS missing-Cargo path did not explain the prerequisite"
}

test_mq_failed_binary_is_removed_and_retryable() {
    local case_dir="$TEST_ROOT/mq-invalid-binary"

    mkdir -p "$case_dir/home"
    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="/usr/bin:/bin" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            uname() { printf "%s\\n" x86_64; }
            ldd() { printf "%s\\n" "ldd (GNU libc)"; }
            curl_calls=0
            curl() {
                local output="${!#}"

                curl_calls=$((curl_calls + 1))
                if [[ $curl_calls -eq 1 ]]; then
                    printf "%s\\n" "#!/bin/sh" "exit 1" > "$output"
                else
                    printf "%s\\n" "#!/bin/sh" "exit 0" > "$output"
                fi
            }
            sha256_file() {
                printf "%s\\n" "88ac9db1a62e3cc5213224a4cbe75ab8924dbca6cc6a988ecb9cafa538ed02cf"
            }

            ensure_path_contains_local_bin
            if install_mq; then
                exit 10
            fi
            [[ ! -e "$HOME/.local/bin/mq" ]] || exit 11
            install_mq
            [[ $curl_calls -eq 2 ]] || exit 12
            [[ -x "$HOME/.local/bin/mq" ]]
        ' _ "$REPO_ROOT" \
        || fail_test "mq invalid binary was not cleaned up for retry"
}

test_existing_tree_sitter_is_not_upgraded() {
    local case_dir="$TEST_ROOT/tree-sitter-existing"
    local fake_bin="$case_dir/bin"
    local output

    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s\n" "tree-sitter 0.20.8"' > "$fake_bin/tree-sitter"
    printf '%s\n' \
        '#!/bin/sh' \
        'touch "$NPM_CALLED"' \
        'exit 99' > "$fake_bin/npm"
    chmod +x "$fake_bin/tree-sitter" "$fake_bin/npm"

    if output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            PATH="$fake_bin:/usr/bin:/bin" \
            NPM_CALLED="$case_dir/npm-called" \
            bash -c '
                source "$1/install.sh"
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                install_tree_sitter_cli
            ' _ "$REPO_ROOT"
    )"; then
        fail_test "existing unsupported tree-sitter CLI was accepted"
    fi

    [[ ! -e "$case_dir/npm-called" ]] \
        || fail_test "existing tree-sitter CLI was upgraded with npm"
    [[ "$output" == *"requires 0.26.1 or newer and will not be replaced"* ]] \
        || fail_test "existing old tree-sitter CLI did not report the blocking incompatibility"
}

test_existing_tree_sitter_target_is_not_replaced() {
    local case_dir="$TEST_ROOT/tree-sitter-existing-target"
    local fake_bin="$case_dir/bin"
    local target="$case_dir/home/.local/bin/tree-sitter"
    local original_target="$case_dir/original-tree-sitter"

    mkdir -p "$fake_bin" "$(dirname "$target")"
    ln -s "$original_target" "$target"
    printf '%s\n' '#!/bin/sh' 'touch "$INSTALLER_CALLED"' 'exit 99' > "$fake_bin/npm"
    printf '%s\n' '#!/bin/sh' 'touch "$INSTALLER_CALLED"' 'exit 99' > "$fake_bin/cargo"
    chmod +x "$fake_bin/npm" "$fake_bin/cargo"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        INSTALLER_CALLED="$case_dir/installer-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && "${2:-}" == "tree-sitter" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            if install_tree_sitter_cli; then exit 10; fi
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "existing unavailable tree-sitter target was not reported as blocking"

    [[ -L "$target" && "$(readlink "$target")" == "$original_target" ]] \
        || fail_test "existing tree-sitter target was removed or replaced"
    [[ ! -e "$case_dir/installer-called" ]] \
        || fail_test "existing tree-sitter target triggered a replacement installer"
}

test_planned_cargo_is_reused_by_tree_sitter_dry_run() {
    local case_dir="$TEST_ROOT/planned-cargo-dry-run"
    local output

    mkdir -p "$case_dir/home" "$case_dir/tmp"
    output="$(
        HOME="$case_dir/home" \
            XDG_STATE_HOME="$case_dir/state" \
            XDG_DATA_HOME="$case_dir/data" \
            TMPDIR="$case_dir/tmp" \
            PATH="/usr/bin:/bin" \
            bash -c '
                source "$1/install.sh"
                DRY_RUN=1
                USE_COLOR=0
                RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
                command() {
                    if [[ "$1" == "-v" ]]; then
                        case "${2:-}" in
                            cargo|rustup) return 1 ;;
                        esac
                    fi
                    builtin command "$@"
                }
                ensure_libclang() { return 0; }
                install_tree_sitter_cli_with_cargo 0.26.1
            ' _ "$REPO_ROOT"
    )" || fail_test "tree-sitter Cargo dry-run rejected the planned Rust toolchain"

    [[ "$output" == *"rustup run stable cargo install --root $case_dir/tmp/tree-sitter-cargo.XXXXXX tree-sitter-cli --locked"* ]] \
        || fail_test "tree-sitter Cargo dry-run did not report the planned Cargo command"
    [[ "$output" == *"Would install the verified tree-sitter CLI to: $case_dir/home/.local/bin/tree-sitter"* ]] \
        || fail_test "tree-sitter Cargo dry-run did not report the verified publish target"
}

test_tree_sitter_allows_npm_install_script_and_falls_back_to_cargo() {
    local case_dir="$TEST_ROOT/tree-sitter-approval"
    local fake_bin="$case_dir/bin"
    local fake_lib_dir="$case_dir/libclang"
    local cargo_root

    mkdir -p "$fake_bin" "$fake_lib_dir" "$case_dir/tmp"
    touch "$fake_lib_dir/libclang.so.1"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s\n" "$*" >> "$TREE_SITTER_NPM_ACTIONS"' \
        'if [ "$1" = "--version" ]; then printf "%s\n" "10.0.0"; exit 0; fi' \
        'case "$1 $2" in' \
        '  "install -g")' \
        '    case " $* " in *" --prefix $HOME/.local "*) ;; *) exit 1 ;; esac' \
        '    case " $* " in *" --allow-scripts=tree-sitter-cli "*) ;; *) exit 1 ;; esac' \
        '    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/node_modules/tree-sitter-cli"' \
        '    printf "%s\n" "#!/bin/sh" "exit 1" > "$TREE_SITTER_BIN"' \
        '    chmod +x "$TREE_SITTER_BIN"' \
        '    touch "$TREE_SITTER_INSTALLED" ;;' \
        '  "rebuild -g")' \
        '    case " $* " in *" --prefix $HOME/.local "*) ;; *) exit 1 ;; esac' \
        '    case " $* " in *" --allow-scripts=tree-sitter-cli "*) ;; *) exit 1 ;; esac' \
        '    test -f "$TREE_SITTER_INSTALLED" || exit 1' \
        '    ;;' \
        '  "uninstall -g")' \
        '    case " $* " in *" --prefix $HOME/.local "*) ;; *) exit 1 ;; esac' \
        '    rm -rf "$HOME/.local/lib/node_modules/tree-sitter-cli"' \
        '    rm -f "$TREE_SITTER_BIN"' \
        '    touch "$TREE_SITTER_NPM_REMOVED" ;;' \
        '  *) exit 1 ;;' \
        'esac' > "$fake_bin/npm"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  --version) printf "%s\n" "cargo 1.85.0" ;;' \
        '  install)' \
        '    case " $* " in *" tree-sitter-cli --locked "*) ;; *) exit 1 ;; esac' \
        '    root=""' \
        '    while [ "$#" -gt 0 ]; do' \
        '      case "$1" in' \
        '        --root) root="$2"; shift 2 ;;' \
        '        *) shift ;;' \
        '      esac' \
        '    done' \
        '    test -n "$root" || exit 1' \
        '    printf "%s\n" "$root" > "$TREE_SITTER_CARGO_ROOT"' \
        '    if [ -e "$TREE_SITTER_BIN" ] || [ -L "$TREE_SITTER_BIN" ] ||' \
        '        [ -e "$HOME/.local/lib/node_modules/tree-sitter-cli" ]; then' \
        '        touch "$TREE_SITTER_CARGO_COLLISION"' \
        '        exit 41' \
        '    fi' \
        '    touch "$TREE_SITTER_TARGET_WAS_FREE"' \
        '    mkdir -p "$root/bin"' \
        '    printf "%s\n" "#!/bin/sh" "printf '\''tree-sitter 0.26.11\\n'\''" > "$root/bin/tree-sitter"' \
        '    chmod +x "$root/bin/tree-sitter"' \
        '    touch "$TREE_SITTER_CARGO_INSTALLED" ;;' \
        '  *) exit 1 ;;' \
        'esac' > "$fake_bin/cargo"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  --version) printf "%s\n" "rustup 1.28.2" ;;' \
        '  toolchain)' \
        '    [ "$2 $3 $4 $5" = "install stable --profile minimal" ] || exit 1' \
        '    touch "$RUSTUP_TOOLCHAIN_INSTALLED" ;;' \
        '  run)' \
        '    [ "$2 $3" = "stable cargo" ] || exit 1' \
        '    shift 3' \
        '    exec cargo "$@" ;;' \
        '  *) exit 1 ;;' \
        'esac' > "$fake_bin/rustup"
    chmod +x "$fake_bin/npm" "$fake_bin/cargo" "$fake_bin/rustup"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        TMPDIR="$case_dir/tmp" \
        PATH="$fake_bin:/usr/bin:/bin" \
        LIBCLANG_PATH="$fake_lib_dir" \
        TREE_SITTER_INSTALLED="$case_dir/installed" \
        TREE_SITTER_NPM_ACTIONS="$case_dir/npm-actions" \
        TREE_SITTER_NPM_REMOVED="$case_dir/npm-removed" \
        TREE_SITTER_BIN="$case_dir/home/.local/bin/tree-sitter" \
        TREE_SITTER_CARGO_INSTALLED="$case_dir/cargo-installed" \
        TREE_SITTER_CARGO_ROOT="$case_dir/cargo-root" \
        TREE_SITTER_CARGO_COLLISION="$case_dir/cargo-collision" \
        TREE_SITTER_TARGET_WAS_FREE="$case_dir/target-was-free" \
        RUSTUP_TOOLCHAIN_INSTALLED="$case_dir/rustup-toolchain-installed" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            command() {
                if [[ "$1" == "-v" && "${2:-}" == "tree-sitter" && ! -x "$TREE_SITTER_BIN" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            install_tree_sitter_cli
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "tree-sitter CLI install did not fall back to Cargo"
    [[ -f "$case_dir/cargo-installed" ]] \
        || fail_test "tree-sitter CLI Cargo fallback was not used"
    [[ -f "$case_dir/npm-removed" ]] \
        || fail_test "tree-sitter npm ownership was not removed before Cargo fallback: $(<"$case_dir/npm-actions")"
    [[ -f "$case_dir/target-was-free" && ! -e "$case_dir/cargo-collision" ]] \
        || fail_test "tree-sitter npm launcher was not removed before Cargo fallback"
    [[ ! -f "$case_dir/rustup-toolchain-installed" ]] \
        || fail_test "tree-sitter CLI updated Rust despite existing Cargo"
    cargo_root="$(<"$case_dir/cargo-root")"
    [[ "$cargo_root" == "$case_dir/tmp"/tree-sitter-cargo.* ]] \
        || fail_test "tree-sitter Cargo fallback did not use a temporary install root: $cargo_root"
    [[ ! -e "$cargo_root" ]] \
        || fail_test "tree-sitter Cargo fallback left its temporary install root behind"
    [[ "$("$case_dir/home/.local/bin/tree-sitter" --version)" == "tree-sitter 0.26.11" ]] \
        || fail_test "verified tree-sitter Cargo binary was not published"
}

test_tree_sitter_cargo_retries_existing_stable_toolchain() {
    local case_dir="$TEST_ROOT/tree-sitter-cargo-stable-retry"
    local fake_bin="$case_dir/bin"
    local fake_lib_dir="$case_dir/libclang"
    local stable_root

    mkdir -p "$fake_bin" "$fake_lib_dir" "$case_dir/tmp"
    touch "$fake_lib_dir/libclang.so.1"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  --version) printf "%s\n" "cargo 1.60.0" ;;' \
        '  install) touch "$DIRECT_CARGO_CALLED"; exit 42 ;;' \
        '  *) exit 1 ;;' \
        'esac' > "$fake_bin/cargo"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  run)' \
        '    [ "$2 $3" = "stable cargo" ] || exit 1' \
        '    shift 3' \
        '    case "$1" in' \
        '      --version) printf "%s\n" "cargo 1.90.0" ;;' \
        '      install)' \
        '        root=""' \
        '        while [ "$#" -gt 0 ]; do' \
        '          case "$1" in' \
        '            --root) root="$2"; shift 2 ;;' \
        '            *) shift ;;' \
        '          esac' \
        '        done' \
        '        test -n "$root" || exit 1' \
        '        printf "%s\n" "$root" > "$STABLE_CARGO_ROOT"' \
        '        mkdir -p "$root/bin"' \
        '        printf "%s\n" "#!/bin/sh" "printf '\''tree-sitter 0.26.11\\n'\''" > "$root/bin/tree-sitter"' \
        '        chmod +x "$root/bin/tree-sitter"' \
        '        touch "$STABLE_CARGO_CALLED" ;;' \
        '      *) exit 1 ;;' \
        '    esac ;;' \
        '  toolchain) touch "$RUSTUP_TOOLCHAIN_INSTALL_CALLED"; exit 99 ;;' \
        '  *) exit 1 ;;' \
        'esac' > "$fake_bin/rustup"
    chmod +x "$fake_bin/cargo" "$fake_bin/rustup"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        TMPDIR="$case_dir/tmp" \
        PATH="$fake_bin:/usr/bin:/bin" \
        LIBCLANG_PATH="$fake_lib_dir" \
        DIRECT_CARGO_CALLED="$case_dir/direct-cargo-called" \
        STABLE_CARGO_CALLED="$case_dir/stable-cargo-called" \
        STABLE_CARGO_ROOT="$case_dir/stable-cargo-root" \
        RUSTUP_TOOLCHAIN_INSTALL_CALLED="$case_dir/rustup-toolchain-install-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            install_tree_sitter_cli_with_cargo 0.26.1
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "tree-sitter Cargo build did not retry the existing stable toolchain"

    [[ -e "$case_dir/direct-cargo-called" && -e "$case_dir/stable-cargo-called" ]] \
        || fail_test "tree-sitter Cargo build did not try both existing toolchains"
    [[ ! -e "$case_dir/rustup-toolchain-install-called" ]] \
        || fail_test "tree-sitter Cargo fallback installed or updated the stable toolchain"
    stable_root="$(<"$case_dir/stable-cargo-root")"
    [[ ! -e "$stable_root" ]] \
        || fail_test "tree-sitter stable Cargo fallback left its temporary root behind"
    [[ "$("$case_dir/home/.local/bin/tree-sitter" --version)" == "tree-sitter 0.26.11" ]] \
        || fail_test "tree-sitter stable Cargo fallback did not publish the verified binary"
}

test_failed_tree_sitter_cargo_build_is_retryable() {
    local case_dir="$TEST_ROOT/tree-sitter-cargo-retry"
    local fake_bin="$case_dir/bin"
    local fake_lib_dir="$case_dir/libclang"
    local failed_root

    mkdir -p "$fake_bin" "$fake_lib_dir" "$case_dir/tmp"
    touch "$fake_lib_dir/libclang.so.1"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '  --version) printf "%s\n" "cargo 1.85.0" ;;' \
        '  install)' \
        '    root=""' \
        '    while [ "$#" -gt 0 ]; do' \
        '      case "$1" in' \
        '        --root) root="$2"; shift 2 ;;' \
        '        *) shift ;;' \
        '      esac' \
        '    done' \
        '    test -n "$root" || exit 1' \
        '    mkdir -p "$root/bin"' \
        '    if [ ! -e "$CARGO_FIRST_ATTEMPT" ]; then' \
        '      touch "$CARGO_FIRST_ATTEMPT"' \
        '      printf "%s\n" "$root" > "$FAILED_CARGO_ROOT"' \
        '      printf "%s\n" "#!/bin/sh" "exit 1" > "$root/bin/tree-sitter"' \
        '    else' \
        '      printf "%s\n" "#!/bin/sh" "printf '\''tree-sitter 0.26.11\\n'\''" > "$root/bin/tree-sitter"' \
        '    fi' \
        '    chmod +x "$root/bin/tree-sitter" ;;' \
        '  *) exit 1 ;;' \
        'esac' > "$fake_bin/cargo"
    chmod +x "$fake_bin/cargo"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        TMPDIR="$case_dir/tmp" \
        PATH="$fake_bin:/usr/bin:/bin" \
        LIBCLANG_PATH="$fake_lib_dir" \
        CARGO_FIRST_ATTEMPT="$case_dir/first-attempt" \
        FAILED_CARGO_ROOT="$case_dir/failed-root" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            if install_tree_sitter_cli_with_cargo 0.26.1; then exit 10; fi
            [[ ! -e "$HOME/.local/bin/tree-sitter" && ! -L "$HOME/.local/bin/tree-sitter" ]]
            install_tree_sitter_cli_with_cargo 0.26.1
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "failed tree-sitter Cargo build was not retryable"

    failed_root="$(<"$case_dir/failed-root")"
    [[ ! -e "$failed_root" ]] \
        || fail_test "failed tree-sitter Cargo build left its temporary root behind"
    [[ "$("$case_dir/home/.local/bin/tree-sitter" --version)" == "tree-sitter 0.26.11" ]] \
        || fail_test "tree-sitter Cargo retry did not publish the verified binary"
}

test_existing_cargo_is_not_replaced_by_rustup() {
    local case_dir="$TEST_ROOT/existing-cargo"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s\n" "cargo 1.63.0"' > "$fake_bin/cargo"
    printf '%s\n' \
        '#!/bin/sh' \
        'touch "$RUSTUP_CURL_CALLED"' \
        'exit 99' > "$fake_bin/curl"
    chmod +x "$fake_bin/cargo" "$fake_bin/curl"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        RUSTUP_CURL_CALLED="$case_dir/rustup-curl-called" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_rust_cargo
            cargo --version | grep -Fqx "cargo 1.63.0"
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "existing Cargo was not preserved"
    [[ ! -f "$case_dir/rustup-curl-called" ]] \
        || fail_test "existing Cargo triggered a Rust replacement install"
}

test_rustup_stable_handles_broken_cargo_proxy() {
    local case_dir="$TEST_ROOT/rustup-broken-cargo-proxy"
    local fake_bin="$case_dir/bin"

    mkdir -p "$fake_bin"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_bin/cargo"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$1" in' \
        '    --version) printf "%s\n" "rustup 1.28.2" ;;' \
        '    run)' \
        '        [ "$2 $3 $4" = "stable cargo --version" ] || exit 2' \
        '        printf "%s\n" "cargo 1.85.0" ;;' \
        '    toolchain) touch "$RUSTUP_TOOLCHAIN_INSTALLED"; exit 99 ;;' \
        '    *) exit 3 ;;' \
        'esac' > "$fake_bin/rustup"
    chmod +x "$fake_bin/cargo" "$fake_bin/rustup"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        RUSTUP_TOOLCHAIN_INSTALLED="$case_dir/toolchain-installed" \
        bash -c '
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_rust_cargo
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "usable rustup stable toolchain did not satisfy a broken Cargo proxy"

    [[ ! -e "$case_dir/toolchain-installed" ]] \
        || fail_test "existing rustup stable toolchain was unnecessarily reinstalled"
}

test_libclang_is_installed_when_missing() {
    local case_dir="$TEST_ROOT/libclang-install"
    local fake_bin="$case_dir/bin"
    local fake_lib_dir="$case_dir/libclang"

    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1" = "/usr/lib" ] && [ -f "$LIBCLANG_INSTALLED" ]; then' \
        '    printf "%s\n" "$LIBCLANG_TEST_DIR/libclang.so.1"' \
        'fi' > "$fake_bin/find"
    printf '%s\n' \
        '#!/bin/sh' \
        'exec "$@"' > "$fake_bin/sudo"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1 $2 $3" = "install -y libclang-dev" ]; then' \
        '    mkdir -p "$LIBCLANG_TEST_DIR"' \
        '    touch "$LIBCLANG_TEST_DIR/libclang.so.1" "$LIBCLANG_INSTALLED"' \
        '    exit 0' \
        'fi' \
        'exit 1' > "$fake_bin/apt-get"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fake_bin/dpkg-query"
    chmod +x "$fake_bin/find" "$fake_bin/sudo" "$fake_bin/apt-get" "$fake_bin/dpkg-query"

    HOME="$case_dir/home" \
        XDG_STATE_HOME="$case_dir/state" \
        XDG_DATA_HOME="$case_dir/data" \
        PATH="$fake_bin:/usr/bin:/bin" \
        LIBCLANG_INSTALLED="$case_dir/installed" \
        LIBCLANG_TEST_DIR="$fake_lib_dir" \
        bash -c '
            unset LIBCLANG_PATH
            source "$1/install.sh"
            USE_COLOR=0
            RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
            ensure_libclang
            [[ "$LIBCLANG_PATH" == "$LIBCLANG_TEST_DIR" ]]
        ' _ "$REPO_ROOT" >/dev/null \
        || fail_test "libclang was not installed when missing"
    [[ -f "$case_dir/installed" ]] \
        || fail_test "libclang package installation was not attempted"
}

test_best_effort_continues_and_counts_failures
test_dry_run_summary_propagates_best_effort_failure
test_waypost_preparation_requires_explicit_migration
test_waypost_preparation_gates_dependent_assets
test_zsh_stack_gates_dependencies_after_core_failure
test_zsh_stack_readiness_gates_only_zshrc
test_failed_zsh_clones_leave_retryable_targets
test_dangling_oh_my_zsh_symlink_is_preserved
test_dry_run_rejects_installed_package_with_missing_resource
test_required_tools_check_every_item_best_effort
test_local_bin_path_injection_reports_persistence_limit
test_shared_agent_snapshot_preserves_local_content
test_failed_shared_snapshot_preserves_existing_consumer_links
test_selected_snapshot_failure_skips_ai_skills_and_continues
test_zshrc_uses_managed_copy_merge
test_shell_configs_clean_path
test_bashrc_preserves_ambient_node_when_loading_nvm
test_component_selection_parsing
test_selected_submodule_paths_follow_components
test_partial_home_and_xdg_initialize_submodules_before_copy
test_partial_submodule_failure_skips_gitlink_configs_and_continues
test_config_installers_skip_unavailable_submodule_sources
test_full_submodule_failure_is_reported
test_partial_ai_skills_detects_agent_deck_from_local_bin
test_ai_skills_only_skips_unrelated_bootstrap
test_managed_copy_dry_run_is_read_only
test_managed_copy_dry_run_plans_updates_without_staging
test_unrelated_repository_symlink_is_preserved
test_expected_repository_symlink_is_migrated
test_shared_link_migration_is_exact
test_unmodified_directory_to_file_transition
test_source_deletion_and_user_addition
test_non_overlapping_file_changes_merge
test_overlapping_file_changes_conflict
test_merge_scratch_does_not_collide_with_sibling
test_deleted_directory_preserves_target_only_content
test_deleted_unmodified_directory_is_removed
test_deleted_directory_modified_managed_content_conflicts
test_local_deletion_is_restored
test_upstream_deletion_local_modification_conflicts
test_local_deletion_upstream_modification_is_restored
test_root_local_deletion_is_restored
test_root_local_deletion_upstream_modification_is_restored
test_excluded_target_directories_are_preserved
test_target_only_symlink_is_preserved
test_relative_repository_symlink_is_rejected_at_final_path
test_indirect_repository_symlink_is_rejected
test_safe_relative_symlink_is_preserved_in_snapshot
test_conflicting_user_addition_requires_force
test_executable_mode_update
test_non_executable_mode_update
test_local_directory_mode_is_preserved_with_upstream_update
test_macos_path_mode_uses_bsd_stat
test_lazygit_asset_selection
test_fd_links_existing_fdfind
test_existing_unrunnable_tools_fail_without_replacement
test_lazygit_installs_verified_release
test_lazygit_unsupported_architecture_skips_cleanly
test_installed_package_is_not_reinstalled
test_uv_uses_unmanaged_local_bin_install
test_existing_node_and_ai_clis_are_not_reinstalled
test_system_node_uses_user_prefix_for_missing_npm_tool
test_broken_existing_node_and_npm_are_rejected_without_replacement
test_active_existing_nvm_warns_without_modifying_bashrc
test_inactive_existing_nvm_is_tried_before_rejecting_ambient_node
test_new_nvm_dry_run_plans_bash_setup
test_node_setup_failure_does_not_install_npm_for_consumers
test_existing_nvm_version_becomes_persistent_default
test_planned_npm_is_reused_by_dry_run_installers
test_existing_npm_tools_skip_prerequisite_installers
test_bun_installs_with_npm
test_zsh_dependencies_are_installed
test_mq_release_selection
test_mq_dry_run_plans_pinned_binary
test_mq_intel_macos_uses_pinned_cargo_install
test_mq_intel_macos_without_cargo_skips_cleanly
test_mq_failed_binary_is_removed_and_retryable
test_existing_tree_sitter_is_not_upgraded
test_existing_tree_sitter_target_is_not_replaced
test_planned_cargo_is_reused_by_tree_sitter_dry_run
test_tree_sitter_allows_npm_install_script_and_falls_back_to_cargo
test_tree_sitter_cargo_retries_existing_stable_toolchain
test_failed_tree_sitter_cargo_build_is_retryable
test_existing_cargo_is_not_replaced_by_rustup
test_rustup_stable_handles_broken_cargo_proxy
test_libclang_is_installed_when_missing
test_known_legacy_links_are_migrated
test_platform_specific_configs_skip_cleanly
test_systemd_bridge_uses_stable_executable
test_nvim_version_check_is_portable

printf 'PASS: install copy regression tests\n'
