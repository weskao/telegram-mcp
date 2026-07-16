# Makefile - local development and Claude MCP convenience commands.

.DEFAULT_GOAL := list

PROJECT_ROOT := $(CURDIR)
START_SCRIPT := $(PROJECT_ROOT)/scripts/start.sh
HEADERS_HELPER := $(PROJECT_ROOT)/scripts/mcp-auth-headers.sh
MCP_NAME ?= telegram
MCP_HOST ?= 127.0.0.1
MCP_PORT ?= 8765
HTTP_URL ?= http://$(MCP_HOST):$(MCP_PORT)/mcp
SSE_URL ?= http://$(MCP_HOST):$(MCP_PORT)/sse
CLAUDE ?= claude
UV ?= uv

.PHONY: list help start start-http start-sse start-stdio config-check use-http use-sse use-stdio

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

config-check: ## Show current Claude user-scope MCP config for telegram
	@$(CLAUDE) mcp get $(MCP_NAME) || echo "($(MCP_NAME) not yet registered with Claude)"

use-http: ## Switch Claude MCP config to Streamable HTTP
	@echo "Removing existing '$(MCP_NAME)' MCP registration (if any)..."
	@$(CLAUDE) mcp remove --scope user $(MCP_NAME) >/dev/null 2>&1 || true
	@echo "Registering '$(MCP_NAME)' via Streamable HTTP at $(HTTP_URL) ..."
	$(CLAUDE) mcp add --transport http --scope user $(MCP_NAME) $(HTTP_URL)
	@echo ""
	@echo "Registered '$(MCP_NAME)' as Streamable HTTP. Restart Claude Code to apply the change."

use-sse: ## Switch Claude MCP config to legacy SSE
	@echo "Removing existing '$(MCP_NAME)' MCP registration (if any)..."
	@$(CLAUDE) mcp remove --scope user $(MCP_NAME) >/dev/null 2>&1 || true
	@echo "Registering '$(MCP_NAME)' via legacy SSE at $(SSE_URL) ..."
	@MCP_NAME="$(MCP_NAME)" SSE_URL="$(SSE_URL)" HEADERS_HELPER="$(HEADERS_HELPER)" python3 -c 'import json, os, pathlib; path = pathlib.Path.home() / ".claude.json"; data = json.loads(path.read_text()) if path.exists() else {}; servers = data.setdefault("mcpServers", {}); servers[os.environ["MCP_NAME"]] = {"type": "sse", "url": os.environ["SSE_URL"], "headersHelper": os.environ["HEADERS_HELPER"]}; path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")'
	@echo ""
	@echo "Registered '$(MCP_NAME)' as legacy SSE. Restart Claude Code to apply the change."

use-stdio: ## Switch Claude MCP config back to stdio
	@echo "Removing existing '$(MCP_NAME)' MCP registration (if any)..."
	@$(CLAUDE) mcp remove --scope user $(MCP_NAME) >/dev/null 2>&1 || true
	@echo "Registering '$(MCP_NAME)' via stdio from $(PROJECT_ROOT) ..."
	$(CLAUDE) mcp add --scope user $(MCP_NAME) -- "$(START_SCRIPT)" --transport stdio
	@echo ""
	@echo "Registered '$(MCP_NAME)' as stdio. Restart Claude Code to apply the change."
