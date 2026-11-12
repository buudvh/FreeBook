#!/usr/bin/env python3
"""Đối chứng nhân bản giọng VieNeu Turbo của app với pipeline gốc (chạy trên máy tính).

App (1.3.890–893) chép bước chuẩn bị mẫu của `pnnbao97/VieNeu-TTS` sang Swift. Script này chạy **đúng code gốc** (chép
lại nguyên văn các hàm cần, không cài cả gói `vieneu`) để ra file tham chiếu, rồi so với file app chia sẻ từ màn thử
VieNeu Turbo › "Tạo giọng Turbo từ file".

Cần: numpy, onnxruntime, soundfile, soxr, kaldi-native-fbank, librosa (các thư viện upstream dùng). Cài vào venv riêng:
    python -m venv venv && venv/Scripts/python -m pip install numpy onnxruntime soundfile soxr kaldi-native-fbank librosa

Model: thư mục `common/` của kho mirror `raikiri1498/VieNeu-TTS` (`speaker_encoder.onnx`, `denoiser.onnx`). Mã tham chiếu
cần thêm MOSS encoder của upstream (`OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX`: `moss_audio_tokenizer_encode.onnx`
+ `.data`, ~45 MB) — tuỳ chọn.

Lệnh:
    reference WAV --models DIR --out DIR [--no-denoise] [--codec-encoder ONNX]
        Cả pipeline gốc: trim (librosa) → ghi PCM_16 rồi đọc lại → 8 s → denoise → speaker.emb.txt (+ ref_codes.txt),
        kèm trimmed.wav / denoised.wav để so từng bước.
    denoise WAV --models DIR --out WAV
        Chỉ khử nhiễu (đưa vào WAV "sau cắt" của app ⇒ tách sai lệch của bước khử nhiễu).
    embed WAV --models DIR --out TXT
        Chỉ speaker embedding (đưa vào WAV "đưa vào audio.cpp" của app ⇒ tách sai lệch của bước embedding).
    compare [--emb A B] [--codes A B] [--wav A B]
        cosine embedding, % mã trùng (theo khung và codebook), SNR / tương quan giữa hai WAV.

Cách đọc kết quả (đo 2026-11-12 trên PC, một mẫu giọng sạch 24 kHz, dùng 8 s; thuật toán bản Swift mô phỏng bằng numpy):
- Cắt im lặng: bản Swift (`VieNeuSilenceTrimmer`) ra **đúng** mẫu đầu / cuối như librosa 1.0.
- Khử nhiễu: thuật toán bản Swift (DFT nhân ma trận, float32) so bản gốc ⇒ SNR 77,5 dB, embedding cosine 0,999998.
  Trên máy thật còn thêm sai khác do lấy lại tần số (AVAudioConverter thay soxr).
- Mã tham chiếu **rất nhạy**: cùng mẫu, chỉ khác có / không khử nhiễu ⇒ codebook 0 trùng 83 %, đủ 16 mã chỉ 8 % khung
  (embedding cosine 0,991). audio.cpp lấy lại tần số bằng sinc của torchaudio, bản gốc dùng soxr ⇒ mã của app sẽ
  không trùng từng số. Xem codebook 0 + cosine embedding cho có, còn lại phải **nghe**.
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

import numpy as np

MAX_REF_SECONDS = 8.0          # `_MAX_REF_SECONDS` (onnx_runtime_lite.py)
TRIM_TOP_DB = 30               # `_preclean_reference_audio(top_db=30)` (v3turbo.py)
CODEC_RATE = 48_000
CODEC_SAMPLES_PER_FRAME = 3840  # vieneu_utils/core_utils.py

# --- onnx_denoiser.py (nguyên văn thuật toán) ---------------------------------------------------------------------
N_FFT = 1680
HOP = 420
WAV_RATE = 44100
_WIN = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(N_FFT) / N_FFT)


def _stft(x):
    pad = N_FFT // 2
    xp = np.pad(x, (pad, pad), mode="reflect")
    n = 1 + (len(xp) - N_FFT) // HOP
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(n)[:, None]
    frames = xp[idx] * _WIN[None, :]
    spec = np.fft.rfft(frames, n=N_FFT, axis=1).T
    return spec[:, :-1]


def _istft(spec, out_len):
    spec = np.concatenate([spec, spec[:, -1:]], axis=1)
    frames = np.fft.irfft(spec, n=N_FFT, axis=0) * _WIN[:, None]
    count = spec.shape[1]
    siglen = N_FFT + HOP * (count - 1)
    out = np.zeros(siglen)
    wsum = np.zeros(siglen)
    w2 = _WIN ** 2
    for i in range(count):
        s = i * HOP
        out[s:s + N_FFT] += frames[:, i]
        wsum[s:s + N_FFT] += w2
    out = out / np.maximum(wsum, 1e-11)
    pad = N_FFT // 2
    out = out[pad:siglen - pad]
    if len(out) < out_len:
        out = np.pad(out, (0, out_len - len(out)))
    return out[:out_len]


def denoise(wav, sr, session):
    """`OnnxDenoiser.denoise`: float mono (sr bất kỳ) → float32 mono 44,1 kHz."""
    import soxr
    wav = np.asarray(wav, dtype=np.float32).reshape(-1)
    if sr != WAV_RATE:
        wav = soxr.resample(wav, sr, WAV_RATE).astype(np.float32)
    length = len(wav)
    abs_max = max(float(np.abs(wav).max()), 1e-7)
    w = np.pad(wav / abs_max, (0, 441))
    x = w / (np.abs(w).max() + 1e-7)
    s = _stft(x)
    phi = np.angle(s)
    out = session.run(None, {
        "mag": np.abs(s)[None].astype(np.float32),
        "cos": np.cos(phi)[None].astype(np.float32),
        "sin": np.sin(phi)[None].astype(np.float32),
    })
    spec = out[0][0] * (out[1][0] + 1j * out[2][0])
    return (_istft(spec, len(x))[:length] * abs_max).astype(np.float32)


# --- speaker/ (audio_utils.py + fbank.py + onnx_extractor.py) -----------------------------------------------------
def speaker_embedding(wav, sr, session):
    import kaldi_native_fbank as knf
    import soxr
    wav = np.asarray(wav, dtype=np.float32).reshape(-1)
    if sr != 16000:
        wav = soxr.resample(wav, sr, 16000).astype(np.float32)
    opts = knf.FbankOptions()
    opts.frame_opts.samp_freq = 16000
    opts.frame_opts.frame_shift_ms = 10.0
    opts.frame_opts.frame_length_ms = 25.0
    opts.frame_opts.dither = 0.0
    opts.frame_opts.snip_edges = True
    opts.frame_opts.window_type = "povey"
    opts.frame_opts.remove_dc_offset = True
    opts.frame_opts.preemph_coeff = 0.97
    opts.mel_opts.num_bins = 80
    fb = knf.OnlineFbank(opts)
    fb.accept_waveform(16000, wav)
    fb.input_finished()
    feat = np.stack([fb.get_frame(i) for i in range(fb.num_frames_ready)]).astype(np.float32)
    feat = feat - feat.mean(axis=0, keepdims=True)
    name_in = session.get_inputs()[0].name
    return session.run(None, {name_in: feat[None]})[0][0].astype(np.float32)


# --- onnx_runtime_lite.py `_encode_ref_wav` -------------------------------------------------------------------------
def reference_codes(wav, sr, session):
    import soxr
    wav = np.asarray(wav, dtype=np.float32).reshape(-1)
    if sr != CODEC_RATE:
        wav = soxr.resample(wav, sr, CODEC_RATE).astype(np.float32)
    if len(wav) % CODEC_SAMPLES_PER_FRAME:
        wav = np.concatenate([wav, np.zeros(CODEC_SAMPLES_PER_FRAME - len(wav) % CODEC_SAMPLES_PER_FRAME, np.float32)])
    n_frames = len(wav) // CODEC_SAMPLES_PER_FRAME
    stereo = np.stack([wav, wav])[None].astype(np.float32)
    lens = np.array([stereo.shape[-1]], dtype=np.int32)
    out = session.run(None, {"waveform": stereo, "input_lengths": lens})
    return np.asarray(out[0][0], dtype=np.int64)[:n_frames]


# --- I/O ------------------------------------------------------------------------------------------------------------
def session(path):
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.add_session_config_entry("session.intra_op.allow_spinning", "0")
    return ort.InferenceSession(str(path), options, providers=["CPUExecutionProvider"])


def read_mono(path):
    import soundfile as sf
    wav, sr = sf.read(str(path), dtype="float32", always_2d=True)
    return wav.mean(axis=1).astype(np.float32), int(sr)


def write_embedding(path, embedding):
    Path(path).write_text(",".join(f"{float(v):.8f}" for v in embedding), encoding="utf-8")


def read_embedding(path):
    return np.array([float(v) for v in Path(path).read_text(encoding="utf-8").strip().split(",") if v.strip()])


def read_codes(path):
    rows = [line.split() for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]
    return np.array([[int(v) for v in row] for row in rows], dtype=np.int64)


# --- lệnh -----------------------------------------------------------------------------------------------------------
def cmd_reference(args):
    import librosa
    import soundfile as sf
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    models = Path(args.models)
    wav, sr = read_mono(args.wav)
    trimmed, index = librosa.effects.trim(wav, top_db=TRIM_TOP_DB)
    # `_preclean_reference_audio` ghi đoạn đã cắt ra WAV (PCM_16 mặc định của soundfile) rồi `prepare_reference` đọc lại.
    with tempfile.TemporaryDirectory() as folder:
        temp = Path(folder) / "trimmed.wav"
        sf.write(str(temp), trimmed, sr)
        wav, sr = read_mono(temp)
    wav = wav[: int(MAX_REF_SECONDS * sr)]
    sf.write(str(out / "trimmed.wav"), wav, sr)
    info = {"source_rate": sr, "trim_start_s": index[0] / sr, "trim_end_s": index[1] / sr, "used_s": len(wav) / sr}
    if not args.no_denoise:
        wav = denoise(wav, sr, session(models / "denoiser.onnx"))
        sr = WAV_RATE
        sf.write(str(out / "denoised.wav"), wav, sr)
    embedding = speaker_embedding(wav, sr, session(models / "speaker_encoder.onnx"))
    write_embedding(out / "speaker.emb.txt", embedding)
    if args.codec_encoder:
        codes = reference_codes(wav, sr, session(args.codec_encoder))
        (out / "ref_codes.txt").write_text("".join(" ".join(map(str, row)) + "\n" for row in codes), encoding="utf-8")
        info["frames"] = int(codes.shape[0])
    (out / "info.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    print(json.dumps(info, indent=2))


def cmd_denoise(args):
    import soundfile as sf
    wav, sr = read_mono(args.wav)
    sf.write(args.out, denoise(wav, sr, session(Path(args.models) / "denoiser.onnx")), WAV_RATE)
    print(f"đã ghi {args.out}")


def cmd_embed(args):
    wav, sr = read_mono(args.wav)
    write_embedding(args.out, speaker_embedding(wav, sr, session(Path(args.models) / "speaker_encoder.onnx")))
    print(f"đã ghi {args.out}")


def cmd_compare(args):
    if args.emb:
        a, b = (read_embedding(p) for p in args.emb)
        cosine = float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))
        print(f"embedding: cosine {cosine:.6f} · |a| {np.linalg.norm(a):.3f} · |b| {np.linalg.norm(b):.3f} · lệch max {np.abs(a - b).max():.5f}")
    if args.codes:
        a, b = (read_codes(p) for p in args.codes)
        n = min(len(a), len(b))
        same = (a[:n] == b[:n])
        print(f"mã tham chiếu: {len(a)} / {len(b)} khung · trùng {same.mean() * 100:.1f}% mã · "
              f"khung trùng cả 16 mã {same.all(axis=1).mean() * 100:.1f}% · codebook 0 trùng {same[:, 0].mean() * 100:.1f}%")
    if args.wav:
        (a, ra), (b, rb) = (read_mono(p) for p in args.wav)
        if ra != rb:
            import soxr
            b = soxr.resample(b, rb, ra).astype(np.float32)
        n = min(len(a), len(b))
        a, b = a[:n], b[:n]
        noise = np.sum((a - b) ** 2) + 1e-20
        snr = 10 * np.log10(np.sum(a ** 2) / noise + 1e-20)
        corr = float(np.corrcoef(a, b)[0, 1]) if n > 1 else float("nan")
        print(f"wav: {n} mẫu @ {ra} Hz · SNR {snr:.1f} dB · tương quan {corr:.5f} · lệch độ dài {len(a) - len(b)}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    ref = sub.add_parser("reference")
    ref.add_argument("wav")
    ref.add_argument("--models", required=True)
    ref.add_argument("--out", required=True)
    ref.add_argument("--no-denoise", action="store_true")
    ref.add_argument("--codec-encoder")
    for name in ("denoise", "embed"):
        one = sub.add_parser(name)
        one.add_argument("wav")
        one.add_argument("--models", required=True)
        one.add_argument("--out", required=True)
    cmp = sub.add_parser("compare")
    cmp.add_argument("--emb", nargs=2)
    cmp.add_argument("--codes", nargs=2)
    cmp.add_argument("--wav", nargs=2)
    args = parser.parse_args(argv)
    {"reference": cmd_reference, "denoise": cmd_denoise, "embed": cmd_embed, "compare": cmd_compare}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
