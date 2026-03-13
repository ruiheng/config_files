Global rules:

- For routine workspace file inspection, use the built-in file-reading tool instead of shell text slicers such as `sed` or `awk`.
- If shell line slicing is truly necessary, use `head -n X | tail -n +Y` instead of `sed -n`.

Follow the guidance files below based on task type.

If the task involves software design or development:

@~/.config/ai-agent/modules/linus.md
@~/.config/ai-agent/modules/engineering-guardrails.md

Default policy is Root-Cause First: investigate and fix root causes before any fallback. Temporary fallback is allowed only if the user explicitly says: "allow temporary mitigation".

When inspecting or transforming JSON, prefer `jq` over ad-hoc scripts such as Python whenever `jq` can reasonably handle the task.

If the task involves git operations:
@~/.config/ai-agent/modules/git-workflow.md

If the task involves browser automation (for example, testing):
@~/.config/ai-agent/modules/browser-automation.md
