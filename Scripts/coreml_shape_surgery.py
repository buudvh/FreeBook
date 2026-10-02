"""Phẫu thuật op `Range` của graph **VieNeu-TTS v3 Nano** cho Core ML.

## Vì sao cần

`Range(start, limit, delta)` **không có lowering trong Core ML**. Lượt thí nghiệm trước
(`coreml_convert_experiment.py`) né nó bằng cách **đóng băng shape** rồi để ORT gấp hằng số — nhưng chốt
shape nghĩa là **mất tính shape động**, mà shape động chính là thứ cho phép **một** gói `.mlpackage` phủ
mọi câu, thay vì 127,8 MB cho **mỗi** mức bucket (trọng số chiếm gần hết gói, không phải activation).

Script này làm hai việc, tách hẳn khỏi phần convert:

- `investigate()` — truy vết từng node `Range` ngược lên `Shape(...)` để trả lời **nó phụ thuộc chiều
  nào** (`x`/`ctx`/`ctx_mask`, dim nào) kèm hệ số nhân/cộng. Đây là câu hỏi phải trả lời **trước** khi
  tin bất cứ điều gì về shape động.
- `apply()` — thay `Range(start, limit, delta)` bằng
  `Slice(arange(0, MAX), starts=[start], ends=[limit], axes=[0], steps=[delta])`.

## Vì sao phép thay thế này tương đương

`arange(0, MAX)[start:limit:delta]` cho đúng `[start, start+delta, …] < limit` — cùng ngữ nghĩa với
`Range(start, limit, delta)`. Điều quan trọng: `limit` **vẫn là tensor suy từ `Shape`**, không bị đóng
băng ⇒ chiều động được giữ nguyên.

## ⚠️ Vượt `MAX` thì cắt cụt **im lặng**

`Slice` không báo lỗi khi `limit > MAX`; nó chỉ trả về `MAX - start` phần tử thay vì `limit - start`.
Đó là loại lỗi tệ nhất trong engine này: sai số âm thầm, không có exception. Vì vậy `apply()` **assert
mọi `Range` đều truy vết được** và **raise** khi không truy được — cố ý dừng thay vì đoán.

Chạy:
    python Scripts/coreml_shape_surgery.py --model <dir> --out reports/range_report.json
    python Scripts/coreml_shape_surgery.py --model <dir> --apply --outdir <dir>
"""
from __future__ import annotations

import argparse
import json
import os
from typing import Any

# Trần chiều, khớp `VieNeuConfig.swift`: `maxChunkCharacters = 140` (⇒ phoneme ≲ 512) và
# `maxChunkSeconds = 15,0` × `flowFPS = 15,625` (⇒ frame ≤ 234). Đặt dư một chút; đây là **trần của
# hằng số `arange`**, không phải shape của model.
MAX_BY_DIM = {
    ("x", 2): 256,          # x        = [1, latent_channels, T]
    ("ctx", 1): 512,        # ctx      = [1, L, style_dim]
    ("ctx_mask", 1): 512,   # ctx_mask = [1, L]
}
DEFAULT_MAX = 512

# Op đi xuyên qua được mà không đổi giá trị (chỉ đổi kiểu/rank).
_TRANSPARENT_OPS = {"Cast", "Squeeze", "Unsqueeze", "Reshape", "Identity", "Flatten"}
_TRACE_DEPTH_LIMIT = 12


def log(stage: str, message: str) -> None:
    print(f"[{stage}] {message}", flush=True)


# ─────────────────────────── Truy vết ───────────────────────────
def build_producer(graph) -> dict:
    """Tên output → node sinh ra nó."""
    producer: dict[str, Any] = {}
    for node in graph.node:
        for output in node.output:
            producer[output] = node
    return producer


def collect_constants(graph) -> dict:
    """Tên → numpy array của mọi hằng số (initializer + node `Constant`)."""
    from onnx import numpy_helper

    values: dict[str, Any] = {}
    for initializer in graph.initializer:
        values[initializer.name] = numpy_helper.to_array(initializer)
    for node in graph.node:
        if node.op_type == "Constant":
            for attribute in node.attribute:
                if attribute.name == "value":
                    values[node.output[0]] = numpy_helper.to_array(attribute.t)
    return values


def _scalar(values: dict, name: str):
    """`float` nếu `name` là hằng đúng 1 phần tử, ngược lại `None` (kể cả khi không phải hằng)."""
    array = values.get(name)
    if array is None or array.size != 1:
        return None
    return float(array.reshape(-1)[0])


def trace_limit(limit_name: str, producer: dict, values: dict, graph_inputs: set, depth: int = 0):
    """Truy `limit` ngược lên `Shape(<input>)[dim]`.

    Trả `{"tensor", "dim", "scale", "offset"}` hoặc `None` khi không truy được. `None` là câu trả lời
    hợp lệ và **phải** được tôn trọng — caller không được đoán thay.
    """
    if depth > _TRACE_DEPTH_LIMIT:
        return None
    node = producer.get(limit_name)
    if node is None:
        return None
    op = node.op_type

    if op == "Gather":
        indices = values.get(node.input[1])
        source = producer.get(node.input[0])
        if (indices is not None and indices.size == 1
                and source is not None and source.op_type == "Shape"):
            tensor = source.input[0]
            return {
                "tensor": tensor,
                "dim": int(indices.reshape(-1)[0]),
                "scale": 1.0,
                "offset": 0.0,
                "is_graph_input": tensor in graph_inputs,
            }
        return None

    if op in _TRANSPARENT_OPS:
        return trace_limit(node.input[0], producer, values, graph_inputs, depth + 1)

    if op in {"Add", "Sub"}:
        left = trace_limit(node.input[0], producer, values, graph_inputs, depth + 1)
        right_constant = _scalar(values, node.input[1])
        if left is not None and right_constant is not None:
            result = dict(left)
            result["offset"] += right_constant if op == "Add" else -right_constant
            return result
        right = trace_limit(node.input[1], producer, values, graph_inputs, depth + 1)
        left_constant = _scalar(values, node.input[0])
        if right is not None and left_constant is not None and op == "Add":
            result = dict(right)
            result["offset"] += left_constant
            return result
        return None

    if op in {"Mul", "Div"}:
        left = trace_limit(node.input[0], producer, values, graph_inputs, depth + 1)
        right_constant = _scalar(values, node.input[1])
        if left is not None and right_constant not in (None, 0.0):
            result = dict(left)
            result["scale"] *= right_constant if op == "Mul" else 1.0 / right_constant
            return result
        return None

    return None


def max_for(traced: dict, overrides: dict | None = None) -> int:
    table = dict(MAX_BY_DIM)
    table.update(overrides or {})
    return int(table.get((traced["tensor"], traced["dim"]), DEFAULT_MAX))


def investigate(model_path: str, overrides: dict | None = None) -> list:
    """Bảng mọi node `Range`: hằng số nào, `limit` phụ thuộc chiều nào, cần `MAX` bao nhiêu."""
    import onnx

    model = onnx.load(model_path)
    graph = model.graph
    producer = build_producer(graph)
    values = collect_constants(graph)
    graph_inputs = {item.name for item in graph.input}

    report = []
    for node in graph.node:
        if node.op_type != "Range":
            continue
        traced = trace_limit(node.input[1], producer, values, graph_inputs)
        entry = {
            "node": node.name or node.output[0],
            "output": node.output[0],
            "start": _scalar(values, node.input[0]),
            "delta": _scalar(values, node.input[2]),
            "limit_value_name": node.input[1],
            "limit_traced": traced,
            "limit_source": ("UNKNOWN" if traced is None else
                             f"{traced['tensor']}[{traced['dim']}] × {traced['scale']} + {traced['offset']}"),
            "max_needed": None if traced is None else int(
                traced["scale"] * max_for(traced, overrides) + traced["offset"]),
        }
        report.append(entry)
    return report


# ─────────────────────────── Phẫu thuật ───────────────────────────
def _vector_input(node_input: str, values: dict, sink_nodes: list, sink_inits: list, tag: str, np):
    """Trả tên một tensor **1 chiều** biểu diễn `node_input` — `Slice` đòi `starts/ends/steps` là vector.

    Hằng 1 phần tử ⇒ dựng initializer `[v]` luôn (rẻ hơn một node `Reshape`).
    """
    from onnx import TensorProto, helper, numpy_helper

    constant = _scalar(values, node_input)
    if constant is not None:
        name = f"{tag}__const"
        sink_inits.append(numpy_helper.from_array(np.asarray([constant], dtype=np.int64), name=name))
        return name

    shape_name = f"{tag}__shape"
    sink_inits.append(numpy_helper.from_array(np.asarray([1], dtype=np.int64), name=shape_name))
    out_name = f"{tag}__vec"
    sink_nodes.append(helper.make_node("Reshape", [node_input, shape_name], [out_name], name=f"{tag}__reshape"))
    return out_name


def apply(src: str, dst: str, overrides: dict | None = None) -> dict:
    """Thay mọi `Range` bằng `Slice` của một hằng `arange`. Raise nếu có `Range` không truy vết được."""
    import numpy as np
    import onnx
    from onnx import helper, numpy_helper

    model = onnx.load(src)
    graph = model.graph
    producer = build_producer(graph)
    values = collect_constants(graph)
    graph_inputs = {item.name for item in graph.input}

    new_nodes = []
    new_initializers = []
    replaced = []

    for node in graph.node:
        if node.op_type != "Range":
            new_nodes.append(node)
            continue

        traced = trace_limit(node.input[1], producer, values, graph_inputs)
        if traced is None:
            raise ValueError(
                f"`Range` {node.name or node.output[0]}: không truy vết được `limit` "
                f"({node.input[1]}) ⇒ không suy ra được `MAX`. Dừng ở đây thay vì đoán — `MAX` quá nhỏ "
                "làm `Slice` cắt cụt IM LẶNG."
            )

        max_needed = int(traced["scale"] * max_for(traced, overrides) + traced["offset"])
        tag = f"{node.output[0]}__surgery"
        arange_name = f"{tag}__arange"
        new_initializers.append(numpy_helper.from_array(
            np.arange(0, max_needed, 1, dtype=np.int64), name=arange_name))

        starts = _vector_input(node.input[0], values, new_nodes, new_initializers, f"{tag}__starts", np)
        ends = _vector_input(node.input[1], values, new_nodes, new_initializers, f"{tag}__ends", np)
        steps = _vector_input(node.input[2], values, new_nodes, new_initializers, f"{tag}__steps", np)

        axes_name = f"{tag}__axes"
        new_initializers.append(numpy_helper.from_array(np.asarray([0], dtype=np.int64), name=axes_name))

        new_nodes.append(helper.make_node(
            "Slice",
            [arange_name, starts, ends, axes_name, steps],
            [node.output[0]],
            name=f"{tag}__slice",
        ))
        replaced.append({
            "node": node.name or node.output[0],
            "limit_source": f"{traced['tensor']}[{traced['dim']}]",
            "arange_length": max_needed,
        })
        log("SURGERY", f"{node.name or node.output[0]}: Range → Slice(arange({max_needed})) "
                       f"[{traced['tensor']}[{traced['dim']}]]")

    del graph.node[:]
    graph.node.extend(new_nodes)
    graph.initializer.extend(new_initializers)

    # `value_info` cũ mô tả shape đã chốt của lượt trước ⇒ bỏ rồi suy lại. Suy lỗi thì vẫn ghi file:
    # `value_info` không bắt buộc, và mất nó chỉ làm mất thông tin chẩn đoán.
    del graph.value_info[:]
    try:
        model = onnx.shape_inference.infer_shapes(model)
    except Exception as error:  # noqa: BLE001 — suy shape là tiện ích, không phải điều kiện
        log("SURGERY", f"infer_shapes lỗi (bỏ qua): {type(error).__name__}: {error}")

    onnx.save(model, dst)
    return {"file": os.path.basename(dst), "replaced": replaced}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True, help="thư mục chứa 4 graph .onnx")
    parser.add_argument("--out", default="range_report.json")
    parser.add_argument("--apply", action="store_true", help="ghi graph đã phẫu thuật")
    parser.add_argument("--outdir", default="surgery")
    parser.add_argument("--only", default="", help="chỉ xử lý graph này (mặc định: cả 4)")
    parser.add_argument("--max", action="append", default=[],
                        help="ghi đè trần, dạng <tensor>.<dim>=<value> (vd ctx.1=512)")
    args = parser.parse_args()

    overrides: dict = {}
    for item in args.max:
        key, _, value = item.partition("=")
        tensor, _, dim = key.rpartition(".")
        overrides[(tensor, int(dim))] = int(value)

    names = ["text_encoder.onnx", "duration_predictor.onnx", "vector_estimator.onnx", "codec_decoder.onnx"]
    if args.only:
        names = [name for name in names if name.startswith(args.only)]

    report: dict = {}
    for name in names:
        path = os.path.join(args.model, name)
        if not os.path.exists(path):
            report[name] = {"error": "không có file"}
            continue
        entry: dict = {"ranges": investigate(path, overrides)}
        entry["range_count"] = len(entry["ranges"])
        entry["untraced"] = [item["node"] for item in entry["ranges"] if item["limit_traced"] is None]
        log("INVESTIGATE", f"{name}: {entry['range_count']} node Range, "
                           f"{len(entry['untraced'])} không truy vết được")
        for item in entry["ranges"]:
            log("INVESTIGATE", f"  {item['node']}: limit = {item['limit_source']} "
                               f"start={item['start']} delta={item['delta']} max={item['max_needed']}")
        if args.apply:
            os.makedirs(args.outdir, exist_ok=True)
            target = os.path.join(args.outdir, name.replace(".onnx", ".dynamic.onnx"))
            try:
                entry["surgery"] = apply(path, target, overrides)
            except Exception as error:  # noqa: BLE001 — lỗi ở đây là KẾT QUẢ cần ghi
                entry["surgery"] = {"error": f"{type(error).__name__}: {error}"}
                log("SURGERY", f"{name}: LỖI {type(error).__name__}: {error}")
        report[name] = entry

    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
    log("XONG", f"báo cáo ở {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
