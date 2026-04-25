# Windows Setup Notes

This repo can keep most AI-agent functionality on Windows, split into two layers:

- Native Windows config links: Claude, Codex, Gemini, skills, modules, Git, and Neovim.
- Unix-like workflow runtime: Bash scripts under `ai-agent/skills/agent-deck-workflow/scripts/` still need Git Bash, MSYS2, or WSL.

## Recommended Setup

1. Enable Windows Developer Mode, or run PowerShell as Administrator.
2. Install core commands:

```powershell
winget install Git.Git OpenJS.NodeJS jqlang.jq Neovim.Neovim
```

3. Install the AI CLIs you use: `codex`, `claude`, `gemini`.
4. Install workflow tools: `agent-mailbox`, `agent-deck`. The installer warns if these are missing.
5. Run the Windows installer:

```powershell
.\install.ps1 -DryRun
.\install.ps1
```

If a target already exists, rerun with `-Interactive` or `-Force`. Use `-BinDir <path>` to place command shims somewhere other than the default `~/.local/bin`; in interactive mode the installer prompts for this path.

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

Most skills are plain Markdown and work natively once linked. The workflow automation scripts are Bash scripts and assume Unix-like tools:

- `bash`
- `jq`
- `git`
- `mktemp`, `rm`, `mv`, `cp`, `chmod`
- `agent-mailbox`
- `agent-deck`

Use Git Bash or MSYS2 when running those scripts from native Windows. WSL is the most complete option if `agent-deck` depends on Unix terminal/session primitives on your machine.

## Practical Compatibility Model

- Best native support: prompts, skills, module imports, MCP config snippets, `resolve-tool-command.js`, Neovim, Git config.
- Needs Git Bash/MSYS2: `agent-deck-workflow` shell helpers, sync scripts, Claude statusline script.
- Best in WSL: full `agent-deck` multi-session workflow if terminal/session behavior is unreliable under native Windows.

For maximum compatibility, keep this repo checked out at the same Windows path and expose it to WSL through `/mnt/c/...` only when needed. Avoid maintaining separate divergent clones.
