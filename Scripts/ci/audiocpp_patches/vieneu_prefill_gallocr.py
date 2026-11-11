#!/usr/bin/env python3
"""Vá `TalkerPrefillGraph` của audio.cpp (family vieneu_v3_turbo) cho đỡ tốn bộ nhớ trên iPhone.

Vấn đề (audio.cpp v0.9.4, `src/community_models/vieneu_v3_turbo/talker.cpp`): bước nạp prompt dựng graph 12 lớp
rồi gọi `ggml_backend_alloc_ctx_tensors` — cấp phát **riêng** cho MỌI tensor trung gian (điểm attention S×S của
từng lớp, MLP…), không tái sử dụng; graph lại dựng mới mỗi khi độ dài prompt đổi (gần như mỗi đoạn). Trên máy thật
lỗi `failed to allocate VieNeu-TTS talker prefill graph` sau ~35 đoạn.

Cách vá — phép tính giữ nguyên, chỉ đổi chỗ đặt bộ nhớ:
- Đầu vào (`input_`, `positions_`) và các tensor mà `run_with_state` đọc ra sau khi tính (K/V từng lớp, hidden,
  logits) đặt trong một context nhỏ riêng `io_ctx_`, cấp phát cố định. Kết quả được `ggml_cpy` từ graph sang các
  tensor đích này ⇒ không phụ thuộc chuyện tensor nguồn có bị ghi đè hay không.
- Toàn bộ tensor trung gian còn lại do `ggml_gallocr` cấp phát: nó tái sử dụng vùng nhớ của tensor đã dùng xong,
  nên đỉnh bộ nhớ chỉ còn cỡ vài lớp thay vì cả 12 lớp. gallocr không bao giờ ghi lên tensor đã có buffer (trọng số,
  hằng số, `io_ctx_`).

Script sửa bằng các mốc chuỗi cố định; mốc nào không khớp đúng một lần ⇒ dừng với lỗi (thà build đỏ còn hơn vá lệch).
Dùng: python3 vieneu_prefill_gallocr.py <thư mục nguồn audio.cpp>
"""
import pathlib
import sys

REL = "src/community_models/vieneu_v3_turbo/talker.cpp"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f"[vieneu_prefill_gallocr] mốc '{label}' khớp {count} lần (cần đúng 1) — audio.cpp đã đổi, phải xem lại bản vá")
    return text.replace(old, new, 1)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 2:
        sys.exit("Dùng: vieneu_prefill_gallocr.py <thư mục nguồn audio.cpp>")
    path = pathlib.Path(sys.argv[1]) / REL
    text = path.read_text(encoding="utf-8")
    if "FREEBOOK_PATCH_PREFILL_GALLOCR" in text:
        print("[vieneu_prefill_gallocr] đã vá từ trước, bỏ qua")
        return

    text = replace_once(
        text,
        "#include <ggml-backend.h>\n",
        "#include <ggml-backend.h>\n#include <ggml-alloc.h>  // FREEBOOK_PATCH_PREFILL_GALLOCR\n",
        "include ggml-backend.h",
    )

    # 1. Đầu vào sang io_ctx_.
    text = replace_once(
        text,
        """        core::ModuleBuildContext ctx{ctx_.get(), "vieneu_v3_turbo.talker.prefill"};
        auto x = core::make_tensor(ctx, GGML_TYPE_F32, core::TensorShape::from_dims({1, prompt_capacity_, config.hidden_size}));
        input_ = x.tensor;
        positions_ = ggml_new_tensor_1d(ctx_.get(), GGML_TYPE_I32, prompt_capacity_);""",
        """        core::ModuleBuildContext ctx{ctx_.get(), "vieneu_v3_turbo.talker.prefill"};
        // FREEBOOK_PATCH_PREFILL_GALLOCR: đầu vào + tensor đọc ra nằm ở io_ctx_ (cấp phát cố định, nhỏ).
        ggml_init_params io_params{ggml_tensor_overhead() * 256, nullptr, true};
        io_ctx_.reset(ggml_init(io_params));
        if (io_ctx_ == nullptr) {
            throw std::runtime_error("failed to initialize VieNeu-TTS talker prefill io context");
        }
        core::ModuleBuildContext io{io_ctx_.get(), "vieneu_v3_turbo.talker.prefill.io"};
        auto x = core::make_tensor(io, GGML_TYPE_F32, core::TensorShape::from_dims({1, prompt_capacity_, config.hidden_size}));
        input_ = x.tensor;
        positions_ = ggml_new_tensor_1d(io_ctx_.get(), GGML_TYPE_I32, prompt_capacity_);""",
        "prefill inputs",
    )

    # 2. K/V, hidden, logits: chép sang tensor đích trong io_ctx_; dựng graph kèm các nút chép; gallocr cấp phát.
    text = replace_once(
        text,
        """        for (const auto & layer : decoder_out.state.layers) {
            if (!layer.key.has_value() || !layer.value.has_value()) {
                throw std::runtime_error("VieNeu-TTS talker prefill decoder did not return K/V state");
            }
            keys_.push_back(layer.key->tensor);
            values_.push_back(layer.value->tensor);
        }
        hidden_output_ = decoder_out.hidden.tensor;
        logits_output_ = decoder_out.logits.tensor;
        ggml_set_output(logits_output_);
        graph_ = ggml_new_graph_custom(ctx_.get(), 65536, false);
        ggml_build_forward_expand(graph_, logits_output_);
        constants.finish_graph();
        constants.ensure_uploaded();
        buffer_ = ggml_backend_alloc_ctx_tensors(ctx_.get(), weights_->backend());
        if (buffer_ == nullptr) {
            throw std::runtime_error("failed to allocate VieNeu-TTS talker prefill graph");
        }""",
        """        std::vector<ggml_tensor *> copy_nodes;
        auto copy_out = [&](ggml_tensor * source) {
            ggml_tensor * destination = ggml_dup_tensor(io_ctx_.get(), source);
            copy_nodes.push_back(ggml_cpy(ctx_.get(), source, destination));
            return destination;
        };
        for (const auto & layer : decoder_out.state.layers) {
            if (!layer.key.has_value() || !layer.value.has_value()) {
                throw std::runtime_error("VieNeu-TTS talker prefill decoder did not return K/V state");
            }
            keys_.push_back(copy_out(layer.key->tensor));
            values_.push_back(copy_out(layer.value->tensor));
        }
        hidden_output_ = copy_out(decoder_out.hidden.tensor);
        logits_output_ = copy_out(decoder_out.logits.tensor);
        graph_ = ggml_new_graph_custom(ctx_.get(), 65536, false);
        for (ggml_tensor * node : copy_nodes) {
            ggml_build_forward_expand(graph_, node);
        }
        constants.finish_graph();
        constants.ensure_uploaded();
        buffer_ = ggml_backend_alloc_ctx_tensors(io_ctx_.get(), weights_->backend());
        if (buffer_ == nullptr) {
            throw std::runtime_error("failed to allocate VieNeu-TTS talker prefill io tensors");
        }
        allocr_ = ggml_gallocr_new(ggml_backend_get_default_buffer_type(weights_->backend()));
        if (allocr_ == nullptr || !ggml_gallocr_alloc_graph(allocr_, graph_)) {
            if (allocr_ != nullptr) {
                ggml_gallocr_free(allocr_);
                allocr_ = nullptr;
            }
            ggml_backend_buffer_free(buffer_);
            buffer_ = nullptr;
            throw std::runtime_error("failed to allocate VieNeu-TTS talker prefill graph");
        }""",
        "prefill outputs + allocation",
    )

    # 3. Giải phóng gallocr.
    text = replace_once(
        text,
        """    ~TalkerPrefillGraph() {
        engine::core::release_backend_graph_resources(weights_->backend(), graph_);
        if (buffer_ != nullptr) {""",
        """    ~TalkerPrefillGraph() {
        engine::core::release_backend_graph_resources(weights_->backend(), graph_);
        if (allocr_ != nullptr) {
            ggml_gallocr_free(allocr_);
        }
        if (buffer_ != nullptr) {""",
        "prefill destructor",
    )

    # 4. Thành viên mới. `io_ctx_` khai sau `ctx_` ⇒ huỷ trước `ctx_` (thứ tự ngược khai báo), sau khi buffer đã free.
    text = replace_once(
        text,
        """    std::unique_ptr<ggml_context, GgmlContextDeleter> ctx_;
    ggml_tensor * input_ = nullptr;
    ggml_tensor * positions_ = nullptr;
    ggml_tensor * hidden_output_ = nullptr;
    ggml_tensor * logits_output_ = nullptr;
    std::vector<ggml_tensor *> keys_;
    std::vector<ggml_tensor *> values_;
    ggml_cgraph * graph_ = nullptr;
    ggml_backend_buffer_t buffer_ = nullptr;
};

class TalkerCachedStepGraph {""",
        """    std::unique_ptr<ggml_context, GgmlContextDeleter> ctx_;
    std::unique_ptr<ggml_context, GgmlContextDeleter> io_ctx_;
    ggml_tensor * input_ = nullptr;
    ggml_tensor * positions_ = nullptr;
    ggml_tensor * hidden_output_ = nullptr;
    ggml_tensor * logits_output_ = nullptr;
    std::vector<ggml_tensor *> keys_;
    std::vector<ggml_tensor *> values_;
    ggml_cgraph * graph_ = nullptr;
    ggml_backend_buffer_t buffer_ = nullptr;
    ggml_gallocr_t allocr_ = nullptr;
};

class TalkerCachedStepGraph {""",
        "prefill members",
    )

    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(f"[vieneu_prefill_gallocr] đã vá {REL}")


if __name__ == "__main__":
    main()
