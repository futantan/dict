# cloud-dict

The instant dictionary as a Cloudflare D1 database.
It holds the same data as the offline `build/dict/dict-en-zh.sqlite` built by `tools/build-dict`, and will later also hold AI-generated senses.

## Schema

`schema.sql` is schema 2 of `tools/build-dict` with one addition, and `meta.schema_version` is `3` in the cloud copy.
The offline sqlite and the Swift build tool stay at schema 2.

- `sense.model TEXT` is NULL for Wiktionary senses and the exact model ID for AI senses, for example `@cf/deepseek-ai/deepseek-v4-flash-0731`.
- `sense.source` takes a third value, `ai`, next to `zh` and `en`.
- A CHECK enforces `(source = 'ai') = (model IS NOT NULL)`.

The `meta` rows, including the CC BY-SA 4.0 attribution, are carried over unchanged.

## Export and verify locally

Neither step needs a Cloudflare account.

```sh
make dict                # if build/dict/dict-en-zh.sqlite is missing
make dict-cloud-export   # writes build/cloud-dict/data.sql
make dict-cloud-verify   # loads it into wrangler's local D1 and checks it
```

`export.mjs` writes multi-row INSERTs in primary-key order, each under D1's 100 KB statement limit, so the output is deterministic.
`verify.mjs` loads `schema.sql` and `data.sql` into a fresh local D1 under `build/cloud-dict/d1`, then compares row counts and the attribution with the source sqlite, checks `schema_version` and a sample entry, and probes the `model` CHECK.
The scripts need Node 22.13 or later for the built-in `node:sqlite`.
Wrangler is a pinned devDependency here; `make dict-cloud-verify` runs `npm ci` when needed, and nothing is installed globally.

## Creating the remote database

Credentials come from `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in the repo-root `.env`, which is never committed and never printed.
Run from `tools/cloud-dict`; if `--env-file` does not supply the credentials, export the two variables into the shell environment instead.

```sh
npx wrangler d1 create dict-en-zh --env-file ../../.env
```

Put the printed `database_id` into `wrangler.jsonc` in place of the placeholder, then load the schema and the data:

```sh
npx wrangler d1 execute dict-en-zh --remote --env-file ../../.env --file schema.sql
npx wrangler d1 execute dict-en-zh --remote --env-file ../../.env --file ../../build/cloud-dict/data.sql
```
