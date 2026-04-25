# Config Files

Personal configuration files collection with one-command installation for new machines.

## Quick Start

```cmd
:: Clone the repository
git clone <your-repo-url> %USERPROFILE%\config_files
cd %USERPROFILE%\config_files
```

Use the PowerShell installer:

```powershell
.\install.ps1 -DryRun
.\install.ps1
```

See [`WINDOWS.md`](./WINDOWS.md) for the Windows compatibility model and AI workflow prerequisites.

**Note for Windows**: Creating symbolic links requires either:
- Running as Administrator, OR
- Enabling Developer Mode in Windows Settings (Windows 10 version 1703+)

To enable Developer Mode: Settings → Update & Security → For developers → Developer Mode

## Installation Script

The supported installer is:

- **`install.ps1`** - For Windows PowerShell, including AI-agent configs and skills

It creates symbolic links from this repository to their proper system locations.

```powershell
.\install.ps1 [OPTIONS]

Options:
  -DryRun       Preview changes without applying
  -Force        Backup and replace existing files
  -Interactive  Prompt when target exists
  -BinDir       Directory for command shims such as adwf.cmd (default: ~/.local/bin)
```

### Examples

```powershell
# Preview changes
.\install.ps1 -DryRun

# Force replace existing configs (backs them up automatically)
.\install.ps1 -Force

# Interactive mode - prompt for each conflict
.\install.ps1 -Interactive

# Install command shims somewhere else
.\install.ps1 -BinDir "$env:USERPROFILE\bin"
```

## Configuration Structure

### Home Directory Dotfiles

| Source | Target | Description |
|--------|--------|-------------|
| `bashrc` | `~/.bashrc` | Bash configuration |
| `zshrc` | `~/.zshrc` | Zsh configuration |
| `screenrc` | `~/.screenrc` | GNU Screen configuration |
| `tmux/tmux.conf` | `~/.tmux.conf` | Tmux configuration |
| `gitconfig.unix` | `~/.gitconfig` | Git config (Unix/Linux/macOS) |
| `gitconfig.win` | `~/.gitconfig` | Git config (Windows) |

### XDG Config Directory (`~/.config/` or `%LOCALAPPDATA%`)

#### Windows

| Source | Target | Description |
|--------|--------|-------------|
| `nvim/` | `%LOCALAPPDATA%\nvim` | Neovim configuration |
| `gitconfig.win` | `%USERPROFILE%\.gitconfig` | Git configuration |
| `ai-agent/` | `%USERPROFILE%\.config\ai-agent` | AI Agent shared configuration |

### Claude Code Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude Code main config |
| `ai-agent/skills/<skill>/` | `~/.claude/skills/<skill>/` | **Each skill linked individually** |

**Note**: Claude Code requires each skill to be linked individually, not the entire skills directory. The script automatically creates separate symlinks for each subdirectory in `ai-agent/skills/`.

### Codex Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/skills/<skill>/` | `~/.codex/skills/<skill>/` | **Each skill linked individually** |

**Note**: Codex skills are linked individually for reliability. If `~/.codex/skills` is currently a symlink, run `.\install.ps1 -Interactive` or `.\install.ps1 -Force` once to migrate it to a real directory and then link each skill.

### Gemini CLI Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/GEMINI.md` | `~/.gemini/GEMINI.md` | Gemini CLI main config |
| `ai-agent/skills/<skill>/` | `~/.agents/skills/<skill>/` or `~/.gemini/skills/<skill>/` | **Linked individually (path depends on environment)** |

**Note**: If `~/.agents/skills` exists, installer uses it as the shared Gemini skills path and skips `~/.gemini/skills` to avoid duplicate skill conflict warnings. If `~/.agents/skills` does not exist, installer links skills under `~/.gemini/skills`.

### Other Special Configurations

| Source | Target | Description |
|--------|--------|-------------|
| `.serena/memories/` | `~/.serena/memories` | Serena memory store |
| `.serena/project.yml` | `~/.serena/project.yml` | Serena project config |

## Neovim Setup

Neovim configuration uses [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager.

### First-time Setup

1. Ensure Neovim 0.9+ is installed
2. Run `.\install.ps1` to link the configuration
3. On first Neovim start, lazy.nvim will automatically install all plugins

```bash
# Install Neovim (Debian/Ubuntu)
sudo apt install neovim

# Or install latest from GitHub
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
mkdir -p ~/.local/bin
ln -s /opt/nvim-linux-x86_64/bin/nvim ~/.local/bin/nvim
```

### Plugin Management

- Plugin configs are in `nvim/lua/ruiheng/plugins/`
- Use `:Lazy` to open the plugin manager
- Use `:Mason` to manage LSP servers

## Windows Notes

1. **Symbolic Links Require Elevation**: On Windows, creating symbolic links requires either:
   - Running Command Prompt/PowerShell as Administrator
   - Enabling Developer Mode in Windows Settings (Windows 10 version 1703+)

2. **AI Workflow Commands**:
   - `jq` is installed automatically with `winget` when missing.
   - Missing `agent-mailbox` or `agent-deck` is reported as a warning; install them before using full workflow automation.
   - If `agent-mailbox` exists, the installer configures the `agent_mailbox` MCP server for installed Claude/Codex/Gemini CLIs.

3. **Workflow Entry Point**: Skills call workflow helpers through `adwf <command>`. The installer places `adwf.cmd` in the selected command shim directory and adds that directory to the User PATH. Some `adwf` subcommands are still Bash-backed internally, so Git Bash, MSYS2, or WSL is needed until those internals are migrated.

4. **Neovim on Windows**: Neovim config is linked to `%LOCALAPPDATA%\nvim` (usually `C:\Users\<username>\AppData\Local\nvim`)

## Notes

### General

1. **No Overwrite by Default**: If a file already exists at the target (and is not a symlink), the script will skip it and report. Use `--force` to backup and replace, or `--interactive` to be prompted for each conflict.

### Local Overrides

Keep shared defaults in the repository and put machine-specific values in local override files instead of a separate branch.

- Git loads `~/.gitconfig.local` after [`gitconfig.unix`](./gitconfig.unix). A sample is provided at [`gitconfig.local.example`](./gitconfig.local.example).
- Coc can merge [`nvim/coc-settings.json`](./nvim/coc-settings.json) with an ignored local file at [`nvim/coc-settings.local.json`](./nvim/coc-settings.local.example.json). This is useful for per-machine proxies or other local-only settings.
- AI workflow tool defaults live in [`ai-agent/config/tool-profiles.toml`](./ai-agent/config/tool-profiles.toml). Override roles or candidate commands locally with `~/.config/ai-agent/config/tool-profiles.local.toml`; add `tool-profiles.local.toml` in the current working directory for project-specific overrides. Current-directory overrides win.

Example:

```toml
[roles]
reviewer = 'reviewer_local'

[profiles.reviewer_local]
strategy = 'ordered'
candidates = [
  'codex --model gpt-5.5 -c model_reasoning_effort=medium --ask-for-approval on-request',
  'claude --model sonnet --permission-mode acceptEdits',
]
```

2. **Interactive Mode**: Use `--interactive` (or `-i`) to be prompted when a target exists:
   - `[s]kip` - Skip this file (default)
   - `[b]ackup` - Backup and replace this file
   - `[f]orce` - Replace without backup
   - `[S]kip all` - Skip all remaining conflicts
   - `[B]ackup all` - Backup and replace all remaining conflicts
   - `[F]orce all` - Replace all without backup
   - `[c]ancel` - Cancel installation

3. **Backup**: When using `--force` or choosing backup in interactive mode, original files are backed up as `<filename>.backup.<timestamp>`

4. **Relative Paths**: Some symlinks use relative paths (e.g., `../config_files/nvim`). These work correctly when the repository is at `~/config_files`.

### Windows-Specific Notes

1. **Symbolic Links Require Elevation**: Creating symlinks on Windows requires either:
   - Running as Administrator, OR
   - Developer Mode enabled in Windows Settings

2. **Windows Installer Scope**: Use `install.ps1` for AI-agent configs and skills. Most other tools (i3, sway, tmux, etc.) are Unix-specific.

3. **Neovim Location**: On Windows, Neovim config goes to `%LOCALAPPDATA%\nvim` (e.g., `C:\Users\<username>\AppData\Local\nvim`)

## Manual Management

If you need to create links manually:

```bash
# Link a directory
ln -s ~/config_files/nvim ~/.config/nvim

# Link a single file
ln -s ~/config_files/bashrc ~/.bashrc
```
