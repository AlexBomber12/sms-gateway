#!/usr/bin/env python3
"""Handle incoming SMS and forward them to Telegram."""
import html
import logging
import os
import re
import sys
import time
from typing import Iterable, Tuple

import requests

import sms_queue


def get_env(name: str, required: bool = True, default: str | None = None) -> str:
    """Get environment variable and optionally require it."""
    value = os.getenv(name, default)
    if required and not value:
        raise EnvironmentError(f"Environment variable {name} is not set")
    return value or ""


def parse_sms(parts: int, getenv=os.getenv) -> Tuple[str, str]:
    """Assemble multipart SMS from environment variables."""
    number = getenv("SMS_1_NUMBER", "unknown").strip()
    messages: Iterable[str] = []
    collected: list[str] = []
    for i in range(1, parts + 1):
        text = getenv(f"SMS_{i}_TEXT")
        if text is not None:
            collected.append(text.rstrip())
    messages = collected
    if not messages:
        messages = ["(empty)"]
    text = "\n".join(messages).lstrip()
    text = re.sub(r"\n(?!\n)", " ", text)
    text = re.sub(r" {2,}", " ", text)
    if not text:
        text = "(empty)"
    return number, text[:4096]


def build_telegram_payload(chat_id: str, number: str, text: str) -> dict[str, str]:
    """Build Telegram payload for the SMS message."""
    return {
        "chat_id": chat_id,
        "text": f"<b>{html.escape(number)}</b>\n{html.escape(text)}",
        "parse_mode": "HTML",
    }


def send_to_telegram(bot_token: str, chat_id: str, number: str, text: str) -> None:
    """Send assembled SMS to Telegram."""
    payload = build_telegram_payload(chat_id, number, text)
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    for attempt in range(120):
        try:
            requests.post(url, json=payload, timeout=10).raise_for_status()
            logging.info("Sent SMS from %s to Telegram", number)
            return
        except Exception as exc:  # pragma: no cover - network failure is ignored in tests
            logging.warning("Send failed (attempt %s): %s", attempt + 1, exc)
            time.sleep(30)
    logging.error("Failed to send SMS after retries")
    raise SystemExit(1)


def normalize_delivery_mode(value: str | None) -> str:
    mode = (value or "direct").strip().lower()
    if mode == "queue":
        return "queue"
    if mode != "direct":
        logging.warning("Unknown DELIVERY_MODE=%r; defaulting to direct", value)
    return "direct"


def enqueue_sms(number: str, text: str) -> None:
    base_dir = sms_queue.resolve_queue_dir()
    path = sms_queue.enqueue_message(number, text, base_dir)
    logging.info("Enqueued SMS from %s to %s", number, path)


def main(argv: list[str] | None = None) -> None:
    logging.basicConfig(level=os.getenv("LOGLEVEL", "INFO"))
    argv = sys.argv[1:] if argv is None else argv
    try:
        parts = int(os.getenv("SMS_MESSAGES", "1"))
    except Exception as exc:
        logging.error("%s", exc)
        sys.exit(1)

    number, text = parse_sms(parts)
    delivery_mode = "queue" if "--enqueue" in argv else normalize_delivery_mode(os.getenv("DELIVERY_MODE"))
    if delivery_mode == "queue":
        enqueue_sms(number, text)
        return

    try:
        bot = get_env("TELEGRAM_BOT_TOKEN")
        chat = get_env("TELEGRAM_CHAT_ID")
    except Exception as exc:
        logging.error("%s", exc)
        sys.exit(1)

    send_to_telegram(bot, chat, number, text)


if __name__ == "__main__":  # pragma: no cover
    main()
