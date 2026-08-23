#!/usr/bin/env bash
# One-shot health check for the telegram-mcp server across all three layers:
#   1. launchd  — is the background service loaded?
#   2. server   — is the HTTP port listening? (401 is healthy: auth is enforced)
#   3. claude   — is Claude's MCP registration actually connecting?
#
# Usage:
#   bash scripts/health-check.sh        # or: make health
#
# Overridable via env (defaults match the Makefile):
#   MCP_HOST=127.0.0.1 MCP_PORT=8765 MCP_NAME=telegram-mcp

set -uo pipefail

MCP_HOST="${MCP_HOST:-127.0.0.1}"
MCP_PORT="${MCP_PORT:-8765}"
MCP_NAME="${MCP_NAME:-telegram-mcp}"
MCP_URL="http://${MCP_HOST}:${MCP_PORT}/mcp"
LAUNCHD_LABEL="com.telegram-mcp.server"

echo "launchd:"
if launchctl list 2>/dev/null | grep -q "$LAUNCHD_LABEL"; then
  echo "  loaded ($LAUNCHD_LABEL)"
else
  echo "  NOT loaded — run scripts/install-launchd.sh"
fi

echo "server :"
code="$(curl -sS -o /dev/null -w '%{http_code}' -m 5 "$MCP_URL" -X POST -d '{}' 2>/dev/null || echo "000")"
case "$code" in
  401) echo "  HTTP 401 — up (auth enforced, healthy)";;
  200) echo "  HTTP 200 — up";;
  000) echo "  unreachable — server not listening on $MCP_HOST:$MCP_PORT";;
  *)   echo "  HTTP $code — up but unexpected status";;
esac

CLAUDE="${CLAUDE:-claude}"
echo "claude :"
if command -v "$CLAUDE" >/dev/null 2>&1; then
  "$CLAUDE" mcp get "$MCP_NAME" 2>/dev/null | grep -E 'Status|Issue' | sed 's/^ */  /' \
    || echo "  ($MCP_NAME not registered — run 'make use-http-claude')"
else
  echo "  claude CLI not found"
fi
