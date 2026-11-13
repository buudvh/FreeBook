#!/usr/bin/env python3
"""Tóm tắt các lượt đo của `audiocpp_profile_macos.sh` (P0a, báo cáo tối ưu VieNeu Turbo) thành bảng Markdown.

Mỗi lượt là một thư mục `runs/<tag>/` có:
- `meta.txt`  — key=value: mode (greedy|sample|f32), voice, text, threads, rep
- `run.log`   — log của audio.cpp (`--log-file`): dòng `[TIMING ts=…] <tên> <số>`
- `codes.txt` — `codes_dump_file`: input_ids / reference_codes / generated_codes của từng đoạn
- `out.wav`   — âm thanh ra (đọc header để lấy số giây)
- `time.txt`  — `/usr/bin/time -l` (RAM tối đa)

Bộ đếm giờ là của chính audio.cpp v0.9.4 (`session.cpp`, `talker.cpp`), không thêm gì vào mã. Ý nghĩa:
- prefill    = `talker.prefill_ms`        nạp prompt (chữ + giọng mẫu) qua 12 lớp, gồm cả dựng graph
- backbone   = `talker.cached_step_ms`    1 lượt backbone mỗi khung
- âm học     = `talker.code_predictor_ms` 16 bước bộ giải mã âm học mỗi khung
- codec      = `speech_decoder_ms`        codec MOSS giải mã cả đoạn (kể cả các lượt sinh lại)
- khác       = wall − (prefill + backbone + âm học + codec): lấy mẫu, tra embedding, dựng prompt, ghép tiếng
- gens       = số lần gọi `generate` (1 + lượt sinh lại vì chạm trần / nghi nói lan)
Dùng: python3 summarize.py <thư mục kết quả>
"""
import json
import pathlib
import re
import statistics
import struct
import sys

TIMING = re.compile(r"\[TIMING ts=[^\]]*\]\s+(\S+)\s+(\S+)")
P = "vieneu_v3_turbo."


def read_meta(path):
    meta = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            meta[key.strip()] = value.strip()
    return meta


def read_timings(path):
    sums, counts = {}, {}
    if not path.exists():
        return sums, counts
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = TIMING.search(line)
        if not match:
            continue
        try:
            value = float(match.group(2))
        except ValueError:
            continue
        name = match.group(1)
        sums[name] = sums.get(name, 0.0) + value
        counts[name] = counts.get(name, 0) + 1
    return sums, counts


def read_codes(path):
    tokens = ref = frames = chunks = 0
    if not path.exists():
        return tokens, ref, frames, chunks
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "input_ids":
            tokens += len(parts) - 1
        elif parts[0] == "reference_codes" and len(parts) >= 2:
            ref = int(parts[1])
        elif parts[0] == "generated_codes" and len(parts) >= 2:
            frames += int(parts[1])
            chunks += 1
    return tokens, ref, frames, chunks


def wav_seconds(path):
    """Số giây của WAV (PCM hoặc float) — đọc chunk `fmt ` và `data`, không cần module ngoài."""
    if not path.exists():
        return 0.0
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return 0.0
    offset, rate, channels, bits, size = 12, 0, 0, 0, 0
    while offset + 8 <= len(data):
        cid = data[offset:offset + 4]
        clen = struct.unpack_from("<I", data, offset + 4)[0]
        body = offset + 8
        if cid == b"fmt ":
            _, channels, rate = struct.unpack_from("<HHI", data, body)
            bits = struct.unpack_from("<H", data, body + 14)[0]
        elif cid == b"data":
            size = clen
        offset = body + clen + (clen & 1)
    if rate == 0 or channels == 0 or bits == 0:
        return 0.0
    return size / (rate * channels * (bits // 8))


def max_rss_mb(path):
    if not path.exists():
        return 0.0
    match = re.search(r"(\d+)\s+maximum resident set size", path.read_text(encoding="utf-8", errors="replace"))
    return int(match.group(1)) / 1024 / 1024 if match else 0.0


def load_run(run_dir):
    meta = read_meta(run_dir / "meta.txt")
    sums, counts = read_timings(run_dir / "run.log")
    tokens, ref, frames, chunks = read_codes(run_dir / "codes.txt")
    audio = wav_seconds(run_dir / "out.wav")
    wall = sums.get("session.wall_ms", 0.0)
    prefill = sums.get(P + "talker.prefill_ms", 0.0)
    step = sums.get(P + "talker.cached_step_ms", 0.0)
    acoustic = sums.get(P + "talker.code_predictor_ms", 0.0)
    codec = sums.get(P + "speech_decoder_ms", 0.0)
    return {
        **meta,
        "tag": run_dir.name,
        "tokens": tokens,
        "ref": ref,
        "frames": frames,
        "chunks": chunks,
        "audio_s": audio,
        "wall_ms": wall,
        "prefill_ms": prefill,
        "prefill_build_ms": sums.get(P + "talker.prefill.graph.build_ms", 0.0),
        "step_ms": step,
        "step_compute_ms": sums.get(P + "talker.cached_step.graph.compute_ms", 0.0),
        "acoustic_ms": acoustic,
        "acoustic_compute_ms": sums.get(P + "talker.code_predictor.graph.compute_ms", 0.0),
        "codec_ms": codec,
        "other_ms": wall - prefill - step - acoustic - codec,
        "gens": counts.get(P + "talker.total_ms", 0),
        "rss_mb": max_rss_mb(run_dir / "time.txt"),
        "timings": sums,
    }


def median_runs(runs):
    """Gộp các lần lặp cùng cấu hình: trung vị từng số (runner dùng chung, lệch giữa các lần đáng kể)."""
    keys = ["tokens", "ref", "frames", "audio_s", "wall_ms", "prefill_ms", "prefill_build_ms", "step_ms",
            "step_compute_ms", "acoustic_ms", "acoustic_compute_ms", "codec_ms", "other_ms", "gens", "rss_mb"]
    out = dict(runs[0])
    for key in keys:
        out[key] = statistics.median(run[key] for run in runs)
    out["reps"] = len(runs)
    return out


def pct(part, whole):
    return f"{part / whole:.0%}" if whole > 0 else "—"


def ms(value):
    return f"{value:,.0f}".replace(",", ".")


def rtf(run):
    return f"{run['wall_ms'] / 1000 / run['audio_s']:.3f}" if run["audio_s"] > 0 else "—"


def part_table(runs, title):
    lines = [f"### {title}", "",
             "| Giọng | Câu | Luồng | Token / mẫu / khung | Giây tiếng | RTF | Prefill | Backbone | Âm học | Codec | Khác | Backbone ms/khung | Âm học ms/khung | gens | RAM MB |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for run in runs:
        wall = run["wall_ms"]
        frames = max(run["frames"], 1)
        lines.append(
            f"| {run.get('voice', '?')} | {run.get('text', '?')} | {run.get('threads', '?')} "
            f"| {run['tokens']:.0f} / {run['ref']:.0f} / {run['frames']:.0f} | {run['audio_s']:.2f} | {rtf(run)} "
            f"| {ms(run['prefill_ms'])} ({pct(run['prefill_ms'], wall)}) "
            f"| {ms(run['step_ms'])} ({pct(run['step_ms'], wall)}) "
            f"| {ms(run['acoustic_ms'])} ({pct(run['acoustic_ms'], wall)}) "
            f"| {ms(run['codec_ms'])} ({pct(run['codec_ms'], wall)}) "
            f"| {ms(run['other_ms'])} ({pct(run['other_ms'], wall)}) "
            f"| {run['step_ms'] / frames:.1f} | {run['acoustic_ms'] / frames:.1f} | {run['gens']:.0f} | {run['rss_mb']:.0f} |")
    lines.append("")
    return lines


def main():
    root = pathlib.Path(sys.argv[1])
    runs = [load_run(d) for d in sorted((root / "runs").iterdir()) if (d / "meta.txt").exists()]
    groups = {}
    for run in runs:
        key = (run.get("mode"), run.get("voice"), run.get("text"), run.get("threads"))
        groups.setdefault(key, []).append(run)
    merged = [median_runs(group) for group in groups.values()]
    order = {"ngan": 0, "vua": 1, "dai": 2}

    def sort_key(run):
        return (run.get("voice", ""), order.get(run.get("text", ""), 9), -int(run.get("threads", "0") or 0))

    out = ["## P0a — VieNeu Turbo: thời gian từng phần (audio.cpp, runner macOS)", ""]
    env = root / "env.txt"
    if env.exists():
        out += ["```", env.read_text(encoding="utf-8").strip(), "```", ""]
    sgemm = root / "sgemm.txt"
    if sgemm.exists():
        out += ["### Accelerate `cblas_sgemm` (kiểm AMX)", "", "```", sgemm.read_text(encoding="utf-8").strip(), "```", ""]

    greedy = sorted((r for r in merged if r.get("mode") == "greedy"), key=sort_key)
    out += part_table(greedy, "Greedy (`do_sample=false`, seed 1, tắt chống nói lan) — trung vị các lần lặp")
    # Cộng dồn mọi lượt greedy 2 luồng: tỉ lệ thời gian của cả bộ câu.
    two = [r for r in greedy if r.get("threads") == "2"]
    if two:
        total = {key: sum(r[key] for r in two) for key in ("wall_ms", "prefill_ms", "step_ms", "acoustic_ms", "codec_ms", "other_ms", "audio_s")}
        out += ["**Cộng dồn greedy 2 luồng:** "
                f"RTF {total['wall_ms'] / 1000 / max(total['audio_s'], 1e-6):.3f} · "
                f"prefill {pct(total['prefill_ms'], total['wall_ms'])} · backbone {pct(total['step_ms'], total['wall_ms'])} · "
                f"âm học {pct(total['acoustic_ms'], total['wall_ms'])} · codec {pct(total['codec_ms'], total['wall_ms'])} · "
                f"khác {pct(total['other_ms'], total['wall_ms'])}", ""]
    sample = sorted((r for r in merged if r.get("mode") == "sample"), key=sort_key)
    if sample:
        out += part_table(sample, "Lấy mẫu như trình đọc (mặc định audio.cpp, seed 7) — gens > 1 là có sinh lại")
    f32 = sorted((r for r in merged if r.get("mode") == "f32"), key=sort_key)
    if f32:
        out += part_table(f32, "Đáp án fp32 của talker (`weight_type=f32`; codec vốn đã F32), greedy")
    out += ["Ghi chú: Backbone / Âm học ms/khung chia cho số khung sinh ra (gồm cả lượt sinh lại nếu có). "
            "Codec chạy một lượt mỗi đoạn. Runner dùng chung ⇒ so tỉ lệ trong cùng một lượt CI, đừng so ms tuyệt đối với iPhone.", ""]
    text = "\n".join(out)
    print(text)
    (root / "summary.md").write_text(text + "\n", encoding="utf-8")
    (root / "runs.json").write_text(json.dumps(runs, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
