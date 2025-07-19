import importlib.util

import pytest


@pytest.mark.parametrize("pkg", ["pytest"])
def test_dev_dep(pkg):
    assert importlib.util.find_spec(pkg), f"{pkg} missing in image"
