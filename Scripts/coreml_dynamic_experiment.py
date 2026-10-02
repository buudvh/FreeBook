"""**Phase 0** — chứng minh `.mlpackage` **shape động** cho VieNeu-TTS v3 Nano.

Đây là **cổng** của plan `Docs/Plans/2026-10-02-plan-vieneu-coreml-engine-trong-app.md`: đạt thì mới
làm engine Core ML trong app; không đạt thì dừng và báo cáo số đo, **không** tự chuyển sang phương án
bucket.

## Vì sao phải là shape động

Trọng số chiếm gần hết dung lượng gói, **không** phải activation: `vector_estimator` fp16 nặng 78,1 MB ở
shape `L=160,T=96` **và** 78,5 MB ở `L=200,T=234`. Nghĩa là bucket hoá tốn **127,8 MB cho MỖI mức** ⇒ 4
mức đã 512 MB, gấp rưỡi 347 MB hiện tại. Một gói shape động phủ mọi câu thì tổng chỉ ~141,6 MB.

## Năm đường được thử (mỗi đường bọc `try/except`, lỗi là KẾT QUẢ)

Thiết kế theo kiểu **mỗi đường trả lời đúng một câu hỏi**, để bảng kết quả là một bảng chẩn đoán chứ
không phải một danh sách "hỏng/hỏng/hỏng":

| Đường | Nguồn | Câu hỏi nó trả lời |
|---|---|---|
| `o2c_original` | graph gốc | `onnx2coreml` chặn vì **op** nào? |
| `o2c_surgery` | đã phẫu thuật | gỡ op rồi thì `onnx2coreml` còn chặn vì gì? (kỳ vọng: **chiều động**) |
| `torch_original` | graph gốc | `onnx2torch` chặn vì **op** nào? |
| `torch_surgery` | đã phẫu thuật | gỡ op rồi thì `torch.jit.trace` có **giữ chiều động** không? |
| `torch_enum_T` | đã phẫu thuật | nếu trace giữ được, `EnumeratedShapes` cho `T` có dựng được gói không? |

`torch_surgery`/`torch_enum_T` trả thêm `trace_shapes`: chạy lại graph **đã trace** ở 3 shape khác. Đây
là phép kiểm quyết định — `torch.jit.trace` chỉ ghi lại op, nhưng op nào không trace được (ví dụ
`torch.Size(...)` trong `onnx2torch/node_converters/reshape.py:23`) thì torch.jit **tính ngay lúc trace
rồi nướng kết quả thành hằng** ⇒ graph đã trace chỉ đúng ở đúng shape đã trace.

## Bốn thứ luôn được thu, kể cả khi mọi đường đều hỏng

1. `range_report.json` — từng node `Range` phụ thuộc chiều nào, cần `MAX` bao nhiêu.
2. `surgery_parity.json` — ORT chạy graph **gốc** vs graph **đã phẫu thuật** ở 3 shape: kỳ vọng
   `max|Δ| = 0`. Đây là phép kiểm **tách hẳn** "phẫu thuật `Range` sai" khỏi "convert sai" — không có nó
   thì hai loại lỗi trông giống hệt nhau và ta sẽ đi sửa nhầm chỗ.
3. `dynamic.json` — kết quả từng đường, **nguyên văn** thông báo lỗi.
4. `bucket_fallback.json` — số đo của phương án bucket (độ trễ từng mức + tổng dung lượng), để nếu
   shape động thất bại thì người dùng có số liệu mà quyết định thay vì quyết theo cảm giác.

Chạy: `python Scripts/coreml_dynamic_experiment.py --out reports-dynamic --workdir coreml-dynamic`
"""
from __future__ import annotations

import argparse
import json
import os
import time
import traceback

# Dùng lại hạ tầng đã kiểm chứng của lượt baseline: cùng nguồn model, cùng cách chốt shape, cùng cách
# cho ORT gấp hằng số. Cố ý **không** sao chép — hai bản sao sẽ trôi khỏi nhau.
from coreml_convert_experiment import (
    BUCKETS,
    MODEL_FILES,
    PHONEMES,
    REVISION,
    fold_range,
    freeze_shapes,
    log,
    machine_info,
    optimize_with_ort,
    stage_download,
)
from coreml_shape_surgery import apply as surgery_apply

GRAPHS = ["text_encoder.onnx", "duration_predictor.onnx", "vector_estimator.onnx", "codec_decoder.onnx"]

# Ba shape đại diện: câu ngắn, câu điển hình, trần (`maxChunkSeconds × flowFPS`).
SHAPES = {
    "small": {"L": 64, "T": 32},
    "typical": {"L": 160, "T": 96},
    "max": {"L": 200, "T": 234},
}

# `EnumeratedShapes` cho `T` — 5 mức, phủ dải 2…234.
T_ENUMERATED = [32, 64, 96, 160, 234]

# Bucket dự phòng (nếu shape động thất bại): chỉ 2 graph nặng, 3 mức `T`.
FALLBACK_BUCKETS = {
    "t64": {"L": 200, "T": 64},
    "t128": {"L": 200, "T": 128},
    "t234": {"L": 200, "T": 234},
}
FALLBACK_GRAPHS = ["vector_estimator.onnx", "codec_decoder.onnx"]


# ─────────────────────────── Input ───────────────────────────
def load_config(model_dir: str) -> dict:
    with open(os.path.join(model_dir, "config.json"), encoding="utf-8") as handle:
        return json.load(handle)


def load_voice(workdir: str, config: dict):
    import numpy as np

    with open(os.path.join(workdir, "voices_v3_nano.json"), encoding="utf-8") as handle:
        presets = json.load(handle)
    voice = presets["presets"][presets["default_voice"]]
    speaker = np.asarray(voice["speaker_emb"], dtype=np.float32).reshape(1, -1)
    style = np.asarray(voice["style"], dtype=np.float32).reshape(1, config["n_style"], config["style_dim"])
    return speaker, style


def real_ids(config: dict):
    """`ids` thật: phoneme chép từ `app_logs (60).txt` — input của phép so là dữ liệu thật, không phải nhiễu."""
    import numpy as np

    vocab = {key: int(value) for key, value in config["vocab"].items()}
    ids = [config["bos_id"]] + [vocab[c] for c in PHONEMES if c in vocab] + [config["eos_id"]]
    return np.asarray(ids, dtype=np.int64).reshape(1, -1)


def build_context(model_dir: str, config: dict, ids, style, length: int):
    """`ctx` + `ctx_mask` **thật** từ `text_encoder`, đệm/cắt về đúng `length`."""
    import numpy as np
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    encoder = ort.InferenceSession(os.path.join(model_dir, "text_encoder.onnx"), options,
                                   providers=["CPUExecutionProvider"])
    ctx = encoder.run(None, {"ids": ids, "style": style})[0]

    channels = ctx.shape[2]
    padded = np.zeros((1, length, channels), dtype=np.float32)
    keep = min(length, ctx.shape[1])
    padded[:, :keep, :] = ctx[:, :keep, :]
    mask = np.zeros((1, length), dtype=np.bool_)
    mask[:, :keep] = True
    return padded, mask


def make_feeds(model_dir: str, workdir: str, length: int, frames: int) -> dict:
    """Mọi tensor cần cho **cả 4** graph ở shape `(L=length, T=frames)`. Graph nào dùng tập con thì tự lấy.

    ⚠️ **Bẫy đã trả giá ở lượt CI #2**: `ids` phải được **cắt/đệm về đúng `length`**. Bản đầu dùng
    `real_ids(config)` nguyên trạng (~140 phần tử) bất kể `length` ⇒ `text_encoder` nhận **cùng một**
    shape ở cả 3 "shape" đại diện ⇒ phép thử `trace_shapes` của nó **rỗng nghĩa**: nó "đạt" mà không
    chứng minh gì. Đúng loại lỗi nguy hiểm nhất — xanh vì phép kiểm không đo gì.
    """
    import numpy as np

    config = load_config(model_dir)
    speaker, style = load_voice(workdir, config)
    ids = _fit_ids(real_ids(config), length, config["pad_id"])
    ctx, mask = build_context(model_dir, config, ids, style, length)
    latent_channels = config["latent_dim"] * config["group"]
    return {
        "config": config,
        "ids": ids,
        "style": style,
        "spk": speaker,
        "ctx": ctx,
        "ctx_mask": mask,
        "x": np.random.default_rng(20261002).standard_normal((1, latent_channels, frames)).astype(np.float32),
        "t": np.asarray([0.5], dtype=np.float32),
    }


def _fit_ids(ids, length: int, pad_id: int):
    """Cắt hoặc đệm `ids` cho đúng `length` để `L` **thật sự** đổi giữa các shape đo."""
    import numpy as np

    if ids.shape[1] == length:
        return ids
    if ids.shape[1] > length:
        return ids[:, :length]
    padding = np.full((1, length - ids.shape[1]), pad_id, dtype=np.int64)
    return np.concatenate([ids, padding], axis=1)


def feeds_for(graph: str, feeds: dict) -> dict:
    table = {
        "text_encoder.onnx": ["ids", "style"],
        "duration_predictor.onnx": ["ctx", "ctx_mask", "spk"],
        "vector_estimator.onnx": ["x", "t", "ctx", "ctx_mask", "spk", "style"],
        "codec_decoder.onnx": ["x"],
    }
    return {name: feeds[name] for name in table[graph]}


# ─────────────────────────── Đặc tả shape cho `ct.convert` ───────────────────────────
def dynamic_spec(graph: str, config: dict, use_enumerated_T: bool):
    """Trả `(input_names, shapes)` — `shapes` đã ở dạng dùng thẳng cho `ct.TensorType(shape=)`.

    ⚠️ **Bẫy đã trả giá ở lượt CI #2**: `x` của `vector_estimator`/`codec_decoder` là
    `[1, latent_channels, T]` — **3 chiều**, với `T` ở chiều **thứ ba**. Trả về một `RangeDim` trần làm
    *cả* shape sẽ ra `ValueError: Shape should be list or tuple, got type RangeDim`. `T` phải nằm trong
    danh sách: `[1, channels, RangeDim]`.

    `L` và `T` là hai chiều động duy nhất. `T` có thể đổi sang `EnumeratedShapes` (đối tượng spec dùng
    thẳng, **không** bọc thêm `ct.Shape`) để ANE khỏi phải đặc biệt hoá theo từng giá trị.
    """
    import coremltools as ct

    style_dim, n_style = config["style_dim"], config["n_style"]
    channels = config["latent_dim"] * config["group"]

    def dim_L():
        return ct.RangeDim(lower_bound=2, upper_bound=512, default=160)

    def shape_x():
        if use_enumerated_T:
            return ct.EnumeratedShapes(shapes=[[1, channels, value] for value in T_ENUMERATED])
        return ct.Shape(shape=[1, channels, ct.RangeDim(lower_bound=2, upper_bound=256, default=96)])

    if graph == "text_encoder.onnx":
        return ["ids", "style"], [ct.Shape(shape=[1, dim_L()]), ct.Shape(shape=[1, n_style, style_dim])]
    if graph == "duration_predictor.onnx":
        return (["ctx", "ctx_mask", "spk"],
                [ct.Shape(shape=[1, dim_L(), style_dim]), ct.Shape(shape=[1, dim_L()]),
                 ct.Shape(shape=[1, 192])])
    if graph == "vector_estimator.onnx":
        return (["x", "t", "ctx", "ctx_mask", "spk", "style"],
                [shape_x(), ct.Shape(shape=[1]), ct.Shape(shape=[1, dim_L(), style_dim]),
                 ct.Shape(shape=[1, dim_L()]), ct.Shape(shape=[1, 192]),
                 ct.Shape(shape=[1, n_style, style_dim])])
    return ["x"], [shape_x()]


# ─────────────────────────── Năm đường convert ───────────────────────────
def route_o2c(graph: str, source: str, package: str, context: dict) -> dict:
    """`onnx2coreml` — đường đã chạy được ở lượt baseline, nhưng **chỉ khi shape đã đóng băng**."""
    import onnx2coreml as o2c

    mlmodel = o2c.convert(source, format="mlpackage", minimum_deployment_target="iOS17")
    mlmodel.save(package)
    return {}


def _torch_pipeline(graph: str, source: str, package: str, context: dict, enumerated_T: bool) -> dict:
    """`onnx2torch` → `torch.jit.trace` → `ct.convert` + `RangeDim`/`EnumeratedShapes`.

    Trả thêm `trace_shapes`: chạy lại graph **đã trace** ở 3 shape khác để **đo** xem trace có giữ được
    chiều động không. `torch.jit.trace` chỉ ghi lại op, nhưng op nào không trace được (ví dụ
    `torch.Size(...)` trong `onnx2torch/node_converters/reshape.py:23`) thì torch.jit **tính ngay lúc
    trace rồi nướng kết quả thành hằng** ⇒ graph đã trace chỉ đúng ở đúng shape đã trace. Đây là bằng
    chứng trực tiếp cho kết luận, không phải suy đoán — và nó rẻ hơn nhiều so với việc đi đoán qua
    thông báo lỗi của `ct.convert`.
    """
    import coremltools as ct
    import onnx2torch
    import torch

    torch_model = onnx2torch.convert(source)
    torch_model.eval()

    names, shapes = dynamic_spec(graph, context["config"], enumerated_T)
    example = make_feeds(context["model_dir"], context["workdir"], 160, 96)
    args = []
    for name in names:
        array = example[name]
        if array.dtype == bool:
            dtype = torch.bool
        elif array.dtype.kind == "i":
            dtype = torch.int64
        else:
            dtype = torch.float32
        args.append(torch.as_tensor(array, dtype=dtype))
    traced = torch.jit.trace(torch_model, tuple(args), strict=False)

    probe: dict = {}
    for shape_name, shape in SHAPES.items():
        feeds = make_feeds(context["model_dir"], context["workdir"], shape["L"], shape["T"])
        try:
            out = traced(*[torch.as_tensor(feeds[name]) for name in names])
            tensor = out[0] if isinstance(out, (tuple, list)) else out
            probe[shape_name] = {"ok": True, "shape": list(tensor.shape)}
        except Exception as error:  # noqa: BLE001 — kết quả cần ghi
            probe[shape_name] = {"ok": False,
                                 "error": f"{type(error).__name__}: {str(error).splitlines()[0][:200]}"}

    # `spec` đã là `ct.Shape` hoặc `ct.EnumeratedShapes` — bọc thêm một lớp `ct.Shape` là sai.
    inputs = [ct.TensorType(name=name, shape=spec) for name, spec in zip(names, shapes)]
    mlmodel = ct.convert(
        traced,
        inputs=inputs,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    mlmodel.save(package)
    return {"trace_shapes": probe}


def route_torch(graph: str, source: str, package: str, context: dict) -> dict:
    return _torch_pipeline(graph, source, package, context, enumerated_T=False)


def route_torch_enum(graph: str, source: str, package: str, context: dict) -> dict:
    return _torch_pipeline(graph, source, package, context, enumerated_T=True)


# Mỗi đường trả lời **một** câu hỏi riêng; gộp lại thành bảng chẩn đoán đầy đủ:
#   `o2c_original`  — `onnx2coreml` chặn vì op nào? (graph gốc)
#   `o2c_surgery`   — gỡ op rồi thì `onnx2coreml` còn chặn vì gì? (kỳ vọng: chiều động)
#   `torch_original`— `onnx2torch` chặn vì op nào? (graph gốc)
#   `torch_surgery` — gỡ op rồi thì `torch.jit.trace` có giữ chiều động không?
#   `torch_enum_T`  — nếu trace giữ được, `EnumeratedShapes` cho `T` có dựng được gói không?
ROUTES = {
    "o2c_original": route_o2c,
    "o2c_surgery": route_o2c,
    "torch_original": route_torch,
    "torch_surgery": route_torch,
    "torch_enum_T": route_torch_enum,
}

# Đường dùng graph gốc (chưa phẫu thuật); còn lại dùng graph đã phẫu thuật + đã vá `Clip`.
_ORIGINAL_ROUTES = {"o2c_original", "torch_original"}


def stage_routes(model_dir: str, workdir: str, reports: str, surgery_dir: str) -> dict:
    """Thử mọi đường cho mọi graph. Trả `{graph: {route: {ok, package|error, seconds, trace_shapes}}}`."""
    context = {"config": load_config(model_dir), "model_dir": model_dir, "workdir": workdir}
    result: dict = {}

    for graph in GRAPHS:
        entry: dict = {}
        original = os.path.join(model_dir, graph)
        surgered = os.path.join(surgery_dir, graph.replace(".onnx", ".dynamic.onnx"))
        for route in ROUTES:
            key = f"{graph.replace('.onnx', '')}__{route}"
            package = os.path.join(workdir, f"{key}.mlpackage")
            use_original = route in _ORIGINAL_ROUTES
            source = original if use_original else surgered
            if not os.path.exists(source):
                entry[route] = {"ok": False, "error": "chưa có graph đã phẫu thuật"}
                continue
            try:
                started = time.time()
                extra = ROUTES[route](graph, source, package, context)
                seconds = round(time.time() - started, 1)
                size = sum(os.path.getsize(os.path.join(root, name))
                           for root, _, files in os.walk(package) for name in files)
                entry[route] = {"ok": True, "package": package, "seconds": seconds,
                                "bytes": size, "source": os.path.basename(source), **extra}
                log("ROUTE", f"{graph} [{route}]: OK — {size / 1e6:.1f} MB, {seconds}s")
            except Exception as error:  # noqa: BLE001 — lỗi ở đây là KẾT QUẢ cần ghi
                entry[route] = {"ok": False, "error": f"{type(error).__name__}: {error}",
                                "traceback": traceback.format_exc()[-1200:]}
                log("ROUTE", f"{graph} [{route}]: LỖI {type(error).__name__}: {str(error).splitlines()[0]}")
            probe = entry[route].get("trace_shapes")
            if probe:
                ok = sum(1 for item in probe.values() if item.get("ok"))
                log("ROUTE", f"{graph} [{route}]: trace chạy lại được ở {ok}/{len(probe)} shape")
        result[graph] = entry

    with open(os.path.join(reports, "dynamic.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    return result


# ─────────────────────────── D2b: chứng minh phẫu thuật không đổi số ───────────────────────────
def stage_verify_surgery(model_dir: str, surgery_dir: str, reports: str) -> dict:
    """Chạy ORT trên graph **gốc** và graph **đã phẫu thuật** ở 3 shape rồi so đầu ra.

    Đây là phép kiểm rẻ nhất và mạnh nhất của Phase 0. Nó **tách hẳn** "phẫu thuật `Range` sai" khỏi
    "convert sai": không có nó, một lỗi do phẫu thuật sẽ trông giống hệt một lỗi của `coremltools`, và
    ta sẽ đi sửa nhầm chỗ. Kỳ vọng là **bit-exact** (`max|Δ| = 0`) vì `Slice(arange)[start:limit:delta]`
    tính ra đúng cùng dãy số — khác `0` nghĩa là phẫu thuật sai, không phải sai số dấu chấm động.
    """
    import numpy as np
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.log_severity_level = 4

    config = load_config(model_dir)
    channels = config["latent_dim"] * config["group"]
    vocab_ceiling = max(int(value) for value in config["vocab"].values()) + 1
    style_dim, n_style = config["style_dim"], config["n_style"]
    rng = np.random.default_rng(20261002)
    result: dict = {}

    for graph in GRAPHS:
        surgered = os.path.join(surgery_dir, graph.replace(".onnx", ".dynamic.onnx"))
        if not os.path.exists(surgered):
            result[graph] = {"skipped": "chưa phẫu thuật"}
            continue
        original = os.path.join(model_dir, graph)
        entry: dict = {}
        for shape_name, shape in SHAPES.items():
            length, frames = shape["L"], shape["T"]
            if graph == "text_encoder.onnx":
                feeds = {
                    "ids": rng.integers(0, vocab_ceiling, size=(1, length)).astype(np.int64),
                    "style": rng.standard_normal((1, n_style, style_dim)).astype(np.float32),
                }
            elif graph == "duration_predictor.onnx":
                feeds = {
                    "ctx": rng.standard_normal((1, length, style_dim)).astype(np.float32),
                    "ctx_mask": np.ones((1, length), dtype=np.bool_),
                    "spk": rng.standard_normal((1, 192)).astype(np.float32),
                }
            elif graph == "vector_estimator.onnx":
                feeds = {
                    "x": rng.standard_normal((1, channels, frames)).astype(np.float32),
                    "t": np.asarray([0.5], dtype=np.float32),
                    "ctx": rng.standard_normal((1, length, style_dim)).astype(np.float32),
                    "ctx_mask": np.ones((1, length), dtype=np.bool_),
                    "spk": rng.standard_normal((1, 192)).astype(np.float32),
                    "style": rng.standard_normal((1, n_style, style_dim)).astype(np.float32),
                }
            else:
                feeds = {"x": rng.standard_normal((1, channels, frames)).astype(np.float32)}

            try:
                before = ort.InferenceSession(original, options, providers=["CPUExecutionProvider"]).run(None, feeds)[0]
                after = ort.InferenceSession(surgered, options, providers=["CPUExecutionProvider"]).run(None, feeds)[0]
                if before.shape != after.shape:
                    entry[shape_name] = {"ok": False, "reason": f"shape khác: {before.shape} vs {after.shape}"}
                else:
                    delta = float(np.max(np.abs(before.astype(np.float32) - after.astype(np.float32))))
                    entry[shape_name] = {"ok": delta == 0.0, "max_abs_delta": delta, "shape": list(before.shape)}
            except Exception as error:  # noqa: BLE001
                entry[shape_name] = {"ok": False, "reason": f"{type(error).__name__}: {error}"}
            log("D2b", f"{graph}[{shape_name}]: {entry[shape_name]}")
        result[graph] = entry

    with open(os.path.join(reports, "surgery_parity.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    return result


# ─────────────────────────── Đo ───────────────────────────
def predict_with_mask_variants(model, feeds: dict):
    """Core ML khai `ctx_mask` là FLOAT32 còn ONNX khai bool ⇒ thử lần lượt cho tới khi `predict` chạy.

    Bản sao có chủ ý của `coreml_convert_experiment._predict_any_variant`: ở đây cần **trả cả tên biến
    thể** cho từng graph để báo cáo, không chỉ để chạy được.
    """
    import numpy as np

    base = {name: np.asarray(value) for name, value in feeds.items()}
    variants = [("as-is", base)]
    if "ctx_mask" in feeds:
        variants.append(("mask-int32", {**base, "ctx_mask": np.asarray(feeds["ctx_mask"], dtype=np.int32)}))
        variants.append(("mask-float32", {**base, "ctx_mask": np.asarray(feeds["ctx_mask"], dtype=np.float32)}))
    last_error = None
    for name, candidate in variants:
        try:
            model.predict(candidate)
            return name, candidate
        except Exception as error:  # noqa: BLE001 — thử tiếp biến thể kế
            last_error = error
    raise RuntimeError(f"mọi cách ép kiểu đều lỗi: {last_error}")


def snr_db(reference, candidate) -> float:
    import numpy as np

    a = np.asarray(reference, dtype=np.float32).reshape(-1)
    b = np.asarray(candidate, dtype=np.float32).reshape(-1)
    n = min(a.size, b.size)
    if n == 0:
        return float("nan")
    diff = a[:n] - b[:n]
    rms = float(np.sqrt(np.mean(a[:n] ** 2)))
    return round(20 * float(np.log10(rms / max(float(np.std(diff)), 1e-12))), 1)


def ort_session(model_dir: str, graph: str):
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    return ort.InferenceSession(os.path.join(model_dir, graph), options, providers=["CPUExecutionProvider"])


def bench_graph(model_dir: str, workdir: str, graph: str, package: str, label: str,
                shapes: dict | None = None) -> dict:
    """Độ trễ + SNR ở các shape, cho `ALL` và `CPU_ONLY`; kèm thời gian `MLModel` biên dịch.

    `shapes` mặc định là `SHAPES` (3 shape đại diện) — đúng cho gói **shape động**. Gói **đã đóng băng**
    thì **phải** truyền đúng shape của nó: model tĩnh chỉ chạy ở đúng shape đã chốt, nên đo bằng shape
    khác sẽ ra `predict` lỗi và trông như Core ML hỏng trong khi thật ra là đo sai.
    """
    import coremltools as ct
    import numpy as np

    session = ort_session(model_dir, graph)
    result: dict = {"shapes": {}}

    for shape_name, shape in (shapes or SHAPES).items():
        feeds = feeds_for(graph, make_feeds(model_dir, workdir, shape["L"], shape["T"]))
        session.run(None, feeds)
        timings = []
        reference = None
        for _ in range(5):
            started = time.perf_counter()
            reference = session.run(None, feeds)[0]
            timings.append((time.perf_counter() - started) * 1000)
        ort_ms = float(np.median(timings))

        entry = {"ort_ms": round(ort_ms, 1), "L": shape["L"], "T": shape["T"]}
        for unit_name, unit in (("all", ct.ComputeUnit.ALL), ("cpuOnly", ct.ComputeUnit.CPU_ONLY)):
            try:
                # `MLModel(...)` chính là bước biên dịch `.mlpackage` → `.mlmodelc`; đo riêng vì trên máy
                # thật đây là chi phí một lần mà người dùng phải chờ.
                started = time.perf_counter()
                model = ct.models.MLModel(package, compute_units=unit)
                compile_seconds = round(time.perf_counter() - started, 1)

                variant, inputs = predict_with_mask_variants(model, feeds)
                timings = []
                output = None
                for _ in range(5):
                    started = time.perf_counter()
                    output = list(model.predict(inputs).values())[0]
                    timings.append((time.perf_counter() - started) * 1000)
                coreml_ms = float(np.median(timings))
                entry[unit_name] = {
                    "coreml_ms": round(coreml_ms, 1),
                    "speed_ratio": round(ort_ms / coreml_ms, 2),
                    "snr_db": snr_db(reference, output),
                    "input_variant": variant,
                    "compile_seconds": compile_seconds,
                }
                log("BENCH", f"{label}[{shape_name}/{unit_name}]: ORT {ort_ms:.1f} → CoreML {coreml_ms:.1f} ms "
                             f"({ort_ms / coreml_ms:.2f}×) · SNR {entry[unit_name]['snr_db']} dB "
                             f"· compile {compile_seconds}s")
            except Exception as error:  # noqa: BLE001
                entry[unit_name] = {"error": f"{type(error).__name__}: {error}"}
                log("BENCH", f"{label}[{shape_name}/{unit_name}]: LỖI {type(error).__name__}: "
                             f"{str(error).splitlines()[0]}")
        result["shapes"][shape_name] = entry
    return result


def stage_bench(model_dir: str, workdir: str, routes: dict, reports: str) -> dict:
    """Đo **đường đầu tiên chạy được** của từng graph (ưu tiên shape động thuần)."""
    priority = ["torch_surgery", "torch_enum_T", "o2c_surgery", "o2c_original"]
    result: dict = {}
    for graph in GRAPHS:
        entry = routes.get(graph, {})
        chosen = next((route for route in priority if entry.get(route, {}).get("ok")), None)
        result[graph] = {"chosen_route": chosen}
        if chosen is None:
            log("BENCH", f"{graph}: không đường nào chạy được ⇒ bỏ qua đo")
            continue
        try:
            result[graph].update(bench_graph(model_dir, workdir, graph, entry[chosen]["package"],
                                             f"{graph.replace('.onnx', '')}[{chosen}]"))
        except Exception as error:  # noqa: BLE001
            result[graph]["error"] = f"{type(error).__name__}: {error}"
            log("BENCH", f"{graph}: LỖI {type(error).__name__}: {error}")
    with open(os.path.join(reports, "dynamic_bench.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    return result


# ─────────────────────────── Golden ───────────────────────────
def stage_golden(model_dir: str, workdir: str, routes: dict, reports: str) -> dict:
    """Sinh `golden.npz` — **đầu vào cố định + đầu ra tham chiếu của cả 4 graph**.

    Vì sao không phải một file WAV: để có WAV phải dựng lại **cả** vòng Euler + bộ phonemizer trong
    Python, mà hai thứ đó không hề đổi ở lượt này. Cho `ids` thật chạy thẳng qua 4 graph thì:
      · chạm **cả 4** graph đã chuyển (kể cả `text_encoder`/`duration_predictor`),
      · tất định (mọi tensor đều cố định, `latent` theo seed),
      · bắt đúng 3 kiểu hỏng đã gặp: **im lặng**, **NaN**, **nhiễu**.
    Không kiểm được: bộ phonemizer (`sea_g2p.bin`, không đổi) và chất lượng tiếng Việt (phải nghe trên máy).
    """
    import numpy as np

    chosen = {}
    for graph in GRAPHS:
        entry = routes.get(graph, {})
        route = next((name for name in ["torch_surgery", "torch_enum_T", "o2c_surgery", "o2c_original"]
                      if entry.get(name, {}).get("ok")), None)
        if route is None:
            log("GOLDEN", f"{graph}: chưa convert được ⇒ bỏ qua golden")
            return {"ok": False, "reason": f"{graph} chưa convert được"}
        chosen[graph] = entry[route]["package"]

    # Lấy `config` thẳng, **không** qua `make_feeds(…, 0, 0)`: từ khi có `_fit_ids`, truyền `length = 0`
    # sẽ cắt `ids` về 0 phần tử ⇒ `text_encoder` chết với `Invalid input shape: {0}`.
    config = load_config(model_dir)
    # `L` lấy đúng độ dài phoneme thật (không đệm) — đây cũng là phép thử `RangeDim` ở một giá trị
    # KHÔNG trùng shape nào đã dùng khi convert.
    length = int(real_ids(config).shape[1])
    frames = 96
    latent_channels = config["latent_dim"] * config["group"]
    feeds = make_feeds(model_dir, workdir, length, frames)
    feeds["x"] = np.random.default_rng(1234).standard_normal((1, latent_channels, frames)).astype(np.float32)

    reference: dict = {}
    reference["ctx"] = ort_session(model_dir, "text_encoder.onnx").run(
        None, {"ids": feeds["ids"], "style": feeds["style"]})[0]
    reference["log_s"] = ort_session(model_dir, "duration_predictor.onnx").run(
        None, {"ctx": reference["ctx"], "ctx_mask": feeds["ctx_mask"], "spk": feeds["spk"]})[0]
    reference["velocity"] = ort_session(model_dir, "vector_estimator.onnx").run(
        None, {"x": feeds["x"], "t": feeds["t"], "ctx": reference["ctx"], "ctx_mask": feeds["ctx_mask"],
               "spk": feeds["spk"], "style": feeds["style"]})[0]
    reference["pcm"] = ort_session(model_dir, "codec_decoder.onnx").run(None, {"x": feeds["x"]})[0]

    import coremltools as ct

    actual: dict = {}
    try:
        encoder = ct.models.MLModel(chosen["text_encoder.onnx"], compute_units=ct.ComputeUnit.ALL)
        actual["ctx"] = list(encoder.predict({"ids": feeds["ids"], "style": feeds["style"]}).values())[0]

        duration = ct.models.MLModel(chosen["duration_predictor.onnx"], compute_units=ct.ComputeUnit.ALL)
        _, inputs = predict_with_mask_variants(duration, {"ctx": reference["ctx"],
                                                          "ctx_mask": feeds["ctx_mask"],
                                                          "spk": feeds["spk"]})
        actual["log_s"] = list(duration.predict(inputs).values())[0]

        vector = ct.models.MLModel(chosen["vector_estimator.onnx"], compute_units=ct.ComputeUnit.ALL)
        _, inputs = predict_with_mask_variants(vector, {"x": feeds["x"], "t": feeds["t"],
                                                        "ctx": reference["ctx"],
                                                        "ctx_mask": feeds["ctx_mask"],
                                                        "spk": feeds["spk"], "style": feeds["style"]})
        actual["velocity"] = list(vector.predict(inputs).values())[0]

        decoder = ct.models.MLModel(chosen["codec_decoder.onnx"], compute_units=ct.ComputeUnit.ALL)
        actual["pcm"] = list(decoder.predict({"x": feeds["x"]}).values())[0]
    except Exception as error:  # noqa: BLE001
        log("GOLDEN", f"chạy Core ML lỗi: {type(error).__name__}: {error}")
        return {"ok": False, "reason": f"{type(error).__name__}: {error}"}

    snr = {name: snr_db(reference[name], actual[name]) for name in reference}
    for name, value in snr.items():
        log("GOLDEN", f"{name}: SNR {value} dB")

    golden_dir = os.path.join(reports, "golden")
    os.makedirs(golden_dir, exist_ok=True)
    npz_path = os.path.join(golden_dir, "golden.npz")
    np.savez(
        npz_path,
        ids=feeds["ids"], style=feeds["style"], spk=feeds["spk"], latent=feeds["x"], time=feeds["t"],
        ctx=np.asarray(reference["ctx"], dtype=np.float32),
        log_s=np.asarray(reference["log_s"], dtype=np.float32),
        velocity=np.asarray(reference["velocity"], dtype=np.float32),
        pcm=np.asarray(reference["pcm"], dtype=np.float32),
    )
    meta = {
        "ok": True,
        "revision": REVISION,
        "sample_rate": config["sample_rate"],
        "length": length,
        "frames": frames,
        "latent_channels": latent_channels,
        "snr_db": snr,
        "bytes": os.path.getsize(npz_path),
        "npz": npz_path,
    }
    with open(os.path.join(golden_dir, "golden.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, ensure_ascii=False, indent=2)
    log("GOLDEN", f"golden.npz {meta['bytes'] / 1e3:.0f} KB ở {npz_path}")
    return meta


# ─────────────────────────── Dự phòng: bucket ───────────────────────────
def stage_bucket_fallback(model_dir: str, workdir: str, reports: str) -> dict:
    """Số đo phương án **bucket** — chỉ để có dữ liệu quyết định nếu shape động thất bại.

    `L` đóng băng 200 và `T` chia 3 mức. Chỉ 2 graph nặng (`vector_estimator`, `codec_decoder`) vì
    `text_encoder`/`duration_predictor` cộng lại chưa tới 1,5 % thời gian.
    """
    import onnx2coreml as o2c

    config = load_config(model_dir)
    channels = config["latent_dim"] * config["group"]
    result: dict = {"buckets": {}, "total_bytes": 0}
    for graph in FALLBACK_GRAPHS:
        entry: dict = {}
        for bucket_name, shape in FALLBACK_BUCKETS.items():
            key = f"{graph.replace('.onnx', '')}__bucket_{bucket_name}"
            try:
                if graph.startswith("vector_estimator"):
                    shapes = {
                        "x": [1, channels, shape["T"]], "t": [1],
                        "ctx": [1, shape["L"], config["style_dim"]], "ctx_mask": [1, shape["L"]],
                        "spk": [1, 192], "style": [1, config["n_style"], config["style_dim"]],
                    }
                else:
                    shapes = {"x": [1, channels, shape["T"]]}
                frozen = os.path.join(workdir, f"{key}.onnx")
                freeze_shapes(os.path.join(model_dir, graph), frozen, shapes)
                optimized = os.path.join(workdir, f"{key}.opt.onnx")
                candidates = []
                if optimize_with_ort(frozen, optimized):
                    fold_range(optimized, optimized)
                    candidates.append(optimized)
                candidates.append(frozen)

                package = os.path.join(workdir, f"{key}.mlpackage")
                last_error = None
                for candidate in candidates:
                    try:
                        o2c.convert(candidate, format="mlpackage", minimum_deployment_target="iOS17").save(package)
                        last_error = None
                        break
                    except Exception as error:  # noqa: BLE001 — thử ứng viên kế
                        last_error = error
                if last_error is not None:
                    raise last_error

                size = sum(os.path.getsize(os.path.join(root, name))
                           for root, _, files in os.walk(package) for name in files)
                bench = bench_graph(model_dir, workdir, graph, package, key, {bucket_name: shape})
                entry[bucket_name] = {"shape": shape, "bytes": size, "bench": bench}
                result["total_bytes"] += size
                log("BUCKET", f"{key}: {size / 1e6:.1f} MB")
            except Exception as error:  # noqa: BLE001
                entry[bucket_name] = {"error": f"{type(error).__name__}: {error}"}
                log("BUCKET", f"{key}: LỖI {type(error).__name__}: {error}")
        result["buckets"][graph] = entry
    log("BUCKET", f"tổng dung lượng 3 mức × 2 graph = {result['total_bytes'] / 1e6:.1f} MB")
    with open(os.path.join(reports, "bucket_fallback.json"), "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)
    return result


# ─────────────────────────── main ───────────────────────────
def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="reports-dynamic")
    parser.add_argument("--workdir", default="coreml-dynamic")
    parser.add_argument("--skip-bucket", action="store_true", help="bỏ phần đo bucket dự phòng")
    parser.add_argument("--skip-bench", action="store_true", help="bỏ phần đo độ trễ")
    args = parser.parse_args()

    reports = os.path.abspath(args.out)
    workdir = os.path.abspath(args.workdir)
    os.makedirs(reports, exist_ok=True)
    os.makedirs(workdir, exist_ok=True)

    summary: dict = {"machine": machine_info(), "revision": REVISION}
    log("D0", f"máy: {summary['machine']}")

    try:
        model_dir = stage_download(workdir)
    except Exception as error:  # noqa: BLE001
        summary["download_error"] = f"{type(error).__name__}: {error}"
        log("D0", f"LỖI tải model: {error}")
        with open(os.path.join(reports, "summary.json"), "w", encoding="utf-8") as handle:
            json.dump(summary, handle, ensure_ascii=False, indent=2)
        return 1

    # D1 — điều tra `Range`: trả lời được "phụ thuộc chiều nào" là điều kiện để tin mọi bước sau.
    surgery_dir = os.path.join(workdir, "surgery")
    os.makedirs(surgery_dir, exist_ok=True)
    try:
        from coreml_shape_surgery import investigate

        summary["range_report"] = {}
        for graph in GRAPHS:
            ranges = investigate(os.path.join(model_dir, graph))
            summary["range_report"][graph] = {
                "range_count": len(ranges),
                "untraced": [item["node"] for item in ranges if item["limit_traced"] is None],
                "ranges": ranges,
            }
            log("D1", f"{graph}: {len(ranges)} Range")
        with open(os.path.join(reports, "range_report.json"), "w", encoding="utf-8") as handle:
            json.dump(summary["range_report"], handle, ensure_ascii=False, indent=2)
    except Exception as error:  # noqa: BLE001
        summary["range_error"] = f"{type(error).__name__}: {error}"
        log("D1", f"LỖI điều tra: {error}")

    # D2 — phẫu thuật.
    try:
        summary["surgery"] = {}
        for graph in GRAPHS:
            target = os.path.join(surgery_dir, graph.replace(".onnx", ".dynamic.onnx"))
            try:
                summary["surgery"][graph] = surgery_apply(os.path.join(model_dir, graph), target)
            except Exception as error:  # noqa: BLE001
                summary["surgery"][graph] = {"error": f"{type(error).__name__}: {error}"}
                log("D2", f"{graph}: LỖI {type(error).__name__}: {error}")
    except Exception as error:  # noqa: BLE001
        summary["surgery_error"] = f"{type(error).__name__}: {error}"
        log("D2", f"LỖI: {error}")

    # D2b — chứng minh phẫu thuật không đổi số (tách "phẫu thuật sai" khỏi "convert sai").
    try:
        summary["surgery_parity"] = stage_verify_surgery(model_dir, surgery_dir, reports)
    except Exception as error:  # noqa: BLE001
        summary["surgery_parity_error"] = f"{type(error).__name__}: {error}"
        log("D2b", f"LỖI: {error}")

    # D3 — bốn đường convert.
    try:
        routes = stage_routes(model_dir, workdir, reports, surgery_dir)
        summary["routes"] = {
            graph: {route: {key: value for key, value in info.items() if key != "traceback"}
                    for route, info in entry.items()}
            for graph, entry in routes.items()
        }
    except Exception as error:  # noqa: BLE001
        routes = {}
        summary["routes_error"] = f"{type(error).__name__}: {error}"
        log("D3", f"LỖI: {error}")

    # D4 — đo độ trễ ở 3 shape.
    if not args.skip_bench and routes:
        try:
            summary["bench"] = stage_bench(model_dir, workdir, routes, reports)
        except Exception as error:  # noqa: BLE001
            summary["bench_error"] = f"{type(error).__name__}: {error}"
            log("D4", f"LỖI: {error}")

    # D5 — golden.
    if routes:
        try:
            summary["golden"] = stage_golden(model_dir, workdir, routes, reports)
        except Exception as error:  # noqa: BLE001
            summary["golden"] = {"ok": False, "reason": f"{type(error).__name__}: {error}"}
            log("D5", f"LỖI: {error}")

    # D6 — dữ liệu dự phòng.
    if not args.skip_bucket:
        try:
            summary["bucket_fallback"] = stage_bucket_fallback(model_dir, workdir, reports)
        except Exception as error:  # noqa: BLE001
            summary["bucket_error"] = f"{type(error).__name__}: {error}"
            log("D6", f"LỖI: {error}")

    # Kết luận chỉ tính đường **shape động** (`torch_*`). `o2c_original`/`o2c_surgery` chạy được cũng
    # KHÔNG tính: chúng chỉ sống khi shape đã đóng băng, mà shape động chính là thứ plan cần.
    #
    # ⚠️ **Và "convert được" KHÔNG đủ.** `ct.convert` vẫn dựng ra `.mlpackage` có `RangeDim` từ một graph
    # đã bị `torch.jit.trace` nướng shape — gói đó **compile được** nhưng cho kết quả **sai/im lặng** ở
    # shape khác. Đó đúng là loại lỗi tệ nhất trong engine này. Nên điều kiện bắt buộc là graph **đã trace**
    # phải chạy lại đúng ở **cả 3** shape (`trace_shapes` toàn `ok`).
    dynamic_routes = ("torch_surgery", "torch_enum_T")
    summary["dynamic_routes"] = list(dynamic_routes)

    def _truly_dynamic(graph: str, route: str) -> bool:
        info = routes.get(graph, {}).get(route) or {}
        if not info.get("ok"):
            return False
        probe = info.get("trace_shapes") or {}
        return bool(probe) and all(item.get("ok") for item in probe.values())

    summary["verdict"] = "PASS" if routes and all(
        any(_truly_dynamic(graph, route) for route in dynamic_routes) for graph in GRAPHS) else "FAIL"
    if summary["verdict"] == "FAIL":
        summary["verdict_reason"] = (
            "Không graph nào có đường shape động chạy lại được ở cả 3 shape. `.mlpackage` vẫn được sinh ra "
            "(xem `routes`) nhưng graph bên trong đã bị `torch.jit.trace` nướng shape ⇒ không dùng được."
        )
    # Phép thử quyết định: graph **đã trace** phải chạy lại được ở **cả 3** shape.
    summary["trace_ok"] = {
        graph: {route: sum(1 for item in (routes.get(graph, {}).get(route, {}).get("trace_shapes") or {}).values()
                           if item.get("ok"))
                for route in dynamic_routes}
        for graph in GRAPHS
    }
    summary["package_bytes"] = {
        graph: {route: (routes.get(graph, {}).get(route) or {}).get("bytes")
                for route in dynamic_routes}
        for graph in GRAPHS
    }

    with open(os.path.join(reports, "summary.json"), "w", encoding="utf-8") as handle:
        json.dump(summary, handle, ensure_ascii=False, indent=2)
    log("XONG", f"KẾT LUẬN: {summary['verdict']} — báo cáo ở {reports}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
