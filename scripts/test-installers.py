#!/usr/bin/env python3
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import installer_support as support


def load(name):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


mcp = load('install-auto-mcp')
skills = load('install-ai-skills')


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.temp.name)
        self.helper = self.home / 'Applications/Cellar.app/Contents/Helpers/keydesk'
        self.helper.parent.mkdir(parents=True)
        self.helper.write_text('fixture')
        self.helper.chmod(0o755)
        skills.install(home=self.home)
        (self.home / '.local/bin/keydesk').symlink_to(self.helper)
        self.cp = self.home / '.codex/config.toml'
        self.lp = self.home / '.claude.json'
        self.sp = self.home / '.claude/settings.json'
        self.cp.parent.mkdir(exist_ok=True)
        self.cp.write_text('model = "retain"\n')
        self.cp.chmod(0o640)
        self.lp.write_text('{"unrelated":"retain","mcpServers":{}}')
        self.sp.parent.mkdir(exist_ok=True)
        self.sp.write_text('{"permissions":{"deny":["Bash"],"allow":["Read"]},"theme":"retain"}')

    def tearDown(self):
        self.temp.cleanup()

    def state(self):
        return {p: (p.read_bytes(), p.stat().st_mode & 0o777) if p.exists() else None for p in [self.cp, self.lp, self.sp]}

    def runner(self, argv, **kwargs):
        if '--version' not in argv:
            doc = json.loads(self.lp.read_text())
            doc['mcpServers']['keydesk'] = json.loads(argv[-1])
            self.lp.write_text(json.dumps(doc))
        return subprocess.CompletedProcess(argv, 0, '', '')

    def install(self, runner=None, client='both'):
        with patch.object(mcp.shutil, 'which', side_effect=lambda c: '/fixture/' + c), patch.object(mcp.subprocess, 'run', side_effect=runner or self.runner):
            mcp.install(client, self.home)

    def test_success_idempotence_preserves_unrelated(self):
        self.install(); before = self.state(); self.install()
        self.assertEqual(before, self.state())
        self.assertEqual(json.loads(self.lp.read_text())['unrelated'], 'retain')
        self.assertEqual(json.loads(self.sp.read_text())['permissions']['deny'], ['Bash'])
        self.assertEqual(self.cp.stat().st_mode & 0o777, 0o600)

    def test_missing_client_changes_nothing(self):
        before = self.state()
        with patch.object(mcp.shutil, 'which', side_effect=lambda c: '/fixture/codex' if c == 'codex' else None), patch.object(mcp.subprocess, 'run', side_effect=self.runner):
            with self.assertRaises(ValueError): mcp.install(home=self.home)
        self.assertEqual(before, self.state())

    def test_unresponsive_client_changes_nothing(self):
        before = self.state()
        def fail(argv, **kwargs): raise subprocess.TimeoutExpired(argv, 10)
        with self.assertRaises(ValueError): self.install(fail)
        self.assertEqual(before, self.state())

    def test_missing_app_or_cli_changes_nothing(self):
        before = self.state(); self.helper.unlink()
        with self.assertRaises(ValueError): self.install()
        self.assertEqual(before, self.state())

    def test_invalid_configuration_changes_nothing(self):
        for data in ['{', '[]', '{"permissions":{"allow":"wrong"}}']:
            self.sp.write_text(data); before = self.state()
            with self.assertRaises(ValueError): self.install()
            self.assertEqual(before, self.state())

    def test_conflict_changes_nothing(self):
        self.lp.write_text('{"mcpServers":{"keydesk":{"command":"other","args":[]}}}')
        before = self.state()
        with self.assertRaises(ValueError): self.install()
        self.assertEqual(before, self.state())

    def test_claude_partial_failure_restores_bytes_and_modes(self):
        before = self.state()
        def fail(argv, **kwargs):
            if '--version' not in argv:
                self.lp.write_text('{"partial":true}')
                raise subprocess.CalledProcessError(1, argv, stderr='withheld fixture')
            return self.runner(argv, **kwargs)
        with self.assertRaises(RuntimeError): self.install(fail)
        self.assertEqual(before, self.state())
        self.install()  # retry after rollback succeeds

    def test_failure_removes_new_configuration_files(self):
        for p in [self.cp, self.lp, self.sp]: p.unlink()
        def fail(argv, **kwargs):
            if '--version' not in argv:
                self.lp.write_text('{}'); raise OSError('fixture')
            return self.runner(argv, **kwargs)
        with self.assertRaises(RuntimeError): self.install(fail)
        self.assertTrue(all(not p.exists() for p in [self.cp, self.lp, self.sp]))

    def test_final_write_failure_restores_both_clients(self):
        before = self.state(); original = mcp.atomic_write
        def fail(path, *args):
            if path == self.sp: raise OSError('fixture')
            return original(path, *args)
        with patch.object(mcp, 'atomic_write', side_effect=fail):
            with self.assertRaises(RuntimeError): self.install()
        self.assertEqual(before, self.state())

    def test_single_client_does_not_require_other_cli_or_touch_it(self):
        before = (self.lp.read_bytes(), self.sp.read_bytes())
        with patch.object(mcp.shutil, 'which', side_effect=lambda c: '/fixture/codex' if c == 'codex' else None), patch.object(mcp.subprocess, 'run', side_effect=self.runner):
            mcp.install('codex', self.home)
        self.assertEqual(before, (self.lp.read_bytes(), self.sp.read_bytes()))

    def test_late_adapter_conflict_preserves_all_skills(self):
        target = self.home / '.local/bin/keydesk-mcp'; target.write_text('conflict')
        before = {p: p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        with self.assertRaises(ValueError): skills.install(home=self.home)
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_skill_write_failure_restores_existing_and_removes_new(self):
        target = self.home / '.local/bin/keydesk-mcp'; target.write_text('old'); target.chmod(0o700)
        fresh = self.home / '.claude/skills/keydesk/SKILL.md'; fresh.unlink()
        original = skills.atomic_write
        def fail(path, *args):
            if path == target: raise OSError('fixture')
            return original(path, *args)
        with patch.object(skills, 'atomic_write', side_effect=fail):
            with self.assertRaises(RuntimeError): skills.install(update=True, home=self.home)
        self.assertEqual(target.read_text(), 'old'); self.assertEqual(target.stat().st_mode & 0o777, 0o700)
        self.assertFalse(fresh.exists())

    def test_symlink_target_rejected(self):
        self.cp.unlink(); self.cp.symlink_to(self.lp); before = self.lp.read_bytes()
        with self.assertRaises(ValueError): self.install()
        self.assertEqual(before, self.lp.read_bytes())


if __name__ == '__main__': unittest.main()
