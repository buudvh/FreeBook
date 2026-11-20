"""CMUdict (Carnegie Mellon University, BSD 2-clause) as a word -> v2-token lexicon.

The dictionary is downloaded once from a pinned commit and checked by SHA256.
Only the first pronunciation of each word is kept; stress digits become S0/S1/S2 tokens
placed right after their vowel.
"""

from __future__ import annotations

import functools
import hashlib
import urllib.request
from pathlib import Path

COMMIT = "74790861f652b15e4ac49015a90074ad62a27690"
URL = f"https://raw.githubusercontent.com/cmusphinx/cmudict/{COMMIT}/cmudict.dict"
SHA256 = "81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22"
DEFAULT_PATH = Path(__file__).resolve().parents[4] / "data" / "cmudict" / "cmudict.dict"


def arpabet_to_tokens(phones: list[str]) -> list[str]:
    out = []
    for p in phones:
        if p[-1].isdigit():
            out += [f"EN:{p[:-1]}", f"S{p[-1]}"]
        else:
            out.append(f"EN:{p}")
    return out


def _fetch(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = urllib.request.urlopen(URL, timeout=60).read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise RuntimeError("CMUdict download does not match the pinned SHA256")
    path.write_bytes(data)


@functools.lru_cache(maxsize=2)
def load_cmudict(path: Path | None = None) -> dict[str, list[str]]:
    path = Path(path) if path else DEFAULT_PATH
    if not path.exists():
        _fetch(path)
    lex: dict[str, list[str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        word, *phones = line.split()
        if "(" in word or word in lex:
            continue
        lex[word] = arpabet_to_tokens(phones)
    return lex
