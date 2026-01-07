import os
import re
import subprocess
import time
from pathlib import Path

ENTRYPOINT = Path("entrypoint.sh").read_text().splitlines()
CUT = next(i for i, line in enumerate(ENTRYPOINT) if line.strip() == 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then')
FUNCTIONS = "\n".join(ENTRYPOINT[:CUT])


def make_gammu_stub(dir_path, succeed_after=1):
    path = Path(dir_path) / "gammu"
    count_file = Path(dir_path) / "count"
    script = f"""#!/usr/bin/env bash
count=$(cat '{count_file}' 2>/dev/null || echo 0)
count=$((count+1))
echo "$count" > '{count_file}'
if [ "$count" -ge {succeed_after} ]; then
  exit 0
else
  exit 1
fi
"""
    path.write_text(script)
    path.chmod(0o755)


def run_bash(snippet, env):
    script = FUNCTIONS + "\nset +e\n" + snippet
    return subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)


def setup_env(tmp_path, modem_port=None):
    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:" + env["PATH"]
    env["GAMMU_SPOOL_PATH"] = "/tmp/gammu-test"
    if modem_port is not None:
        env["MODEM_PORT"] = str(modem_port)
    return env


def test_detect_modem_success(tmp_path):
    make_gammu_stub(tmp_path)
    dev = tmp_path / "ttyUSB42"
    dev.touch()
    env = setup_env(tmp_path, modem_port=dev)
    res = run_bash('detect_modem; echo "MODEM_PORT=${MODEM_PORT}"', env)
    dev.unlink()
    assert res.returncode == 0
    assert f"MODEM_PORT={dev}" in res.stdout


def test_detect_modem_failure(tmp_path):
    make_gammu_stub(tmp_path, succeed_after=999)
    dev = tmp_path / "ttyUSB42"
    dev.touch()
    env = setup_env(tmp_path, modem_port=dev)
    res = run_bash("detect_modem", env)
    dev.unlink()
    assert res.returncode == 1


def test_retry_loop_retries(tmp_path):
    env = setup_env(tmp_path)
    loop = (
        "detect_modem() { return 1; }\n"
        "sleep() { count=$((count+1)); [ $count -ge 3 ] && exit 0; }\n"
        "count=0\n"
        "until detect_modem; do reset_modem; echo retry$count; sleep 30; done"
    )
    res = run_bash(loop, env)
    assert res.returncode == 0
    assert res.stdout.count("retry") == 3


def test_retry_loop_succeeds(tmp_path):
    env = setup_env(tmp_path)
    loop = (
        "codes=(1 1 0)\n"
        "idx=0\n"
        "detect_modem() { rc=${codes[$idx]}; idx=$((idx+1)); return $rc; }\n"
        "sleep() { :; }\n"
        "until detect_modem; do reset_modem; sleep 30; done; echo calls=$idx"
    )
    res = run_bash(loop, env)
    assert res.returncode == 0
    assert "calls=3" in res.stdout


def test_single_instance(tmp_path):
    make_gammu_stub(tmp_path)
    subprocess.run(["pkill", "-9", "-f", "gammu-smsd"], stderr=subprocess.DEVNULL)
    svc = Path(tmp_path) / "service"
    svc.write_text("#!/usr/bin/env bash\nexit 0\n")
    svc.chmod(0o755)
    slp = Path(tmp_path) / "sleep"
    slp.write_text("#!/usr/bin/env bash\n/bin/true\n")
    slp.chmod(0o755)
    smsd = Path(tmp_path) / "gammu-smsd"
    smsd.write_text("#!/usr/bin/env bash\n/bin/sleep 60\n")
    smsd.chmod(0o755)
    dev = tmp_path / "ttyUSB42"
    dev.touch()
    env = setup_env(tmp_path, modem_port=dev)
    env.pop("CI_MODE", None)
    proc = subprocess.Popen(["bash", "entrypoint.sh"], env=env)
    try:
        time.sleep(2)
        count = int(subprocess.check_output(["pgrep", "-f", "-c", "gammu-smsd"]).strip())
        assert count == 1
    finally:
        proc.terminate()
        proc.wait(timeout=5)
        dev.unlink()


def test_reset_usb_modem_defined():
    assert re.search(r"^reset_usb_modem\(\)", FUNCTIONS, re.M)
