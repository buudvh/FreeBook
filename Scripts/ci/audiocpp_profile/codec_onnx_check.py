#!/usr/bin/env python3
"""Hướng 3 (báo cáo tối ưu Turbo §18): codec MOSS của Turbo chạy bằng graph ONNX chính thức có ra đúng tiếng không.

So graph `moss_audio_tokenizer_decode_full.onnx` (HF OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX, revision ghim) với codec
của audio.cpp trên cùng mã âm thanh (`codes_dump_file`, mỗi lượt một đoạn — `text_chunk_size` lớn):
1. ONNX Runtime CPU: SNR (dB) so với WAV audio.cpp, thời gian giải mã (ms mỗi giây tiếng) so với `speech_decoder_ms`.
2. Độn mã tới cỡ cố định (bội 32 khung) + `audio_code_lengths` = độ dài thật ⇒ phần đầu có giữ nguyên không (Neural
   Engine cần cỡ cố định — khuôn bucket của Nano).
3. Core ML EP (MLProgram): số node Core ML nhận / tổng node, SNR, thời gian. Máy ảo không có Neural Engine ⇒ tốc độ
   Core ML ở đây không nói gì về iPhone; chỉ xem đúng/sai + độ phủ.
Dùng: python3 codec_onnx_check.py <thư mục onnx> <thư mục runs>   (mỗi run có codes.txt, out.wav, run.log)
"""
import math
import os
import pathlib
import re
import struct
import sys
import tempfile
import time

import numpy as np
import onnxruntime as ort

DOWNSAMPLE = 3840


def read_wav(path):
    data = path.read_bytes()
    offset, fmt, channels, rate, bits, payload = 12, None, 0, 0, 0, b""
    while offset + 8 <= len(data):
        cid, size = data[offset:offset + 4], struct.unpack_from("<I", data, offset + 4)[0]
        body = data[offset + 8:offset + 8 + size]
        if cid == b"fmt ":
            fmt, channels, rate = struct.unpack_from("<HHI", body, 0)
            bits = struct.unpack_from("<H", body, 14)[0]
        elif cid == b"data":
            payload = body
        offset += 8 + size + (size & 1)
    if fmt == 3 or (fmt == 0xFFFE and bits == 32):
        samples = np.frombuffer(payload, dtype="<f4").astype(np.float64)
    elif bits == 16:
        samples = np.frombuffer(payload, dtype="<i2").astype(np.float64) / 32768.0
    else:
        sys.exit(f"{path}: WAV fmt={fmt} bits={bits} chưa đọc được")
    return samples.reshape(-1, channels).T, rate  # [channels, samples]


def read_codes(path):
    for line in path.read_text().splitlines():
        if line.startswith("generated_codes "):
            parts = line.split()
            frames, groups = int(parts[1]), int(parts[2])
            values = np.array([int(v) for v in parts[3:]], dtype=np.int64)
            return values.reshape(frames, groups).T  # [groups, frames]
    sys.exit(f"{path}: không có dòng generated_codes")


def snr_db(test, ref):
    n = min(test.shape[-1], ref.shape[-1])
    noise = np.sum((test[..., :n] - ref[..., :n]) ** 2)
    signal = np.sum(ref[..., :n] ** 2)
    return 10 * math.log10(signal / max(noise, 1e-30))


def best_aligned_snr(test, ref, max_shift=DOWNSAMPLE):
    """audio.cpp có thể lệch vài mẫu đầu/cuối — thử dịch ±max_shift, lấy SNR lớn nhất."""
    best = (-1e9, 0)
    for shift in range(-max_shift, max_shift + 1, 16):
        a = test[..., max(shift, 0):]
        b = ref[..., max(-shift, 0):]
        best = max(best, (snr_db(a, b), shift))
    shift = best[1]
    for fine in range(shift - 16, shift + 17):
        a = test[..., max(fine, 0):]
        b = ref[..., max(-fine, 0):]
        best = max(best, (snr_db(a, b), fine))
    return best


def make_inputs(session, codes, frames_total):
    """Đầu vào theo khai báo của graph: audio_codes [1,16,T] hoặc [16,1,T]; audio_code_lengths [1]."""
    feeds = {}
    for spec in session.get_inputs():
        if spec.name == "audio_codes":
            shape = spec.shape
            padded = np.zeros((codes.shape[0], frames_total), dtype=np.int64)
            padded[:, :codes.shape[1]] = codes
            if len(shape) == 3 and shape[-1] in (16, "16"):
                feeds[spec.name] = padded.T[None, :, :]  # [batch, khung, 16]
            elif len(shape) == 3 and shape[0] in (16, "16"):
                feeds[spec.name] = padded[:, None, :]
            else:
                feeds[spec.name] = padded[None, :, :]
            feeds[spec.name] = np.ascontiguousarray(feeds[spec.name])
            if "int32" in spec.type:
                feeds[spec.name] = feeds[spec.name].astype(np.int32)
        elif spec.name == "audio_code_lengths":
            dtype = np.int32 if "int32" in spec.type else np.int64
            feeds[spec.name] = np.array([codes.shape[1]], dtype=dtype)
    return feeds


def decode(session, codes, frames_total, repeats=3):
    feeds = make_inputs(session, codes, frames_total)
    best_ms, out = 1e18, None
    for _ in range(repeats):
        start = time.perf_counter()
        out = session.run(None, feeds)
        best_ms = min(best_ms, (time.perf_counter() - start) * 1000)
    audio = np.asarray(out[0], dtype=np.float64)
    audio = audio.reshape(-1, audio.shape[-1]) if audio.ndim >= 2 else audio[None, :]
    if len(out) > 1:
        length = int(np.asarray(out[1]).reshape(-1)[0])
        audio = audio[:, :length]
    return audio, best_ms


def coreml_session(model_path, options, free_dims=None):
    """Tạo session Core ML, bắt log verbose của ORT để đọc số node Core ML nhận. `free_dims` = cố định chiều động lúc
    tạo session (`add_free_dimension_override_by_name`) thay vì sửa file model."""
    log_path = tempfile.mktemp(suffix=".log")
    saved = os.dup(2)
    with open(log_path, "w") as handle:
        os.dup2(handle.fileno(), 2)
        try:
            so = ort.SessionOptions()
            so.log_severity_level = 0
            for name, value in (free_dims or {}).items():
                so.add_free_dimension_override_by_name(name, value)
            session = ort.InferenceSession(
                str(model_path), sess_options=so,
                providers=[("CoreMLExecutionProvider", options), "CPUExecutionProvider"])
        finally:
            os.dup2(saved, 2)
            os.close(saved)
    text = pathlib.Path(log_path).read_text(errors="replace")
    unsupported = {}
    for op_type in re.findall(r"Operator type: \[(\w+)\][^\n]*supported: \[0\]", text):
        unsupported[op_type] = unsupported.get(op_type, 0) + 1
    if unsupported:
        listing = ", ".join(f"{name}×{count}" for name, count in sorted(unsupported.items(), key=lambda kv: -kv[1]))
        print(f"    op Core ML không nhận ({model_path.name}): {listing}")
    else:
        reasons = sorted(set(re.findall(r"(?:not supported|unsupported)[^\n]{0,120}", text)))[:12]
        if reasons:
            print(f"    lý do không nhận ({model_path.name}): " + " | ".join(reasons))
    found = re.findall(r"number of nodes in the graph: (\d+).*?number of nodes supported by CoreML: (\d+)", text, re.S)
    partitions = re.findall(r"number of partitions supported by CoreML: (\d+)", text)
    coverage = f"{found[-1][1]}/{found[-1][0]} node, {partitions[-1] if partitions else '?'} mảnh" if found else "không đọc được log độ phủ"
    return session, coverage


def main():
    onnx_dir, runs_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    model = onnx_dir / "moss_audio_tokenizer_decode_full.onnx"
    print(f"onnxruntime {ort.__version__} · providers {ort.get_available_providers()}")
    cpu = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])
    for spec in cpu.get_inputs():
        print(f"  vào  {spec.name} {spec.shape} {spec.type}")
    for spec in cpu.get_outputs():
        print(f"  ra   {spec.name} {spec.shape} {spec.type}")

    coreml_options = {"ModelFormat": "MLProgram", "MLComputeUnits": "ALL"}
    coreml = None
    if "CoreMLExecutionProvider" in ort.get_available_providers():
        try:
            coreml, coverage = coreml_session(model, coreml_options)
            print(f"Core ML EP (shape động): {coverage}")
        except Exception as error:  # noqa: BLE001 — chỉ là phép đo
            print(f"Core ML EP lỗi khi tạo session: {error}")

    print("| Đoạn | Khung | Giây | audio.cpp codec ms/s | ONNX CPU ms/s | SNR CPU (dB, lệch mẫu) | SNR độn khung (dB) | Core ML ms/s | SNR Core ML (dB) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for run in sorted(p for p in runs_dir.iterdir() if (p / "codes.txt").exists()):
        codes = read_codes(run / "codes.txt")
        ref, rate = read_wav(run / "out.wav")
        frames = codes.shape[1]
        seconds = frames * DOWNSAMPLE / 48000
        log = (run / "run.log").read_text(errors="replace") if (run / "run.log").exists() else ""
        decoder_ms = sum(float(m) for m in re.findall(r"vieneu_v3_turbo\.speech_decoder_ms (\S+)", log))
        audio, cpu_ms = decode(cpu, codes, frames)
        if audio.shape[0] != ref.shape[0]:
            audio_cmp = audio.mean(axis=0, keepdims=True) if ref.shape[0] == 1 else audio
        else:
            audio_cmp = audio
        snr, shift = best_aligned_snr(audio_cmp, ref)
        bucket = ((frames + 31) // 32) * 32 + 32
        padded, _ = decode(cpu, codes, bucket, repeats=1)
        snr_pad = snr_db(padded[..., :audio.shape[-1]], audio)
        coreml_cell = "—", "—"
        if coreml is not None:
            try:
                audio_ml, ml_ms = decode(coreml, codes, frames)
                coreml_cell = f"{ml_ms / seconds:.0f}", f"{snr_db(audio_ml, audio):.1f}"
            except Exception as error:  # noqa: BLE001
                coreml_cell = "lỗi", str(error)[:60]
        print(f"| {run.name} | {frames} | {seconds:.1f} | {decoder_ms / seconds:.0f} | {cpu_ms / seconds:.0f} | "
              f"{snr:.1f} ({shift:+d}) | {snr_pad:.1f} | {coreml_cell[0]} | {coreml_cell[1]} |")
    print(f"\nWAV audio.cpp: {ref.shape[0]} kênh, {rate} Hz. ONNX ra {audio.shape[0]} kênh.")

    # Shape cố định (bucket) — Neural Engine chỉ nhận graph shape tĩnh. Đếm node / mảnh Core ML nhận, SNR so với CPU.
    try:
        import onnx
        from onnxruntime.tools.onnx_model_utils import fix_output_shapes, make_dim_param_fixed
    except Exception as error:  # noqa: BLE001
        print(f"Không có onnx / onnx_model_utils: {error}")
        return
    runs = sorted(p for p in runs_dir.iterdir() if (p / "codes.txt").exists())
    # Cố định chiều lúc tạo session trên file GỐC (cách màn test trên máy sẽ làm — không phải tự lưu trữ model).
    for bucket in (64,):
        try:
            options = dict(coreml_options, RequireStaticInputShapes="1")
            session, coverage = coreml_session(model, options, {"batch": 1, "code_length": bucket})
            codes = read_codes(runs[0] / "codes.txt")
            reference, _ = decode(cpu, codes, codes.shape[1], repeats=1)
            audio_ml, _ = decode(session, codes, bucket, repeats=1)
            print(f"\nFile gốc + free dimension override (T={bucket}): {coverage}; SNR so với CPU "
                  f"{snr_db(audio_ml[..., :reference.shape[-1]], reference):.1f} dB")
        except Exception as error:  # noqa: BLE001
            print(f"\nFile gốc + free dimension override (T={bucket}) lỗi: {str(error)[:160]}")
    print("\n| Bucket (khung) | Core ML nhận | Đoạn thử | ms/s Core ML (máy ảo) | SNR so với CPU (dB) |")
    print("|---|---|---|---|---|")
    for bucket in (64, 128):
        fixed_path = onnx_dir / f"decode_full_T{bucket}.onnx"
        try:
            model_proto = onnx.load(str(model))
            make_dim_param_fixed(model_proto.graph, "batch", 1)
            make_dim_param_fixed(model_proto.graph, "code_length", bucket)
            fix_output_shapes(model_proto)
            onnx.save(model_proto, str(fixed_path))
            options = dict(coreml_options, RequireStaticInputShapes="1")
            session, coverage = coreml_session(fixed_path, options)
        except Exception as error:  # noqa: BLE001
            print(f"| {bucket} | lỗi: {str(error)[:80]} | | | |")
            continue
        for run in runs:
            codes = read_codes(run / "codes.txt")
            if codes.shape[1] > bucket:
                continue
            seconds = codes.shape[1] * DOWNSAMPLE / 48000
            reference, _ = decode(cpu, codes, codes.shape[1], repeats=1)
            try:
                audio_ml, ml_ms = decode(session, codes, bucket)
                print(f"| {bucket} | {coverage} | {run.name} ({codes.shape[1]} khung) | {ml_ms / seconds:.0f} | "
                      f"{snr_db(audio_ml[..., :reference.shape[-1]], reference):.1f} |")
            except Exception as error:  # noqa: BLE001
                print(f"| {bucket} | {coverage} | {run.name} | lỗi | {str(error)[:60]} |")


if __name__ == "__main__":
    main()
