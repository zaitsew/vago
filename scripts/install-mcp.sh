#!/usr/bin/env bash
# Builds the read-only Vago MCP server and copies it to ~/.local/bin (or $VAGO_BIN_DIR).
# It reads ~/Library/Application Support/Vago/state.json, written by the Mac app.
set -euo pipefail
cd "$(dirname "$0")/.."

dest="${VAGO_BIN_DIR:-$HOME/.local/bin}"
if command -v teyla >/dev/null 2>&1; then teyla load --wait --kind build; fi
swift build -c release --product vago-mcp
mkdir -p "$dest"
cp "$(swift build -c release --product vago-mcp --show-bin-path)/vago-mcp" "$dest/vago-mcp"
echo "installed: $dest/vago-mcp"

state="$HOME/Library/Application Support/Vago/state.json"
[ -f "$state" ] || echo "note: no $state yet; open the Vago Mac app once"
"$dest/vago-mcp" today || true

cat <<MSG

Add it to your tools:
  claude mcp add vago -- $dest/vago-mcp
  codex mcp add vago -- $dest/vago-mcp
MSG
