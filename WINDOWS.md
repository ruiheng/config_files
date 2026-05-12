# Windows Setup Notes

This repo can keep most AI-agent functionality on Windows, split into two layers:

- Native Windows config links: Claude, Codex, Gemini, skills, modules, Git, and Neovim.
- Workflow runtime: Node-backed `adwf` helpers run natively; remaining legacy Bash helpers still need Git Bash or MSYS2 for native Windows use.

## Recommended Setup

1. Install core commands:

```powershell
winget install Git.Git OpenJS.NodeJS jqlang.jq Neovim.Neovim
```

2. Install the AI CLIs you use: `codex`, `claude`, `gemini`.
3. Install workflow tools: `agent-mailbox`, `agent-deck`. The installer warns if these are missing.
4. Run the Windows installer:

```powershell
.\install.ps1 -DryRun
.\install.ps1
```

If a target already exists, rerun with `-Interactive` or `-Force`. Use `-BinDir <path>` to place command shims somewhere other than the default `~/.local/bin`; in interactive mode the installer prompts for this path.

The installer prefers symbolic links. If Windows blocks them, it falls back to directory junctions and file hardlinks, so Administrator privileges or Developer Mode are not required for normal installs.

For remaining Bash-backed `adwf` commands, install Git Bash or MSYS2. `adwf.ps1` intentionally avoids auto-selecting WSL `bash.exe` because WSL and Windows paths/tool installs are separate environments. Set `ADWF_BASH` to a specific `bash.exe` path only when you want to override detection.

## What `install.ps1` Links

- `ai-agent/` -> `~/.config/ai-agent`
- `ai-agent/CLAUDE.md` -> `~/.claude/CLAUDE.md`
- `ai-agent/GEMINI.md` -> `~/.gemini/GEMINI.md`
- `ai-agent/AGENTS.md` -> `~/.codex/AGENTS.md`
- `ai-agent/modules/` into each tool config directory
- every `ai-agent/skills/<skill>/` into Claude, Codex, and Gemini skill directories
- agent-deck workflow policy/rule files for Gemini and Codex
- the `adwf` workflow launcher into the selected command shim directory
- the selected command shim directory into the User PATH
- `agent_mailbox` MCP for installed Claude/Codex/Gemini CLIs when `agent-mailbox` exists

This keeps hard-coded module references such as `@~/.config/ai-agent/modules/...` valid on Windows.

Skills should call workflow helpers as `adwf <command>` only. The dispatcher hides whether a command is currently PowerShell, Node, or Bash-backed.

## Runtime Expectations

Most skills are plain Markdown and work natively once linked. Node-backed workflow helpers work natively through `adwf`. Remaining legacy workflow scripts are Bash scripts and assume Unix-like tools:

- `bash`
- `jq`
- `git`
- `mktemp`, `rm`, `mv`, `cp`, `chmod`
- `agent-mailbox`
- `agent-deck`

Use Git Bash or MSYS2 when running those scripts from native Windows. If you prefer WSL, install and run this repo's workflow inside WSL so paths, git worktrees, and CLI tools live in one environment.

## Practical Compatibility Model

- Best native support: prompts, skills, module imports, MCP config snippets, `resolve-tool-command.js`, Neovim, Git config.
- Needs Git Bash/MSYS2: remaining legacy `agent-deck-workflow` shell helpers, sync scripts, Claude statusline script.
- WSL: use a WSL-side install/checkout instead of mixing Windows `adwf.cmd` with WSL paths.

For maximum compatibility, keep native Windows and WSL installs separate unless you are only reading files across the boundary.
