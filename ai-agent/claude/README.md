# Claude Code Configuration

This directory contains Claude Code specific configuration files.

## Files

### `settings.local.json`
Local settings template containing:
- Workflow automation approval allowlist
- Agent-deck integration permissions

### `statusline-command.sh`
Custom status line script that displays:
- Current directory name (cyan)
- Git branch with status:
  - Green: clean working tree
  - Red: uncommitted changes
- Proxy indicator (🌐) when proxy is active
- Session name (purple) if renamed
- Context remaining percentage (yellow)

The status line is inspired by the Spaceship ZSH theme and provides consistent visual feedback across your terminal and Claude Code sessions.

## Installation

Run the main installation script from the repository root:

```bash
./install.sh
```

This will:
1. Link `CLAUDE.md` and `modules/` for global instructions
2. Link skills individually to `~/.claude/skills/`
3. Link `settings.local.json` for permissions
4. Link `statusline-command.sh` for custom status line

## Manual Setup

If you need to set up manually:

```bash
# Link statusline script
ln -s ~/config_files/ai-agent/claude/statusline-command.sh ~/.claude/statusline-command.sh

# Ensure it's executable
chmod +x ~/.claude/statusline-command.sh
```

Then add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /home/ruiheng/.claude/statusline-command.sh"
  }
}
```

## Customization

To customize the status line, edit `statusline-command.sh`. The script receives JSON input via stdin with the following structure:

```json
{
  "workspace": {
    "current_dir": "/path/to/directory"
  },
  "session_name": "optional-session-name",
  "context_window": {
    "remaining_percentage": 85
  }
}
```

You can modify colors, add new indicators, or change the format to match your preferences.
