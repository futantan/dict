#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Runs the Debug app against the local mock model, so trying it costs no tokens.
#   start  starts scripts/fake-model.py on 127.0.0.1:$PORT unless it is already up, quits
#          the running Debug app, and launches it with DICT_MOCK_MODEL set.
#   stop   stops the mock and quits the Debug app, which would otherwise keep calling it.
# The mock's request log is build/mock-model.log. `make run` afterwards uses the real model
# again: the variable lives only in the launched process.
#
# Usage: scripts/mock-model.sh start|stop

set -euo pipefail
cd "$(dirname "$0")/.."

PORT=8767
BASE_URL="http://127.0.0.1:$PORT/v1"
PID_FILE=build/mock-model.pid
LOG_FILE=build/mock-model.log

app="$(scripts/app-path.sh Debug)"

is_up() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/up")" = 404 ]
}

quit_app() {
  pkill -TERM -f "$app/Contents/MacOS/" || return 0
  for _ in $(seq 50); do
    pgrep -f "$app/Contents/MacOS/" >/dev/null || return 0
    sleep 0.1
  done
  echo "mock-model: the Debug app did not quit" >&2
  exit 1
}

case "${1:-}" in
  start)
    mkdir -p build
    if ! is_up; then
      nohup /usr/bin/python3 scripts/fake-model.py "$PORT" >>"$LOG_FILE" 2>&1 &
      echo $! >"$PID_FILE"
      for _ in $(seq 50); do is_up && break; sleep 0.1; done
      is_up || { echo "mock-model: no answer on port $PORT; see $LOG_FILE" >&2; exit 1; }
    fi
    quit_app
    open --env "DICT_MOCK_MODEL=$BASE_URL" "$app"
    echo "Debug app running against the mock model at $BASE_URL (log: $LOG_FILE)"
    ;;
  stop)
    quit_app
    if [ -f "$PID_FILE" ]; then
      kill "$(cat "$PID_FILE")" 2>/dev/null || true
      rm -f "$PID_FILE"
    fi
    if is_up; then
      echo "mock-model: something else still answers on port $PORT" >&2
      exit 1
    fi
    echo "mock model stopped"
    ;;
  *)
    echo "usage: $0 start|stop" >&2
    exit 2
    ;;
esac
