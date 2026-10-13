#!/usr/bin/env python3
"""Negative distribution cases and signature tampering, using only disposable fixtures."""
import copy
import datetime
import hashlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('verify_profile', ROOT / 'scripts/verify-profile.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ReleaseToolsTests(unittest.TestCase):
    def localization_fixture(self, directory):
        app = pathlib.Path(directory) / 'Cellar.app'
        for language, reason in [('en', 'Authenticate to unlock your Cellar vault.'),
                                 ('ko', 'Cellar 금고를 열기 위해 인증합니다.')]:
            resource = app / 'Contents/Resources' / (language + '.lproj') / 'InfoPlist.strings'
            resource.parent.mkdir(parents=True)
            resource.write_text('"NSFaceIDUsageDescription" = ' + json.dumps(reason, ensure_ascii=False) + ';\n')
        info = {'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'ko']}
        return app, info

    def test_bilingual_bundle_resources_are_validated_without_running_app(self):
        spec = importlib.util.spec_from_file_location('verify_release', ROOT / 'scripts/verify-release.py')
        release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
        with tempfile.TemporaryDirectory(prefix='cellar-localization-test-') as directory:
            app, info = self.localization_fixture(directory)
            with patch.object(release, 'run', wraps=release.run) as tool:
                self.assertTrue(all(release.localization_checks(app, info).values()))
                self.assertEqual(tool.call_count, 2)
                self.assertTrue(all(call.args[0] == 'plutil' for call in tool.call_args_list))

    def test_localization_gate_rejects_missing_or_invalid_resources_and_metadata(self):
        spec = importlib.util.spec_from_file_location('verify_release', ROOT / 'scripts/verify-release.py')
        release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
        cases = ['missing_en', 'missing_ko', 'empty_en', 'missing_usage_key', 'blank_usage_key',
                 'malformed_strings', 'missing_languages', 'missing_korean', 'invalid_languages',
                 'missing_region', 'wrong_region']
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory(prefix='cellar-localization-test-') as directory:
                app, info = self.localization_fixture(directory)
                resource = app / 'Contents/Resources/en.lproj/InfoPlist.strings'
                if case in ('missing_en', 'missing_ko'):
                    (app / 'Contents/Resources' / (case.removeprefix('missing_') + '.lproj') / 'InfoPlist.strings').unlink()
                elif case == 'empty_en':
                    resource.write_text('')
                elif case == 'missing_usage_key':
                    resource.write_text('"OtherKey" = "Not an authentication description";\n')
                elif case == 'blank_usage_key':
                    resource.write_text('"NSFaceIDUsageDescription" = " ";\n')
                elif case == 'malformed_strings':
                    resource.write_text('"NSFaceIDUsageDescription" = "unterminated;\n')
                elif case == 'missing_languages':
                    info.pop('CFBundleLocalizations')
                elif case == 'missing_korean':
                    info['CFBundleLocalizations'] = ['en']
                elif case == 'invalid_languages':
                    info['CFBundleLocalizations'] = 'en,ko'
                elif case == 'missing_region':
                    info.pop('CFBundleDevelopmentRegion')
                elif case == 'wrong_region':
                    info['CFBundleDevelopmentRegion'] = 'ko'
                with patch.object(release, 'run', wraps=release.run) as tool:
                    self.assertFalse(all(release.localization_checks(app, info).values()))
                    self.assertTrue(all(call.args[0] == 'plutil' for call in tool.call_args_list))

    def test_non_system_linked_libraries_fail_closed(self):
        spec = importlib.util.spec_from_file_location('verify_release', ROOT / 'scripts/verify-release.py')
        release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
        self.assertTrue(release.apple_system_links('app:\n\t/usr/lib/libSystem.B.dylib (compatibility version 1)\n'))
        for link in ['@rpath/unreviewed.dylib', '/opt/homebrew/lib/libunreviewed.dylib', '/tmp/other.dylib']:
            self.assertFalse(release.apple_system_links('app:\n\t' + link + ' (compatibility version 1)\n'))
        self.assertFalse(release.apple_system_links('app:\n'))

    def test_distribution_profile_rejects_wrong_identity_platform_and_debug(self):
        now = datetime.datetime(2026, 10, 10)
        team, certificate = 'TESTTEAM01', b'PUBLIC_TEST_CERTIFICATE_NOT_A_REAL_PROFILE'
        identity = hashlib.sha1(certificate).hexdigest().upper()
        fixture = {'TeamIdentifier': [team], 'Platform': ['OSX'],
                   'ProvisionsAllDevices': True, 'ExpirationDate': now + datetime.timedelta(days=1),
                   'DeveloperCertificates': [certificate],
                   'Entitlements': {'com.apple.application-identifier': team + '.com.keydesk.local',
                                    'com.apple.developer.team-identifier': team,
                                    'keychain-access-groups': [team + '.*']}}
        module.validate(fixture, team, identity, now=now)
        for field, value in [('TeamIdentifier', ['OTHER']), ('Platform', ['iOS']),
                             ('ProvisionsAllDevices', False), ('ProvisionedDevices', ['device']),
                             ('ExpirationDate', now), ('DeveloperCertificates', [b'other'])]:
            invalid = copy.deepcopy(fixture); invalid[field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                module.validate(invalid, team, identity, now=now)
        for field, value in [('com.apple.application-identifier', team + '.other'),
                             ('com.apple.developer.team-identifier', 'OTHER'),
                             ('keychain-access-groups', [team + '.other']),
                             ('get-task-allow', True), ('com.apple.security.get-task-allow', True)]:
            invalid = copy.deepcopy(fixture); invalid['Entitlements'][field] = value
            with self.subTest(field=field), self.assertRaises(SystemExit):
                module.validate(invalid, team, identity, now=now)

    def test_custom_bundle_profile_requires_matching_access_group(self):
        now = datetime.datetime(2026, 10, 10)
        team, cert, bundle = 'TESTTEAM01', b'FAKE_CERTIFICATE', 'org.example.keydesk'
        identity = hashlib.sha1(cert).hexdigest().upper()
        fixture = {'TeamIdentifier':[team], 'Platform':['OSX'], 'ProvisionsAllDevices':True,
                   'ExpirationDate':now + datetime.timedelta(days=1), 'DeveloperCertificates':[cert],
                   'Entitlements':{'com.apple.application-identifier':team+'.'+bundle,
                       'com.apple.developer.team-identifier':team, 'keychain-access-groups':[team+'.'+bundle]}}
        module.validate(fixture, team, identity, now, bundle_id=bundle)
        with self.assertRaises(SystemExit): module.validate(fixture, team, identity, now)
        fixture['Entitlements']['keychain-access-groups']=[team+'.com.keydesk.local']
        with self.assertRaises(SystemExit): module.validate(fixture, team, identity, now, bundle_id=bundle)

    def test_missing_profile_cannot_produce_release(self):
        import os
        env = dict(os.environ); env.pop('KEYDESK_PROVISIONING_PROFILE', None)
        env['KEYDESK_RELEASE'] = '1'
        result = subprocess.run(['zsh', 'scripts/build-app.sh'], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Release requires', result.stderr)

    def test_tampered_helper_rejected_before_execution(self):
        with tempfile.TemporaryDirectory(prefix='keydesk-release-gate-test-') as temporary:
            app = pathlib.Path(temporary) / 'Cellar.app'
            shutil.copytree(ROOT / 'dist/Cellar.app', app)
            helper = app / 'Contents/Helpers/keydesk'
            # Change a signed code page, not unsigned padding after the signature blob.
            data = bytearray(helper.read_bytes()); data[16_384] ^= 1; helper.write_bytes(data)
            report = pathlib.Path(temporary) / 'report.json'
            result = subprocess.run(['python3', str(ROOT / 'scripts/verify-release.py'), '--app', str(app), '--report', str(report)], capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 2)
            checks = json.loads(report.read_text())['checks']
            self.assertFalse(checks['strict_helper_signature'])
            self.assertFalse(checks['bundled_cli_runs'])

if __name__ == '__main__':
    unittest.main()
