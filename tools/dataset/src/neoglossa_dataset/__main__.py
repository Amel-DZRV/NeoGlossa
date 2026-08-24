"""Run a dataset build step.

    python -m neoglossa_dataset parse
"""

import argparse
import collections
import csv
import os
import sys

from .parse import build
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

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
