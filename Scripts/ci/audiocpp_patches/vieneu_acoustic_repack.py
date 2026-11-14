#!/usr/bin/env python3
"""Đưa trọng số q8_0 của bộ giải mã âm học VieNeu Turbo vào bộ đệm `CPU_REPACK` của ggml (thử, báo cáo tối ưu Turbo §16).

Vì sao: mỗi khung 80 ms bộ giải mã âm học (1 lớp: qkv 768→2304, o 768², MLP 2048) chạy 16 bước tuần tự, mỗi bước là
phép nhân ma trận × vectơ trên ~7,5 MB trọng số q8_0. ggml có sẵn bố cục xen kẽ `q8_0_4x4` (4 hàng xen theo khối 4 byte,
kernel NEON dotprod — đúng cờ `armv8.2-a+dotprod` của bản iOS) cho phép nhân này, như llama.cpp đặt trọng số; audio.cpp
chỉ bật nó cho lfm2_audio (`WeightStores`, `cpu_repack`).

Cách làm (session option `vieneu_v3_turbo.acoustic_repack`, mặc định tắt = y như upstream):
- `load_talker_weights` nhận cờ; bật + backend CPU + kiểu lưu `Native` ⇒ tìm bộ đệm phụ tên `CPU_REPACK` trong
  `core::cpu_extra_buffer_types`, dựng thêm một `BackendWeightStore` trên bộ đệm đó, và 5 ma trận của mỗi lớp âm học
  (`acoustic_decoder.layers.N.{attn.qkv, attn.o_proj, ff_gate, ff_up, ff_down}`) nạp vào đó khi
  `core::buffer_type_supports_matmul_weight` nhận (q8_0, số hàng chia hết 4). Head F16 (`audio_embeddings.N`),
  `codec_head` và toàn bộ backbone giữ chỗ cũ — backbone còn phải đi Accelerate ở bước nạp prompt (ggml-blas chỉ đọc
  bộ đệm host thường).
- Trọng số chỉ chuyển chỗ, không nhân đôi ⇒ RAM không đổi.
- Graph nạp 2 vị trí + 16 graph từng bước của bộ giải mã âm học được kiểm bằng
  `core::validate_backend_graph_with_cpu_extra_buffers` (trọng số repack chỉ được làm src0 của `mul_mat` 2D với đầu vào
  F32 liền) — dùng sai ⇒ ném lỗi lúc dựng session thay vì ra tiếng sai.
- Phép tính: cùng lượng tử activation q8_0, chỉ khác thứ tự cộng fp32 giữa các khối ⇒ không trùng từng byte với đường cũ.
- Log: `vieneu_v3_turbo.talker.acoustic_repack.weights` (số ma trận đã repack) lúc nạp và mỗi lượt nạp prompt.

Sửa bằng mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 vieneu_acoustic_repack.py <thư mục nguồn audio.cpp>   (sau vieneu_threadpool.py)
"""
import pathlib
import sys

MARK = "FREEBOOK_PATCH_ACOUSTIC_REPACK"
TALKER_HEADER = "include/engine/community_models/vieneu_v3_turbo/talker.h"
TALKER = "src/community_models/vieneu_v3_turbo/talker.cpp"
SESSION = "src/community_models/vieneu_v3_turbo/session.cpp"
OPTION = "vieneu_v3_turbo.acoustic_repack"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[vieneu_acoustic_repack] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp / bản vá trước đã đổi")
    return text.replace(old, new, 1)


def patch_talker_header(text: str) -> str:
    return replace_once(
        text,
        "        bool prefill_blas = false) const;  // FREEBOOK_PATCH_PREFILL_BLAS\n",
        "        bool prefill_blas = false,  // FREEBOOK_PATCH_PREFILL_BLAS\n"
        "        bool acoustic_repack = false) const;  // " + MARK + "\n",
        "create_weights_runtime (talker.h)",
    )


ACOUSTIC_LOADER = (
    "        // " + MARK + ": the acoustic decoder's q8_0 matmul weights go into ggml's CPU_REPACK buffer (interleaved\n"
    "        // q8_0_4x4 for the dotprod GEMV kernels); everything else stays in the plain store.\n"
    "        ggml_backend_buffer_type_t freebook_repack_buft = nullptr;\n"
    "        if (acoustic_repack && backend_type == core::BackendType::Cpu &&\n"
    "            weight_storage_type == assets::TensorStorageType::Native) {\n"
    "            for (ggml_backend_buffer_type_t buft : core::cpu_extra_buffer_types(backend)) {\n"
    "                if (std::string(ggml_backend_buft_name(buft)) == \"CPU_REPACK\") {\n"
    "                    freebook_repack_buft = buft;\n"
    "                }\n"
    "            }\n"
    "            if (freebook_repack_buft != nullptr) {\n"
    "                weights.acoustic_repack_store = std::make_shared<core::BackendWeightStore>(\n"
    "                    backend,\n"
    "                    backend_type,\n"
    "                    \"vieneu_v3_turbo.acoustic_decoder.repack\",\n"
    "                    64 * ggml_tensor_overhead(),\n"
    "                    freebook_repack_buft);\n"
    "            }\n"
    "        }\n"
    "        const auto freebook_load_acoustic = [&](\n"
    "            const assets::TensorSource & tensor_source,\n"
    "            const std::string & name,\n"
    "            assets::TensorStorageType storage,\n"
    "            std::initializer_list<int64_t> shape) {\n"
    "            const std::vector<int64_t> dims(shape);\n"
    "            if (freebook_repack_buft != nullptr && dims.size() == 2) {\n"
    "                const ggml_type type = assets::ggml_type_for_tensor_storage(\n"
    "                    assets::tensor_storage_type_for_dtype(tensor_source.require_metadata(name).dtype));\n"
    "                if (core::buffer_type_supports_matmul_weight(backend, freebook_repack_buft, type, dims[1], dims[0])) {\n"
    "                    auto value = weights.acoustic_repack_store->load_tensor(tensor_source, name, storage, dims);\n"
    "                    ggml_set_name(value.tensor, name.c_str());\n"
    "                    ++weights.acoustic_repack_weights;\n"
    "                    return value;\n"
    "                }\n"
    "            }\n"
    "            return weights.store->load_tensor(tensor_source, name, storage, dims);\n"
    "        };\n"
)


def patch_talker(text: str) -> str:
    if "FREEBOOK_PATCH_PREFILL_BLAS" not in text:
        sys.exit("[vieneu_acoustic_repack] cần chạy vieneu_prefill_blas.py trước")
    text = replace_once(
        text,
        "struct VieNeuTalkerWeights {\n    std::shared_ptr<core::BackendWeightStore> store;\n",
        "struct VieNeuTalkerWeights {\n    std::shared_ptr<core::BackendWeightStore> store;\n"
        "    // " + MARK + ": CPU_REPACK store of the acoustic decoder's matmul weights (null when off).\n"
        "    std::shared_ptr<core::BackendWeightStore> acoustic_repack_store;\n"
        "    int64_t acoustic_repack_weights = 0;\n",
        "struct VieNeuTalkerWeights",
    )
    text = replace_once(
        text,
        "    size_t weight_context_bytes,\n"
        "    engine::assets::TensorStorageType weight_storage_type) {\n"
        "    const auto & source = *assets.model_weights;\n",
        "    size_t weight_context_bytes,\n"
        "    engine::assets::TensorStorageType weight_storage_type,\n"
        "    bool acoustic_repack = false) {  // " + MARK + "\n"
        "    const auto & source = *assets.model_weights;\n",
        "load_talker_weights signature",
    )
    text = replace_once(
        text,
        "        weights.code_predictor.layers.reserve(static_cast<size_t>(predictor_config.num_hidden_layers));\n"
        "        for (int64_t layer = 0; layer < predictor_config.num_hidden_layers; ++layer) {\n"
        "            const std::string prefix = \"acoustic_decoder.layers.\" + std::to_string(layer);\n",
        ACOUSTIC_LOADER
        + "        weights.code_predictor.layers.reserve(static_cast<size_t>(predictor_config.num_hidden_layers));\n"
        "        for (int64_t layer = 0; layer < predictor_config.num_hidden_layers; ++layer) {\n"
        "            const std::string prefix = \"acoustic_decoder.layers.\" + std::to_string(layer);\n",
        "vòng lớp acoustic_decoder",
    )
    for suffix in (".attn.qkv.weight", ".attn.o_proj.weight", ".ff_gate.weight", ".ff_up.weight", ".ff_down.weight"):
        text = replace_once(
            text,
            "weights.store->load_tensor(\n                source,\n                prefix + \"" + suffix + "\",\n",
            "freebook_load_acoustic(  // " + MARK + "\n                source,\n                prefix + \"" + suffix + "\",\n",
            "nạp " + suffix,
        )
    text = replace_once(
        text,
        "    weights.store->upload();\n    return weights;\n}\n",
        "    weights.store->upload();\n"
        "    if (weights.acoustic_repack_store != nullptr) {  // " + MARK + "\n"
        "        weights.acoustic_repack_store->upload();\n"
        "    }\n"
        "    engine::debug::timing_log_scalar(\"vieneu_v3_turbo.talker.acoustic_repack.weights\", weights.acoustic_repack_weights);\n"
        "    return weights;\n}\n",
        "cuối load_talker_weights",
    )
    text = replace_once(
        text,
        "        bool prefill_blas = false)  // FREEBOOK_PATCH_PREFILL_BLAS\n",
        "        bool prefill_blas = false,  // FREEBOOK_PATCH_PREFILL_BLAS\n"
        "        bool acoustic_repack = false)  // " + MARK + "\n",
        "tham số hàm dựng VieNeuTalkerWeightsRuntime",
    )
    text = replace_once(
        text,
        "load_talker_weights(*assets_, backend_, backend_type_, kTalkerWeightContextBytes, weight_storage_type));\n",
        "load_talker_weights(\n"
        "                *assets_, backend_, backend_type_, kTalkerWeightContextBytes, weight_storage_type, acoustic_repack));  // "
        + MARK + "\n",
        "gọi load_talker_weights",
    )
    text = replace_once(
        text,
        "    bool prefill_blas) const {  // FREEBOOK_PATCH_PREFILL_BLAS\n",
        "    bool prefill_blas,  // FREEBOOK_PATCH_PREFILL_BLAS\n"
        "    bool acoustic_repack) const {  // " + MARK + "\n",
        "định nghĩa create_weights_runtime",
    )
    text = replace_once(
        text,
        "        prefill_blas);  // FREEBOOK_PATCH_PREFILL_BLAS\n}\n",
        "        prefill_blas,  // FREEBOOK_PATCH_PREFILL_BLAS\n"
        "        acoustic_repack);  // " + MARK + "\n}\n",
        "make_shared VieNeuTalkerWeightsRuntime",
    )
    text = replace_once(
        text,
        "        constants.ensure_uploaded();\n"
        "        buffer_ = ggml_backend_alloc_ctx_tensors(ctx_.get(), weights_->backend());\n"
        "        if (buffer_ == nullptr) {\n"
        "            throw std::runtime_error(\"failed to allocate VieNeu-TTS code predictor graph\");\n"
        "        }\n",
        "        constants.ensure_uploaded();\n"
        "        if (weights_->weights().acoustic_repack_weights > 0) {  // " + MARK + "\n"
        "            core::validate_backend_graph_with_cpu_extra_buffers(\n"
        "                weights_->backend(), prefill_graph_, \"VieNeu-TTS code predictor prefill graph\");\n"
        "            for (const auto & step_graph : step_graphs_) {\n"
        "                core::validate_backend_graph_with_cpu_extra_buffers(\n"
        "                    weights_->backend(), step_graph.graph, \"VieNeu-TTS code predictor step graph\");\n"
        "            }\n"
        "        }\n"
        "        buffer_ = ggml_backend_alloc_ctx_tensors(ctx_.get(), weights_->backend());\n"
        "        if (buffer_ == nullptr) {\n"
        "            throw std::runtime_error(\"failed to allocate VieNeu-TTS code predictor graph\");\n"
        "        }\n",
        "CodePredictorGraph dựng graph",
    )
    text = replace_once(
        text,
        "        engine::debug::timing_log_scalar(\"vieneu_v3_turbo.talker.prefill.blas_active\", "
        "static_cast<int64_t>(sched_ != nullptr));\n",
        "        engine::debug::timing_log_scalar(\"vieneu_v3_turbo.talker.prefill.blas_active\", "
        "static_cast<int64_t>(sched_ != nullptr));\n"
        "        engine::debug::timing_log_scalar(  // " + MARK + "\n"
        "            \"vieneu_v3_turbo.talker.acoustic_repack.weights\", weights_->weights().acoustic_repack_weights);\n",
        "log blas_active của bước nạp prompt",
    )
    return text


def patch_session(text: str) -> str:
    if "FREEBOOK_PATCH_THREADPOOL" not in text:
        sys.exit("[vieneu_acoustic_repack] cần chạy vieneu_threadpool.py trước")
    text = replace_once(
        text,
        "bool prefill_blas_from_options(const runtime::SessionOptions & options) {\n",
        "// " + MARK + ": `" + OPTION + "` — acoustic decoder weights in ggml's CPU_REPACK buffer (default off).\n"
        "bool acoustic_repack_from_options(const runtime::SessionOptions & options) {\n"
        "    if (const auto value = runtime::find_option(options.options, {\"" + OPTION + "\"})) {\n"
        "        return runtime::parse_bool_option(*value, \"" + OPTION + "\");\n"
        "    }\n"
        "    return false;\n"
        "}\n"
        "\n"
        "bool prefill_blas_from_options(const runtime::SessionOptions & options) {\n",
        "prefill_blas_from_options",
    )
    text = replace_once(
        text,
        "            key != \"vieneu_v3_turbo.threadpool_poll\") {  // FREEBOOK_PATCH_THREADPOOL\n",
        "            key != \"vieneu_v3_turbo.threadpool_poll\" &&  // FREEBOOK_PATCH_THREADPOOL\n"
        "            key != \"" + OPTION + "\") {  // " + MARK + "\n",
        "khoá session option hợp lệ",
    )
    text = replace_once(
        text,
        "        prefill_blas_from_options(options));  // FREEBOOK_PATCH_PREFILL_BLAS\n",
        "        prefill_blas_from_options(options),  // FREEBOOK_PATCH_PREFILL_BLAS\n"
        "        acoustic_repack_from_options(options));  // " + MARK + "\n",
        "gọi create_weights_runtime",
    )
    return text


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: vieneu_acoustic_repack.py <thư mục nguồn audio.cpp>")
    root = pathlib.Path(sys.argv[1])
    files = {TALKER_HEADER: patch_talker_header, TALKER: patch_talker, SESSION: patch_session}
    texts = {rel: (root / rel).read_text(encoding="utf-8") for rel in files}
    if MARK in texts[TALKER]:
        print("[vieneu_acoustic_repack] đã vá từ trước, bỏ qua")
        return
    patched = {rel: fn(texts[rel]) for rel, fn in files.items()}
    for rel, text in patched.items():
        (root / rel).write_text(text, encoding="utf-8")
    print("[vieneu_acoustic_repack] đã vá " + ", ".join(files))


if __name__ == "__main__":
    main()
