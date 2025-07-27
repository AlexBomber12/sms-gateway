import os
import subprocess
from pathlib import Path

ENTRYPOINT = Path("entrypoint.sh").read_text().splitlines()
CUT = ENTRYPOINT.index('main "$@"')
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


def setup_env(tmp_path):
    env = os.environ.copy()
    env["PATH"] = f"{tmp_path}:" + env["PATH"]
    env["GAMMU_SPOOL_PATH"] = "/tmp/gammu-test"
    return env


def test_detect_modem_success(tmp_path):
    make_gammu_stub(tmp_path)
    dev = Path("/dev/ttyUSB42")
    dev.touch()
    env = setup_env(tmp_path)
    res = run_bash("detect_modem", env)
    dev.unlink()
    assert res.returncode == 0


def test_detect_modem_failure(tmp_path):
    make_gammu_stub(tmp_path, succeed_after=999)
    dev = Path("/dev/ttyUSB42")
    dev.touch()
    env = setup_env(tmp_path)
    res = run_bash("detect_modem", env)
    dev.unlink()
    assert res.returncode == 1


def test_retry_loop_exit_70(tmp_path):
    make_gammu_stub(tmp_path, succeed_after=999)
    dev = Path("/dev/ttyUSB42")
    dev.touch()
    env = setup_env(tmp_path)
    loop = (
        "tries=0; max_tries=3; "
        "until detect_modem; do ((tries++)); "
        "if [ $tries -ge $max_tries ]; then exit 70; fi; sleep 0.1; done"
    )
    res = run_bash(loop, env)
    dev.unlink()
    assert res.returncode == 70


def test_retry_loop_succeeds(tmp_path):
    make_gammu_stub(tmp_path, succeed_after=2)
    dev = Path("/dev/ttyUSB42")
    dev.touch()
    env = setup_env(tmp_path)
    loop = (
        "tries=0; max_tries=3; "
        "until detect_modem; do ((tries++)); "
        "if [ $tries -ge $max_tries ]; then exit 70; fi; sleep 0.1; done"
    )
    res = run_bash(loop, env)
    dev.unlink()
    assert res.returncode == 0
