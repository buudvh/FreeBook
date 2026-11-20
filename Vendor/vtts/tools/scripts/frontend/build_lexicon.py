"""Build the VLEX blob (English lexicon + letter-to-sound) for the device front-end.

Usage: uv run python scripts/frontend/build_lexicon.py --out lex_en.bin [--max-words N]
       [--expect runtime/test/lex_expect.tsv --n-words 5000 --n-lts 1000]
--expect writes a fixture for runtime/test/lex_test.c: lines "L<TAB>word<TAB>ids" for lexicon
lookups (ids empty when absent), "P<TAB>word<TAB>ids" for letter-to-sound predictions and
"G<TAB>word<TAB>ids" for whole-word English G2P (g2p_word_en: inflections, compounds, CamelCase).
"""

import argparse
import random
import string
from pathlib import Path

from vtts.frontend.en.cmudict import load_cmudict
from vtts.frontend.en.g2p_en import g2p_word_en
from vtts.frontend.phoneme_set import token_to_id_v2
from vtts.frontend.en.vlex import build_vlex, read_vlex


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--max-words", type=int, default=None)
    ap.add_argument("--expect", type=Path, default=None)
    ap.add_argument("--n-words", type=int, default=5000)
    ap.add_argument("--n-lts", type=int, default=1000)
    a = ap.parse_args()
    blob = build_vlex(a.max_words)
    a.out.write_bytes(blob)
    print(f"wrote {a.out} ({len(blob)} bytes)")
    if a.expect:
        v, rnd = read_vlex(blob), random.Random(0)
        lex = sorted(load_cmudict())
        lines = []
        for w in rnd.sample(lex, min(a.n_words, len(lex))):
            lines.append(f"L\t{w}\t{' '.join(map(str, v.lookup(w)))}")
        absent = ["".join(rnd.choice(string.ascii_lowercase) for _ in range(rnd.randint(3, 9))) for _ in range(200)]
        for w in absent:
            ids = v.lookup(w)
            lines.append(f"L\t{w}\t{' '.join(map(str, ids or []))}")
        for _ in range(a.n_lts):
            w = "".join(rnd.choice(string.ascii_lowercase) for _ in range(rnd.randint(1, 14)))
            lines.append(f"P\t{w}\t{' '.join(map(str, v.predict(w)))}")
        alpha = [w for w in lex if w.isalpha() and w.isascii() and 3 <= len(w) <= 10]
        words = []
        for w in rnd.sample(alpha, 600):
            words += [w + s for s in ("s", "es", "'s", "ed", "d", "ing", "er", "ly")] + [w[:-1] + "ing"]
        words += [a + b for a, b in zip(rnd.sample(alpha, 400), rnd.sample(alpha, 400))]
        words += ["don't", "spotify's", "o'clock", "rock'n'roll", "well-known", "e-mail", "x-ray-ish",
                  "HTMLParser", "ChatGPT", "iPhone", "USB", "NASA", "AirPods", "YouTube", "macOS", "'tis",
                  "''", "-", "a-", "TCP-IP", "McDonald's", "IoT", "ESP"]
        words += ["".join(rnd.choice(string.ascii_lowercase + "'") for _ in range(rnd.randint(1, 12)))
                  for _ in range(800)]
        for w in words:
            ids = [token_to_id_v2(x) for x in g2p_word_en(w)]
            lines.append(f"G\t{w}\t{' '.join(map(str, ids))}")
        a.expect.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"wrote {a.expect} ({len(lines)} cases)")


if __name__ == "__main__":
    main()
