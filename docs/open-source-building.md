# Build and distribute

## Requirements and demo

macOS 14+, Swift 6.2+ (a compatible Xcode or Command Line Tools installation).
Accept any Apple toolchain license yourself. No external Swift packages.

```sh
swift test
KEYDESK_SIGNING_MODE=adhoc ./scripts/build-app.sh
open dist/Keydesk.app --args --demo
```

Ad-hoc/demo builds cannot create a real protected vault. This is intentional.
Do not remove OS authentication or use weaker Keychain storage to bypass it.

## Signed real-vault builds

End users do not need an Apple Developer membership to run an official signed,
notarized app. Developers producing their own real-vault builds currently need
a Developer ID Application certificate and a matching macOS Developer ID
provisioning profile authorizing `TEAM_ID.YOUR_BUNDLE_ID` and its Keychain
access group. The team is discovered from the selected certificate; no
maintainer's team ID or credentials are shipped. Set `KEYDESK_BUNDLE_ID=org.yourdomain.keydesk` consistently for build,
preflight and notarization; the default is `com.keydesk.local`. Different teams' builds have different Keychain access;
restore from backup with a recovery key before changing signing identities.

```sh
export KEYDESK_BUNDLE_ID=org.yourdomain.keydesk
KEYDESK_SIGNING_IDENTITY=CERTIFICATE_SHA1 \
KEYDESK_PROVISIONING_PROFILE=/absolute/path/Keydesk.provisionprofile \
./scripts/prepare-release.sh
./scripts/notarize.sh YOUR_EXISTING_NOTARY_PROFILE
```

Set KEYDESK_SIGNING_IDENTITY if multiple Developer ID certificates exist.
Never put private keys, profiles, Apple passwords or notary credentials in Git.
Notarization credentials stay in the developer's own Keychain.
The release app embeds its public provisioning profile as required by macOS;
this profile is excluded from the source package.

## Public-source packaging

```sh
python3 scripts/export-public-source.py
```

Output: `dist/public-source/Keydesk-source` and `dist/public-source/Keydesk-source.zip`.
This uses an explicit allowlist, no Git history, personal docs, screenshots,
logs, built apps, signing materials or real vault data. Source hashes are
recorded beside the archive. Do not publish the working folder directly.
The content scanner is defense in depth, not a guarantee of absence of secrets.
Before pushing a fresh public repository, inspect the exported file list,
verify licensing, enable private vulnerability reporting and run clean tests.

## Known verification limits

The prior 0.5.4 installed app passed actual Codex/Claude store/use workflows, local
peer rejection and same-Mac real encrypted iCloud-backup restore. Another Mac
was unavailable. Actual sleep/screen-lock transitions and a separate-account
installation remain manual release checks. Public distribution is a beta,
not an independently audited credential manager.
