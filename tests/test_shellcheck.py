import shutil
import subprocess
import pytest

@pytest.mark.skipif(shutil.which("shellcheck") is None, reason="shellcheck missing")
def test_entrypoint_shellcheck():
    subprocess.run(["shellcheck", "entrypoint.sh"], check=True)
