#!/usr/bin/env bash
set -euo pipefail

# Sync official agent-deck skill snapshot into this repository.
# Usage:
#   ai-agent/scripts/sync-official-agent-deck-skill.sh [ref]
# Example:
#   ai-agent/scripts/sync-official-agent-deck-skill.sh main
#   ai-agent/scripts/sync-official-agent-deck-skill.sh v0.8.98

UPSTREAM_URL="https://github.com/asheshgoplani/agent-deck"
REF="${1:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$AI_AGENT_DIR/skills/agent-deck"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

printf '[INFO] Cloning %s (ref=%s)\n' "$UPSTREAM_URL" "$REF"
git clone --depth 1 --branch "$REF" "$UPSTREAM_URL" "$TMP_DIR/repo"

if [[ ! -d "$TMP_DIR/repo/skills/agent-deck" ]]; then
  printf '[ERR] Upstream skill path missing: skills/agent-deck\n' >&2
  exit 1
fi

UPSTREAM_COMMIT="$(git -C "$TMP_DIR/repo" rev-parse HEAD)"
SYNC_DATE_UTC="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -R "$TMP_DIR/repo/skills/agent-deck/." "$DEST_DIR/"

cat > "$DEST_DIR/UPSTREAM.md" <<META
# Upstream Source

- Repository: $UPSTREAM_URL
- Skill Path: skills/agent-deck
- Ref: $REF
- Commit: $UPSTREAM_COMMIT
- Synced At (UTC): $SYNC_DATE_UTC

This directory is a vendored snapshot of the official `agent-deck` skill.
Update it by rerunning:


ai-agent/scripts/sync-official-agent-deck-skill.sh <ref>

META

printf '[OK] Synced official skill to %s\n' "$DEST_DIR"
printf '[OK] Upstream commit: %s\n' "$UPSTREAM_COMMIT"
