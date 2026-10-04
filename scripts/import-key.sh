#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# `make import-key`: saves OPENAI_API_KEY from the repository's .env into the Debug app's
# own Keychain item (service au.ibra.dict.dev.model, account openai) and selects OpenAI with
# MODEL (default gpt-6-luna) in its preferences. The app's debug entry point writes both
# through the Settings window's own path, so the item belongs to Dict Dev and reading it
# later never shows a Keychain dialog. The key goes through a pipe only: never a command
# line argument, an environment variable, a file or the output.
#
# Usage: scripts/import-key.sh [model]

set -euo pipefail
cd "$(dirname "$0")/.."

env_file=".env"
model="${1:-gpt-6-luna}"
app="$(scripts/app-path.sh Debug)"
binary="$app/Contents/MacOS/$(basename "$app" .app)"

if [[ ! -f "$env_file" ]]; then
  echo "import-key: $env_file not found; it must define OPENAI_API_KEY" >&2
  exit 2
fi
if ! grep -qE '^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY=' "$env_file"; then
  echo "import-key: OPENAI_API_KEY is not set in $env_file" >&2
  exit 2
fi

# The same extraction as scripts/eval.sh: the last line, `export` and quotes allowed.
sed -n -E 's/^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY=[[:space:]]*//p' "$env_file" \
  | tail -n 1 | sed -E 's/^"(.*)"[[:space:]]*$/\1/; s/^'"'"'(.*)'"'"'[[:space:]]*$/\1/' \
  | "$binary" --import-api-key openai --model "$model"
