import pytest

from telegram_mcp import runner


class _FakeClient:
    def __init__(self, *, authorized: bool):
        self.authorized = authorized
        self.connected = False
        self.started = False

    async def connect(self):
        self.connected = True

    async def is_user_authorized(self):
        return self.authorized

    async def start(self):
        self.started = True


@pytest.mark.asyncio
async def test_connect_authorized_client_uses_existing_session_without_interactive_start():
    client = _FakeClient(authorized=True)

    await runner._connect_authorized_client("default", client)

    assert client.connected is True
    assert client.started is False


@pytest.mark.asyncio
async def test_connect_authorized_client_rejects_unauthorized_session():
    client = _FakeClient(authorized=False)

    with pytest.raises(RuntimeError, match="Interactive phone login is disabled"):
        await runner._connect_authorized_client("default", client)

    assert client.connected is True
    assert client.started is False


class _FakeMcp:
    def __init__(self):
        self.ran = None

    async def run_stdio_async(self):
        self.ran = "stdio"

    def sse_app(self):
        return "sse-app"

    def streamable_http_app(self):
        return "http-app"


def _patch_uvicorn(monkeypatch, captured):
    import uvicorn

    class _FakeConfig:
        def __init__(self, app, host=None, port=None, log_level=None):
            captured["app"] = app
            captured["host"] = host
            captured["port"] = port

    class _FakeServer:
        def __init__(self, config):
            pass

        async def serve(self):
            captured["served"] = True

    monkeypatch.setattr(uvicorn, "Config", _FakeConfig)
    monkeypatch.setattr(uvicorn, "Server", _FakeServer)


@pytest.mark.asyncio
@pytest.mark.parametrize("transport", ["stdio", "unknown"])
async def test_serve_defaults_to_stdio(monkeypatch, transport):
    fake = _FakeMcp()
    monkeypatch.setattr(runner, "mcp", fake)

    await runner._serve(transport)

    assert fake.ran == "stdio"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "transport,expected_app", [("http", "http-app"), ("sse", "sse-app")]
)
async def test_serve_http_transports_bind_host_and_port_with_auth(
    monkeypatch, transport, expected_app
):
    fake = _FakeMcp()
    monkeypatch.setattr(runner, "mcp", fake)
    monkeypatch.setenv("MCP_HOST", "0.0.0.0")
    monkeypatch.setenv("TELEGRAM_MCP_TOKEN", "sekret")
    monkeypatch.setattr(runner.runtime, "_sse_port", 9000)

    captured = {}
    _patch_uvicorn(monkeypatch, captured)

    await runner._serve(transport)

    assert captured["served"] is True
    assert captured["host"] == "0.0.0.0"
    assert captured["port"] == 9000
    # Token set -> the right base app is wrapped in the bearer-auth middleware.
    assert isinstance(captured["app"], runner.BearerTokenMiddleware)
    assert captured["app"].app == expected_app


@pytest.mark.asyncio
async def test_serve_http_defaults_localhost_and_warns_without_token(monkeypatch, capsys):
    fake = _FakeMcp()
    monkeypatch.setattr(runner, "mcp", fake)
    monkeypatch.delenv("MCP_HOST", raising=False)
    monkeypatch.delenv("TELEGRAM_MCP_TOKEN", raising=False)
    monkeypatch.setattr(runner.runtime, "_sse_port", 8765)

    captured = {}
    _patch_uvicorn(monkeypatch, captured)

    await runner._serve("http")

    assert captured["served"] is True
    assert captured["host"] == "127.0.0.1"
    assert captured["port"] == 8765
    # No token -> unwrapped app plus a warning on stderr.
    assert captured["app"] == "http-app"
    assert "without auth" in capsys.readouterr().err
