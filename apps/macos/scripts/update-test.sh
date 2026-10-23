#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The whole Sparkle update cycle on this Mac, offline, with the Debug app and a throwaway key
# (Design/architecture.md 15.6). Everything lives in build/update-test/:
#   1. Builds the Debug app twice, as build 1 and build 2 (CURRENT_PROJECT_VERSION on the
#      xcodebuild line; the committed value stays 1), with the throwaway public key.
#   2. Zips build 2 and writes two appcasts for it with generate_appcast: a good one, and
#      one whose EdDSA signature belongs to another file; checks both signatures.
#   3. Serves feed/ on 127.0.0.1 with python3 -m http.server.
#   4. Installs build 1 into install/ (outside DerivedData), launches it with
#      DICT_UPDATE_FEED on the bad appcast and DICT_UPDATE_HEADLESS=1, and checks that it
#      refuses the update and stays on build 1.
#   5. Launches it again on the good appcast, waits for Sparkle to install and relaunch, and
#      checks: the installed bundle is build 2, the relaunched process logs
#      "version ... (2)" and "accessibility true", the copy has no quarantine attribute, and
#      it replaced build 1 in place (one app in install/, a different executable).
#   6. Quits the installed test app and stops the server.
#
# It launches and quits a copy of the Dev app (bundle id au.ibra.dict.dev), so it refuses to
# run while any other Dev app is running. Accessibility must already be granted to the Dev
# app; the throwaway builds share its signing identity, so the grant applies to them.
#
# Usage: scripts/update-test.sh [--prepare-only]
#   --prepare-only stops after step 3's check that the feed is served: nothing is launched.

set -euo pipefail
cd "$(dirname "$0")/.."

prepare_only=0
[ "${1:-}" = "--prepare-only" ] && prepare_only=1

root="$PWD/build/update-test"
port="${DICT_UPDATE_TEST_PORT:-8770}"
feed_url="http://127.0.0.1:$port"
bundle_id="au.ibra.dict.dev"
products="$root/DerivedData/Build/Products/Debug"
install="$root/install"
server_pid=""

fail() {
  echo "update-test: FAIL: $1" >&2
  exit 1
}

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  # Only the copy in install/, never another Dev app.
  pkill -TERM -f "$install/[^/]*/Contents/MacOS/" 2>/dev/null || true
}
trap cleanup EXIT

build_version() {
  local version="$1" public_key="$2"
  xcodebuild -project DictApp.xcodeproj -scheme DictApp -configuration Debug \
    -derivedDataPath "$root/DerivedData" \
    -clonedSourcePackagesDirPath build/DerivedData/SourcePackages \
    -destination "platform=macOS,arch=$(uname -m)" -quiet \
    CURRENT_PROJECT_VERSION="$version" DICT_UPDATE_PUBLIC_KEY="$public_key" build
  local app
  app="$(find "$products" -maxdepth 1 -name '*.app' ! -name 'CaptureFixture.app' | head -1)"
  [ -n "$app" ] || fail "no app in $products"
  rm -rf "$root/v$version"
  mkdir -p "$root/v$version"
  ditto "$app" "$root/v$version/$(basename "$app")"
}

bundle_version() { plutil -extract CFBundleVersion raw -o - "$1/Contents/Info.plist"; }

edSignature() { sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$1" | head -1; }

# The pids of the installed app itself (not the helpers inside it), whatever its name.
installed_pids() { pgrep -f "$install/[^/]*/Contents/MacOS/" || true; }
running() { [ -n "$(installed_pids)" ]; }
stopped() { ! running; }

logged() {
  log show --info --style compact --start "$1" --predicate "subsystem == \"$bundle_id\"" \
    | grep -E "$2" >/dev/null
}
refusal_logged() { logged "$start" 'headless: error|update aborted'; }
accessibility_logged() { logged "$start" 'accessibility true'; }

wait_for() {
  local seconds="$1"
  shift
  for _ in $(seq "$((seconds * 5))"); do
    "$@" && return 0
    sleep 0.2
  done
  return 1
}

update_log() {
  log show --info --style compact --start "$1" \
    --predicate "subsystem == \"$bundle_id\" AND (category == \"update\" OR category == \"ui\")"
}

launch() {
  local appcast="$1"
  open -n -g --env DICT_UPDATE_FEED="$feed_url/$appcast" --env DICT_UPDATE_HEADLESS=1 \
    --env DICT_MOCK_MODEL=http://127.0.0.1:9/v1 "$app" --args --no-onboarding
}

quit_installed() {
  pkill -TERM -f "$install/[^/]*/Contents/MacOS/" 2>/dev/null || return 0
  wait_for 10 stopped || fail "the test app did not quit"
}

# --- 0. Nothing else may be using the Dev bundle id.
if [ "$prepare_only" = 0 ]; then
  others="$(pgrep -fl 'Dict Dev.app/Contents/MacOS/' | grep -v -F "$install/" || true)"
  [ -z "$others" ] || fail "another Dev app is running; quit it first:
$others"
fi

# --- 1. Key and the two builds.
xcodegen generate --quiet
rm -rf "$root/feed" "$root/key"
mkdir -p "$root/feed" "$root/key"
public_key="$(swift scripts/ed-key.swift generate "$root/key/ed-private.txt")"
echo "update-test: throwaway public key $public_key"
build_version 1 "$public_key"
build_version 2 "$public_key"
name="$(basename "$(find "$root/v1" -maxdepth 1 -name '*.app' | head -1)")"
[ "$(bundle_version "$root/v1/$name")" = 1 ] || fail "build 1 is not CFBundleVersion 1"
[ "$(bundle_version "$root/v2/$name")" = 2 ] || fail "build 2 is not CFBundleVersion 2"
for version in 1 2; do
  codesign --verify --deep --strict "$root/v$version/$name" || fail "build $version signature"
done
[ "$(codesign -d -r- "$root/v1/$name" 2>&1 | grep designated)" = \
  "$(codesign -d -r- "$root/v2/$name" 2>&1 | grep designated)" ] \
  || fail "the two builds have different designated requirements"

# --- 2. Archive and appcasts.
zip="$root/feed/${name%.app}-2.zip"
ditto -c -k --sequesterRsrc --keepParent "$root/v2/$name" "$zip"
bin="$(scripts/sparkle-bin.sh)"
"$bin/generate_appcast" --ed-key-file "$root/key/ed-private.txt" \
  --download-url-prefix "$feed_url/" --maximum-deltas 0 -o "$root/feed/appcast.xml" "$root/feed"
good="$(edSignature "$root/feed/appcast.xml")"
[ -n "$good" ] || fail "the appcast has no sparkle:edSignature"
swift scripts/ed-key.swift verify "$public_key" "$zip" "$good"
# A signature that is valid, but for another file.
echo "not the update" >"$root/key/other.bin"
bad="$("$bin/sign_update" --ed-key-file "$root/key/ed-private.txt" -p "$root/key/other.bin")"
sed "s|sparkle:edSignature=\"$good\"|sparkle:edSignature=\"$bad\"|" "$root/feed/appcast.xml" \
  > "$root/feed/appcast-bad.xml"
[ "$(edSignature "$root/feed/appcast-bad.xml")" = "$bad" ] || fail "could not write appcast-bad"
if swift scripts/ed-key.swift verify "$public_key" "$zip" "$bad" 2>/dev/null; then
  fail "the bad signature verifies"
fi

# --- 3. Serve.
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$root/feed" \
  >"$root/server.log" 2>&1 &
server_pid=$!
wait_for 10 curl -sf -o /dev/null "$feed_url/appcast.xml" || fail "the feed is not served"
echo "update-test: serving $feed_url/appcast.xml and appcast-bad.xml"
if [ "$prepare_only" = 1 ]; then
  echo "update-test: prepared; nothing launched"
  exit 0
fi

# --- 4. A bad signature is refused.
rm -rf "$install"
mkdir -p "$install"
app="$install/$name"
ditto "$root/v1/$name" "$app"
old_executable_hash="$(shasum -a 256 "$app/Contents/MacOS/${name%.app}" | cut -d' ' -f1)"
start="$(date '+%Y-%m-%d %H:%M:%S')"
launch appcast-bad.xml
wait_for 60 refusal_logged || fail "no refusal logged for the bad signature"
sleep 2
[ "$(bundle_version "$app")" = 1 ] || fail "the bad signature was installed"
running || fail "the app quit after refusing the update"
echo "update-test: bad signature refused; still build 1"
quit_installed

# --- 5. A good update installs and relaunches.
start="$(date '+%Y-%m-%d %H:%M:%S')"
launch appcast.xml
wait_for 30 running || fail "build 1 did not start"
first_pid="$(installed_pids | head -1)"
relaunched() {
  [ "$(bundle_version "$app" 2>/dev/null)" = 2 ] || return 1
  local pid
  pid="$(installed_pids | head -1)"
  [ -n "$pid" ] && [ "$pid" != "$first_pid" ]
}
wait_for 180 relaunched || fail "build 2 was not installed and relaunched"
wait_for 30 accessibility_logged || fail "the relaunched app does not log accessibility true"
log="$(update_log "$start")"
grep -q 'version .* (2)' <<<"$log" || fail "the relaunched app does not log build 2"
grep -q 'headless: found' <<<"$log" || fail "no headless phases logged"
if xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
  fail "the installed update is quarantined"
fi
[ "$(find "$install" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')" = 1 ] \
  || fail "install/ does not hold exactly one app"
new_executable_hash="$(shasum -a 256 "$app/Contents/MacOS/${name%.app}" | cut -d' ' -f1)"
[ "$new_executable_hash" != "$old_executable_hash" ] || fail "the executable was not replaced"
codesign --verify --deep --strict "$app" || fail "the installed update's signature"
echo "$log" | grep -e 'update' -e 'started' | sed 's/^/update-test: log: /'

# --- 6.
quit_installed
echo "update-test: PASS: build 1 refused a bad signature, then updated itself to build 2"
