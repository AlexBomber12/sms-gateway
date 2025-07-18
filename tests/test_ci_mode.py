import os
import subprocess


def test_ci_mode(tmp_path):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    # gammu should fail so device_ok returns false
    (bin_dir / "gammu").symlink_to("/usr/bin/false")
    env = os.environ.copy()
    env.update({
        "CI_MODE": "true",
        "PATH": f"{bin_dir}:{env.get('PATH','')}",
        "GAMMU_SPOOL_PATH": str(tmp_path / "spool"),
        "GAMMU_CONFIG_PATH": str(tmp_path / "config"),
    })
    result = subprocess.run(["bash", "entrypoint.sh"], env=env, timeout=5, capture_output=True, text=True)
    assert result.returncode == 0
    assert "CI_MODE enabled" in result.stdout

