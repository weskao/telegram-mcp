#!/usr/bin/env bash
# Claude / Codex / Grok / AGY MCP client operations.
#
# Executed:
#   bash scripts/mcp-client.sh register <claude|codex|grok|agy> <http|sse|stdio>
#   bash scripts/mcp-client.sh config-check <claude|codex|grok|agy>
#
# Sourced (health-check):
#   resolve_token <ENV_VAR>  — process env, then launchctl getenv

resolve_token() {
  local var="$1"
  local token="${!var:-}"
  [[ -z "$token" ]] && token="$(launchctl getenv "$var" 2>/dev/null || true)"
  printf '%s\n' "$token"
}

_mcp_client_bin() {
  case "$1" in
    claude) printf '%s\n' "${CLAUDE:-claude}" ;;
    codex) printf '%s\n' "${CODEX:-codex}" ;;
    grok) printf '%s\n' "${GROK:-grok}" ;;
    agy) printf '%s\n' "${AGY:-agy}" ;;
    *) echo "unknown client: $1" >&2; return 1 ;;
  esac
}

_mcp_client_title() {
  case "$1" in
    claude) echo Claude ;;
    codex) echo Codex ;;
    grok) echo Grok ;;
    agy) echo AGY ;;
    *) return 1 ;;
  esac
}

_mcp_client_install_name() {
  case "$1" in
    claude) echo "Claude Code" ;;
    agy) echo "Antigravity CLI (agy)" ;;
    *) _mcp_client_title "$1" ;;
  esac
}

_mcp_client_defaults() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$script_dir/.." && pwd)}"
  START_SCRIPT="${START_SCRIPT:-$PROJECT_ROOT/scripts/start.sh}"
  HEADERS_HELPER="${HEADERS_HELPER:-$PROJECT_ROOT/scripts/mcp-auth-headers.sh}"
  MCP_NAME="${MCP_NAME:-telegram-mcp}"
  HTTP_URL="${HTTP_URL:-http://127.0.0.1:8765/mcp}"
  SSE_URL="${SSE_URL:-http://127.0.0.1:8765/sse}"
  CODEX_BEARER_ENV="${CODEX_BEARER_ENV:-TELEGRAM_MCP_TOKEN}"
  GROK_BEARER_ENV="${GROK_BEARER_ENV:-TELEGRAM_MCP_TOKEN}"
  AGY_BEARER_ENV="${AGY_BEARER_ENV:-TELEGRAM_MCP_TOKEN}"
}

_mcp_client_remove() {
  local client="$1" bin="$2" name="$3"
  case "$client" in
    claude | grok) "$bin" mcp remove --scope user "$name" >/dev/null 2>&1 || true ;;
    codex | agy) "$bin" mcp remove "$name" >/dev/null 2>&1 || true ;;
  esac
}

_mcp_client_add() {
  local client="$1" transport="$2" bin="$3"
  case "$client:$transport" in
    claude:http)
      "$bin" mcp add-json --scope user "$MCP_NAME" \
        "{\"type\":\"http\",\"url\":\"$HTTP_URL\",\"headersHelper\":\"$HEADERS_HELPER\"}"
      ;;
    claude:sse)
      "$bin" mcp add-json --scope user "$MCP_NAME" \
        "{\"type\":\"sse\",\"url\":\"$SSE_URL\",\"headersHelper\":\"$HEADERS_HELPER\"}"
      ;;
    claude:stdio)
      "$bin" mcp add --scope user "$MCP_NAME" -- "$START_SCRIPT" --transport stdio
      ;;
    codex:http)
      "$bin" mcp add "$MCP_NAME" --url "$HTTP_URL" --bearer-token-env-var "$CODEX_BEARER_ENV"
      ;;
    codex:stdio)
      "$bin" mcp add "$MCP_NAME" -- "$START_SCRIPT" --transport stdio
      ;;
    grok:http)
      "$bin" mcp add --scope user --transport http "$MCP_NAME" "$HTTP_URL" \
        --header "Authorization: Bearer \${${GROK_BEARER_ENV}}"
      ;;
    grok:stdio)
      "$bin" mcp add --scope user "$MCP_NAME" -- "$START_SCRIPT" --transport stdio
      ;;
    agy:http)
      "$bin" mcp add --type http \
        --header "Authorization: Bearer \${${AGY_BEARER_ENV}}" \
        "$MCP_NAME" "$HTTP_URL"
      ;;
    agy:stdio)
      "$bin" mcp add "$MCP_NAME" -- "$START_SCRIPT" --transport stdio
      ;;
    *:sse)
      echo "legacy SSE is only supported for Claude" >&2
      return 1
      ;;
    *)
      echo "unknown client/transport: $client $transport" >&2
      return 1
      ;;
  esac
}

_mcp_client_registering_line() {
  case "$1" in
    http) echo "Registering '$MCP_NAME' via Streamable HTTP at $HTTP_URL ..." ;;
    sse) echo "Registering '$MCP_NAME' via legacy SSE at $SSE_URL ..." ;;
    stdio) echo "Registering '$MCP_NAME' via stdio from $PROJECT_ROOT ..." ;;
    *) echo "unknown transport: $1" >&2; return 1 ;;
  esac
}

_mcp_client_success() {
  local client="$1" transport="$2"
  case "$client:$transport" in
    claude:http)
      echo "Registered '$MCP_NAME' for Claude. Restart Claude Code to apply the change."
      ;;
    claude:sse)
      echo "Registered '$MCP_NAME' as legacy SSE for Claude. Restart Claude Code to apply the change."
      ;;
    claude:stdio)
      echo "Registered '$MCP_NAME' as stdio for Claude. Restart Claude Code to apply the change."
      ;;
    codex:http)
      echo "Registered '$MCP_NAME' for Codex. Restart Codex after the launchd service is running."
      ;;
    codex:stdio)
      echo "Registered '$MCP_NAME' as stdio. Restart Codex to apply the change."
      ;;
    grok:http)
      echo "Registered '$MCP_NAME' for Grok. Restart Grok to apply the change."
      ;;
    grok:stdio)
      echo "Registered '$MCP_NAME' as stdio for Grok. Restart Grok to apply the change."
      ;;
    agy:http)
      echo "Registered '$MCP_NAME' for AGY. Restart agy to apply the change."
      ;;
    agy:stdio)
      echo "Registered '$MCP_NAME' as stdio for AGY. Restart agy to apply the change."
      ;;
    *)
      return 1
      ;;
  esac
}

_mcp_client_register() {
  local client="$1" transport="$2"
  local bin title
  _mcp_client_defaults
  bin="$(_mcp_client_bin "$client")"
  title="$(_mcp_client_title "$client")"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "$title CLI not found — skipping $title registration."
    echo "After installing $(_mcp_client_install_name "$client"), run 'make use-${transport}-${client}'."
    return 0
  fi
  echo "Removing existing '$MCP_NAME' $title MCP registration (if any)..."
  _mcp_client_remove "$client" "$bin" "$MCP_NAME"
  _mcp_client_registering_line "$transport"
  _mcp_client_add "$client" "$transport" "$bin"
  echo ""
  _mcp_client_success "$client" "$transport"
}

_mcp_client_config_check() {
  local client="$1"
  local bin title
  _mcp_client_defaults
  bin="$(_mcp_client_bin "$client")"
  title="$(_mcp_client_title "$client")"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "$title CLI not found — $title is not configured. After installing it, run 'make use-http-${client}'."
    return 0
  fi
  case "$client" in
    claude | codex)
      "$bin" mcp get "$MCP_NAME" || echo "($MCP_NAME not yet registered with $title)"
      ;;
    grok | agy)
      "$bin" mcp list | grep -F "$MCP_NAME" || echo "($MCP_NAME not yet registered with $title)"
      ;;
  esac
}

_mcp_client_main() {
  set -euo pipefail
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    register)
      _mcp_client_register "${1:-}" "${2:-}"
      ;;
    config-check)
      _mcp_client_config_check "${1:-}"
      ;;
    *)
      echo "usage: $0 register <claude|codex|grok|agy> <http|sse|stdio>" >&2
      echo "       $0 config-check <claude|codex|grok|agy>" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  _mcp_client_main "$@"
fi
