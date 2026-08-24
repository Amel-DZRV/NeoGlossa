"""Emit the read-only lexicon.sqlite the app bundles.

Only parts of speech that can produce a card are written: nouns, verbs and
prepositions. The word list's 625 'other' rows (adjectives, adverbs,
function words) have no card type in v1 — adjective endings are explicitly
out of scope — so they would be dead weight in a file the app only reads.
"""

import json
import os
import sqlite3

SCHEMA = """
CREATE TABLE lexeme (
  id            INTEGER PRIMARY KEY,
  lemma         TEXT NOT NULL,
  word          TEXT NOT NULL,
  pos           TEXT NOT NULL CHECK (pos IN ('noun','verb','preposition')),
  cefr          TEXT NOT NULL CHECK (cefr IN ('A1','A2')),
  glosses       TEXT NOT NULL,
  exampleDE     TEXT NOT NULL,
  exampleEN     TEXT NOT NULL,
  isCognate     INTEGER NOT NULL DEFAULT 0,
  isFalseFriend INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE noun_data (
  lexemeId      INTEGER PRIMARY KEY REFERENCES lexeme(id),
  gender        TEXT NOT NULL CHECK (gender IN ('der','die','das')),
  plural        TEXT,
  pluralPattern TEXT,
  singularOnly  INTEGER NOT NULL DEFAULT 0,
  pluralOnly    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE verb_data (
  lexemeId       INTEGER PRIMARY KEY REFERENCES lexeme(id),
  partizipII     TEXT NOT NULL,
  auxiliary      TEXT NOT NULL CHECK (auxiliary IN ('haben','sein')),
  praeteritum3sg TEXT,
  isSeparable    INTEGER NOT NULL DEFAULT 0,
  isIrregular    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE prep_data (
  lexemeId     INTEGER PRIMARY KEY REFERENCES lexeme(id),
  governedCase TEXT NOT NULL
                 CHECK (governedCase IN ('akkusativ','dativ','wechsel','genitiv'))
);

CREATE INDEX lexeme_pos_cefr ON lexeme(pos, cefr);
CREATE INDEX lexeme_word ON lexeme(word);
"""

CARD_POS = ("noun", "verb", "preposition")


def _int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def emit(lexemes, path):
    if os.path.exists(path):
        os.remove(path)

    conn = sqlite3.connect(path)
    conn.executescript(SCHEMA)

    counts = {"lexeme": 0, "noun_data": 0, "verb_data": 0, "prep_data": 0, "skipped": 0}
    next_id = 1

    for entry in lexemes:
        pos = entry["pos"]
        if pos not in CARD_POS:
            counts["skipped"] += 1
            continue

        glosses = entry.get("glosses") or "[]"
        if pos == "preposition":
            # A prepCase card prompts with the German word and expects the
            # case, so it needs no gloss.
            glosses = glosses or "[]"

        lexeme_id = next_id
        next_id += 1
        conn.execute(
            "INSERT INTO lexeme (id, lemma, word, pos, cefr, glosses, exampleDE,"
            " exampleEN, isCognate, isFalseFriend) VALUES (?,?,?,?,?,?,?,?,0,0)",
            (
                lexeme_id, entry["lemma"], entry["word"], pos, entry["cefr"],
                glosses, entry.get("exampleDE", ""), entry.get("exampleEN", ""),
            ),
        )
        counts["lexeme"] += 1

        if pos == "noun":
            conn.execute(
                "INSERT INTO noun_data (lexemeId, gender, plural, pluralPattern,"
                " singularOnly, pluralOnly) VALUES (?,?,?,?,?,?)",
                (
                    lexeme_id, entry["gender"], entry["plural"] or None,
                    entry["pluralPattern"] or None,
                    _int(entry.get("singularOnly")), _int(entry.get("pluralOnly")),
                ),
            )
            counts["noun_data"] += 1
        elif pos == "verb":
            # Without both a participle and an auxiliary there is no card to
            # ask, so the row is not written.
            if entry.get("partizipII") and entry.get("auxiliary"):
                conn.execute(
                    "INSERT INTO verb_data (lexemeId, partizipII, auxiliary,"
                    " praeteritum3sg, isSeparable, isIrregular) VALUES (?,?,?,?,?,?)",
                    (
                        lexeme_id, entry["partizipII"], entry["auxiliary"],
                        entry.get("praeteritum3sg") or None,
                        _int(entry.get("isSeparable")), _int(entry.get("isIrregular")),
                    ),
                )
                counts["verb_data"] += 1
        else:
            conn.execute(
                "INSERT INTO prep_data (lexemeId, governedCase) VALUES (?,?)",
                (lexeme_id, entry["governedCase"]),
            )
            counts["prep_data"] += 1

    conn.commit()
    conn.execute("VACUUM")
    conn.close()
    return counts
