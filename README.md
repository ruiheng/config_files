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

# Execute installation (creates symbolic links)
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

Both scripts automatically create symbolic links to link configuration files from this repository to their proper system locations.

### Linux/macOS/WSL (install.sh)

```bash
./install.sh [OPTIONS]

Options:
  --dry-run         Preview changes without applying
  --force           Backup and replace existing files
  --interactive, -i Prompt when target exists (asks: skip/backup/replace/all)
  --no-color        Disable colored output
  --help, -h        Show help message
```

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
| `gitconfig.ruiheng.unix` | `~/.gitconfig` | Git config (Unix/Linux/macOS) |
| `gitconfig.ruiheng.win` | `~/.gitconfig` | Git config (Windows) |

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

#### Windows

| Source | Target | Description |
|--------|--------|-------------|
| `nvim/` | `%LOCALAPPDATA%\nvim` | Neovim configuration |
| `gitconfig.ruiheng.win` | `%USERPROFILE%\.gitconfig` | Git configuration |

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

**Note**: Codex skills are linked individually for reliability. If `~/.codex/skills` is currently a symlink, run `./install.sh --interactive` or `./install.sh --force` once to migrate it to a real directory and then link each skill.

### Gemini CLI Configuration

| Source | Target | Description |
|--------|--------|-------------|
| `ai-agent/GEMINI.md` | `~/.gemini/GEMINI.md` | Gemini CLI main config |
| `ai-agent/skills/<skill>/` | `~/.gemini/skills/<skill>/` | **Each skill linked individually** |

**Note**: Gemini CLI skills are linked individually for reliability. If `~/.gemini/skills` is currently a symlink, run `./install.sh --interactive` or `./install.sh --force` once to migrate it to a real directory and then link each skill.

### Other Special Configurations

| Source | Target | Description |
|--------|--------|-------------|
| `.serena/memories/` | `~/.serena/memories` | Serena memory store |
| `.serena/project.yml` | `~/.serena/project.yml` | Serena project config |

## Neovim Setup

Neovim configuration uses [lazy.nvim](https://github.com/folke/lazy.nvim) as the plugin manager.

### First-time Setup

1. Ensure Neovim 0.9+ is installed
2. Run `./install.sh` to link the configuration
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
- **macOS**: Most configs supported, window manager configs (i3, sway, niri, waybar) not applicable (via `install.sh`)
- **WSL**: Same as Linux, window manager configs won't work in WSL (via `install.sh`)
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

1. **No Overwrite by Default**: If a file already exists at the target (and is not a symlink), the script will skip it and report. Use `--force` to backup and replace, or `--interactive` to be prompted for each conflict.

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

2. **Limited Config Support**: The Windows script only installs Neovim and Git configs. Most other tools (i3, sway, tmux, etc.) are Unix-specific.

3. **Neovim Location**: On Windows, Neovim config goes to `%LOCALAPPDATA%\nvim` (e.g., `C:\Users\<username>\AppData\Local\nvim`)

## Manual Management

If you need to create links manually:

```bash
# Link a directory
ln -s ~/config_files/nvim ~/.config/nvim

# Link a single file
ln -s ~/config_files/bashrc ~/.bashrc
```
