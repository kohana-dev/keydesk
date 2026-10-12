#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('migration', Path(__file__).with_name('migrate-cellar-paths.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class MigrationTests(unittest.TestCase):
    def test_clients_preserve_permissions_targets_and_unrelated_values(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = str(home / 'Applications/Keydesk.app/Contents/Helpers/keydesk')
            new = str(home / 'Applications/Cellar.app/Contents/Helpers/keydesk')
            for name, text in [('config.toml', '[mcp_servers.keydesk]\ncommand = ' + json.dumps(old) + '\nargs = ["mcp", "--env", "prod"]\n[mcp_servers.other]\ncommand = "other"\n'), ('client.json', json.dumps({'mcpServers': {'keydesk': {'command': old, 'args': ['mcp', '--env', 'prod']}}, 'permissions': ['Read'], 'unrelated': 'Keydesk.app'}))]:
                path = home / name
                path.write_text(text)
                self.assertTrue(m.migrate(path, home))
                self.assertIn(new, path.read_text())
                self.assertFalse(m.migrate(path, home))
                self.assertEqual(next(home.glob(name + '.cellar-backup-*')).read_text(), text)
            data = json.loads((home / 'client.json').read_text())
            self.assertEqual(data['permissions'], ['Read'])
            self.assertEqual(data['unrelated'], 'Keydesk.app')
            self.assertEqual(data['mcpServers']['keydesk']['args'], ['mcp', '--env', 'prod'])

    def test_cli_retargets_without_touching_other_executable(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            new = home / 'Applications/Cellar.app/Contents/Helpers/keydesk'
            new.parent.mkdir(parents=True)
            new.touch()
            cli = home / '.local/bin/keydesk'
            cli.parent.mkdir(parents=True)
            cli.symlink_to(home / 'Applications/Keydesk.app/Contents/Helpers/keydesk')
            self.assertTrue(m.migrate_cli(home))
            self.assertEqual(os.readlink(cli), str(new))
            self.assertFalse(m.migrate_cli(home))
            cli.unlink()
            cli.write_text('other executable')
            with self.assertRaises(ValueError):
                m.migrate_cli(home)
            self.assertEqual(cli.read_text(), 'other executable')


unittest.main()
