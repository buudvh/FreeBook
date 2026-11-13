#!/usr/bin/env python3
"""Chấm bước nạp prompt của VieNeu Turbo qua Accelerate (bản vá `vieneu_prefill_blas`, 1.3.927).

Đường BLAS bỏ bước lượng tử hoá activation về q8 nên **không** trùng từng byte với đường CPU q8 đang chạy; thước đo là
khoảng cách tới đáp án fp32 (`vieneu_v3_turbo.weight_type=f32` — cùng trọng số q8 giải lượng tử ra fp32, tính fp32).
So vector ẩn cuối của bước nạp prompt (đầu vào bộ giải mã âm học ở khung đầu tiên — dòng `prefill_hidden` đầu tiên của
`VIENEU_LOGITS_DUMP`, đo trước mọi lấy mẫu), sai số tương đối L2 = ‖x − fp32‖ / ‖fp32‖.

Đạt khi: sai số BLAS < sai số q8 (BLAS phải gần bản gốc hơn đường đang chạy) và < 1e-3.
Dùng: python3 audiocpp_prefill_check.py <dump_q8> <dump_blas> <dump_f32>
"""
import math
import sys


def first_hidden(path):
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("prefill_hidden "):
                return [float(value) for value in line.split()[1:]]
    sys.exit(f"{path}: không có dòng prefill_hidden")


def rel_error(x, ref):
    if len(x) != len(ref):
        sys.exit(f"khác độ dài vector: {len(x)} ≠ {len(ref)}")
    diff = math.sqrt(sum((a - b) ** 2 for a, b in zip(x, ref)))
    norm = math.sqrt(sum(b * b for b in ref))
    return diff / max(norm, 1e-30)


def main():
    q8, blas, f32 = (first_hidden(path) for path in sys.argv[1:4])
    err_q8 = rel_error(q8, f32)
    err_blas = rel_error(blas, f32)
    print(f"Sai số tương đối so với fp32 — đường q8 đang chạy: {err_q8:.3e} · đường BLAS: {err_blas:.3e} "
          f"({len(f32)} chiều)")
    if not (err_blas < err_q8 and err_blas < 1e-3):
        print("Đường BLAS KHÔNG gần bản fp32 hơn đường q8 (hoặc sai số ≥ 1e-3)")
        sys.exit(1)


if __name__ == "__main__":
    main()
