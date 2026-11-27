"""Học mô hình "đoán tên Latin" cho Lọc name local (công tắc "Ưu tiên tên Latin") từ một file VietPhrase, xuất JSON.

    python export_translit.py <VietPhrase.txt> <thư mục ra> [--eval]

Ra `<thư mục ra>/translit_latin.json` (định dạng ở `SPEC` dưới) + in sha256. `--eval` giữ 10 % cặp làm bài thi trước khi
học trên toàn bộ, in tỉ lệ đúng.

Cách học (kiểu m2m-aligner): lấy các mục VP 2–6 chữ Hán mà ≥ một nửa số chữ là "chữ phiên âm" (bảng tính từ chính VP) và
có một nghĩa Latin một từ (`[A-Z][a-z]+`) ⇒ cặp (克莱恩, klein). EM trên mọi cách cắt tên Latin thành các đoạn 1–4 chữ cái,
mỗi chữ Hán ↔ một đoạn, xác suất theo (chữ, vị trí trong tên: S một mình / B đầu / M giữa / E cuối). Kèm mô hình chữ cái
bậc 3 trên các tên Latin để tên đoán đọc trơn.
"""
import hashlib
import io
import json
import math
import os
import random
import re
import sys
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")

SPEC = """
translit_latin.json (format 1):
  maxSegmentLength   độ dài đoạn tối đa (4)
  lmWeight           trọng số mô hình chữ cái (λ)
  lmSmoothing        hằng cộng khi làm trơn (0.5); lmAlphabet = số ký hiệu (28 = a–z + "^" + "$")
  minVowelRatio      bỏ dự đoán có ít nguyên âm (aeiouy) hơn max(1, floor(n × tỉ lệ)) — n = số chữ Hán
  translitChars      chuỗi các "chữ phiên âm" (≥ 30 % mục 2–6 chữ chứa nó có nghĩa Latin, ≥ 20 mục)
  segments           {chữ: {"S"|"B"|"M"|"E": [[đoạn, xác suất], …]}} — xác suất dùng nguyên (không chuẩn hoá lại)
  trigram            {"xyz": số lần} — x, y, z ∈ a–z ∪ {"^", "$"}; ngữ cảnh đầu tên là "^^"
  context            {"xy": số lần}
Giải mã: vị trí của chữ i trong tên n chữ = S nếu n = 1, B nếu i = 0, E nếu i = n − 1, còn lại M. Tra segments[chữ][vị trí],
không có ⇒ thử M, rồi B, rồi E; chữ nào không có gì ⇒ không đoán. Tìm chùm (beam 16): mỗi bước điểm += log p(đoạn)
+ λ · LM(lịch sử, đoạn); hết tên cộng λ · LM(lịch sử, "$"); LM(h, chữ cái…) = Σ log((trigram[w+c] + 0.5) /
(context[w] + 0.5 · 28)), w = 2 ký tự cuối của "^^" + h. Lấy điểm cao nhất, viết hoa chữ đầu.
"""

VIET = set("ăâđêôơưĂÂĐÊÔƠƯàáãèéìíòóõùúýÀÁÃÈÉÌÍÒÓÕÙÚÝĩũĨŨ") | {chr(c) for c in range(0x1EA0, 0x1EFA)}
MAXSEG = 4
LAMBDA = 0.3
KEEP_PER_KEY = 8
MIN_PROB = 0.01
MIN_VOWEL_RATIO = 0.5


def han(s):
    return all("一" <= c <= "鿿" for c in s)


def alternatives(v):
    return [a.strip() for a in re.split(r"[/|¦]", v) if a.strip()]


def is_latin_name(a):
    return a[:1].isupper() and not (set(a) & VIET) and any(ch.isalpha() for ch in a)


def read_vp(path):
    entries = {}
    for line in io.open(path, encoding="utf-8", errors="replace"):
        if "=" not in line:
            continue
        k, v = line.rstrip("\r\n").split("=", 1)
        entries.setdefault(k, v)
    return entries


def translit_chars(entries, threshold=0.3, min_entries=20):
    tot, lat = defaultdict(int), defaultdict(int)
    for k, v in entries.items():
        if not (2 <= len(k) <= 6) or not han(k):
            continue
        has = any(is_latin_name(a) for a in alternatives(v))
        for c in set(k):
            tot[c] += 1
            if has:
                lat[c] += 1
    return {c for c in tot if tot[c] >= min_entries and lat[c] / tot[c] >= threshold}


def load_pairs(entries, chars):
    pairs = []
    for k, v in entries.items():
        if not (2 <= len(k) <= 6) or not han(k) or 2 * sum(1 for c in k if c in chars) < len(k):
            continue
        for a in alternatives(v):
            if re.fullmatch(r"[A-Z][a-z]{1,15}", a) and len(k) <= len(a) <= 4 * len(k):
                pairs.append((k, a.lower()))
                break
    return pairs


def pos_of(i, n):
    return "S" if n == 1 else "B" if i == 0 else "E" if i == n - 1 else "M"


class Model:
    def __init__(self):
        self.t = {}
        self.tri, self.ctx = {}, {}

    def train(self, pairs, iters=8):
        counts = defaultdict(lambda: defaultdict(float))
        for k, a in pairs:
            for i, ch in enumerate(k):
                for s in range(len(a)):
                    for l in range(1, MAXSEG + 1):
                        if s + l <= len(a):
                            counts[(ch, pos_of(i, len(k)))][a[s:s + l]] += 1
        self.t = self.normalize(counts, keep=12)
        for it in range(iters):
            counts = defaultdict(lambda: defaultdict(float))
            ll = sum(self.expect(k, a, counts) for k, a in pairs)
            self.t = self.normalize(counts, keep=12)
            print(f"  EM {it + 1}: log-likelihood {ll:.0f}", file=sys.stderr)
        self.t = self.normalize_prune(self.t)
        tri, ctx = defaultdict(int), defaultdict(int)
        for _, a in pairs:
            w = "^^" + a + "$"
            for i in range(2, len(w)):
                tri[w[i - 2:i + 1]] += 1
                ctx[w[i - 2:i]] += 1
        self.tri, self.ctx = dict(tri), dict(ctx)

    @staticmethod
    def normalize(counts, keep):
        out = {}
        for key, d in counts.items():
            total = sum(d.values())
            if total <= 0:
                continue
            out[key] = {seg: c / total for seg, c in sorted(d.items(), key=lambda kv: -kv[1])[:keep] if c > 0}
        return out

    @staticmethod
    def normalize_prune(t):
        """Bản xuất: giữ ≤ 8 đoạn, xác suất ≥ 1 %, làm tròn 4 chữ số — y như bộ giải mã của app đọc."""
        out = {}
        for key, d in t.items():
            kept = [(seg, round(p, 4)) for seg, p in sorted(d.items(), key=lambda kv: -kv[1])[:KEEP_PER_KEY] if p >= MIN_PROB]
            if kept:
                out[key] = dict(kept)
        return out

    def expect(self, k, a, counts):
        n, L = len(k), len(a)
        alpha = [[0.0] * (L + 1) for _ in range(n + 1)]
        alpha[0][0] = 1.0
        for i in range(n):
            d = self.t.get((k[i], pos_of(i, n)), {})
            for j in range(L):
                if alpha[i][j]:
                    for l in range(1, MAXSEG + 1):
                        if j + l > L:
                            break
                        p = d.get(a[j:j + l], 0.0)
                        if p:
                            alpha[i + 1][j + l] += alpha[i][j] * p
        z = alpha[n][L]
        if z <= 0:
            return 0.0
        beta = [[0.0] * (L + 1) for _ in range(n + 1)]
        beta[n][L] = 1.0
        for i in range(n - 1, -1, -1):
            d = self.t.get((k[i], pos_of(i, n)), {})
            for j in range(L, -1, -1):
                for l in range(1, MAXSEG + 1):
                    if j + l > L:
                        break
                    p = d.get(a[j:j + l], 0.0)
                    if p and beta[i + 1][j + l]:
                        beta[i][j] += p * beta[i + 1][j + l]
        for i in range(n):
            key = (k[i], pos_of(i, n))
            d = self.t.get(key, {})
            for j in range(L):
                if alpha[i][j]:
                    for l in range(1, MAXSEG + 1):
                        if j + l > L:
                            break
                        seg = a[j:j + l]
                        p = d.get(seg, 0.0)
                        if p and beta[i + 1][j + l]:
                            counts[key][seg] += alpha[i][j] * p * beta[i + 1][j + l] / z
        return math.log(z)

    # ---- Bộ giải mã đúng như đặc tả `SPEC` (app chép theo)
    def candidates(self, ch, p):
        for q in (p, "M", "B", "E"):
            d = self.t.get((ch, q))
            if d:
                return d
        return None

    def lm(self, history, letters):
        w = ("^^" + history)[-2:]
        total = 0.0
        for ch in letters:
            total += math.log((self.tri.get(w + ch, 0) + 0.5) / (self.ctx.get(w, 0) + 0.5 * 28))
            w = w[1:] + ch
        return total

    def predict(self, k, beam=16):
        n = len(k)
        hyps = [("", 0.0)]
        for i, ch in enumerate(k):
            d = self.candidates(ch, pos_of(i, n))
            if not d:
                return None
            new = [(text + seg, score + math.log(p) + LAMBDA * self.lm(text, seg))
                   for text, score in hyps for seg, p in d.items()]
            new.sort(key=lambda h: -h[1])
            hyps = new[:beam]
        best = max(((t, sc + LAMBDA * self.lm(t, "$")) for t, sc in hyps), key=lambda h: h[1])[0]
        vowels = sum(1 for c in best if c in "aeiouy")
        if vowels < max(1, int(n * MIN_VOWEL_RATIO)):
            return None
        return best[:1].upper() + best[1:]


def edit(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    vp_path, out_dir = sys.argv[1], sys.argv[2]
    entries = read_vp(vp_path)
    chars = translit_chars(entries)
    pairs = load_pairs(entries, chars)
    print(f"{len(entries)} mục VP · {len(chars)} chữ phiên âm · {len(pairs)} cặp tên", file=sys.stderr)
    if "--eval" in sys.argv:
        shuffled = pairs[:]
        random.Random(7).shuffle(shuffled)
        cut = len(shuffled) // 10
        m = Model()
        m.train(shuffled[cut:])
        exact = close = none = 0
        for k, a in shuffled[:cut]:
            p = m.predict(k)
            if p is None:
                none += 1
                continue
            e = edit(p.lower(), a)
            exact += e == 0
            close += e <= 1
        n = cut
        print(f"bài thi {n}: đúng y hệt {exact / n:.1%} · sai ≤ 1 chữ cái {close / n:.1%} · không đoán {none / n:.1%}")
    m = Model()
    m.train(pairs)
    segments = defaultdict(dict)
    for (ch, p), d in sorted(m.t.items()):
        segments[ch][p] = [[seg, prob] for seg, prob in d.items()]
    data = {
        "format": 1,
        "source": f"{os.path.basename(vp_path)} · {len(pairs)} cặp tên",
        "maxSegmentLength": MAXSEG,
        "lmWeight": LAMBDA,
        "lmSmoothing": 0.5,
        "lmAlphabet": 28,
        "minVowelRatio": MIN_VOWEL_RATIO,
        "translitChars": "".join(sorted(chars)),
        "segments": segments,
        "trigram": m.tri,
        "context": m.ctx,
    }
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "translit_latin.json")
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    print(f"xong: {path} · {os.path.getsize(path):,} byte · sha256 {digest}")
    for k in ["伽罗斯", "戈鲁克", "霍尔登", "马尔内斯", "弗克", "盖文", "克莱恩", "阿兹克"]:
        print(f"  {k} ⇒ {m.predict(k)}")


if __name__ == "__main__":
    main()
