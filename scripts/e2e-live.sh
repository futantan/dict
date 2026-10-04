#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# `make e2e-live`: the "read" shortcut path with the real model in CaptureFixture, TextEdit,
# Safari and the user's Chrome (scripts/driver/Live.swift). Needs the network and the Debug
# app's own Keychain key (`make import-key`); each run makes about 15 short model calls.
# The driver holds /private/tmp/dict-ui.lock per section and restores the clipboard.
#
# Usage: scripts/e2e-live.sh
# Environment: LIVE_ONLY=fixture,textedit,safari,chrome limits the sections; LIVE_RUNS sets
# how many times TextEdit's sentence is read for the latency medians (default 10).

set -euo pipefail
cd "$(dirname "$0")/.."

app="$(scripts/app-path.sh Debug)"
driver="$(scripts/build-driver.sh)"
work="build/e2e-live/$(date +%Y%m%d-%H%M%S)"

exec "$driver" live --app "$app" --fixture "$(dirname "$app")/CaptureFixture.app" \
  --pages "$PWD/Fixtures/CaptureFixture/Resources" --work "$PWD/$work" \
  ${LIVE_ONLY:+--only "$LIVE_ONLY"} --runs "${LIVE_RUNS:-10}"
