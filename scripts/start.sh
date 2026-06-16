#!/usr/bin/env bash
# Wrapper that loads Telegram credentials from macOS Keychain before starting
# the MCP server. Use this as the command in your MCP client config instead of
# calling `uv run` directly.
#
# Usage (Claude Code ~/.claude.json):
#   "command": "/path/to/telegram-mcp/scripts/start.sh"
#
# NOTE: only used by the *stdio* transport, where the MCP client spawns this
# script per connection. The default deployment uses an SSE daemon (launchd ->
# launcher.sh) and this script is never spawned in that mode.
#
# SECURITY — least-privilege Keychain access (whitelist-friendly):
#   Every Keychain call below is a SCOPED single-item read
#   (`security find-generic-password -s <service>`); it touches only this
#   project's own `telegram-*` items and NEVER `security dump-keychain`, which
#   would read the attributes of every item across all apps. EDR tools (e.g.
#   Bitdefender) that flag "security ... dump the Apple keychain" are reacting
#   to dump-keychain — not present here. The single write (token bootstrap, far
#   below) only adds this project's own `telegram-mcp-token`.
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
# `telegram-session-string-<label>`, and the set of labels is tracked in a
# dedicated `telegram-session-labels` index item (comma-separated, written by
# session_string_generator.py). We read that single item and look each label up
# with the scoped `find-generic-password` above, exporting it as
# TELEGRAM_SESSION_STRING_<LABEL> for the server's account discovery.
#
# This deliberately avoids `security dump-keychain`, which would read the
# attributes of *every* keychain item (all apps/services) just to find ours and
# can trigger keychain access prompts.
_labels="$(_keychain_get telegram-session-labels)"
if [[ -n "$_labels" ]]; then
  IFS=',' read -ra _label_list <<< "$_labels"
  for _label in "${_label_list[@]}"; do
    [[ -z "$_label" ]] && continue
    _var="TELEGRAM_SESSION_STRING_$(printf '%s' "$_label" | tr '[:lower:]' '[:upper:]')"
    if [[ -z "${!_var:-}" ]]; then
      _value="$(_keychain_get "telegram-session-string-$_label")"
      [[ -n "$_value" ]] && export "$_var=$_value"
    fi
  done
fi

if [[ -z "$TELEGRAM_MCP_TOKEN" ]]; then
  TELEGRAM_MCP_TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  security add-generic-password -a "$USER" -s telegram-mcp-token -w "$TELEGRAM_MCP_TOKEN"
  echo "[telegram-mcp] Generated and stored new SSE token in Keychain" >&2
fi

export TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_SESSION_STRING TELEGRAM_MCP_TOKEN

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec uv --directory "$SCRIPT_DIR/.." run telegram-mcp "$@"
