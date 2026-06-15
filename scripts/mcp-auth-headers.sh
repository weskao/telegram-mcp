#!/usr/bin/env bash
# Reads the telegram-mcp bearer token from macOS Keychain and outputs an
# Authorization header as JSON.
# Called by Claude Code's headersHelper at connection time — token is never
# stored in config files.
set -euo pipefail

token="$(security find-generic-password -a "$USER" -s telegram-mcp-token -w 2>/dev/null || true)"
[ -z "$token" ] && { printf '{}\n'; exit 0; }

printf '{"Authorization":"Bearer %s"}\n' "$token"
