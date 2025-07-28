import subprocess
import pathlib
import time

proc = subprocess.Popen([pathlib.Path("entrypoint.sh").resolve()], env={"CI_MODE": "true"})
try:
    time.sleep(1)
    assert proc.poll() is None
finally:
    proc.terminate()
    proc.wait(timeout=3)
