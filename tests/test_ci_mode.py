import subprocess
import pathlib

assert subprocess.run(
    ["bash", pathlib.Path(__file__).parents[1] / "entrypoint.sh", "true"],
    env={"CI_MODE": "true"},
    timeout=8,
).returncode == 0

