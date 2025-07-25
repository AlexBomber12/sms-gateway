import os
import shutil
import subprocess
import time
from pathlib import Path
import glob
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


def modem_available():
    candidates = []
    if os.environ.get("MODEM_PORT"):
        candidates.append(os.environ["MODEM_PORT"])
    candidates.extend(glob.glob("/dev/serial/by-id/*"))
    candidates.extend(glob.glob("/dev/ttyUSB*"))
    return any(Path(p).exists() for p in candidates)


modem_required = pytest.mark.skipif(not modem_available(), reason="no modem available")


@docker_required
@modem_required
def test_compose_service_healthy():
    env = Path(".env")
    if not env.exists():
        env.write_text("SMSGW_VERSION=test\n")
    subprocess.run(["docker", "compose", "up", "-d"], check=True)
    container_id = subprocess.check_output(["docker", "compose", "ps", "-q", "smsgateway"]).decode().strip()
    try:
        deadline = time.time() + 60
        status = ""
        while time.time() < deadline:
            result = subprocess.run(
                [
                    "docker",
                    "inspect",
                    "--format",
                    "{{.State.Health.Status}}",
                    container_id,
                ],
                capture_output=True,
                text=True,
            )
            status = result.stdout.strip()
            if status == "healthy":
                break
            time.sleep(1)
        assert status == "healthy"
        subprocess.run(
            [
                "docker",
                "exec",
                container_id,
                "gammu",
                "--identify",
                "-c",
                "/tmp/gammu-smsdrc",
            ],
            check=True,
        )
    finally:
        subprocess.run(["docker", "compose", "down", "-v"], check=False)
        if env.exists():
            env.unlink()
