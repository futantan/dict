#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# `make matrix` (architecture 14.4): captures from TextEdit, Safari, Chrome (the user's own
# and an isolated cold instance) and an isolated VS Code through the app's `--e2e` entry
# point, writes Design/app-matrix.json and prints the differences from the previous run.
# Each app section holds /private/tmp/dict-ui.lock and restores the clipboard.
#
# Usage: scripts/matrix.sh [Debug|Release]
# Environment: MATRIX_ONLY=textedit,safari,chrome,chrome-cold,vscode limits the sections;
# MATRIX_APP and MATRIX_OUT override the app under test and the output file (driver tests).

set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-Debug}"
app="${MATRIX_APP:-$(scripts/app-path.sh "$config")}"
out="${MATRIX_OUT:-$PWD/Design/app-matrix.json}"
driver="$(scripts/build-driver.sh)"
work="build/matrix/$(date +%Y%m%d-%H%M%S)"

exec "$driver" matrix --app "$app" --pages "$PWD/Fixtures/CaptureFixture/Resources" \
  --out "$out" --work "$PWD/$work" ${MATRIX_ONLY:+--only "$MATRIX_ONLY"}
