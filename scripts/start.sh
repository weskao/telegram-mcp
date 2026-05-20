#!/usr/bin/env bash
# Wrapper that loads Telegram credentials from macOS Keychain before starting
# the MCP server. Use this as the command in your MCP client config instead of
# calling `uv run` directly.
#
# Usage (Claude Code ~/.claude.json):
#   "command": "/path/to/telegram-mcp/scripts/start.sh"
#
# First-time setup — store credentials in Keychain:
#   security add-generic-password -a "$USER" -s telegram-api-id        -w "YOUR_API_ID"
#   security add-generic-password -a "$USER" -s telegram-api-hash       -w "YOUR_API_HASH"
#   security add-generic-password -a "$USER" -s telegram-session-string -w "YOUR_SESSION_STRING"

set -euo pipefail

_keychain_get() {
  security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null || true
}

# Load from Keychain only when the env var isn't already set.
: "${TELEGRAM_API_ID:=$(_keychain_get telegram-api-id)}"
: "${TELEGRAM_API_HASH:=$(_keychain_get telegram-api-hash)}"
: "${TELEGRAM_SESSION_STRING:=$(_keychain_get telegram-session-string)}"

export TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_SESSION_STRING

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec uv --directory "$SCRIPT_DIR/.." run telegram-mcp "$@"
