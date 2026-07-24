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
- `<target_workdir>` is the same workdir passed to `agent_deck_create_session`.
- Record the resolved profile as `*_tool_profile`, command as `*_tool_cmd`, and ordered `tool_cmds` for this creation.
- If creation rejects a profile-resolved command and `tool_cmds[1]` exists, replace `*_tool_cmd` with it and retry the same `agent_deck_create_session` once. Keep its other arguments unchanged; if the retry fails, surface the error.
- Pass `--workdir` for the target session. Pass `--target-path <PATH>` only when its PATH is known.
- Static checking does not run commands. Filter only trusted-context misses; retain dispatcher-/command-path misses in `tool_cmds` as `unverified_tool_cmds`, and preserve `unavailable_tool_cmds` as diagnostics.
- Local profile candidates replace by default. Set `merge = "prepend"` or `merge = "append"` with `candidates` to extend the prior list.
- The action skill owns the role, parent, workspace, reuse policy, and create/require choice.
