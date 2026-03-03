#!/bin/bash

input=$(cat)

# Extract data from JSON
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
session_name=$(echo "$input" | jq -r '.session_name // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Get git info if in a git repo
git_info=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        # Check for uncommitted changes
        if ! git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null || \
           ! git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
            git_info=" on $(printf '\033[31m')$branch$(printf '\033[0m')"
        else
            git_info=" on $(printf '\033[32m')$branch$(printf '\033[0m')"
        fi
    fi
fi

# Check proxy
proxy_indicator=""
if [[ -n $https_proxy || -n $all_proxy ]]; then
    proxy_indicator=" 🌐"
fi

# Build status line
status="$(printf '\033[36m')$(basename "$cwd")$(printf '\033[0m')$git_info$proxy_indicator"

# Add session name if present
if [ -n "$session_name" ]; then
    status="$status $(printf '\033[35m')[$session_name]$(printf '\033[0m')"
fi

# Add context remaining if available
if [ -n "$remaining" ]; then
    status="$status $(printf '\033[33m')${remaining}%%$(printf '\033[0m')"
fi

echo "$status"
