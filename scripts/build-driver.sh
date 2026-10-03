#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compiles the e2e driver (scripts/driver) and, with --fakes, the fake apps used by its
# self-test (scripts/fake-dict) into build/e2e-tools. Rebuilds only when a source changed.
# Prints the driver's path.

set -euo pipefail
cd "$(dirname "$0")/.."

out="build/e2e-tools"
driver="$out/dict-driver"
mkdir -p "$out"

stale() { # target, sources...
  local target="$1"
  shift
  [ ! -e "$target" ] || [ -n "$(find "$@" -newer "$target" -print -quit)" ]
}

compile() { # output, then flags and sources
  local output="$1"
  shift
  xcrun swiftc -swift-version 6 -warnings-as-errors -O \
    -target "$(uname -m)-apple-macos15.0" -o "$output" "$@" >&2
}

fake_plist() { # variant
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>au.ibra.dict.e2e-fake.$1</string>
  <key>CFBundleName</key><string>FakeDict$1</string>
  <key>CFBundleExecutable</key><string>FakeDict</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
}

if stale "$driver" scripts/driver; then
  echo "build-driver: compiling dict-driver" >&2
  compile "$driver" scripts/driver/*.swift
fi

if [ "${1:-}" = "--fakes" ]; then
  for variant in Echo Wrong NoEntry; do
    app="$out/FakeDict$variant.app"
    if stale "$app/Contents/MacOS/FakeDict" scripts/fake-dict; then
      echo "build-driver: compiling FakeDict$variant.app" >&2
      mkdir -p "$app/Contents/MacOS"
      case "$variant" in
        Wrong) flags=(-D FAKE_WRONG) ;;
        NoEntry) flags=(-D FAKE_NO_ENTRY) ;;
        *) flags=() ;;
      esac
      compile "$app/Contents/MacOS/FakeDict" ${flags[@]+"${flags[@]}"} scripts/fake-dict/main.swift
      fake_plist "$variant" >"$app/Contents/Info.plist"
      codesign --force --sign - "$app" >/dev/null 2>&1
    fi
  done
fi

echo "$PWD/$driver"
