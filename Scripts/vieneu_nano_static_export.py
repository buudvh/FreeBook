#!/usr/bin/env python3
"""Xuất gói graph **tĩnh** của VieNeu-TTS v3 Nano cho phép thử Core ML / ANE / XNNPACK trên máy (P1).

Nguồn: `pnnbao-ump/VieNeu-TTS-v3-Nano` rev `aba295eb` (Apache-2.0). Không đổi trọng số — chỉ mổ graph:

* `vector_estimator` (VE):
  1. node `/ConstantOfShape` (mask khung bản export cứng thành toàn số 1) ⇒ input `frame_mask` ⇒ chạy ở T đệm mà
     **trùng** kết quả T thật (mẫu số chuẩn hoá vị trí `i/T` lấy từ tổng mask, mask nhân vào activation);
  2. đóng băng T (bucket) và L = 200, gấp hằng bằng ORT mức BASIC;
  3. `Where(mask, -FLT_MAX, logits)` ⇒ `Add(logits, bias)` với bias ∈ {-1e4, 0} (an toàn fp16);
  4. tách **prep** (mọi tensor chỉ phụ thuộc `frame_mask` / `ctx_mask` / `t`: vị trí, RoPE, nhúng t, bias mask —
     chạy CPU) và **main** (0 op ngoài danh sách Core ML EP, 0 tensor bool / int). Hai mask của prep nhận float32 rồi
     tự `Cast` sang bool, để phía app chỉ cần tensor float.
* `codec_decoder`: nhân quả hoàn toàn (mọi Pad chỉ đệm trái, 256 mẫu / khung) ⇒ đệm cuối rồi cắt = trùng bit. Đóng
  băng T, gộp `Pad` hằng 0 vào `Conv.pads`, `BatchNormalization` ⇒ `Mul` + `Add`.

Gói P1 (đủ cho nút "So EP cho Nano"):
* `ve_prep_T128.onnx` + `ve_main_T128.onnx` (trọng số nhúng) + `codec_T128.onnx` (trọng số nhúng) — quỹ đạo 5 đoạn;
* `ve_prep_T234/T256.onnx` + `ve_main_T234/T256.onnx` dùng chung `ve_main.weights` (external data) — đối chứng
  giả thuyết "T234 hỏng vì 234 không chia hết 32" (H1) và kiểm Core ML EP có nhận external data không;
* `golden.npz` (float32, không nén): ctx đã đệm, mask, x0, spk/style, lưới t, và tham chiếu (v bước 0, latent cuối,
  sóng âm) của 5 đoạn — app không phải dựng lại phonemizer / text_encoder / duration;
* `manifest.json` (sha256 từng file + số tự kiểm), `NOTICE.txt` (nguồn gốc Apache-2.0).

Tự kiểm (bắt buộc, lệch là thoát mã 1 và không ghi manifest): nạp lại **từ đĩa** bằng ORT CPU, quỹ đạo 8 bước + CFG 3
của 5 đoạn so với graph gốc — v bước 0 ≥ 110 dB, latent ≥ 100 dB, sóng âm ≥ 90 dB (sàn fp32 khác kernel); main
T234 / T256 so v bước 0 ≥ 110 dB.

Chạy: `python Scripts/vieneu_nano_static_export.py --out build/vieneu-nano-static`
Cần: `onnx==1.23.2 onnxruntime==1.24.2 numpy huggingface_hub` (ghim đúng như workflow để file ra giống nhau).
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import os
import sys
import tempfile
import urllib.request

import numpy as np
import onnx
import onnxruntime as ort
from onnx import TensorProto, helper, numpy_helper

REPO = "pnnbao-ump/VieNeu-TTS-v3-Nano"
REVISION = "aba295eb96a6fa6003ebe417cc1f2802a7adc1dc"
VOICES_URL = ("https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/2e982ff857bbe23fffa0c314e0f60da2497e2f4b/"
              "src/vieneu/assets/voices_v3_nano.json")
MODEL_FILES = ("config.json", "constants.npz", "text_encoder.onnx", "duration_predictor.onnx",
               "vector_estimator.onnx", "codec_decoder.onnx")
L_FROZEN = 200
VE_INLINE_BUCKET = 128
VE_EXTERNAL_BUCKETS = (234, 256)
CODEC_BUCKET = 128
STEPS, SWAY, CFG = 8, -1.0, 3.0
FPS, HOP, CHANNELS = 15.625, 1536, 144
# Ngưỡng tự kiểm theo **sàn fp32 khác kernel** (cùng seed, ORT_ENABLE_ALL vs DISABLE_ALL: v bước 0 ~123 dB, latent
# 109–116 dB, sóng âm 94–109 dB) — graph tĩnh gấp hằng / gộp Pad nên thứ tự cộng khác bản gốc đúng cỡ đó.
MIN_SNR_DB = {"v0": 110.0, "latent": 100.0, "wav": 90.0}
H1_CHUNK = 3
FORMAT_VERSION = 1

# 5 đoạn văn mẫu (sea-g2p → vocab), nhúng sẵn để CI không cần phonemizer. Độ dài 155/82/163/188/104 token ⇒
# T = 98/47/100/124/60 khung ở tốc độ 1× (đều ≤ 128).
GOLDEN_IDS = [
    [1, 25, 60, 45, 26, 3, 20, 60, 43, 40, 3, 44, 60, 36, 48, 40, 3, 31, 55, 60, 19, 27, 3, 44, 60, 22, 10, 52, 3, 27, 60, 32, 48, 23, 5, 3, 52, 60, 22, 9, 27, 3, 30, 60, 32, 45, 48, 40, 3, 31, 60, 32, 40, 3, 25, 60, 32, 11, 40, 3, 20, 60, 22, 45, 48, 3, 37, 60, 36, 45, 48, 23, 7, 3, 37, 60, 43, 48, 3, 25, 60, 19, 6, 12, 52, 3, 31, 60, 28, 10, 23, 3, 24, 34, 60, 15, 62, 5, 3, 26, 60, 15, 62, 40, 3, 31, 60, 47, 34, 3, 26, 60, 32, 9, 23, 3, 21, 60, 36, 45, 40, 3, 24, 61, 32, 45, 10, 3, 24, 60, 43, 10, 3, 24, 60, 45, 51, 3, 30, 60, 15, 34, 3, 24, 60, 45, 62, 27, 3, 26, 60, 36, 45, 7, 2],
    [1, 21, 60, 15, 48, 27, 3, 35, 60, 47, 11, 3, 31, 60, 45, 62, 10, 3, 37, 60, 15, 62, 9, 23, 5, 3, 31, 55, 60, 43, 40, 3, 25, 60, 43, 9, 40, 3, 37, 60, 45, 40, 3, 25, 60, 19, 27, 3, 26, 60, 28, 12, 31, 63, 3, 24, 60, 15, 62, 10, 26, 3, 37, 60, 15, 62, 48, 17, 3, 35, 60, 43, 48, 3, 31, 63, 60, 15, 62, 10, 7, 2],
    [1, 16, 60, 15, 62, 3, 27, 60, 15, 26, 3, 31, 55, 60, 36, 45, 48, 17, 5, 3, 21, 60, 15, 48, 27, 3, 31, 55, 60, 22, 10, 3, 25, 61, 15, 62, 9, 3, 26, 60, 28, 12, 31, 63, 3, 31, 60, 22, 47, 48, 34, 3, 27, 60, 22, 47, 27, 3, 16, 60, 22, 9, 52, 3, 31, 60, 36, 45, 9, 40, 3, 31, 55, 60, 43, 40, 3, 37, 60, 15, 62, 3, 31, 63, 60, 28, 12, 24, 5, 3, 16, 61, 22, 12, 3, 26, 61, 43, 12, 23, 3, 40, 60, 36, 45, 9, 23, 3, 24, 60, 43, 23, 3, 31, 60, 36, 45, 9, 40, 7, 3, 52, 61, 36, 40, 3, 16, 60, 45, 51, 3, 37, 60, 45, 62, 9, 5, 3, 26, 61, 43, 12, 23, 3, 31, 60, 36, 48, 3, 44, 61, 15, 62, 11, 3, 35, 60, 15, 62, 48, 17, 7, 2],
    [1, 30, 60, 36, 3, 20, 60, 32, 12, 5, 3, 40, 60, 36, 45, 9, 23, 3, 27, 60, 43, 48, 23, 3, 30, 60, 47, 26, 5, 3, 24, 61, 43, 27, 3, 44, 60, 36, 45, 9, 40, 3, 20, 60, 22, 45, 48, 3, 31, 55, 60, 36, 45, 48, 17, 3, 30, 61, 47, 11, 3, 53, 60, 15, 62, 3, 30, 60, 15, 62, 34, 14, 3, 21, 60, 15, 48, 27, 3, 21, 60, 43, 10, 23, 3, 52, 60, 43, 10, 7, 3, 35, 61, 28, 40, 3, 24, 60, 43, 48, 3, 60, 15, 62, 23, 3, 31, 55, 60, 15, 62, 10, 3, 25, 60, 45, 62, 9, 23, 5, 3, 31, 55, 60, 22, 10, 3, 24, 60, 43, 48, 3, 31, 63, 60, 22, 47, 48, 40, 3, 37, 60, 43, 48, 3, 53, 60, 22, 48, 31, 63, 3, 24, 34, 60, 15, 62, 3, 52, 61, 36, 11, 40, 3, 31, 63, 60, 15, 62, 48, 27, 3, 24, 60, 45, 51, 3, 24, 60, 28, 10, 3, 31, 60, 32, 12, 7, 2],
    [1, 21, 60, 15, 48, 27, 3, 27, 60, 15, 48, 26, 3, 31, 55, 60, 15, 12, 31, 63, 3, 31, 60, 19, 6, 52, 3, 24, 60, 22, 47, 48, 26, 3, 31, 55, 60, 43, 40, 3, 31, 63, 60, 15, 23, 5, 3, 60, 19, 6, 48, 52, 3, 26, 60, 15, 48, 31, 63, 3, 24, 60, 22, 47, 27, 3, 44, 60, 22, 12, 52, 3, 52, 60, 22, 9, 27, 3, 33, 60, 19, 9, 3, 20, 60, 22, 45, 48, 3, 31, 55, 60, 45, 27, 3, 31, 55, 60, 45, 62, 9, 23, 7, 2],
]


# ---------------------------------------------------------------- tiện ích

def log(message: str) -> None:
    print(message, flush=True)


def session_options(level=ort.GraphOptimizationLevel.ORT_ENABLE_ALL, optimized_path: str | None = None):
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.graph_optimization_level = level
    options.log_severity_level = 3
    options.add_session_config_entry("session.intra_op.allow_spinning", "0")
    if optimized_path:
        options.optimized_model_filepath = optimized_path
    return options


def open_session(path: str):
    return ort.InferenceSession(path, session_options(), providers=["CPUExecutionProvider"])


def snr_db(reference: np.ndarray, test: np.ndarray) -> float:
    reference = reference.astype(np.float64).ravel()
    test = test.astype(np.float64).ravel()
    count = min(reference.size, test.size)
    error = float(np.sum((reference[:count] - test[:count]) ** 2))
    return float("inf") if error == 0 else 10 * math.log10(float(np.sum(reference[:count] ** 2)) / error)


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def time_grid() -> np.ndarray:
    u = np.arange(STEPS + 1, dtype=np.float64) / STEPS
    return (u + SWAY * (np.cos(np.pi / 2 * u) - 1 + u)).astype(np.float32)


def download(model_dir: str) -> None:
    os.makedirs(model_dir, exist_ok=True)
    from huggingface_hub import hf_hub_download
    for name in MODEL_FILES:
        if not os.path.exists(os.path.join(model_dir, name)):
            hf_hub_download(REPO, name, revision=REVISION, local_dir=model_dir)
    voices = os.path.join(model_dir, "voices_v3_nano.json")
    if not os.path.exists(voices):
        urllib.request.urlretrieve(VOICES_URL, voices)


# ---------------------------------------------------------------- mổ graph

def freeze(model: onnx.ModelProto, dims: dict[str, list[int]], outputs: dict[str, list[int]]) -> None:
    for tensor in list(model.graph.input) + list(model.graph.output):
        shape = dims.get(tensor.name) or outputs.get(tensor.name)
        if shape is None:
            continue
        for dim, value in zip(tensor.type.tensor_type.shape.dim, shape):
            dim.ClearField("dim_param")
            dim.dim_value = value


def ort_basic(model: onnx.ModelProto, work: str, name: str) -> onnx.ModelProto:
    """Gấp hằng + dọn node thừa bằng ORT mức BASIC (không phụ thuộc phần cứng)."""
    source = os.path.join(work, f"{name}.frozen.onnx")
    target = os.path.join(work, f"{name}.basic.onnx")
    onnx.save(model, source)
    ort.InferenceSession(source, session_options(ort.GraphOptimizationLevel.ORT_ENABLE_BASIC, target),
                         providers=["CPUExecutionProvider"])
    return onnx.load(target)


def expose_frame_mask(model: onnx.ModelProto) -> None:
    node = next(n for n in model.graph.node if n.name == "/ConstantOfShape")
    produced = node.output[0]
    model.graph.node.remove(node)
    model.graph.input.append(helper.make_tensor_value_info("frame_mask", TensorProto.BOOL, [1, "T"]))
    for other in model.graph.node:
        for index, name in enumerate(other.input):
            if name == produced:
                other.input[index] = "frame_mask"


def rewrite_masked_where(model: onnx.ModelProto) -> int:
    """`Where(c, -FLT_MAX, y)` ⇒ `Add(y, Where(c, -1e4, 0))` — nhánh bias chỉ phụ thuộc mask nên rơi vào prep."""
    graph = model.graph
    initializers = {t.name: t for t in graph.initializer}
    graph.initializer.extend([numpy_helper.from_array(np.array(-1e4, np.float32), "p1_neg_bias"),
                              numpy_helper.from_array(np.array(0.0, np.float32), "p1_zero")])
    rewritten = 0
    for node in list(graph.node):
        if node.op_type != "Where" or node.input[1] not in initializers:
            continue
        value = numpy_helper.to_array(initializers[node.input[1]])
        if value.size != 1 or float(value) > -1e30:
            continue
        bias = node.output[0] + "_p1bias"
        index = list(graph.node).index(node)
        graph.node.remove(node)
        graph.node.insert(index, helper.make_node("Add", [node.input[2], bias], [node.output[0]], name=node.name + "_p1add"))
        graph.node.insert(index, helper.make_node("Where", [node.input[0], "p1_neg_bias", "p1_zero"], [bias],
                                                  name=node.name + "_p1bias"))
        rewritten += 1
    return rewritten


def split_prep_main(model: onnx.ModelProto) -> tuple[onnx.ModelProto, onnx.ModelProto]:
    prep_inputs = {"frame_mask", "ctx_mask", "t"}
    graph = model.graph
    init_names = {t.name for t in graph.initializer}
    deps: dict[str, set[str]] = {i.name: {i.name} for i in graph.input}
    for name in init_names:
        deps[name] = set()
    for node in graph.node:
        merged: set[str] = set()
        for name in node.input:
            if name:
                merged |= deps.get(name, set())
        for name in node.output:
            deps[name] = merged

    def is_prep(name: str) -> bool:
        return 0 < len(deps.get(name, set())) and deps[name] <= prep_inputs

    def is_prep_node(node: onnx.NodeProto) -> bool:
        return all(is_prep(o) for o in node.output)

    boundary: list[str] = []
    for node in graph.node:
        if is_prep_node(node):
            continue
        for name in node.input:
            if name and name not in init_names and name not in prep_inputs and is_prep(name) and name not in boundary:
                boundary.append(name)
            if name in prep_inputs:
                raise RuntimeError(f"node chính {node.name} dùng thẳng {name} — chưa hỗ trợ")
    # Extractor cần value_info của mọi tensor biên ⇒ suy shape trước (bản trong RAM không tự suy như bản đọc file).
    inferred = onnx.shape_inference.infer_shapes(model)
    prep = onnx.utils.Extractor(inferred).extract_model(sorted(prep_inputs), boundary)
    value_info = {v.name: v for v in inferred.graph.value_info}
    main = onnx.ModelProto()
    main.CopyFrom(model)
    kept = [n for n in main.graph.node if not is_prep_node(n)]
    del main.graph.node[:]
    main.graph.node.extend(kept)
    kept_inputs = [i for i in main.graph.input if i.name not in prep_inputs]
    del main.graph.input[:]
    main.graph.input.extend(kept_inputs)
    for name in boundary:
        main.graph.input.append(value_info.get(name) or helper.make_tensor_value_info(name, TensorProto.FLOAT, None))
    used = {name for n in main.graph.node for name in n.input}
    kept_init = [t for t in main.graph.initializer if t.name in used]
    del main.graph.initializer[:]
    main.graph.initializer.extend(kept_init)
    del main.graph.value_info[:]
    return prep, main


def floatify_bool_inputs(model: onnx.ModelProto) -> None:
    """Input bool ⇒ input float32 cùng tên + `Cast` sang bool ở đầu graph (app chỉ truyền float)."""
    graph = model.graph
    casts = []
    for tensor in graph.input:
        if tensor.type.tensor_type.elem_type != TensorProto.BOOL:
            continue
        internal = tensor.name + "__bool"
        tensor.type.tensor_type.elem_type = TensorProto.FLOAT
        for node in graph.node:
            for index, name in enumerate(node.input):
                if name == tensor.name:
                    node.input[index] = internal
        casts.append(helper.make_node("Cast", [tensor.name], [internal], to=TensorProto.BOOL,
                                      name=tensor.name + "_p1cast"))
    for offset, node in enumerate(casts):
        graph.node.insert(offset, node)


def fuse_left_pads(model: onnx.ModelProto) -> int:
    graph = model.graph
    initializers = {t.name: t for t in graph.initializer}
    consumers: dict[str, list[onnx.NodeProto]] = collections.defaultdict(list)
    for node in graph.node:
        for name in node.input:
            consumers[name].append(node)
    fused = 0
    for node in list(graph.node):
        if node.op_type != "Pad" or node.input[1] not in initializers:
            continue
        mode = next((a.s.decode() for a in node.attribute if a.name == "mode"), "constant")
        users = consumers[node.output[0]]
        if mode != "constant" or len(users) != 1 or users[0].op_type != "Conv":
            continue
        if len(node.input) > 2 and node.input[2]:
            continue
        pads = numpy_helper.to_array(initializers[node.input[1]]).tolist()
        rank = len(pads) // 2
        begin, end = pads[:rank], pads[rank:]
        if any(begin[:2]) or any(end[:2]):
            continue
        conv = users[0]
        spatial = rank - 2
        pads_attr = next((a for a in conv.attribute if a.name == "pads"), None)
        old = list(pads_attr.ints) if pads_attr is not None else [0] * (2 * spatial)
        new = [old[i] + begin[2 + i] for i in range(spatial)] + [old[spatial + i] + end[2 + i] for i in range(spatial)]
        if pads_attr is None:
            conv.attribute.append(helper.make_attribute("pads", new))
        else:
            del pads_attr.ints[:]
            pads_attr.ints.extend(new)
        conv.input[0] = node.input[0]
        graph.node.remove(node)
        fused += 1
    return fused


def batchnorm_to_mul_add(model: onnx.ModelProto) -> int:
    graph = model.graph
    initializers = {t.name: numpy_helper.to_array(t) for t in graph.initializer}
    replaced = 0
    for node in list(graph.node):
        if node.op_type != "BatchNormalization":
            continue
        epsilon = next((a.f for a in node.attribute if a.name == "epsilon"), 1e-5)
        scale, bias, mean, var = (initializers[name].astype(np.float64) for name in node.input[1:5])
        a = scale / np.sqrt(var + epsilon)
        b = bias - mean * a
        shape = (1, a.size, 1)
        a_name, b_name = node.name + "_p1scale", node.name + "_p1shift"
        graph.initializer.extend([numpy_helper.from_array(a.astype(np.float32).reshape(shape), a_name),
                                  numpy_helper.from_array(b.astype(np.float32).reshape(shape), b_name)])
        index = list(graph.node).index(node)
        graph.node.remove(node)
        middle = node.output[0] + "_p1mul"
        graph.node.insert(index, helper.make_node("Add", [middle, b_name], [node.output[0]], name=node.name + "_p1add"))
        graph.node.insert(index, helper.make_node("Mul", [node.input[0], a_name], [middle], name=node.name + "_p1mul"))
        replaced += 1
    return replaced


def save_external(models: list[tuple[onnx.ModelProto, str]], weights_path: str, threshold: int = 1024) -> None:
    """Ghi các model với tensor lớn ở **một** file trọng số dùng chung (cùng tên + cùng nội dung ⇒ cùng vùng)."""
    table: dict[str, tuple[int, int, str]] = {}
    location = os.path.basename(weights_path)
    with open(weights_path, "wb") as handle:
        for model, path in models:
            for tensor in model.graph.initializer:
                raw = numpy_helper.to_array(tensor).tobytes()
                if len(raw) < threshold:
                    continue
                digest = hashlib.sha1(raw).hexdigest()
                key = tensor.name if table.get(tensor.name, (0, 0, digest))[2] == digest else f"{tensor.name}#{digest}"
                if key not in table:
                    pad = (-handle.tell()) % 4096
                    handle.write(b"\0" * pad)
                    table[key] = (handle.tell(), len(raw), digest)
                    handle.write(raw)
                offset, length, _ = table[key]
                for field in ("raw_data", "float_data", "int32_data", "int64_data", "double_data"):
                    tensor.ClearField(field)
                tensor.data_location = TensorProto.EXTERNAL
                del tensor.external_data[:]
                for k, v in (("location", location), ("offset", str(offset)), ("length", str(length))):
                    entry = tensor.external_data.add()
                    entry.key, entry.value = k, v
            onnx.save(model, path)


# ---------------------------------------------------------------- golden + quỹ đạo

def load_assets(model_dir: str) -> dict:
    config = json.load(open(os.path.join(model_dir, "config.json"), encoding="utf-8"))
    constants = np.load(os.path.join(model_dir, "constants.npz"))
    voices = json.load(open(os.path.join(model_dir, "voices_v3_nano.json"), encoding="utf-8"))
    preset = voices["presets"][voices["default_voice"]]
    return {
        "config": config,
        "spk": np.array(preset["speaker_emb"], np.float32)[None, :],
        "style": np.array(preset["style"], np.float32)[None, :, :],
        "null_spk": constants["null_spk"].astype(np.float32)[None, :],
        "null_style": constants["null_style"].astype(np.float32)[None, :, :],
        "voice": voices["default_voice"],
    }


def pad_ctx(ctx: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    padded = np.zeros((1, L_FROZEN, ctx.shape[2]), np.float32)
    padded[:, :ctx.shape[1]] = ctx
    mask = np.zeros((1, L_FROZEN), np.float32)
    mask[0, :ctx.shape[1]] = 1
    return padded, mask


def reference_chunks(model_dir: str, assets: dict) -> tuple[list[dict], np.ndarray]:
    te = open_session(os.path.join(model_dir, "text_encoder.onnx"))
    dp = open_session(os.path.join(model_dir, "duration_predictor.onnx"))
    ve = open_session(os.path.join(model_dir, "vector_estimator.onnx"))
    cd = open_session(os.path.join(model_dir, "codec_decoder.onnx"))
    cfg = assets["config"]
    null_ctx = te.run(None, {"ids": np.array([[cfg["bos_id"], cfg["eos_id"]]], np.int64), "style": assets["null_style"]})[0]
    grid = time_grid()
    chunks = []
    for k, ids in enumerate(GOLDEN_IDS):
        ids_array = np.array([ids], np.int64)
        ctx = te.run(None, {"ids": ids_array, "style": assets["style"]})[0]
        mask = np.ones((1, ctx.shape[1]), bool)
        log_s = float(dp.run(None, {"ctx": ctx, "ctx_mask": mask, "spk": assets["spk"]})[0].reshape(-1)[0])
        frames = max(2, int(round(min(math.exp(log_s), 15.0) * FPS)))
        if frames > VE_INLINE_BUCKET:
            raise RuntimeError(f"đoạn {k}: T={frames} > bucket {VE_INLINE_BUCKET}")
        x = np.random.default_rng(1000 + k).standard_normal((1, CHANNELS, frames)).astype(np.float32)
        x0 = x.copy()
        v0 = None
        for step in range(STEPS):
            t = np.array([grid[step]], np.float32)
            v = ve.run(None, {"x": x, "t": t, "ctx": ctx, "ctx_mask": mask, "spk": assets["spk"], "style": assets["style"]})[0]
            vu = ve.run(None, {"x": x, "t": t, "ctx": null_ctx, "ctx_mask": np.ones((1, 2), bool),
                               "spk": assets["null_spk"], "style": assets["null_style"]})[0]
            velocity = vu + CFG * (v - vu)
            if v0 is None:
                v0 = velocity.copy()
            x = x + np.float32(grid[step + 1] - grid[step]) * velocity
        wav = cd.run(None, {"x": x})[0].reshape(-1)
        ctx_p, ctx_m = pad_ctx(ctx)
        chunks.append({"ctx": ctx_p, "cmask": ctx_m, "T": frames, "x0": x0, "v0": v0, "lat": x, "wav": wav})
        log(f"  đoạn {k}: L={ctx.shape[1]} T={frames} mẫu={wav.size}")
    null_p, null_m = pad_ctx(null_ctx)
    return chunks, np.concatenate([null_p.reshape(-1), null_m.reshape(-1)])


class StaticRunner:
    """Chạy prep + main + codec đã xuất (đọc lại từ đĩa) — y như phía app sẽ chạy."""

    def __init__(self, prep_path: str, main_path: str, codec_path: str | None, bucket: int):
        self.prep = open_session(prep_path)
        self.main = open_session(main_path)
        self.codec = open_session(codec_path) if codec_path else None
        self.bucket = bucket
        self.prep_outputs = [o.name for o in self.prep.get_outputs()]
        self.main_inputs = [i.name for i in self.main.get_inputs()]

    def velocity(self, x, t, ctx, cmask, spk, style, frames):
        frame_mask = np.zeros((1, self.bucket), np.float32)
        frame_mask[0, :frames] = 1
        prepared = dict(zip(self.prep_outputs, self.prep.run(None, {"frame_mask": frame_mask, "ctx_mask": cmask, "t": t})))
        feeds = {"x": x, "ctx": ctx, "spk": spk, "style": style}
        feeds.update(prepared)
        return self.main.run(None, {name: feeds[name] for name in self.main_inputs})[0]

    def trajectory(self, chunk, null_ctx, null_mask, assets):
        frames, grid = chunk["T"], time_grid()
        x = np.zeros((1, CHANNELS, self.bucket), np.float32)
        x[:, :, :frames] = chunk["x0"]
        v0 = None
        for step in range(STEPS):
            t = np.array([grid[step]], np.float32)
            v = self.velocity(x, t, chunk["ctx"], chunk["cmask"], assets["spk"], assets["style"], frames)
            vu = self.velocity(x, t, null_ctx, null_mask, assets["null_spk"], assets["null_style"], frames)
            velocity = vu + CFG * (v - vu)
            if v0 is None:
                v0 = velocity[:, :, :frames].copy()
            x = x + np.float32(grid[step + 1] - grid[step]) * velocity
        latent = x[:, :, :frames]
        wav = self.codec.run(None, {"x": x})[0].reshape(-1)[: frames * HOP] if self.codec else None
        return v0, latent, wav


# ---------------------------------------------------------------- chính

def build(out: str, model_dir: str) -> int:
    os.makedirs(out, exist_ok=True)
    work = tempfile.mkdtemp(prefix="vieneu-p1-")
    log(f"Tải model {REPO}@{REVISION[:8]} …")
    download(model_dir)
    assets = load_assets(model_dir)

    log("Dựng graph VE tĩnh …")
    base = onnx.load(os.path.join(model_dir, "vector_estimator.onnx"))
    expose_frame_mask(base)
    preps, mains = {}, {}
    for bucket in (VE_INLINE_BUCKET, *VE_EXTERNAL_BUCKETS):
        model = onnx.ModelProto()
        model.CopyFrom(base)
        freeze(model, {"x": [1, CHANNELS, bucket], "t": [1], "ctx": [1, L_FROZEN, 256], "ctx_mask": [1, L_FROZEN],
                       "spk": [1, 192], "style": [1, 50, 256], "frame_mask": [1, bucket]}, {"v": [1, CHANNELS, bucket]})
        model = ort_basic(model, work, f"ve_T{bucket}")
        count = rewrite_masked_where(model)
        prep, main = split_prep_main(model)
        floatify_bool_inputs(prep)
        preps[bucket], mains[bucket] = prep, main
        log(f"  T{bucket}: Where viết lại {count}, prep {len(prep.graph.node)} node, main {len(main.graph.node)} node, "
            f"main {len(main.graph.input)} input")

    for bucket, prep in preps.items():
        onnx.save(prep, os.path.join(out, f"ve_prep_T{bucket}.onnx"))
    onnx.save(mains[VE_INLINE_BUCKET], os.path.join(out, f"ve_main_T{VE_INLINE_BUCKET}.onnx"))
    save_external([(mains[b], os.path.join(out, f"ve_main_T{b}.onnx")) for b in VE_EXTERNAL_BUCKETS],
                  os.path.join(out, "ve_main.weights"))

    log("Dựng codec tĩnh …")
    codec = onnx.load(os.path.join(model_dir, "codec_decoder.onnx"))
    freeze(codec, {"x": [1, CHANNELS, CODEC_BUCKET]}, {})
    codec = ort_basic(codec, work, f"codec_T{CODEC_BUCKET}")
    pads, norms = fuse_left_pads(codec), batchnorm_to_mul_add(codec)
    onnx.save(codec, os.path.join(out, f"codec_T{CODEC_BUCKET}.onnx"))
    log(f"  gộp {pads} Pad vào Conv, đổi {norms} BatchNorm")

    log("Golden (graph gốc, ORT CPU) …")
    chunks, null_flat = reference_chunks(model_dir, assets)
    null_ctx = null_flat[: L_FROZEN * 256].reshape(1, L_FROZEN, 256)
    null_mask = null_flat[L_FROZEN * 256:].reshape(1, L_FROZEN)
    golden = {"grid": time_grid(), "spk": assets["spk"], "style": assets["style"], "null_spk": assets["null_spk"],
              "null_style": assets["null_style"], "null_ctx": null_ctx, "null_cmask": null_mask}
    for k, chunk in enumerate(chunks):
        for key in ("ctx", "cmask", "x0", "v0", "lat", "wav"):
            golden[f"c{k}_{key}"] = chunk[key].astype(np.float32)
        golden[f"c{k}_T"] = np.array([chunk["T"]], np.float32)
    np.savez(os.path.join(out, "golden.npz"), **golden)

    log("Tự kiểm (nạp lại từ đĩa) …")
    report = {"chunks": [], "h1": {}}
    ok = True
    runner = StaticRunner(os.path.join(out, f"ve_prep_T{VE_INLINE_BUCKET}.onnx"),
                          os.path.join(out, f"ve_main_T{VE_INLINE_BUCKET}.onnx"),
                          os.path.join(out, f"codec_T{CODEC_BUCKET}.onnx"), VE_INLINE_BUCKET)
    for k, chunk in enumerate(chunks):
        v0, latent, wav = runner.trajectory(chunk, null_ctx, null_mask, assets)
        row = {"T": chunk["T"], "v0": snr_db(chunk["v0"], v0), "latent": snr_db(chunk["lat"], latent),
               "wav": snr_db(chunk["wav"], wav)}
        report["chunks"].append(row)
        ok &= all(row[key] >= MIN_SNR_DB[key] for key in ("v0", "latent", "wav"))
        log(f"  đoạn {k}: v0 {row['v0']:.1f} dB · latent {row['latent']:.1f} dB · sóng âm {row['wav']:.1f} dB")
    chunk = chunks[H1_CHUNK]
    for bucket in VE_EXTERNAL_BUCKETS:
        external = StaticRunner(os.path.join(out, f"ve_prep_T{bucket}.onnx"),
                                os.path.join(out, f"ve_main_T{bucket}.onnx"), None, bucket)
        t = np.array([time_grid()[0]], np.float32)
        x = np.zeros((1, CHANNELS, bucket), np.float32)
        x[:, :, :chunk["T"]] = chunk["x0"]
        v = external.velocity(x, t, chunk["ctx"], chunk["cmask"], assets["spk"], assets["style"], chunk["T"])
        vu = external.velocity(x, t, null_ctx, null_mask, assets["null_spk"], assets["null_style"], chunk["T"])
        value = snr_db(chunk["v0"], (vu + CFG * (v - vu))[:, :, :chunk["T"]])
        report["h1"][f"T{bucket}"] = value
        ok &= value >= MIN_SNR_DB["v0"]
        log(f"  main T{bucket} (external data): v0 {value:.1f} dB")
    if not ok:
        log("❌ Tự kiểm không đạt — không ghi manifest.")
        return 1

    with open(os.path.join(out, "NOTICE.txt"), "w", encoding="utf-8") as handle:
        handle.write(
            f"VieNeu-TTS v3 Nano — graph tĩnh cho thử nghiệm Core ML / XNNPACK (Tàng Công Các)\n\n"
            f"Nguồn: https://huggingface.co/{REPO} (revision {REVISION}), giấy phép Apache-2.0.\n"
            "Trọng số giữ nguyên. Đã sửa graph: mở mask khung thành input `frame_mask`, đóng băng shape (T bucket,\n"
            "L = 200), gấp hằng (ONNX Runtime 1.24.2 mức BASIC), đổi Where(mask, -FLT_MAX, ·) thành Add(bias),\n"
            "tách graph chuẩn bị / graph chính; codec: gộp Pad vào Conv, đổi BatchNormalization thành Mul + Add.\n"
            "Sinh bởi Scripts/vieneu_nano_static_export.py.\n")
    files = sorted(name for name in os.listdir(out) if name != "manifest.json")
    manifest = {
        "format": FORMAT_VERSION, "sourceRepo": REPO, "sourceRevision": REVISION, "voice": assets["voice"],
        "veInlineBucket": VE_INLINE_BUCKET, "veExternalBuckets": list(VE_EXTERNAL_BUCKETS), "codecBucket": CODEC_BUCKET,
        "lengthFrozen": L_FROZEN, "steps": STEPS, "sway": SWAY, "cfg": CFG, "goldenChunks": len(chunks),
        "h1Chunk": H1_CHUNK, "selfTest": report,
        "files": [{"name": name, "bytes": os.path.getsize(os.path.join(out, name)),
                   "sha256": sha256(os.path.join(out, name))} for name in files],
    }
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=1)
    total = sum(f["bytes"] for f in manifest["files"])
    log(f"✅ Xong: {len(files)} file, {total / 1e6:.1f} MB ở {out}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default="build/vieneu-nano-static")
    parser.add_argument("--model-dir", default="build/vieneu-nano-source")
    args = parser.parse_args()
    return build(args.out, args.model_dir)


if __name__ == "__main__":
    sys.exit(main())
