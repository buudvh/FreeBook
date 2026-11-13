#!/usr/bin/env python3
"""Cho bước nạp prompt của VieNeu Turbo chạy phép nhân ma trận qua Accelerate (AMX trên iPhone) — session option
`vieneu_v3_turbo.prefill_blas`, mặc định tắt (1.3.927).

Vì sao: nạp prompt (12 lớp backbone trên phiên âm + giọng mẫu 68–91 khung, mỗi đoạn một lần) chiếm ~21–23% thời gian
Turbo trên iPhone 11. Nó chạy theo lô (~190 vị trí) ⇒ đúng loại việc AMX làm nhanh (`cblas_sgemm` 388 GFLOPS trên máy).

Cách làm (khuôn y bản vá `vieneu_codec_blas`):
- `VieNeuTalkerWeightsRuntime` nhận cờ `prefill_blas` (tham số cuối của `create_weights_runtime`, mặc định `false`) và giữ
  một backend "BLAS" khi cờ bật + backend là CPU + bản build có ggml-blas.
- `TalkerPrefillGraph` (đã qua bản vá `vieneu_prefill_gallocr` — chạy SAU bản vá đó): có backend BLAS ⇒ cấp phát + chạy
  graph qua `ggml_backend_sched` [BLAS, CPU] thay cho gallocr. Cỡ scheduler = 2 × số tensor graph dùng + 1024 (truyền
  sức chứa graph 65536 sẽ xin ~1,3 GB — lỗi đã làm app chết ở 1.3.924 với codec). Reserve hỏng ⇒ lùi gallocr (reserve
  chưa gán dữ liệu cho tensor nào); alloc hỏng sau reserve ⇒ ném lỗi cho đoạn đó (graph cấp phát dở không dùng lại được).
- Trọng số q8_0: ggml-blas giải lượng tử ra F32 mỗi lần gọi rồi `cblas_sgemm` với activation F32 — **không** lượng tử
  hoá activation về q8 như đường CPU ⇒ kết quả gần bản fp32 gốc hơn, không trùng từng byte với đường cũ. Job parity
  chấm bằng hidden cuối của bước nạp prompt so với đáp án fp32 (`weight_type=f32`).
- Tắt (mặc định) ⇒ đúng đường cũ.
- Log (khi bật log): `vieneu_v3_turbo.talker.prefill.blas_active` 0/1 mỗi lượt nạp; `…prefill.graph_nodes`,
  `…prefill.sched_context_mb` mỗi lần dựng graph.

Sửa bằng mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 vieneu_prefill_blas.py <thư mục nguồn audio.cpp>   (sau vieneu_prefill_gallocr.py + vieneu_codec_blas.py)
"""
import pathlib
import sys

MARK = "FREEBOOK_PATCH_PREFILL_BLAS"
HEADER = "include/engine/community_models/vieneu_v3_turbo/talker.h"
TALKER = "src/community_models/vieneu_v3_turbo/talker.cpp"
SESSION = "src/community_models/vieneu_v3_turbo/session.cpp"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[vieneu_prefill_blas] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp / bản vá trước đã đổi")
    return text.replace(old, new, 1)


def patch_header(text: str) -> str:
    return replace_once(
        text,
        "        engine::assets::TensorStorageType weight_storage_type) const;\n",
        "        engine::assets::TensorStorageType weight_storage_type,\n"
        "        bool prefill_blas = false) const;  // " + MARK + "\n",
        "create_weights_runtime declaration",
    )


def patch_talker(text: str) -> str:
    if "FREEBOOK_PATCH_PREFILL_GALLOCR" not in text:
        sys.exit("[vieneu_prefill_blas] cần chạy vieneu_prefill_gallocr.py trước")
    text = replace_once(
        text,
        "#include <ggml-alloc.h>  // FREEBOOK_PATCH_PREFILL_GALLOCR\n",
        "#include <ggml-alloc.h>  // FREEBOOK_PATCH_PREFILL_GALLOCR\n"
        "#include <unordered_set>  // " + MARK + "\n",
        "include ggml-alloc.h",
    )
    # 1. Dựng backend BLAS (như moonshine_asr), trước lớp weights runtime.
    text = replace_once(
        text,
        "}  // namespace\n\nclass VieNeuTalkerWeightsRuntime {\n",
        "}  // namespace\n"
        "\n"
        "// " + MARK + ": the BLAS backend (ggml-blas, Accelerate on Apple) when this build has it.\n"
        "static ggml_backend_t freebook_init_talker_blas_backend(int threads) {\n"
        "    for (size_t reg_index = 0; reg_index < ggml_backend_reg_count(); ++reg_index) {\n"
        "        ggml_backend_reg_t reg = ggml_backend_reg_get(reg_index);\n"
        "        const char * reg_name = reg != nullptr ? ggml_backend_reg_name(reg) : nullptr;\n"
        "        if (reg_name == nullptr || std::string(reg_name) != \"BLAS\") {\n"
        "            continue;\n"
        "        }\n"
        "        if (ggml_backend_reg_dev_count(reg) == 0) {\n"
        "            return nullptr;\n"
        "        }\n"
        "        ggml_backend_t blas = ggml_backend_dev_init(ggml_backend_reg_dev_get(reg, 0), nullptr);\n"
        "        if (blas != nullptr && threads > 0) {\n"
        "            core::set_backend_threads(blas, threads);\n"
        "        }\n"
        "        return blas;\n"
        "    }\n"
        "    return nullptr;\n"
        "}\n"
        "\n"
        "class VieNeuTalkerWeightsRuntime {\n",
        "class VieNeuTalkerWeightsRuntime",
    )
    # 2. Weights runtime nhận cờ, giữ backend BLAS, nhả trước backend CPU.
    text = replace_once(
        text,
        "        size_t code_predictor_constant_context_bytes,\n"
        "        engine::assets::TensorStorageType weight_storage_type)\n"
        "        : assets_(std::move(assets)),\n",
        "        size_t code_predictor_constant_context_bytes,\n"
        "        engine::assets::TensorStorageType weight_storage_type,\n"
        "        bool prefill_blas = false)  // " + MARK + "\n"
        "        : assets_(std::move(assets)),\n",
        "VieNeuTalkerWeightsRuntime ctor",
    )
    text = replace_once(
        text,
        "            \"vieneu_v3_turbo.talker.code_predictor.constants\",\n"
        "            code_predictor_constant_context_bytes);\n"
        "    }\n"
        "\n"
        "    ~VieNeuTalkerWeightsRuntime() {\n",
        "            \"vieneu_v3_turbo.talker.code_predictor.constants\",\n"
        "            code_predictor_constant_context_bytes);\n"
        "        // " + MARK + "\n"
        "        if (prefill_blas && backend_type_ == core::BackendType::Cpu) {\n"
        "            prefill_blas_backend_ = freebook_init_talker_blas_backend(threads_);\n"
        "        }\n"
        "    }\n"
        "\n"
        "    ~VieNeuTalkerWeightsRuntime() {\n"
        "        if (prefill_blas_backend_ != nullptr) {  // " + MARK + "\n"
        "            ggml_backend_free(prefill_blas_backend_);\n"
        "        }\n",
        "VieNeuTalkerWeightsRuntime ctor end / dtor",
    )
    text = replace_once(
        text,
        "    int threads() const noexcept {\n"
        "        return threads_;\n"
        "    }\n"
        "\n"
        "    ggml_backend_t backend() const noexcept {\n"
        "        return backend_;\n"
        "    }\n",
        "    int threads() const noexcept {\n"
        "        return threads_;\n"
        "    }\n"
        "\n"
        "    ggml_backend_t backend() const noexcept {\n"
        "        return backend_;\n"
        "    }\n"
        "\n"
        "    // " + MARK + ": nullptr unless the session asked for vieneu_v3_turbo.prefill_blas and ggml-blas is built in.\n"
        "    ggml_backend_t prefill_blas_backend() const noexcept {\n"
        "        return prefill_blas_backend_;\n"
        "    }\n",
        "weights runtime accessors",
    )
    text = replace_once(
        text,
        "    std::unique_ptr<core::ConstantTensorCache> code_predictor_constants_;\n};\n",
        "    std::unique_ptr<core::ConstantTensorCache> code_predictor_constants_;\n"
        "    ggml_backend_t prefill_blas_backend_ = nullptr;  // " + MARK + "\n"
        "};\n",
        "weights runtime members",
    )
    text = replace_once(
        text,
        "    engine::assets::TensorStorageType weight_storage_type) const {\n"
        "    return std::make_shared<VieNeuTalkerWeightsRuntime>(\n",
        "    engine::assets::TensorStorageType weight_storage_type,\n"
        "    bool prefill_blas) const {  // " + MARK + "\n"
        "    return std::make_shared<VieNeuTalkerWeightsRuntime>(\n",
        "create_weights_runtime definition",
    )
    text = replace_once(
        text,
        "        code_predictor_constant_context_bytes,\n"
        "        weight_storage_type);\n"
        "}\n",
        "        code_predictor_constant_context_bytes,\n"
        "        weight_storage_type,\n"
        "        prefill_blas);  // " + MARK + "\n"
        "}\n",
        "create_weights_runtime make_shared",
    )
    # 3. Graph nạp prompt: scheduler [BLAS, CPU] khi có backend BLAS, không thì gallocr như bản vá gallocr.
    text = replace_once(
        text,
        "        allocr_ = ggml_gallocr_new(ggml_backend_get_default_buffer_type(weights_->backend()));\n"
        "        if (allocr_ == nullptr || !ggml_gallocr_alloc_graph(allocr_, graph_)) {\n"
        "            if (allocr_ != nullptr) {\n"
        "                ggml_gallocr_free(allocr_);\n"
        "                allocr_ = nullptr;\n"
        "            }\n"
        "            ggml_backend_buffer_free(buffer_);\n"
        "            buffer_ = nullptr;\n"
        "            throw std::runtime_error(\"failed to allocate VieNeu-TTS talker prefill graph\");\n"
        "        }\n",
        "        // " + MARK + ": matmuls that ggml-blas takes (the batched projections of the prompt) run on\n"
        "        // Accelerate. Scheduler sized by the tensors this graph uses, not its 65536-node capacity (that asks for\n"
        "        // ~1.3 GB up front, which an iPhone refuses).\n"
        "        if (ggml_backend_t blas = weights_->prefill_blas_backend()) {\n"
        "            std::unordered_set<const ggml_tensor *> graph_tensors;\n"
        "            const int graph_nodes = ggml_graph_n_nodes(graph_);\n"
        "            for (int i = 0; i < graph_nodes; ++i) {\n"
        "                const ggml_tensor * node = ggml_graph_node(graph_, i);\n"
        "                graph_tensors.insert(node);\n"
        "                for (int j = 0; j < GGML_MAX_SRC; ++j) {\n"
        "                    if (node->src[j] != nullptr) {\n"
        "                        graph_tensors.insert(node->src[j]);\n"
        "                    }\n"
        "                }\n"
        "            }\n"
        "            const size_t sched_graph_size = 2 * graph_tensors.size() + 1024;\n"
        "            engine::debug::timing_log_scalar(\"vieneu_v3_turbo.talker.prefill.graph_nodes\", static_cast<int64_t>(graph_nodes));\n"
        "            engine::debug::timing_log_scalar(\"vieneu_v3_turbo.talker.prefill.sched_context_mb\",\n"
        "                static_cast<double>(sched_graph_size) * 60.0 * static_cast<double>(sizeof(ggml_tensor)) / (1024.0 * 1024.0));\n"
        "            ggml_backend_t backends[] = {blas, weights_->backend()};\n"
        "            ggml_backend_buffer_type_t bufts[] = {\n"
        "                ggml_backend_get_default_buffer_type(blas),\n"
        "                ggml_backend_get_default_buffer_type(weights_->backend()),\n"
        "            };\n"
        "            sched_ = ggml_backend_sched_new(backends, bufts, 2, sched_graph_size, false, false);\n"
        "            // reserve only measures (no tensor gets data yet) => falling back to gallocr is safe here.\n"
        "            if (sched_ != nullptr && !ggml_backend_sched_reserve(sched_, graph_)) {\n"
        "                ggml_backend_sched_free(sched_);\n"
        "                sched_ = nullptr;\n"
        "            }\n"
        "            if (sched_ != nullptr && !ggml_backend_sched_alloc_graph(sched_, graph_)) {\n"
        "                // Half-allocated: tensors may point into buffers being freed, the graph cannot be reused.\n"
        "                ggml_backend_sched_free(sched_);\n"
        "                sched_ = nullptr;\n"
        "                ggml_backend_buffer_free(buffer_);\n"
        "                buffer_ = nullptr;\n"
        "                throw std::runtime_error(\"failed to allocate VieNeu-TTS talker prefill graph through the BLAS scheduler\");\n"
        "            }\n"
        "        }\n"
        "        if (sched_ == nullptr) {\n"
        "        allocr_ = ggml_gallocr_new(ggml_backend_get_default_buffer_type(weights_->backend()));\n"
        "        if (allocr_ == nullptr || !ggml_gallocr_alloc_graph(allocr_, graph_)) {\n"
        "            if (allocr_ != nullptr) {\n"
        "                ggml_gallocr_free(allocr_);\n"
        "                allocr_ = nullptr;\n"
        "            }\n"
        "            ggml_backend_buffer_free(buffer_);\n"
        "            buffer_ = nullptr;\n"
        "            throw std::runtime_error(\"failed to allocate VieNeu-TTS talker prefill graph\");\n"
        "        }\n"
        "        }\n",
        "TalkerPrefillGraph gallocr",
    )
    text = replace_once(
        text,
        "    ~TalkerPrefillGraph() {\n"
        "        engine::core::release_backend_graph_resources(weights_->backend(), graph_);\n",
        "    ~TalkerPrefillGraph() {\n"
        "        engine::core::release_backend_graph_resources(weights_->backend(), graph_);\n"
        "        if (sched_ != nullptr) {  // " + MARK + "\n"
        "            ggml_backend_sched_free(sched_);\n"
        "        }\n",
        "TalkerPrefillGraph dtor",
    )
    text = replace_once(
        text,
        "        core::set_backend_threads(weights_->backend(), weights_->threads());\n"
        "        const ggml_status status = engine::core::compute_backend_graph(weights_->backend(), graph_);\n"
        "        ggml_backend_synchronize(weights_->backend());\n"
        "        if (status != GGML_STATUS_SUCCESS) {\n"
        "            throw std::runtime_error(\"VieNeu-TTS talker prefill graph compute failed\");\n",
        "        core::set_backend_threads(weights_->backend(), weights_->threads());\n"
        "        // " + MARK + "\n"
        "        const ggml_status status = sched_ != nullptr\n"
        "            ? ggml_backend_sched_graph_compute(sched_, graph_)\n"
        "            : engine::core::compute_backend_graph(weights_->backend(), graph_);\n"
        "        if (sched_ != nullptr) {\n"
        "            ggml_backend_sched_synchronize(sched_);\n"
        "        } else {\n"
        "            ggml_backend_synchronize(weights_->backend());\n"
        "        }\n"
        "        engine::debug::timing_log_scalar(\"vieneu_v3_turbo.talker.prefill.blas_active\", static_cast<int64_t>(sched_ != nullptr));\n"
        "        if (status != GGML_STATUS_SUCCESS) {\n"
        "            throw std::runtime_error(\"VieNeu-TTS talker prefill graph compute failed\");\n",
        "TalkerPrefillGraph compute",
    )
    text = replace_once(
        text,
        "    ggml_backend_buffer_t buffer_ = nullptr;\n"
        "    ggml_gallocr_t allocr_ = nullptr;\n"
        "};\n",
        "    ggml_backend_buffer_t buffer_ = nullptr;\n"
        "    ggml_gallocr_t allocr_ = nullptr;\n"
        "    ggml_backend_sched_t sched_ = nullptr;  // " + MARK + "\n"
        "};\n",
        "TalkerPrefillGraph members",
    )
    return text


def patch_session(text: str) -> str:
    if "FREEBOOK_PATCH_CODEC_BLAS" not in text:
        sys.exit("[vieneu_prefill_blas] cần chạy vieneu_codec_blas.py trước")
    text = replace_once(
        text,
        "bool codec_blas_from_options(const runtime::SessionOptions & options) {\n",
        "// " + MARK + ": `vieneu_v3_turbo.prefill_blas` — prompt prefill through Accelerate (default off).\n"
        "bool prefill_blas_from_options(const runtime::SessionOptions & options) {\n"
        "    if (const auto value = runtime::find_option(options.options, {\"vieneu_v3_turbo.prefill_blas\"})) {\n"
        "        return runtime::parse_bool_option(*value, \"vieneu_v3_turbo.prefill_blas\");\n"
        "    }\n"
        "    return false;\n"
        "}\n"
        "\n"
        "bool codec_blas_from_options(const runtime::SessionOptions & options) {\n",
        "codec_blas_from_options",
    )
    text = replace_once(
        text,
        "            key != \"vieneu_v3_turbo.codec_blas\") {  // FREEBOOK_PATCH_CODEC_BLAS\n",
        "            key != \"vieneu_v3_turbo.codec_blas\" &&  // FREEBOOK_PATCH_CODEC_BLAS\n"
        "            key != \"vieneu_v3_turbo.prefill_blas\") {  // " + MARK + "\n",
        "khoá session option hợp lệ",
    )
    text = replace_once(
        text,
        "        code_predictor_constant_context_bytes_,\n"
        "        talker_weight_storage_type_);\n",
        "        code_predictor_constant_context_bytes_,\n"
        "        talker_weight_storage_type_,\n"
        "        prefill_blas_from_options(options));  // " + MARK + "\n",
        "create_weights_runtime call",
    )
    return text


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: vieneu_prefill_blas.py <thư mục nguồn audio.cpp>")
    root = pathlib.Path(sys.argv[1])
    files = {HEADER: patch_header, TALKER: patch_talker, SESSION: patch_session}
    texts = {rel: (root / rel).read_text(encoding="utf-8") for rel in files}
    if MARK in texts[TALKER]:
        print("[vieneu_prefill_blas] đã vá từ trước, bỏ qua")
        return
    patched = {rel: fn(texts[rel]) for rel, fn in files.items()}
    for rel, text in patched.items():
        (root / rel).write_text(text, encoding="utf-8")
    print("[vieneu_prefill_blas] đã vá " + ", ".join(files))


if __name__ == "__main__":
    main()
