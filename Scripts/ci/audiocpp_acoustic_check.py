#!/usr/bin/env python3
"""Chấm bộ giải mã âm học của VieNeu Turbo khi repack trọng số (bản vá `vieneu_acoustic_repack`, 1.3.930).

Repack chỉ đổi thứ tự cộng fp32 giữa các khối q8_0, nhưng một chênh ~1e-7 đôi khi làm một activation đổi nấc khi lượng tử
q8 ở ma trận kế ⇒ logit của bước đó lệch cỡ một nấc lượng tử (đo CI 2026-11-14: lớn nhất 1,1·10⁻² tương đối). Mã greedy vì
vậy có thể rẽ ở chỗ **hai mã gần hoà**; sau chỗ rẽ hai chuỗi tự hồi quy khác nhau nên không so tiếp được. Nên không đòi
trùng từng byte mà chấm:

1. Mọi bước trước chỗ rẽ: sai số tương đối L2 của logit ≤ `MAX_REL_ERROR` (nhiễu lượng tử q8, không phải lỗi bố cục —
   dùng sai trọng số repack cho ra rác, sai số cỡ 1).
2. Nếu greedy rẽ: ở bước đó top1 − top2 (logit của base) ≤ `MAX_TIE_MARGIN` — tức chỉ rẽ ở chỗ gần hoà.
3. Phải so được ít nhất `MIN_STEPS` bước (một khung = 16 bước).

Đầu vào: hai file `VIENEU_LOGITS_DUMP` (mỗi khung `prefill_hidden …` + 16 dòng `logits <nhóm> …`), cùng câu / giọng / greedy.
Dùng: python3 audiocpp_acoustic_check.py <dump_base> <dump_repack>   — exit 1 nếu không đạt.
"""
import math
import sys

MAX_REL_ERROR = 3e-2
MAX_TIE_MARGIN = 0.25
MIN_STEPS = 16


def read_steps(path):
    frames = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("prefill_hidden"):
                frames.append([])
            elif line.startswith("logits ") and frames:
                parts = line.split()
                frames[-1].append((int(parts[1]), [float(v) for v in parts[2:]]))
    return frames


def argmax(values):
    return max(range(len(values)), key=values.__getitem__)


def main():
    base, test = read_steps(sys.argv[1]), read_steps(sys.argv[2])
    errors = []
    divergence = None
    for frame_index, (frame_b, frame_t) in enumerate(zip(base, test)):
        for (group_b, logits_b), (group_t, logits_t) in zip(frame_b, frame_t):
            if group_b != group_t or len(logits_b) != len(logits_t):
                sys.exit(f"khung {frame_index}: lệch cấu trúc (nhóm {group_b}/{group_t}, {len(logits_b)}/{len(logits_t)} logit)")
            diff = math.sqrt(sum((a - b) ** 2 for a, b in zip(logits_t, logits_b)))
            norm = math.sqrt(sum(b * b for b in logits_b))
            errors.append(diff / max(norm, 1e-30))
            if argmax(logits_b) != argmax(logits_t):
                ordered = sorted(logits_b, reverse=True)
                divergence = (frame_index, group_b, ordered[0] - ordered[1])
                break
        if divergence is not None:
            break
    if len(errors) < MIN_STEPS:
        print(f"Chỉ so được {len(errors)} bước (< {MIN_STEPS})")
        sys.exit(1)
    worst = max(errors)
    print(f"Khung: base {len(base)} · repack {len(test)} — đã so {len(errors)} bước; "
          f"sai số logit trung vị {sorted(errors)[len(errors) // 2]:.3e} · lớn nhất {worst:.3e} (ngưỡng {MAX_REL_ERROR:g})")
    ok = worst <= MAX_REL_ERROR
    if divergence is None:
        print("Mã greedy trùng hết" + (" (số khung khác nhau)" if len(base) != len(test) else ""))
    else:
        frame_index, group, margin = divergence
        near_tie = margin <= MAX_TIE_MARGIN
        print(f"Mã greedy rẽ ở khung {frame_index}, bước {group}: top1 − top2 của base = {margin:.3e} "
              f"({'gần hoà' if near_tie else 'KHÔNG gần hoà'}, ngưỡng {MAX_TIE_MARGIN:g})")
        ok = ok and near_tie
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
