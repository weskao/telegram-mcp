#!/usr/bin/env bash
# Single source of truth for the MCP HTTP endpoint used by the shell scripts.
#
# Precedence (matches the Makefile's own resolution):
#   1. an already-set environment variable  — an explicit override wins
#   2. .env                                — the same file the server itself
#                                            reads via load_dotenv(), so the
#                                            scripts probe the port the server
#                                            actually binds
#   3. built-in defaults 127.0.0.1 / 8765  — used when nothing is set
#
# Sourced, never executed: it only sets MCP_HOST, MCP_PORT and MCP_URL.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/mcp-endpoint.sh"

_mcp_env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"

# Only uncommented `KEY=value` lines match, so the commented-out samples in
# .env.example stay inert. The value stops at whitespace or an inline `#`; the
# last assignment wins, the way python-dotenv resolves duplicates.
_mcp_env_get() {
  [[ -f "$_mcp_env_file" ]] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" \
    "$_mcp_env_file" | tail -1 | tr -d "\"'"
}

MCP_HOST="${MCP_HOST:-$(_mcp_env_get MCP_HOST)}"
MCP_PORT="${MCP_PORT:-$(_mcp_env_get MCP_PORT)}"
MCP_HOST="${MCP_HOST:-127.0.0.1}"
MCP_PORT="${MCP_PORT:-8765}"
MCP_URL="http://${MCP_HOST}:${MCP_PORT}/mcp"
