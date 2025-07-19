import os
import subprocess
import time
import pty
import threading
import shutil
import pytest


class FakeModem(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.master, self.slave = pty.openpty()
        self.path = os.ttyname(self.slave)
        self.running = True

    def run(self):
        with os.fdopen(self.master, 'rb+', buffering=0) as fd:
            while self.running:
                data = fd.readline()
                if not data:
                    continue
                cmd = data.strip().decode('ascii', 'ignore')
                if cmd in ('AT', 'ATE0'):
                    fd.write(b'OK\r\n')
                elif cmd == 'AT+CGMI':
                    fd.write(b'Generic\r\nOK\r\n')
                elif cmd == 'AT+CGMM':
                    fd.write(b'Model\r\nOK\r\n')
                elif cmd == 'AT+CGMR':
                    fd.write(b'1.0\r\nOK\r\n')
                elif cmd == 'AT+CGSN':
                    fd.write(b'12345\r\nOK\r\n')
                else:
                    fd.write(b'OK\r\n')

    def stop(self):
        self.running = False


def test_container_becomes_healthy(tmp_path):
    if not shutil.which('docker'):
        pytest.skip('docker not available')

    image = 'smsgateway:test'
    subprocess.run(['docker', 'build', '-t', image, '.'], check=True)

    modem = FakeModem(); modem.start()
    compose = tmp_path / 'compose.yml'
    compose.write_text(
        f"""
services:
  smsgateway:
    image: {image}
    devices:
      - {modem.path}:/dev/ttyUSB0
    privileged: true
    environment:
      TELEGRAM_BOT_TOKEN: dummy
      TELEGRAM_CHAT_ID: dummy
    healthcheck:
      test: [\"CMD-SHELL\", \"gammu --identify -c /tmp/gammurc >/dev/null 2>&1\"]
      interval: 1s
      timeout: 1s
      retries: 60
"""
    )

    subprocess.run(['docker', 'compose', '-f', str(compose), 'up', '-d'], check=True)
    try:
        status = ''
        for _ in range(60):
            status = subprocess.check_output(
                ['docker', 'inspect', '--format', '{{.State.Health.Status}}', 'smsgateway'],
                text=True,
            ).strip()
            if status == 'healthy':
                break
            time.sleep(1)
        assert status == 'healthy'
        subprocess.run([
            'docker', 'exec', 'smsgateway', 'gammu', '--identify', '-c', '/tmp/gammurc'
        ], check=True)
    finally:
        subprocess.run(['docker', 'compose', '-f', str(compose), 'down', '-v'], check=False)
        modem.stop()
