#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Cuts a release: builds and zips the Release app (scripts/package.sh), writes its appcast
# (scripts/appcast.sh), and publishes both as GitHub release v<MARKETING_VERSION> with gh.
# Installed copies find it through .../releases/latest/download/appcast.xml.
# With --dry-run it checks what it can and prints the commands without running them.
#
# Usage: scripts/release.sh [--dry-run] [<private-key-file>]
#   Without a key file, the appcast is signed with the key in the login Keychain.
#
# Before each release: raise CURRENT_PROJECT_VERSION (Sparkle compares it) and
# MARKETING_VERSION (it names the tag) in Config/Base.xcconfig, and commit.
#
# Once, on Tantan's Mac only (see Design/architecture.md 15.6):
#   1. "$(scripts/sparkle-bin.sh)/generate_keys" creates the EdDSA key in the login
#      Keychain and prints the public key; paste it as DICT_UPDATE_PUBLIC_KEY.
#      Back up the private key (generate_keys -x <file>): without it no installed copy can
#      be updated again.
#   2. Replace OWNER in DICT_UPDATE_FEED_URL with the GitHub account, and add the remote.
#   3. gh auth login.

set -euo pipefail
cd "$(dirname "$0")/.."

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi
key_file="${1:-}"

run() {
  if [ "$dry_run" = 1 ]; then
    printf 'release: would run:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Refuses for real; in a dry run says what would stop the release and carries on.
check() {
  local message="$1"
  shift
  "$@" && return 0
  if [ "$dry_run" = 1 ]; then
    echo "release: would stop: $message"
  else
    echo "release: $message" >&2
    exit 1
  fi
}

setting() {
  xcodebuild -project DictApp.xcodeproj -target DictApp -configuration Release \
    -showBuildSettings 2>/dev/null | sed -n "s/^ *$1 = //p"
}

xcodegen generate --quiet
version="$(setting MARKETING_VERSION)"
build="$(setting CURRENT_PROJECT_VERSION)"
name="$(setting DICT_APP_NAME)"
feed="$(setting DICT_UPDATE_FEED_URL)"
tag="v$version"
zip="build/dist/$name-$version-$build.zip"

clean_tree() { [ -z "$(git status --porcelain)" ]; }
feed_set() { case "$feed" in */OWNER/*) return 1 ;; *) return 0 ;; esac; }
key_set() { [ -n "$(setting DICT_UPDATE_PUBLIC_KEY)" ]; }
tag_free() { ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; }
has_gh() { command -v gh >/dev/null; }
has_remote() { git remote get-url origin >/dev/null 2>&1; }

check "the working tree has uncommitted changes" clean_tree
check "DICT_UPDATE_FEED_URL still has the OWNER placeholder" feed_set
check "DICT_UPDATE_PUBLIC_KEY is empty" key_set
check "tag $tag exists: raise MARKETING_VERSION" tag_free
check "gh is not installed" has_gh
check "there is no git remote origin" has_remote
[ -z "$key_file" ] || check "no private key file at $key_file" test -f "$key_file"

echo "release: $name $version ($build) as $tag"
run scripts/package.sh
if [ -n "$key_file" ]; then
  run scripts/appcast.sh "$zip" "$tag" "$key_file"
else
  run scripts/appcast.sh "$zip" "$tag"
fi
run git tag "$tag"
run git push origin "$tag"
run gh release create "$tag" "$zip" build/dist/appcast.xml --verify-tag --title "$name $version" \
  --notes "Drag $name to Applications, then open it. The first time, macOS blocks it once: open System Settings, Privacy & Security, and choose Open Anyway. Later versions install themselves."
