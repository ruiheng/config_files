# Shared Tool-Resolution Contract

Use this reference only before creating a new Agent Deck session.

- Keep an explicit full command unchanged.
- Keep an existing session's recorded `*_tool_cmd`; do not resolve a replacement.
- Keep model/provider/version defaults in the shared profile, not an action skill.
- Resolve a new role command with:

  ```bash
  node ~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js --role <role> --profile <profile> --workdir <target_workdir> --show-list --format json
  ```

  Omit `--profile` when none is set.
- List configured roles with:

  ```bash
  node ~/.config/ai-agent/skills/agent-deck-workflow/scripts/resolve-tool-command.js --list-roles --format text
  ```

  JSON output is an object with a `roles` array.
- `<target_workdir>` is the same workdir passed to `agent_deck_create_session`.
- JSON includes ordered `tool_candidates`. Each has `command` and its configured fields; `startup_message` is absent when not configured.
- Record the chosen profile as `*_tool_profile`, command as `*_tool_cmd`, and optional candidate `startup_message` as `*_tool_startup_message`.
- For a new profile-resolved session, pass the optional `*_tool_startup_message` as `startup_instruction`. If the action owns another startup instruction, put the profile message first, then the action message, separated by one blank line. Do not add a startup instruction when neither exists.
- Use candidates in order. If creation rejects the first profile-resolved candidate and another exists, retry once with the next candidate and its optional startup message; otherwise surface the error.
- Pass `--workdir` for the target session. Pass `--target-path <PATH>` only when its PATH is known.
- Static checking does not run commands. Filter only trusted-context misses; retain dispatcher-/command-path misses in `tool_candidates` as `unverified_tool_cmds`, and preserve `unavailable_tool_cmds` as diagnostics.
- `strategy` defaults to `ordered`, the only supported strategy; omit it unless a future strategy requires an explicit choice.
- Local profile candidates replace by default. Set `merge = "prepend"` or `merge = "append"` with `candidates` to extend the prior list.
- The action skill owns the role, parent, workspace, reuse policy, and create/require choice.
