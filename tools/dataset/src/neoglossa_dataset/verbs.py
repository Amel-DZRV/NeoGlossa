"""Fill Partizip II, auxiliary, Präteritum and irregularity for verbs.

Source: `german-verbs-database`, a Wiktionary-derived conjugation table
carrying Infinitive, Präteritum, Partizip II and Hilfsverb.

The auxiliary is not optional. `gefahren` on its own is useless — `ist`
against `hat` is the thing that actually gets missed.

Irregularity is derived rather than looked up: a weak verb forms its
Präteritum with -te and its Partizip II with -t (lieben, liebte, geliebt).
Anything that breaks either half is strong or mixed, and gets a card.
"""

import csv
import os


def load_verbs(path):
    """Return {infinitive: {...}} from the conjugation CSV."""
    index = {}
    with open(path, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            infinitive = (row.get("Infinitive") or "").strip()
            if not infinitive or infinitive in index:
                continue
            index[infinitive] = {
                "partizipII": (row.get("Partizip II") or "").strip(),
                "praeteritum": (row.get("Präteritum_ich") or "").strip(),
                "auxiliary": (row.get("Hilfsverb") or "").strip(),
            }
    return index


def is_irregular(praeteritum, partizip):
    """True unless the verb is weak in both halves.

    A separable verb writes its Präteritum with the prefix detached
    ("holte ab"), so the test looks at the stem rather than the last
    characters of the whole string — otherwise every separable weak verb
    reads as irregular.
    """
    if not praeteritum or not partizip:
        return False
    stem = praeteritum.split()[0]
    return not (stem.endswith("te") and partizip.endswith("t"))


def attach(lexemes, index):
    """Fill verb fields in place. Returns (filled, irregular, missing)."""
    filled = irregular = 0
    missing = []

    for entry in lexemes:
        entry.setdefault("praeteritum3sg", "")
        entry.setdefault("isIrregular", 0)
        if entry["pos"] != "verb":
            continue
        found = index.get(entry["word"])
        if not found:
            if not entry["partizipII"]:
                missing.append(entry)
            continue

        # The source list already supplied some of these; it is the closer
        # authority on the sense being taught, so it is not overwritten.
        entry["partizipII"] = entry["partizipII"] or found["partizipII"]
        entry["auxiliary"] = entry["auxiliary"] or (
            "haben" if found["auxiliary"] == "haben" else "sein" if found["auxiliary"] == "sein" else ""
        )
        # praesens3sg comes from the word list's sub-entries; the Präteritum
        # is a separate column that this source supplies.
        entry["praeteritum3sg"] = entry["praeteritum3sg"] or found["praeteritum"]

        if entry["partizipII"]:
            filled += 1
        if is_irregular(entry["praeteritum3sg"], entry["partizipII"]):
            entry["isIrregular"] = 1
            irregular += 1
        else:
            entry["isIrregular"] = 0

    return filled, irregular, missing
