"""Every send tool reports the id of what it just sent."""

from types import SimpleNamespace

import pytest

from telegram_mcp import runtime
from telegram_mcp.tools import media, messages


class _SendingClient:
    """Returns Message-like objects the way Telethon's send_* helpers do."""

    def __init__(self, result):
        self._result = result

    async def send_message(self, entity, message, **kwargs):
        return self._result

    async def send_file(self, entity, file_path, **kwargs):
        return self._result

    async def forward_messages(self, to_entity, ids, from_entity):
        return self._result

    async def get_messages(self, entity, ids=None):
        # Standalone message: no grouped_id, so forward_message skips album expansion.
        return SimpleNamespace(id=ids, grouped_id=None)


def _msg(message_id):
    return SimpleNamespace(id=message_id)


def _patch(monkeypatch, module, client):
    monkeypatch.setattr(module, "get_client", lambda account=None: client)

    async def _resolve_entity(chat_id, cl):
        return f"entity:{chat_id}"

    monkeypatch.setattr(module, "resolve_entity", _resolve_entity)


def test_suffix_shapes():
    assert runtime.sent_ids_suffix(_msg(7)) == " (message_id: 7)"
    assert runtime.sent_ids_suffix([_msg(7), _msg(8)]) == " (message_ids: 7, 8)"
    # No id available must never break the send's own result string.
    assert runtime.sent_ids_suffix(None) == ""
    assert runtime.sent_ids_suffix([]) == ""


def test_updates_message_id_prefers_update_message_id():
    updates = SimpleNamespace(
        updates=[
            SimpleNamespace(message=SimpleNamespace(id=99)),
            runtime.types.UpdateMessageID(id=42, random_id=1),
        ]
    )
    assert runtime.updates_message_id(updates) == 42
    fallback = SimpleNamespace(updates=[SimpleNamespace(message=SimpleNamespace(id=99))])
    assert runtime.updates_message_id(fallback) == 99
    assert runtime.updates_message_id(SimpleNamespace()) is None


@pytest.mark.asyncio
async def test_send_message_reports_id(monkeypatch):
    _patch(monkeypatch, messages, _SendingClient(_msg(101)))
    assert await messages.send_message("chat", "hi") == (
        "Message sent successfully. (message_id: 101)"
    )


@pytest.mark.asyncio
async def test_reply_to_message_reports_new_id(monkeypatch):
    _patch(monkeypatch, messages, _SendingClient(_msg(202)))
    assert await messages.reply_to_message("chat", 5, "hi") == (
        "Replied to message 5 in chat chat. (message_id: 202)"
    )


@pytest.mark.asyncio
async def test_send_file_reports_id(monkeypatch, tmp_path):
    root = (tmp_path / "root").resolve()
    root.mkdir()
    doc = root / "a.png"
    doc.write_bytes(b"png")
    monkeypatch.setattr(runtime, "SERVER_ALLOWED_ROOTS", [root])
    _patch(monkeypatch, media, _SendingClient(_msg(303)))
    result = await media.send_file("chat", str(doc))
    assert result.endswith(" (message_id: 303)")


@pytest.mark.asyncio
async def test_forward_message_reports_copy_id(monkeypatch):
    _patch(monkeypatch, messages, _SendingClient(_msg(404)))
    result = await messages.forward_message("from", 5, "to")
    assert result.endswith(" (message_id: 404)")
