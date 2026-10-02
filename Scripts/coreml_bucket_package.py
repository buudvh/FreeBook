"""Phase 2 — sinh gói Core ML **bucket tĩnh** (hướng A) cho VieNeu-TTS v3 Nano.

Đây là bước chuyển từ "đã đo được" sang "có gói để phát hành". So với lượt thí nghiệm:

* Lượt cũ sinh gói **để đo**, rồi vứt đi. Lượt này sinh gói **để phát hành**, kèm
  `manifest.json` (sha256 từng file) và `golden/` (đầu vào cố định + đầu ra tham chiếu cho self-test).
* Lưới đã chốt ở Phase 1: **`T ∈ {64, 96, 234}`** với **`L = 200`**.
  * `T = 234` là **trần cấu trúc** — `VieNeuConfig.maxChunkSeconds = 15,0` chặn `T ≤ round(15 × 15,625)`
    bằng thiết kế, nên có bucket này thì **không thể tràn**, không cần guard chia đoạn.
  * `T = 128` **không sinh** — Phase 1 đo được: thêm 127,8 MB mà tỉ lệ **không đổi**.
* `text_encoder` + `duration_predictor` mỗi cái **1 gói** (chiều động duy nhất của chúng là `L`, đã cố định).

Số gói: 2 + 3 × 2 = **8**.

Chạy: `python Scripts/coreml_bucket_package.py --out coreml-bucket --workdir coreml-bucket-work`
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
import traceback

# Dùng lại hạ tầng đã kiểm chứng của lượt baseline — cố ý không sao chép.
from coreml_convert_experiment import (
    REVISION,
    fold_range,
    freeze_shapes,
    log,
    machine_info,
    optimize_with_ort,
    stage_download,
)

# Lưới đã chốt ở Phase 1 (xem `Docs/Plans/2026-10-02-plan-vieneu-coreml-bucket-tinh.md` §1.4).
BUCKET_FRAMES = (64, 96, 234)
# `L` thật đo được từ log: p50 91 · p90 129 · p99 143 · max 150 ⇒ 200 phủ hết với biên rộng.
LENGTH_FROZEN = 200

# Hai graph này chỉ phụ thuộc `L` (đã cố định) ⇒ mỗi cái 1 gói.
LENGTH_ONLY_GRAPHS = ("text_encoder.onnx", "duration_predictor.onnx")
# Hai graph này phụ thuộc `T` ⇒ 1 gói mỗi mức.
FRAME_GRAPHS = ("vector_estimator.onnx", "codec_decoder.onnx")


def shapes_for(graph: str, config: dict, frames: int) -> dict:
    """Shape đóng băng cho `graph` ở mức `frames` (bỏ qua nếu graph không dùng chiều đó)."""
    style_dim, n_style = config["style_dim"], config["n_style"]
    channels = config["latent_dim"] * config["group"]
    table = {
        "text_encoder.onnx": {"ids": [1, LENGTH_FROZEN], "style": [1, n_style, style_dim]},
        "duration_predictor.onnx": {"ctx": [1, LENGTH_FROZEN, style_dim],
                                    "ctx_mask": [1, LENGTH_FROZEN],
                                    "spk": [1, 192]},
        "vector_estimator.onnx": {"x": [1, channels, frames],
                                  "t": [1],
                                  "ctx": [1, LENGTH_FROZEN, style_dim],
                                  "ctx_mask": [1, LENGTH_FROZEN],
                                  "spk": [1, 192],
                                  "style": [1, n_style, style_dim]},
        "codec_decoder.onnx": {"x": [1, channels, frames]},
    }
    return table[graph]


def convert_graph(source: str, pkgdir: str, name: str, config: dict, frames: int) -> dict:
    """Đóng băng shape rồi convert bằng `onnx2coreml` — đúng đường đã chạy ở lượt baseline.

    ⚠️ `pkgdir` **phải** nằm trong thư mục phát hành. Lượt đầu ghi gói vào `workdir` trong khi publish chỉ
    upload `outdir` ⇒ repo HF nhận được **mỗi** `manifest.json` + `golden/` (3,7 MB) và **không có gói nào**
    — mà CI vẫn **xanh**. Đúng loại lỗi "xanh mà không làm gì": publish thành công, nội dung trống rỗng.
    """
    import onnx2coreml as o2c

    shapes = shapes_for(os.path.basename(source), config, frames)
    frozen = os.path.join(pkgdir, f"{name}.frozen.onnx")
    freeze_shapes(source, frozen, shapes)

    # Thử **nhiều ứng viên** như lượt baseline: một bản tối ưu hỏng không được làm mất bản gốc.
    candidates = []
    optimized = os.path.join(pkgdir, f"{name}.opt.onnx")
    if optimize_with_ort(frozen, optimized):
        fold_range(optimized, optimized)
        candidates.append(("basic-folded", optimized))
    candidates.append(("frozen", frozen))

    package = os.path.join(pkgdir, f"{name}.mlpackage")
    errors = []
    for label, candidate in candidates:
        try:
            started = time.time()
            o2c.convert(candidate, format="mlpackage", minimum_deployment_target="iOS17").save(package)
            return {"ok": True, "package": package, "converted_with": label,
                    "seconds": round(time.time() - started, 1),
                    "bytes": _dir_bytes(package), "shapes": shapes,
                    "candidates": errors}
        except Exception as error:  # noqa: BLE001 — thử ứng viên kế
            errors.append(f"{label}: {type(error).__name__}: {str(error).splitlines()[0][:200]}")
    return {"ok": False, "error": "; ".join(errors)}


def _dir_bytes(path: str) -> int:
    return sum(os.path.getsize(os.path.join(root, name))
               for root, _, files in os.walk(path) for name in files)


def _ort_session(model_dir: str, graph: str):
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.log_severity_level = 4
    return ort.InferenceSession(os.path.join(model_dir, graph), options,
                                providers=["CPUExecutionProvider"])


def build_golden(model_dir: str, outdir: str, config: dict, frames: int) -> dict:
    """Sinh `golden/T{frames}.npz`: đầu vào cố định + đầu ra tham chiếu (ORT fp32) ở đúng shape bucket.

    Vì sao là npz chứ không phải WAV: để có WAV phải dựng lại **cả** vòng Euler và bộ phonemizer trong
    Python, mà hai thứ đó **không hề đổi** ở lượt này. Cho một tập đầu vào cố định chạy thẳng qua 4 graph
    thì vẫn chạm đủ 4 graph đã chuyển, tất định, và bắt đúng 3 kiểu hỏng đã gặp: **im lặng · NaN · nhiễu**.

    Không kiểm được: bộ phonemizer (`sea_g2p.bin`, không đổi) và chất lượng tiếng Việt — phải nghe trên máy.
    """
    import numpy as np

    style_dim, n_style = config["style_dim"], config["n_style"]
    channels = config["latent_dim"] * config["group"]
    rng = np.random.default_rng(20261002)

    ids = rng.integers(0, 81, size=(1, LENGTH_FROZEN)).astype(np.int64)
    style = rng.standard_normal((1, n_style, style_dim)).astype(np.float32)
    spk = rng.standard_normal((1, 192)).astype(np.float32)
    latent = rng.standard_normal((1, channels, frames)).astype(np.float32)
    time_step = np.asarray([0.5], dtype=np.float32)
    mask = np.ones((1, LENGTH_FROZEN), dtype=np.bool_)

    # Tham chiếu lấy từ graph **gốc** (shape động) — cùng trọng số với gói đã convert, nên so được.
    ctx = _ort_session(model_dir, "text_encoder.onnx").run(None, {"ids": ids, "style": style})[0]
    log_s = _ort_session(model_dir, "duration_predictor.onnx").run(
        None, {"ctx": ctx, "ctx_mask": mask, "spk": spk})[0]
    velocity = _ort_session(model_dir, "vector_estimator.onnx").run(
        None, {"x": latent, "t": time_step, "ctx": ctx, "ctx_mask": mask,
               "spk": spk, "style": style})[0]
    pcm = _ort_session(model_dir, "codec_decoder.onnx").run(None, {"x": latent})[0]

    golden_dir = os.path.join(outdir, "golden")
    os.makedirs(golden_dir, exist_ok=True)
    npz_path = os.path.join(golden_dir, f"T{frames}.npz")
    np.savez(npz_path,
             ids=ids, style=style, spk=spk, latent=latent, time=time_step, ctx_mask=mask,
             ctx=np.asarray(ctx, dtype=np.float32), log_s=np.asarray(log_s, dtype=np.float32),
             velocity=np.asarray(velocity, dtype=np.float32), pcm=np.asarray(pcm, dtype=np.float32))

    meta = {
        "bucket_frames": frames,
        "length": LENGTH_FROZEN,
        "latent_channels": channels,
        "sample_rate": config["sample_rate"],
        "bytes": os.path.getsize(npz_path),
        "npz": f"golden/T{frames}.npz",
        "reference": "onnxruntime fp32 trên graph gốc (shape động)",
        "revision": REVISION,
    }
    with open(os.path.join(golden_dir, f"T{frames}.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, ensure_ascii=False, indent=2)
    log("GOLDEN", f"T{frames}: {meta['bytes'] / 1e3:.0f} KB")
    return meta


def manifest_files(outdir: str) -> list:
    """Đi `outdir` và trả `{path, bytes, sha256}` từng file. Dùng cho `manifest.json` **và** để kiểm gói
    thật sự nằm trong thư mục phát hành (điều mà lượt đầu đã không làm)."""
    entries = []
    for root, _, files in os.walk(outdir):
        for name in sorted(files):
            full = os.path.join(root, name)
            relative = os.path.relpath(full, outdir).replace(os.sep, "/")
            digest = hashlib.sha256()
            with open(full, "rb") as handle:
                for chunk in iter(lambda: handle.read(1 << 20), b""):
                    digest.update(chunk)
            entries.append({"path": relative, "bytes": os.path.getsize(full),
                            "sha256": digest.hexdigest()})
    return entries


def write_manifest(outdir: str, config: dict, packages: dict, goldens: list) -> dict:
    """`manifest.json` — sha256 + size từng file. App kiểm size lúc tải (hiện tại chỉ kiểm `size > 0`)."""
    entries = manifest_files(outdir)
    manifest = {
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "modelRevision": REVISION,
        "length": LENGTH_FROZEN,
        "buckets": list(BUCKET_FRAMES),
        "packages": packages,
        "golden": goldens,
        "files": entries,
        "totalBytes": sum(item["bytes"] for item in entries),
    }
    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
    log("MANIFEST", f"{len(entries)} file · {manifest['totalBytes'] / 1e6:.1f} MB")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="coreml-bucket")
    parser.add_argument("--workdir", default="coreml-bucket-work")
    args = parser.parse_args()

    outdir = os.path.abspath(args.out)
    workdir = os.path.abspath(args.workdir)
    os.makedirs(outdir, exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    summary: dict = {"machine": machine_info()}
    try:
        model_dir = stage_download(workdir)
    except Exception as error:  # noqa: BLE001
        summary["download_error"] = f"{type(error).__name__}: {error}"
        log("G0", f"LỖI tải model: {error}")
        _dump(outdir, summary)
        return 1

    config = json.load(open(os.path.join(model_dir, "config.json"), encoding="utf-8"))

    # Gói phải nằm trong `outdir` thì `hf upload` mới mang theo được (xem `convert_graph`).
    pkgdir = os.path.join(outdir, "mlpackage")
    os.makedirs(pkgdir, exist_ok=True)

    # ── 1. Sinh 8 gói ──────────────────────────────────────────────────────────
    packages: dict = {}
    for graph in LENGTH_ONLY_GRAPHS:
        name = graph.replace(".onnx", "")
        try:
            result = convert_graph(os.path.join(model_dir, graph), pkgdir, name, config, 0)
        except Exception as error:  # noqa: BLE001
            result = {"ok": False, "error": f"{type(error).__name__}: {error}",
                      "traceback": traceback.format_exc()[-1000:]}
        packages[name] = result
        log("PKG", f"{name}: {'OK ' + str(result.get('bytes', 0) / 1e6) + ' MB' if result.get('ok') else 'LỖI ' + str(result.get('error'))[:110]}")

    for frames in BUCKET_FRAMES:
        for graph in FRAME_GRAPHS:
            name = f"{graph.replace('.onnx', '')}-T{frames}"
            try:
                result = convert_graph(os.path.join(model_dir, graph), pkgdir, name, config, frames)
            except Exception as error:  # noqa: BLE001
                result = {"ok": False, "error": f"{type(error).__name__}: {error}",
                          "traceback": traceback.format_exc()[-1000:]}
            packages[name] = result
            log("PKG", f"{name}: {'OK ' + str(result.get('bytes', 0) / 1e6) + ' MB' if result.get('ok') else 'LỖI ' + str(result.get('error'))[:110]}")

    # ── 2. Golden self-test theo từng mức ──────────────────────────────────────
    goldens: list = []
    for frames in BUCKET_FRAMES:
        try:
            goldens.append(build_golden(model_dir, outdir, config, frames))
        except Exception as error:  # noqa: BLE001
            goldens.append({"bucket_frames": frames, "error": f"{type(error).__name__}: {error}"})
            log("GOLDEN", f"T{frames}: LỖI {type(error).__name__}: {error}")

    # ── 3. manifest.json ───────────────────────────────────────────────────────
    try:
        summary["manifest"] = write_manifest(outdir, config, packages, goldens)
    except Exception as error:  # noqa: BLE001
        summary["manifest_error"] = f"{type(error).__name__}: {error}"
        log("MANIFEST", f"LỖI: {error}")

    expected = len(LENGTH_ONLY_GRAPHS) + len(FRAME_GRAPHS) * len(BUCKET_FRAMES)
    ok = sum(1 for item in packages.values() if item.get("ok"))
    summary["packages_ok"] = f"{ok}/{expected}"
    # Đếm theo số file **thật sự có mặt** trong `outdir`, không chỉ theo kết quả convert — để một gói sinh
    # ra ở chỗ sai (không nằm trong `outdir`) thì vẫn bị bắt, chứ không "PASS" với nội dung trống rỗng.
    published = [item for item in manifest_files(outdir)
                 if item["path"].endswith(".mlmodel") or item["path"].endswith("weight.bin")]
    summary["package_files_in_outdir"] = len(published)
    summary["verdict"] = "PASS" if ok == expected and len(published) > 0 else "FAIL"
    log("XONG", f"{summary['packages_ok']} gói · verdict {summary['verdict']} · ở {outdir}")
    _dump(outdir, summary)
    return 0 if summary["verdict"] == "PASS" else 1


def _dump(outdir: str, summary: dict) -> None:
    with open(os.path.join(outdir, "summary.json"), "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    raise SystemExit(main())
