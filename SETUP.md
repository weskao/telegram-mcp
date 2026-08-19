# Telegram MCP — Setup 指南

每位成員需要用**自己的** Telegram 帳號完成以下步驟。Session 綁定個人帳號，不能共用。

**推薦方式：Streamable HTTP 模式**。一個 server 在本機執行，Claude Code 與 Codex 透過 HTTP 共用同一條 session，避免多個 IDE 同時啟動時互相衝突。預設用 `bash scripts/setup.sh` 安裝並登記兩個 client，不需要在各專案中重複設定。

> 若不想 clone 本專案，可改用[備用：stdio 模式](#備用stdio-模式)，但同一台機器上多個 IDE 同時使用時會有 session 衝突問題。

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

> **預設安裝方式：** clone 完成後可直接執行 `bash scripts/setup.sh`。script 會安裝缺少的 uv、引導你完成 Telegram 憑證與 session string、安裝 launchd 常駐 Streamable HTTP server，並把 Claude Code 與 Codex MCP 設定指向 `http://127.0.0.1:8765/mcp`。
>
> **常用指令：** 可執行 `make list` 查看所有 Makefile 指令。HTTP 模式用 `make start` 或 `make start-http` 前景啟動 server，再用 `make use-http` 將 Claude Code 與 Codex MCP 設定切到 `http://127.0.0.1:8765/mcp`。

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

## 步驟三：設定本機環境

若要使用預設一鍵安裝，可從這裡直接執行：

```bash
bash scripts/setup.sh
```

這會自動完成 Keychain 寫入、launchd Streamable HTTP 常駐服務安裝，以及 Claude Code／Codex MCP 設定。以下手動設定只在不使用 `setup.sh` 時需要。

如果你已經把 Telegram 憑證存入 macOS Keychain，並且下列三個 item 都存在，HTTP / SSE / stdio 的 Makefile 啟動指令會自動讀取它們，不需要在 `.env` 填寫 Telegram 憑證：

```bash
security find-generic-password -a "$USER" -s telegram-api-id -w >/dev/null
security find-generic-password -a "$USER" -s telegram-api-hash -w >/dev/null
security find-generic-password -a "$USER" -s telegram-session-string -w >/dev/null
```

如果尚未使用 Keychain，才需要複製 `.env.example`，把 Telegram 憑證寫進 `.env`：

```bash
cp .env.example .env
```

`.env` 明文方式至少需要設定：

```env
TELEGRAM_API_ID=你的api_id
TELEGRAM_API_HASH=你的api_hash
TELEGRAM_SESSION_STRING=你的session_string
```

建議使用 Keychain，避免把憑證寫進 `.env`。**不要把 session string commit 到 git。**

Keychain 寫入範例：

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

在 shell 中匯出：

```bash
export TELEGRAM_API_ID=$(security find-generic-password -a "$USER" -s telegram-api-id -w)
export TELEGRAM_API_HASH=$(security find-generic-password -a "$USER" -s telegram-api-hash -w)
export TELEGRAM_SESSION_STRING=$(security find-generic-password -a "$USER" -s telegram-session-string -w)
```

---

## 步驟四：啟動 Streamable HTTP server

預設常駐安裝使用 launchd：

```bash
bash scripts/install-launchd.sh
```

這會啟動 Streamable HTTP server：

```text
http://127.0.0.1:8765/mcp
```

如需前景模式除錯，在專案目錄內執行：

```bash
make start
```

`make start` 等同於 `make start-http`，會以前景模式啟動：

```bash
MCP_HOST=127.0.0.1 ./scripts/start.sh --transport http --port 8765
```

前景模式的 Streamable HTTP endpoint 同樣是：

```text
http://127.0.0.1:8765/mcp
```

> 預設只綁定 `127.0.0.1`。不要把未加認證的 MCP endpoint 暴露到公開網路。

---

## 步驟五：切換 MCP client 設定

若你是執行 `bash scripts/setup.sh` 或 `bash scripts/install-launchd.sh`，script 已經把 Claude Code 與 Codex 設為 Streamable HTTP；此步驟只需用 `make config-check` 確認。

使用 Makefile 指令管理 MCP registration：

```bash
# 檢查目前 Claude Code 與 Codex MCP 設定
make config-check

# 兩個 client 都切到 Streamable HTTP
make use-http

# Claude Code 切到 legacy SSE（Codex 不支援 SSE）
make use-sse

# 兩個 client 都切回 stdio
make use-stdio
```

`make use-http` 會設定：

```bash
claude mcp add-json --scope user telegram-mcp '{"type":"http","url":"http://127.0.0.1:8765/mcp","headersHelper":"/path/to/telegram-mcp/scripts/mcp-auth-headers.sh"}'
codex mcp add telegram-mcp --url http://127.0.0.1:8765/mcp --bearer-token-env-var TELEGRAM_MCP_TOKEN
```

Claude Code 用 `headersHelper` 於連線時從 Keychain 讀取 bearer token；Codex 使用 `TELEGRAM_MCP_TOKEN`。安裝腳本會將該 Keychain token 設到使用者 launchd 環境，因此重新啟動後的 Codex 可取得它，不會把 token 寫進設定檔。

`make use-stdio` 會把兩個 client 的 registration 改回由 client 啟動本專案：

```bash
claude mcp add --scope user telegram-mcp -- "/path/to/telegram-mcp/scripts/start.sh" --transport stdio
codex mcp add telegram-mcp -- "/path/to/telegram-mcp/scripts/start.sh" --transport stdio
```

`make use-sse` 只會把 Claude Code 設為 legacy SSE，並使用 `scripts/mcp-auth-headers.sh` 從 Keychain 讀取 bearer token。現有 Codex CLI 原生只支援 Streamable HTTP URL 與 stdio，不能直接設定 SSE；切換 SSE 時 Codex 設定保持不變。

完全結束 Claude Code／Codex（**所有視窗**）後重新開啟即生效。

---

## Makefile 指令

```bash
make list          # 顯示所有指令
make start         # 前景啟動 HTTP mode，同 make start-http
make start-http    # 前景啟動 Streamable HTTP mode
make start-sse     # 前景啟動 legacy SSE mode
make start-stdio   # 前景啟動 stdio mode

make config-check  # 顯示目前 Claude Code 與 Codex MCP 設定
make use-http      # 兩個 client 切到 Streamable HTTP
make use-sse       # Claude Code 切到 legacy SSE；Codex 維持原設定
make use-stdio     # 兩個 client 切回 stdio
```

可覆寫變數：

```bash
make start-http MCP_PORT=9000
make use-http MCP_NAME=telegram-mcp HTTP_URL=http://127.0.0.1:9000/mcp
make use-sse MCP_NAME=telegram-mcp SSE_URL=http://127.0.0.1:9000/sse
```

---

## 從 stdio 升級到 Streamable HTTP 模式

若你之前用 stdio 模式，現在想切換到 Streamable HTTP：

```bash
make start
```

另開一個 terminal：

```bash
make use-http
```

完成後完全結束 Claude Code（所有視窗）再重新開啟。切換前 Claude Code 啟動的 stdio process 不一定會自動回收；若看到舊進程殘留，確認 `make config-check` 已指向 HTTP 後再手動清理。

---

## 伺服器環境設定（.env）

Server 啟動時會載入專案目錄的 `.env`。需要調整以下功能時，在 `.env` 中加入對應的變數（複製 `.env.example` 作為起點）：

```bash
cp .env.example .env
```

修改 `.env` 後需重新啟動 server 才會生效。

HTTP / SSE transport 相關設定：

```bash
MCP_TRANSPORT=http
MCP_HOST=127.0.0.1
MCP_PORT=8765
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
TELEGRAM_DISPLAY_UTC_OFFSET=8
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
>
> 透過 `session_string_generator.py` 產生並存入 Keychain 時，標籤會自動登記到索引項目 `telegram-session-labels`，`scripts/start.sh` 即可據此列出所有帳號（無需掃描整個 Keychain）。**若你手動以 `security add-generic-password` 存入帶標籤的 session（或在此功能之前就已存入），需自行把標籤補進索引**，否則 `start.sh` 不會載入它：
>
> ```bash
> # 例如已有 work / personal 兩個帳號
> security add-generic-password -U -a "$USER" -s telegram-session-labels -w "personal,work"
> ```

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

看到 `telegram`（或你用 `MCP_NAME=...` 指定的名稱）出現且狀態正常即完成。也可以直接問 Claude「幫我查看我的 Telegram 帳號資訊」，Claude 應該能回傳你的帳號名稱。

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

替換後重啟目前執行中的 server（例如停止後重跑 `make start`）。

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

**Q: `make config-check` 顯示尚未 registered？**
A: 代表 Claude user-scope 還沒有這個 MCP server。先確認 HTTP server 已用 `make start` 啟動，再執行 `make use-http`。

**Q: 切換到 HTTP 後 `ps aux | grep telegram-mcp` 仍有多個進程？**
A: 那些通常是切換前 Claude Code 啟動的 stdio process，不一定會自動回收。確認 `make config-check` 已指向 HTTP 後，可手動清理舊 stdio process：

```bash
ps -axo pid,command | awk '$NF == "telegram-mcp" {print $1}' | xargs kill 2>/dev/null
```

確認 Claude MCP config 已切到 HTTP 後再殺，否則 Claude Code 可能會立刻 respawn。

**Q: 某個專案無法看到 telegram-mcp 工具？**
A: 該專案可能在 `~/.claude.json` 的 `projects.<path>.mcpServers` 有獨立 stdio 設定，覆蓋了 user-scope HTTP 設定。檢查：

```bash
python3 -c "
import json
d = json.load(open('$HOME/.claude.json'))
for p, v in d.get('projects', {}).items():
    if 'telegram-mcp' in v.get('mcpServers', {}):
        print(p)
"
```

若發現專案層級覆蓋，手動移除該 project entry，或重新用 `make use-http` 設定 user-scope registration。

---

## 備用：stdio 模式

缺點：同一台機器多個 IDE 同時使用時，各自啟動獨立進程，會因 session 重連互相衝突。

兩種子方式：

| | 方式 A — uvx | 方式 B — start.sh |
| --- | --- | --- |
| 需要 clone 專案 | 否 | 是 |
| 憑證存放 | `.mcp.json` 明文 或 `~/.zshrc` 匯出 | macOS Keychain |
| 適合對象 | 快速試用 | 已完成步驟一至三者 |

### Claude Code（.mcp.json）

#### 方式 A — uvx（無需 clone）

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

#### 方式 B — start.sh（已 clone 專案 + 憑證在 Keychain）

完成步驟一至三後，`scripts/start.sh` 會在執行時自動從 Keychain 讀取憑證，`.mcp.json` 不需要任何 `env` 欄位：

```json
{
  "mcpServers": {
    "telegram-mcp": {
      "command": "/absolute/path/to/telegram-mcp/scripts/start.sh"
    }
  }
}
```

將路徑替換為實際位置（在專案根目錄執行 `pwd` 取得）。

### Claude Desktop

#### 方式 A — uvx

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

#### 方式 B — start.sh（已 clone + Keychain）

```json
{
  "mcpServers": {
    "telegram-mcp": {
      "command": "/absolute/path/to/telegram-mcp/scripts/start.sh"
    }
  }
}
```

**Q: uvx 每次都會重新下載嗎？**
A: 第一次執行時會下載並快取，之後使用快取版本。若需要更新到最新版，執行：

```bash
uvx --from git+https://github.com/chigwell/telegram-mcp.git --reinstall telegram-mcp
```
