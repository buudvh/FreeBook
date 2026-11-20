#!/usr/bin/env python3
"""ĐO TẠM THỜI (1.3.1034) — so mức to của Google TTS (readaloud) với vtts để chọn mốc âm lượng cho `VttsLoudness`.

Anh Bửu: vtts (1.3.1033, mốc −16 dBFS ước lượng) vẫn "không to bằng google tts". Script này chạy trên CI (macOS), chỉ
dùng thư viện chuẩn, **không bao giờ làm đỏ build** và **không in key**:

1. Google: đọc câu thử + một đoạn truyện ~30 s bằng cả 6 giọng (`GoogleVoice.allVoices`), đúng request của app
   (`GoogleTTSService.makeRequest`). Key lấy từ env `GOOGLE_CLOUD_TTS_API_KEY`; thiếu key ⇒ bỏ qua phần này.
   Audio giải mã bằng `afconvert` (lùi về `ffmpeg` nếu có) ra WAV 16-bit.
2. vtts: các WAV đoạn dài do `check_vtts_assets.sh` đọc sẵn (`label=path`), đo mức gốc + mô phỏng `VttsLoudness` hiện tại.

Đo: LUFS tích hợp (BS.1770, có gate), đỉnh mẫu, RMS lúc có tiếng (khung 20 ms > −45 dBFS — đúng cách `VttsLoudness`
đo), độ chênh đỉnh − RMS. Kết quả in ra log CI và ghi `<out>/loudness.txt` (artifact `vtts-samples`). Audio của Google
**không** lưu vào artifact.

Xoá script này (và lời gọi trong `check_vtts_assets.sh`) khi đã chốt mốc.
"""
import array
import base64
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import wave

GOOGLE_VOICES = ["via", "vib", "vic", "vid", "vie", "vif"]
GOOGLE_URL = "https://readaloud.googleapis.com/v1:generateAudioDocStream"
SENTENCE = "Đã kết nối Bluetooth với AirPods, chương này tên là The Last Train."
PARAGRAPH = (
    "Lâm Phong đứng lặng trước cổng thành, gió đêm thổi tung vạt áo. Hắn nhìn về phía xa, nơi ánh đèn của Thiên Vân "
    "Các vẫn còn le lói. “Ngươi thật sự muốn đi sao?” Tiểu Nguyệt khẽ hỏi, giọng run run. Hắn không trả lời, chỉ "
    "siết chặt chuôi kiếm. Bỗng một tiếng nổ vang trời! “Chạy mau! Bọn chúng tới rồi!” Tiếng hét xé toạc màn "
    "đêm, cả con phố lập tức hỗn loạn. Lâm Phong rút kiếm, ánh thép loé lên như một tia chớp. Ba năm trước, hắn đã thề "
    "sẽ không bao giờ quay lại nơi này. Nhưng giờ đây, vì nàng, hắn sẵn sàng phá bỏ lời thề ấy."
)

# Hằng số của `VttsLoudness` 1.3.1033 — để mô phỏng đúng mức trên máy hiện tại.
CURRENT_TARGET_DB = -16.0
CURRENT_MAX_GAIN_DB = 12.0
PEAK_CEILING_DB = -1.0
SPEECH_FLOOR_DB = -45.0

LINES = []


def out(line=""):
    print(line, flush=True)
    LINES.append(line)


def db(amplitude):
    return 20 * math.log10(max(amplitude, 1e-9))


def load_wav(path):
    """Mẫu float mono (trộn kênh nếu stereo) + tần số."""
    with wave.open(path, "rb") as w:
        rate, channels, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        data = w.readframes(w.getnframes())
    if width != 2:
        raise ValueError(f"WAV {width * 8}-bit")
    pcm = array.array("h")
    pcm.frombytes(data)
    if channels == 1:
        return [s / 32768 for s in pcm], rate
    return [sum(pcm[i:i + channels]) / channels / 32768 for i in range(0, len(pcm), channels)], rate


def biquad(x, b, a):
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    a1, a2 = a
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def k_weight(x, fs):
    """Bộ lọc K của BS.1770 (kệ cao + thông cao RLB), hệ số tính lại theo tần số mẫu."""
    gain_db, f0, q = 3.999843853973347, 1681.974450955533, 0.7071752369554196
    k = math.tan(math.pi * f0 / fs)
    vh = 10 ** (gain_db / 20)
    vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    x = biquad(
        x,
        ((vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0),
        (2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0),
    )
    f0, q = 38.13547087602444, 0.5003270373238773
    k = math.tan(math.pi * f0 / fs)
    a0 = 1 + k / q + k * k
    return biquad(x, (1.0, -2.0, 1.0), (2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0))


def integrated_lufs(x, fs):
    y = k_weight(x, fs)
    block, hop = int(0.4 * fs), int(0.1 * fs)
    powers = [sum(v * v for v in y[s:s + block]) / block for s in range(0, len(y) - block + 1, hop)]
    gated = [p for p in powers if -0.691 + 10 * math.log10(max(p, 1e-12)) > -70]
    if not gated:
        return None
    relative = -0.691 + 10 * math.log10(sum(gated) / len(gated)) - 10
    gated = [p for p in gated if -0.691 + 10 * math.log10(max(p, 1e-12)) > relative]
    return -0.691 + 10 * math.log10(sum(gated) / len(gated))


def speech_rms(x, fs):
    """Đúng cách đo của `VttsLoudness.speechRMS`: khung 20 ms, bỏ khung ≤ −45 dBFS."""
    frame = max(1, int(fs * 0.02))
    floor = 10 ** (SPEECH_FLOOR_DB / 10) * frame
    energy, count = 0.0, 0
    for s in range(0, len(x) - frame + 1, frame):
        e = sum(v * v for v in x[s:s + frame])
        if e > floor:
            energy += e
            count += frame
    return ((energy / count) ** 0.5, count / fs) if count else (None, 0.0)


def describe(label, x, fs):
    peak = max((abs(v) for v in x), default=0.0)
    rms, speech_seconds = speech_rms(x, fs)
    lufs = integrated_lufs(x, fs)
    if rms is None or lufs is None:
        out(f"  {label}: im lặng?")
        return None
    out(
        f"  {label}: {len(x) / fs:5.1f} s @ {fs} Hz | LUFS {lufs:6.1f} | RMS có tiếng {db(rms):6.1f} dBFS "
        f"({speech_seconds:4.1f} s) | đỉnh {db(peak):5.1f} dBFS | đỉnh−RMS {db(peak) - db(rms):4.1f} dB"
    )
    return {"lufs": lufs, "rms_db": db(rms), "peak_db": db(peak)}


def detect_format(data):
    if data[:4] == b"RIFF":
        return "wav"
    if data[:4] == b"OggS":
        return "ogg"
    if data[4:8] == b"ftyp":
        return "m4a"
    if data[:3] == b"ID3" or (len(data) > 1 and data[0] == 0xFF and (data[1] & 0xE0) == 0xE0):
        return "mp3"
    if data[:4] == b"fLaC":
        return "flac"
    return "bin"


def decode_to_wav(data, workdir, name):
    fmt = detect_format(data)
    src = os.path.join(workdir, f"{name}.{fmt}")
    dst = os.path.join(workdir, f"{name}.wav")
    with open(src, "wb") as f:
        f.write(data)
    if fmt == "wav":
        try:
            load_wav(src)
            return src, fmt
        except Exception:
            pass
    commands = []
    if shutil.which("afconvert"):
        commands.append(["afconvert", "-f", "WAVE", "-d", "LEI16", src, dst])
    if shutil.which("ffmpeg"):
        commands.append(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-c:a", "pcm_s16le", dst])
    for command in commands:
        if subprocess.run(command, capture_output=True).returncode == 0 and os.path.exists(dst):
            return dst, fmt
    raise RuntimeError(f"không giải mã được audio dạng {fmt} ({len(data)} byte)")


def google_audio(key, voice, parts):
    """Đúng body của `GoogleTTSService.makeRequest` (tốc độ 1, cao độ 1)."""
    body = {
        "text": {"textParts": parts},
        "advanced_options": {
            "force_language": "vi",
            "audio_generation_options": {"speed_factor": 1.0, "pitch_factor": 1.0},
        },
        "voice_settings": {
            "voice_criteria_and_selections": [
                {"criteria": {"language": "vi"}, "selection": {"default_voice": voice}}
            ]
        },
    }
    request = urllib.request.Request(
        GOOGLE_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.loads(response.read())
    elements = payload if isinstance(payload, list) else [payload]
    audios = []
    for element in elements:
        audio = element.get("audio") if isinstance(element.get("audio"), dict) else None
        encoded = (audio or {}).get("bytes") or element.get("bytes")
        if encoded:
            audios.append(base64.b64decode(encoded.strip()))
    return audios


def probe_google(workdir):
    key = os.environ.get("GOOGLE_CLOUD_TTS_API_KEY", "").strip()
    if not key:
        out("Google: không có GOOGLE_CLOUD_TTS_API_KEY ⇒ bỏ qua")
        return []
    results = []
    for voice in GOOGLE_VOICES:
        try:
            audios = google_audio(key, voice, [SENTENCE, PARAGRAPH])
        except urllib.error.HTTPError as error:
            # Thân lỗi của Google không chứa key (key chỉ nằm ở header request).
            detail = error.read()[:300].decode("utf-8", "replace").replace("\n", " ")
            out(f"  google {voice}: HTTP {error.code} {detail}")
            continue
        except Exception as error:  # noqa: BLE001 — đo tạm, lỗi gì cũng chỉ ghi lại
            out(f"  google {voice}: lỗi {type(error).__name__}")
            continue
        if len(audios) != 2:
            out(f"  google {voice}: {len(audios)} audio cho 2 đoạn")
            continue
        for part, data in zip(("câu", "đoạn"), audios):
            try:
                path, fmt = decode_to_wav(data, workdir, f"google-{voice}-{part}")
                x, fs = load_wav(path)
            except Exception as error:  # noqa: BLE001
                out(f"  google {voice} {part}: {error}")
                continue
            stats = describe(f"google {voice:3} {part:4} [{fmt}]", x, fs)
            if stats and part == "đoạn":
                results.append(stats)
    return results


def current_gain_db(stats):
    """Mức `VttsLoudness` 1.3.1033 tăng cho cả đoạn."""
    gain = min(CURRENT_TARGET_DB - stats["rms_db"], PEAK_CEILING_DB - stats["peak_db"], CURRENT_MAX_GAIN_DB)
    return max(0.0, gain)


def probe_vtts(entries):
    results = []
    for entry in entries:
        label, path = entry.split("=", 1)
        try:
            x, fs = load_wav(path)
        except Exception as error:  # noqa: BLE001
            out(f"  vtts {label}: {error}")
            continue
        stats = describe(f"vtts {label:5} gốc     ", x, fs)
        if not stats:
            continue
        gain = current_gain_db(stats)
        factor = 10 ** (gain / 20)
        after = describe(f"vtts {label:5} 1.3.1033", [v * factor for v in x], fs)
        out(f"    ⇒ 1.3.1033 tăng +{gain:.1f} dB (trần đỉnh {'CHẶN' if gain < CURRENT_TARGET_DB - stats['rms_db'] - 0.05 else 'không chặn'})")
        results.append((label, stats, after))
    return results


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) < 2:
        print("dùng: tts_loudness_probe.py <out_dir> [label=wav ...]")
        return
    out_dir, vtts_entries = sys.argv[1], sys.argv[2:]
    os.makedirs(out_dir, exist_ok=True)
    out("▶ Đo mức to TTS (tạm thời, 1.3.1034)")
    with tempfile.TemporaryDirectory() as workdir:
        google = probe_google(workdir)
    vtts = probe_vtts(vtts_entries)
    if google:
        lufs = sorted(s["lufs"] for s in google)
        rms = sorted(s["rms_db"] for s in google)
        out(
            f"Google đoạn dài ({len(google)} giọng): LUFS {lufs[0]:.1f}…{lufs[-1]:.1f} (trung vị {lufs[len(lufs) // 2]:.1f}), "
            f"RMS có tiếng {rms[0]:.1f}…{rms[-1]:.1f} dBFS"
        )
        median = lufs[len(lufs) // 2]
        for label, raw, after in vtts:
            gap_now = median - after["lufs"] if after else float("nan")
            out(
                f"vtts {label}: LUFS−RMS {raw['lufs'] - raw['rms_db']:+.1f} dB | bản hiện tại nhỏ hơn Google {gap_now:.1f} dB "
                f"| cần tăng từ gốc {median - raw['lufs']:+.1f} dB"
            )
    with open(os.path.join(out_dir, "loudness.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(LINES) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 — đo tạm không được làm đỏ build
        print(f"::warning::đo mức to TTS lỗi: {type(error).__name__}: {error}")
