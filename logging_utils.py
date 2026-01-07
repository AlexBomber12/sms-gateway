"""Logging helpers."""

from __future__ import annotations

import logging
import os

_LEVEL_NAMES = {
    "CRITICAL": logging.CRITICAL,
    "ERROR": logging.ERROR,
    "WARNING": logging.WARNING,
    "INFO": logging.INFO,
    "DEBUG": logging.DEBUG,
    "NOTSET": logging.NOTSET,
}


def parse_loglevel(value: str | None) -> int:
    if value is None:
        return logging.INFO
    cleaned = value.strip()
    if not cleaned:
        return logging.INFO
    if cleaned.isdigit():
        return int(cleaned)
    return _LEVEL_NAMES.get(cleaned.upper(), logging.INFO)


def get_loglevel(name: str = "LOGLEVEL") -> int:
    return parse_loglevel(os.getenv(name))
