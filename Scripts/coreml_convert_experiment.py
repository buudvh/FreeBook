"""Thí nghiệm: ONNX → `.mlpackage` (CoreML) cho **VieNeu-TTS v3 Nano**.

Chạy trên runner macOS (Apple Silicon ⇒ có ANE). Trả lời 3 câu, mỗi câu ghi ra `reports/`:

  G1 `analysis.json` — `onnx2coreml` convert được graph nào, op nào bị thiếu.
  G2 `.mlpackage`    — có sinh được file không (shape cố định: 2 bucket cho `vector_estimator`).
  G3 `parity.json`   — Core ML (fp16) vs ONNX Runtime (fp32) **trên cùng một máy**: SNR, max|Δ|,
                       và `ms/lượt` của từng bên ⇒ biết Core ML có nhanh hơn CPU hay không.

**Không** sửa gì trong app. Mọi giai đoạn bọc `try/except` để một lỗi không làm mất kết quả
của các giai đoạn khác — vì bản thân "lỗi ở đâu, vì sao" cũng là kết quả cần thu.

Chạy: `python Scripts/coreml_convert_experiment.py [--out reports]`
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
import time
import traceback

REPO_ID = "pnnbao-ump/VieNeu-TTS-v3-Nano"
# Ghim đúng revision app dùng (`VieNeuModelClient.modelRevision`).
REVISION = "aba295eb96a6fa6003ebe417cc1f2802a7adc1dc"
MODEL_FILES = [
    "text_encoder.onnx",
    "duration_predictor.onnx",
    "vector_estimator.onnx",
    "codec_decoder.onnx",
    "config.json",
    "constants.npz",
]
# `voices_v3_nano.json` nằm ở **GitHub** (không phải HuggingFace) — tải qua raw URL ghim revision,
# đúng như app làm trong `VieNeuModelClient`.
VOICES_URL = ("https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/"
              "2e982ff857bbe23fffa0c314e0f60da2497e2f4b/src/vieneu/assets/voices_v3_nano.json")
VOICES_FILE = "voices_v3_nano.json"

# Phoneme THẬT chép từ `app_logs (60).txt` — để input của phép so số là dữ liệu thật, không phải nhiễu.
PHONEMES = (
    "tʃˈi4 tˈəɪɜ nˈaː ɹˈu t̪ˈo nˈəŋ t̪ˈaj tʃˈaːɜj lˈen, "
    "ŋˈɔɜn t̪ˈaj ɲˈɛ6 ɲˈaː2ŋ bˈɔɜp lˈiɛ2n bˈaɜt̪ lˈəɪɜ t̪ˈaː2 ŋwˈiɛ6t̪ tʃˈɔŋ ɗˈɔɜ "
    "mˈo6t̪ tˈe-ɲ ŋwˈiɛ6t̪ ɲˈə6n,"
)

# Hai bucket shape: điển hình (L=160, T=96) và trần (L=200, T=234 = 15 s × 15,625 fps).
BUCKETS = {
    "typical": {"L": 160, "T": 96},
    "max": {"L": 200, "T": 234},
}


def log(stage: str, message: str) -> None:
    print(f"[{stage}] {message}", flush=True)


def machine_info() -> dict:
    info = {"platform": platform.platform(), "machine": platform.machine(), "python": sys.version.split()[0]}
    for key in ("machdep.cpu.brand_string", "hw.model", "hw.ncpu", "hw.perflevel0.physicalcpu", "hw.perflevel1.physicalcpu"):
        try:
            info[key] = subprocess.run(["sysctl", "-n", key], capture_output=True, text=True).stdout.strip()
        except Exception:
            pass
    return info


# ─────────────────────────── G0: tải model ───────────────────────────
def stage_download(workdir: str) -> str:
    from huggingface_hub import hf_hub_download

    model_dir = os.path.join(workdir, "model")
    os.makedirs(model_dir, exist_ok=True)
    for name in MODEL_FILES:
        hf_hub_download(repo_id=REPO_ID, filename=name, revision=REVISION, local_dir=model_dir)
        log("G0", f"tải {name} ({os.path.getsize(os.path.join(model_dir, name)) / 1e6:.1f} MB)")
    voices = os.path.join(workdir, VOICES_FILE)
    if not os.path.exists(voices):
        import urllib.request

        urllib.request.urlretrieve(VOICES_URL, voices)  # noqa: S310 — URL ghim revision, hằng số
    log("G0", f"tải {VOICES_FILE} ({os.path.getsize(voices) / 1e6:.1f} MB)")
    log("G0", "xong")
    return model_dir


# ─────────────────────────── G1: phân tích độ phủ ───────────────────────────
def stage_analyze(model_dir: str, reports: str) -> dict:
    import onnx2coreml as o2c

    result: dict = {}
    for name in MODEL_FILES:
        if not name.endswith(".onnx"):
            continue
        path = os.path.join(model_dir, name)
        try:
            report = o2c.analyze(path)
            entry = {"ok": True}
            for attr in ("convertible", "unsupported", "ops", "histogram", "supported", "missing"):
                if hasattr(report, attr):
                    value = getattr(report, attr)
                    entry[attr] = value if isinstance(value, (list, dict, str, int, float, bool)) else repr(value)
            result[name] = entry
            log("G1", f"{name}: convertible={entry.get('convertible')} unsupported={entry.get('unsupported')}")
        except Exception as error:  # noqa: BLE001 — lỗi ở đây là KẾT QUẢ cần ghi
            result[name] = {"ok": False, "error": f"{type(error).__name__}: {error}"}
            log("G1", f"{name}: LỖI {type(error).__name__}: {error}")
    with open(os.path.join(reports, "analysis.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    return result


# ─────────────────────────── G2: làm shape tĩnh + convert ───────────────────────────
def freeze_shapes(src: str, dst: str, shapes: dict) -> None:
    """Ghi `dim_value` cố định cho các input trong `shapes` rồi suy lại shape.

    `onnx2coreml` chỉ nhận **shape tĩnh**, nên `L` (phoneme) và `T` (frame) phải chốt trước khi convert.
    Xoá `value_info` cũ để `infer_shapes` tính lại theo chiều đã chốt.
    """
    import onnx

    model = onnx.load(src)
    for item in model.graph.input:
        if item.name in shapes:
            dims = item.type.tensor_type.shape.dim
            values = shapes[item.name]
            if len(dims) != len(values):
                raise ValueError(f"{item.name}: rank {len(dims)} != {len(values)}")
            for dim, value in zip(dims, values):
                dim.ClearField("dim_param")
                dim.dim_value = value
    del model.graph.value_info[:]
    model = onnx.shape_inference.infer_shapes(model)
    onnx.save(model, dst)


def optimize_with_ort(src: str, dst: str) -> None:
    """Cho **ORT tự tối ưu** rồi lưu graph đã tối ưu ra `dst`.

    Đây là cách rẻ nhất để gấp hằng số: sau khi chốt shape tĩnh, các chuỗi `Shape`→`Gather`→`Range`
    trở thành hằng, và bộ `ConstantFolding` của ORT sẽ thay chúng bằng initializer. `Range` chính là op
    mà `onnx2coreml` báo thiếu lowering (6 node ở `vector_estimator`, 1 ở `text_encoder`).
    """
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.optimized_model_filepath = dst
    ort.InferenceSession(src, options, providers=["CPUExecutionProvider"])


def fold_range(src: str, dst: str) -> int:
    """Gấp mọi `Range` có input hằng thành initializer (lưới an toàn nếu ORT không gấp).

    `Range(start, limit, delta)` với input hằng thì kết quả là hằng ⇒ thay node bằng một initializer
    cùng tên output. Trả về số node đã gấp.
    """
    import numpy as np
    import onnx
    from onnx import numpy_helper

    model = onnx.load(src)
    values: dict = {}
    for init in model.graph.initializer:
        values[init.name] = numpy_helper.to_array(init)
    for node in model.graph.node:
        if node.op_type == "Constant":
            for attr in node.attribute:
                if attr.name == "value":
                    values[node.output[0]] = numpy_helper.to_array(attr.t)
    kept = []
    folded = 0
    for node in model.graph.node:
        if node.op_type == "Range" and all(item in values for item in node.input):
            start, limit, delta = (values[item] for item in node.input)
            array = np.arange(start.item(), limit.item(), delta.item())
            dtype = values[node.input[0]].dtype
            model.graph.initializer.append(
                numpy_helper.from_array(array.astype(dtype), name=node.output[0])
            )
            folded += 1
            continue
        kept.append(node)
    if folded:
        del model.graph.node[:]
        model.graph.node.extend(kept)
        onnx.save(model, dst)
    return folded


def stage_convert(model_dir: str, workdir: str) -> dict:
    import onnx2coreml as o2c

    result: dict = {}
    plans = [
        ("vector_estimator.onnx", "typical"),
        ("vector_estimator.onnx", "max"),
        ("codec_decoder.onnx", "typical"),
    ]
    for name, bucket in plans:
        key = f"{name.replace('.onnx', '')}-{bucket}"
        entry: dict = {"bucket": BUCKETS[bucket]}
        try:
            cfg = json.load(open(os.path.join(model_dir, "config.json"), encoding="utf-8"))
            latent_channels = cfg["latent_dim"] * cfg["group"]
            length, frames = BUCKETS[bucket]["L"], BUCKETS[bucket]["T"]
            if name.startswith("vector_estimator"):
                shapes = {
                    "x": [1, latent_channels, frames],
                    "t": [1],
                    "ctx": [1, length, cfg["style_dim"]],
                    "ctx_mask": [1, length],
                    "spk": [1, 192],
                    "style": [1, cfg["n_style"], cfg["style_dim"]],
                }
            else:
                shapes = {"x": [1, latent_channels, frames]}
            frozen = os.path.join(workdir, f"{key}.onnx")
            freeze_shapes(os.path.join(model_dir, name), frozen, shapes)
            log("G2", f"{key}: đã chốt shape {shapes}")

            # Chốt shape trước ⇒ các chuỗi `Shape`→`Gather`→`Range` thành hằng ⇒ gấp được.
            optimized = os.path.join(workdir, f"{key}.opt.onnx")
            optimize_with_ort(frozen, optimized)
            if os.path.exists(optimized):
                folded = fold_range(optimized, optimized)
                log("G2", f"{key}: ORT tối ưu xong, gấp thêm {folded} node Range")
                frozen = optimized

            started = time.time()
            mlmodel = o2c.convert(frozen, format="mlpackage", minimum_deployment_target="iOS17")
            package = os.path.join(workdir, f"{key}.mlpackage")
            mlmodel.save(package)
            entry["ok"] = True
            entry["package"] = package
            entry["seconds"] = round(time.time() - started, 1)
            entry["bytes"] = sum(
                os.path.getsize(os.path.join(root, file))
                for root, _, files in os.walk(package)
                for file in files
            )
            log("G2", f"{key}: OK — {entry['bytes'] / 1e6:.1f} MB, {entry['seconds']}s")
        except Exception as error:  # noqa: BLE001
            entry["ok"] = False
            entry["error"] = f"{type(error).__name__}: {error}"
            entry["traceback"] = traceback.format_exc()[-1500:]
            log("G2", f"{key}: LỖI {type(error).__name__}: {error}")
        result[key] = entry
    return result


# ─────────────────────────── G3: so số + đo tốc độ ───────────────────────────
def build_inputs(model_dir: str, workdir: str, bucket: str):
    """Input **thật**: phoneme thật từ log + preset giọng thật; `ctx` lấy từ `text_encoder`."""
    import numpy as np
    import onnxruntime as ort

    cfg = json.load(open(os.path.join(model_dir, "config.json"), encoding="utf-8"))
    vocab = {key: int(value) for key, value in cfg["vocab"].items()}
    preset = json.load(open(os.path.join(workdir, "voices_v3_nano.json"), encoding="utf-8"))
    voice = preset["presets"][preset["default_voice"]]
    speaker = np.asarray(voice["speaker_emb"], dtype=np.float32).reshape(1, -1)
    style = np.asarray(voice["style"], dtype=np.float32).reshape(1, cfg["n_style"], cfg["style_dim"])

    ids = [cfg["bos_id"]] + [vocab[c] for c in PHONEMES if c in vocab] + [cfg["eos_id"]]
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    encoder = ort.InferenceSession(os.path.join(model_dir, "text_encoder.onnx"), options,
                                   providers=["CPUExecutionProvider"])
    ctx = encoder.run(None, {"ids": np.asarray(ids, dtype=np.int64).reshape(1, -1), "style": style})[0]

    length, frames = BUCKETS[bucket]["L"], BUCKETS[bucket]["T"]
    latent_channels = cfg["latent_dim"] * cfg["group"]
    ctx_padded = np.zeros((1, length, ctx.shape[2]), dtype=np.float32)
    keep = min(length, ctx.shape[1])
    ctx_padded[:, :keep, :] = ctx[:, :keep, :]
    mask = np.zeros((1, length), dtype=np.bool_)
    mask[:, :keep] = True
    latent = np.random.default_rng(20261002).standard_normal((1, latent_channels, frames)).astype(np.float32)
    return {
        "x": latent,
        "t": np.asarray([0.5], dtype=np.float32),
        "ctx": ctx_padded,
        "ctx_mask": mask,
        "spk": speaker,
        "style": style,
    }


def stage_parity(model_dir: str, workdir: str, converted: dict, reports: str) -> dict:
    import numpy as np
    import onnxruntime as ort

    key = "vector_estimator-typical"
    if not converted.get(key, {}).get("ok"):
        log("G3", f"bỏ qua: {key} chưa convert được")
        return {"skipped": f"{key} not converted"}

    result: dict = {}
    try:
        feeds = build_inputs(model_dir, workdir, "typical")
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        session = ort.InferenceSession(os.path.join(model_dir, "vector_estimator.onnx"), options,
                                       providers=["CPUExecutionProvider"])

        def run_ort():
            return session.run(None, feeds)[0]

        run_ort()  # warm-up
        timings = []
        for _ in range(5):
            started = time.perf_counter()
            out_ort = run_ort()
            timings.append((time.perf_counter() - started) * 1000)
        ort_ms = float(np.median(timings))
        log("G3", f"ORT fp32: {ort_ms:.1f} ms/lượt")

        import coremltools as ct

        package = converted[key]["package"]
        units = {"all": ct.ComputeUnit.ALL, "cpuAndNeuralEngine": ct.ComputeUnit.CPU_AND_NE,
                 "cpuOnly": ct.ComputeUnit.CPU_ONLY}
        for unit_name, unit in units.items():
            try:
                model = ct.models.MLModel(package, compute_units=unit)
                inputs = {name: np.asarray(value) for name, value in feeds.items()}
                model.predict(inputs)  # warm-up
                timings = []
                for _ in range(5):
                    started = time.perf_counter()
                    out_cml = list(model.predict(inputs).values())[0]
                    timings.append((time.perf_counter() - started) * 1000)
                cml_ms = float(np.median(timings))
                diff = np.abs(np.asarray(out_ort, dtype=np.float32) - np.asarray(out_cml, dtype=np.float32))
                rms = float(np.sqrt(np.mean(np.asarray(out_ort, dtype=np.float32) ** 2)))
                snr = 20 * float(np.log10(rms / max(float(np.std(diff)), 1e-12)))
                result[unit_name] = {
                    "coreml_ms": round(cml_ms, 1),
                    "ort_ms": round(ort_ms, 1),
                    "speed_ratio": round(ort_ms / cml_ms, 2),
                    "snr_db": round(snr, 1),
                    "max_abs_diff": float(diff.max()),
                }
                log("G3", f"Core ML[{unit_name}]: {cml_ms:.1f} ms/lượt · tỉ lệ ORT/CoreML={ort_ms / cml_ms:.2f}× · SNR={snr:.1f} dB")
            except Exception as error:  # noqa: BLE001
                result[unit_name] = {"error": f"{type(error).__name__}: {error}"}
                log("G3", f"Core ML[{unit_name}]: LỖI {type(error).__name__}: {error}")
    except Exception as error:  # noqa: BLE001
        result["error"] = f"{type(error).__name__}: {error}"
        result["traceback"] = traceback.format_exc()[-1500:]
        log("G3", f"LỖI {type(error).__name__}: {error}")

    with open(os.path.join(reports, "parity.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="reports")
    parser.add_argument("--workdir", default=".coreml-experiment")
    args = parser.parse_args()

    reports = os.path.abspath(args.out)
    workdir = os.path.abspath(args.workdir)
    os.makedirs(reports, exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    summary: dict = {"machine": machine_info()}
    log("G0", f"máy: {summary['machine']}")

    try:
        model_dir = stage_download(workdir)
    except Exception as error:  # noqa: BLE001
        summary["download_error"] = f"{type(error).__name__}: {error}"
        log("G0", f"LỖI tải model: {error}")
        with open(os.path.join(reports, "summary.json"), "w", encoding="utf-8") as handle:
            json.dump(summary, handle, ensure_ascii=False, indent=2)
        return 1

    try:
        summary["analysis"] = stage_analyze(model_dir, reports)
    except Exception as error:  # noqa: BLE001
        summary["analysis_error"] = f"{type(error).__name__}: {error}"
        log("G1", f"LỖI: {error}")

    try:
        converted = stage_convert(model_dir, workdir)
        summary["converted"] = {key: {k: v for k, v in value.items() if k != "traceback"}
                                for key, value in converted.items()}
    except Exception as error:  # noqa: BLE001
        converted = {}
        summary["convert_error"] = f"{type(error).__name__}: {error}"
        log("G2", f"LỖI: {error}")

    try:
        summary["parity"] = stage_parity(model_dir, workdir, converted, reports)
    except Exception as error:  # noqa: BLE001
        summary["parity_error"] = f"{type(error).__name__}: {error}"
        log("G3", f"LỖI: {error}")

    with open(os.path.join(reports, "summary.json"), "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
    log("XONG", f"báo cáo ở {reports}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
