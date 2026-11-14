#!/usr/bin/env python3
"""CHỈ ĐỂ ĐO (nhánh claude/turbo-tp-profile): biến môi trường `FREEBOOK_ACOUSTIC_THREADS=N` ép số luồng của bộ giải mã âm
học VieNeu Turbo (graph nạp 2 vị trí + 16 graph từng bước của `CodePredictorGraph`). Không có biến ⇒ như cũ (số luồng
của talker). Mỗi phần tử kết quả của mul_mat / repack gemv do đúng một luồng tính ⇒ đổi số luồng phải trùng từng bit.
Dùng: python3 acoustic_threads_env.py <thư mục nguồn audio.cpp>   (sau vieneu_acoustic_repack.py)
"""
import pathlib
import sys

TALKER = "src/community_models/vieneu_v3_turbo/talker.cpp"
HELPER = (
    "// FREEBOOK_MEASURE_ACOUSTIC_THREADS: FREEBOOK_ACOUSTIC_THREADS=N overrides the code predictor's thread count.\n"
    "int freebook_acoustic_threads(int fallback) {\n"
    "    static const int forced = [] {\n"
    "        const char * value = std::getenv(\"FREEBOOK_ACOUSTIC_THREADS\");\n"
    "        return value != nullptr ? std::atoi(value) : 0;\n"
    "    }();\n"
    "    return forced > 0 ? std::min(forced, fallback) : fallback;\n"
    "}\n\n"
    "class CodePredictorGraph {\n"
)


def replace_once(text, old, new, label):
    if text.count(old) != 1:
        sys.exit(f"[acoustic_threads_env] mốc '{label}' khớp {text.count(old)} lần")
    return text.replace(old, new, 1)


def main():
    path = pathlib.Path(sys.argv[1]) / TALKER
    text = path.read_text(encoding="utf-8")
    text = replace_once(text, "class CodePredictorGraph {\n", HELPER, "class CodePredictorGraph")
    for graph in ("prefill_graph_", "step_graph.graph"):
        text = replace_once(
            text,
            "        core::set_backend_threads(weights_->backend(), weights_->threads());\n"
            "        timing_start = Clock::now();\n"
            "        const ggml_status status = engine::core::compute_backend_graph(weights_->backend(), " + graph + ");\n",
            "        core::set_backend_threads(weights_->backend(), freebook_acoustic_threads(weights_->threads()));\n"
            "        timing_start = Clock::now();\n"
            "        const ggml_status status = engine::core::compute_backend_graph(weights_->backend(), " + graph + ");\n",
            graph,
        )
    path.write_text(text, encoding="utf-8")
    print("[acoustic_threads_env] đã vá " + TALKER)


if __name__ == "__main__":
    main()
