"""VLEX: CMUdict and the pruned letter-to-sound table packed for the device front-end.

Little-endian. Header (32 bytes):
  magic "VLEX", version u16 = 1, block u16 (words per block), n_words u32, n_blocks u32,
  lts_off u32, lts_n u32, lab_off u32, n_labels u16, reserved u16.
Lexicon (from byte 32): block offset table u32 x n_blocks (relative to the first block), then
  blocks of front-coded entries [prefix_len u8][suffix_len u8][suffix][n u8][phones u8 x n]
  sorted by word bytes; the first entry of a block has prefix_len 0. A phone byte is the ARPAbet
  index (0..38) plus 40 x (stress + 1) for a vowel followed by its stress token, so one byte
  expands to EN:<phone> or EN:<phone> S<stress>.
LTS (at lts_off): lts_n keys of 6 bytes, sorted: a 40-bit key (window index << 35, then the
  letters L3 L2 L1 C R1 R2 R3 at 5 bits each, '#' = 0, a..z = 1..26, unused = 0) and a label index.
Labels (at lab_off): n_labels entries [n u8][token ids u8...] (phonemes with stress tokens, as
  LtsModel.predict emits them before the one-primary-stress clean-up).
"""

from __future__ import annotations

import bisect
import struct
from dataclasses import dataclass

from ..phoneme_set import ARPABET, ARPABET_VOWELS, TOKENS_V2, token_to_id_v2
from .cmudict import load_cmudict
from .lts import EPS, PAD, WINDOWS, LtsModel, load_lts, prune_table

MAGIC, VERSION, BLOCK = b"VLEX", 1, 32
HEADER = struct.Struct("<4sHHIIIIIHH")


def _sym(ch: str) -> int:
    return 0 if ch == PAD else ord(ch) - ord("a") + 1


def pack_key(lw: int, rw: int, left: str, c: str, right: str) -> int:
    slots = [0] * 7  # L3 L2 L1 C R1 R2 R3
    for i, ch in enumerate(reversed(left)):
        slots[2 - i] = _sym(ch)
    slots[3] = _sym(c)
    for i, ch in enumerate(right):
        slots[4 + i] = _sym(ch)
    v = WINDOWS.index((lw, rw))
    for s in slots:
        v = (v << 5) | s
    return v


def label_ids(lab: str) -> list[int]:
    if lab == EPS:
        return []
    out = []
    for p in lab.split():
        base = p.rstrip("012")
        out.append(token_to_id_v2(f"EN:{base}"))
        if base in ARPABET_VOWELS:
            out.append(token_to_id_v2(f"S{p[len(base):] or '0'}"))
    return out


def pack_phones(tokens: list[str]) -> bytes:
    out, i = bytearray(), 0
    while i < len(tokens):
        b = ARPABET.index(tokens[i][3:])
        if i + 1 < len(tokens) and tokens[i + 1] in ("S0", "S1", "S2"):
            b += 40 * (int(tokens[i + 1][1]) + 1)
            i += 1
        out.append(b)
        i += 1
    return bytes(out)


def unpack_phones(data: bytes) -> list[int]:
    ids = []
    for b in data:
        ids.append(token_to_id_v2(f"EN:{ARPABET[b % 40]}"))
        if b >= 40:
            ids.append(token_to_id_v2(f"S{b // 40 - 1}"))
    return ids


def build_vlex(max_words: int | None = None) -> bytes:
    lex = load_cmudict()
    words = sorted(lex, key=lambda w: w.encode())[:max_words]
    blocks, offs, pos = [], [], 0
    for b0 in range(0, len(words), BLOCK):
        buf, prev = bytearray(), b""
        for w in words[b0:b0 + BLOCK]:
            wb = w.encode()
            pre = 0 if not buf else next((i for i in range(min(len(prev), len(wb), 255))
                                          if prev[i] != wb[i]), min(len(prev), len(wb), 255))
            ph = pack_phones(lex[w])
            buf += bytes([pre, len(wb) - pre]) + wb[pre:] + bytes([len(ph)]) + ph
            prev = wb
        offs.append(pos)
        pos += len(buf)
        blocks.append(bytes(buf))
    lexicon = struct.pack(f"<{len(offs)}I", *offs) + b"".join(blocks)
    table = prune_table(load_lts().table)
    labels = sorted(set(table.values()))
    lab_idx = {lab: i for i, lab in enumerate(labels)}
    keys = []
    for k, lab in table.items():
        lw, rw = int(k[0]), int(k[1])
        left, c, right = k[2:].split("|")
        keys.append((pack_key(lw, rw, left, c, right), lab_idx[lab]))
    keys.sort()
    lts = b"".join(v.to_bytes(5, "little") + bytes([li]) for v, li in keys)
    labs = b"".join(bytes([len(ids)]) + bytes(ids) for ids in map(label_ids, labels))
    lts_off = HEADER.size + len(lexicon)
    lab_off = lts_off + len(lts)
    head = HEADER.pack(MAGIC, VERSION, BLOCK, len(words), len(blocks), lts_off, len(keys), lab_off,
                       len(labels), 0)
    return head + lexicon + lts + labs


@dataclass
class Vlex:
    """Reference reader with the same lookups as the C reader (runtime/src/vtts_lex.c)."""
    blob: bytes

    def __post_init__(self):
        (magic, ver, self.block, self.n_words, self.n_blocks, self.lts_off, self.lts_n, self.lab_off,
         self.n_labels, _) = HEADER.unpack_from(self.blob, 0)
        assert magic == MAGIC and ver == VERSION
        self.offs = struct.unpack_from(f"<{self.n_blocks}I", self.blob, HEADER.size)
        self.base = HEADER.size + 4 * self.n_blocks
        self.keys = [int.from_bytes(self.blob[self.lts_off + 6 * i: self.lts_off + 6 * i + 5], "little")
                     for i in range(self.lts_n)]
        p, self.labels = self.lab_off, []
        for _ in range(self.n_labels):
            n = self.blob[p]
            self.labels.append(list(self.blob[p + 1: p + 1 + n]))
            p += 1 + n

    def _block(self, b: int):
        p = self.base + self.offs[b]
        word = b""
        for _ in range(min(self.block, self.n_words - b * self.block)):
            pre, sl = self.blob[p], self.blob[p + 1]
            word = word[:pre] + self.blob[p + 2: p + 2 + sl]
            p += 2 + sl
            n = self.blob[p]
            yield word, unpack_phones(self.blob[p + 1: p + 1 + n])
            p += 1 + n

    def lookup(self, word: str) -> list[int] | None:
        wb = word.encode()
        lo, hi = 0, self.n_blocks - 1
        while lo < hi:  # last block whose first word <= wb
            mid = (lo + hi + 1) // 2
            if next(self._block(mid))[0] <= wb:
                lo = mid
            else:
                hi = mid - 1
        for w, ids in self._block(lo):
            if w == wb:
                return ids
        return None

    def predict(self, word: str) -> list[int]:
        letters = "".join(ch for ch in word.lower() if "a" <= ch <= "z")
        padded = PAD * 3 + letters + PAD * 3
        ids: list[int] = []
        for i in range(3, 3 + len(letters)):
            for lw, rw in WINDOWS:
                k = pack_key(lw, rw, padded[i - lw:i], padded[i], padded[i + 1:i + 1 + rw])
                j = bisect.bisect_left(self.keys, k)
                if j < self.lts_n and self.keys[j] == k:
                    ids += self.labels[self.blob[self.lts_off + 6 * j + 5]]
                    break
        toks = [_ID_TO_TOK[i] for i in ids]
        return [token_to_id_v2(t) for t in LtsModel.finish(toks)]


def read_vlex(blob: bytes) -> Vlex:
    return Vlex(blob)


_ID_TO_TOK = dict(enumerate(TOKENS_V2))
