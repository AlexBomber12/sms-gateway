import subprocess


def test_shellcheck_entrypoint():
    subprocess.run(["shellcheck", "entrypoint.sh"], check=True)
