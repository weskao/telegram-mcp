import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def run_make(target: str, **variables: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["make", target, *(f"{key}={value}" for key, value in variables.items())],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize(
    "target,variable,follow_up",
    [
        ("use-http-claude", "CLAUDE", "make use-http-claude"),
        ("use-http-codex", "CODEX", "make use-http-codex"),
        ("use-sse-claude", "CLAUDE", "make use-sse-claude"),
        ("use-stdio-claude", "CLAUDE", "make use-stdio-claude"),
        ("use-stdio-codex", "CODEX", "make use-stdio-codex"),
    ],
)
def test_missing_client_is_skipped_with_follow_up(target, variable, follow_up):
    result = run_make(target, **{variable: "definitely-missing-mcp-cli"})

    assert result.returncode == 0
    assert "CLI not found" in result.stdout
    assert follow_up in result.stdout


@pytest.mark.parametrize(
    "target,variable",
    [
        ("use-http-claude", "CLAUDE"),
        ("use-http-codex", "CODEX"),
        ("use-sse-claude", "CLAUDE"),
        ("use-stdio-claude", "CLAUDE"),
        ("use-stdio-codex", "CODEX"),
    ],
)
def test_client_registration_failure_is_not_reported_as_success(target, variable):
    result = run_make(target, **{variable: "false"})

    assert result.returncode != 0
    assert "Registered 'telegram-mcp'" not in result.stdout


@pytest.mark.parametrize(
    "claude,codex,registered,skipped",
    [
        ("true", "definitely-missing-codex", "Claude", "Codex"),
        ("definitely-missing-claude", "true", "Codex", "Claude"),
    ],
)
def test_http_clients_are_handled_independently(claude, codex, registered, skipped):
    result = run_make("use-http", CLAUDE=claude, CODEX=codex)

    assert result.returncode == 0
    assert f"Registered 'telegram-mcp' for {registered}" in result.stdout
    assert f"{skipped} CLI not found" in result.stdout
