#!/usr/bin/env python3
"""Chấm logit bộ giải mã âm học của VieNeu Turbo: cấu hình thử (repack) so với cấu hình app, cùng câu / giọng / greedy.

Mỗi file là `VIENEU_LOGITS_DUMP`: mỗi khung một dòng `prefill_hidden …` rồi 16 dòng `logits <nhóm> …` (một dòng mỗi bước).
Hai lượt cùng đầu vào cho tới khi mã greedy (argmax) lệch lần đầu; sau đó chuỗi rẽ nhánh nên chỉ so tới khung đó.
In: số bước đã so, sai số tương đối L2 của logit (trung vị / lớn nhất), lệch tối đa tuyệt đối, khung + bước lệch mã đầu
tiên (nếu có) và hiệu logit top-1 − top-2 ở bước đó (gần 0 = hoà sát nút, lệch do làm tròn là bình thường).
Dùng: python3 rp_logits_check.py <dump_base> <dump_thử>
"""
import math
import sys


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
    errors, max_abs, steps = [], 0.0, 0
    first_diff = None
    worst = []  # (sai số, khung, nhóm, chuẩn base, top1 − top2)
    for frame_index, (frame_b, frame_t) in enumerate(zip(base, test)):
        for (group_b, logits_b), (group_t, logits_t) in zip(frame_b, frame_t):
            if group_b != group_t or len(logits_b) != len(logits_t):
                sys.exit(f"khung {frame_index}: lệch cấu trúc (nhóm {group_b}/{group_t}, {len(logits_b)}/{len(logits_t)} logit)")
            diff = math.sqrt(sum((a - b) ** 2 for a, b in zip(logits_t, logits_b)))
            norm = math.sqrt(sum(b * b for b in logits_b))
            errors.append(diff / max(norm, 1e-30))
            if errors[-1] > 0:
                ordered = sorted(logits_b, reverse=True)
                worst.append((errors[-1], frame_index, group_b, norm, ordered[0] - ordered[1], len(logits_b)))
            max_abs = max(max_abs, max(abs(a - b) for a, b in zip(logits_t, logits_b)))
            steps += 1
            if argmax(logits_b) != argmax(logits_t):
                ordered = sorted(logits_b, reverse=True)
                first_diff = (frame_index, group_b, ordered[0] - ordered[1])
                break
        if first_diff is not None:
            break
    if not errors:
        sys.exit("không có bước nào để so")
    errors.sort()
    print(f"Khung: base {len(base)} · thử {len(test)} — đã so {steps} bước")
    print(f"Sai số tương đối L2 của logit: trung vị {errors[len(errors) // 2]:.3e} · lớn nhất {errors[-1]:.3e} "
          f"· lệch tuyệt đối lớn nhất {max_abs:.3e}")
    print(f"Bước có lệch: {sum(e > 0 for e in errors)} · > 1e-6: {sum(e > 1e-6 for e in errors)} "
          f"· > 1e-4: {sum(e > 1e-4 for e in errors)} · > 1e-3: {sum(e > 1e-3 for e in errors)}")
    by_group = {}
    for err, _, group, _, _, _ in worst:
        by_group[group] = by_group.get(group, 0) + 1
    print("Số bước lệch theo nhóm: " + ", ".join(f"{g}:{n}" for g, n in sorted(by_group.items())))
    for err, frame_index, group, norm, margin, size in sorted(worst, reverse=True)[:6]:
        print(f"  khung {frame_index} nhóm {group}: sai số {err:.3e} · chuẩn {norm:.3e} · top1−top2 {margin:.3e} · {size} logit")
    if first_diff is None:
        print("Mã greedy trùng hết" + (" (số khung khác nhau)" if len(base) != len(test) else ""))
    else:
        frame_index, group, margin = first_diff
        print(f"Mã greedy lệch lần đầu ở khung {frame_index}, bước {group} (top1 − top2 của base = {margin:.3e})")


if __name__ == "__main__":
    main()
