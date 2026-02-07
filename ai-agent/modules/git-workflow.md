# Git Workflow

## Commit Style

Before committing, always review your changes using `git status` and `git diff`. Only stage and commit changes that are directly related to the work at hand. If you have unrelated changes, split them into separate commits. Prioritize committing general-purpose infrastructure and utility code first.

Use conventional commit style with a concise description of what changed, unless it is a very simple change.

**Format**: `<type>(<scope>): <description>`

**Types**: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`

**Example**:
```bash
git commit -m "feat(buffer-nexus): add window picker integration"
git commit -m "fix: resolve layout offset calculation"
```

## Commit Approval

All commits must be approved by the user before creating.

## Branch Strategy

- `master` / `main`: Primary branch for PRs
- Feature branches: Create for non-trivial work
