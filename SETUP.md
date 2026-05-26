# Telegram MCP — Setup 指南

每位成員需要用**自己的** Telegram 帳號完成以下步驟。Session 綁定個人帳號，不能共用。

基本模式（stdio）不需要 clone 專案，只需要安裝 [uv](https://docs.astral.sh/uv/)，其餘全部由 `uvx` 自動處理。進階 SSE 模式需要 clone 專案（使用 `scripts/install-launchd.sh`）。

---

## 步驟一：安裝 uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

安裝後重新開啟 Terminal，確認可以執行 `uvx --version`。

---

## 步驟二：申請 Telegram API 憑證

1. 瀏覽 [my.telegram.org/apps](https://my.telegram.org/apps)，用你的 Telegram 帳號登入
2. 建立一個 App（名稱任意），取得：
   - `App api_id`（純數字）
   - `App api_hash`（32 位英數字串）

> 每個人的 API 憑證是獨立的，不要使用別人的 `api_id` / `api_hash`。

---

## 步驟三：產生 Session String

Session string 是一次性操作，產生後存起來，之後不需要再次驗證。

```bash
TELEGRAM_API_ID=你的api_id \
TELEGRAM_API_HASH=你的api_hash \
uvx --from git+https://github.com/chigwell/telegram-mcp.git telegram-mcp-generate-session
```

依照提示輸入手機號碼（含國碼，例如 `+886912345678`）和 Telegram 傳來的驗證碼。

成功後畫面會顯示一串以 `1BV...` 開頭的長字串，這就是你的 `SESSION_STRING`，**請複製並妥善保存**。

---

## 步驟四：存入 macOS Keychain（推薦）

比起直接寫在 config 檔裡，Keychain 不會意外洩漏憑證。

```bash
security add-generic-password -a "$USER" -s telegram-api-id       -w "你的api_id"
security add-generic-password -a "$USER" -s telegram-api-hash      -w "你的api_hash"
security add-generic-password -a "$USER" -s telegram-session-string -w "你的session_string"
```

存入後驗證（應該印出你的 api_id）：

```bash
security find-generic-password -a "$USER" -s telegram-api-id -w
```

---

## 步驟五：設定 MCP Server

### Claude Code

在你的 workspace 根目錄建立（或編輯）`.mcp.json`：

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

若已把憑證存入 Keychain，可改用環境變數方式（不在 `.mcp.json` 明文存憑證）：

在 `~/.zshrc` 加入：

```bash
export TELEGRAM_API_ID=$(security find-generic-password -a "$USER" -s telegram-api-id -w 2>/dev/null)
export TELEGRAM_API_HASH=$(security find-generic-password -a "$USER" -s telegram-api-hash -w 2>/dev/null)
export TELEGRAM_SESSION_STRING=$(security find-generic-password -a "$USER" -s telegram-session-string -w 2>/dev/null)
```

然後 `.mcp.json` 的 `env` 區塊就可以省略（Claude Code 會繼承 shell 環境變數）。

#### 已 clone 本專案的替代方式

若已將本 repo clone 到本機，可改用 `scripts/start.sh` 作為 command（它會自動從 Keychain 載入憑證，不需要在 `.mcp.json` 裡設定任何 `env`）：

```json
{
  "mcpServers": {
    "telegram-mcp": {
      "command": "/path/to/telegram-mcp/scripts/start.sh"
    }
  }
}
```

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

從預設停用清單中開放指定工具（其餘仍封鎖）。

**只需要刪除單則訊息時**：

```json
"TELEGRAM_EXTRA_UNBLOCKED_TOOLS": "delete_message"
```

多個工具用逗號分隔：

```json
"TELEGRAM_EXTRA_UNBLOCKED_TOOLS": "delete_message,delete_messages_bulk"
```

> 列出的工具必須在預設停用清單內才有效；填入其他工具名稱不會產生作用（server 啟動時會印出 Warning）。

### TELEGRAM_EXTRA_BLOCKED_TOOLS — 額外鎖定

把平時可用的工具也加入封鎖（例如打造近唯讀環境）：

```json
"TELEGRAM_EXTRA_BLOCKED_TOOLS": "send_message,forward_message,edit_message,block_user"
```

### 衝突規則

同一工具同時出現在兩個變數中時，**`TELEGRAM_EXTRA_BLOCKED_TOOLS` 優先**，工具保持停用。

> 操作完後建議移除這幾行並重啟 MCP server。

---

## 顯示時區

所有工具輸出的時間戳記預設為 **UTC+8**。如需調整，在 `.mcp.json` 的 `env` 加入：

```json
"TELEGRAM_DISPLAY_TZ": "8"
```

值為整數 UTC 偏移小時，例如 `0` = UTC、`-5` = EST、`9` = JST。

---

## 多帳號模式

同時連接多個 Telegram 帳號，在每個 session 變數加上 `_<標籤>` 後綴：

```json
"TELEGRAM_SESSION_STRING_WORK":     "工作帳號的session_string",
"TELEGRAM_SESSION_STRING_PERSONAL": "個人帳號的session_string"
```

`TELEGRAM_API_ID` 和 `TELEGRAM_API_HASH` 共用同一組即可。

多帳號模式下，讀取類工具（`get_messages`、`list_chats` 等）若未指定 `account` 參數，會同時查詢所有帳號並合併結果；寫入類工具（`send_message` 等）則必須明確指定 `account`。

---

## 下載媒體安全過濾

`download_media` 工具會根據檔案內容（非檔名）判斷副檔名，並拒絕危險類型（可執行檔、腳本等）。預設行為已涵蓋常見安全需求，通常無需調整。

若需自訂允許或封鎖的副檔名，在 `.mcp.json` 的 `env` 加入（**完整取代**預設清單）：

```json
"TELEGRAM_DOWNLOAD_ALLOWED_EXT": "jpg,jpeg,png,gif,mp4,pdf,txt,md,csv",
"TELEGRAM_DOWNLOAD_BLOCKED_EXT": "exe,msi,bat,sh,ps1,js,jar,dmg,pkg,apk"
```

> 封鎖清單優先於允許清單。若要允許 `.zip`，需同時從 `TELEGRAM_DOWNLOAD_BLOCKED_EXT` 移除並加入 `TELEGRAM_DOWNLOAD_ALLOWED_EXT`。

---

## Proxy（代理）

透過 SOCKS5/SOCKS4/HTTP 代理路由 Telegram 流量（需先安裝 `proxy` extra：`uv sync --extra proxy`）：

```json
"TELEGRAM_PROXY_TYPE": "socks5",
"TELEGRAM_PROXY_HOST": "127.0.0.1",
"TELEGRAM_PROXY_PORT": "1080"
```

MTProxy：

```json
"TELEGRAM_PROXY_TYPE": "mtproxy",
"TELEGRAM_PROXY_HOST": "proxy.example.com",
"TELEGRAM_PROXY_PORT": "443",
"TELEGRAM_PROXY_SECRET": "<hex secret>"
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
A: 重新執行步驟三產生新的 session string，替換 Keychain 中的舊值：

```bash
security delete-generic-password -a "$USER" -s telegram-session-string
security add-generic-password -a "$USER" -s telegram-session-string -w "新的session_string"
```

**Q: 可以在多台電腦使用同一個 session string 嗎？**
A: **不行**。Telegram MTProto 的 session string 綁定到單一連線 — 兩台電腦同時使用同一個 session，Telegram 會立即撤銷它，兩邊都斷線。

憑證共用規則如下：

| 憑證                       | 兩台共用？        |
| -------------------------- | ----------------- |
| `telegram-api-id`          | ✅ 可以共用       |
| `telegram-api-hash`        | ✅ 可以共用       |
| `telegram-session-string`  | ❌ 每台要各自產生 |

每台電腦各自執行步驟三，產生獨立的 session string，分別存入各自機器的 Keychain。

**Q: MCP server 啟動後看到 `Tool disabled: delete_message` 的訊息？**
A: 這是正常行為，代表危險工具保護機制正在運作。若需要啟用，參考上方「工具存取控制」章節。

**Q: uvx 每次都會重新下載嗎？**
A: 第一次執行時會下載並快取，之後使用快取版本。若需要更新到最新版，執行：

```bash
uvx --from git+https://github.com/chigwell/telegram-mcp.git --reinstall telegram-mcp
```

---

## 進階：SSE 模式（多個 IDE 共用同一連線）

> **前置要求**：SSE 模式需要 clone 本專案（`scripts/install-launchd.sh` 在 repo 裡）。

### 為什麼需要 SSE 模式？

預設 stdio 模式下，每個 IDE 各自啟動一個獨立的 `telegram-mcp` 進程。同一台機器上多個 IDE 同時使用時，會因為 session 重連互相衝突。

SSE（Server-Sent Events）模式改為啟動一個常駐 server，所有 IDE 透過 HTTP 連線共用同一個 session，避免重複初始化和衝突。

### 步驟一：確認 Keychain 已有三個憑證

原本就設過的人跳過。三個指令都能印出值才繼續。

```bash
security find-generic-password -a "$USER" -s telegram-api-id -w
security find-generic-password -a "$USER" -s telegram-api-hash -w
security find-generic-password -a "$USER" -s telegram-session-string -w
```

若尚未設置，先完成上方步驟四。

### 步驟二：安裝 launchd 常駐服務

```bash
bash scripts/install-launchd.sh
```

script 自動完成：

1. 產生 bearer token 並存入 Keychain（`telegram-mcp-token`）
2. 在 `~/Library/LaunchAgents/` 建立 plist
3. 立即載入並啟動 server 在 port 8306

### 步驟三：確認 server 已啟動

```bash
curl -s http://127.0.0.1:8306/sse \
  -H "Authorization: Bearer $(security find-generic-password -a "$USER" -s telegram-mcp-token -w)"
```

有輸出（`data:` 開頭的串流）即表示 server 正常運作。

### 步驟四：重啟 Claude Code

`install-launchd.sh` 已自動將 `~/.claude.json` 中的 `telegram-mcp` 從 stdio 改為 SSE 模式。重啟 Claude Code 即生效。

> **若 `~/.claude.json` 沒有 `telegram-mcp` entry**（例如只用 `.mcp.json` 設定），script 會提示需要手動修改。此時先取得 token：
>
> ```bash
> security find-generic-password -a "$USER" -s telegram-mcp-token -w
> ```
>
> 然後選擇以下其中一個位置填入 SSE 設定：
>
> **選項 A — 全域（`~/.claude.json`，所有 IDE 共用）：**
> 在 `mcpServers` 物件中加入：
>
> ```json
> "telegram-mcp": {
>   "type": "sse",
>   "url": "http://127.0.0.1:8306/sse",
>   "headers": {
>     "Authorization": "Bearer <上面取得的token>"
>   }
> }
> ```
>
> **選項 B — 專案層級（`.mcp.json`）：**
>
> ```json
> {
>   "mcpServers": {
>     "telegram-mcp": {
>       "type": "sse",
>       "url": "http://127.0.0.1:8306/sse",
>       "headers": {
>         "Authorization": "Bearer <上面取得的token>"
>       }
>     }
>   }
> }
> ```

### 管理常駐服務

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

### 注意事項

- SSE server 只在**本機**監聽（`127.0.0.1:8306`），不會暴露到網路。
- Token 只用於 IDE 之間的內部認證，與 Telegram 憑證分開管理。
- 停用 SSE 模式：將 IDE 設定改回 stdio 模式即可。launchd service 仍在背景，但 IDE 會忽略它。
