#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Aggregate UI manual confirmation packages from closeout artifacts.

Usage:
  summarize-ui-confirmation-packages.sh [options]

Options:
  --artifact-root <path>   Artifact root (default: .agent-artifacts)
  --output <path>          Output markdown path (default: <artifact-root>/ui-confirmation/summary.md)
  --limit <n>              Max recent closeout files to scan (default: 50)
  -h, --help               Show help

Notes:
  - Looks for section heading: "#### UI Manual Confirmation Package"
  - Deduplicates packages by normalized section content.
  - Keeps large detail in closeout files; summary is pointer-first.
EOF
}

artifact_root=".agent-artifacts"
output_path=""
limit="50"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-root) artifact_root="${2:-}"; shift 2 ;;
    --output) output_path="${2:-}"; shift 2 ;;
    --limit) limit="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ "$limit" =~ ^[0-9]+$ ]] || { echo "ERROR: --limit must be integer" >&2; exit 2; }

if [[ -z "$output_path" ]]; then
  output_path="${artifact_root%/}/ui-confirmation/summary.md"
fi

mkdir -p "$(dirname "$output_path")"

if [[ ! -d "$artifact_root" ]]; then
  cat >"$output_path" <<EOF
# UI Confirmation Summary

Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

No artifact root found: \`$artifact_root\`
EOF
  echo "ui_summary_ok entries=0 deduped=0 output=${output_path}"
  exit 0
fi

mapfile -t closeout_files < <(
  find "$artifact_root" -maxdepth 3 -type f -name 'closeout-*.md' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n "$limit" \
    | cut -d' ' -f2-
)

declare -A seen
entries=()
deduped=0

for file in "${closeout_files[@]}"; do
  [[ -f "$file" ]] || continue

  section="$(awk '
    /^#### UI Manual Confirmation Package[[:space:]]*$/ { in_block=1; next }
    /^#### / && in_block { exit }
    in_block { print }
  ' "$file")"

  section="$(sed '/^[[:space:]]*$/d' <<<"$section")"
  [[ -n "$section" ]] || continue

  if grep -Eqi '^[-*][[:space:]]*UI impact:[[:space:]]*(\[)?none detected(\])?$' <<<"$section"; then
    continue
  fi

  norm="$(tr '[:upper:]' '[:lower:]' <<<"$section" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//')"
  key="$(cksum <<<"$norm" | awk '{print $1":"$2}')"
  if [[ -n "${seen[$key]:-}" ]]; then
    deduped=$((deduped + 1))
    continue
  fi
  seen[$key]=1

  task_id="$(basename "$(dirname "$file")")"
  entry=$(
    cat <<EOF
## ${task_id}
- Closeout: \`${file}\`
${section}

EOF
  )
  entries+=("$entry")
done

{
  echo "# UI Confirmation Summary"
  echo
  echo "Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "No UI manual confirmation packages found."
  else
    for e in "${entries[@]}"; do
      printf '%s\n' "$e"
    done
  fi
} >"$output_path"

echo "ui_summary_ok entries=${#entries[@]} deduped=${deduped} output=${output_path}"

