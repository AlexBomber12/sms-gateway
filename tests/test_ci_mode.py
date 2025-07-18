import subprocess
import pathlib

assert subprocess.run(
    [pathlib.Path("entrypoint.sh").resolve()],
    env={"CI_MODE": "true"},
    timeout=3,
).returncode == 0

