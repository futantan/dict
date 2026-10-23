// SPDX-License-Identifier: GPL-3.0-or-later
//
// Loads schema.sql and data.sql into a fresh local D1 (wrangler --local, never remote) and
// checks it against the source sqlite. Exits non-zero on any mismatch.
// Usage: node verify.mjs <dict-en-zh.sqlite> <data.sql> <persist-dir>

import { DatabaseSync } from "node:sqlite";
import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

const [source, data, persist] = process.argv.slice(2).map((path) => path && resolve(path));
if (!source || !data || !persist) {
  console.error("usage: node verify.mjs <dict-en-zh.sqlite> <data.sql> <persist-dir>");
  process.exit(2);
}
const here = fileURLToPath(new URL(".", import.meta.url));
const wrangler = resolve(here, "node_modules/.bin/wrangler");

function d1(args) {
  return execFileSync(
    wrangler,
    ["d1", "execute", "dict-en-zh", "--local", "--persist-to", persist, ...args],
    { cwd: here, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 << 20 },
  );
}

function query(sql) {
  return JSON.parse(d1(["--json", "--command", sql]))[0].results;
}

// The error output of a statement that fails, or "" when it succeeds.
function error(sql) {
  try {
    d1(["--command", sql]);
    return "";
  } catch (failure) {
    return `${failure.stdout}${failure.stderr}`;
  }
}

let failures = 0;
function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures += 1;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${JSON.stringify(actual)}`);
  if (!ok) console.log(`     expected: ${JSON.stringify(expected)}`);
}

rmSync(persist, { recursive: true, force: true });
const started = Date.now();
d1(["--file", resolve(here, "schema.sql")]);
d1(["--file", data]);
console.log(`imported into local D1 in ${((Date.now() - started) / 1000).toFixed(1)} s`);

const db = new DatabaseSync(source, { readOnly: true });
for (const table of ["meta", "headword", "sense", "form"]) {
  const sql = `SELECT count(*) AS n FROM ${table}`;
  check(`${table} rows`, query(sql)[0].n, db.prepare(sql).get().n);
}
const attribution = "SELECT hex(value) AS v FROM meta WHERE key = 'attribution'";
const expected = db.prepare(attribution).get().v;
check(`attribution identical (${expected.length / 2} bytes)`, query(attribution)[0].v === expected, true);
db.close();

check(
  "schema_version",
  query("SELECT value FROM meta WHERE key = 'schema_version'")[0].value,
  "3",
);
check(
  "concept",
  query(
    "SELECT gloss, source, model FROM sense JOIN headword ON headword.id = headword_id " +
      "WHERE lemma_key = 'concept' ORDER BY ord LIMIT 1",
  ),
  [{ gloss: "概念、观念", source: "en", model: null }],
);

const probe = (model) =>
  "INSERT INTO sense (headword_id, ord, pos, gloss, source, hint, model) " +
  `SELECT id, 9999, 'noun', 'probe', 'ai', NULL, ${model} FROM headword WHERE lemma_key = 'concept'`;
const removeProbe = "DELETE FROM sense WHERE ord = 9999 AND gloss = 'probe'";
check(
  "ai sense without model rejected",
  error(probe("NULL")).includes("CHECK constraint failed"),
  true,
);
check("ai sense with model accepted", error(probe("'@cf/deepseek-ai/deepseek-v4-flash-0731'")), "");
check("probe row present", query("SELECT count(*) AS n FROM sense WHERE gloss = 'probe'")[0].n, 1);
query(removeProbe);
check("probe row removed", query("SELECT count(*) AS n FROM sense WHERE gloss = 'probe'")[0].n, 0);

if (failures > 0) {
  console.error(`${failures} check(s) failed`);
  process.exit(1);
}
console.log("all checks passed");
