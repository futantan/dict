// SPDX-License-Identifier: GPL-3.0-or-later

/// The migrations of `vocab.sqlite` (architecture 8.2); `migrations[n]` takes the file from
/// `PRAGMA user_version` n to n + 1. Only append: a shipped migration never changes.
let migrations = [
  """
  CREATE TABLE term (
    id           INTEGER PRIMARY KEY,
    language     TEXT NOT NULL,
    lemma        TEXT NOT NULL,
    lemma_key    TEXT NOT NULL,
    tier         TEXT NOT NULL DEFAULT 'seen' CHECK (tier IN ('seen', 'learning')),
    card_json    TEXT,
    card_version INTEGER,
    created_at   INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    UNIQUE (language, lemma_key)
  );

  CREATE TABLE encounter (
    id            INTEGER PRIMARY KEY,
    term_id       INTEGER NOT NULL REFERENCES term(id) ON DELETE CASCADE,
    kind          TEXT NOT NULL CHECK (kind IN ('read', 'produce')),
    surface       TEXT NOT NULL,
    sentence      TEXT,
    term_start    INTEGER,
    term_length   INTEGER,
    sense         TEXT,
    sentence_translation TEXT,
    source_kind   TEXT NOT NULL,
    source_app    TEXT,
    source_url    TEXT,
    day           TEXT NOT NULL,
    seen_at       INTEGER NOT NULL
  );
  CREATE INDEX encounter_term ON encounter (term_id, seen_at);
  CREATE INDEX encounter_day  ON encounter (day);

  CREATE TABLE sentence_event (
    id          INTEGER PRIMARY KEY,
    kind        TEXT NOT NULL
                CHECK (kind IN ('translated', 'corrected', 'improved', 'translated_out')),
    source      TEXT NOT NULL,
    result      TEXT NOT NULL,
    edits_json  TEXT,
    applied     INTEGER NOT NULL DEFAULT 0,
    source_lang TEXT NOT NULL,
    result_lang TEXT NOT NULL,
    source_app  TEXT,
    day         TEXT NOT NULL,
    created_at  INTEGER NOT NULL
  );
  CREATE INDEX sentence_event_day ON sentence_event (day);

  CREATE TABLE review_state (
    term_id  INTEGER PRIMARY KEY REFERENCES term(id) ON DELETE CASCADE,
    step     INTEGER NOT NULL,
    due_day  TEXT NOT NULL
  );

  CREATE TABLE review_log (
    id           INTEGER PRIMARY KEY,
    term_id      INTEGER NOT NULL REFERENCES term(id) ON DELETE CASCADE,
    encounter_id INTEGER REFERENCES encounter(id) ON DELETE SET NULL,
    rating       TEXT NOT NULL CHECK (rating IN ('again', 'good')),
    reviewed_at  INTEGER NOT NULL
  );
  CREATE INDEX review_log_term ON review_log (term_id, reviewed_at);
  """,
  // The day a term became 要学, for 生词本's 「本周新加」 and 「加入时间」. Terms already being
  // learnt get the day they were first met: the earliest it can be, and a day the user saw.
  """
  ALTER TABLE term ADD COLUMN learning_day TEXT;
  UPDATE term SET learning_day = (SELECT min(day) FROM encounter e WHERE e.term_id = term.id)
  WHERE tier = 'learning';
  """,
]
