"""Attach short English glosses to nouns and verbs.

A gloss is the answer on a recognition card: `der Tisch` -> `table`. The
Goethe list's English column is a translated sentence and cannot serve, so
glosses come from two learner decks built from the same Wortlisten, with a
translator's dictionary as fallback:

1. The Goethe A1 Anki deck (`anki_german_a1_vocab`), column 4.
2. The Goethe A2 deck (`A2_Wortliste_Goethe`), the `Wort_EN` field.
3. Ding (TU Chemnitz), `de-en.txt`, for anything the decks miss.

The decks come first because they carry the sense a learner needs, while
Ding is ordered alphabetically rather than by frequency and its first entry
is often obscure -- its only bare `Alter {n}` line glosses it "antiqueness"
rather than "age".

Harvesting is separate from attaching: `harvest` reads the external sources
and writes a vendored subset, `attach` reads only that subset, so a rebuild
needs no network and no clones.
"""

import csv
import glob
import json
import os
import re

MAX_WORDS = 3
MAX_SENSES = 2

_ARTICLE = re.compile(r"^(?:der|die|das)\s+", re.I)
_BRACKETED = re.compile(r"\{[^}]*\}|\[[^\]]*\]|\([^)]*\)|/[^/]*/")


def _headword(raw):
    """'die Ansage, -n' -> 'Ansage'."""
    return _ARTICLE.sub("", raw.split(",")[0].strip()).strip()


def clean_gloss(text):
    """Normalise one English sense, or return '' if unusable.

    Parentheticals are dropped rather than kept, so 'to be (switched) on'
    reduces to 'to be on' and stays inside the word cap.
    """
    text = _BRACKETED.sub(" ", text)
    text = text.replace("⇆", " ")
    text = " ".join(text.split()).strip(" .,;:!?")
    # The A1 deck writes '…' where a phrase entry has no single-word gloss.
    if not any(ch.isalpha() for ch in text):
        return ""
    if not text or len(text.split()) > MAX_WORDS:
        return ""
    return text.lower()


def _add(index, word, gloss, source):
    """Record one sense. A slash inside a gloss separates two of them."""
    if not word:
        return
    for part in gloss.split("/"):
        cleaned = clean_gloss(part)
        if not cleaned:
            continue
        bucket = index.setdefault(word, {"glosses": [], "source": source})
        if cleaned not in bucket["glosses"]:
            bucket["glosses"].append(cleaned)


def harvest_a1(path, index):
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 4:
                _add(index, _headword(parts[1]), parts[3], "goethe-a1-deck")


def harvest_a2(directory, index):
    for path in sorted(glob.glob(os.path.join(directory, "*.md"))):
        text = open(path, encoding="utf-8").read()
        de = re.search(r"### Wort_DE\n(.+?)\n", text)
        en = re.search(r"### Wort_EN\n(.+?)\n", text)
        if de and en:
            _add(index, _headword(de.group(1)), en.group(1), "goethe-a2-deck")


def harvest_ding(path, index, wanted):
    """Fill only `wanted` headwords, so the fallback never overrides a deck."""
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#") or "::" not in line:
                continue
            german, _, english = line.partition("::")
            heads = [clean_gloss(h) for h in german.split("|")[0].split(";")]
            senses = [s for s in (clean_gloss(x) for x in english.split("|")[0].split(";")) if s]
            if not senses:
                continue
            for head in german.split("|")[0].split(";"):
                head = _BRACKETED.sub("", head).strip()
                if head in wanted and head not in index:
                    _add(index, head, senses[0], "ding")


def write_index(index, path):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["word", "glosses", "source"])
        for word in sorted(index):
            entry = index[word]
            writer.writerow([
                word,
                json.dumps(entry["glosses"][:MAX_SENSES], ensure_ascii=False),
                entry["source"],
            ])


def read_index(path):
    index = {}
    with open(path, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            index[row["word"]] = {
                "glosses": json.loads(row["glosses"]),
                "source": row["source"],
            }
    return index


def attach(lexemes, index):
    """Set `glosses` on every noun and verb. Returns the list without one."""
    missing = []
    for entry in lexemes:
        if entry["pos"] not in ("noun", "verb"):
            entry["glosses"] = ""
            continue
        found = index.get(entry["word"])
        if found and found["glosses"]:
            entry["glosses"] = json.dumps(found["glosses"], ensure_ascii=False)
        else:
            entry["glosses"] = ""
            missing.append(entry)
    return missing
