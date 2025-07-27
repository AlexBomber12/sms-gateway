import os
import subprocess
import time
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
    env = setup_env(tmp_path)
    loop = (
        "codes=(1 1 1)\n"
        "idx=0\n"
        "detect_modem() { rc=${codes[$idx]}; idx=$((idx+1)); return $rc; }\n"
        "tries=0; max_tries=3;\n"
        "until detect_modem; do ((tries++)); "
        "if [ $tries -lt $max_tries ]; then sleep 0.1; continue; fi; "
        "echo exit70; exit 70; done"
    )
    res = run_bash(loop, env)
    assert res.returncode == 70


def test_retry_loop_succeeds(tmp_path):
    env = setup_env(tmp_path)
    loop = (
        "codes=(1 1 0)\n"
        "idx=0\n"
        "detect_modem() { rc=${codes[$idx]}; idx=$((idx+1)); return $rc; }\n"
        "tries=0; max_tries=3;\n"
        "until detect_modem; do ((tries++)); "
        "if [ $tries -lt $max_tries ]; then sleep 0.1; continue; fi; "
        "echo exit70; exit 70; done; echo calls=$idx"
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
    dev = Path("/dev/ttyUSB42")
    dev.touch()
    env = setup_env(tmp_path)
    proc = subprocess.Popen(["bash", "entrypoint.sh"], env=env)
    try:
        time.sleep(2)
        count = int(subprocess.check_output(["pgrep", "-f", "-c", "gammu-smsd"]).strip())
        assert count == 1
    finally:
        proc.terminate()
        proc.wait(timeout=5)
        dev.unlink()
