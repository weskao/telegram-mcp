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
        ("use-http-grok", "GROK", "make use-http-grok"),
        ("use-sse-claude", "CLAUDE", "make use-sse-claude"),
        ("use-stdio-claude", "CLAUDE", "make use-stdio-claude"),
        ("use-stdio-codex", "CODEX", "make use-stdio-codex"),
        ("use-stdio-grok", "GROK", "make use-stdio-grok"),
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
        ("use-http-grok", "GROK"),
        ("use-sse-claude", "CLAUDE"),
        ("use-stdio-claude", "CLAUDE"),
        ("use-stdio-codex", "CODEX"),
        ("use-stdio-grok", "GROK"),
    ],
)
def test_client_registration_failure_is_not_reported_as_success(target, variable):
    result = run_make(target, **{variable: "false"})

    assert result.returncode != 0
    assert "Registered 'telegram-mcp'" not in result.stdout


@pytest.mark.parametrize(
    "variables,registered,skipped",
    [
        (
            {
                "CLAUDE": "true",
                "CODEX": "definitely-missing-codex",
                "GROK": "definitely-missing-grok",
            },
            "Claude",
            ["Codex", "Grok"],
        ),
        (
            {
                "CLAUDE": "definitely-missing-claude",
                "CODEX": "true",
                "GROK": "definitely-missing-grok",
            },
            "Codex",
            ["Claude", "Grok"],
        ),
        (
            {
                "CLAUDE": "definitely-missing-claude",
                "CODEX": "definitely-missing-codex",
                "GROK": "true",
            },
            "Grok",
            ["Claude", "Codex"],
        ),
    ],
)
def test_http_clients_are_handled_independently(variables, registered, skipped):
    result = run_make("use-http", **variables)

    assert result.returncode == 0
    assert f"Registered 'telegram-mcp' for {registered}" in result.stdout
    for name in skipped:
        assert f"{name} CLI not found" in result.stdout


def test_health_skips_missing_grok_cli():
    result = run_make("health", GROK="definitely-missing-grok")

    assert "grok CLI not found" in result.stdout
