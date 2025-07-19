import os
import shutil
import subprocess
import time
import pytest


def docker_available():
    if shutil.which("docker") is None:
        return False
    try:
        subprocess.run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        return True
    except subprocess.CalledProcessError:
        return False


docker_required = pytest.mark.skipif(not docker_available(), reason="docker unavailable")


@docker_required
def test_compose_service_healthy():
    subprocess.run(["docker", "compose", "up", "-d"], check=True)
    try:
        deadline = time.time() + 60
        status = ""
        while time.time() < deadline:
            result = subprocess.run([
                "docker",
                "inspect",
                "--format",
                "{{.State.Health.Status}}",
                "smsgateway",
            ], capture_output=True, text=True)
            status = result.stdout.strip()
            if status == "healthy":
                break
            time.sleep(1)
        assert status == "healthy"
        subprocess.run([
            "docker",
            "exec",
            "smsgateway",
            "gammu",
            "identify",
            "-c",
            "/tmp/gammurc",
        ], check=True)
    finally:
        subprocess.run(["docker", "compose", "down", "-v"], check=False)

