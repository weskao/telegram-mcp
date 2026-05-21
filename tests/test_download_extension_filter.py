"""Tests for _check_download_extension safety filter in tools/media.py."""

from pathlib import Path

import pytest

import main  # noqa: F401  ensures telegram_mcp.runtime loaded
from telegram_mcp.tools.media import _check_download_extension


@pytest.mark.parametrize(
    "name",
    [
        "photo.jpg",
        "photo.jpeg",
        "PHOTO.JPG",  # uppercase
        "graphic.PNG",
        "sticker.webp",
        "snap.heic",
        "snap.heif",
        "meme.gif",
        "clip.mp4",
        "clip.MOV",
        "anim.webm",
        "voice.ogg",
        "track.mp3",
        "audio.m4a",
        "report.pdf",
        "notes.txt",
        "spec.md",
        "data.csv",
        "doc.docx",
        "sheet.xlsx",
        "deck.pptx",
    ],
)
def test_allowed_extensions_pass(name):
    assert _check_download_extension(Path(f"/tmp/{name}")) is None


@pytest.mark.parametrize(
    "name",
    [
        "malware.exe",
        "installer.msi",
        "script.sh",
        "trojan.bat",
        "evil.ps1",
        "bad.vbs",
        "loader.scr",
        "click.lnk",
        "mount.iso",
        "macro.docm",
        "macro.xlsm",
        "embed.svg",
        "page.html",
        "config.xml",
        "archive.zip",
        "bundle.rar",
        "code.py",
        "applet.jar",
    ],
)
def test_blocked_extensions_rejected(name):
    err = _check_download_extension(Path(f"/tmp/{name}"))
    assert err is not None
    assert "blocklist" in err or "double-extension" in err


@pytest.mark.parametrize(
    "name",
    [
        "weird.xyz",
        "old.aac",  # not on either list — defaults to reject
        "audio.flac",
        "video.mkv",
        "image.bmp",
    ],
)
def test_unknown_extensions_rejected(name):
    err = _check_download_extension(Path(f"/tmp/{name}"))
    assert err is not None
    assert "allowlist" in err


def test_no_extension_rejected():
    err = _check_download_extension(Path("/tmp/no_extension"))
    assert err is not None
    assert "no extension" in err.lower()


@pytest.mark.parametrize(
    "name",
    [
        "report.pdf.exe",
        "photo.jpg.scr",
        "invoice.docx.bat",
    ],
)
def test_double_extension_detected(name):
    err = _check_download_extension(Path(f"/tmp/{name}"))
    assert err is not None
    assert "double-extension" in err


def test_safe_double_dot_still_passes():
    # benign multi-dot names where the *real* trailing extension is allowed
    assert _check_download_extension(Path("/tmp/my.photo.jpg")) is None


def test_parse_ext_env_uses_default_when_unset(monkeypatch):
    from telegram_mcp.tools import media

    monkeypatch.delenv("TELEGRAM_DOWNLOAD_ALLOWED_EXT", raising=False)
    parsed = media._parse_ext_env(
        "TELEGRAM_DOWNLOAD_ALLOWED_EXT", media._DEFAULT_DOWNLOAD_ALLOWED_EXT
    )
    assert parsed == media._DEFAULT_DOWNLOAD_ALLOWED_EXT


def test_parse_ext_env_overrides(monkeypatch):
    from telegram_mcp.tools import media

    monkeypatch.setenv("TELEGRAM_DOWNLOAD_ALLOWED_EXT", "jpg, .PNG,webp,")
    parsed = media._parse_ext_env(
        "TELEGRAM_DOWNLOAD_ALLOWED_EXT", media._DEFAULT_DOWNLOAD_ALLOWED_EXT
    )
    assert parsed == frozenset({"jpg", "png", "webp"})


def test_parse_ext_env_empty_string_falls_back(monkeypatch):
    from telegram_mcp.tools import media

    monkeypatch.setenv("TELEGRAM_DOWNLOAD_ALLOWED_EXT", "   ")
    parsed = media._parse_ext_env(
        "TELEGRAM_DOWNLOAD_ALLOWED_EXT", media._DEFAULT_DOWNLOAD_ALLOWED_EXT
    )
    assert parsed == media._DEFAULT_DOWNLOAD_ALLOWED_EXT
