#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Self-test of CaptureFixture and the e2e driver that does not need the app's capture code:
# the fixture's command channel, event log and menu items, then the e2e driver against fake
# apps (correct, wrong, and without an --e2e entry point). Builds first.
#
# Usage: scripts/e2e-selftest.sh [Debug|Release]

set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-Debug}"
make build CONFIG="$config"
app="$(scripts/app-path.sh "$config")"
driver="$(scripts/build-driver.sh --fakes)"
work="build/e2e-selftest/$(date +%Y%m%d-%H%M%S)"

exec "$driver" selftest --fixture "$(dirname "$app")/CaptureFixture.app" \
  --fakes "$PWD/build/e2e-tools" --work "$PWD/$work"
