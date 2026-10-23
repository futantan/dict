-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Cloud dictionary schema (schema_version 3) for Cloudflare D1.
-- Schema 2 of tools/build-dict plus `sense.model`: NULL for Wiktionary senses, the exact
-- model ID (e.g. @cf/deepseek-ai/deepseek-v4-flash-0731) for AI senses (source = 'ai').

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE headword (
  id         INTEGER PRIMARY KEY,
  lemma      TEXT NOT NULL,
  lemma_key  TEXT NOT NULL UNIQUE,
  zipf       REAL,
  ipa_us     TEXT,
  ipa_uk     TEXT,
  wiki_title TEXT NOT NULL
);

CREATE TABLE sense (
  headword_id INTEGER NOT NULL REFERENCES headword(id),
  ord         INTEGER NOT NULL,
  pos         TEXT NOT NULL,
  gloss       TEXT NOT NULL,
  source      TEXT NOT NULL CHECK (source IN ('zh', 'en', 'ai')),
  hint        TEXT,
  model       TEXT,
  PRIMARY KEY (headword_id, ord),
  CHECK ((source = 'ai') = (model IS NOT NULL))
) WITHOUT ROWID;

CREATE TABLE form (
  form_key    TEXT NOT NULL,
  headword_id INTEGER NOT NULL REFERENCES headword(id),
  PRIMARY KEY (form_key, headword_id)
) WITHOUT ROWID;
