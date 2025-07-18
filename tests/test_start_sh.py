import os
import subprocess
import unittest
from pathlib import Path


class TestStartScript(unittest.TestCase):
    def test_dry_run(self):
        env = os.environ.copy()
        env.update({
            'DEVICE': '/dev/null',
            'BAUDRATE': '9600',
            'TELEGRAM_BOT_TOKEN': 'x',
            'TELEGRAM_CHAT_ID': 'x',
        })
        config = Path('/etc/gammu-smsdrc')
        if config.exists():
            config.unlink()
        subprocess.run(['bash', 'start.sh', '--dry-run'], check=True, env=env)
        self.assertTrue(config.exists())
        config.unlink()
        self.assertTrue(Path('/var/spool/gammu').exists())


if __name__ == '__main__':
    unittest.main()
