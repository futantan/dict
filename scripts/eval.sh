#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# `make eval SUITE=<suite> RUNS=<n>`: runs the prompt evaluation against the real model
# (architecture 14.5). Reads OPENAI_API_KEY from the repository's .env into DictEval's
# environment only; the key is never printed. Exits non-zero when any invariant falls below
# the pass threshold, or when DictEval cannot run.
#
# Extra DictEval flags (for example `--model` or `--max-cost`) can be passed in EVAL_ARGS.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$root/.env"

if [[ -z "${SUITE:-}" ]]; then
  echo "make eval: SUITE is required (direction, injection, fallback or all)" >&2
  exit 2
fi
runs="${RUNS:-}"
runs="${runs:-10}"

if [[ ! -f "$env_file" ]]; then
  echo "make eval: $env_file not found; it must define OPENAI_API_KEY" >&2
  exit 2
fi
# Take the last OPENAI_API_KEY= line, allowing `export` and surrounding quotes. Never echoed.
key="$(sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY=[[:space:]]*//p' "$env_file" \
  | tail -n 1 | sed -E 's/^"(.*)"[[:space:]]*$/\1/; s/^'"'"'(.*)'"'"'[[:space:]]*$/\1/')"
if [[ -z "$key" ]]; then
  echo "make eval: OPENAI_API_KEY is not set in $env_file" >&2
  exit 2
fi

# Build first so compiler output does not mix with the report.
swift build -c release --package-path "$root/Packages/DictCore" --product DictEval
bin="$(swift build -c release --package-path "$root/Packages/DictCore" --show-bin-path)"

# shellcheck disable=SC2086  # EVAL_ARGS is split into separate flags on purpose.
OPENAI_API_KEY="$key" "$bin/DictEval" --suite "$SUITE" --runs "$runs" ${EVAL_ARGS:-}
