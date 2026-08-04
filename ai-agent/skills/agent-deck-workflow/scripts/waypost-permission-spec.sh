#!/usr/bin/env bash
#
# Shared Waypost permission rule primitives.
#
# Source this file; do not execute it directly. Callers own rendering and user
# messages. This module owns only the argv trust/capability contract shared by
# global and project-scoped permission generators.

waypost_rule_path_is_within() {
    local path="$1"
    local root="$2"

    [[ "$path" == "$root" || "$path" == "$root/"* ]]
}

waypost_rule_normalize_existing_path() {
    local path="$1"
    local parent

    [[ "$path" == /* ]] || return 1
    [[ -e "$path" || -L "$path" ]] || return 1
    parent="$(cd -P "$(dirname "$path")" && pwd -P)" || return 1
    printf '%s/%s\n' "$parent" "$(basename "$path")"
}

waypost_rule_canonicalize_existing_path() {
    local path
    local target
    local depth=0

    path="$(waypost_rule_normalize_existing_path "$1")" || return 1

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

    waypost_rule_normalize_existing_path "$path"
}

waypost_rule_state_dir() {
    local state_dir

    state_dir="${WAYPOST_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ai-agent/waypost}"
    # A permission prefix has no stable meaning for a relative state path:
    # the later shell's working directory selects the actual queue. Reject it
    # before any Waypost client-specific rules or ownership manifests render.
    [[ "$state_dir" == /* ]] || return 1
    printf '%s\n' "$state_dir"
}

waypost_rule_home_tilde_path() {
    local path="$1"
    local home_path="$HOME"

    while [[ "$home_path" != "/" && "$home_path" == */ ]]; do
        home_path="${home_path%/}"
    done

    if [[ "$home_path" == "/" ]]; then
        case "$path" in
            /)
                printf '%s\n' "~"
                return 0
                ;;
            /*)
                printf '~%s\n' "$path"
                return 0
                ;;
        esac
    elif [[ "$path" == "$home_path" ]]; then
        printf '%s\n' "~"
        return 0
    elif [[ "$path" == "$home_path/"* ]]; then
        printf '~/%s\n' "${path#"$home_path/"}"
        return 0
    fi

    return 1
}

waypost_rule_path_forms() {
    local path="$1"
    local tilde_path=""

    printf '%s\0' "$path"
    tilde_path="$(waypost_rule_home_tilde_path "$path" || true)"
    if [[ -n "$tilde_path" && "$tilde_path" != "$path" ]]; then
        printf '%s\0' "$tilde_path"
    fi
}

waypost_rule_command_forms() {
    # A bare `waypost` approval would be resolved again by the runtime shell
    # and could authorize a different PATH entry. Keep only validated paths.
    waypost_rule_path_forms "$1"
}

# Result fields are deliberately global so callers can validate once and then
# render the exact executable they validated without parsing stdout. The
# rendered command is canonical: persistent approvals must not keep following
# a mutable launcher symlink after validation.
WAYPOST_RULE_COMMAND=""
WAYPOST_RULE_CANONICAL_COMMAND=""
WAYPOST_RULE_RESOLVE_ERROR=""

# Resolve a usable absolute executable. Optional arguments are physical roots
# that must not contain either the rendered command path or its final symlink
# target (for example a project root).
waypost_rule_resolve_cli() {
    local resolved_command=""
    local rule_command=""
    local canonical_command=""
    local rejected_root
    local canonical_rejected_root

    WAYPOST_RULE_COMMAND=""
    WAYPOST_RULE_CANONICAL_COMMAND=""
    WAYPOST_RULE_RESOLVE_ERROR=""

    resolved_command="$(command -v waypost 2>/dev/null || true)"
    if [[ -z "$resolved_command" ]]; then
        WAYPOST_RULE_RESOLVE_ERROR="waypost is not in PATH"
        return 1
    fi
    if [[ "$resolved_command" != /* ]]; then
        WAYPOST_RULE_RESOLVE_ERROR="waypost resolved to a relative or shell-defined command: $resolved_command"
        return 1
    fi
    if ! rule_command="$(waypost_rule_normalize_existing_path "$resolved_command")" \
        || ! canonical_command="$(waypost_rule_canonicalize_existing_path "$rule_command")"; then
        WAYPOST_RULE_RESOLVE_ERROR="waypost does not resolve to an existing executable"
        return 1
    fi
    if [[ ! -f "$canonical_command" || ! -x "$canonical_command" ]]; then
        WAYPOST_RULE_RESOLVE_ERROR="waypost target is not an executable file: $canonical_command"
        return 1
    fi
    # The ownership manifest accepts only recognizable Waypost executable
    # names. Reject other canonical targets here so a successful first run
    # cannot write a manifest the next run will refuse.
    case "${canonical_command##*/}" in
        waypost|waypost.*|waypost-*|waypost_*) ;;
        *)
            WAYPOST_RULE_RESOLVE_ERROR="waypost target has an unsupported executable name: $canonical_command"
            return 1
            ;;
    esac

    for rejected_root in "$@"; do
        [[ -n "$rejected_root" ]] || continue
        canonical_rejected_root="$(waypost_rule_canonicalize_existing_path "$rejected_root" 2>/dev/null || true)"
        [[ -n "$canonical_rejected_root" ]] || continue
        if waypost_rule_path_is_within "$rule_command" "$canonical_rejected_root" \
            || waypost_rule_path_is_within "$canonical_command" "$canonical_rejected_root"; then
            WAYPOST_RULE_RESOLVE_ERROR="waypost command or target is inside an untrusted project root"
            return 1
        fi
    done

    WAYPOST_RULE_COMMAND="$canonical_command"
    WAYPOST_RULE_CANONICAL_COMMAND="$canonical_command"
    return 0
}

waypost_rule_validate_capabilities() {
    local command_path="$1"
    local state_dir

    [[ -n "$command_path" ]] || return 1
    state_dir="$(waypost_rule_state_dir)" || return 1

    "$command_path" mcp --help >/dev/null 2>&1 \
        && "$command_path" --state-dir "$state_dir" read --help >/dev/null 2>&1 \
        && "$command_path" --state-dir "$state_dir" list --help >/dev/null 2>&1
}

waypost_rule_state_dirs() {
    local state_dir

    state_dir="$(waypost_rule_state_dir)" || return 1
    waypost_rule_path_forms "$state_dir"
}

# Replace a staged file without treating a directory destination as a target
# directory. Callers must stage beside the destination so rename is atomic.
waypost_rule_replace_file() {
    local source_path="$1"
    local destination_path="$2"

    [[ -f "$source_path" && ! -L "$source_path" ]] || return 1

    if command -v perl >/dev/null 2>&1; then
        command perl -e '
            rename $ARGV[0], $ARGV[1]
                or die "rename($ARGV[0], $ARGV[1]): $!\\n";
        ' -- "$source_path" "$destination_path"
        return
    fi

    # GNU mv -T has the same non-directory target semantics. Fail closed on
    # platforms that provide neither primitive.
    command mv -T -- "$source_path" "$destination_path"
}

waypost_rule_json_string_literal() {
    local value="$1"
    local escaped=""
    local char
    local char_code
    local control_escape
    local index

    if command -v jq &>/dev/null; then
        jq -cn --arg value "$value" '$value'
        return
    fi

    # JSON string escapes are valid in the TOML basic strings emitted below.
    for ((index = 0; index < ${#value}; index++)); do
        char="${value:index:1}"
        case "$char" in
            '"') escaped+='\"' ;;
            $'\b') escaped+='\b' ;;
            $'\f') escaped+='\f' ;;
            $'\n') escaped+='\n' ;;
            $'\r') escaped+='\r' ;;
            $'\t') escaped+='\t' ;;
            *)
                if [[ "$char" == "\\" ]]; then
                    escaped="${escaped}\\\\"
                    continue
                fi
                printf -v char_code '%d' "'$char"
                if ((char_code < 0x20)); then
                    printf -v control_escape '\\u%04x' "$char_code"
                    escaped+="$control_escape"
                else
                    escaped+="$char"
                fi
                ;;
        esac
    done

    printf '"%s"\n' "$escaped"
}

waypost_rule_shell_quote_argument() {
    local value="$1"
    local suffix
    local quoted_value

    # Preserve leading tilde syntax so the approval matches commands written
    # with a HOME-relative path.
    if [[ "$value" == "~" ]]; then
        printf '~'
        return 0
    elif [[ "$value" == "~/"* ]]; then
        suffix="${value:2}"
        LC_ALL=C printf -v quoted_value '%q' "$suffix"
        printf '~/%s' "$quoted_value"
        return 0
    fi

    LC_ALL=C printf '%q' "$value"
}

waypost_rule_shell_quote_command() {
    local value
    local quoted_value
    local separator=""

    for value in "$@"; do
        quoted_value="$(waypost_rule_shell_quote_argument "$value")"
        printf '%s%s' "$separator" "$quoted_value"
        separator=" "
    done
}

# Render one narrowly scoped Claude Bash permission from structured argv.
# Keep the quote format locale-independent so the ownership manifest can be
# read after a locale change.
waypost_rule_claude_cli_permission() {
    local command_path="$1"
    local state_dir="$2"
    local action="$3"
    local wildcard="${4:-false}"
    local base_command
    local suffix=""

    case "$wildcard" in
        true|1) suffix=" *" ;;
        false|0) ;;
        *) return 1 ;;
    esac

    base_command="$(waypost_rule_shell_quote_command \
        "$command_path" "--state-dir" "$state_dir" "$action")" || return 1
    printf 'Bash(%s%s)\n' "$base_command" "$suffix"
}

# Emit one JSON manifest record. This works without jq so a first project
# initialization can still record ownership before jq is later installed.
waypost_rule_claude_cli_rule_json() {
    local command_path="$1"
    local state_dir="$2"
    local action="$3"
    local wildcard="${4:-false}"
    local command_literal
    local state_literal
    local action_literal
    local wildcard_literal

    case "$wildcard" in
        true|1) wildcard_literal=true ;;
        false|0) wildcard_literal=false ;;
        *) return 1 ;;
    esac

    command_literal="$(waypost_rule_json_string_literal "$command_path")" || return 1
    state_literal="$(waypost_rule_json_string_literal "$state_dir")" || return 1
    action_literal="$(waypost_rule_json_string_literal "$action")" || return 1
    printf '{"command":%s,"state_dir":%s,"action":%s,"wildcard":%s}\n' \
        "$command_literal" "$state_literal" "$action_literal" "$wildcard_literal"
}

waypost_rule_claude_cli_rule_records_are_valid() {
    local records_json="$1"

    command -v jq >/dev/null 2>&1 || return 1
    jq -e '
        def is_managed_path:
            type == "string"
            and (index("\u0000") | not)
            and (. == "~" or startswith("/") or startswith("~/"));
        def is_managed_command:
            is_managed_path
            and (. != "~")
            and test("(^|/)waypost(?:[._-][^/]*)?$");
        type == "array"
        and (length > 0 and length <= 16)
        and (length == (unique | length))
        and all(.[]?;
            type == "object"
            and (.command | is_managed_command)
            and (.state_dir | is_managed_path)
            and (.action == "read" or .action == "list")
            and ((.wildcard | type) == "boolean")
        )
    ' <<< "$records_json" >/dev/null
}

# Rebuild exact Claude permissions from structured ownership records. Do not
# parse or execute manifest-provided shell syntax.
waypost_rule_claude_cli_permissions_from_rule_records_json() {
    local records_json="$1"
    local permissions_json='[]'
    local command_path
    local state_dir
    local action
    local wildcard
    local permission

    command -v jq >/dev/null 2>&1 || return 1
    waypost_rule_claude_cli_rule_records_are_valid "$records_json" || return 1

    while IFS= read -r -d '' command_path; do
        IFS= read -r -d '' state_dir || return 1
        IFS= read -r -d '' action || return 1
        IFS= read -r -d '' wildcard || return 1
        permission="$(waypost_rule_claude_cli_permission \
            "$command_path" "$state_dir" "$action" "$wildcard")" || return 1
        permissions_json="$(jq -cn \
            --argjson permissions "$permissions_json" \
            --arg permission "$permission" \
            '$permissions + [$permission] | unique')" || return 1
    done < <(jq -j '
        .[]
        | .command, "\u0000", .state_dir, "\u0000", .action, "\u0000",
          (if .wildcard then "true" else "false" end), "\u0000"
    ' <<< "$records_json")

    printf '%s\n' "$permissions_json"
}

# Read an installer-owned Claude manifest and print the exact prior
# permissions it is safe to remove. Version 1 is accepted only for a narrow,
# one-time migration; version 2 stores structured argv and verifies its
# rendered permissions before trusting them.
waypost_rule_claude_cli_manifest_permissions_json() {
    local manifest_path="$1"
    local manifest_json
    local manifest_version
    local rules_json
    local stored_permissions
    local rendered_permissions

    command -v jq >/dev/null 2>&1 || return 1
    [[ -f "$manifest_path" && ! -L "$manifest_path" ]] || return 1

    manifest_json="$(jq -cer '
        def is_safe_plain_shell_word:
            test("^(?:[^[:space:]\\\\$\\x60\"\u0027;&|()<>*?\\[\\]{}!#]|\\\\[^\r\n])(?:[^[:space:]\\\\$\\x60\"\u0027;&|()<>*?\\[\\]{}!]|\\\\[^\r\n])*$");
        def is_safe_ansi_c_shell_word:
            if startswith("$\u0027") and endswith("\u0027") then
                (.[2:-1] | test("^(?:[^\u0027\\\\[:cntrl:]]|\\\\[^\r\n])*$"))
            elif startswith("~/$\u0027") and endswith("\u0027") then
                (.[4:-1] | test("^(?:[^\u0027\\\\[:cntrl:]]|\\\\[^\r\n])*$"))
            else false
            end;
        def is_safe_shell_word:
            is_safe_plain_shell_word or is_safe_ansi_c_shell_word;
        def is_managed_command:
            if is_safe_plain_shell_word then
                (startswith("/") or startswith("~/")) and endswith("/waypost")
            elif is_safe_ansi_c_shell_word then
                (startswith("$\u0027/") or startswith("~/$\u0027"))
                and endswith("/waypost\u0027")
            else false
            end;
        def is_managed_state_dir:
            if is_safe_plain_shell_word then
                . == "~" or startswith("/") or startswith("~/")
            elif is_safe_ansi_c_shell_word then
                startswith("$\u0027/") or startswith("~/$\u0027")
            else false
            end;
        def is_v1_permission:
            if type != "string" then false
            else
                ((try (
                    capture("^Bash\\((?<command>.+) --state-dir (?<state_dir>.+) (?<action>read|list)(?<wildcard> \\*)?\\)$")
                    | .command as $command
                    | .state_dir as $state_dir
                    | (($command | is_managed_command)
                       and ($state_dir | is_managed_state_dir))
                ) catch false) // false)
            end;
        def is_v2_record:
            type == "object"
            and ((.command | type) == "string")
            and ((.state_dir | type) == "string")
            and (.command | index("\u0000") | not)
            and (.state_dir | index("\u0000") | not)
            and (((.command | startswith("/")) or (.command | startswith("~/"))))
            and (.command | test("(^|/)waypost(?:[._-][^/]*)?$"))
            and ((.state_dir == "~")
                 or (.state_dir | startswith("/"))
                 or (.state_dir | startswith("~/")))
            and (.action == "read" or .action == "list")
            and ((.wildcard | type) == "boolean");
        if type == "object"
           and .version == 1
           and ((.permissions? | type) == "array")
           and all(.permissions[]?; is_v1_permission)
        then {version: 1, permissions: .permissions}
        elif type == "object"
           and .version == 2
           and ((.permissions? | type) == "array")
           and all(.permissions[]?; type == "string")
           and ((.rules? | type) == "array")
           and (.rules | length > 0 and length <= 16)
           and ((.rules | length) == (.rules | unique | length))
           and all(.rules[]?; is_v2_record)
        then {version: 2, permissions: .permissions, rules: .rules}
        else error("invalid manifest")
        end
    ' "$manifest_path" 2>/dev/null)" || return 1

    manifest_version="$(jq -r '.version' <<< "$manifest_json")" || return 1
    if [[ "$manifest_version" == 1 ]]; then
        jq -cer '.permissions' <<< "$manifest_json"
        return
    fi

    rules_json="$(jq -cer '.rules' <<< "$manifest_json")" || return 1
    stored_permissions="$(jq -cer '.permissions' <<< "$manifest_json")" || return 1
    rendered_permissions="$(waypost_rule_claude_cli_permissions_from_rule_records_json "$rules_json")" || return 1
    jq -e \
        --argjson stored "$stored_permissions" \
        --argjson rendered "$rendered_permissions" '
        ($stored | length) == ($stored | unique | length)
        and (($stored | sort) == ($rendered | sort))
    ' >/dev/null || return 1

    printf '%s\n' "$rendered_permissions"
}
