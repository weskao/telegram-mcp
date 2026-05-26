# Telegram MCP — Setup 指南

每位成員需要用**自己的** Telegram 帳號完成以下步驟。Session 綁定個人帳號，不能共用。

**推薦方式：SSE 模式**。一個常駐 server 在本機執行，所有 IDE 透過 HTTP 共用同一條 session，避免多個 IDE 同時啟動時互相衝突。設定完成後在 `~/.claude.json` 全域登記一次，所有專案均可使用，不需要在各專案中重複設定 `.mcp.json`。

> 若不想 clone 本專案，可改用[備用：stdio 模式](#備用stdio-模式無需-clone-本專案)，但同一台機器上多個 IDE 同時使用時會有 session 衝突問題。

---

## 前置需求

### 安裝 uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

安裝後重新開啟 Terminal，確認可以執行 `uv --version`。

### Clone 本專案

**團隊成員請改用內部 GitLab fork**（包含團隊客製化的工具存取控制等設定）：

```bash
git clone <團隊 GitLab URL>
cd telegram-mcp
```

> 上游公開版本位於 `https://github.com/chigwell/telegram-mcp.git`，僅供參考。所有 PR / issue 請在內部 GitLab 處理。

<!-- -->

> **一鍵設定（步驟一至五）：** clone 完成後直接執行 `bash scripts/setup.sh`。script 會自動安裝缺少的 uv、引導你完成憑證輸入、安裝 launchd 服務並設定 `~/.claude.json`，完成後重啟 Claude Code 即可。以下步驟說明各階段的細節供參考。

---

## 步驟一：申請 Telegram API 憑證

1. 瀏覽 [my.telegram.org/apps](https://my.telegram.org/apps)，用你的 Telegram 帳號登入
2. 建立一個 App（名稱任意），取得：
   - `App api_id`（純數字）
   - `App api_hash`（32 位英數字串）

> 每個人的 API 憑證是獨立的，不要使用別人的 `api_id` / `api_hash`。

### Troubleshooting：my.telegram.org 建立 App 失敗（ERROR）

點擊 Create application 後出現 ERROR，Telegram 不顯示任何詳細原因。

**根本原因**：Telegram 故意隱藏錯誤細節以防自動化濫用。核心機制是 **IP 地理位置須與手機號碼所屬地區相符**，不符則靜默拒絕。參考：[GitHub issue #597](https://github.com/tdlib/telegram-bot-api/issues/597)、[GitHub issue #573](https://github.com/tdlib/telegram-bot-api/issues/573)（Telegram 官方 contributor `levlam` 親回確認：關閉 VPN / 換 ISP 是主要解法）。Telegram 對 `my.telegram.org` 加入了反自動化偵測機制，故意阻擋 Bot 大量申請 API，因此同一操作在不同網路環境 / 瀏覽器狀態下結果可能完全不同。

#### 解法 1 — 用手機行動網路（最多人確認有效）

用手機瀏覽器（iOS / Android），切到電信 4G/5G（關閉 WiFi），登入 [my.telegram.org](https://my.telegram.org/apps) 建立 App。行動網路 IP 與手機號碼所屬地區最一致，通過率最高。

#### 解法 2 — 手機開熱點分享給電腦 + Chrome 無痕（親測有效）

1. 裝置關閉 VPN
2. 手機切到 4G/5G 行動網路（關閉 WiFi）
3. 開啟個人熱點，讓電腦連到手機熱點
4. 電腦用 **Chrome 無痕模式**，登入 [my.telegram.org](https://my.telegram.org/apps) 建立 App

行動網路 IP 與手機號碼地區一致（原理同解法 1），無痕模式同時清除瀏覽器 fingerprint / Cookie 等自動化特徵，雙重降低被 Telegram 判定為自動化的機率。

---

## 步驟二：產生 Session String

Session string 是一次性操作，產生後存起來，之後不需要再次驗證。

在 **專案目錄內** 執行：

```bash
TELEGRAM_API_ID=你的api_id \
TELEGRAM_API_HASH=你的api_hash \
uv run telegram-mcp-generate-session
```

依照提示輸入手機號碼（含國碼，例如 `+886912345678`）和 Telegram 傳來的驗證碼。

成功後畫面會顯示一串以 `1BV...` 開頭的長字串，這就是你的 `SESSION_STRING`，**請複製並妥善保存**。

---

## 步驟三：存入 macOS Keychain

SSE 常駐服務在開機後自動從 Keychain 載入 Telegram 憑證（`api_id`、`api_hash`、`session_string`）。**這三項憑證不會寫入任何 config 檔**。

> **SSE bearer token 說明：** `install-launchd.sh` 會另外產生一個本機服務鑑權 token（與上述 Telegram 憑證無關），並將其寫入 `~/.claude.json`，供 Claude Code 連線 SSE server 使用。這是預期行為，`~/.claude.json` 權限為 `600`（僅本機使用者可讀），bearer token 也只對 `127.0.0.1:8306` 有效，不直接暴露 Telegram 帳號存取權。

```bash
security add-generic-password -a "$USER" -s telegram-api-id        -w "你的api_id"
security add-generic-password -a "$USER" -s telegram-api-hash       -w "你的api_hash"
security add-generic-password -a "$USER" -s telegram-session-string -w "你的session_string"
```

存入後驗證（三個指令都能印出值才繼續）：

```bash
security find-generic-password -a "$USER" -s telegram-api-id -w
security find-generic-password -a "$USER" -s telegram-api-hash -w
security find-generic-password -a "$USER" -s telegram-session-string -w
```

---

## 步驟四：安裝 launchd 常駐服務

在專案目錄內執行：

```bash
bash scripts/install-launchd.sh
```

script 自動完成：

1. 產生 bearer token 並存入 Keychain（`telegram-mcp-token`）
2. 在 `~/Library/LaunchAgents/` 建立 `com.telegram-mcp.server.plist`
3. 立即載入並啟動 server 在 `127.0.0.1:8306`
4. 若 `~/.claude.json` 中已有 `telegram-mcp` entry，自動將其從 stdio 改為 SSE 模式

確認 server 已啟動（有 `data:` 開頭的串流輸出即正常）：

```bash
curl -s http://127.0.0.1:8306/sse \
  -H "Authorization: Bearer $(security find-generic-password -a "$USER" -s telegram-mcp-token -w)"
```

---

## 步驟五：設定 ~/.claude.json

> **推薦：直接使用 `bash scripts/setup.sh`**，會自動完成此步驟（包含填入 token、清理舊進程、驗證 SSE）。
> 以下為手動 fallback，僅在不使用 `setup.sh` 時參考。

`install-launchd.sh` 已自動產生 bearer token（存於 Keychain `telegram-mcp-token`）。

若 script 在步驟四成功 patch 了 `~/.claude.json`（輸出 `~/.claude.json updated to SSE mode`），此步驟**跳過**，直接重啟 Claude Code 即可。

若 script 輸出 `~/.claude.json has no telegram-mcp entry — skipping auto-patch`，表示 `~/.claude.json` 中尚無此 entry，需手動加入。

> **bearer token 必須以明文填入 `~/.claude.json`：** `headers` 欄位是靜態 JSON，不支援 `$(security ...)` 等 shell 動態取值。這是 Claude Code 的設計限制。
> 可接受性：token 只對 `127.0.0.1:8306` 有效，`~/.claude.json` 權限為 `600`，Telegram 憑證本身仍在 Keychain 中，不受影響。

取得 token：

```bash
security find-generic-password -a "$USER" -s telegram-mcp-token -w
```

在 `~/.claude.json` 的 `mcpServers` 物件中加入（將上一行的輸出值直接貼入）：

```json
"telegram-mcp": {
  "type": "sse",
  "url": "http://127.0.0.1:8306/sse",
  "headers": {
    "Authorization": "Bearer <上一行印出的token>"
  }
}
```

完全結束 Claude Code（**所有視窗**）後重新開啟即生效。

---

## 管理常駐服務

```bash
# 查看狀態（正常會顯示 PID）
launchctl list | grep telegram-mcp

# 停止
launchctl unload ~/Library/LaunchAgents/com.telegram-mcp.server.plist

# 啟動
launchctl load ~/Library/LaunchAgents/com.telegram-mcp.server.plist

# 查看錯誤日誌
tail -f ~/Library/Logs/telegram-mcp/server.err.log
```

SSE server 只在**本機**監聽（`127.0.0.1:8306`），不會暴露到網路。

---

## 從 stdio 升級到 SSE 模式

若你之前用 stdio 模式，現在想切換到 SSE：

```bash
bash scripts/setup.sh
```

script 是 idempotent 的，重跑會：

1. 沿用 Keychain 中已有的憑證（不會重新驗證手機）
2. 安裝/重啟 launchd SSE server
3. 把 `~/.claude.json` 全域 `mcpServers.telegram-mcp` 改為 SSE
4. **清理舊的 stdio zombie 進程**（切換前 Claude Code 啟動的 stdio process 不會自動回收）
5. 警告任何專案層級的 `telegram-mcp` 覆蓋（會 shadow 全域 SSE 設定）

完成後完全結束 Claude Code（所有視窗）再重新開啟。

---

## 伺服器環境設定（.env）

SSE 常駐服務在啟動時載入專案目錄的 `.env`。需要調整以下功能時，在 `.env` 中加入對應的變數（複製 `.env.example` 作為起點）：

```bash
cp .env.example .env
```

修改 `.env` 後需重新啟動服務才會生效：

```bash
launchctl unload ~/Library/LaunchAgents/com.telegram-mcp.server.plist
launchctl load  ~/Library/LaunchAgents/com.telegram-mcp.server.plist
```

> stdio 模式使用者：在 `.mcp.json` 的 `env` 區塊加入對應變數即可，不需要 `.env` 檔。

---

## 工具存取控制

### 預設停用的危險工具

以下 **19 個工具**預設停用（對 MCP 客戶端不可見），涵蓋不可逆刪除、權限變更、大量個人資料寫入等高風險操作：

| 類別 | 工具 |
| ---- | ---- |
| 刪除訊息 | `delete_message`、`delete_messages_bulk`、`delete_scheduled_message`、`delete_chat_history` |
| 刪除資料 | `delete_folder`、`delete_contact`、`delete_profile_photo`、`delete_chat_photo` |
| 群組管理 | `ban_user`、`promote_admin`、`demote_admin`、`edit_admin_rights` |
| 建立群組 | `create_group`、`create_channel` |
| 資料匯出入 | `export_contacts`、`export_chat_invite`、`import_contacts` |
| 帳號設定 | `set_privacy_settings`、`leave_chat` |

### TELEGRAM_EXTRA_UNBLOCKED_TOOLS — 精確解鎖

從預設停用清單中開放指定工具（其餘仍封鎖）。在 `.env` 中加入：

```bash
TELEGRAM_EXTRA_UNBLOCKED_TOOLS=delete_message
```

多個工具用逗號分隔：

```bash
TELEGRAM_EXTRA_UNBLOCKED_TOOLS=delete_message,delete_messages_bulk
```

> 列出的工具必須在預設停用清單內才有效；填入其他工具名稱不會產生作用（server 啟動時會印出 Warning）。

### TELEGRAM_EXTRA_BLOCKED_TOOLS — 額外鎖定

把平時可用的工具也加入封鎖（例如打造近唯讀環境）：

```bash
TELEGRAM_EXTRA_BLOCKED_TOOLS=send_message,forward_message,edit_message,block_user
```

### 衝突規則

同一工具同時出現在兩個變數中時，**`TELEGRAM_EXTRA_BLOCKED_TOOLS` 優先**，工具保持停用。

> 操作完後建議移除這幾行並重啟服務。

---

## 顯示時區

所有工具輸出的時間戳記預設為 **UTC+8**。如需調整，在 `.env` 加入：

```bash
TELEGRAM_DISPLAY_TZ=8
```

值為整數 UTC 偏移小時，例如 `0` = UTC、`-5` = EST、`9` = JST。

---

## 多帳號模式

同時連接多個 Telegram 帳號，在 `.env` 中為每個帳號加上 `_<標籤>` 後綴：

```bash
TELEGRAM_SESSION_STRING_WORK=工作帳號的session_string
TELEGRAM_SESSION_STRING_PERSONAL=個人帳號的session_string
```

`TELEGRAM_API_ID` 和 `TELEGRAM_API_HASH` 共用同一組即可。

多帳號模式下，讀取類工具（`get_messages`、`list_chats` 等）若未指定 `account` 參數，會同時查詢所有帳號並合併結果；寫入類工具（`send_message` 等）則必須明確指定 `account`。

> 建議將各帳號的 session string 存入 Keychain，再在 `.env` 中以指令讀取，避免明文儲存。

---

## 下載媒體安全過濾

`download_media` 工具會根據檔案內容（非檔名）判斷副檔名，並拒絕危險類型（可執行檔、腳本等）。預設行為已涵蓋常見安全需求，通常無需調整。

若需自訂，在 `.env` 加入（**完整取代**預設清單）：

```bash
TELEGRAM_DOWNLOAD_ALLOWED_EXT=jpg,jpeg,png,gif,mp4,pdf,txt,md,csv
TELEGRAM_DOWNLOAD_BLOCKED_EXT=exe,msi,bat,sh,ps1,js,jar,dmg,pkg,apk
```

> 封鎖清單優先於允許清單。若要允許 `.zip`，需同時從 `TELEGRAM_DOWNLOAD_BLOCKED_EXT` 移除並加入 `TELEGRAM_DOWNLOAD_ALLOWED_EXT`。

---

## Proxy（代理）

透過 SOCKS5/SOCKS4/HTTP 代理路由 Telegram 流量（需先安裝 `proxy` extra：`uv sync --extra proxy`）。在 `.env` 加入：

```bash
TELEGRAM_PROXY_TYPE=socks5
TELEGRAM_PROXY_HOST=127.0.0.1
TELEGRAM_PROXY_PORT=1080
```

MTProxy：

```bash
TELEGRAM_PROXY_TYPE=mtproxy
TELEGRAM_PROXY_HOST=proxy.example.com
TELEGRAM_PROXY_PORT=443
TELEGRAM_PROXY_SECRET=<hex secret>
```

多帳號時可用 `_<標籤>` 後綴為特定帳號設定不同代理，例如 `TELEGRAM_PROXY_TYPE_WORK`。

---

## 驗證安裝

重啟 Claude Code 後執行：

```bash
claude mcp list
```

看到 `telegram-mcp` 出現且狀態正常即完成。也可以直接問 Claude「幫我查看我的 Telegram 帳號資訊」，Claude 應該能回傳你的帳號名稱。

---

## 常見問題

**Q: 驗證碼輸入正確但一直失敗？**
A: 確認 `api_id` 和 `api_hash` 是從你自己帳號申請的，不是別人的。

**Q: Session 過期了怎麼辦？**
A: 重新執行步驟二產生新的 session string，替換 Keychain 中的舊值：

```bash
security delete-generic-password -a "$USER" -s telegram-session-string
security add-generic-password -a "$USER" -s telegram-session-string -w "新的session_string"
```

替換後重啟 launchd 服務。

**Q: 可以在多台電腦使用同一個 session string 嗎？**
A: **不行**。Telegram MTProto 的 session string 綁定到單一連線 — 兩台電腦同時使用同一個 session，Telegram 會立即撤銷它，兩邊都斷線。

| 憑證 | 兩台共用？ |
| ---- | ---- |
| `telegram-api-id` | ✅ 可以共用 |
| `telegram-api-hash` | ✅ 可以共用 |
| `telegram-session-string` | ❌ 每台要各自產生 |

每台電腦各自執行步驟二，產生獨立的 session string，分別存入各自機器的 Keychain。

**Q: MCP server 啟動後看到 `Tool disabled: delete_message` 的訊息？**
A: 這是正常行為，代表危險工具保護機制正在運作。若需要啟用，參考上方「工具存取控制」章節。

**Q: install-launchd.sh 說 `~/.claude.json` 沒有 telegram-mcp entry？**
A: 執行 script 前 `~/.claude.json` 中還沒有 `telegram-mcp`，所以 script 跳過自動修改。改用 `bash scripts/setup.sh` 會自動建立 entry，或按照步驟五手動填入。

**Q: 切換到 SSE 後 `ps aux | grep telegram-mcp` 仍有多個進程？**
A: 那些是切換前 Claude Code 啟動的 stdio process，不會自動回收。`setup.sh` 會自動清理；也可手動執行：

```bash
ps -axo pid,command | awk '$NF == "telegram-mcp" {print $1}' | xargs kill 2>/dev/null
```

確認 `~/.claude.json` 已切換 SSE 後再殺，否則 Claude Code 會立刻 respawn。

**Q: 某個專案無法看到 telegram-mcp 工具？**
A: 該專案可能在 `~/.claude.json` 的 `projects.<path>.mcpServers` 有獨立 stdio 設定，覆蓋了全域 SSE 設定。檢查：

```bash
python3 -c "
import json
d = json.load(open('$HOME/.claude.json'))
for p, v in d.get('projects', {}).items():
    if 'telegram-mcp' in v.get('mcpServers', {}):
        print(p)
"
```

清理：`bash scripts/setup.sh --clean-project-overrides`

---

## 備用：stdio 模式（無需 clone 本專案）

只需安裝 uv，不需要 clone 本專案。缺點：同一台機器多個 IDE 同時使用時，各自啟動獨立進程，會因 session 重連互相衝突。

完成步驟一至三後，在 `.mcp.json` 或 Claude Desktop config 中加入：

### Claude Code（.mcp.json）

```json
{
  "mcpServers": {
    "telegram-mcp": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/chigwell/telegram-mcp.git",
        "telegram-mcp"
      ],
      "env": {
        "TELEGRAM_API_ID": "你的api_id",
        "TELEGRAM_API_HASH": "你的api_hash",
        "TELEGRAM_SESSION_STRING": "你的session_string"
      }
    }
  }
}
```

> `.mcp.json` 包含個人憑證，不應 commit 到 git。確認 `.gitignore` 有排除它。

若已把憑證存入 Keychain，可在 `~/.zshrc` 加入下列匯出，並省略 `.mcp.json` 的 `env` 區塊（Claude Code 會繼承 shell 環境變數）：

```bash
export TELEGRAM_API_ID=$(security find-generic-password -a "$USER" -s telegram-api-id -w 2>/dev/null)
export TELEGRAM_API_HASH=$(security find-generic-password -a "$USER" -s telegram-api-hash -w 2>/dev/null)
export TELEGRAM_SESSION_STRING=$(security find-generic-password -a "$USER" -s telegram-session-string -w 2>/dev/null)
```

工具存取控制、時區等設定在 `env` 區塊中加入對應變數。

### Claude Desktop

編輯 `~/Library/Application Support/Claude/claude_desktop_config.json`：

```json
{
  "mcpServers": {
    "telegram-mcp": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/chigwell/telegram-mcp.git",
        "telegram-mcp"
      ],
      "env": {
        "TELEGRAM_API_ID": "你的api_id",
        "TELEGRAM_API_HASH": "你的api_hash",
        "TELEGRAM_SESSION_STRING": "你的session_string"
      }
    }
  }
}
```

**Q: uvx 每次都會重新下載嗎？**
A: 第一次執行時會下載並快取，之後使用快取版本。若需要更新到最新版，執行：

```bash
uvx --from git+https://github.com/chigwell/telegram-mcp.git --reinstall telegram-mcp
```
