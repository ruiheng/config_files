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

test_local_deletion_is_preserved() {
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
    [[ ! -e "$dst/deleted-locally" ]] || fail_test "locally deleted file was restored"
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

test_local_deletion_upstream_modification_conflicts() {
    local case_dir="$TEST_ROOT/local-delete-conflict"
    local base="$case_dir/base"
    local src="$case_dir/src"
    local dst="$case_dir/dst"
    local forced_dst="$case_dir/dst-force"
    local backup_path

    mkdir -p "$base" "$src" "$dst" "$forced_dst"
    printf 'old\n' > "$base/changed-upstream"
    printf 'new\n' > "$src/changed-upstream"

    if deploy_copy "$src" "$dst" "$base"; then
        fail_test "local deletion and upstream modification did not conflict"
    fi
    [[ ! -e "$dst/changed-upstream" ]] || fail_test "failed conflict changed local deletion"

    FORCE=1
    deploy_copy "$src" "$forced_dst" "$base" \
        || fail_test "--force local deletion conflict failed"
    FORCE=0
    assert_file_content "$forced_dst/changed-upstream" "new"

    backup_path="$(find "$case_dir" ! -path "$case_dir" -prune -name 'dst-force.backup.*' -print -quit)"
    [[ -n "$backup_path" && -d "$backup_path" ]] \
        || fail_test "--force did not back up the locally deleted target"
}

test_root_local_deletion_is_preserved() {
    local case_dir="$TEST_ROOT/root-local-deletion"
    local dst="$case_dir/bashrc"
    local snapshot

    mkdir -p "$case_dir"
    snapshot="$(managed_copy_snapshot_path "$dst")"
    mkdir -p "$(dirname "$snapshot")"
    cp "$REPO_ROOT/bashrc" "$snapshot"

    install_copy "bashrc" "$dst" || fail_test "root local deletion merge failed"
    [[ ! -e "$dst" && ! -L "$dst" ]] || fail_test "deleted managed root was restored"
}

test_root_local_deletion_upstream_modification_conflicts() {
    local case_dir="$TEST_ROOT/root-delete-conflict"
    local dst="$case_dir/bashrc"
    local snapshot

    mkdir -p "$case_dir"
    snapshot="$(managed_copy_snapshot_path "$dst")"
    mkdir -p "$(dirname "$snapshot")"
    printf 'old\n' > "$snapshot"

    if install_copy "bashrc" "$dst"; then
        fail_test "root deletion and upstream modification did not conflict"
    fi
    [[ ! -e "$dst" && ! -L "$dst" ]] || fail_test "failed root conflict restored the target"

    FORCE=1
    install_copy "bashrc" "$dst" || fail_test "--force root deletion conflict failed"
    FORCE=0
    cmp -s "$REPO_ROOT/bashrc" "$dst" || fail_test "--force did not install the upstream root"
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

test_shared_agent_snapshot_preserves_local_content
test_zshrc_uses_managed_copy_merge
test_managed_copy_dry_run_is_read_only
test_managed_copy_dry_run_plans_updates_without_staging
test_unrelated_repository_symlink_is_preserved
test_expected_repository_symlink_is_migrated
test_shared_link_migration_is_exact
test_unmodified_directory_to_file_transition
test_source_deletion_and_user_addition
test_deleted_directory_preserves_target_only_content
test_deleted_unmodified_directory_is_removed
test_deleted_directory_modified_managed_content_conflicts
test_local_deletion_is_preserved
test_upstream_deletion_local_modification_conflicts
test_local_deletion_upstream_modification_conflicts
test_root_local_deletion_is_preserved
test_root_local_deletion_upstream_modification_conflicts
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
test_mq_release_selection
test_mq_dry_run_plans_pinned_binary
test_mq_intel_macos_uses_pinned_cargo_install
test_mq_intel_macos_without_cargo_skips_cleanly
test_mq_failed_binary_is_removed_and_retryable
test_known_legacy_links_are_migrated
test_platform_specific_configs_skip_cleanly
test_systemd_bridge_uses_stable_executable
test_nvim_version_check_is_portable

printf 'PASS: install copy regression tests\n'
