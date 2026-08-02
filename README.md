# Config Files

Personal configuration files collection with one-command installation for new machines.

## Quick Start

### Linux/macOS/WSL

```bash
# Clone the repository
git clone <your-repo-url> ~/config_files
cd ~/config_files

# Preview changes without applying
./install.sh --dry-run

# Execute installation (copies configs and creates shared links)
./install.sh
```

### Windows

```cmd
:: Clone the repository
git clone <your-repo-url> %USERPROFILE%\config_files
cd %USERPROFILE%\config_files

:: Preview changes without applying
install.bat --dry-run

:: Execute installation (creates symbolic links)
install.bat
```

**Note for Windows**: Creating symbolic links requires either:
- Running as Administrator, OR
- Enabling Developer Mode in Windows Settings (Windows 10 version 1703+)

To enable Developer Mode: Settings → Update & Security → For developers → Developer Mode

## Installation Scripts

Two scripts are provided for different platforms:

- **`install.sh`** - For Linux, macOS, and WSL (Bash)
- **`install.bat`** - For Windows (Command Prompt)

`install.sh` copies ordinary configuration files so installed configs do not depend on the repository location. Shared agent instructions, modules, and skills are copied to `~/.local/share/config_files/ai-agent` and linked from there when multiple agents need the same files. `install.bat` continues to use its Windows-specific link behavior.

### Linux/macOS/WSL (install.sh)

```bash
./install.sh [OPTIONS]

Options:
  --dry-run         Preview changes without applying
  --force           Backup and replace existing files
  --interactive, -i Prompt when target exists (asks: skip/backup/replace/all)
  --only PARTS      Install only selected comma-separated sections
  --skip PARTS      Skip selected comma-separated sections
  --ai-skills       Install/update AI skills only
  --no-color        Disable colored output
  --help, -h        Show help message
```

`--only` can be repeated and accepts `home`, `xdg`, `bin`, `ai`, `ai-skills`,
`serena`, or `all`. Partial selections skip unrelated tool/CLI bootstrap, OS
setup, and Neovim checks. Selections containing `home` or `xdg` initialize
their required Git submodules before copying. If initialization fails, only
the submodule-backed TPM and Neovim configs are skipped; independent selected
items continue.
`ai` updates
`$XDG_CONFIG_HOME/ai-agent` (or `$HOME/.config/ai-agent`) and all AI skills;
`ai-skills` only updates the shared snapshot at
`$XDG_DATA_HOME/config_files/ai-agent` (or
`$HOME/.local/share/config_files/ai-agent`) and per-agent skill links.

`--skip` can also be repeated and accepts `home`, `xdg`, `bin`, `ai`,
`ai-skills`, or `serena`. It keeps the full-install tool/CLI bootstrap while
omitting those sections. It cannot be combined with `--only`; skipping `ai`
also skips `ai-skills`.

`install.sh` checks required CLI tools before installing configs and installs missing ones through the detected package manager when supported. Required system tools include `fd`, `fzf`, `git`, `tmux`, `lsof`, `jq`, `sqlite3`, `yq`, and `zsh`. Debian/Ubuntu installs the `fd-find` package and creates a `~/.local/bin/fd` compatibility link. It installs Oh My Zsh with the configured Spaceship theme, `spaceship-vi-mode`, and `zsh-autocomplete`. It also installs `lazygit` from Homebrew or a checksum-verified official release, `uv` from Astral's official installer, Bun from its official npm package, and [`mq`](https://mqlang.org), a jq-like Markdown processor. Unsupported lazygit architectures are reported and skipped without blocking config deployment. If `agent-browser` is missing, it installs it with `npm install -g agent-browser` and runs `agent-browser install` once to download Chrome. Existing `agent-browser` installs are left alone. When the official Tree-sitter CLI binary is unusable, it ensures the current Rust stable toolchain and libclang before building from source.

For copied paths, including the stable shared agent assets under `~/.local/share/config_files/ai-agent`, the installer keeps the previous source snapshot under `~/.local/state/config_files/managed-copies`. Updates use that snapshot to remove files deleted from the repository, preserve target-only files and local-only modifications, restore missing managed files, and three-way merge concurrent text changes. Overlapping edits and incompatible type or mode changes are reported; `--force` backs up the target before applying the repository version.

### Windows (install.bat)

```cmd
install.bat [OPTIONS]

Options:
  --dry-run         Preview changes without applying
  --force           Backup and replace existing files
  --interactive, -i Prompt when target exists
  --help, -h, /?    Show help message
```

### Examples

```bash
# Standard installation (recommended)
./install.sh

# Preview changes
./install.sh --dry-run

# Force replace existing configs (backs them up automatically)
./install.sh --force

# Interactive mode - prompt for each conflict
./install.sh --interactive

# Update repository-managed AI skills only
./install.sh --ai-skills

# Install selected configuration sections
./install.sh --only home,xdg

# Full install except selected sections
./install.sh --skip xdg,serena

# No color output (for scripts or logging)
./install.sh --no-color
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

#### Linux/macOS/WSL

| Source | Target | Description |
|--------|--------|-------------|
| `nvim/` | `~/.config/nvim` | Neovim configuration |
| `i3/` | `~/.config/i3` | i3 window manager config |
| `niri/` | `~/.config/niri` | Niri window manager config |
| `sway/` | `~/.config/sway` | Sway window manager config |
| `waybar/` | `~/.config/waybar` | Waybar status bar config |
| `ranger/` | `~/.config/ranger` | Ranger file manager config |
| `systemd/` | `~/.config/systemd` | Systemd user services |
| `ai-agent/` | `~/.config/ai-agent` | AI Agent configuration |
| `grc/` | `~/.config/grc` | GRC colorizer configuration |
| `fourmolu.yaml` | `~/.config/fourmolu.yaml` | Haskell formatter config |

The i3, niri, sway, waybar, and systemd paths are Linux-only. `install.sh` reports them as skipped on macOS and WSL without failing the installation.

#### Windows

| Source | Target | Description |
|--------|--------|-------------|
| `nvim/` | `%LOCALAPPDATA%\nvim` | Neovim configuration |
| `gitconfig.win` | `%USERPROFILE%\.gitconfig` | Git configuration |

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

**Note**: Codex skills are linked individually from the stable shared snapshot. A legacy link to this repository's `ai-agent/skills` directory is migrated automatically; unrelated user-managed links still require `--interactive` or `--force`.

### Gemini CLI Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/GEMINI.md` | `~/.gemini/GEMINI.md` | Gemini CLI main config |
| `ai-agent/skills/<skill>/` | `~/.agents/skills/<skill>/` or `~/.gemini/skills/<skill>/` | **Linked individually (path depends on environment)** |

**Note**: If `~/.agents/skills` exists, installer uses it as the shared Gemini skills path and skips `~/.gemini/skills` to avoid duplicate skill conflict warnings. If `~/.agents/skills` does not exist, installer links skills under `~/.gemini/skills`.

### Antigravity CLI Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/skills/<skill>/` | `~/.gemini/antigravity-cli/skills/<skill>/` | **Each skill linked individually** |
| `waypost mcp` | `~/.gemini/config/mcp_config.json` | Antigravity CLI MCP server config |

**Note**: Antigravity MCP servers inherit the parent process environment. The installer does not write an `env` block for Antigravity.

### Kiro CLI Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/skills/<skill>/` | `~/.kiro/skills/<skill>/` | **Each skill linked individually** |
| `waypost mcp` | `~/.kiro/settings/mcp.json` | Kiro CLI MCP server config |

### Other Special Configurations

| Source | Target | Description |
|--------|--------|-------------|
| `.serena/memories/` | `~/.serena/memories` | Serena memory store |
| `.serena/project.yml` | `~/.serena/project.yml` | Serena project config |

## Neovim Setup

Neovim configuration uses [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager.

### First-time Setup

1. Ensure Neovim 0.9+ is installed
2. Run `./install.sh` to install the configuration
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

## OS Support

The scripts automatically detect the OS and apply appropriate configurations:

- **Linux**: Full support for all configurations (via `install.sh`)
- **macOS**: Cross-platform shell, editor, and agent configs; Linux desktop and systemd paths are skipped (via `install.sh`)
- **WSL**: Cross-platform shell, editor, and agent configs; Linux desktop and systemd paths are skipped (via `install.sh`)
- **Windows**: Limited support - mainly Neovim and Git configs (via `install.bat`)

## Windows Notes

1. **Symbolic Links Require Elevation**: On Windows, creating symbolic links requires either:
   - Running Command Prompt/PowerShell as Administrator
   - Enabling Developer Mode in Windows Settings (Windows 10 version 1703+)

2. **Limited Configurations**: The Windows batch script only installs:
   - Neovim configuration
   - Git configuration (Windows version)

   Most other configurations (i3, sway, niri, tmux, etc.) are Unix-specific and not applicable to Windows.

3. **Neovim on Windows**: Neovim config is linked to `%LOCALAPPDATA%\nvim` (usually `C:\Users\<username>\AppData\Local\nvim`)

## Notes

### General

1. **Unmanaged Targets Are Preserved**: Existing unmanaged paths are skipped by default. Previously installed managed copies, including `~/.zshrc`, are updated with the three-way merge rules described above.

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

4. **Stable Install Paths**: Ordinary configs are copied to their runtime locations. Necessary shared-agent symlinks point to `~/.local/share/config_files`, not to the repository checkout.

### Windows-Specific Notes

1. **Symbolic Links Require Elevation**: Creating symlinks on Windows requires either:
   - Running as Administrator, OR
   - Developer Mode enabled in Windows Settings

2. **Limited Config Support**: The Windows script only installs Neovim and Git configs. Most other tools (i3, sway, tmux, etc.) are Unix-specific.

3. **Neovim Location**: On Windows, Neovim config goes to `%LOCALAPPDATA%\nvim` (e.g., `C:\Users\<username>\AppData\Local\nvim`)

## Manual Management

If you need to install ordinary configs manually, copy them so runtime behavior does not depend on the repository location:

```bash
# Copy a directory
cp -pPR ~/config_files/nvim ~/.config/nvim

# Copy a single file
cp -p ~/config_files/bashrc ~/.bashrc
```
