#!/usr/bin/env bash
# One-shot setup: prerequisites → credentials → Keychain → launchd → ~/.claude.json
#
# Usage:
#   bash scripts/setup.sh
#
# What this script handles automatically:
#   - Installs uv if missing
#   - Prompts for Telegram API ID, API Hash, and phone verification (session string)
#   - Stores all credentials in macOS Keychain
#   - Installs and starts the launchd SSE server
#   - Patches ~/.claude.json for SSE mode
#
# Required user input (interactive prompts):
#   - Telegram API ID and API Hash (from https://my.telegram.org/apps)
#   - Phone number and Telegram verification code (for session string generation)
#   - Paste the resulting session string when prompted

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
if ! command -v uv &>/dev/null; then
  echo "  安裝 uv…"
  if command -v brew &>/dev/null; then
    brew install uv
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add to PATH for this session
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
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
    SESSION_STRING="$EXISTING_SESSION"
    SKIP_SESSION=1
  fi
fi

if [[ -z "${SKIP_SESSION:-}" ]]; then
  echo "  即將啟動互動式 session 產生器（需要輸入手機號碼和 Telegram 驗證碼）…"
  echo
  TELEGRAM_API_ID="$API_ID" \
  TELEGRAM_API_HASH="$API_HASH" \
    uv --directory "$PROJECT_DIR" run telegram-mcp-generate-session
  echo
  read -rp "  請將上方顯示的 Session String 貼入此處：" SESSION_STRING
  _kc_set "telegram-session-string" "$SESSION_STRING"
  echo "  ✅ Session string 已存入 Keychain"
fi
echo

# ── Step 3: launchd service ───────────────────────────────────────────────────

echo "步驟 3：安裝 launchd 常駐服務…"
bash "$SCRIPT_DIR/install-launchd.sh"
echo

# ── Step 4: ~/.claude.json ────────────────────────────────────────────────────

echo "步驟 4：設定 ~/.claude.json…"

TOKEN="$(_kc_get telegram-mcp-token)"
CLAUDE_JSON="$HOME/.claude.json"

if [[ -z "$TOKEN" ]]; then
  echo "  ⚠️  無法從 Keychain 讀到 telegram-mcp-token，請確認步驟 3 執行成功"
elif [[ ! -f "$CLAUDE_JSON" ]]; then
  echo "  ⚠️  ~/.claude.json 不存在，請先啟動 Claude Code 一次再執行本 script"
else
  python3 - "$CLAUDE_JSON" "$TOKEN" <<'PYEOF'
import json, sys
path, token = sys.argv[1], sys.argv[2]
with open(path) as f:
    d = json.load(f)
servers = d.setdefault("mcpServers", {})
servers["telegram-mcp"] = {
    "type": "sse",
    "url": "http://127.0.0.1:8306/sse",
    "headers": {"Authorization": f"Bearer {token}"},
}
# Detect project-level overrides that would shadow the global SSE config.
overrides = []
for proj, val in d.get("projects", {}).items():
    if "telegram-mcp" in val.get("mcpServers", {}):
        overrides.append(proj)
with open(path, "w") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print("  ✅ ~/.claude.json 全域 mcpServers 已設為 SSE 模式")
if overrides:
    print()
    print("  ⚠️  以下專案有獨立的 telegram-mcp 設定，會覆蓋全域 SSE 設定：")
    for p in overrides:
        print(f"       - {p}")
    print("       要讓這些專案也用 SSE，請手動刪除上述專案的 telegram-mcp entry，")
    print("       或執行：  bash scripts/setup.sh --clean-project-overrides")
PYEOF
fi
echo

# Optional flag: clean up project-level telegram-mcp overrides
if [[ "${1:-}" == "--clean-project-overrides" ]]; then
  echo "清理專案層級 telegram-mcp 覆蓋…"
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
# After switching to SSE, pre-existing stdio telegram-mcp processes (spawned by
# Claude Code before the config change) become orphans. Since the new config
# points to SSE, these won't be respawned after we kill them.

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

# ── Step 6: Verify SSE server ─────────────────────────────────────────────────

echo "步驟 6：驗證 SSE server…"
if launchctl list | grep -q "com.telegram-mcp.server"; then
  PID=$(launchctl list | grep "com.telegram-mcp.server" | awk '{print $1}')
  if [[ "$PID" =~ ^[0-9]+$ ]]; then
    echo "  ✅ launchd 服務運行中 (PID $PID)"
  else
    echo "  ⚠️  launchd 服務已註冊但未啟動，請檢查 ~/Library/Logs/telegram-mcp/server.err.log"
  fi
else
  echo "  ⚠️  launchd 服務未註冊，請重新執行 install-launchd.sh"
fi
echo

# ── Done ──────────────────────────────────────────────────────────────────────

echo "=== 設定完成 ==="
echo
echo "下一步："
echo "  1. 完全結束 Claude Code（所有視窗），再重新開啟"
echo "  2. 執行 'claude mcp list' 確認 telegram-mcp 已載入且為 SSE 模式"
echo "  3. 在 Claude Code 中問「幫我查看我的 Telegram 帳號資訊」測試"
