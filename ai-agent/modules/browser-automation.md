# Browser Automation

## Tool: agent-browser

Use `agent-browser` for web automation tasks.

```bash
# See all commands
agent-browser --help
```

## Core Workflow

1. **Open URL**: `agent-browser open <url>`
2. **Snapshot**: `agent-browser snapshot -i` - Get interactive elements with refs (`@e1`, `@e2`, etc.)
3. **Interact**: Use refs to click or fill
   - `agent-browser click @e1`
   - `agent-browser fill @e2 "text"`
4. **Re-snapshot**: After page changes, take new snapshot to get updated refs
