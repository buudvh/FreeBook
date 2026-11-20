"""English word -> v2 tokens.

Order: lexicon, CamelCase/acronym split, hyphen split, inflection (-'s -s -es -ed -ing -er -ly)
on a known base, two-part compound, learned letter-to-sound. Short all-caps words that are not
in the lexicon are spelled with letter names. Compounds keep one primary stress (the first part's).
"""

from __future__ import annotations

import functools
import re

from .cmudict import arpabet_to_tokens, load_cmudict
from .lts import load_lts

LETTERS = {
    "a": "EY1", "b": "B IY1", "c": "S IY1", "d": "D IY1", "e": "IY1", "f": "EH1 F", "g": "JH IY1",
    "h": "EY1 CH", "i": "AY1", "j": "JH EY1", "k": "K EY1", "l": "EH1 L", "m": "EH1 M", "n": "EH1 N",
    "o": "OW1", "p": "P IY1", "q": "K Y UW1", "r": "AA1 R", "s": "EH1 S", "t": "T IY1", "u": "Y UW1",
    "v": "V IY1", "w": "D AH1 B AH0 L Y UW0", "x": "EH1 K S", "y": "W AY1", "z": "Z IY1",
}
SIBILANTS = {"S", "Z", "SH", "ZH", "CH", "JH"}
VOICELESS = {"P", "T", "K", "F", "TH"}
CAMEL = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+")


def letter_tokens(ch: str) -> list[str]:
    return arpabet_to_tokens(LETTERS[ch.lower()].split())


def _last_phone(tokens: list[str]) -> str:
    for t in reversed(tokens):
        if t.startswith("EN:"):
            return t[3:]
    return ""


def _demote(tokens: list[str]) -> list[str]:
    return ["S2" if t == "S1" else t for t in tokens]


def _join(parts: list[list[str]]) -> list[str]:
    """Concatenate parts keeping the first primary stress only."""
    out: list[str] = []
    for p in parts:
        out += _demote(p) if "S1" in out else p
    return out


def _plural(base: list[str]) -> list[str]:
    last = _last_phone(base)
    if last in SIBILANTS:
        return base + ["EN:IH", "S0", "EN:Z"]
    return base + (["EN:S"] if last in VOICELESS else ["EN:Z"])


def _past(base: list[str]) -> list[str]:
    last = _last_phone(base)
    if last in ("T", "D"):
        return base + ["EN:IH", "S0", "EN:D"]
    return base + (["EN:T"] if last in VOICELESS | {"S", "SH", "CH"} else ["EN:D"])


def _known(w: str) -> list[str] | None:
    """Lexicon entry or two-part compound of lexicon words (each part >= 3 letters)."""
    lex = load_cmudict()
    if w in lex:
        return lex[w]
    for i in range(len(w) - 3, 2, -1):
        a, b = w[:i], w[i:]
        if a in lex and b in lex:
            return _join([lex[a], lex[b]])
    return None


def _inflected(w: str) -> list[str] | None:
    if w.endswith("'s") and (b := _known(w[:-2])):
        return _plural(b)
    if w.endswith("es") and w[:-2].endswith(("s", "x", "z", "ch", "sh")) and (b := _known(w[:-2])):
        return _plural(b)
    if w.endswith("s") and not w.endswith("ss") and (b := _known(w[:-1])):
        return _plural(b)
    if w.endswith("ed"):
        for base in (w[:-2], w[:-1]):
            if b := _known(base):
                return _past(b)
    if w.endswith("ing"):
        for base in (w[:-3], w[:-3] + "e"):
            if b := _known(base):
                return b + ["EN:IH", "S0", "EN:NG"]
    if w.endswith("er") and (b := _known(w[:-2])):
        return b + ["EN:ER", "S0"]
    if w.endswith("ly") and (b := _known(w[:-2])):
        return b + ["EN:L", "EN:IY", "S0"]
    return None


@functools.lru_cache(maxsize=65536)
def _g2p(word: str) -> tuple[str, ...]:
    w = word.strip("'")
    if not w:
        return ()
    low = w.lower()
    if low in load_cmudict():
        return tuple(load_cmudict()[low])
    if "-" in w:
        return tuple(_join([list(_g2p(p)) for p in w.split("-") if p]))
    pieces = CAMEL.findall(w)
    if len(pieces) > 1 and "".join(pieces) == w.replace("'", ""):
        return tuple(_join([list(_g2p(p)) for p in pieces]))
    if w.isupper() and len(w) <= 4 and w.isalpha():
        return tuple(_join([letter_tokens(c) for c in w]))
    for f in (_known, _inflected):
        if r := f(low):
            return tuple(r)
    return tuple(load_lts().predict(low))


def g2p_word_en(word: str) -> list[str]:
    """v2 tokens for one English word (letters, apostrophes and hyphens; no digits)."""
    return list(_g2p(word))
