"""Run a dataset build step.

    python -m neoglossa_dataset parse
"""

import argparse
import collections
import csv
import os
import sys

from .parse import build
from .glosses import attach, harvest_a1, harvest_a2, harvest_ding, read_index, write_index
from .verify import load_wiktionary, verify, write_conflicts

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def cmd_parse(args):
    rows, logged = build(args.raw, args.out)
    nouns = [r for r in rows if r["pos"] == "noun"]
    by_pos = collections.Counter(r["pos"] for r in rows)

    print(f"lexemes           {len(rows)}")
    for pos, count in by_pos.most_common():
        print(f"  {pos:<15} {count}")
    print(f"nouns with plural {sum(1 for r in nouns if r['plural'])}")
    print(f"  singular-only   {sum(1 for r in nouns if r['singularOnly'])}")
    print(f"  needing lookup  {sum(1 for r in nouns if not r['plural'] and not r['singularOnly'])}")
    print(f"verbs with aux    {sum(1 for r in rows if r['auxiliary'])}")
    print(f"with example      {sum(1 for r in rows if r['exampleDE'])}")
    print(f"logged for review {len(logged)}  -> {os.path.join(args.out, 'unparsed.log')}")
    return 0


def cmd_verify(args):
    path = os.path.join(args.out, "lexemes.csv")
    with open(path, encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    index = load_wiktionary()
    print(f"wiktionary nouns  {len(index)}")
    conflicts, stats = verify(rows, index)

    fields = list(rows[0].keys())
    if "verification" not in fields:
        fields.append("verification")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    nouns = [r for r in rows if r["pos"] == "noun"]
    missing = sum(1 for r in nouns if not r["plural"] and r["singularOnly"] in ("0", 0))
    print(f"nouns checked     {stats['checked']}")
    print(f"  absent          {stats['absent']} (kept Goethe, marked unverified)")
    print(f"plurals filled    {stats['filled']}")
    print(f"plurals corrected {stats['corrected']}")
    print(f"gender kept       {stats['gender_kept']} (homograph collisions)")
    print(f"still no plural   {missing}")
    print(f"conflicts         {len(conflicts)} -> {write_conflicts(conflicts, args.out)}")
    return 0


def _load_lexemes(out_dir):
    with open(os.path.join(out_dir, "lexemes.csv"), encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _save_lexemes(rows, out_dir, extra):
    fields = list(rows[0].keys())
    for name in extra:
        if name not in fields:
            fields.append(name)
    with open(os.path.join(out_dir, "lexemes.csv"), "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def cmd_harvest_glosses(args):
    """Read the external gloss sources once and vendor the subset we need."""
    rows = _load_lexemes(args.out)
    wanted = {r["word"] for r in rows if r["pos"] in ("noun", "verb")}

    index = {}
    harvest_a1(args.a1, index)
    print(f"after A1 deck    {len(index)}")
    harvest_a2(args.a2, index)
    print(f"after A2 deck    {len(index)}")
    harvest_ding(args.ding, index, wanted)
    print(f"after Ding       {len(index)}")

    index = {w: e for w, e in index.items() if w in wanted}
    write_index(index, args.index)
    print(f"vendored         {len(index)} -> {args.index}")
    return 0


def cmd_gloss(args):
    rows = _load_lexemes(args.out)
    index = read_index(args.index)
    missing = attach(rows, index)
    _save_lexemes(rows, args.out, ["glosses"])

    path = os.path.join(args.out, "glosses_missing.csv")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["lemma", "pos", "cefr"])
        for entry in missing:
            writer.writerow([entry["lemma"], entry["pos"], entry["cefr"]])

    glossed = sum(1 for r in rows if r["glosses"])
    by_source = collections.Counter(
        index[r["word"]]["source"] for r in rows if r["glosses"] and r["word"] in index
    )
    print(f"glossed          {glossed}")
    for source, count in by_source.most_common():
        print(f"  {source:<16} {count}")
    print(f"missing          {len(missing)} -> {path}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(prog="neoglossa_dataset")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("parse", help="parse the raw word lists into lexemes.csv")
    p.add_argument("--raw", default=os.path.join(HERE, "data", "raw"))
    p.add_argument("--out", default=os.path.join(HERE, "data", "review"))
    p.set_defaults(func=cmd_parse)

    p = sub.add_parser("verify", help="cross-check gender and plural against Wiktionary")
    p.add_argument("--out", default=os.path.join(HERE, "data", "review"))
    p.set_defaults(func=cmd_verify)

    SC = os.environ.get("NEOGLOSSA_SOURCES", "")
    p = sub.add_parser("harvest-glosses", help="vendor glosses from the external sources")
    p.add_argument("--a1", default=os.path.join(SC, "anki_german_a1_vocab", "Goethe Institute A1 Wordlist.txt"))
    p.add_argument("--a2", default=os.path.join(SC, "A2_Wortliste_Goethe", "A2_Wortliste_Goethe"))
    p.add_argument("--ding", default=os.path.join(SC, "ding", "de-en.txt"))
    p.add_argument("--out", default=os.path.join(HERE, "data", "review"))
    p.add_argument("--index", default=os.path.join(HERE, "data", "raw", "glosses.csv"))
    p.set_defaults(func=cmd_harvest_glosses)

    p = sub.add_parser("gloss", help="attach the vendored glosses to lexemes.csv")
    p.add_argument("--out", default=os.path.join(HERE, "data", "review"))
    p.add_argument("--index", default=os.path.join(HERE, "data", "raw", "glosses.csv"))
    p.set_defaults(func=cmd_gloss)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
