#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the path of the built .app for a configuration (Debug or Release).
# The name comes from the build settings, so it follows Config/Base.xcconfig.

set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-Debug}"
name="$(xcodebuild -project DictApp.xcodeproj -target DictApp -configuration "$config" \
  -showBuildSettings 2>/dev/null | sed -n 's/^ *FULL_PRODUCT_NAME = //p')"
[ -n "$name" ] || { echo "app-path: could not read FULL_PRODUCT_NAME" >&2; exit 1; }
echo "$PWD/build/DerivedData/Build/Products/$config/$name"
