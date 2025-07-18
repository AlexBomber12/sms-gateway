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
        spool = Path('/tmp/gammu-test-spool')
        config = Path('/tmp/gammu-test-config')
        env['GAMMU_SPOOL_PATH'] = str(spool)
        env['GAMMU_CONFIG_PATH'] = str(config)
        if config.exists():
            config.unlink()
        if spool.exists():
            subprocess.run(['rm', '-rf', str(spool)], check=True)
        subprocess.run(['bash', 'start.sh', '--dry-run'], check=True, env=env)
        self.assertTrue(config.exists())
        self.assertTrue(spool.exists())
        config.unlink()
        subprocess.run(['rm', '-rf', str(spool)], check=True)


if __name__ == '__main__':
    unittest.main()
