# Telegram MCP — 團隊 Setup 指南

每位成員需要用**自己的** Telegram 帳號完成以下步驟。Session 綁定個人帳號，不能共用。

不需要 clone 專案，只需要安裝 [uv](https://docs.astral.sh/uv/)，其餘全部由 `uvx` 自動處理。

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

## 關於危險工具（刪除訊息等）

以下工具**預設停用**，需要明確開啟才能使用：

- `delete_message`、`delete_chat_history`、`delete_messages_bulk`
- `ban_user`、`promote_admin`、`demote_admin`
- `create_group`、`create_channel`
- `export_contacts`、`export_chat_invite`

**只需要刪除單則訊息時**，建議精確控制（避免全開），在 `.mcp.json` 的 `env` 區塊加入：

```json
"TELEGRAM_ENABLE_DANGEROUS_TOOLS": "1",
"TELEGRAM_DISABLE_TOOLS": "delete_chat_history,delete_messages_bulk,ban_user,promote_admin,demote_admin,create_group,create_channel,export_contacts,export_chat_invite,delete_scheduled_message,delete_folder,delete_contact,delete_profile_photo,delete_chat_photo"
```

這樣只有 `delete_message` 被開放，其他危險工具仍然封鎖。

> 操作完後建議移除這兩行並重啟 MCP server。

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
A: 可以，但 Telegram 有連線數限制。建議每台電腦產生獨立的 session，避免互相踢掉線。

**Q: MCP server 啟動後看到 `Tool disabled: delete_message` 的訊息？**
A: 這是正常行為，代表危險工具保護機制正在運作。若需要啟用，參考上方「關於危險工具」章節。

**Q: uvx 每次都會重新下載嗎？**
A: 第一次執行時會下載並快取，之後使用快取版本。若需要更新到最新版，執行：

```bash
uvx --from git+https://github.com/chigwell/telegram-mcp.git --reinstall telegram-mcp
```
