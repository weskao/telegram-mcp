"""Regression guards for fork-specific features.

These features were added in this fork (not present upstream) and live in code
regions that upstream also modifies. They exist to catch silent regressions when
merging ``upstream/main``:

- ``TELEGRAM_DISPLAY_UTC_OFFSET`` display-offset formatting (``sanitize.format_date``)
- Tool access-control blocklist (``runtime._apply_tool_disable_list``)
- SSE bearer-token auth (``runtime.BearerTokenMiddleware``)
- Media-label surfacing in message listings (``messages.get_media_label``)
"""

import importlib
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from telegram_mcp import runtime


# ---------------------------------------------------------------------------
# Display-offset formatting (TELEGRAM_DISPLAY_UTC_OFFSET)
# ---------------------------------------------------------------------------


def test_format_date_default_offset_is_utc_plus_8():
    from sanitize import format_date

    dt = datetime(2026, 1, 1, 0, 0, tzinfo=timezone.utc)
    assert format_date(dt) == "2026-01-01T08:00:00+08:00"


def test_format_date_none_returns_unknown():
    from sanitize import format_date

    assert format_date(None) == "unknown"


def test_format_date_honours_configured_offset(monkeypatch):
    """The configured UTC offset must drive conversion, not a hardcoded zone."""
    import sanitize

    monkeypatch.setenv("TELEGRAM_DISPLAY_UTC_OFFSET", "-5")
    reloaded = importlib.reload(sanitize)
    try:
        dt = datetime(2026, 1, 1, 12, 0, tzinfo=timezone.utc)
        assert reloaded.format_date(dt) == "2026-01-01T07:00:00-05:00"
    finally:
        monkeypatch.delenv("TELEGRAM_DISPLAY_UTC_OFFSET", raising=False)
        importlib.reload(sanitize)  # restore module-level default for other tests


# ---------------------------------------------------------------------------
# Tool access-control blocklist
# ---------------------------------------------------------------------------


class _FakeToolManager:
    def __init__(self, known):
        self.known = set(known)
        self.removed = []

    def remove_tool(self, name):
        from mcp.server.fastmcp.exceptions import ToolError

        if name not in self.known:
            raise ToolError(f"unknown tool: {name}")
        self.known.discard(name)
        self.removed.append(name)


class _FakeMCP:
    def __init__(self, known):
        self._tool_manager = _FakeToolManager(known)


def _clear_tool_env(monkeypatch):
    monkeypatch.delenv("TELEGRAM_EXTRA_UNBLOCKED_TOOLS", raising=False)
    monkeypatch.delenv("TELEGRAM_EXTRA_BLOCKED_TOOLS", raising=False)


def test_dangerous_tools_blocked_by_default(monkeypatch):
    _clear_tool_env(monkeypatch)
    fake = _FakeMCP(set(runtime._DANGEROUS_TOOLS) | {"send_message", "get_history"})
    monkeypatch.setattr(runtime, "mcp", fake)

    runtime._apply_tool_disable_list()

    assert set(fake._tool_manager.removed) == set(runtime._DANGEROUS_TOOLS)
    assert "send_message" not in fake._tool_manager.removed
    assert "get_history" not in fake._tool_manager.removed


def test_extra_unblocked_re_enables_specific_tool(monkeypatch):
    _clear_tool_env(monkeypatch)
    monkeypatch.setenv("TELEGRAM_EXTRA_UNBLOCKED_TOOLS", "delete_message")
    fake = _FakeMCP(set(runtime._DANGEROUS_TOOLS))
    monkeypatch.setattr(runtime, "mcp", fake)

    runtime._apply_tool_disable_list()

    assert "delete_message" not in fake._tool_manager.removed
    assert "delete_contact" in fake._tool_manager.removed


def test_extra_blocked_adds_routine_tool(monkeypatch):
    _clear_tool_env(monkeypatch)
    monkeypatch.setenv("TELEGRAM_EXTRA_BLOCKED_TOOLS", "send_message")
    fake = _FakeMCP(set(runtime._DANGEROUS_TOOLS) | {"send_message"})
    monkeypatch.setattr(runtime, "mcp", fake)

    runtime._apply_tool_disable_list()

    assert "send_message" in fake._tool_manager.removed


def test_blocklist_conflict_keeps_tool_disabled(monkeypatch):
    """A tool in BOTH lists stays disabled (block wins over unblock)."""
    _clear_tool_env(monkeypatch)
    monkeypatch.setenv("TELEGRAM_EXTRA_UNBLOCKED_TOOLS", "delete_message")
    monkeypatch.setenv("TELEGRAM_EXTRA_BLOCKED_TOOLS", "delete_message")
    fake = _FakeMCP(set(runtime._DANGEROUS_TOOLS))
    monkeypatch.setattr(runtime, "mcp", fake)

    runtime._apply_tool_disable_list()

    assert "delete_message" in fake._tool_manager.removed


# ---------------------------------------------------------------------------
# SSE bearer-token middleware
# ---------------------------------------------------------------------------


async def _noop_receive():
    return {"type": "http.request"}


@pytest.mark.asyncio
async def test_bearer_middleware_rejects_missing_token():
    app_called = []

    async def app(scope, receive, send):
        app_called.append(True)

    sent = []

    async def send(message):
        sent.append(message)

    mw = runtime.BearerTokenMiddleware(app, "secret")
    await mw({"type": "http", "headers": []}, _noop_receive, send)

    assert app_called == []
    assert sent[0]["status"] == 401


@pytest.mark.asyncio
async def test_bearer_middleware_rejects_wrong_token():
    app_called = []

    async def app(scope, receive, send):
        app_called.append(True)

    sent = []

    async def send(message):
        sent.append(message)

    mw = runtime.BearerTokenMiddleware(app, "secret")
    scope = {"type": "http", "headers": [(b"authorization", b"Bearer wrong")]}
    await mw(scope, _noop_receive, send)

    assert app_called == []
    assert sent[0]["status"] == 401


@pytest.mark.asyncio
async def test_bearer_middleware_accepts_correct_token():
    app_called = []

    async def app(scope, receive, send):
        app_called.append(True)

    async def send(message):
        pass

    mw = runtime.BearerTokenMiddleware(app, "secret")
    scope = {"type": "http", "headers": [(b"authorization", b"Bearer secret")]}
    await mw(scope, _noop_receive, send)

    assert app_called == [True]


@pytest.mark.asyncio
async def test_bearer_middleware_passes_through_non_http_scope():
    seen = []

    async def app(scope, receive, send):
        seen.append(scope["type"])

    mw = runtime.BearerTokenMiddleware(app, "secret")
    await mw({"type": "lifespan"}, _noop_receive, lambda m: None)

    assert seen == ["lifespan"]


# ---------------------------------------------------------------------------
# Media-label surfacing in message listings
# ---------------------------------------------------------------------------


def _media_msg(**overrides):
    """Message stub with every media attribute defaulted to None/falsey."""
    base = dict(
        sticker=None,
        photo=None,
        voice=None,
        video_note=None,
        video=None,
        audio=None,
        gif=None,
        document=None,
        contact=None,
        geo=None,
        poll=None,
        web_preview=None,
        media=None,
        file=None,
    )
    base.update(overrides)
    return SimpleNamespace(**base)


def test_media_label_plain_message_is_empty():
    from telegram_mcp.tools.messages import get_media_label

    assert get_media_label(_media_msg()) == ""


def test_media_label_photo():
    from telegram_mcp.tools.messages import get_media_label

    assert get_media_label(_media_msg(photo=object())) == "photo"


def test_media_label_voice():
    from telegram_mcp.tools.messages import get_media_label

    assert get_media_label(_media_msg(voice=object())) == "voice"


def test_media_label_poll():
    from telegram_mcp.tools.messages import get_media_label

    assert get_media_label(_media_msg(poll=object())) == "poll"


def test_media_label_document_with_filename():
    from telegram_mcp.tools.messages import get_media_label

    msg = _media_msg(document=object(), file=SimpleNamespace(name="report.pdf"))
    assert get_media_label(msg) == "document: report.pdf"


def test_media_label_document_without_filename():
    from telegram_mcp.tools.messages import get_media_label

    assert get_media_label(_media_msg(document=object())) == "document"


def test_media_label_sticker_includes_alt():
    from telegram_mcp.tools.messages import get_media_label

    sticker = SimpleNamespace(attributes=[SimpleNamespace(alt="😀")])
    assert get_media_label(_media_msg(sticker=sticker)) == "sticker 😀"
