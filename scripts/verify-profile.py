#!/usr/bin/env python3
"""Check public profile metadata before claiming restricted Keychain entitlements."""
import sys, subprocess, plistlib, fnmatch, hashlib, datetime
def require(condition, message):
    if not condition: raise SystemExit(message)
def validate(p, team, identity, now=None, bundle_id="com.keydesk.local"):
    e = p.get('Entitlements', {})
    application = team + '.' + bundle_id
    require(fnmatch.fnmatchcase(application, e.get('com.apple.application-identifier', '')), 'Profile does not authorize Keydesk app ID')
    require(any(fnmatch.fnmatchcase(application, group) for group in e.get('keychain-access-groups', [])), 'Profile does not authorize Keydesk access group')
    require(team in p.get('TeamIdentifier', []), 'Profile team mismatch')
    require(e.get('com.apple.developer.team-identifier') == team, 'Entitlement team mismatch')
    require('OSX' in p.get('Platform', []), 'A macOS profile is required')
    require(p.get('ProvisionsAllDevices') is True and not p.get('ProvisionedDevices'), 'A Developer ID distribution profile is required')
    require(not e.get('get-task-allow') and not e.get('com.apple.security.get-task-allow'), 'Debuggable profiles cannot be released')
    require(p.get('ExpirationDate', datetime.datetime.min) > (now or datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)), 'Expired profile')
    require(any(hashlib.sha1(certificate).hexdigest().upper() == identity for certificate in p.get('DeveloperCertificates', [])), 'Profile and signing certificate mismatch')

if __name__ == '__main__':
    require(len(sys.argv) in [4,5], 'Usage: verify-profile.py <profile> <team-id> <certificate-sha1> [bundle-id]')
    profile, team, identity = sys.argv[1:4]
    bundle_id = sys.argv[4] if len(sys.argv) == 5 else "com.keydesk.local"
    result = subprocess.run(['security', 'cms', '-D', '-i', profile], capture_output=True, check=True)
    validate(plistlib.loads(result.stdout), team, identity, bundle_id=bundle_id)
    print('Matching Keydesk provisioning profile validated.')
