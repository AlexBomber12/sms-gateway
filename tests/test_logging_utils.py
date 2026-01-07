import logging

import pytest

import logging_utils


@pytest.mark.parametrize(
    "value, expected",
    [
        ("CRITICAL", logging.CRITICAL),
        ("error", logging.ERROR),
        ("Warning", logging.WARNING),
        ("info", logging.INFO),
        ("DeBuG", logging.DEBUG),
        ("notset", logging.NOTSET),
    ],
)
def test_parse_loglevel_names(value, expected):
    assert logging_utils.parse_loglevel(value) == expected


@pytest.mark.parametrize("value, expected", [("1", 1), ("10", 10), (" 20 ", 20)])
def test_parse_loglevel_numeric(value, expected):
    assert logging_utils.parse_loglevel(value) == expected


@pytest.mark.parametrize("value", [None, "", " ", "verbose", "trace"])
def test_parse_loglevel_invalid_defaults(value):
    assert logging_utils.parse_loglevel(value) == logging.INFO


def test_get_loglevel_from_env(monkeypatch):
    monkeypatch.setenv("LOGLEVEL", "debug")
    assert logging_utils.get_loglevel() == logging.DEBUG


def test_get_loglevel_default(monkeypatch):
    monkeypatch.delenv("LOGLEVEL", raising=False)
    assert logging_utils.get_loglevel() == logging.INFO
