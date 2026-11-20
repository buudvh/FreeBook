"""Letter-to-sound for English words outside the lexicon, learned from CMUdict.

1. Letters and phonemes are aligned with hard EM: every letter emits nothing ("_"), one phoneme
   or two ("K S" for x), and emission probabilities are re-estimated from Viterbi alignments.
2. Each letter's label (phonemes with stress digits) is stored for letter-context windows of
   decreasing size; prediction uses the widest window seen in training (backoff).
3. Stress is cleaned up afterwards: exactly one primary stress per word.

Deterministic and table-driven, so the same model can be exported for the device front-end.
"""

from __future__ import annotations

import collections
import functools
import json
import math

from ..phoneme_set import ARPABET_VOWELS
from .cmudict import COMMIT, DEFAULT_PATH, load_cmudict

EPS = "_"
WINDOWS = ((3, 3), (3, 2), (2, 3), (2, 2), (2, 1), (1, 2), (1, 1), (1, 0), (0, 1), (0, 0))
PAD = "#"
UNSEEN = -20.0
MODEL_PATH = DEFAULT_PATH.parent / f"lts_{COMMIT[:12]}.json"


def _labels(phones: list[str]) -> list[str]:
    labs = [EPS] + phones
    labs += [f"{a} {b}" for a, b in zip(phones, phones[1:])]
    return labs


def align(word: str, phones: list[str], table: dict[str, dict[str, float]]) -> list[tuple[str, str]] | None:
    """Viterbi alignment of letters to phonemes; None when the word cannot be aligned."""
    n, m = len(word), len(phones)
    if m > 2 * n:
        return None
    neg = -math.inf
    best = [[neg] * (m + 1) for _ in range(n + 1)]
    back: list[list[tuple[int, str] | None]] = [[None] * (m + 1) for _ in range(n + 1)]
    best[0][0] = 0.0
    for i in range(n):
        em = table.get(word[i], {})
        for j in range(m + 1):
            if best[i][j] == neg:
                continue
            for k in (0, 1, 2):
                if j + k > m:
                    break
                lab = EPS if k == 0 else " ".join(phones[j:j + k])
                s = best[i][j] + em.get(lab, UNSEEN)
                if s > best[i + 1][j + k]:
                    best[i + 1][j + k] = s
                    back[i + 1][j + k] = (j, lab)
    if best[n][m] == neg:
        return None
    out, j = [], m
    for i in range(n, 0, -1):
        pj, lab = back[i][j]
        out.append((word[i - 1], lab))
        j = pj
    return out[::-1]


def em_align(pairs: list[tuple[str, list[str]]], iters: int = 4) -> dict[str, dict[str, float]]:
    """Emission log-probabilities letter -> label, from co-occurrence then hard EM."""
    counts: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for word, phones in pairs:
        labs = _labels(phones)
        for ch in word:
            counts[ch].update(labs)

    def normalize(c: dict[str, collections.Counter]) -> dict[str, dict[str, float]]:
        out = {}
        for ch, cnt in c.items():
            tot = sum(cnt.values()) + 0.1 * len(cnt)
            out[ch] = {lab: math.log((v + 0.1) / tot) for lab, v in cnt.items()}
        return out

    table = normalize(counts)
    for _ in range(iters):
        counts = collections.defaultdict(collections.Counter)
        for word, phones in pairs:
            a = align(word, phones, table)
            if a:
                for ch, lab in a:
                    counts[ch][lab] += 1
        table = normalize(counts)
    return table


def _split(tokens: list[str]) -> tuple[list[str], list[str]]:
    """v2 tokens -> (base phonemes, phonemes with stress digit on vowels)."""
    base, stressed = [], []
    for t in tokens:
        if t.startswith("EN:"):
            base.append(t[3:]); stressed.append(t[3:])
        elif t in ("S0", "S1", "S2") and stressed:
            stressed[-1] += t[1]
    return base, stressed


def _key(w: tuple[int, int], padded: str, i: int) -> str:
    left, right = w
    return f"{left}{right}{padded[i - left:i]}|{padded[i]}|{padded[i + 1:i + 1 + right]}"


class LtsModel:
    def __init__(self, table: dict, default: str = EPS):
        self.table = table
        self.default = default

    def labels(self, word: str) -> list[str]:
        letters = "".join(ch for ch in word.lower() if "a" <= ch <= "z")
        padded = PAD * 3 + letters + PAD * 3
        out = []
        for i in range(3, 3 + len(letters)):
            for w in WINDOWS:
                lab = self.table.get(_key(w, padded, i))
                if lab is not None:
                    out.append(lab)
                    break
            else:
                out.append(self.default)
        return out

    @staticmethod
    def finish(tokens: list[str]) -> list[str]:
        """Exactly one primary stress: promote the first vowel if none, demote extra S1."""
        idx = [i for i, t in enumerate(tokens) if t in ("S0", "S1", "S2")]
        prim = [i for i in idx if tokens[i] == "S1"]
        out = list(tokens)
        if not prim and idx:
            out[idx[0]] = "S1"
        for i in prim[1:]:
            out[i] = "S2"
        return out

    def predict(self, word: str) -> list[str]:
        toks = []
        for lab in self.labels(word):
            if lab == EPS:
                continue
            for p in lab.split():
                base = p.rstrip("012")
                toks.append(f"EN:{base}")
                if base in ARPABET_VOWELS:
                    toks.append(f"S{p[len(base):] or '0'}")
        return self.finish(toks)


def train_lts(lex: dict[str, list[str]], min_count: int = 2) -> LtsModel:
    words = [(w, *_split(t)) for w, t in lex.items() if w.isalpha() and w.isascii()]
    table = em_align([(w, b) for w, b, _ in words])
    counts: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for w, base, stressed in words:
        a = align(w, base, table)
        if not a:
            continue
        it = iter(stressed)
        padded = PAD * 3 + w + PAD * 3
        for i, (_, lab) in enumerate(a):
            slab = EPS if lab == EPS else " ".join(next(it) for _ in lab.split())
            for win in WINDOWS:
                counts[_key(win, padded, i + 3)][slab] += 1
    model = {}
    for key, cnt in counts.items():
        lab, c = cnt.most_common(1)[0]
        if c >= min_count or key.startswith("00"):
            model[key] = lab
    return LtsModel(model)


ALPHA = tuple(chr(c) for c in range(ord("a"), ord("z") + 1)) + (PAD,)
_WIDX = {w: i for i, w in enumerate(WINDOWS)}


def _first_label(table: dict, left: str, c: str, right: str, start: int):
    """Label for a context with known left/right letters, trying windows from `start` on;
    ("need", window) when a window needs a letter beyond the known ones."""
    for w in WINDOWS[start:]:
        lw, rw = w
        if lw > len(left) or rw > len(right):
            return ("need", w)
        lab = table.get(f"{lw}{rw}{left[len(left) - lw:]}|{c}|{right[:rw]}")
        if lab is not None:
            return lab
    return None


def _redundant(table: dict, key: str) -> bool:
    """True if every context where `key` is the widest match gets the same label without it.
    Some later windows are not nested in the key's window ((3,2) is followed by (2,3)), so the
    missing letter is enumerated over the alphabet and the padding symbol."""
    w = (int(key[0]), int(key[1]))
    left, c, right = key[2:].split("|")
    lab, stack = table[key], [(left, right)]
    while stack:
        lf, rt = stack.pop()
        res = _first_label(table, lf, c, rt, _WIDX[w] + 1)
        if isinstance(res, tuple):
            nl, _ = res[1]
            stack += [(x + lf, rt) for x in ALPHA] if nl > len(lf) else [(lf, rt + x) for x in ALPHA]
        elif res != lab:
            return False
    return True


def prune_table(table: dict) -> dict:
    """Drop window keys that never change a prediction (widest windows first). Lossless:
    every word gets the same labels from the pruned table."""
    t = dict(table)
    for key in sorted(t, key=lambda k: _WIDX[(int(k[0]), int(k[1]))]):
        if _redundant(t, key):
            del t[key]
    return t


@functools.lru_cache(maxsize=1)
def load_lts() -> LtsModel:
    """The model trained on the full pinned CMUdict, cached next to it."""
    if MODEL_PATH.exists():
        return LtsModel(json.loads(MODEL_PATH.read_text(encoding="utf-8")))
    model = train_lts(load_cmudict())
    MODEL_PATH.write_text(json.dumps(model.table, ensure_ascii=False), encoding="utf-8")
    return model
