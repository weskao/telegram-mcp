#!/usr/bin/env bash
# One-shot health check for the telegram-mcp server across all four layers:
#   1. launchd  — is the background service loaded *and running*?
#   2. server   — is the HTTP port listening? (401 is healthy: auth is enforced)
#   3. claude   — is Claude's MCP registration actually connecting?
#   4. codex    — is Codex's MCP registration enabled *and* does the bearer token it
#                 points at actually complete an MCP handshake? The Codex CLI has no
#                 connection probe (a dead URL still lists as "enabled"), so we run one
#                 ourselves: resolve the token from the env var Codex reads, then POST
#                 `initialize`. 200 = token accepted, 401 = Codex would be rejected.
#
# Read-only: never changes config. Exits 0 when every layer is healthy,
# 1 otherwise, so it can gate other commands (`make health && ...`).
#
# Usage:
#   bash scripts/health-check.sh        # or: make health
#
# Overridable via env; otherwise read from .env, else the built-in defaults:
#   MCP_HOST=127.0.0.1 MCP_PORT=8765 MCP_NAME=telegram-mcp

# NOTE: deliberately no `-e` — every layer must be reported even when an
# earlier one fails. Failures are collected in $fail instead.
set -uo pipefail

# MCP_HOST / MCP_PORT / MCP_URL from env, then .env, then defaults.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/mcp-endpoint.sh"

MCP_NAME="${MCP_NAME:-telegram-mcp}"
CLAUDE="${CLAUDE:-claude}"
CODEX="${CODEX:-codex}"
LAUNCHD_LABEL="com.telegram-mcp.server"
LOG_ERR="$HOME/Library/Logs/telegram-mcp/server.err.log"

fail=0

# Result markers. ok/bad carry the pass/fail verdict for a layer (bad also flags the
# run); skip is for a layer that legitimately does not apply, e.g. an uninstalled CLI.
ok()   { echo "  ✅ $*"; }
bad()  { echo "  ❌ $*"; fail=1; }
skip() { echo "  ⏭️  $*"; }

# 1. launchd — exact label match on column 3; column 1 is the PID ("-" when the
#    job is registered but not running, e.g. crash-looping). Same parse as setup.sh.
echo "launchd:"
launchd_line="$(launchctl list 2>/dev/null | awk -v label="$LAUNCHD_LABEL" '$3 == label')"
if [[ -z "$launchd_line" ]]; then
  bad "NOT loaded — run scripts/install-launchd.sh"
else
  launchd_pid="$(awk '{print $1}' <<<"$launchd_line")"
  if [[ "$launchd_pid" =~ ^[0-9]+$ ]]; then
    ok "running (PID $launchd_pid, $LAUNCHD_LABEL)"
  else
    bad "loaded but NOT running — check $LOG_ERR"
  fi
fi

# 2. server — curl's -w already prints 000 on connection failure, so no `|| echo`.
echo "server :"
code="$(curl -sS -o /dev/null -w '%{http_code}' -m 5 -X POST \
  -H 'Content-Type: application/json' -d '{}' "$MCP_URL" 2>/dev/null)"
case "${code:-000}" in
  401) ok  "HTTP 401 — up (auth enforced, healthy)";;
  200) ok  "HTTP 200 — up";;
  000) bad "unreachable — server not listening on $MCP_HOST:$MCP_PORT";;
  *)   bad "HTTP $code — up but unexpected status";;
esac

# 3. claude — registration status. A missing CLI is not a failure (Codex-only setups).
echo "claude :"
if ! command -v "$CLAUDE" >/dev/null 2>&1; then
  skip "claude CLI not found"
elif ! mcp_get="$("$CLAUDE" mcp get "$MCP_NAME" 2>/dev/null)" || [[ -z "$mcp_get" ]]; then
  bad "$MCP_NAME not registered — run 'make use-http-claude'"
elif grep -q 'Connected' <<<"$mcp_get"; then
  ok "connected (Claude's own registration)"
else
  # `claude mcp get` reports the reason on an "Issue:" line; fall through to the raw
  # status text if the format ever changes.
  issue="$(sed -n 's/^[[:space:]]*Issue:[[:space:]]*//p' <<<"$mcp_get" | head -1)"
  bad "NOT connected — ${issue:-$(grep -E 'Status' <<<"$mcp_get" | head -1 | sed 's/^[[:space:]]*//')}"
fi

# 4. codex — config plus a real handshake. A missing CLI is not a failure (Claude-only
#    setups). `codex mcp get` reports config only, so after the config checks we probe
#    the connection the way Codex would: read the token out of the env var Codex is
#    configured to use and POST an `initialize` request. The token is never echoed.
echo "codex  :"
if ! command -v "$CODEX" >/dev/null 2>&1; then
  skip "codex CLI not found"
elif ! codex_get="$("$CODEX" mcp get "$MCP_NAME" 2>/dev/null)" || [[ -z "$codex_get" ]]; then
  bad "$MCP_NAME not registered — run 'make use-http-codex'"
elif ! grep -qE '^[[:space:]]*enabled:[[:space:]]*true' <<<"$codex_get"; then
  bad "registered but DISABLED — run 'make use-http-codex'"
else
  codex_transport="$(awk '/^[[:space:]]*transport:/{print $2; exit}' <<<"$codex_get")"
  codex_var="$(awk '/^[[:space:]]*bearer_token_env_var:/{print $2; exit}' <<<"$codex_get")"
  if [[ -z "$codex_var" || "$codex_var" == "-" ]]; then
    bad "enabled ($codex_transport) but no bearer_token_env_var — run 'make use-http-codex'"
  else
    # Both lookups are paths Codex itself uses: launcher.sh publishes the token via
    # `launchctl setenv` (what a GUI-launched Codex inherits), and a Codex started from
    # a shell inherits that shell's exported value instead.
    codex_token="${!codex_var:-}"
    [[ -z "$codex_token" ]] && codex_token="$(launchctl getenv "$codex_var" 2>/dev/null)"
    if [[ -z "$codex_token" ]]; then
      bad "enabled ($codex_transport) but \$$codex_var is unset — restart the service"
    else
      codex_code="$(curl -sS -o /dev/null -w '%{http_code}' -m 5 -X POST \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -H "Authorization: Bearer $codex_token" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"health-check","version":"0"}}}' \
        "$MCP_URL" 2>/dev/null)"
      case "${codex_code:-000}" in
        200) ok  "handshake OK ($codex_transport, token from \$$codex_var)";;
        401) bad "the token in \$$codex_var was REJECTED (HTTP 401)";;
        000) bad "server unreachable at $MCP_HOST:$MCP_PORT";;
        *)   bad "handshake returned HTTP $codex_code";;
      esac
    fi
  fi
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "✅ healthy"
else
  echo "❌ problems found — see above"
fi
exit "$fail"
