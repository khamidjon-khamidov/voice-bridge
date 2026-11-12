#!/usr/bin/env bash
# Install voice-bridge: dependencies, the always-on hub (launchd), Claude Code
# hooks + MCP registration, and the CLAUDE.md rules. Safe to run again.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.voicebridge.hub"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS="$HOME/Library/Logs/voice-bridge"
PORT="${VB_PORT:-8765}"

cd "$ROOT"
echo "==> Installing Python dependencies"
uv sync --quiet

echo "==> Downloading the natural voice model (Kokoro, ~340 MB, once)"
MODELS="$HOME/Library/Application Support/voice-bridge/models"
mkdir -p "$MODELS"
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  if [ ! -s "$MODELS/$f" ]; then
    curl -fL --progress-bar -o "$MODELS/$f.part" \
      "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/$f" \
      && mv "$MODELS/$f.part" "$MODELS/$f" \
      || echo "!! Couldn't download $f; the phone will use its own voice until you rerun install.sh"
  fi
done

echo "==> Starting the hub with launchd (port $PORT, localhost only)"
mkdir -p "$LOGS" "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$ROOT/.venv/bin/vb-hub</string></array>
  <key>EnvironmentVariables</key><dict><key>VB_PORT</key><string>$PORT</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGS/hub.log</string>
  <key>StandardErrorPath</key><string>$LOGS/hub.log</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> Configuring Claude Code hooks, env and CLAUDE.md rules"
"$ROOT/.venv/bin/python" "$ROOT/scripts/configure_claude.py"

echo "==> Registering the MCP server for all projects"
claude mcp remove -s user voice-bridge >/dev/null 2>&1 || true
claude mcp add -s user voice-bridge -- "$ROOT/.venv/bin/vb-mcp"

for _ in 1 2 3 4 5; do
  curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break
  sleep 1
done
if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "==> Hub is up at http://127.0.0.1:$PORT"
else
  echo "!! Hub did not answer; see $LOGS/hub.log"
fi

cat <<EOF

Next, on this Mac (once):
  tailscale serve --bg $PORT
Then open the https://….ts.net address it prints on your phone.
Restart any running Claude Code sessions so they pick up the MCP server and hooks.
EOF
