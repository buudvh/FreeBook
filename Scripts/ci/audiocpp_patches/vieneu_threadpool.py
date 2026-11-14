#!/usr/bin/env python3
"""Giữ một threadpool ggml suốt đời session VieNeu Turbo thay vì tạo + huỷ luồng ở mỗi lượt tính (1.3.929, thử).

Vì sao: audio.cpp build không OpenMP ⇒ mỗi `ggml_graph_compute` trên CPU tạo một threadpool dùng một lần rồi huỷ
(`ggml-cpu.c`: `disposable_threadpool`). Turbo có ~17 lượt tính mỗi khung 80 ms (1 backbone + 16 bước bộ giải mã âm
học) ⇒ ~210 lần tạo + join luồng mỗi giây tiếng, cộng ~400 split CPU mỗi lượt giải mã codec qua scheduler BLAS. Đo
trên CI (P0a): âm học 2 luồng chỉ nhanh 1,13× so 1 luồng ⇒ chi phí mỗi lượt tính ăn gần hết phần chia việc.

Cách làm — phép tính giữ nguyên (cùng số luồng ⇒ cùng cách chia việc ⇒ trùng từng bit):
- Session option `vieneu_v3_turbo.threadpool_poll` (0…100, mặc định không có = tắt, y như upstream). Có ⇒ ở lượt
  `run` **đầu tiên** của session, `ggml_threadpool_new` (số luồng của talker, `poll` = giá trị option) rồi
  `ggml_backend_cpu_set_threadpool` cho backend CPU của talker và của session (codec). Tạo ở lượt chạy chứ không ở hàm
  dựng: luồng phụ thừa hưởng QoS của luồng tạo ra nó — app dựng session trên hàng đợi `.utility` nhưng tổng hợp ở
  `.userInitiated` (lõi hiệu năng).
- `poll`: luồng phụ quay chờ `1024 × 128 × poll` vòng trước khi ngủ (0 = ngủ ngay, đánh thức bằng cond var).
- QoS: luồng của pool giữ QoS lúc tạo. Người gọi đổi QoS (nghe thử giọng ở `.utility` rồi trình đọc ở
  `.userInitiated`) ⇒ nhả pool cũ, tạo pool mới ở lượt đó (`qos_class_self`, chỉ Apple) — kẻo trình đọc kẹt ở lõi
  tiết kiệm.
- Lớp `VieNeuTalkerWeightsRuntime` chỉ khai báo trước trong `talker.h` ⇒ thêm hai hàm tự do
  `freebook_talker_backend` / `freebook_talker_threads` (định nghĩa trong talker.cpp, cùng namespace có tên).
- Nhả: thành viên khai báo **cuối** lớp ⇒ huỷ **trước** các thành viên khác; deleter gỡ pool khỏi hai backend rồi free.
- Log (khi bật log): `vieneu_v3_turbo.threadpool_poll` + `vieneu_v3_turbo.threadpool_qos` lúc tạo pool.

Sửa bằng mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 vieneu_threadpool.py <thư mục nguồn audio.cpp>   (sau vieneu_prefill_blas.py)
"""
import pathlib
import sys

MARK = "FREEBOOK_PATCH_THREADPOOL"
HEADER = "include/engine/community_models/vieneu_v3_turbo/session.h"
SESSION = "src/community_models/vieneu_v3_turbo/session.cpp"
TALKER_HEADER = "include/engine/community_models/vieneu_v3_turbo/talker.h"
TALKER = "src/community_models/vieneu_v3_turbo/talker.cpp"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[vieneu_threadpool] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp / bản vá trước đã đổi")
    return text.replace(old, new, 1)


def patch_header(text: str) -> str:
    return replace_once(
        text,
        "    std::optional<VoicePromptCacheEntry> uncached_voice_prompt_;\n};\n",
        "    std::optional<VoicePromptCacheEntry> uncached_voice_prompt_;\n"
        "    // " + MARK + ": persistent ggml threadpool shared by the talker and codec CPU backends, created on the\n"
        "    // first run (its threads take that caller's QoS) and declared last so it is released first, before the\n"
        "    // backends it is attached to. -1 = off (a fresh pool per graph, as upstream).\n"
        "    int freebook_threadpool_poll_ = -1;\n"
        "    int freebook_threadpool_qos_ = -1;\n"
        "    std::shared_ptr<void> freebook_threadpool_;\n"
        "};\n",
        "cuối lớp VieNeuTTSSession",
    )


def patch_talker_header(text: str) -> str:
    return replace_once(
        text,
        "    VieNeuTTSTalkerConfig config_;\n};\n\n}  // namespace engine::models::vieneu_v3_turbo\n",
        "    VieNeuTTSTalkerConfig config_;\n};\n\n"
        "// " + MARK + ": the session only sees a forward declaration of the weights runtime.\n"
        "ggml_backend_t freebook_talker_backend(const VieNeuTalkerWeightsRuntime & weights);\n"
        "int freebook_talker_threads(const VieNeuTalkerWeightsRuntime & weights);\n\n"
        "}  // namespace engine::models::vieneu_v3_turbo\n",
        "cuối talker.h",
    )


def patch_talker(text: str) -> str:
    return replace_once(
        text,
        "class TalkerPrefillGraph {\n",
        "// " + MARK + "\n"
        "ggml_backend_t freebook_talker_backend(const VieNeuTalkerWeightsRuntime & weights) {\n"
        "    return weights.backend();\n"
        "}\n"
        "\n"
        "int freebook_talker_threads(const VieNeuTalkerWeightsRuntime & weights) {\n"
        "    return weights.threads();\n"
        "}\n"
        "\n"
        "class TalkerPrefillGraph {\n",
        "class TalkerPrefillGraph",
    )


def patch_session(text: str) -> str:
    if "FREEBOOK_PATCH_PREFILL_BLAS" not in text:
        sys.exit("[vieneu_threadpool] cần chạy vieneu_prefill_blas.py trước")
    text = replace_once(
        text,
        "#include <algorithm>\n#include <chrono>\n",
        "#include <ggml-cpu.h>  // " + MARK + "\n"
        "#if defined(__APPLE__)\n"
        "#include <pthread/qos.h>  // " + MARK + "\n"
        "#endif\n\n#include <algorithm>\n#include <chrono>\n",
        "include algorithm/chrono",
    )
    text = replace_once(
        text,
        "bool prefill_blas_from_options(const runtime::SessionOptions & options) {\n",
        "// " + MARK + ": `vieneu_v3_turbo.threadpool_poll` = 0..100 keeps one ggml threadpool for the session.\n"
        "int threadpool_poll_from_options(const runtime::SessionOptions & options) {\n"
        "    if (const auto value = runtime::parse_int_option(options.options, {\"vieneu_v3_turbo.threadpool_poll\"})) {\n"
        "        if (*value < 0 || *value > 100) {\n"
        "            throw std::runtime_error(\"vieneu_v3_turbo.threadpool_poll must be 0..100\");\n"
        "        }\n"
        "        return *value;\n"
        "    }\n"
        "    return -1;\n"
        "}\n"
        "\n"
        "bool prefill_blas_from_options(const runtime::SessionOptions & options) {\n",
        "prefill_blas_from_options",
    )
    text = replace_once(
        text,
        "            key != \"vieneu_v3_turbo.prefill_blas\") {  // FREEBOOK_PATCH_PREFILL_BLAS\n",
        "            key != \"vieneu_v3_turbo.prefill_blas\" &&  // FREEBOOK_PATCH_PREFILL_BLAS\n"
        "            key != \"vieneu_v3_turbo.threadpool_poll\") {  // " + MARK + "\n",
        "khoá session option hợp lệ",
    )
    text = replace_once(
        text,
        "    talker_weights_ = talker_.create_weights_runtime(\n",
        "    freebook_threadpool_poll_ = threadpool_poll_from_options(options);  // " + MARK + "\n"
        "    talker_weights_ = talker_.create_weights_runtime(\n",
        "create_weights_runtime call",
    )
    text = replace_once(
        text,
        "    require_prepared(\"VieNeu-TTS TTS run\");\n"
        "    const auto wall_start = Clock::now();\n",
        "    require_prepared(\"VieNeu-TTS TTS run\");\n"
        "    const auto wall_start = Clock::now();\n"
        "    // " + MARK + ": one pool for the session, made here so its threads inherit this caller's QoS; a caller\n"
        "    // at another QoS gets a fresh pool (threads keep the QoS they were created with).\n"
        "    if (freebook_threadpool_poll_ >= 0 && execution_context().backend_type() == core::BackendType::Cpu) {\n"
        "        int caller_qos = 0;\n"
        "#if defined(__APPLE__)\n"
        "        caller_qos = static_cast<int>(qos_class_self());\n"
        "#endif\n"
        "        if (freebook_threadpool_ != nullptr && caller_qos != freebook_threadpool_qos_) {\n"
        "            freebook_threadpool_.reset();\n"
        "        }\n"
        "        if (freebook_threadpool_ == nullptr) {\n"
        "            ggml_backend_t talker_backend = freebook_talker_backend(*talker_weights_);\n"
        "            ggml_backend_t session_backend = execution_context().backend();\n"
        "            auto params = ggml_threadpool_params_default(std::max(1, freebook_talker_threads(*talker_weights_)));\n"
        "            params.poll = static_cast<uint32_t>(freebook_threadpool_poll_);\n"
        "            ggml_threadpool * pool = ggml_threadpool_new(&params);\n"
        "            if (pool != nullptr) {\n"
        "                ggml_backend_cpu_set_threadpool(talker_backend, pool);\n"
        "                if (session_backend != talker_backend) {\n"
        "                    ggml_backend_cpu_set_threadpool(session_backend, pool);\n"
        "                }\n"
        "                freebook_threadpool_ = std::shared_ptr<void>(pool, [talker_backend, session_backend](void * owned) {\n"
        "                    ggml_backend_cpu_set_threadpool(talker_backend, nullptr);\n"
        "                    ggml_backend_cpu_set_threadpool(session_backend, nullptr);\n"
        "                    ggml_threadpool_free(static_cast<ggml_threadpool *>(owned));\n"
        "                });\n"
        "                freebook_threadpool_qos_ = caller_qos;\n"
        "                debug::timing_log_scalar(\"vieneu_v3_turbo.threadpool_poll\", static_cast<int64_t>(freebook_threadpool_poll_));\n"
        "                debug::timing_log_scalar(\"vieneu_v3_turbo.threadpool_qos\", static_cast<int64_t>(caller_qos));\n"
        "            }\n"
        "        }\n"
        "    }\n",
        "đầu VieNeuTTSSession::run",
    )
    return text


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: vieneu_threadpool.py <thư mục nguồn audio.cpp>")
    root = pathlib.Path(sys.argv[1])
    files = {HEADER: patch_header, SESSION: patch_session, TALKER_HEADER: patch_talker_header, TALKER: patch_talker}
    texts = {rel: (root / rel).read_text(encoding="utf-8") for rel in files}
    if MARK in texts[SESSION]:
        print("[vieneu_threadpool] đã vá từ trước, bỏ qua")
        return
    patched = {rel: fn(texts[rel]) for rel, fn in files.items()}
    for rel, text in patched.items():
        (root / rel).write_text(text, encoding="utf-8")
    print("[vieneu_threadpool] đã vá " + ", ".join(files))


if __name__ == "__main__":
    main()
