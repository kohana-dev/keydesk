#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
: "${KEYDESK_PROVISIONING_PROFILE:?Set a Keydesk Developer ID provisioning profile path.}"
mkdir -p artifacts
swift test -c release > artifacts/release-swift-tests.txt 2>&1
KEYDESK_RELEASE=1 ./scripts/build-app.sh > artifacts/release-build.txt 2>&1
python3 scripts/verify-protocol.py
python3 scripts/verify-terminal-signals.py
python3 scripts/verify-release.py
print 'Technical preflight complete. Human authentication/recovery and valid API verification remain separate.'
