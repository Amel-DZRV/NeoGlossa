"""Cross-check gender and plural against Wiktionary, and fill missing plurals.

Source: the `german-nouns` package, a Wiktionary-derived lexicon of ~100k
German nouns carrying `genus` and `nominativ plural`. (kaikki.org, the
extract the plan originally named, is not reachable from the build
environment; this is the same underlying data in a packaged form.)

The two fields get opposite treatment, because their disagreements have
opposite causes:

*Gender* — Goethe wins. Every disagreement observed is a homograph
collision, where Wiktionary's entry for the bare word is a different noun:
`der Schild` (shield) against `das Schild` (sign), `der Teil` against
`das Teil`, `der Alte` against `das Alter`. Goethe lists the sense actually
taught.

*Plural* — Wiktionary wins. Every disagreement observed is this module's
own suffix derivation failing on a Latin or Greek stem, where the ending is
replaced rather than appended: Datum -> Daten, not Datumen; Praktikum ->
Praktika, not Praktikuma. Wiktionary states the form directly instead of
deriving it, so it is the better value.

Both are recorded in conflicts.csv either way.
"""

import csv
import os
import re

csv.field_size_limit(10 ** 7)

GENUS_TO_ARTICLE = {"m": "der", "f": "die", "n": "das"}


def _nouns_csv_path():
    """Locate nouns.csv inside the installed package.

    german_nouns ships as a namespace package, so __file__ is None and the
    search locations have to be used instead.
    """
    import german_nouns

    for root in list(german_nouns.__path__):
        candidate = os.path.join(root, "nouns.csv")
        if os.path.exists(candidate):
            return candidate
    raise FileNotFoundError("nouns.csv not found; run: pip install german-nouns")


def load_wiktionary(path=None):
    """Return {lemma: {'gender': .., 'plural': ..}} keyed by headword."""
    path = path or _nouns_csv_path()
    index = {}
    with open(path, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            lemma = (row.get("lemma") or "").strip()
            if not lemma or lemma in index:
                continue  # first entry wins; later ones are rarer senses
            genus = (row.get("genus") or row.get("genus 1") or "").strip()
            plural = (row.get("nominativ plural") or row.get("nominativ plural 1") or "").strip()
            index[lemma] = {
                "gender": GENUS_TO_ARTICLE.get(genus, ""),
                "plural": plural,
            }
    return index


def _lookup(index, word):
    """Look a headword up, tolerating the source's parenthetical spellings.

    'die (E-)Mail' and 'das (Fahr)Rad' write two spellings into one entry;
    try the full form first, then each half.
    """
    if word in index:
        return index[word]
    if "(" in word:
        for candidate in (
            re.sub(r"[()]", "", word),          # (E-)Mail -> E-Mail
            re.sub(r"\([^)]*\)", "", word).strip(),  # (Fahr)Rad -> Rad
        ):
            if candidate and candidate in index:
                return index[candidate]
    return None


def verify(lexemes, index):
    """Annotate `lexemes` in place. Returns (conflicts, stats)."""
    conflicts = []
    stats = {"checked": 0, "absent": 0, "filled": 0, "corrected": 0, "gender_kept": 0}

    for entry in lexemes:
        if entry["pos"] != "noun":
            entry["verification"] = ""
            continue

        found = _lookup(index, entry["word"])
        if not found:
            entry["verification"] = "unverified"
            stats["absent"] += 1
            continue

        stats["checked"] += 1
        entry["verification"] = "verified"

        if found["gender"] and found["gender"] != entry["gender"]:
            # Homograph collision — keep Goethe, record it.
            stats["gender_kept"] += 1
            conflicts.append({
                "lemma": entry["lemma"], "field": "gender",
                "goetheValue": entry["gender"], "wiktionaryValue": found["gender"],
                "resolution": "kept Goethe (homograph)", "sourceLine": entry["sourceLine"],
            })

        plural = found["plural"]
        if not plural or entry["singularOnly"] in ("1", 1):
            continue

        if not entry["plural"]:
            entry["plural"] = plural
            entry["pluralPattern"] = entry["pluralPattern"] or "wiktionary"
            stats["filled"] += 1
        elif plural != entry["plural"]:
            # The derivation lost — take the stated form.
            conflicts.append({
                "lemma": entry["lemma"], "field": "plural",
                "goetheValue": entry["plural"], "wiktionaryValue": plural,
                "resolution": "took Wiktionary (derivation failed)",
                "sourceLine": entry["sourceLine"],
            })
            entry["plural"] = plural
            entry["pluralPattern"] = "wiktionary"
            stats["corrected"] += 1

    return conflicts, stats


def write_conflicts(conflicts, out_dir):
    path = os.path.join(out_dir, "conflicts.csv")
    fields = ["lemma", "field", "goetheValue", "wiktionaryValue", "resolution", "sourceLine"]
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerows(conflicts)
    return path
