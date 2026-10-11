#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Writes build/dist/appcast.xml for one release archive with Sparkle's generate_appcast.
# The appcast lists only that archive, whose download URL is the GitHub release asset
# https://github.com/<owner>/dict/releases/download/<tag>/<zip>; the app reads the appcast
# from .../releases/latest/download/appcast.xml (DICT_UPDATE_FEED_URL).
# Refuses while Config/Base.xcconfig still has the OWNER placeholder or no public key, and
# checks that the archive's signature matches that public key.
#
# Usage: scripts/appcast.sh <zip> <tag> [<private-key-file>]
#   Without a key file, generate_appcast reads the private key from the login Keychain,
#   where Sparkle's generate_keys put it (Tantan's Mac only).

set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -ge 2 ] && [ $# -le 3 ] || {
  echo "usage: scripts/appcast.sh <zip> <tag> [<private-key-file>]" >&2
  exit 2
}
zip="$1" tag="$2" key_file="${3:-}"
[ -f "$zip" ] || { echo "appcast: no archive at $zip" >&2; exit 1; }

setting() {
  xcodebuild -project DictApp.xcodeproj -target DictApp -configuration Release \
    -showBuildSettings 2>/dev/null | sed -n "s/^ *$1 = //p"
}

feed="$(setting DICT_UPDATE_FEED_URL)"
public_key="$(setting DICT_UPDATE_PUBLIC_KEY)"
suffix="/releases/latest/download/appcast.xml"
case "$feed" in
  */OWNER/*)
    echo "appcast: DICT_UPDATE_FEED_URL still has the OWNER placeholder (Config/Base.xcconfig)" >&2
    exit 1 ;;
  https://github.com/*"$suffix") ;;
  *)
    echo "appcast: DICT_UPDATE_FEED_URL is not a GitHub latest-release appcast: $feed" >&2
    exit 1 ;;
esac
[ -n "$public_key" ] || {
  echo "appcast: DICT_UPDATE_PUBLIC_KEY is empty (Config/Base.xcconfig)" >&2
  exit 1
}
prefix="${feed%"$suffix"}/releases/download/$tag/"

bin="$(scripts/sparkle-bin.sh)"
# generate_appcast reads every archive in its directory, and merges into an appcast already
# at its output path: give it this archive alone and no old appcast.
stage="build/appcast-stage"
rm -rf "$stage" build/dist/appcast.xml
mkdir -p "$stage" build/dist
cp "$zip" "$stage/"
key_args=()
[ -z "$key_file" ] || key_args=(--ed-key-file "$key_file")
"$bin/generate_appcast" ${key_args[@]+"${key_args[@]}"} --download-url-prefix "$prefix" --maximum-deltas 0 \
  -o build/dist/appcast.xml "$stage"

signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' build/dist/appcast.xml | head -1)"
swift scripts/ed-key.swift verify "$public_key" "$zip" "$signature" >/dev/null || {
  echo "appcast: the archive's signature does not match DICT_UPDATE_PUBLIC_KEY" >&2
  exit 1
}
echo "appcast: build/dist/appcast.xml for $prefix$(basename "$zip")"
