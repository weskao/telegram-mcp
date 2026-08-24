# 🛰️ Telegram MCP Server — 強化版 Fork Project

> Fork of [chigwell/telegram-mcp](https://github.com/chigwell/telegram-mcp)。
> 在原本的 Telegram MCP 伺服器之上，新增**一鍵安裝與常駐 HTTP 服務**、
> **Keychain 優先的 Session 儲存**、**危險工具預設停用的存取控制**、
> **顯示時區預設 UTC+8**，以及一份完整的**繁體中文安裝指南**。
>
> 📖 原作者的完整工具清單與 API 參數說明請見 **[README.upstream.md](README.upstream.md)**。

---

## ⚡ 快速開始

> 📖 **初次設定？請直接照 [SETUP.md](SETUP.md) 逐步操作**，涵蓋 uv 安裝、Telegram API 憑證申請、產生 Session String、環境設定到掛載 Claude 的完整流程。

回訪速查：一鍵安裝並登記到 Claude user scope（所有專案共用）。

```bash
bash scripts/setup.sh
```

服務管理、HTTP／stdio／SSE 切換、多帳號等指令見 **[SETUP.md § Makefile 指令](SETUP.md)**，或執行 `make list`。

---

## ✨ 這個 Fork 多了什麼

相對於上游，本 fork 額外提供：

### 🚀 一鍵安裝與常駐 HTTP 服務

- `bash scripts/setup.sh`：一次安裝、將 bearer token 存入 Keychain，並把 Claude Code 與 Codex 設為連向同一個本機 HTTP server。
- `scripts/install-launchd.sh`：安裝 launchd 服務並開機自啟，讓 HTTP server 常駐。
- launchd 用的 stateless streamable HTTP 傳輸無法向 client 發出 Roots 請求，因此一律 fallback 回 server CLI roots（除非設定 `TELEGRAM_ALLOW_SERVER_ROOTS_FALLBACK=0`），不會等待或逾時。其他傳輸模式下，client 接受了 Roots 請求卻不回應，會在 `TELEGRAM_ROOTS_REQUEST_TIMEOUT_SECONDS`（預設 `10` 秒）後失敗，而非卡住；同樣受上述 opt-in 控制是否 fallback。修改後需重啟服務才會生效。

### 🔐 Keychain 優先的 Session 儲存

- Session String 優先存入系統 Keychain，`.env` 作為 fallback，降低純文字外洩風險。

### 🛡️ 危險工具預設停用的存取控制

- 危險工具（發送、刪除、封鎖等）**預設停用**；用 `TELEGRAM_ENABLE_TOOLS`、`TELEGRAM_EXTRA_UNBLOCKED_TOOLS`、`TELEGRAM_EXTRA_BLOCKED_TOOLS` 精確控制暴露的工具面。
- 細節與衝突規則見 [SETUP.md § 工具存取控制](SETUP.md)。

### 🕒 顯示時區預設 UTC+8

- 時間欄位預設以 UTC+8 呈現，可用 `TELEGRAM_DISPLAY_UTC_OFFSET` 調整。

### 🛠️ 開發者便利工具

- 繁體中文安裝指南 **[SETUP.md](SETUP.md)**。
- Makefile 便利指令：`make start-http`、`make use-http`、`make use-sse`、`make use-stdio`、`make config-check`、`make health`… 執行 `make list` 查看全部。
- SSE bearer 驗證輔助腳本 `scripts/mcp-auth-headers.sh`。

---

## 📂 文件導覽

| 檔案                                     | 內容                                                       |
| ---------------------------------------- | ---------------------------------------------------------- |
| [SETUP.md](SETUP.md)                     | 完整安裝、Session 取得、常駐服務、工具存取控制設定（繁中） |
| [README.upstream.md](README.upstream.md) | 上游原始 README：完整工具清單與 API 參數                   |

---

## 🔄 與上游同步

- 例行更新上游 README 參照：`make sync-upstream-readme`（絕不手動編輯 `README.upstream.md`）。
- 完整合併上游修正／新工具：見 `/sync-upstream` 指令（[.claude/commands/sync-upstream.md](.claude/commands/sync-upstream.md)）。

---

## 🙏 致謝

本專案 fork 自 [chigwell/telegram-mcp](https://github.com/chigwell/telegram-mcp)。
核心 Telegram MCP 工具由原作者（[@chigwell](https://github.com/chigwell)、[@l1v0n1](https://github.com/l1v0n1)）開發；本 fork 著重於部署體驗、Session 維運與工具存取控制。

## 📄 授權

Apache 2.0（與上游一致），見 [LICENSE](LICENSE)。
