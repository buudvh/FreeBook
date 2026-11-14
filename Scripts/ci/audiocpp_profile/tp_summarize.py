#!/usr/bin/env python3
"""Tóm tắt lượt đo threadpool giữ lâu (audiocpp_profile_macos.sh trên nhánh claude/turbo-tp-profile).

Mỗi lượt `runs/<mode>__<voice>__r<rep>/`: meta.txt, run.log (dòng [TIMING …] của audio.cpp), codes.txt, out.wav,
time.txt (/usr/bin/time -l: dòng "<real> real <user> user <sys> sys").
In: theo cấu hình — RTF, ms mỗi giây tiếng của từng phần, CPU-giây mỗi giây tiếng (gồm nạp model, giống nhau mọi cấu
hình), số lượt; và bảng trùng byte (mã + WAV) của mỗi cấu hình tp* so với base cùng giọng / lần lặp.
Dùng: python3 tp_summarize.py <thư mục kết quả>
"""
import pathlib
import re
import struct
import sys

TIMING = re.compile(r"\[TIMING ts=[^\]]*\]\s+(\S+)\s+(\S+)")
P = "vieneu_v3_turbo."
PARTS = [("prefill", P + "talker.prefill_ms"), ("backbone", P + "talker.cached_step_ms"),
         ("âm học", P + "talker.code_predictor_ms"), ("codec", P + "speech_decoder_ms")]


def wav_seconds(path):
    data = path.read_bytes() if path.exists() else b""
    if data[:4] != b"RIFF":
        return 0.0
    offset, rate, channels, bits, size = 12, 0, 0, 0, 0
    while offset + 8 <= len(data):
        cid = data[offset:offset + 4]
        clen = struct.unpack_from("<I", data, offset + 4)[0]
        if cid == b"fmt ":
            _, channels, rate = struct.unpack_from("<HHI", data, offset + 8)
            bits = struct.unpack_from("<H", data, offset + 22)[0]
        elif cid == b"data":
            size = clen
        offset += 8 + clen + (clen & 1)
    return size / (rate * channels * (bits // 8)) if rate and channels and bits else 0.0


def load(run_dir):
    meta = dict(line.split("=", 1) for line in (run_dir / "meta.txt").read_text().splitlines() if "=" in line)
    sums = {}
    log = run_dir / "run.log"
    if log.exists():
        for line in log.read_text(encoding="utf-8", errors="replace").splitlines():
            match = TIMING.search(line)
            if match:
                try:
                    sums[match.group(1)] = sums.get(match.group(1), 0.0) + float(match.group(2))
                except ValueError:
                    pass
    cpu = 0.0
    time_txt = run_dir / "time.txt"
    if time_txt.exists():
        match = re.search(r"([\d.]+)\s+real\s+([\d.]+)\s+user\s+([\d.]+)\s+sys", time_txt.read_text(errors="replace"))
        if match:
            cpu = float(match.group(2)) + float(match.group(3))
    return {
        **meta,
        "dir": run_dir,
        "audio": wav_seconds(run_dir / "out.wav"),
        "wall": sums.get("session.wall_ms", 0.0),
        "parts": {name: sums.get(key, 0.0) for name, key in PARTS},
        "cpu": cpu,
    }


def same_bytes(a, b):
    return a.exists() and b.exists() and a.read_bytes() == b.read_bytes()


def main():
    root = pathlib.Path(sys.argv[1])
    runs = [load(d) for d in sorted((root / "runs").iterdir()) if (d / "meta.txt").exists()]
    modes = []
    for run in runs:
        if run["mode"] not in modes:
            modes.append(run["mode"])
    out = ["## Threadpool giữ lâu — VieNeu Turbo (audio.cpp, runner macOS)", ""]
    env = root / "env.txt"
    if env.exists():
        out += ["```", env.read_text(encoding="utf-8").strip(), "```", ""]
    out += ["| Cấu hình | Lượt | Giây tiếng | RTF | Prefill | Backbone | Âm học | Codec | CPU-s / giây tiếng |",
            "|---|---|---|---|---|---|---|---|---|"]
    base_rtf = None
    for mode in modes:
        group = [r for r in runs if r["mode"] == mode and r["audio"] > 0]
        if not group:
            out.append(f"| {mode} | 0 | — | — | — | — | — | — | — |")
            continue
        audio = sum(r["audio"] for r in group)
        rtf = sum(r["wall"] for r in group) / 1000 / audio
        if mode == "base":
            base_rtf = rtf
        parts = {name: sum(r["parts"][name] for r in group) / audio for name, _ in PARTS}
        delta = f" ({rtf / base_rtf - 1:+.0%})" if base_rtf and mode != "base" else ""
        out.append(f"| {mode} | {len(group)} | {audio:.0f} | {rtf:.3f}{delta} | "
                   + " | ".join(f"{parts[name]:.0f}" for name, _ in PARTS)
                   + f" | {sum(r['cpu'] for r in group) / audio:.2f} |")
    out += ["", "Prefill / Backbone / Âm học / Codec: ms mỗi giây tiếng. CPU-s gồm cả nạp model (giống nhau mọi cấu hình).",
            "", "### Trùng byte với base (cùng giọng, cùng lần lặp)", "", "| Cấu hình | Mã trùng | WAV trùng | Lượt so |", "|---|---|---|---|"]
    failures = 0
    for mode in modes:
        if mode == "base":
            continue
        codes_ok = wav_ok = total = 0
        for run in [r for r in runs if r["mode"] == mode]:
            base_dir = run["dir"].parent / f"base__{run['voice']}__r{run['rep']}"
            total += 1
            codes_ok += same_bytes(run["dir"] / "codes.txt", base_dir / "codes.txt")
            wav_ok += same_bytes(run["dir"] / "out.wav", base_dir / "out.wav")
        failures += (total - codes_ok) + (total - wav_ok)
        out.append(f"| {mode} | {codes_ok}/{total} | {wav_ok}/{total} | {total} |")
    out.append("")
    text = "\n".join(out)
    print(text)
    (root / "summary.md").write_text(text + "\n", encoding="utf-8")
    if failures:
        print(f"::error::threadpool đổi kết quả ở {failures} phép so (phải trùng từng byte)")


if __name__ == "__main__":
    main()
