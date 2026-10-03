#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# `make e2e` (architecture 14.3): runs Fixtures/E2E/scenarios.json against CaptureFixture
# through the app's `--e2e` entry point. The driver holds /private/tmp/dict-ui.lock while it
# takes focus or uses the clipboard, and restores the clipboard afterwards.
# Exit status: 0 passed, 1 failed, 2 skipped (the app has no --e2e entry point yet), 3 error.
#
# Usage: scripts/e2e.sh [Debug|Release]

set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-Debug}"
app="$(scripts/app-path.sh "$config")"
driver="$(scripts/build-driver.sh)"
work="build/e2e/$(date +%Y%m%d-%H%M%S)"

exec "$driver" e2e --app "$app" --fixture "$(dirname "$app")/CaptureFixture.app" \
  --scenarios Fixtures/E2E/scenarios.json --work "$PWD/$work"
