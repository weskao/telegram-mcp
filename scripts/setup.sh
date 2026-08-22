#!/usr/bin/env bash
# One-shot setup: prerequisites → credentials → Keychain → launchd → MCP clients
#
# Usage:
#   bash scripts/setup.sh
#
# What this script handles automatically:
#   - Installs uv if missing
#   - Prompts for Telegram API ID, API Hash, and phone verification (session string)
#   - Stores all credentials in macOS Keychain
#   - Installs and starts the launchd Streamable HTTP server
#   - Registers Claude Code and Codex for authenticated Streamable HTTP
#
# Required user input (interactive prompts):
#   - Telegram API ID and API Hash (from https://my.telegram.org/apps)
#   - Phone number and Telegram verification code (for session string generation)
#   - Choose "store in Keychain" when the generator asks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

_kc_get() { security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null || true; }
_kc_set() {
  security delete-generic-password -a "$USER" -s "$1" 2>/dev/null || true
  security add-generic-password -a "$USER" -s "$1" -w "$2"
}

echo "=== Telegram MCP 快速設定 ==="
echo

# ── Prerequisites ─────────────────────────────────────────────────────────────

echo "前置需求檢查…"

# Xcode Command Line Tools (provides git, python3, security)
if ! xcode-select -p &>/dev/null; then
  echo "  安裝 Xcode Command Line Tools（需要管理員密碼）…"
  xcode-select --install
  echo "  ⚠️  安裝視窗已開啟，完成後請重新執行本 script"
  exit 0
fi

# uv
# The Astral installer drops uv in ~/.local/bin, which a non-login shell may not
# have on PATH yet — add it before probing so an existing install is found.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

if ! command -v uv &>/dev/null; then
  echo "  安裝 uv…"
  # Prefer the Astral installer: it ships prebuilt binaries. Homebrew is a
  # fallback because a prefix without bottles for this macOS/arch (e.g. a
  # Rosetta /usr/local brew) builds rust and llvm from source for hours.
  if curl -LsSf https://astral.sh/uv/install.sh | sh; then
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  elif command -v brew &>/dev/null; then
    brew install uv
  fi
  if ! command -v uv &>/dev/null; then
    echo "  ⚠️  uv 安裝完成但需要重新開啟 Terminal 後再執行本 script"
    exit 0
  fi
  echo "  ✅ uv 已安裝 ($(uv --version))"
else
  echo "  ✅ uv $(uv --version)"
fi

# curl (should always be present on macOS, but check anyway)
if ! command -v curl &>/dev/null; then
  echo "  ❌ curl 未找到，macOS 應內建 curl，請確認系統環境"
  exit 1
fi

echo

# ── Step 1: API credentials ───────────────────────────────────────────────────

echo "步驟 1：Telegram API 憑證（從 https://my.telegram.org/apps 取得）"

EXISTING_ID="$(_kc_get telegram-api-id)"
EXISTING_HASH="$(_kc_get telegram-api-hash)"

if [[ -n "$EXISTING_ID" && -n "$EXISTING_HASH" ]]; then
  echo "  Keychain 已有憑證 (api_id=${EXISTING_ID:0:4}…)，是否重新輸入？[y/N]"
  read -rp "  > " REDO_CREDS
  if [[ "$REDO_CREDS" =~ ^[Yy]$ ]]; then
    EXISTING_ID=""
    EXISTING_HASH=""
  fi
fi

if [[ -z "$EXISTING_ID" ]]; then
  read -rp "  API ID: " API_ID
  read -rp "  API Hash: " API_HASH
  _kc_set "telegram-api-id" "$API_ID"
  _kc_set "telegram-api-hash" "$API_HASH"
  echo "  ✅ 憑證已存入 Keychain"
else
  API_ID="$EXISTING_ID"
  API_HASH="$EXISTING_HASH"
  echo "  ✅ 沿用 Keychain 中的憑證"
fi
echo

# ── Step 2: Session string ────────────────────────────────────────────────────

echo "步驟 2：Session String"

EXISTING_SESSION="$(_kc_get telegram-session-string)"
if [[ -n "$EXISTING_SESSION" ]]; then
  echo "  Keychain 已有 session string，是否重新產生？[y/N]"
  read -rp "  > " REDO_SESSION
  if [[ ! "$REDO_SESSION" =~ ^[Yy]$ ]]; then
    echo "  ✅ 沿用 Keychain 中的 session string"
    echo
    SKIP_SESSION=1
  fi
fi

if [[ -z "${SKIP_SESSION:-}" ]]; then
  TELEGRAM_API_ID="$API_ID" \
  TELEGRAM_API_HASH="$API_HASH" \
    uv --directory "$PROJECT_DIR" run telegram-mcp-generate-session
fi
echo

# ── Step 3: launchd service ───────────────────────────────────────────────────

echo "步驟 3：安裝 Streamable HTTP launchd 常駐服務…"
bash "$SCRIPT_DIR/install-launchd.sh"
echo

# ── Step 4: MCP clients ──────────────────────────────────────────────────────

echo "步驟 4：確認 Claude Code 與 Codex MCP 設定…"
make -C "$PROJECT_DIR" config-check
echo

# Optional flag: clean up project-level telegram-mcp overrides
if [[ "${1:-}" == "--clean-project-overrides" ]]; then
  echo "清理專案層級 telegram-mcp 覆蓋…"
  CLAUDE_JSON="$HOME/.claude.json"
  python3 - "$CLAUDE_JSON" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    d = json.load(f)
removed = []
for proj, val in d.get("projects", {}).items():
    if "telegram-mcp" in val.get("mcpServers", {}):
        del val["mcpServers"]["telegram-mcp"]
        removed.append(proj)
if removed:
    with open(path, "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
    print(f"  ✅ 已移除 {len(removed)} 個專案覆蓋")
    for p in removed:
        print(f"       - {p}")
else:
    print("  ✅ 沒有專案覆蓋需要清理")
PYEOF
  echo
fi

# ── Step 5: Clean up stale stdio processes ────────────────────────────────────
# After switching to HTTP, pre-existing stdio telegram-mcp processes (spawned by
# Claude Code before the config change) become orphans. Since the new config
# points to HTTP, these won't be respawned after we kill them.

echo "步驟 5：清理舊的 stdio zombie 進程…"

ZOMBIES=$(ps -axo pid,command | awk '$NF == "telegram-mcp" {print $1}')
if [[ -n "$ZOMBIES" ]]; then
  COUNT=$(echo "$ZOMBIES" | wc -l | tr -d ' ')
  echo "$ZOMBIES" | xargs kill 2>/dev/null || true
  echo "  ✅ 已清理 $COUNT 個 zombie 進程"
else
  echo "  ✅ 無 zombie 進程"
fi
echo

# ── Step 6: Verify Streamable HTTP server ─────────────────────────────────────

echo "步驟 6：驗證 Streamable HTTP server…"

MCP_PORT=8765   # 需與 install-launchd.sh 的 --port 一致
MCP_URL="http://127.0.0.1:${MCP_PORT}/mcp"
LOG_ERR="$HOME/Library/Logs/telegram-mcp/server.err.log"
VERIFY_OK=1

# 6a. launchd 是否註冊、是否真的有進程
LAUNCHD_LINE="$(launchctl list | grep "com.telegram-mcp.server" || true)"
if [[ -z "$LAUNCHD_LINE" ]]; then
  echo "  ❌ launchd 服務未註冊，請重新執行 install-launchd.sh"
  VERIFY_OK=0
else
  SERVICE_PID="$(awk '{print $1}' <<<"$LAUNCHD_LINE")"
  if [[ "$SERVICE_PID" =~ ^[0-9]+$ ]]; then
    echo "  ✅ launchd 服務已啟動 (PID $SERVICE_PID)"
  else
    echo "  ⚠️  launchd 服務已註冊，但目前沒有執行中的進程"
  fi
fi

# 6b. port 是否真的在監聽（服務可能註冊成功卻不斷崩潰重啟）
if [[ "$VERIFY_OK" == 1 ]]; then
  PORT_UP=0
  for _ in $(seq 1 40); do
    if nc -z 127.0.0.1 "$MCP_PORT" 2>/dev/null; then PORT_UP=1; break; fi
    sleep 0.5
  done
  if [[ "$PORT_UP" == 1 ]]; then
    echo "  ✅ Port $MCP_PORT 監聽中"
  else
    echo "  ❌ Port $MCP_PORT 在 20 秒內沒有起來"
    VERIFY_OK=0
  fi
fi

# 6c. 認證與 MCP 交握
if [[ "$VERIFY_OK" == 1 ]]; then
  MCP_TOKEN="$(_kc_get telegram-mcp-token)"
  if [[ -z "$MCP_TOKEN" ]]; then
    echo "  ❌ Keychain 找不到 telegram-mcp-token，請重新執行 install-launchd.sh"
    VERIFY_OK=0
  else
    INIT_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"setup.sh","version":"1"}}}'

    CODE_NOAUTH="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$MCP_URL" \
      -X POST -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' -d "$INIT_BODY" || echo 000)"
    if [[ "$CODE_NOAUTH" == "401" ]]; then
      echo "  ✅ 未帶 token 正確回傳 401"
    else
      echo "  ⚠️  未帶 token 預期 401，實際收到 $CODE_NOAUTH"
    fi

    INIT_RESP="$(curl -s --max-time 15 "$MCP_URL" -X POST \
      -H "Authorization: Bearer $MCP_TOKEN" -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' -d "$INIT_BODY" || true)"
    if grep -q '"serverInfo"' <<<"$INIT_RESP"; then
      SERVER_INFO="$(sed -n 's/.*"serverInfo":{"name":"\([^"]*\)","version":"\([^"]*\)".*/\1 v\2/p' <<<"$INIT_RESP")"
      echo "  ✅ MCP 交握成功${SERVER_INFO:+（${SERVER_INFO}）}"
    else
      echo "  ❌ MCP 交握失敗（帶 token 仍無法取得 serverInfo）"
      VERIFY_OK=0
    fi
  fi
fi

# 6d. 失敗時給出可行動的診斷
if [[ "$VERIFY_OK" != 1 ]]; then
  echo
  echo "  ── 診斷 ──"
  if [[ -z "$(_kc_get telegram-session-string)" ]]; then
    SESSION_LABELS="$(_kc_get telegram-session-labels)"
    if [[ -n "$SESSION_LABELS" ]]; then
      echo "  ⚠️  Keychain 只有帶 label 的 session（${SESSION_LABELS}），"
      echo "      但服務讀取的是無 label 的 telegram-session-string。"
      echo "      請重跑步驟 2，並在 Account label 那題直接按 Enter 留空。"
    else
      echo "  ⚠️  Keychain 沒有 telegram-session-string。"
      echo "      請重跑步驟 2，並在最後一題輸入 y 存入 Keychain。"
    fi
  fi
  if [[ -f "$LOG_ERR" ]]; then
    echo "  最近的錯誤訊息（${LOG_ERR}）："
    { grep -v "IncompleteFieldDefinitionWarning\|warnings.warn" "$LOG_ERR" | tail -5 | sed 's/^/      /'; } || true
  fi
fi
echo

# ── Done ──────────────────────────────────────────────────────────────────────

if [[ "$VERIFY_OK" == 1 ]]; then
  echo "=== 設定完成 ==="
  echo
  echo "下一步："
  echo "  1. 完全結束 Claude Code 與 Codex，再重新開啟"
  echo "  2. 執行 'make config-check' 確認兩個 client 都已載入 Streamable HTTP"
  echo "  3. 在任一 client 中問「幫我查看我的 Telegram 帳號資訊」測試"
else
  echo "=== 設定尚未完成 ==="
  echo
  echo "server 無法正常提供服務，請依照上方診斷處理後重新執行本 script。"
  echo "重跑本 script 是安全的：已存在的憑證會被沿用，不會重複詢問。"
  exit 1
fi
