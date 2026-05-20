# Telegram MCP Server — Claude Code Setup

The repository is cloned and dependencies are installed. One manual step remains:
registering the MCP server with Claude Code requires writing to a config file that
Claude Code's auto mode classifier hard-blocks for safety (self-modification protection).

This setup registers the server **globally** (`~/.claude.json`) using `scripts/start.sh`,
which loads credentials from the macOS Keychain at runtime — no plaintext secrets in any
config file.

---

## Step 1 — Store credentials in Keychain (one-time)

Run this once from any terminal:

```bash
security add-generic-password -a "$USER" -s telegram-api-id        -w "YOUR_API_ID"
security add-generic-password -a "$USER" -s telegram-api-hash       -w "YOUR_API_HASH"
security add-generic-password -a "$USER" -s telegram-session-string -w "YOUR_SESSION_STRING"
```

Get `API_ID` and `API_HASH` from <https://my.telegram.org/apps>.
For `SESSION_STRING`, see [Step 2](#step-2--generate-a-session-string-first-time-only).

---

## Step 2 — Generate a session string (first-time only)

Run from the repo root:

```bash
uv run session_string_generator.py
```

Follow the prompts (phone number + Telegram verification code).
Copy the printed session string and store it in Keychain as shown in Step 1.

---

## Step 3 — Register the global MCP server

Run from the repo root:

```bash
claude mcp add --scope user telegram-mcp "$(pwd)/scripts/start.sh"
```

This writes an entry to `~/.claude.json` pointing to `start.sh`.
Because `start.sh` reads credentials from Keychain, no `env` block is needed.

To verify the entry was added:

```bash
claude mcp list
```

---

## Alternatively — edit `~/.claude.json` directly

If you prefer to edit the file by hand, add this entry under `mcpServers`:

```json
{
  "mcpServers": {
    "telegram-mcp": {
      "command": "/absolute/path/to/telegram-mcp/scripts/start.sh"
    }
  }
}
```

Replace `/absolute/path/to/telegram-mcp` with the actual path to the repo
(run `pwd` from the repo root to get it).

---

## After registering

Restart Claude Code — `telegram-mcp` should appear in `claude mcp list` with status `connected`.
