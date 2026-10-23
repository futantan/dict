// SPDX-License-Identifier: GPL-3.0-or-later
//
// Writes INSERT statements for the cloud schema (schema.sql) from the offline dictionary.
// Usage: node export.mjs <dict-en-zh.sqlite> <data.sql>
// Rows are emitted in primary-key order, so the output is deterministic. Rows are grouped
// into multi-row INSERTs, each kept under D1's 100 KB statement limit.

import { DatabaseSync } from "node:sqlite";
import { writeFileSync } from "node:fs";

const MAX_STATEMENT_BYTES = 90_000;
const CLOUD_SCHEMA_VERSION = "3";

const [source, target] = process.argv.slice(2);
if (!source || !target) {
  console.error("usage: node export.mjs <dict-en-zh.sqlite> <data.sql>");
  process.exit(2);
}

function literal(value) {
  if (value === null) return "NULL";
  if (typeof value === "number" || typeof value === "bigint") return String(value);
  if (value.includes("\0")) throw new Error(`NUL character in ${JSON.stringify(value)}`);
  return `'${value.replaceAll("'", "''")}'`;
}

function inserts(table, columns, rows) {
  const head = `INSERT INTO ${table} (${columns.join(", ")}) VALUES\n`;
  const statements = [];
  let tuples = [];
  let bytes = head.length;
  for (const row of rows) {
    const tuple = `(${columns.map((column) => literal(row[column])).join(", ")})`;
    const size = Buffer.byteLength(tuple) + 2;
    if (tuples.length > 0 && bytes + size > MAX_STATEMENT_BYTES) {
      statements.push(head + tuples.join(",\n") + ";");
      tuples = [];
      bytes = head.length;
    }
    if (head.length + size > MAX_STATEMENT_BYTES) throw new Error(`row too large in ${table}`);
    tuples.push(tuple);
    bytes += size;
  }
  if (tuples.length > 0) statements.push(head + tuples.join(",\n") + ";");
  return statements;
}

const db = new DatabaseSync(source, { readOnly: true });
const rows = (sql) => db.prepare(sql).all();

const meta = rows("SELECT key, value FROM meta ORDER BY key").map((row) =>
  row.key === "schema_version" ? { ...row, value: CLOUD_SCHEMA_VERSION } : row,
);
const senses = rows(
  "SELECT headword_id, ord, pos, gloss, source, hint FROM sense ORDER BY headword_id, ord",
).map((row) => ({ ...row, model: null }));

// Headwords come before senses and forms, which reference them (D1 enforces foreign keys).
const statements = [
  ...inserts("meta", ["key", "value"], meta),
  ...inserts(
    "headword",
    ["id", "lemma", "lemma_key", "zipf", "ipa_us", "ipa_uk", "wiki_title"],
    rows("SELECT * FROM headword ORDER BY id"),
  ),
  ...inserts("sense", ["headword_id", "ord", "pos", "gloss", "source", "hint", "model"], senses),
  ...inserts(
    "form",
    ["form_key", "headword_id"],
    rows("SELECT form_key, headword_id FROM form ORDER BY form_key, headword_id"),
  ),
];
db.close();

writeFileSync(target, statements.join("\n") + "\n");
console.log(`${target}: ${statements.length} statements`);
