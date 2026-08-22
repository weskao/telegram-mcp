# Makefile - local development and MCP client convenience commands.

.DEFAULT_GOAL := list

PROJECT_ROOT := $(CURDIR)
START_SCRIPT := $(PROJECT_ROOT)/scripts/start.sh
HEADERS_HELPER := $(PROJECT_ROOT)/scripts/mcp-auth-headers.sh
MCP_NAME ?= telegram-mcp
MCP_HOST ?= 127.0.0.1
MCP_PORT ?= 8765
HTTP_URL ?= http://$(MCP_HOST):$(MCP_PORT)/mcp
SSE_URL ?= http://$(MCP_HOST):$(MCP_PORT)/sse
CLAUDE ?= claude
CODEX ?= codex
CODEX_BEARER_ENV ?= TELEGRAM_MCP_TOKEN
UV ?= uv

.PHONY: list help start start-http start-sse start-stdio config-check config-check-claude config-check-codex use-http use-http-claude use-http-codex use-sse use-sse-claude use-stdio use-stdio-claude use-stdio-codex sync-upstream-readme

list:
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-24s\033[0m %s\n", "make " $$1, $$2}'
	@echo ""

help: list ## Same as list; show available commands

start: start-http ## Run HTTP mode in foreground

start-http: ## Run Streamable HTTP mode in foreground at http://127.0.0.1:8765/mcp
	MCP_HOST=$(MCP_HOST) "$(START_SCRIPT)" --transport http --port $(MCP_PORT)

start-sse: ## Run legacy SSE mode in foreground at http://127.0.0.1:8765/sse
	MCP_HOST=$(MCP_HOST) "$(START_SCRIPT)" --transport sse --port $(MCP_PORT)

start-stdio: ## Run stdio mode in foreground
	"$(START_SCRIPT)" --transport stdio

config-check: config-check-claude config-check-codex ## Show current Claude and Codex MCP config for telegram

config-check-claude: ## Show current Claude user-scope MCP config
	@if command -v "$(CLAUDE)" >/dev/null 2>&1; then $(CLAUDE) mcp get $(MCP_NAME) || echo "($(MCP_NAME) not yet registered with Claude)"; else echo "Claude CLI not found — Claude is not configured. After installing it, run 'make use-http-claude'."; fi

config-check-codex: ## Show current Codex MCP config
	@if command -v "$(CODEX)" >/dev/null 2>&1; then $(CODEX) mcp get $(MCP_NAME) || echo "($(MCP_NAME) not yet registered with Codex)"; else echo "Codex CLI not found — Codex is not configured. After installing it, run 'make use-http-codex'."; fi

use-http: use-http-claude use-http-codex ## Switch Claude and Codex MCP config to Streamable HTTP
	@echo "Finished configuring installed MCP clients for Streamable HTTP. Missing CLIs were skipped."

use-http-claude: ## Switch Claude MCP config to authenticated Streamable HTTP
	@if ! command -v "$(CLAUDE)" >/dev/null 2>&1; then echo "Claude CLI not found — skipping Claude registration."; echo "After installing Claude Code, run 'make use-http-claude'."; exit 0; fi; \
	set -e; \
	echo "Removing existing '$(MCP_NAME)' Claude MCP registration (if any)..."; \
	$(CLAUDE) mcp remove --scope user $(MCP_NAME) >/dev/null 2>&1 || true; \
	echo "Registering '$(MCP_NAME)' via Streamable HTTP at $(HTTP_URL) ..."; \
	$(CLAUDE) mcp add-json --scope user $(MCP_NAME) '{"type":"http","url":"$(HTTP_URL)","headersHelper":"$(HEADERS_HELPER)"}'; \
	echo ""; \
	echo "Registered '$(MCP_NAME)' for Claude. Restart Claude Code to apply the change."

use-http-codex: ## Switch Codex MCP config to authenticated Streamable HTTP
	@if ! command -v "$(CODEX)" >/dev/null 2>&1; then echo "Codex CLI not found — skipping Codex registration."; echo "After installing Codex, run 'make use-http-codex'."; exit 0; fi; \
	set -e; \
	echo "Removing existing '$(MCP_NAME)' Codex MCP registration (if any)..."; \
	$(CODEX) mcp remove $(MCP_NAME) >/dev/null 2>&1 || true; \
	echo "Registering '$(MCP_NAME)' via Streamable HTTP at $(HTTP_URL) ..."; \
	$(CODEX) mcp add $(MCP_NAME) --url "$(HTTP_URL)" --bearer-token-env-var "$(CODEX_BEARER_ENV)"; \
	echo ""; \
	echo "Registered '$(MCP_NAME)' for Codex. Restart Codex after the launchd service is running."

use-sse: use-sse-claude ## Switch Claude MCP config to legacy SSE (Codex does not support SSE)
	@echo "Codex supports Streamable HTTP and stdio, not legacy SSE; its configuration was not changed."

use-sse-claude: ## Switch Claude MCP config to authenticated legacy SSE
	@if ! command -v "$(CLAUDE)" >/dev/null 2>&1; then echo "Claude CLI not found — skipping Claude registration."; echo "After installing Claude Code, run 'make use-sse-claude'."; exit 0; fi; \
	set -e; \
	echo "Removing existing '$(MCP_NAME)' Claude MCP registration (if any)..."; \
	$(CLAUDE) mcp remove --scope user $(MCP_NAME) >/dev/null 2>&1 || true; \
	echo "Registering '$(MCP_NAME)' via legacy SSE at $(SSE_URL) ..."; \
	$(CLAUDE) mcp add-json --scope user $(MCP_NAME) '{"type":"sse","url":"$(SSE_URL)","headersHelper":"$(HEADERS_HELPER)"}'; \
	echo ""; \
	echo "Registered '$(MCP_NAME)' as legacy SSE for Claude. Restart Claude Code to apply the change."

use-stdio: use-stdio-claude use-stdio-codex ## Switch Claude and Codex MCP config to stdio
	@echo "Finished configuring installed MCP clients for stdio. Missing CLIs were skipped."

use-stdio-claude: ## Switch Claude MCP config back to stdio
	@if ! command -v "$(CLAUDE)" >/dev/null 2>&1; then echo "Claude CLI not found — skipping Claude registration."; echo "After installing Claude Code, run 'make use-stdio-claude'."; exit 0; fi; \
	set -e; \
	echo "Removing existing '$(MCP_NAME)' Claude MCP registration (if any)..."; \
	$(CLAUDE) mcp remove --scope user $(MCP_NAME) >/dev/null 2>&1 || true; \
	echo "Registering '$(MCP_NAME)' via stdio from $(PROJECT_ROOT) ..."; \
	$(CLAUDE) mcp add --scope user $(MCP_NAME) -- "$(START_SCRIPT)" --transport stdio; \
	echo ""; \
	echo "Registered '$(MCP_NAME)' as stdio for Claude. Restart Claude Code to apply the change."

use-stdio-codex: ## Switch Codex MCP config back to stdio
	@if ! command -v "$(CODEX)" >/dev/null 2>&1; then echo "Codex CLI not found — skipping Codex registration."; echo "After installing Codex, run 'make use-stdio-codex'."; exit 0; fi; \
	set -e; \
	echo "Removing existing '$(MCP_NAME)' Codex MCP registration (if any)..."; \
	$(CODEX) mcp remove $(MCP_NAME) >/dev/null 2>&1 || true; \
	echo "Registering '$(MCP_NAME)' via stdio from $(PROJECT_ROOT) ..."; \
	$(CODEX) mcp add $(MCP_NAME) -- "$(START_SCRIPT)" --transport stdio; \
	echo ""; \
	echo "Registered '$(MCP_NAME)' as stdio. Restart Codex to apply the change."

sync-upstream-readme: ## Refresh README.upstream.md from upstream/main (never edit it by hand)
	@git remote get-url upstream >/dev/null 2>&1 || { echo "No 'upstream' remote. Add it: git remote add upstream https://github.com/chigwell/telegram-mcp.git"; exit 1; }
	@echo "Fetching upstream..."
	@git fetch upstream
	@git show upstream/main:README.md > README.upstream.md
	@echo "README.upstream.md updated from upstream/main"
