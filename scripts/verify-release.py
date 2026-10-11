#!/usr/bin/env python3
"""Check an actual bundle. This gate never attests human authentication or real API use."""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent

def run(*args):
    return subprocess.run(args, capture_output=True, timeout=60)

def apple_system_links(output):
    libraries = [line.strip().split(' (')[0] for line in output.splitlines()[1:] if line.strip()]
    return bool(libraries) and all(name.startswith(('/usr/lib/', '/System/Library/')) for name in libraries)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=pathlib.Path, default=ROOT / 'dist/Keydesk.app')
    parser.add_argument('--require-notarized', action='store_true')
    parser.add_argument('--report', type=pathlib.Path, default=ROOT / 'artifacts/release-preflight.json')
    options = parser.parse_args()
    app = options.app.resolve()
    checks, failures = {}, []

    def check(name, condition):
        checks[name] = bool(condition)
        if not condition:
            failures.append(name)

    try:
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        bundle_id = __import__('os').environ.get('KEYDESK_BUNDLE_ID', 'com.keydesk.local')
        check('bundle_id', info.get('CFBundleIdentifier') == bundle_id)
        executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
        helper = app / 'Contents/Helpers/keydesk'
        # Fail closed if a future release adds unaudited packages or linked libraries.
        manifest = subprocess.run(['swift', 'package', 'dump-package'], cwd=ROOT, capture_output=True, timeout=60)
        check('no_external_swift_packages', manifest.returncode == 0 and json.loads(manifest.stdout).get('dependencies') == [])
        links = [run('otool', '-L', str(binary)) for binary in [executable, helper]]
        check('apple_system_libraries_only', all(result.returncode == 0 and apple_system_links(result.stdout.decode()) for result in links))
        check('strict_app_signature', run('codesign', '--verify', '--deep', '--strict', str(app)).returncode == 0)
        check('strict_helper_signature', run('codesign', '--verify', '--strict', str(helper)).returncode == 0)
        description = run('codesign', '-d', '--verbose=4', str(app)).stderr.decode()
        team = re.search(r'^TeamIdentifier=(\w+)$', description, re.M)
        check('developer_id_and_runtime', 'Authority=Developer ID Application:' in description and 'runtime' in description and team is not None)
        helper_description = run('codesign', '-d', '--verbose=4', str(helper)).stderr.decode()
        helper_team = re.search(r'^TeamIdentifier=(\w+)$', helper_description, re.M)
        check('helper_identity_and_runtime', 'Authority=Developer ID Application:' in helper_description and 'runtime' in helper_description and ('Identifier=' + bundle_id + '.cli\n') in helper_description and team is not None and helper_team is not None and helper_team.group(1) == team.group(1))
        raw = run('codesign', '-d', '--entitlements', ':-', str(app)).stdout
        entitlements = plistlib.loads(raw) if raw.strip() else {}
        group = team.group(1) + '.' + bundle_id if team else ''
        check('own_keychain_group_only', entitlements.get('keychain-access-groups') == [group] and entitlements.get('com.apple.application-identifier') == group)
        unsafe = ['com.apple.security.get-task-allow', 'get-task-allow',
                  'com.apple.security.cs.disable-library-validation',
                  'com.apple.security.cs.allow-jit',
                  'com.apple.security.cs.allow-unsigned-executable-memory',
                  'com.apple.security.cs.disable-executable-page-protection',
                  'com.apple.security.cs.allow-dyld-environment-variables']
        check('no_hardened_runtime_exceptions', not any(entitlements.get(key) for key in unsafe))
        helper_raw = run('codesign', '-d', '--entitlements', ':-', str(helper)).stdout
        helper_entitlements = plistlib.loads(helper_raw) if helper_raw.strip() else {}
        check('helper_has_no_keychain_access', not helper_entitlements.get('keychain-access-groups') and not helper_entitlements.get('com.apple.application-identifier') and not any(helper_entitlements.get(key) for key in unsafe))
        profile = app / 'Contents/embedded.provisionprofile'
        check('embedded_profile', profile.is_file())
        if profile.is_file() and team:
            # Extract the public leaf certificate, never its private key.
            import tempfile
            with tempfile.TemporaryDirectory(prefix='keydesk-release-cert-') as temporary:
                prefix = str(pathlib.Path(temporary) / 'certificate')
                cert = run('codesign', '-d', '--extract-certificates=' + prefix, str(app))
                certificate_path = pathlib.Path(prefix + '0')
                fingerprint = hashlib.sha1(certificate_path.read_bytes()).hexdigest().upper() if cert.returncode == 0 else ''
                verified = run('python3', str(ROOT / 'scripts/verify-profile.py'), str(profile), team.group(1), fingerprint, bundle_id)
                check('profile_matches_certificate_and_distribution', verified.returncode == 0)
            # The probe touches only one random disposable item; no existing values or prompt.
            may_execute = (checks['strict_app_signature'] and checks['strict_helper_signature'] and
                           checks['developer_id_and_runtime'] and checks['helper_identity_and_runtime'] and
                           checks['profile_matches_certificate_and_distribution'])
            text = run(str(executable), '--keychain-self-test').stdout.decode() if may_execute else ''
            check('protected_keychain_no_ui_probe', 'protected_item_add=success' in text and 'user_presence_enforced=true' in text)
            check('icloud_keychain_item_allowed', 'synchronizable_item_add=success' in text)
            # The unlock path refuses to authenticate unless the app can find its own profile.
            check('unlock_path_finds_profile', 'authentication_profile_found=true' in text)
        else:
            check('profile_matches_certificate_and_distribution', False)
            check('protected_keychain_no_ui_probe', False)
        check('bundled_cli_runs', checks['strict_helper_signature'] and checks['helper_identity_and_runtime'] and run(str(helper), '--help').returncode == 0)
        if options.require_notarized:
            check('stapled_ticket', run('xcrun', 'stapler', 'validate', str(app)).returncode == 0)
            check('gatekeeper', run('spctl', '--assess', '--type', 'execute', str(app)).returncode == 0)
        hashes = {str(p.relative_to(app)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [executable, helper, profile] if p.is_file()}
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        # Keep error bodies out of the report; this is infrastructure state only.
        failures.append(type(error).__name__)
        hashes = {}
    report = {'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'version': info.get('CFBundleShortVersionString') if 'info' in locals() else None,
              'checks': checks, 'failed_checks': failures, 'sha256': hashes,
              'technical_preflight_passed': not failures,
              'notarization_required': options.require_notarized,
              'human_authentication_and_valid_api_verification_attested': False,
              'production_ready': False}
    options.report.parent.mkdir(parents=True, exist_ok=True)
    options.report.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: technical release preflight' if not failures else 'BLOCKED: ' + ', '.join(failures))
    print('Human authentication/recovery and valid-provider verification are separate release requirements.')
    return 0 if not failures else 2

if __name__ == '__main__':
    raise SystemExit(main())
