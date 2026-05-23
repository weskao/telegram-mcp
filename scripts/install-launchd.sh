#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.telegram-mcp.server.plist"
LOG_DIR="$HOME/Library/Logs/telegram-mcp"
LAUNCHER="$HOME/Library/Application Support/telegram-mcp/launcher.sh"

mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$LAUNCHER")"

PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
UV_BIN="$(command -v uv)"

# Self-contained launcher — no files from ~/Documents/ are executed.
# Credentials are loaded inline from Keychain; uv is called directly.
cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/bin/bash
_kc() { security find-generic-password -a "\$USER" -s "\$1" -w 2>/dev/null || true; }
: "\${TELEGRAM_API_ID:=\$(_kc telegram-api-id)}"
: "\${TELEGRAM_API_HASH:=\$(_kc telegram-api-hash)}"
: "\${TELEGRAM_SESSION_STRING:=\$(_kc telegram-session-string)}"
: "\${TELEGRAM_MCP_TOKEN:=\$(_kc telegram-mcp-token)}"
if [[ -z "\$TELEGRAM_MCP_TOKEN" ]]; then
  TELEGRAM_MCP_TOKEN=\$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  security add-generic-password -a "\$USER" -s telegram-mcp-token -w "\$TELEGRAM_MCP_TOKEN"
fi
export TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_SESSION_STRING TELEGRAM_MCP_TOKEN
exec "${UV_BIN}" --directory "${PROJECT_DIR}" run telegram-mcp --transport sse --port 8306
LAUNCHER_EOF
chmod +x "$LAUNCHER"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.telegram-mcp.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${LAUNCHER}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/server.out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/server.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "[telegram-mcp] LaunchAgent installed. Retrieve your SSE token for IDE config:"
echo "  security find-generic-password -a \"\$USER\" -s telegram-mcp-token -w"
echo "[telegram-mcp] To check status: launchctl list | grep telegram-mcp"
echo "[telegram-mcp] To stop:   launchctl unload ~/Library/LaunchAgents/com.telegram-mcp.server.plist"
echo "[telegram-mcp] To start:  launchctl load   ~/Library/LaunchAgents/com.telegram-mcp.server.plist"
