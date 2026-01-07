#!/usr/bin/env python3
"""Worker that delivers queued SMS messages to Telegram."""
from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Dict

import requests

import sms_queue
from on_receive import build_telegram_payload, get_env


def _get_int_env(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        logging.warning("Invalid %s=%r; using %s", name, value, default)
        return default


def _get_float_env(name: str, default: float) -> float:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return float(value)
    except ValueError:
        logging.warning("Invalid %s=%r; using %s", name, value, default)
        return default


def send_with_retries(
    bot_token: str,
    chat_id: str,
    number: str,
    text: str,
    max_attempts: int,
    retry_delay: float,
) -> bool:
    max_attempts = max(1, max_attempts)
    payload = build_telegram_payload(chat_id, number, text)
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    for attempt in range(1, max_attempts + 1):
        try:
            requests.post(url, json=payload, timeout=10).raise_for_status()
            logging.info("Delivered SMS from %s", number)
            return True
        except Exception as exc:  # pragma: no cover - request error paths are mocked in tests
            logging.warning("Delivery failed (%s/%s): %s", attempt, max_attempts, exc)
            if attempt < max_attempts:
                time.sleep(retry_delay)
    return False


def load_payload(path: Path) -> Dict[str, object]:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def recover_processing(dirs: Dict[str, Path]) -> None:
    processing_dir = dirs["processing"]
    pending_dir = dirs["pending"]
    for item in sorted(processing_dir.glob("*.json")):
        try:
            sms_queue.move_item(item, pending_dir)
        except FileNotFoundError:
            continue


def process_queue_once(
    dirs: Dict[str, Path],
    bot_token: str,
    chat_id: str,
    max_attempts: int,
    retry_delay: float,
) -> bool:
    pending_items = sorted(dirs["pending"].glob("*.json"))
    if not pending_items:
        return False
    for item in pending_items:
        try:
            processing_item = sms_queue.move_item(item, dirs["processing"])
        except FileNotFoundError:
            continue
        try:
            payload = load_payload(processing_item)
            number = payload.get("number")
            text = payload.get("text")
            if not isinstance(number, str) or not isinstance(text, str):
                raise ValueError("Missing number/text fields")
        except Exception as exc:
            logging.error("Invalid queue payload %s: %s", processing_item, exc)
            sms_queue.move_item(processing_item, dirs["failed"])
            continue
        if send_with_retries(bot_token, chat_id, number, text, max_attempts, retry_delay):
            sms_queue.move_item(processing_item, dirs["sent"])
        else:
            sms_queue.move_item(processing_item, dirs["failed"])
    return True


def run_worker() -> None:
    logging.basicConfig(level=os.getenv("LOGLEVEL", "INFO"))
    try:
        bot_token = get_env("TELEGRAM_BOT_TOKEN")
        chat_id = get_env("TELEGRAM_CHAT_ID")
    except EnvironmentError as exc:
        logging.error("%s", exc)
        raise SystemExit(1)

    base_dir = sms_queue.resolve_queue_dir()
    dirs = sms_queue.ensure_queue_dirs(base_dir)
    recover_processing(dirs)

    poll_interval = _get_float_env("QUEUE_POLL_INTERVAL", 2.0)
    max_attempts = _get_int_env("QUEUE_MAX_RETRIES", 5)
    retry_delay = _get_float_env("QUEUE_RETRY_DELAY", 5.0)

    while True:
        if not process_queue_once(dirs, bot_token, chat_id, max_attempts, retry_delay):
            time.sleep(poll_interval)


if __name__ == "__main__":  # pragma: no cover
    run_worker()
