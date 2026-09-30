"""Gate A — macOS CI harness for `Sources/Services/TTS/VieNeu/VieNeuFbank.swift`.

This is the *independent* side of the fbank cross-check: it implements the Kaldi 80-mel
front-end on numpy's own FFT (no shared code with the Swift), so that agreement between
the two is real evidence and not a shared misunderstanding.

    python Scripts/FbankGate/gate.py probe   probe.wav
    python Scripts/FbankGate/gate.py golden  probe.wav golden.csv
    python Scripts/FbankGate/gate.py compare golden.csv swift.csv

Ported from upstream `pnnbao97/VieNeu-TTS`:
  src/vieneu/_v3_turbo_engine/speaker/audio_utils.py (_kaldi_fbank)
  src/vieneu/_v3_turbo_engine/speaker/fbank.py       (extract_speaker_fbank)
Kaldi params: 16 kHz, 80 mel, frame 25 ms / shift 10 ms, povey, preemph 0.97,
remove_dc_offset, snip_edges=True, dither=0, low_freq=20, high_freq=0 (Nyquist),
use_energy=False, htk_mode=False (no area normalisation), use_power=True, natural log,
floor = FLT_EPSILON. Waveform is fed as float in [-1, 1] with NO *32768 scaling.
"""

from __future__ import annotations

import math
import sys
import wave

import numpy as np

SAMPLE_RATE = 16000
N_MELS = 80
FRAME_LENGTH_MS = 25.0
FRAME_SHIFT_MS = 10.0
PREEMPH = 0.97
LOW_FREQ = 20.0
HIGH_FREQ = 0.0
EPS = float(np.finfo(np.float32).eps)
TOLERANCE = 1e-4


# --------------------------------------------------------------------------- reference

def mel_scale(freq):
    return 1127.0 * np.log(1.0 + np.asarray(freq, dtype=np.float64) / 700.0)


def povey_window(frame_length: int) -> np.ndarray:
    a = 2.0 * math.pi / (frame_length - 1)
    i = np.arange(frame_length, dtype=np.float64)
    return np.power(0.5 - 0.5 * np.cos(a * i), 0.85)


def mel_banks(num_bins: int, padded: int, sample_rate: float) -> np.ndarray:
    num_fft_bins = padded // 2
    high = HIGH_FREQ if HIGH_FREQ > 0 else HIGH_FREQ + 0.5 * sample_rate
    mel_low, mel_high = mel_scale(LOW_FREQ), mel_scale(high)
    delta = (mel_high - mel_low) / (num_bins + 1)
    fft_bin_width = sample_rate / padded
    mels = mel_scale(fft_bin_width * np.arange(num_fft_bins, dtype=np.float64))

    banks = np.zeros((num_bins, num_fft_bins), dtype=np.float64)
    for b in range(num_bins):
        left = mel_low + b * delta
        center = mel_low + (b + 1) * delta
        right = mel_low + (b + 2) * delta
        weight = np.where(mels <= center,
                          (mels - left) / (center - left),
                          (right - mels) / (right - center))
        banks[b] = np.where((mels > left) & (mels < right), weight, 0.0)
    return banks


def kaldi_fbank(wav: np.ndarray, sample_rate: int = SAMPLE_RATE, num_mel_bins: int = N_MELS) -> np.ndarray:
    frame_length = int(round(FRAME_LENGTH_MS * sample_rate / 1000.0))
    frame_shift = int(round(FRAME_SHIFT_MS * sample_rate / 1000.0))
    n = wav.shape[0]
    num_frames = 1 + (n - frame_length) // frame_shift if n >= frame_length else 0
    if num_frames <= 0:
        raise ValueError(f"audio too short ({n} samples @ {sample_rate} Hz)")

    padded = 1
    while padded < frame_length:
        padded *= 2

    idx = np.arange(frame_length)[None, :] + frame_shift * np.arange(num_frames)[:, None]
    frames = wav[idx].astype(np.float64)
    frames = frames - frames.mean(axis=1, keepdims=True)            # remove_dc_offset
    shifted = np.concatenate([frames[:, :1], frames[:, :-1]], axis=1)
    frames = frames - PREEMPH * shifted                             # preemphasis (replicate pad)
    frames = frames * povey_window(frame_length)[None, :]           # window last

    spec = np.fft.rfft(frames, n=padded, axis=1)
    power = spec.real ** 2 + spec.imag ** 2                         # use_power=True

    banks = mel_banks(num_mel_bins, padded, float(sample_rate))
    energies = power[:, : banks.shape[1]] @ banks.T
    energies = np.maximum(energies, EPS)                            # ApplyFloor
    return np.log(energies).astype(np.float32)                      # ApplyLog (natural)


# --------------------------------------------------------------------------- probe

def generate_probe(path: str, seconds: float = 6.0) -> None:
    """Deterministic probe: LCG noise (excites every mel bin) + 3 tones + a DC offset
    (exercises remove_dc_offset). Written at exactly 16 kHz so no resampler is involved."""
    total = int(SAMPLE_RATE * seconds)
    state = 20260930
    samples = np.empty(total, dtype=np.float64)
    for i in range(total):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        noise = state / 0x7FFFFFFF - 0.5
        t = i / SAMPLE_RATE
        value = (0.25 * noise
                 + 0.30 * math.sin(2.0 * math.pi * 300.0 * t)
                 + 0.20 * math.sin(2.0 * math.pi * 1200.0 * t)
                 + 0.10 * math.sin(2.0 * math.pi * 3300.0 * t)
                 + 0.03)                                            # DC offset
        samples[i] = value
    clipped = np.clip(samples, -1.0, 1.0)
    ints = np.round(clipped * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(ints.tobytes())
    print(f"probe  : {path}  {total} samples @ {SAMPLE_RATE} Hz ({seconds:.1f} s)")


def read_wav_mono(path: str):
    with wave.open(path, "rb") as w:
        sr, n_ch, width, n = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(n)
    if width != 2:
        raise ValueError(f"expected 16-bit, got {width * 8}-bit")
    if n_ch != 1:
        raise ValueError(f"expected mono, got {n_ch} channels")
    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    return data, sr


# --------------------------------------------------------------------------- csv

def write_csv(path: str, feats: np.ndarray) -> None:
    frames, bins = feats.shape
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"frames,bins\n{frames},{bins}\n")
        for value in feats.reshape(-1):
            f.write(f"{float(value):.9g}\n")
    print(f"csv    : {path}  shape=({frames}, {bins})")


def read_csv(path: str):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    assert lines[0] == "frames,bins", f"unexpected header {lines[0]!r}"
    frames, bins = (int(x) for x in lines[1].split(","))
    values = np.array([float(x) for x in lines[2:2 + frames * bins]], dtype=np.float64)
    return values.reshape(frames, bins)


# --------------------------------------------------------------------------- commands

def cmd_golden(wav_path: str, csv_path: str) -> int:
    wav, sr = read_wav_mono(wav_path)
    print(f"wav    : {wav_path}  {wav.shape[0]} samples @ {sr} Hz")
    feats = kaldi_fbank(wav, sr)
    print(f"numpy  : shape={feats.shape} min={feats.min():.4f} max={feats.max():.4f}")
    write_csv(csv_path, feats)
    return 0


def cmd_compare(golden_path: str, swift_path: str) -> int:
    golden = read_csv(golden_path)
    swift = read_csv(swift_path)
    print(f"golden : {golden.shape}   swift: {swift.shape}")
    if golden.shape != swift.shape:
        print("FAIL: shape mismatch")
        return 1

    diff = np.abs(golden - swift)
    mae = float(diff.mean())
    print(f"RAW  MAE={mae:.3e}  max|d|={diff.max():.3e}  "
          f"at frame {int(diff.max(axis=1).argmax())} bin {int(diff.max(axis=0).argmax())}")

    gold_n = golden - golden.mean(axis=0, keepdims=True)
    swift_n = swift - swift.mean(axis=0, keepdims=True)
    diff_n = np.abs(gold_n - swift_n)
    print(f"MEAN-NORM MAE={float(diff_n.mean()):.3e}  max|d|={diff_n.max():.3e}")

    ok = mae < TOLERANCE
    print(f"\nGATE A: {'PASS' if ok else 'FAIL'}  (RAW MAE {mae:.3e} vs tol {TOLERANCE:.0e})")
    return 0 if ok else 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    command = sys.argv[1]
    if command == "probe" and len(sys.argv) >= 3:
        generate_probe(sys.argv[2])
        return 0
    if command == "golden" and len(sys.argv) >= 4:
        return cmd_golden(sys.argv[2], sys.argv[3])
    if command == "compare" and len(sys.argv) >= 4:
        return cmd_compare(sys.argv[2], sys.argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
