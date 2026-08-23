#!/usr/bin/env bash
# One-shot health check for the telegram-mcp server across all three layers:
#   1. launchd  — is the background service loaded *and running*?
#   2. server   — is the HTTP port listening? (401 is healthy: auth is enforced)
#   3. claude   — is Claude's MCP registration actually connecting?
#
# Read-only: never changes config. Exits 0 when every layer is healthy,
# 1 otherwise, so it can gate other commands (`make health && ...`).
#
# Usage:
#   bash scripts/health-check.sh        # or: make health
#
# Overridable via env (defaults match the Makefile):
#   MCP_HOST=127.0.0.1 MCP_PORT=8765 MCP_NAME=telegram-mcp

# NOTE: deliberately no `-e` — every layer must be reported even when an
# earlier one fails. Failures are collected in $fail instead.
set -uo pipefail

MCP_HOST="${MCP_HOST:-127.0.0.1}"
MCP_PORT="${MCP_PORT:-8765}"
MCP_NAME="${MCP_NAME:-telegram-mcp}"
CLAUDE="${CLAUDE:-claude}"
MCP_URL="http://${MCP_HOST}:${MCP_PORT}/mcp"
LAUNCHD_LABEL="com.telegram-mcp.server"
LOG_ERR="$HOME/Library/Logs/telegram-mcp/server.err.log"

fail=0

# 1. launchd — exact label match on column 3; column 1 is the PID ("-" when the
#    job is registered but not running, e.g. crash-looping). Same parse as setup.sh.
echo "launchd:"
launchd_line="$(launchctl list 2>/dev/null | awk -v label="$LAUNCHD_LABEL" '$3 == label')"
if [[ -z "$launchd_line" ]]; then
  echo "  NOT loaded — run scripts/install-launchd.sh"
  fail=1
else
  launchd_pid="$(awk '{print $1}' <<<"$launchd_line")"
  if [[ "$launchd_pid" =~ ^[0-9]+$ ]]; then
    echo "  running (PID $launchd_pid, $LAUNCHD_LABEL)"
  else
    echo "  loaded but NOT running — check $LOG_ERR"
    fail=1
  fi
fi

# 2. server — curl's -w already prints 000 on connection failure, so no `|| echo`.
echo "server :"
code="$(curl -sS -o /dev/null -w '%{http_code}' -m 5 -X POST \
  -H 'Content-Type: application/json' -d '{}' "$MCP_URL" 2>/dev/null)"
case "${code:-000}" in
  401) echo "  HTTP 401 — up (auth enforced, healthy)";;
  200) echo "  HTTP 200 — up";;
  000) echo "  unreachable — server not listening on $MCP_HOST:$MCP_PORT"; fail=1;;
  *)   echo "  HTTP $code — up but unexpected status"; fail=1;;
esac

# 3. claude — registration status. A missing CLI is not a failure (Codex-only setups).
echo "claude :"
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  echo "  claude CLI not found — skipped"
elif ! mcp_get="$("$CLAUDE" mcp get "$MCP_NAME" 2>/dev/null)" || [[ -z "$mcp_get" ]]; then
  echo "  $MCP_NAME not registered — run 'make use-http-claude'"
  fail=1
else
  status="$(grep -E 'Status|Issue' <<<"$mcp_get" | sed 's/^ */  /')"
  echo "${status:-  registered (no status line reported)}"
  grep -q 'Connected' <<<"$mcp_get" || fail=1
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "healthy"
else
  echo "problems found — see above"
fi
exit "$fail"
