#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 1 ]] || { print 'Usage: scripts/notarize.sh <existing-notarytool-keychain-profile>'; exit 2; }
profile="$1"
python3 scripts/verify-release.py
ditto -c -k --keepParent dist/Keydesk.app dist/Keydesk-notarization.zip
xcrun notarytool submit dist/Keydesk-notarization.zip --keychain-profile "$profile" --wait
xcrun stapler staple dist/Keydesk.app
xcrun stapler validate dist/Keydesk.app
spctl --assess --type execute dist/Keydesk.app
python3 scripts/verify-release.py --require-notarized --report artifacts/release-notarized-preflight.json
# Recreate the deliverable after stapling so the distributed app carries its ticket.
ditto -c -k --keepParent dist/Keydesk.app dist/Keydesk-notarized.zip
shasum -a 256 dist/Keydesk-notarized.zip > artifacts/release-archive-sha256.txt
