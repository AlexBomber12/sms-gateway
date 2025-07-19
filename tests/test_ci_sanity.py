import importlib


def test_pytest_present():
    assert importlib.util.find_spec("pytest") is not None
