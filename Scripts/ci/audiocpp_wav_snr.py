#!/usr/bin/env python3
"""So hai file WAV cùng độ dài bằng SNR (dB) — job parity dùng để chấm codec qua Accelerate với đường CPU thường.

SNR = 10·log10(Σ ref² / Σ (ref − test)²); trùng từng mẫu ⇒ "inf". Đọc WAV PCM nguyên (16/24/32 bit) hoặc float 32 bit,
chỉ dùng thư viện chuẩn. Exit 1 khi khác số kênh / tần số / số mẫu, hoặc SNR dưới ngưỡng `--min-db`.
Dùng: python3 audiocpp_wav_snr.py <ref.wav> <test.wav> [--min-db 90]
"""
import argparse
import math
import struct
import sys


def read_wav(path):
    data = open(path, "rb").read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        sys.exit(f"{path}: không phải WAV")
    offset, fmt, payload = 12, None, None
    while offset + 8 <= len(data):
        cid = data[offset:offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        body = data[offset + 8:offset + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", body, 0)
            if fmt[0] == 0xFFFE and len(body) >= 26:
                # WAVE_FORMAT_EXTENSIBLE: định dạng thật là 2 byte đầu của GUID SubFormat (offset 24).
                fmt = (struct.unpack_from("<H", body, 24)[0],) + fmt[1:]
        elif cid == b"data":
            payload = body
        offset += 8 + size + (size & 1)
    if fmt is None or payload is None:
        sys.exit(f"{path}: thiếu chunk fmt / data")
    tag, channels, rate, _, _, bits = fmt
    if tag == 3 and bits == 32:
        samples = struct.unpack(f"<{len(payload) // 4}f", payload)
    elif tag == 1 and bits == 16:
        samples = [v / 32768.0 for v in struct.unpack(f"<{len(payload) // 2}h", payload)]
    elif tag == 1 and bits == 32:
        samples = [v / 2147483648.0 for v in struct.unpack(f"<{len(payload) // 4}i", payload)]
    elif tag == 1 and bits == 24:
        samples = [int.from_bytes(payload[i:i + 3], "little", signed=True) / 8388608.0
                   for i in range(0, len(payload) - 2, 3)]
    else:
        sys.exit(f"{path}: định dạng WAV chưa hỗ trợ (tag {tag}, {bits} bit)")
    return channels, rate, samples


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ref")
    parser.add_argument("test")
    parser.add_argument("--min-db", type=float, default=None)
    args = parser.parse_args()
    ref_ch, ref_rate, ref = read_wav(args.ref)
    test_ch, test_rate, test = read_wav(args.test)
    if (ref_ch, ref_rate, len(ref)) != (test_ch, test_rate, len(test)):
        print(f"KHÁC khuôn: {ref_ch} kênh {ref_rate} Hz {len(ref)} mẫu ≠ {test_ch} kênh {test_rate} Hz {len(test)} mẫu")
        sys.exit(1)
    signal = sum(v * v for v in ref)
    noise = sum((a - b) * (a - b) for a, b in zip(ref, test))
    peak = max((abs(a - b) for a, b in zip(ref, test)), default=0.0)
    snr = math.inf if noise == 0 else 10 * math.log10(max(signal, 1e-30) / noise)
    print(f"SNR {snr:.1f} dB · max|Δ| {peak:.3g} · {len(ref)} mẫu")
    if args.min_db is not None and snr < args.min_db:
        print(f"SNR dưới ngưỡng {args.min_db} dB")
        sys.exit(1)


if __name__ == "__main__":
    main()
