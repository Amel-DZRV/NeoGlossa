"""Parse the Goethe A1/A2 TSVs into one structured row per lexeme.

Input rows look like:

    der Termin, -e   Am besten machen wir sofort einen Termin.   It's best ...
    abgeben          Ich muss meinen Schluessel abgeben.         I have to ...
    abgeben(2)       gibt ab                                     He/She hands in.
    abgeben(3)       hat abgegeben                               has handed in.

Sub-entries suffixed (2), (3) belong to the base lemma. For verbs they carry
the present 3sg and the auxiliary + Partizip II rather than a sentence, which
is where the verb table comes from.
"""

import csv
import glob
import os
import re
from collections import OrderedDict

from .plural import PluralError, derive_plural

ARTICLES = ("der", "die", "das")

DATIVE = {"mit", "nach", "bei", "von", "zu", "aus", "seit", "gegenüber"}
ACCUSATIVE = {"durch", "für", "gegen", "ohne", "um"}
WECHSEL = {"in", "an", "auf", "über", "unter", "neben", "zwischen", "vor", "hinter"}
GENITIVE = {"wegen", "außerhalb", "innerhalb", "während", "trotz", "statt"}

PREPOSITIONS = {}
for _set, _case in (
    (DATIVE, "dativ"),
    (ACCUSATIVE, "akkusativ"),
    (WECHSEL, "wechsel"),
    (GENITIVE, "genitiv"),
):
    for _w in _set:
        PREPOSITIONS[_w] = _case

# Sub-entry field carrying auxiliary + Partizip II, e.g. "hat abgegeben".
AUX_PARTICIPLE = re.compile(r"^(hat|ist)\s+([\wäöüßÄÖÜ]+)$")
# Sub-entry field carrying a present-tense 3sg, e.g. "gibt ab" or "fährt".
PRESENT_3SG = re.compile(r"^[a-zäöüß]+(\s+[a-zäöüß]+)?$")

SEPARABLE_PREFIXES = (
    "ab", "an", "auf", "aus", "bei", "ein", "fest", "her", "hin", "los", "mit",
    "nach", "vor", "weg", "zu", "zurück", "zusammen",
)


# 'der Partner, -/ die Partnerin, -nen' is two lexemes on one line. Only a
# slash followed by an article starts a second one; 'der Club, -s / Klub, -s'
# is an alternate spelling and stays whole.
_PAIRED = re.compile(r"/\s*(?=(?:der|die|das)\s)")


def split_paired(lemma):
    """Split a masculine/feminine pair into separate lemmas."""
    return [part.strip() for part in _PAIRED.split(lemma) if part.strip()]


def _strip_subentry(lemma):
    m = re.match(r"^(.*?)\((\d+)\)\s*$", lemma.strip())
    if m:
        return m.group(1).strip(), int(m.group(2))
    return lemma.strip(), 1


def read_rows(raw_dir):
    """Yield one dict per source row, sub-entry suffix already split off."""
    for level in ("a1", "a2"):
        for path in sorted(glob.glob(os.path.join(raw_dir, level, "*.tsv"))):
            with open(path, encoding="utf-8") as fh:
                for lineno, line in enumerate(fh, 1):
                    line = line.rstrip("\n")
                    if not line.strip():
                        continue
                    parts = line.split("\t")
                    if parts[0].strip() == "german word":
                        continue
                    while len(parts) < 3:
                        parts.append("")
                    lemma, sense = _strip_subentry(parts[0])
                    if not lemma:
                        continue
                    yield {
                        "cefr": level.upper(),
                        "lemma": lemma,
                        "sense": sense,
                        "f2": parts[1].strip(),
                        "f3": parts[2].strip(),
                        "source": f"{level}/{os.path.basename(path)}:{lineno}",
                        "sourceLine": line,
                    }


def classify(lemma):
    """Return (pos, headword) for a raw lemma string."""
    low = lemma.lower()
    for art in ARTICLES:
        if low.startswith(art + " "):
            return "noun", lemma
    bare = re.sub(r"^\(sich\)\s*", "", lemma).strip()
    if bare.lower() in PREPOSITIONS:
        return "preposition", bare
    if re.fullmatch(r"[a-zäöüß]+", bare.lower()) and bare.lower().endswith(("en", "ern", "eln")):
        return "verb", bare
    return "other", bare


# Number markers the source appends to the headword, in every spelling it
# uses: '(Sg.)', '(Sing.)', '(Pl.)', '(pl.)'. They must come off the lemma or
# they end up in the key and split one noun into several.
_SINGULAR_ONLY = re.compile(r"\(\s*[Ss](?:g|ing)\.?\s*\)")
_PLURAL_ONLY = re.compile(r"\(\s*[Pp]l\.?\s*\)")


def parse_noun(lemma):
    """Split 'der Termin, -e' into gender, headword, plural, pattern, flags."""
    head = lemma
    singular_only = bool(_SINGULAR_ONLY.search(head))
    plural_only = bool(_PLURAL_ONLY.search(head))
    head = _PLURAL_ONLY.sub("", _SINGULAR_ONLY.sub("", head)).strip()

    marker = None
    if "," in head:
        head, marker = head.split(",", 1)
        head, marker = head.strip(), marker.strip()

    gender, _, word = head.partition(" ")
    # Collapse any internal or trailing whitespace: 'der Wagen, – ' leaves a
    # trailing space that would otherwise miss every dictionary lookup.
    gender, word = gender.lower(), " ".join(word.split())

    plural = None
    pattern = None
    error = None
    if marker and not singular_only:
        pattern = marker
        try:
            plural = derive_plural(word, marker)
        except PluralError as exc:
            error = str(exc)
    return {
        "gender": gender,
        "word": word,
        "plural": plural,
        "pluralPattern": pattern,
        "singularOnly": singular_only,
        "pluralOnly": plural_only,
        "error": error,
    }


def _blank_entry(head, pos, cefr, source_line):
    return {
        "lemma": head,
        "pos": pos,
        "cefr": cefr,
        "gender": "",
        "word": head,
        "plural": "",
        "pluralPattern": "",
        "singularOnly": 0,
        "pluralOnly": 0,
        "governedCase": "",
        "partizipII": "",
        "auxiliary": "",
        "praesens3sg": "",
        "isSeparable": 0,
        "exampleDE": "",
        "exampleEN": "",
        "sourceLine": source_line,
    }


def _ingest(row, lexemes, unparsed):
    """Fold one source row (already split to a single lemma) into `lexemes`."""
    pos, head = classify(row["lemma"])

    # Nouns key on gender + word, never on the raw lemma: the same noun
    # appears under several plural markers across the source, and keying on
    # the raw string emits one lexeme per spelling.
    noun = parse_noun(head) if pos == "noun" else None
    key = (pos, noun["gender"], noun["word"].lower()) if noun else (pos, head.lower())
    entry = lexemes.get(key)

    if entry is not None and noun:
        entry["singularOnly"] = entry["singularOnly"] or int(noun["singularOnly"])
        entry["pluralOnly"] = entry["pluralOnly"] or int(noun["pluralOnly"])
        # Second sighting of a known noun: fill a gap, or record a genuine
        # disagreement for the Wiktionary cross-check to settle.
        if noun["plural"] and not entry["plural"]:
            entry["plural"] = noun["plural"]
            entry["pluralPattern"] = noun["pluralPattern"] or ""
        elif noun["plural"] and noun["plural"] != entry["plural"]:
            unparsed.append((
                row["source"], row["sourceLine"],
                f"plural disagreement: {entry['plural']} vs {noun['plural']}",
            ))

    if entry is None:
        entry = lexemes[key] = _blank_entry(head, pos, row["cefr"], row["sourceLine"])
        if noun:
            if noun["error"]:
                unparsed.append((row["source"], row["sourceLine"], noun["error"]))
            entry.update(
                lemma=f"{noun['gender']} {noun['word']}".strip(),
                word=noun["word"],
                gender=noun["gender"],
                plural=noun["plural"] or "",
                pluralPattern=noun["pluralPattern"] or "",
                singularOnly=int(noun["singularOnly"]),
                pluralOnly=int(noun["pluralOnly"]),
            )
        elif pos == "preposition":
            entry["governedCase"] = PREPOSITIONS[head.lower()]
        elif pos == "verb":
            bare = head.lower()
            entry["isSeparable"] = int(
                any(bare.startswith(pre) for pre in SEPARABLE_PREFIXES) and len(bare) > 5
            )
    elif row["cefr"] == "A1":
        entry["cefr"] = "A1"  # earliest level wins

    aux = AUX_PARTICIPLE.match(row["f2"])
    if aux and pos == "verb":
        entry["auxiliary"] = "haben" if aux.group(1) == "hat" else "sein"
        entry["partizipII"] = aux.group(2)
    elif row["sense"] > 1 and pos == "verb" and PRESENT_3SG.match(row["f2"]):
        entry["praesens3sg"] = entry["praesens3sg"] or row["f2"]
    elif not entry["exampleDE"] and " " in row["f2"] and row["f3"]:
        entry["exampleDE"] = row["f2"]
        entry["exampleEN"] = row["f3"]


def build(raw_dir, out_dir):
    lexemes = OrderedDict()
    unparsed = []

    for source_row in read_rows(raw_dir):
        for variant in split_paired(source_row["lemma"]):
            _ingest(dict(source_row, lemma=variant), lexemes, unparsed)

    os.makedirs(out_dir, exist_ok=True)
    fields = list(_blank_entry("", "", "", "").keys())
    with open(os.path.join(out_dir, "lexemes.csv"), "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for entry in lexemes.values():
            writer.writerow(entry)

    with open(os.path.join(out_dir, "unparsed.log"), "w", encoding="utf-8") as fh:
        for src, line, err in unparsed:
            fh.write(f"{src}\t{err}\t{line}\n")

    return list(lexemes.values()), unparsed
