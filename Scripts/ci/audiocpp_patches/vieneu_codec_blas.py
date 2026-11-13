#!/usr/bin/env python3
"""Cho codec MOSS của VieNeu Turbo giải mã qua Accelerate (AMX trên iPhone) — sau session option, mặc định tắt.

Vì sao (báo cáo tối ưu Turbo, P0a): codec chiếm 37–51% thời gian một đoạn. Nó chạy phép nhân ma trận fp32 trên NEON
(trọng số transformer của codec được nạp thành F32), đúng loại việc mà AMX của A13 làm nhanh ~10× (`cblas_sgemm`
388 GFLOPS trên iPhone 11 so với ~37 GFLOPS mỗi lõi NEON).

Cách làm — phép tính giữ nguyên, chỉ đổi nơi chạy phép nhân ma trận:
- `MossAudioTokenizerCodecRuntimeOptions.decoder_cpu_blas_scheduler` (mặc định `false`).
- Bật + backend là CPU + bản build có ggml-blas ⇒ decoder dựng thêm backend "BLAS"; graph giải mã cả đoạn
  (`prepare_graph`) chạy qua `ggml_backend_sched` [BLAS, CPU] — khuôn y hệt `moonshine_asr` của audio.cpp. ggml-blas
  chỉ nhận MUL_MAT liền bộ nhớ, đủ lớn (≥ 32 mỗi chiều), activation F32; mọi node khác ở lại CPU. Dựng không được ⇒
  lùi về gallocr như cũ.
- Tắt (mặc định) ⇒ đúng đường cũ, graph y hệt ⇒ job parity so từng byte với bản gốc.
- Không đụng: giải mã từng khung (stream), encoder (nhân bản giọng), talker.
- VieNeu Turbo: session option `vieneu_v3_turbo.codec_blas` (true/false) ⇒ field trên.
- Scheduler dựng hỏng giữa chừng ⇒ bỏ hẳn BLAS cho decoder này và dựng lại graph sạch trên đường cũ (graph cấp phát
  dở có thể trỏ vào bộ nhớ scheduler đã nhả, không dùng lại được).
- **Cỡ của scheduler** (1.3.926): `ggml_backend_sched_new` dành sẵn `graph_size × 60` tensor (mỗi node một split, 30
  đầu vào mỗi split, ×2). 1.3.924 truyền sức chứa của graph (131072) ⇒ một lần `malloc` ~2,6 GB: máy ảo macOS cho qua
  (bộ nhớ ảo dư), iPhone trả NULL ⇒ `GGML_ASSERT(ctx->mem_buffer != NULL)` ⇒ app chết. Nay truyền 2 × số tensor graph
  thật sự dùng (node + nguồn của chúng) + 1024. Log `…graph_nodes`, `…sched_graph_size`, `…sched_context_mb`; job
  parity chặn khi `sched_context_mb` > 512.
- **Q·Kᵀ của attention** (1.3.927): ggml-blas chỉ nhận src1 liền bộ nhớ, mà Q là view hoán vị ⇒ khi dựng graph cho
  scheduler BLAS, attention chép Q thành tensor liền (`ggml_cont`) để phép này cũng chạy Accelerate. Cờ thread_local
  `freebook_contiguous_attention_q` chỉ bật trong `prepare_graph` của decoder khi có backend BLAS.
- Log (khi bật log): `moss.audio_tokenizer.decode.blas_scheduler` 0/1 + `…blas_nodes` + `…sched_splits` mỗi lần dựng
  graph, `…blas_active` 0/1 mỗi lượt giải mã (app đọc để ghi đoạn đó có chạy BLAS không).

Sửa bằng mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 vieneu_codec_blas.py <thư mục nguồn audio.cpp>
"""
import pathlib
import sys

MARK = "FREEBOOK_PATCH_CODEC_BLAS"
HEADER = "include/engine/framework/codecs/moss_audio_tokenizer_codec_runtime.h"
CODEC = "src/framework/codecs/moss_audio_tokenizer_codec_runtime.cpp"
SESSION = "src/community_models/vieneu_v3_turbo/session.cpp"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[vieneu_codec_blas] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp đã đổi, phải xem lại bản vá")
    return text.replace(old, new, 1)


def patch_header(text: str) -> str:
    return replace_once(
        text,
        "    bool widen_encoder_transformer_weights_to_f32 = false;\n};\n",
        "    bool widen_encoder_transformer_weights_to_f32 = false;\n"
        "    // " + MARK + ": decode whole chunks through a ggml_backend_sched of [BLAS, CPU] (Accelerate on Apple)\n"
        "    // when the backend is the CPU and ggml-blas is built in; otherwise the plain CPU path is kept.\n"
        "    bool decoder_cpu_blas_scheduler = false;\n"
        "};\n",
        "Options: widen_encoder_transformer_weights_to_f32",
    )


def patch_codec(text: str) -> str:
    # 0. unordered_set cho bước đếm tensor của graph (cỡ bộ chia việc, 1.3.926).
    text = replace_once(
        text,
        "#include <utility>\n",
        "#include <unordered_set>  // " + MARK + "\n#include <utility>\n",
        "include utility",
    )
    # 0b. Q liền bộ nhớ trong attention khi graph đang dựng cho scheduler BLAS (1.3.927): ggml-blas từ chối src1 là
    #     view hoán vị ⇒ Q·Kᵀ ở lại NEON. Cờ thread_local chỉ bật trong `prepare_graph` của decoder khi có backend
    #     BLAS ⇒ tắt công tắc / encoder / giải mã từng khung: graph y hệt cũ.
    text = replace_once(
        text,
        "inline constexpr float kMaskedAttentionBias = std::numeric_limits<float>::lowest();\n",
        "inline constexpr float kMaskedAttentionBias = std::numeric_limits<float>::lowest();\n"
        "\n"
        "// " + MARK + ": while a decoder graph for the BLAS scheduler is being built, attention copies Q into a\n"
        "// contiguous tensor so ggml-blas also takes Q*K^T (it rejects a permuted view as src1). Off => graph unchanged.\n"
        "inline thread_local bool freebook_contiguous_attention_q = false;\n",
        "kMaskedAttentionBias",
    )
    text = replace_once(
        text,
        "    const modules::MatMulModule matmul;\n"
        "    auto scores = matmul.build(\n"
        "        ctx,\n"
        "        q_heads,\n",
        "    const modules::MatMulModule matmul;\n"
        "    auto scores = matmul.build(\n"
        "        ctx,\n"
        "        freebook_contiguous_attention_q  // " + MARK + "\n"
        "            ? core::wrap_tensor(ggml_cont(ctx.ggml, q_heads.tensor), q_heads.shape, q_heads.type)\n"
        "            : q_heads,\n",
        "attention: scores matmul",
    )
    text = replace_once(
        text,
        "    GraphCache & prepare_graph(int64_t frames) {\n"
        "        if (graph_cache != nullptr && graph_cache->frames == frames) {\n"
        "            return *graph_cache;\n"
        "        }\n"
        "\n"
        "        auto cache = std::make_unique<GraphCache>();\n",
        "    GraphCache & prepare_graph(int64_t frames) {\n"
        "        if (graph_cache != nullptr && graph_cache->frames == frames) {\n"
        "            return *graph_cache;\n"
        "        }\n"
        "\n"
        "        auto cache = std::make_unique<GraphCache>();\n"
        "        // " + MARK + ": contiguous Q only while building a graph that will run through the BLAS scheduler.\n"
        "        struct ContiguousQScope {\n"
        "            bool saved;\n"
        "            explicit ContiguousQScope(bool on) : saved(cd::freebook_contiguous_attention_q) {\n"
        "                cd::freebook_contiguous_attention_q = on;\n"
        "            }\n"
        "            ~ContiguousQScope() { cd::freebook_contiguous_attention_q = saved; }\n"
        "        } contiguous_q_scope(blas_backend != nullptr);\n",
        "Decoder prepare_graph start",
    )
    # 1. Hàm dựng backend BLAS (chép từ moonshine_asr) + deleter, trước Impl của decoder.
    text = replace_once(
        text,
        "struct MossAudioTokenizerDecoder::Impl {\n",
        "// " + MARK + ": the BLAS backend (ggml-blas, Accelerate on Apple) when this build has it, as moonshine_asr does.\n"
        "namespace {\n"
        "ggml_backend_t freebook_init_blas_backend(int threads) {\n"
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
        "struct FreebookBackendDeleter {\n"
        "    void operator()(ggml_backend_t backend) const noexcept {\n"
        "        if (backend != nullptr) ggml_backend_free(backend);\n"
        "    }\n"
        "};\n"
        "\n"
        "struct FreebookSchedDeleter {\n"
        "    void operator()(ggml_backend_sched_t sched) const noexcept {\n"
        "        if (sched != nullptr) ggml_backend_sched_free(sched);\n"
        "    }\n"
        "};\n"
        "}  // namespace\n"
        "\n"
        "struct MossAudioTokenizerDecoder::Impl {\n",
        "struct MossAudioTokenizerDecoder::Impl",
    )
    # 2. GraphCache của decoder giữ scheduler (huỷ trước gallocr / context của graph).
    text = replace_once(
        text,
        "        std::vector<StageInput> stage_inputs;\n"
        "        std::unique_ptr<std::remove_pointer_t<ggml_gallocr_t>, cd::GgmlGallocrDeleter> gallocr;\n"
        "        modules::StreamingFrameAttentionCache attention_cache;\n",
        "        std::vector<StageInput> stage_inputs;\n"
        "        std::unique_ptr<std::remove_pointer_t<ggml_gallocr_t>, cd::GgmlGallocrDeleter> gallocr;\n"
        "        modules::StreamingFrameAttentionCache attention_cache;\n"
        "        std::unique_ptr<std::remove_pointer_t<ggml_backend_sched_t>, FreebookSchedDeleter> sched;  // " + MARK + "\n",
        "Decoder GraphCache",
    )
    # 3. Backend BLAS là thành viên khai TRƯỚC graph_cache ⇒ huỷ SAU scheduler đang tham chiếu nó.
    text = replace_once(
        text,
        "    ggml_backend_t backend = nullptr;\n"
        "    core::BackendType backend_type = core::BackendType::Cpu;\n"
        "    int threads = 1;\n"
        "    int64_t sampling_rate = 48000;\n",
        "    ggml_backend_t backend = nullptr;\n"
        "    std::unique_ptr<std::remove_pointer_t<ggml_backend_t>, FreebookBackendDeleter> blas_backend;  // " + MARK + "\n"
        "    core::BackendType backend_type = core::BackendType::Cpu;\n"
        "    int threads = 1;\n"
        "    int64_t sampling_rate = 48000;\n",
        "Decoder Impl backend",
    )
    # 4. Graph giải mã cả đoạn: scheduler [BLAS, CPU] nếu có, không thì gallocr như cũ.
    text = replace_once(
        text,
        "        cache->gallocr.reset(ggml_gallocr_new(ggml_backend_get_default_buffer_type(backend)));\n"
        "        if (cache->gallocr == nullptr ||\n"
        "            !ggml_gallocr_reserve(cache->gallocr.get(), cache->graph) ||\n"
        "            !ggml_gallocr_alloc_graph(cache->gallocr.get(), cache->graph)) {\n"
        "            throw std::runtime_error(\"failed to allocate MOSS codec decoder forward graph\");\n"
        "        }\n",
        "        // " + MARK + ": matmuls that ggml-blas takes run on Accelerate; everything else stays on the CPU.\n"
        "        if (blas_backend != nullptr) {\n"
        "            ggml_backend_t backends[] = {blas_backend.get(), backend};\n"
        "            ggml_backend_buffer_type_t bufts[] = {\n"
        "                ggml_backend_get_default_buffer_type(blas_backend.get()),\n"
        "                ggml_backend_get_default_buffer_type(backend),\n"
        "            };\n"
        "            // ggml_backend_sched_new reserves graph_size x 60 tensors (one split per node, 30 inputs each, x2) up\n"
        "            // front. Passing the graph's 131072-node capacity asked for ~2.6 GB in one malloc: fine on a desktop,\n"
        "            // NULL on an iPhone => GGML_ASSERT(ctx->mem_buffer != NULL) (FreeBook 1.3.924). Size it by the tensors\n"
        "            // this graph really uses (nodes + their sources), doubled for the hash set's load factor.\n"
        "            std::unordered_set<const ggml_tensor *> graph_tensors;\n"
        "            const int graph_nodes = ggml_graph_n_nodes(cache->graph);\n"
        "            for (int i = 0; i < graph_nodes; ++i) {\n"
        "                const ggml_tensor * node = ggml_graph_node(cache->graph, i);\n"
        "                graph_tensors.insert(node);\n"
        "                for (int j = 0; j < GGML_MAX_SRC; ++j) {\n"
        "                    if (node->src[j] != nullptr) {\n"
        "                        graph_tensors.insert(node->src[j]);\n"
        "                    }\n"
        "                }\n"
        "            }\n"
        "            const size_t sched_graph_size = 2 * graph_tensors.size() + 1024;\n"
        "            engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.graph_nodes\", static_cast<int64_t>(graph_nodes));\n"
        "            engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.sched_graph_size\",\n"
        "                                             static_cast<int64_t>(sched_graph_size));\n"
        "            engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.sched_context_mb\",\n"
        "                static_cast<double>(sched_graph_size) * 60.0 * static_cast<double>(sizeof(ggml_tensor)) / (1024.0 * 1024.0));\n"
        "            cache->sched.reset(ggml_backend_sched_new(backends, bufts, 2, sched_graph_size, false, false));\n"
        "            if (cache->sched == nullptr ||\n"
        "                !ggml_backend_sched_reserve(cache->sched.get(), cache->graph) ||\n"
        "                !ggml_backend_sched_alloc_graph(cache->sched.get(), cache->graph)) {\n"
        "                // A half-allocated graph may point into the scheduler's freed buffers: drop it, give up on\n"
        "                // BLAS for this decoder and build a fresh graph on the plain path.\n"
        "                cache->sched.reset();\n"
        "                cache.reset();\n"
        "                blas_backend.reset();\n"
        "                engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.blas_scheduler\", static_cast<int64_t>(0));\n"
        "                return prepare_graph(frames);\n"
        "            }\n"
        "            int64_t blas_nodes = 0;\n"
        "            for (int i = 0; i < ggml_graph_n_nodes(cache->graph); ++i) {\n"
        "                if (ggml_backend_sched_get_tensor_backend(cache->sched.get(), ggml_graph_node(cache->graph, i)) ==\n"
        "                    blas_backend.get()) {\n"
        "                    ++blas_nodes;\n"
        "                }\n"
        "            }\n"
        "            engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.blas_scheduler\", static_cast<int64_t>(1));\n"
        "            engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.blas_nodes\", blas_nodes);\n"
        "            engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.sched_splits\",\n"
        "                static_cast<int64_t>(ggml_backend_sched_get_n_splits(cache->sched.get())));\n"
        "        }\n"
        "        if (cache->sched == nullptr) {\n"
        "        cache->gallocr.reset(ggml_gallocr_new(ggml_backend_get_default_buffer_type(backend)));\n"
        "        if (cache->gallocr == nullptr ||\n"
        "            !ggml_gallocr_reserve(cache->gallocr.get(), cache->graph) ||\n"
        "            !ggml_gallocr_alloc_graph(cache->gallocr.get(), cache->graph)) {\n"
        "            throw std::runtime_error(\"failed to allocate MOSS codec decoder forward graph\");\n"
        "        }\n"
        "        }\n",
        "Decoder prepare_graph gallocr",
    )
    # 5. Chạy graph giải mã cả đoạn: qua scheduler nếu có.
    text = replace_once(
        text,
        "    const ggml_status status = ggml_backend_graph_compute(impl_->backend, graph.graph);\n"
        "    ggml_backend_synchronize(impl_->backend);\n"
        "    if (collect_timing) {\n"
        "        graph_compute_ms = engine::debug::elapsed_ms(compute_start);\n",
        "    // " + MARK + "\n"
        "    const ggml_status status = graph.sched != nullptr\n"
        "        ? ggml_backend_sched_graph_compute(graph.sched.get(), graph.graph)\n"
        "        : ggml_backend_graph_compute(impl_->backend, graph.graph);\n"
        "    if (graph.sched != nullptr) {\n"
        "        ggml_backend_sched_synchronize(graph.sched.get());\n"
        "    } else {\n"
        "        ggml_backend_synchronize(impl_->backend);\n"
        "    }\n"
        "    if (collect_timing) {\n"
        "        // Every decode, also when the graph came from the cache: the app reads it to label each chunk.\n"
        "        engine::debug::timing_log_scalar(\"moss.audio_tokenizer.decode.blas_active\",\n"
        "                                         static_cast<int64_t>(graph.sched != nullptr));\n"
        "    }\n"
        "    if (collect_timing) {\n"
        "        graph_compute_ms = engine::debug::elapsed_ms(compute_start);\n",
        "Decoder decode compute",
    )
    # 6. Hàm dựng decoder nhận cờ (tham số cuối, có mặc định ⇒ các family khác không đổi).
    text = replace_once(
        text,
        "        assets::TensorStorageType weight_storage_type,\n"
        "        MossAudioTokenizerConfig config = moss_audio_tokenizer_v2_config());\n"
        "    ~MossAudioTokenizerDecoder();\n",
        "        assets::TensorStorageType weight_storage_type,\n"
        "        MossAudioTokenizerConfig config = moss_audio_tokenizer_v2_config(),\n"
        "        bool cpu_blas_scheduler = false);  // " + MARK + "\n"
        "    ~MossAudioTokenizerDecoder();\n",
        "Decoder ctor declaration",
    )
    text = replace_once(
        text,
        "    assets::TensorStorageType weight_storage_type,\n"
        "    MossAudioTokenizerConfig config)\n"
        "    : impl_(std::make_unique<Impl>()) {\n"
        "    impl_->backend = execution_context.backend();\n"
        "    if (impl_->backend == nullptr) {\n"
        "        throw std::runtime_error(\"MOSS codec decoder backend is not initialized\");\n",
        "    assets::TensorStorageType weight_storage_type,\n"
        "    MossAudioTokenizerConfig config,\n"
        "    bool cpu_blas_scheduler)  // " + MARK + "\n"
        "    : impl_(std::make_unique<Impl>()) {\n"
        "    impl_->backend = execution_context.backend();\n"
        "    if (impl_->backend == nullptr) {\n"
        "        throw std::runtime_error(\"MOSS codec decoder backend is not initialized\");\n",
        "Decoder ctor definition",
    )
    text = replace_once(
        text,
        "    impl_->store->upload();\n"
        "}\n"
        "\n"
        "MossAudioTokenizerDecoder::~MossAudioTokenizerDecoder() = default;\n",
        "    impl_->store->upload();\n"
        "    // " + MARK + "\n"
        "    if (cpu_blas_scheduler && impl_->backend_type == core::BackendType::Cpu) {\n"
        "        impl_->blas_backend.reset(freebook_init_blas_backend(impl_->threads));\n"
        "    }\n"
        "}\n"
        "\n"
        "MossAudioTokenizerDecoder::~MossAudioTokenizerDecoder() = default;\n",
        "Decoder ctor body end",
    )
    text = replace_once(
        text,
        "                options.transformer_weight_storage_type,\n"
        "                config);\n"
        "        }\n"
        "        return *decoder;\n",
        "                options.transformer_weight_storage_type,\n"
        "                config,\n"
        "                options.decoder_cpu_blas_scheduler);  // " + MARK + "\n"
        "        }\n"
        "        return *decoder;\n",
        "require_decoder",
    )
    return text


def patch_session(text: str) -> str:
    text = replace_once(
        text,
        "        return runtime::parse_bool_option(*value, \"vieneu_v3_turbo.mem_saver\");\n"
        "    }\n"
        "    return false;\n"
        "}\n",
        "        return runtime::parse_bool_option(*value, \"vieneu_v3_turbo.mem_saver\");\n"
        "    }\n"
        "    return false;\n"
        "}\n"
        "\n"
        "// " + MARK + ": `vieneu_v3_turbo.codec_blas` — decode chunks through Accelerate (default off).\n"
        "bool codec_blas_from_options(const runtime::SessionOptions & options) {\n"
        "    if (const auto value = runtime::find_option(options.options, {\"vieneu_v3_turbo.codec_blas\"})) {\n"
        "        return runtime::parse_bool_option(*value, \"vieneu_v3_turbo.codec_blas\");\n"
        "    }\n"
        "    return false;\n"
        "}\n",
        "mem_saver_from_options",
    )
    text = replace_once(
        text,
        "            key != \"vieneu_v3_turbo.mem_saver\") {\n",
        "            key != \"vieneu_v3_turbo.mem_saver\" &&\n"
        "            key != \"vieneu_v3_turbo.codec_blas\") {  // " + MARK + "\n",
        "khoá session option hợp lệ",
    )
    text = replace_once(
        text,
        "        engine::codecs::MossAudioTokenizerCodecRuntimeOptions{\n"
        "            speech_decoder_constant_context_bytes_,\n"
        "            speech_decoder_graph_arena_bytes_,\n"
        "            speech_decoder_graph_arena_bytes_,\n"
        "            false,\n"
        "        },\n",
        "        [&]() {\n"
        "            engine::codecs::MossAudioTokenizerCodecRuntimeOptions codec_options{\n"
        "                speech_decoder_constant_context_bytes_,\n"
        "                speech_decoder_graph_arena_bytes_,\n"
        "                speech_decoder_graph_arena_bytes_,\n"
        "                false,\n"
        "            };\n"
        "            codec_options.decoder_cpu_blas_scheduler = codec_blas_from_options(options);  // " + MARK + "\n"
        "            return codec_options;\n"
        "        }(),\n",
        "MossAudioTokenizerCodecRuntimeOptions",
    )
    return text


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: vieneu_codec_blas.py <thư mục nguồn audio.cpp>")
    root = pathlib.Path(sys.argv[1])
    files = {HEADER: patch_header, CODEC: patch_codec, SESSION: patch_session}
    texts = {rel: (root / rel).read_text(encoding="utf-8") for rel in files}
    if MARK in texts[CODEC]:
        print("[vieneu_codec_blas] đã vá từ trước, bỏ qua")
        return
    # Vá hết trong bộ nhớ rồi mới ghi ⇒ một mốc lệch thì không file nào bị sửa dở.
    patched = {rel: fn(texts[rel]) for rel, fn in files.items()}
    for rel, text in patched.items():
        (root / rel).write_text(text, encoding="utf-8")
    print("[vieneu_codec_blas] đã vá " + ", ".join(files))


if __name__ == "__main__":
    main()
