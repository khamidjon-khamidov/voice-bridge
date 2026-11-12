#!/usr/bin/env bash
# Undo install.sh: stop the hub, remove hooks/env/rules and the MCP server.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.voicebridge.hub"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
"$ROOT/.venv/bin/python" "$ROOT/scripts/configure_claude.py" --remove
claude mcp remove -s user voice-bridge 2>/dev/null || true
echo "voice-bridge removed. (tailscale serve is left as is: run 'tailscale serve reset' to clear it.)"
