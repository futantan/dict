#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the directory of Sparkle's command-line tools (generate_appcast, sign_update), which
# come with the Sparkle package that `make build` resolves into build/DerivedData.

set -euo pipefail
cd "$(dirname "$0")/.."

bin="$PWD/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
[ -x "$bin/generate_appcast" ] || {
  echo "sparkle-bin: no Sparkle tools in $bin (run make build)" >&2
  exit 1
}
echo "$bin"
