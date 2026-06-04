"""Application entrypoints for the Telegram MCP server."""

import os

from telegram_mcp.install_guard import UnsafeInstallationError, assert_safe_distribution

try:
    assert_safe_distribution()
except UnsafeInstallationError as exc:
    raise SystemExit(str(exc)) from None

from telegram_mcp import runtime
from telegram_mcp.runtime import *
import telegram_mcp.tools  # noqa: F401 - registers MCP tools via decorators


async def _connect_authorized_client(label, client) -> None:
    await client.connect()
    if await client.is_user_authorized():
        return

    raise RuntimeError(
        f"Telegram client '{label}' is not authorized. Interactive phone login "
        "is disabled for the MCP server because it runs over stdio. Generate a "
        "session string with `uv run session_string_generator.py`, then set "
        "TELEGRAM_SESSION_STRING or TELEGRAM_SESSION_STRING_<LABEL> in .env. "
        "For existing file sessions, run the login outside the MCP server first."
    )


async def _main() -> None:
    try:
        labels = ", ".join(clients.keys())
        print(f"Starting {len(clients)} Telegram client(s) ({labels})...", file=sys.stderr)
        await asyncio.gather(
            *(_connect_authorized_client(label, cl) for label, cl in clients.items())
        )

        # Warm entity caches — StringSession has no persistent cache,
        # so fetch all dialogs once per client to populate them
        print("Warming entity caches...", file=sys.stderr)
        await asyncio.gather(*(cl.get_dialogs() for cl in clients.values()))

        print(f"Telegram client(s) started ({labels}). Running MCP server...", file=sys.stderr)
        if runtime._transport == "sse":
            token = os.getenv("TELEGRAM_MCP_TOKEN", "")
            if not token:
                print(
                    "[telegram-mcp] WARNING: TELEGRAM_MCP_TOKEN not set — SSE running without auth",
                    file=sys.stderr,
                )
            import uvicorn

            app = mcp.sse_app()
            if token:
                app = BearerTokenMiddleware(app, token)
            config = uvicorn.Config(app, host="127.0.0.1", port=runtime._sse_port, log_level="warning")
            server = uvicorn.Server(config)
            await server.serve()
        else:
            await mcp.run_stdio_async()
    except Exception as e:
        print(f"Error starting client: {e}", file=sys.stderr)
        if isinstance(e, sqlite3.OperationalError) and "database is locked" in str(e):
            print(
                "Database lock detected. Please ensure no other instances are running.",
                file=sys.stderr,
            )
        sys.exit(1)
    finally:
        try:
            await asyncio.gather(
                *(cl.disconnect() for cl in clients.values()), return_exceptions=True
            )
        except Exception:
            pass


def main() -> None:
    _configure_allowed_roots_from_cli(sys.argv[1:])
    # Fork blocklist (default dangerous-tool removal) AND upstream read-only
    # exposure mode are complementary — apply both before serving.
    _apply_tool_disable_list()
    _apply_exposed_tools_mode()
    # nest_asyncio is only needed for the stdio path's nested asyncio.run; the
    # SSE path runs under uvicorn's own event loop and must not be patched.
    if runtime._transport == "stdio":
        nest_asyncio.apply()
    asyncio.run(_main())


if __name__ == "__main__":
    main()
