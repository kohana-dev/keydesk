#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "${KEYDESK_RELEASE:-0}" == 1 && -z "${KEYDESK_PROVISIONING_PROFILE:-}" ]]; then
  print -u2 "Release requires KEYDESK_PROVISIONING_PROFILE; no demo-only artifact will be published."
  exit 2
fi
bundle_id="${KEYDESK_BUNDLE_ID:-com.keydesk.local}"
if [[ ! "$bundle_id" =~ '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$' ]]; then
  print -u2 "Invalid KEYDESK_BUNDLE_ID."; exit 2
fi
swift build -c release
build_dir=$(swift build -c release --show-bin-path)
mkdir -p "$PWD/dist/bin"
stage_root=$(mktemp -d "$PWD/dist/.keydesk-stage.XXXXXX")
trap 'rm -rf "$stage_root"' EXIT
app_dir="$stage_root/Cellar.app"
final_app="$PWD/dist/Cellar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources"
cp -R Resources/ProviderLogos "$app_dir/Contents/Resources/ProviderLogos"
cp Resources/AppIcon/Cellar.icns "$app_dir/Contents/Resources/Cellar.icns"
cp -R Resources/en.lproj Resources/ko.lproj "$app_dir/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/"
cp "$build_dir/KeydeskDesktop" "$app_dir/Contents/MacOS/Cellar"
cp "$build_dir/keydesk" "$app_dir/Contents/Helpers/keydesk"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.keydesk.local</string>
<key>CFBundleName</key><string>Cellar</string>
<key>CFBundleDisplayName</key><string>Cellar</string>
<key>CFBundleIconFile</key><string>Cellar.icns</string>
<key>CFBundleExecutable</key><string>Cellar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7.8</string>
<key>CFBundleVersion</key><string>29</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ko</string></array>
<key>NSFaceIDUsageDescription</key><string>Cellar 금고를 열기 위해 인증합니다.</string>
</dict></plist>
PLIST
python3 - "$app_dir/Contents/Info.plist" "$bundle_id" <<'PYPLIST'
import pathlib, plistlib, sys
path=pathlib.Path(sys.argv[1]);info=plistlib.loads(path.read_bytes());info['CFBundleIdentifier']=sys.argv[2];path.write_bytes(plistlib.dumps(info))
PYPLIST
identity="${KEYDESK_SIGNING_IDENTITY:-}"
signing_mode="${KEYDESK_SIGNING_MODE:-auto}"
if [[ "$signing_mode" != auto && "$signing_mode" != adhoc ]]; then
  print -u2 "KEYDESK_SIGNING_MODE must be auto or adhoc."; exit 2
fi
if [[ "$signing_mode" == adhoc ]]; then
  if [[ "${KEYDESK_RELEASE:-0}" == 1 || -n "${KEYDESK_PROVISIONING_PROFILE:-}" ]]; then
    print -u2 "Ad-hoc signing cannot produce a real-vault release."; exit 2
  fi
  identity=""
elif [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | sed -nE '/Developer ID Application/s/.* ([A-F0-9]{40}) .*/\1/p' | head -1)
fi
if [[ -n "$identity" ]]; then
  if [[ ! "$identity" =~ '^[A-Fa-f0-9]{40}$' ]]; then
    print -u2 "KEYDESK_SIGNING_IDENTITY must be a certificate SHA-1."; exit 2
  fi
  identity="${(U)identity}"
  team=$(security find-identity -v -p codesigning | sed -nE "/$identity/s/.*\(([A-Z0-9]+)\)\".*/\1/p" | head -1)
  if [[ -z "$team" ]]; then
    print -u2 "Selected identity must be an installed Developer ID Application certificate SHA-1."; exit 2
  fi
  codesign --force --sign "$identity" --options runtime --timestamp --identifier "$bundle_id.cli" "$app_dir/Contents/Helpers/keydesk"
  if [[ -n "${KEYDESK_PROVISIONING_PROFILE:-}" ]]; then
    python3 scripts/verify-profile.py "$KEYDESK_PROVISIONING_PROFILE" "$team" "$identity" "$bundle_id"
    cp "$KEYDESK_PROVISIONING_PROFILE" "$app_dir/Contents/embedded.provisionprofile"
    entitlement="$stage_root/app-entitlements.plist"
    cat > "$entitlement" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>com.apple.application-identifier</key><string>$team.$bundle_id</string>
<key>com.apple.developer.team-identifier</key><string>$team</string>
<key>keychain-access-groups</key><array><string>$team.$bundle_id</string></array>
</dict></plist>
PLIST
    codesign --force --sign "$identity" --options runtime --timestamp --entitlements "$entitlement" "$app_dir"
  else
    codesign --force --sign "$identity" --options runtime --timestamp "$app_dir"
    print "Protected Keychain requires a matching provisioning profile. Real vault creation fails closed; demo is available."
  fi
  print "Developer ID signed with hardened runtime. Notarization is a separate step."
else
  if [[ "${KEYDESK_RELEASE:-0}" == 1 ]]; then
    print -u2 "Release requires a Developer ID Application signing identity."
    exit 2
  fi
  codesign --force --sign - --identifier "$bundle_id.cli" "$app_dir/Contents/Helpers/keydesk"
  codesign --force --sign - --identifier "$bundle_id" "$app_dir"
  print "Ad-hoc signed: protected Keychain access requires a Developer ID build."
fi
codesign --verify --strict "$app_dir/Contents/Helpers/keydesk"
codesign --verify --strict "$app_dir"
cp "$app_dir/Contents/Helpers/keydesk" "$stage_root/keydesk"
if [[ -d "$final_app" ]]; then mv "$final_app" "$stage_root/previous.app"; fi
if ! mv "$app_dir" "$final_app"; then
  if [[ -d "$stage_root/previous.app" ]]; then mv "$stage_root/previous.app" "$final_app"; fi
  exit 1
fi
mv "$stage_root/keydesk" "$PWD/dist/bin/keydesk"
print "Built: $final_app"
print "Bundled CLI: $final_app/Contents/Helpers/keydesk"
print "Development CLI copy: $PWD/dist/bin/keydesk"
