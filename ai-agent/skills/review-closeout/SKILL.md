---
name: review-closeout
description: Extracts a concise review closeout from a full review report, keeping actionable items and any FAIL/UNKNOWN checks, and outputs directly for copy/paste.
---

# Review Closeout

Extract a closeout summary from a full review report.

## Purpose

Use this skill when a full review report already exists and only the remaining follow-up items are needed for handoff/closure.

## Input

Provide one of the following:
1. A full review report text, OR
2. A path to a review report file

## Output Mode (Fixed)

- Output directly in the response.
- Do NOT create files.
- Keep output copy/paste friendly Markdown.

## Extraction Rules

Keep content with **inclusion-first** policy (prefer keeping over dropping):

1. **Always keep non-empty items from**:
- `Critical Issues`
- `Design Concerns`
- `Minor Suggestions`
- `Verification Questions`

2. **Request/Security checks**:
- Remove `PASS` lines.
- Keep any line marked `FAIL` or `UNKNOWN`.

3. **None handling**:
- Remove `None.` placeholders.
- If a section has both `None.` and real items, keep real items only.

4. **Wording safety**:
- Preserve original technical meaning.
- Keep file paths / line references when present.
- Do not invent new issues.

## Output Template

Use this structure:

```markdown
### Review Closeout

#### Critical Issues
- [item]

#### Design Concerns
- [item]

#### Minor Suggestions
- [item]

#### Verification Questions
- [item]

#### Remaining Check Alerts (FAIL/UNKNOWN Only)
- [item]
```

## Empty Result Behavior

If all sections are empty after filtering, output exactly:

```markdown
### Review Closeout
No actionable items.
```

## Guidelines

1. Prefer completeness over aggressive trimming.
2. Keep neutral tone and avoid chat framing.
3. Do not include PASS-only status lines.
4. Keep ordering stable: Critical -> Design -> Minor -> Questions -> Alerts.
