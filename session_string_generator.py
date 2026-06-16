#!/usr/bin/env python3
"""
Telegram Session String Generator

This script generates a session string that can be used for Telegram authentication
with the Telegram MCP server. The session string allows for portable authentication
without storing session files.

Usage:
    python session_string_generator.py
    python session_string_generator.py --qr

Requirements:
    - telethon
    - python-dotenv

Note on ID Formats:
When using the MCP server, please be aware that all `chat_id` and `user_id`
parameters support integer IDs, string representations of IDs (e.g., "123456"),
and usernames (e.g., "@mychannel").
"""

import argparse
import asyncio
import io
import os
import subprocess
import sys

from dotenv import load_dotenv
from telethon import errors
from telethon.sessions import StringSession
from telethon.sync import TelegramClient
from telegram_mcp.install_guard import UnsafeInstallationError, assert_safe_distribution

load_dotenv()


def _store_in_keychain(service: str, value: str) -> bool:
    """Store ``value`` in the macOS login Keychain under ``service``.

    Uses the ``security`` CLI with ``-U`` so an existing item is updated rather
    than duplicated. Returns ``True`` on success; ``False`` if ``security`` is
    unavailable (non-macOS) or the command fails.
    """
    account = os.getenv("USER") or ""
    try:
        subprocess.run(
            ["security", "add-generic-password", "-U",
             "-a", account, "-s", service, "-w", value],
            check=True,
            capture_output=True,
        )
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def _register_session_label(label: str) -> None:
    """Track ``label`` in the ``telegram-session-labels`` Keychain index.

    ``scripts/start.sh`` reads this comma-separated index to enumerate
    multi-account sessions without resorting to ``security dump-keychain``
    (which would expose every keychain item and can trigger access prompts).
    """
    index_service = "telegram-session-labels"
    account = os.getenv("USER") or ""
    label = label.lower()
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-a", account,
             "-s", index_service, "-w"],
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        return
    existing = result.stdout.strip() if result.returncode == 0 else ""
    labels = {part for part in existing.split(",") if part}
    if label in labels:
        return
    labels.add(label)
    _store_in_keychain(index_service, ",".join(sorted(labels)))


def _update_env_file(env_var: str, session_string: str) -> None:
    """Write ``env_var=session_string`` into the local .env file."""
    try:
        try:
            with open(".env", "r") as file:
                env_contents = file.readlines()
        except FileNotFoundError:
            env_contents = []

        for i, line in enumerate(env_contents):
            if line.startswith(f"{env_var}="):
                env_contents[i] = f"{env_var}={session_string}\n"
                break
        else:
            env_contents.append(f"{env_var}={session_string}\n")

        with open(".env", "w") as file:
            file.writelines(env_contents)

        print("\n.env file updated successfully!")
    except Exception as e:
        print(f"\nError updating .env file: {e}")
        print("Please manually add the session string to your .env file.")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a Telegram session string for telegram-mcp."
    )
    login_group = parser.add_mutually_exclusive_group()
    login_group.add_argument(
        "--qr",
        action="store_true",
        help="Use Telegram QR login without prompting for a login method.",
    )
    login_group.add_argument(
        "--phone",
        action="store_true",
        help="Use phone number + verification code login without prompting for a login method.",
    )
    return parser.parse_args()


def _check_installation() -> None:
    try:
        assert_safe_distribution()
    except UnsafeInstallationError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


def _qr_login(client: TelegramClient) -> None:
    import qrcode

    qr = client.qr_login()

    print("\n----- QR Code Login -----\n")

    qr_obj = qrcode.QRCode(border=1)
    qr_obj.add_data(qr.url)
    qr_obj.make(fit=True)
    f = io.StringIO()
    qr_obj.print_ascii(out=f, invert=True)
    print(f.getvalue())

    print("Scan the QR code above with your Telegram app:")
    print("  Open Telegram > Settings > Devices > Link Desktop Device\n")
    print(f"Or open this link on a device where you're logged in:\n  {qr.url}\n")
    print(f"Expires at: {qr.expires.strftime('%H:%M:%S')}")
    print("Waiting for you to scan...")

    try:
        client.loop.run_until_complete(qr.wait(timeout=120))
    except asyncio.TimeoutError:
        print("\nQR code expired. Please try again.")
        client.disconnect()
        sys.exit(1)
    except errors.SessionPasswordNeededError:
        pw = input("\nTwo-factor authentication enabled. Please enter your password: ")
        client.sign_in(password=pw)


def _phone_login(client: TelegramClient) -> None:
    phone = input(
        "Please enter your phone with country code (e.g. +886912345678), "
        "or a bot token: "
    )

    try:
        client.send_code_request(phone)
    except errors.FloodWaitError as e:
        print(f"\nFlood wait error; you must wait {e.seconds} seconds before trying again.")
        client.disconnect()
        sys.exit(1)
    except errors.PhoneNumberInvalidError:
        print("\nThe phone number is invalid.")
        client.disconnect()
        sys.exit(1)
    except Exception as e:
        print(f"\nError sending code: {e}")
        client.disconnect()
        sys.exit(1)

    code = input("\nPlease enter the code you received: ")
    try:
        client.sign_in(phone, code)
    except errors.SessionPasswordNeededError:
        pw = input("Two-factor authentication enabled. Please enter your password: ")
        client.sign_in(password=pw)


def main() -> None:
    args = _parse_args()
    _check_installation()

    API_ID = os.getenv("TELEGRAM_API_ID")
    API_HASH = os.getenv("TELEGRAM_API_HASH")

    if not API_ID or not API_HASH:
        print("Error: TELEGRAM_API_ID and TELEGRAM_API_HASH must be set in .env file")
        print("Create an .env file with your credentials from https://my.telegram.org/apps")
        sys.exit(1)

    try:
        API_ID = int(API_ID)
    except ValueError:
        print("Error: TELEGRAM_API_ID must be an integer")
        sys.exit(1)

    print("\n----- Telegram Session String Generator -----\n")
    print("This script will generate a session string for your Telegram account.")
    print("The generated session string can be added to your .env file.")
    print(
        "\nYour credentials will NOT be stored on any server and are only used for local authentication.\n"
    )

    label = (
        input("Account label (optional, e.g. 'work', 'personal'; leave empty for default): ")
        .strip()
        .lower()
    )

    if args.qr:
        method = "1"
    elif args.phone:
        method = "2"
    else:
        print("\nChoose login method:")
        print("  1) QR code login (recommended -- scan from your Telegram app)")
        print("  2) Phone number + verification code")
        method = input("\nEnter 1 or 2 [default: 1]: ").strip() or "1"

    try:
        client = TelegramClient(StringSession(), API_ID, API_HASH)
        client.connect()

        if not client.is_user_authorized():
            if method == "1":
                _qr_login(client)
            else:
                _phone_login(client)

        session_string = StringSession.save(client.session)

        if label:
            env_var = f"TELEGRAM_SESSION_STRING_{label.upper()}"
            keychain_service = f"telegram-session-string-{label.lower()}"
        else:
            env_var = "TELEGRAM_SESSION_STRING"
            keychain_service = "telegram-session-string"

        print("\nAuthentication successful!")
        print("\n----- Your Session String -----")
        print(f"\n{session_string}\n")
        print("Add this to your .env file as:")
        print(f"{env_var}={session_string}")
        print("\nIMPORTANT: Keep this string private and never share it with anyone!")

        choice = input(
            "\nStore this session string in the macOS Keychain? (y/N): "
        )
        if choice.lower() == "y":
            if _store_in_keychain(keychain_service, session_string):
                if label:
                    _register_session_label(label)
                print(f"\n✅ Stored in Keychain (service: {keychain_service}).")
            else:
                print("\n⚠️  Could not store in Keychain; falling back to .env.")
                _update_env_file(env_var, session_string)
        else:
            _update_env_file(env_var, session_string)

        client.disconnect()

    except Exception as e:
        print(f"\nError: {e}")
        print("Failed to generate session string. Please try again.")
        sys.exit(1)


if __name__ == "__main__":
    main()
