#!/usr/bin/env python3
"""Xuất gói **Core ML đọc truyện thật** của VieNeu-TTS v3 Nano cho vòng thử P1b (màn thử VieNeu, "Đo tự động").

Dựng trên các bước mổ graph của `vieneu_nano_static_export.py` (P1, giữ nguyên — import dùng lại), khác ở chỗ:

* **Nhiều bucket T** cho đoạn văn thật: VE `64 / 96 / 128 / 160`, codec `64 / 128 / 160`. App chọn bucket nhỏ nhất
  ≥ T **riêng** cho VE và codec (T = 70 ⇒ VE 96, codec 128), đoạn T > 160 hoặc L > 256 lùi về ORT.
* **L = 256** (P1 là 200): đoạn 140 ký tự có thể vượt 200 token (golden đã tới 188).
* Trọng số **một bản**: mọi `ve_main_T*.onnx` trỏ `ve_main.weights`, mọi `codec_T*.onnx` trỏ `codec.weights`
  (external data). Core ML EP của ORT 1.24.2 đọc external data sai đường dẫn (lấy đường dẫn file model làm thư mục)
  ⇒ app nạp file trọng số vào bộ nhớ bằng `AddExternalInitializersFromFilesInMemory` (ORT chép thẳng vào graph).
* **Khoá cache Core ML** (`COREML_CACHE_KEY` trong metadata, chữ + số, < 64 ký tự): mặc định ORT băm **đường dẫn**
  model, thay file cùng tên là dùng nhầm bản biên dịch cũ ⇒ khoá = tên + 12 ký tự hex của sha256(graph + trọng số).
* Tự kiểm **mọi bucket vừa với từng đoạn golden** (đoạn T = 47 chạy cả VE 64 / 96 / 128 / 160 và codec 64 / 128 / 160)
  bằng ORT CPU, nạp lại từ đĩa, so với graph gốc ở cùng ngưỡng sàn fp32 như P1. Lệch là thoát mã 1, không ghi manifest.

Chạy: `python Scripts/vieneu_nano_coreml_export.py --out build/vieneu-nano-coreml`
Cần: `onnx==1.23.2 onnxruntime==1.24.2 numpy` (như P1).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile

import numpy as np
import onnx

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vieneu_nano_static_export as base  # noqa: E402  (cùng thư mục)

FORMAT_VERSION = 2
L_FROZEN = 256
VE_BUCKETS = (64, 96, 128, 160)
CODEC_BUCKETS = (64, 128, 160)
VE_WEIGHTS = "ve_main.weights"
CODEC_WEIGHTS = "codec.weights"

log = base.log


def file_sha256(path: str) -> str:
    return base.sha256(path)


def stamp_cache_key(path: str, prefix: str, weights_sha: str) -> str:
    """Ghi `COREML_CACHE_KEY` = prefix + 12 hex của sha256(graph không metadata + sha trọng số) vào file graph."""
    model = onnx.load(path, load_external_data=False)
    del model.metadata_props[:]
    digest = hashlib.sha256(model.SerializeToString() + weights_sha.encode()).hexdigest()[:12]
    key = f"{prefix}{digest}"
    if not key.isalnum() or len(key) >= 64:
        raise RuntimeError(f"khoá cache không hợp lệ: {key}")
    entry = model.metadata_props.add()
    entry.key, entry.value = "COREML_CACHE_KEY", key
    onnx.save(model, path)
    return key


def build_ve(base_model: onnx.ModelProto, work: str, out: str) -> dict:
    preps, mains = {}, {}
    for bucket in VE_BUCKETS:
        model = onnx.ModelProto()
        model.CopyFrom(base_model)
        base.freeze(model, {"x": [1, base.CHANNELS, bucket], "t": [1], "ctx": [1, L_FROZEN, 256],
                            "ctx_mask": [1, L_FROZEN], "spk": [1, 192], "style": [1, 50, 256],
                            "frame_mask": [1, bucket]}, {"v": [1, base.CHANNELS, bucket]})
        model = base.ort_basic(model, work, f"ve_T{bucket}")
        count = base.rewrite_masked_where(model)
        prep, main = base.split_prep_main(model)
        base.floatify_bool_inputs(prep)
        preps[bucket], mains[bucket] = prep, main
        log(f"  VE T{bucket}: Where viết lại {count}, prep {len(prep.graph.node)} node, main {len(main.graph.node)} node")
    for bucket, prep in preps.items():
        onnx.save(prep, os.path.join(out, f"ve_prep_T{bucket}.onnx"))
    base.save_external([(mains[b], os.path.join(out, f"ve_main_T{b}.onnx")) for b in VE_BUCKETS],
                       os.path.join(out, VE_WEIGHTS))
    weights_sha = file_sha256(os.path.join(out, VE_WEIGHTS))
    return {f"ve_main_T{b}.onnx": stamp_cache_key(os.path.join(out, f"ve_main_T{b}.onnx"), f"vnve{b}x", weights_sha)
            for b in VE_BUCKETS}


def build_codec(model_dir: str, work: str, out: str) -> dict:
    source = onnx.load(os.path.join(model_dir, "codec_decoder.onnx"))
    models = []
    for bucket in CODEC_BUCKETS:
        codec = onnx.ModelProto()
        codec.CopyFrom(source)
        base.freeze(codec, {"x": [1, base.CHANNELS, bucket]}, {})
        codec = base.ort_basic(codec, work, f"codec_T{bucket}")
        pads, norms = base.fuse_left_pads(codec), base.batchnorm_to_mul_add(codec)
        models.append((codec, os.path.join(out, f"codec_T{bucket}.onnx")))
        log(f"  codec T{bucket}: gộp {pads} Pad vào Conv, đổi {norms} BatchNorm")
    base.save_external(models, os.path.join(out, CODEC_WEIGHTS))
    weights_sha = file_sha256(os.path.join(out, CODEC_WEIGHTS))
    return {f"codec_T{b}.onnx": stamp_cache_key(os.path.join(out, f"codec_T{b}.onnx"), f"vncodec{b}x", weights_sha)
            for b in CODEC_BUCKETS}


def self_test(out: str, chunks: list[dict], null_ctx, null_mask, assets: dict) -> tuple[bool, list[dict]]:
    """Mỗi đoạn golden × mọi bucket VE ≥ T (quỹ đạo đủ 8 bước) × mọi bucket codec ≥ T (giải mã latent của VE đó)."""
    ok = True
    rows = []
    codecs = {b: base.open_session(os.path.join(out, f"codec_T{b}.onnx")) for b in CODEC_BUCKETS}
    runners = {b: base.StaticRunner(os.path.join(out, f"ve_prep_T{b}.onnx"), os.path.join(out, f"ve_main_T{b}.onnx"),
                                    None, b) for b in VE_BUCKETS}
    for k, chunk in enumerate(chunks):
        frames = chunk["T"]
        for ve_bucket in (b for b in VE_BUCKETS if b >= frames):
            v0, latent, _ = runners[ve_bucket].trajectory(chunk, null_ctx, null_mask, assets)
            row = {"chunk": k, "T": frames, "ve": ve_bucket, "v0": base.snr_db(chunk["v0"], v0),
                   "latent": base.snr_db(chunk["lat"], latent), "wav": {}}
            ok &= row["v0"] >= base.MIN_SNR_DB["v0"] and row["latent"] >= base.MIN_SNR_DB["latent"]
            for codec_bucket in (b for b in CODEC_BUCKETS if b >= frames):
                x = np.zeros((1, base.CHANNELS, codec_bucket), np.float32)
                x[:, :, :frames] = latent
                wav = codecs[codec_bucket].run(None, {"x": x})[0].reshape(-1)[: frames * base.HOP]
                value = base.snr_db(chunk["wav"], wav)
                row["wav"][f"T{codec_bucket}"] = value
                ok &= value >= base.MIN_SNR_DB["wav"]
            rows.append(row)
            wavs = " · ".join(f"codec {name} {value:.1f}" for name, value in row["wav"].items())
            log(f"  đoạn {k} (T={frames}) VE {ve_bucket}: v0 {row['v0']:.1f} · latent {row['latent']:.1f} · {wavs} dB")
    return ok, rows


def build(out: str, model_dir: str) -> int:
    # Các hàm dùng lại của P1 đọc hằng ở cấp module ⇒ đặt L và bucket lớn nhất cho golden trước khi gọi.
    base.L_FROZEN = L_FROZEN
    base.VE_INLINE_BUCKET = max(VE_BUCKETS)
    os.makedirs(out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="vieneu-p1b-")
    log(f"Tải model {base.REPO}@{base.REVISION[:8]} …")
    base.download(model_dir)
    assets = base.load_assets(model_dir)

    log("Dựng VE tĩnh (4 bucket, L = 256) …")
    ve_model = onnx.load(os.path.join(model_dir, "vector_estimator.onnx"))
    base.expose_frame_mask(ve_model)
    cache_keys = build_ve(ve_model, work, out)
    log("Dựng codec tĩnh (3 bucket) …")
    cache_keys.update(build_codec(model_dir, work, out))

    log("Golden (graph gốc, ORT CPU) …")
    chunks, null_flat = base.reference_chunks(model_dir, assets)
    null_ctx = null_flat[: L_FROZEN * 256].reshape(1, L_FROZEN, 256)
    null_mask = null_flat[L_FROZEN * 256:].reshape(1, L_FROZEN)
    golden = {"grid": base.time_grid(), "spk": assets["spk"], "style": assets["style"],
              "null_spk": assets["null_spk"], "null_style": assets["null_style"], "null_ctx": null_ctx,
              "null_cmask": null_mask}
    for k, chunk in enumerate(chunks):
        for key in ("ctx", "cmask", "x0", "v0", "lat", "wav"):
            golden[f"c{k}_{key}"] = chunk[key].astype(np.float32)
        golden[f"c{k}_T"] = np.array([chunk["T"]], np.float32)
    np.savez(os.path.join(out, "golden.npz"), **golden)

    log("Tự kiểm mọi bucket (nạp lại từ đĩa) …")
    ok, rows = self_test(out, chunks, null_ctx, null_mask, assets)
    if not ok:
        log("❌ Tự kiểm không đạt — không ghi manifest.")
        return 1

    with open(os.path.join(out, "NOTICE.txt"), "w", encoding="utf-8") as handle:
        handle.write(
            "VieNeu-TTS v3 Nano — graph tĩnh nhiều bucket cho thử nghiệm Core ML đọc truyện (Tàng Công Các)\n\n"
            f"Nguồn: https://huggingface.co/{base.REPO} (revision {base.REVISION}), giấy phép Apache-2.0.\n"
            "Trọng số giữ nguyên. Đã sửa graph: mở mask khung thành input `frame_mask`, đóng băng shape (T theo bucket\n"
            f"VE {'/'.join(map(str, VE_BUCKETS))}, codec {'/'.join(map(str, CODEC_BUCKETS))}, L = {L_FROZEN}), gấp hằng"
            " (ONNX Runtime 1.24.2 mức BASIC),\n"
            "đổi Where(mask, -FLT_MAX, ·) thành Add(bias), tách graph chuẩn bị / graph chính; codec: gộp Pad vào Conv,\n"
            "đổi BatchNormalization thành Mul + Add. Thêm metadata COREML_CACHE_KEY.\n"
            "Sinh bởi Scripts/vieneu_nano_coreml_export.py.\n")
    files = sorted(name for name in os.listdir(out) if name != "manifest.json")
    manifest = {
        "format": FORMAT_VERSION, "sourceRepo": base.REPO, "sourceRevision": base.REVISION, "voice": assets["voice"],
        "lengthFrozen": L_FROZEN, "veBuckets": list(VE_BUCKETS), "codecBuckets": list(CODEC_BUCKETS),
        "veWeights": VE_WEIGHTS, "codecWeights": CODEC_WEIGHTS, "cacheKeys": cache_keys,
        "steps": base.STEPS, "sway": base.SWAY, "cfg": base.CFG, "goldenChunks": len(chunks),
        "selfTest": rows,
        "files": [{"name": name, "bytes": os.path.getsize(os.path.join(out, name)),
                   "sha256": file_sha256(os.path.join(out, name))} for name in files],
    }
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=1)
    total = sum(f["bytes"] for f in manifest["files"])
    log(f"✅ Xong: {len(files)} file, {total / 1e6:.1f} MB ở {out}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default="build/vieneu-nano-coreml")
    parser.add_argument("--model-dir", default="build/vieneu-nano-source")
    args = parser.parse_args()
    return build(args.out, args.model_dir)


if __name__ == "__main__":
    sys.exit(main())
