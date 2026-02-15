---
name: commit-staged
description: Analyzes staged git changes, checks for issues, generates and executes commit with appropriate message.
---

# Commit Staged Changes

Analyze staged git changes, check for obvious mistakes, and execute `git commit` with a generated message.

## Process

1. `git status` - Check staged files
2. `git diff --staged` - Review the changes
3. Security check - Stop if issues found (see below)
4. Generate conventional commit message
5. Execute `git commit`

## Security Check

Stop and report if any of these are staged:

- **Sensitive files**: `.env*`, `*.pem`, `*.key`, `credentials.*`, `secrets.*`
- **Personal files**: IDE configs, `.DS_Store`, `Thumbs.db`
- **Debug code**: `console.log`, `debugger`, `print` statements
- **Merge conflicts**: Conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)

## Output

1. **If issues found**: List problems, stop and ask user to fix
2. **If clean**: Execute commit, show the message and result

## Notes

- For mixed concerns, suggest splitting commits
- Execute directly without confirmation
