"""Derive a noun's plural form from the Goethe list's suffix marker.

The source encodes the plural as a marker appended after a comma:

    der Abend, -e     -> Abende      (suffix)
    die Mutter, ¨-    -> Mütter      (umlaut, no suffix)
    das Maedchen, -   -> Maedchen    (unchanged)
    die Brille, -n    -> Brillen

Two encodings for the umlaut appear in the source and both are handled: the
canonical '¨-e' form, and rows that spell the resulting vowel instead
('die Mutter, -ue' style, written '-ü' in the file).
"""

import re

UMLAUT = {"a": "ä", "o": "ö", "u": "ü", "A": "Ä", "O": "Ö", "U": "Ü"}

# Markers meaning "umlaut the stem, add nothing" that spell the result vowel
# rather than using the ¨ sign.
_SPELLED_UMLAUT = {"ä", "ö", "ü", "Ä", "Ö", "Ü"}

# Every dash-like character the source uses interchangeably.
_DASHES = "-–—‒"


class PluralError(ValueError):
    """The marker did not match any known pattern."""


def umlaut_stem(stem: str) -> str:
    """Umlaut the last umlautable vowel in `stem`.

    'au' is a single unit and becomes 'äu'; otherwise the last a/o/u is
    raised. Matches the spec's rule of applying it to the last such vowel.
    """
    matches = list(re.finditer(r"au|[aouAOU]", stem))
    if not matches:
        raise PluralError(f"no umlautable vowel in stem {stem!r}")
    m = matches[-1]
    v = m.group(0)
    if v.lower() == "au":
        rep = "äu" if v[0].islower() else "Äu"
    else:
        rep = UMLAUT[v]
    return stem[: m.start()] + rep + stem[m.end() :]


def normalise_marker(marker: str) -> str:
    """Reduce a raw marker to a single canonical form.

    The source carries three encodings for the umlaut plural and two ways of
    offering alternatives, so this collapses them before `derive_plural`
    interprets anything:

        -s/-n       alternatives      -> first one wins
        -ae, e      umlaut + suffix   -> canonical umlaut form
        -¨e         misplaced dash    -> canonical umlaut form
        -, -er      alternatives      -> first one wins
    """
    marker = re.sub(r"\(\d+\)\s*$", "", marker.strip())
    for d in _DASHES[1:]:
        marker = marker.replace(d, "-")

    # 'die Creme, -s/-n' and 'das Wort, -oe, er/-e' offer two plurals.
    marker = marker.split("/")[0].strip()

    if "," in marker:
        head, _, tail = marker.partition(",")
        head, tail = head.strip(), tail.strip()
        stripped = head.lstrip("-")
        if stripped in _SPELLED_UMLAUT and tail:
            # 'der Baum, -ae, e' -> umlaut plus the suffix after the comma.
            return "\u00a8-" + tail.lstrip("-")
        # 'der Ski, -, -er' -> take the first alternative.
        marker = head

    # 'die Ankunft, -¨e' puts the dash before the umlaut sign.
    if "\u00a8" in marker:
        marker = "\u00a8-" + marker.replace("\u00a8", "").lstrip("-")

    return marker.strip()


def derive_plural(stem: str, marker: str) -> str:
    """Apply `marker` to `stem` and return the plural form.

    Raises PluralError for anything unrecognised, so callers can log the row
    rather than silently emitting a wrong plural.
    """
    marker = normalise_marker(marker)
    if not marker:
        raise PluralError("empty marker")

    umlauted = False
    if marker.startswith("¨"):
        umlauted = True
        marker = marker[1:].strip()
    elif marker.lstrip("-") in _SPELLED_UMLAUT:
        # 'die Mutter, -ü' — the row spells the result instead of using ¨.
        return umlaut_stem(stem)

    suffix = marker.lstrip("-").strip()

    # A bare '-' (or nothing left after the umlaut sign) means no suffix.
    if suffix == "":
        return umlaut_stem(stem) if umlauted else stem

    if not re.fullmatch(r"[a-zäöüß]+", suffix):
        raise PluralError(f"unrecognised suffix {suffix!r}")

    base = umlaut_stem(stem) if umlauted else stem

    # '-n' on a stem already ending in 'e' just appends; '-en' after 'e'
    # would double it, which the source never intends.
    if suffix == "en" and base.endswith("e"):
        suffix = "n"
    return base + suffix
