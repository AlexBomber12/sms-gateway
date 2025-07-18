import subprocess


def test_entrypoint_ci_mode():
    result = subprocess.run(
        ["bash", "entrypoint.sh"], env={"CI_MODE": "true"}, timeout=5
    )
    assert result.returncode == 0
