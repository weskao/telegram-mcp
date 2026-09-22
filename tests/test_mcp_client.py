import os
import stat
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CLIENT_SCRIPT = ROOT / "scripts" / "mcp-client.sh"


def run_client(*args: str, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        ["bash", str(CLIENT_SCRIPT), *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def source_resolve_token(var: str, extra_env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(extra_env)
    return subprocess.run(
        ["bash", "-c", f'source "{CLIENT_SCRIPT}" && resolve_token "{var}"'],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


@pytest.mark.parametrize(
    "client,variable,follow_up",
    [
        ("claude", "CLAUDE", "make use-http-claude"),
        ("codex", "CODEX", "make use-http-codex"),
        ("grok", "GROK", "make use-http-grok"),
    ],
)
def test_register_missing_cli_is_skipped_with_follow_up(client, variable, follow_up):
    result = run_client("register", client, "http", extra_env={variable: "definitely-missing-mcp-cli"})

    assert result.returncode == 0
    assert "CLI not found" in result.stdout
    assert follow_up in result.stdout
    assert "Registered" not in result.stdout


@pytest.mark.parametrize("client,variable", [("claude", "CLAUDE"), ("codex", "CODEX"), ("grok", "GROK")])
def test_register_failure_is_not_reported_as_success(client, variable):
    result = run_client("register", client, "http", extra_env={variable: "false"})

    assert result.returncode != 0
    assert "Removing existing" in result.stdout
    assert "Registered 'telegram-mcp'" not in result.stdout


def test_resolve_token_prefers_process_env(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    launchctl = fake_bin / "launchctl"
    launchctl.write_text("#!/bin/sh\necho from-launchctl\n")
    launchctl.chmod(launchctl.stat().st_mode | stat.S_IEXEC)

    result = source_resolve_token(
        "TELEGRAM_MCP_TOKEN",
        {
            "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', '')}",
            "TELEGRAM_MCP_TOKEN": "from-env",
        },
    )

    assert result.returncode == 0
    assert result.stdout.strip() == "from-env"


def test_resolve_token_falls_back_to_launchctl(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    launchctl = fake_bin / "launchctl"
    launchctl.write_text('#!/bin/sh\n[ "$1" = getenv ] && echo from-launchctl\n')
    launchctl.chmod(launchctl.stat().st_mode | stat.S_IEXEC)

    result = source_resolve_token(
        "TELEGRAM_MCP_TOKEN",
        {
            "PATH": f"{fake_bin}{os.pathsep}{os.environ.get('PATH', '')}",
            "TELEGRAM_MCP_TOKEN": "",
        },
    )

    assert result.returncode == 0
    assert result.stdout.strip() == "from-launchctl"
