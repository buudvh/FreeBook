"""Xuất model LAC 2.1.2 (Baidu, Apache-2.0) thành bộ file app tải về cho "Lọc name local".

Môi trường: python 3.9 + paddlepaddle 2.6.2 + LAC 2.1.2 (pip install paddlepaddle==2.6.2 lac==2.1.2).
    python export_lac.py <thư mục ra> [truyện.txt để đối chiếu thêm] [số dòng, mặc định 3000]

Ra <thư mục ra>/: lac_weights.bin, lac_manifest.json, word.dic, tag.dic, q2b.dic, small_seg.dic (chép nguyên byte),
lac_golden.json (mẫu đối chiếu), LICENSE, README.md (nguồn, định dạng, thuật toán, sha256).

Script còn tự kiểm: (1) bản tách từ viết lại theo đặc tả trùng `Segment.fast_cut` của LAC; (2) mạng tính lại bằng numpy
(embedding fp16 như file xuất) cho nhãn trùng predictor của LAC.
"""
import hashlib
import io
import json
import math
import os
import random
import re
import shutil
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.stdout.reconfigure(encoding="utf-8")
import lac_shim  # noqa: E402,F401
import paddle  # noqa: E402
import LAC as lac_pkg  # noqa: E402
from LAC import LAC  # noqa: E402

FORMAT_VERSION = 1
H = 128
ALIGN = 64
TENSORS = (["word_emb"]
           + [f"fc_{i}.{k}_0" for i in range(5) for k in ("w", "b")]
           + [f"gru_{i}.{k}_0" for i in range(4) for k in ("w", "b")]
           + ["crfw"])
DICTS = ["word.dic", "tag.dic", "q2b.dic", "small_seg.dic"]
MODEL_DIR = os.path.join(os.path.dirname(lac_pkg.__file__), "lac_model")
LICENSE_SOURCE = os.path.join(HERE, "LICENSE-Apache-2.0.txt")

# Câu tự viết (không trích truyện nào) + vài ca biên: chữ ngoài BMP, chữ/số ASCII, toàn khoảng trắng, dấu câu.
OWN_SENTENCES = [
    "林青云提着长剑走进了天剑宗的山门。", "苏婉儿笑道：“师兄，你又来晚了。”",
    "东海之滨有一座极星岛，岛上住着三位长老。", "他服下一枚五气丹，体内真元顿时翻涌。",
    "赵长老冷哼一声，转身离开了圣元城。", "青石镇外的黑风谷里，常有妖兽出没。",
    "李师妹修炼的是太虚剑诀，已经到了第三层。", "云梦商会的掌柜亲自把灵石送到了王府。",
    "陈默抬头望向天空，只见一道金光划过。", "这本《九转玄功》是从万宝阁里拍来的。",
    "慕容雪轻声说：“明日我们去落霞峰。”", "北冥剑派与南华宫世代交好。",
    "张三丰并不是这个世界的人。", "2026年11月，他在ABC公司找到了第一份工作。",
    "ＡＢＣ和１２３都是全角字符。", "叶凡、石昊和楚风同时出手。",
    "那头赤炎狮子被困在八门金锁阵中。", "孟浩然的诗写得很好，杜甫也很佩服。",
    "她把紫霞鼎放在桌上，鼎中飘出淡淡的药香。", "罗峰的师父是混沌城主。",
    "天色已晚，掌门吩咐弟子们早些休息。", "王掌柜，这批货什么时候能到青州？",
    "宋师兄的剑法比我高明多了。", "他一口气跑到了长安城的朱雀大街。",
    "道友请留步，贫道有一事相求。", "魔教教主独孤求败已经闭关三十年。",
    "小鱼儿和花无缺是一对孪生兄弟。", "灵虚子掐指一算，脸色大变。",
    "这枚玉简里记载着《星辰变》的残篇。", "风云阁的弟子个个都是好手。",
    "白发老者叹了口气：“罢了，罢了。”", "唐门的暗器天下无双。",
    "𫄸这个字很少见，𠀀也是。", "Hello世界，LAC测试123。", "师尊！弟子知错了！", "……",
    "三日后，玄天宗山门大开，各路豪杰齐聚。", "金陵城外有一座寒山寺。",
    "他取出一张五雷符，往空中一抛。", "秦皇岛和张家口都在河北省。", "啊", " 他 来了 ", "a1b2 c3",
]
RANDOM_LINES = 160
RANDOM_SEED = 20261127
PUNCT = ["，", "。", "！", "？", "：", "“", "”", "、", "…"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_params():
    paddle.enable_static()
    exe = paddle.static.Executor(paddle.CPUPlace())
    paddle.static.load_inference_model(os.path.join(MODEL_DIR, "model"), exe,
                                       model_filename="__model__", params_filename=None)
    scope = paddle.static.global_scope()
    return {name: np.array(scope.find_var(name).get_tensor()) for name in TENSORS}


def write_weights(params, path):
    """Một file nhị phân little-endian, mỗi tensor bắt đầu ở bội số 64 byte; vị trí ghi trong manifest."""
    blob, entries = bytearray(), []
    for name in TENSORS:
        a = params[name]
        half = name == "word_emb"
        data = np.ascontiguousarray(a.astype("<f2" if half else "<f4")).tobytes()
        blob += b"\0" * ((-len(blob)) % ALIGN)
        entries.append({"name": name, "dtype": "float16" if half else "float32", "shape": list(a.shape),
                        "offset": len(blob), "bytes": len(data)})
        blob += data
    with open(path, "wb") as f:
        f.write(blob)
    return entries


# ---- Đặc tả tách từ (bản viết lại để Swift chép theo), phải trùng Segment.fast_cut
class SegSpec:
    def __init__(self, path):
        self.words, self.prefixes, total, maxlen = set(), set(), 0, 0
        with io.open(path, "r", encoding="utf-8") as f:
            for line in f:
                word, count = line.strip().split(" ")
                total += int(count)
                maxlen = max(maxlen, len(word))
                self.words.add(word)
                for i in range(1, len(word)):
                    self.prefixes.add(word[:i])
        self.log_total = math.log(total)
        self.log_length = [math.log(n) for n in range(1, maxlen + 1)]
        self.total, self.maxlen = total, maxlen

    def cut(self, text):
        n = len(text)
        known = lambda w: w in self.words or w in self.prefixes  # noqa: E731
        dag = []
        for head in range(n):
            ends, end = [head], head + 1
            while end <= n and known(text[head:end]):
                if text[head:end] in self.words:
                    ends.append(end - 1)
                end += 1
            dag.append(ends)
        route = [None] * (n + 1)
        route[n] = (0.0, 0)
        for idx in range(n - 1, -1, -1):
            route[idx] = max((self.log_length[e - idx] - self.log_total + route[e + 1][0], e) for e in dag[idx])
        out, buf, i = [], "", 0
        while i < n:
            j = route[i][1] + 1
            piece = text[i:j]
            if len(piece) == 1 and re.match("[a-zA-Z0-9]", piece):
                buf += piece
            else:
                if buf:
                    out.append(buf)
                    buf = ""
                out.append(piece)
            i = j
        if buf:
            out.append(buf)
        return out


# ---- Mạng tính lại bằng numpy (cùng công thức sẽ chép sang Swift)
def make_forward(params, emb):
    fc = [(params[f"fc_{i}.w_0"], params[f"fc_{i}.b_0"]) for i in range(5)]
    gru = [(params[f"gru_{i}.w_0"], params[f"gru_{i}.b_0"].reshape(-1)) for i in range(4)]
    crfw = params["crfw"]

    def sig(x):
        return 1.0 / (1.0 + np.exp(-x))

    def gru_run(x, w, b, reverse):
        flat = w.reshape(-1)
        wg, ws = flat[:2 * H * H].reshape(H, 2 * H), flat[2 * H * H:].reshape(H, H)
        h = np.zeros(H, dtype=np.float32)
        out = np.zeros((x.shape[0], H), dtype=np.float32)
        xb = x + b
        for t in (range(x.shape[0] - 1, -1, -1) if reverse else range(x.shape[0])):
            g = xb[t, :2 * H] + h @ wg
            u, r = sig(g[:H]), sig(g[H:])
            c = np.tanh(xb[t, 2 * H:] + (r * h) @ ws)
            h = (1 - u) * h + u * c
            out[t] = h
        return out

    def viterbi(e):
        start, end, trans = crfw[0], crfw[1], crfw[2:]
        score = start + e[0]
        back = np.zeros(e.shape, dtype=np.int64)
        for t in range(1, e.shape[0]):
            cand = score[:, None] + trans
            back[t] = cand.argmax(0)
            score = cand.max(0) + e[t]
        best = [int((score + end).argmax())]
        for t in range(e.shape[0] - 1, 0, -1):
            best.append(int(back[t][best[-1]]))
        return best[::-1]

    def forward(ids):
        x = emb[ids]
        for layer in range(2):
            f = gru_run(x @ fc[2 * layer][0] + fc[2 * layer][1], *gru[2 * layer], False)
            r = gru_run(x @ fc[2 * layer + 1][0] + fc[2 * layer + 1][1], *gru[2 * layer + 1], True)
            x = np.concatenate([f, r], axis=1)
        return viterbi(x @ fc[4][0] + fc[4][1])

    return forward


def random_lines(seg_words):
    rnd = random.Random(RANDOM_SEED)
    pool = sorted(w for w in seg_words if 1 <= len(w) <= 4)
    lines = []
    for _ in range(RANDOM_LINES):
        parts = [rnd.choice(pool) for _ in range(rnd.randint(3, 12))]
        if rnd.random() < 0.5:
            parts.insert(rnd.randint(0, len(parts)), rnd.choice(PUNCT))
        lines.append("".join(parts))
    return lines


def reference(model, text):
    """Kết quả gốc của LAC: tách từ, id, độ dài, id nhãn của predictor, (từ, nhãn) cuối."""
    words = model.segment_tool.fast_cut(text)
    ids, word_length = model.dataset.text_to_ids(words)
    tag_ids = list(model.predictor.run([model.to_tensor(ids, [0, len(ids)])])[0].data.int64_data())
    out_words, out_tags = model.run(text)
    return {"text": text, "words": words, "ids": ids, "wordLength": word_length, "tagIds": tag_ids,
            "outWords": out_words, "outTags": out_tags}


def write_readme(out_dir, manifest, check):
    files = sorted(f for f in os.listdir(out_dir) if f != "README.md")
    rows = "\n".join(f"| `{f}` | {os.path.getsize(os.path.join(out_dir, f)):,} | `{sha256(os.path.join(out_dir, f))}` |"
                     for f in files)
    text = f"""# LAC 2.1.2 cho Tàng Công Các (Lọc name local)

Bản sao **đã đổi định dạng** của model phân tích từ vựng tiếng Trung **LAC 2.1.2** của Baidu
(PyPI `lac==2.1.2`, https://github.com/baidu/lac), giấy phép **Apache-2.0** (file `LICENSE`).
Copyright (c) 2020 Baidu, Inc. All Rights Reserved.

Thay đổi so với bản gốc (theo mục 4b của Apache-2.0):
- Trọng số chuyển từ định dạng tham số Paddle sang một file nhị phân `lac_weights.bin`; bảng embedding `word_emb`
  đổi sang **float16** (các tensor khác giữ float32). Mô tả vị trí từng tensor ở `lac_manifest.json`.
- `word.dic`, `tag.dic`, `q2b.dic`, `small_seg.dic` chép nguyên byte từ `lac_model/conf/`.
- `lac_golden.json`: {manifest['golden']['count']} câu đối chiếu (câu tự viết + chuỗi từ ngẫu nhiên, không trích tác phẩm nào)
  kèm kết quả của LAC gốc.

Sinh bằng `Tools/lac-export/export_lac.py` trong repo app. Kiểm khi xuất: {check}.

## File

| File | Byte | sha256 |
|---|---|---|
{rows}

## Thuật toán (để viết lại bằng ngôn ngữ khác)

Mọi độ dài / vị trí tính theo **code point Unicode** (như `str` Python), không theo UTF-16 hay grapheme.

1. **Tách từ sơ bộ** (`Segment.fast_cut`) trên `small_seg.dic` (dòng `từ số_lần`, `strip()` rồi tách bằng một dấu cách):
   - DAG: từ vị trí `i`, tăng dần `j` khi `text[i:j]` là từ **hoặc tiền tố thật** của một từ; `text[i:j]` là từ ⇒ thêm
     điểm cuối `j-1`. Luôn có điểm cuối `i`.
   - Điểm của một từ là `log(độ dài từ) - logTotal` — **độ dài, không phải số lần** (LAC lưu độ dài trong cây tiền tố);
     số lần chỉ dùng tính `logTotal = log(tổng số lần)`. Hai số này ghi sẵn trong manifest (`segment.logTotal`,
     `segment.logLength[k-1] = log(k)`) để khỏi phụ thuộc thư viện `log`.
   - Quy hoạch ngược: `route[n] = 0`; `route[i] = max((logLength[e-i] - logTotal) + route[e+1])` trên các điểm cuối
     `e`, cộng **đúng thứ tự đó**; bằng điểm ⇒ chọn `e` lớn hơn.
   - Đi từ đầu theo route; mảnh dài 1 khớp `[a-zA-Z0-9]` dồn vào bộ đệm, gặp mảnh khác thì đẩy bộ đệm ra trước.
2. **Ra id** (`text_to_ids`): `word.dic` là `id<TAB>từ` (đọc ngược thành từ → id, dòng sau ghi đè; chỉ bỏ `\\n`, giữ
   dấu cách). Từ của bước 1 có trong `word.dic` ⇒ một id (độ dài = số chữ của từ), qua `q2b.dic` (`gốc<TAB>thay`)
   trước khi tra, không có ⇒ `OOV`. Không có ⇒ **từng chữ** qua `q2b.dic` rồi tra, độ dài 1.
3. **Mạng** (embedding {manifest['network']['vocabSize']}×{H}, hai lớp BiGRU {H}, FC, CRF):
   - Lớp `l` (0, 1): chiều xuôi `x·fc_{{2l}}.w + fc_{{2l}}.b` → `gru_{{2l}}`; chiều ngược `x·fc_{{2l+1}}.w + fc_{{2l+1}}.b`
     → `gru_{{2l+1}}` chạy từ cuối câu; ghép [xuôi, ngược] làm đầu vào lớp sau.
   - GRU: trọng số `[{H},{3 * H}]` đọc như **buffer phẳng**: {2 * H * H} số đầu là `W_gate [{H},{2 * H}]`, còn lại
     `W_state [{H},{H}]`. Bias `[1,{3 * H}]` cộng vào đầu vào. `g = x[:{2 * H}] + h·W_gate`, `u = σ(g[:{H}])`,
     `r = σ(g[{H}:])`, `c = tanh(x[{2 * H}:] + (r⊙h)·W_state)`, `h = (1-u)⊙h + u⊙c`, `h` đầu = 0.
   - `fc_4` ({2 * H}→{manifest['network']['numLabels']}) ra điểm phát xạ; Viterbi với `crfw [{manifest['network']['numLabels'] + 2},{manifest['network']['numLabels']}]`: hàng 0 điểm bắt đầu,
     hàng 1 điểm kết thúc, hàng 2.. ma trận chuyển `[từ, sang]`.
4. **Nhãn** (`tag.dic`, `id<TAB>nhãn`, **dòng sau ghi đè** ⇒ 16 = `PER-B`, 18 = `LOC-B`, 20 = `ORG-B`, 34 = `TIME-B`,
   48 = `O`): từ nhiều chữ ở bước 2 nở lại thành `nhãn-B` + `nhãn-I` cho các chữ sau; rồi gộp: chữ đầu hoặc nhãn
   kết thúc bằng `B`/`S` mở từ mới, còn lại nối vào từ trước và lấy nhãn chữ cuối (bỏ hậu tố `-B`/`-I`).
"""
    with io.open(os.path.join(out_dir, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    out_dir = sys.argv[1]
    novel = sys.argv[2] if len(sys.argv) > 2 else None
    novel_n = int(sys.argv[3]) if len(sys.argv) > 3 else 3000
    os.makedirs(out_dir, exist_ok=True)

    params = load_params()
    lac = LAC(mode="lac")
    model = lac.model

    weights = write_weights(params, os.path.join(out_dir, "lac_weights.bin"))
    for name in DICTS:
        shutil.copyfile(os.path.join(MODEL_DIR, "conf", name), os.path.join(out_dir, name))
    shutil.copyfile(LICENSE_SOURCE, os.path.join(out_dir, "LICENSE"))

    seg = SegSpec(os.path.join(MODEL_DIR, "conf", "small_seg.dic"))
    texts = OWN_SENTENCES + random_lines(seg.words)
    golden = [reference(model, t) for t in texts]
    with io.open(os.path.join(out_dir, "lac_golden.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write("[\n" + ",\n".join(json.dumps(x, ensure_ascii=False) for x in golden) + "\n]\n")

    # ---- tự kiểm
    check_texts = list(texts)
    if novel:
        with io.open(novel, encoding="utf-8") as f:
            check_texts += [line.strip() for line in f if line.strip()][:novel_n]
    seg_bad = [t for t in check_texts if seg.cut(t) != model.segment_tool.fast_cut(t)]
    emb16 = params["word_emb"].astype(np.float16).astype(np.float32)
    fwd32, fwd16 = make_forward(params, params["word_emb"]), make_forward(params, emb16)
    same32 = same16 = 0
    t0 = time.time()
    for t in check_texts:
        ids, _ = model.dataset.text_to_ids(model.segment_tool.fast_cut(t))
        ref = list(model.predictor.run([model.to_tensor(ids, [0, len(ids)])])[0].data.int64_data())
        same32 += fwd32(ids) == ref
        same16 += fwd16(ids) == ref
    n = len(check_texts)
    print(f"tách từ: lệch {len(seg_bad)}/{n}" + (f" vd {seg_bad[:3]}" if seg_bad else ""))
    print(f"mạng fp32 trùng {same32}/{n} · fp16 trùng {same16}/{n} · {time.time() - t0:.1f}s")

    vocab = max(int(line.split("\t")[0]) for line in io.open(os.path.join(MODEL_DIR, "conf", "word.dic"), encoding="utf-8")
                if "\t" in line) + 1
    manifest = {
        "format": FORMAT_VERSION,
        "source": "LAC 2.1.2 (Baidu, Apache-2.0) lac_model",
        "network": {"vocabSize": vocab, "embeddingDim": H, "hiddenSize": H, "layers": 2,
                    "numLabels": int(params["fc_4.w_0"].shape[1])},
        "tensors": weights,
        "segment": {"dictTotalCount": seg.total, "maxWordLength": seg.maxlen,
                    "logTotal": seg.log_total, "logLength": seg.log_length},
        "golden": {"count": len(golden)},
        "files": {},
    }
    for name in ["lac_weights.bin"] + DICTS + ["lac_golden.json"]:
        manifest["files"][name] = {"bytes": os.path.getsize(os.path.join(out_dir, name)),
                                   "sha256": sha256(os.path.join(out_dir, name))}
    with io.open(os.path.join(out_dir, "lac_manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    check = (f"tách từ viết lại trùng LAC {n - len(seg_bad)}/{n} câu; mạng tính lại (embedding fp16) trùng nhãn LAC "
             f"{same16}/{n} câu")
    write_readme(out_dir, manifest, check)
    print("xong:", out_dir, "· vocab", vocab, "· nhãn", manifest["network"]["numLabels"])


if __name__ == "__main__":
    main()
