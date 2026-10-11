#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Builds the Release app and zips it into build/dist/<name>-<version>-<build>.zip, the archive
# Sparkle updates from (scripts/appcast.sh). It is signed with the Apple Development
# certificate (Config/Base.xcconfig) and checked with codesign before zipping.
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

# Sparkle refuses an update whose signature does not hold up, so check before shipping one.
check_signature() {
  local app="$1"
  codesign --verify --deep --strict "$app"
  codesign -dv --verbose=2 "$app" 2>&1 | grep -E '^(Authority|TeamIdentifier)=' | head -2 | sed 's/^/package: /'
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
  check_signature "$app"
  zip_app "$app" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "$DICT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  zip_app "$app" "$zip"
}

build_release
app="$(scripts/app-path.sh Release)"
# The build copies build/dict into the app when it is there (project.yml); say which it was.
if [ -f "$app/Contents/Resources/dict-en-zh.sqlite" ]; then
  echo "package: the dictionary is included"
else
  echo "package: no dictionary in build/dict (run make dict): the app ships without it" >&2
fi
version="$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString)"
build="$(defaults read "$app/Contents/Info.plist" CFBundleVersion)"
name="$(basename "$app" .app)"
mkdir -p "$dist"
zip="$dist/$name-$version-$build.zip"

if [ -n "${DICT_NOTARY_PROFILE:-}" ]; then
  notarize "$app" "$zip"
else
  check_signature "$app"
  zip_app "$app" "$zip"
  echo "package: not notarized (set DICT_NOTARY_PROFILE to notarize; see scripts/package.sh)"
fi
echo "package: $zip"
