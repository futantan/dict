#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Release app and zips it into build/dist/.
# Notarization runs only when DICT_NOTARY_PROFILE is set; see notarize() below.

set -euo pipefail
cd "$(dirname "$0")/.."

dist="build/dist"

build_release() {
  xcodebuild -project DictApp.xcodeproj -scheme DictApp -configuration Release \
    -derivedDataPath build/DerivedData -destination "platform=macOS,arch=$(uname -m)" \
    -quiet "$@" build
}

zip_app() {
  local app="$1" zip="$2"
  rm -f "$zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
}

# Notarization needs, and this machine does not have yet:
#   1. A "Developer ID Application" certificate in the keychain (an Apple Development
#      certificate cannot be notarized).
#   2. A notarytool keychain profile, created once with
#      `xcrun notarytool store-credentials <profile> --apple-id ... --team-id ...`,
#      whose name is passed in DICT_NOTARY_PROFILE.
notarize() {
  local app="$1" zip="$2"
  if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "package: cannot notarize: no Developer ID Application certificate" >&2
    exit 1
  fi
  build_release CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS=--timestamp
  zip_app "$app" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "$DICT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  zip_app "$app" "$zip"
}

build_release
app="$(scripts/app-path.sh Release)"
version="$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString)"
name="$(basename "$app" .app)"
mkdir -p "$dist"
zip="$dist/$name-$version.zip"

if [ -n "${DICT_NOTARY_PROFILE:-}" ]; then
  notarize "$app" "$zip"
else
  zip_app "$app" "$zip"
  echo "package: not notarized (set DICT_NOTARY_PROFILE to notarize; see scripts/package.sh)"
fi
echo "package: $zip"
