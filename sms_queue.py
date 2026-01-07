#!/usr/bin/env python3
"""Durable file queue helpers for SMS delivery."""
from __future__ import annotations

import json
import os
import time
import uuid
from pathlib import Path
from typing import Dict

QUEUE_DIR_ENV = "SMSGW_QUEUE_DIR"
QUEUE_SUBDIRS = ("pending", "processing", "sent", "failed", "tmp")


def resolve_queue_dir(env=os.getenv) -> Path:
    base = env(QUEUE_DIR_ENV)
    if base:
        return Path(base)
    spool = env("GAMMU_SPOOL_PATH", "/var/spool/gammu")
    return Path(spool) / "sms-queue"


def ensure_queue_dirs(base_dir: Path) -> Dict[str, Path]:
    dirs = {name: base_dir / name for name in QUEUE_SUBDIRS}
    for path in dirs.values():
        path.mkdir(parents=True, exist_ok=True)
    return dirs


def _fsync_dir(path: Path) -> None:
    try:
        fd = os.open(path, os.O_DIRECTORY)
    except OSError:
        return
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def enqueue_message(number: str, text: str, base_dir: Path) -> Path:
    dirs = ensure_queue_dirs(base_dir)
    message_id = f"{int(time.time() * 1000)}-{uuid.uuid4().hex}"
    payload = {
        "id": message_id,
        "number": number,
        "text": text,
        "received_at": time.time(),
    }
    tmp_path = dirs["tmp"] / f"{message_id}.json"
    final_path = dirs["pending"] / f"{message_id}.json"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=True)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp_path, final_path)
    _fsync_dir(final_path.parent)
    return final_path


def move_item(path: Path, dest_dir: Path) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest_path = dest_dir / path.name
    os.replace(path, dest_path)
    _fsync_dir(dest_dir)
    return dest_path
