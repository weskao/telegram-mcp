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
: "${TELEGRAM_MCP_TOKEN:=$(_keychain_get telegram-mcp-token)}"

# Multi-account: labeled session strings are stored as
# `telegram-session-string-<label>`. Export each as TELEGRAM_SESSION_STRING_<LABEL>
# so the server's account discovery picks them up. The unsuffixed default above is
# excluded (it has no trailing label).
while IFS= read -r _svc; do
  _label="${_svc#telegram-session-string-}"
  [[ -z "$_label" || "$_label" == "$_svc" ]] && continue
  _var="TELEGRAM_SESSION_STRING_$(printf '%s' "$_label" | tr '[:lower:]' '[:upper:]')"
  if [[ -z "${!_var:-}" ]]; then
    _value="$(_keychain_get "$_svc")"
    [[ -n "$_value" ]] && export "$_var=$_value"
  fi
done < <(security dump-keychain 2>/dev/null \
           | sed -n 's/.*"svce"<blob>="\(telegram-session-string-[^"]*\)".*/\1/p' \
           | sort -u)

if [[ -z "$TELEGRAM_MCP_TOKEN" ]]; then
  TELEGRAM_MCP_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  security add-generic-password -a "$USER" -s telegram-mcp-token -w "$TELEGRAM_MCP_TOKEN"
  echo "[telegram-mcp] Generated and stored new SSE token in Keychain" >&2
fi

export TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_SESSION_STRING TELEGRAM_MCP_TOKEN

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec uv --directory "$SCRIPT_DIR/.." run telegram-mcp "$@"
