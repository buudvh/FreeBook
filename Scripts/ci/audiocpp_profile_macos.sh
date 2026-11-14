#!/usr/bin/env bash
# Hướng 3 (báo cáo tối ưu Turbo §18): codec MOSS qua graph ONNX chính thức có ra đúng tiếng như codec audio.cpp
# không, độn khung cố định có giữ tiếng không, Core ML EP nhận bao nhiêu node. (Lượt trước: threadpool §15, repack §16,
# âm học 1 luồng.)
#
# Build `audiocpp_cli` đúng cấu hình bản iOS (mọi bản vá của app, ggml-blas = Accelerate, cờ armv8.2-a+dotprod+fp16,
# không OpenMP / Metal) rồi chạy xen kẽ các cấu hình, cùng câu / giọng / seed (greedy):
#   base  = như app 1.3.931: codec_blas + prefill_blas + threadpool_poll=0 + acoustic_repack
#   a1    = base, bộ giải mã âm học chạy 1 luồng (FREEBOOK_ACOUSTIC_THREADS=1) — phải trùng từng byte với base
# Ghi: thời gian từng phần (bộ đếm giờ có sẵn của audio.cpp qua --log-file), CPU-time tiến trình (/usr/bin/time),
# và so mã với base. Repack đổi thứ tự cộng fp32 ⇒ không trùng từng byte: chấm thêm logit của bộ giải mã âm học
# (VIENEU_LOGITS_DUMP) so với base tới khung đầu tiên lệch mã. Máy ảo không AMX ⇒ số tuyệt đối
# không nói gì về iPhone; chỉ so tương đối giữa các cấu hình trong cùng lượt.
set -uo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIOCPP_REF="${AUDIOCPP_REF:-$(tr -d '[:space:]' < "$CI_DIR/audiocpp_ref.txt")}"
WORK_DIR="${WORK_DIR:-build/audiocpp-profile}"
OUT_DIR="${OUT_DIR:-build/audiocpp-profile-out}"
REPEATS="${REPEATS:-3}"
ARM_ARCH="armv8.2-a+dotprod+fp16"
HF_REV="61b85e3d937fbbacb387714180e8182823512523"
HF_BASE="https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/$HF_REV/gguf"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 3)"
VOICES="mai_anh"
MODES="base a1"

rm -rf "$WORK_DIR" "$OUT_DIR"
mkdir -p "$WORK_DIR/model" "$OUT_DIR/runs"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

set -e
{
  echo "audio.cpp $AUDIOCPP_REF · cờ ARM $ARM_ARCH · runner $(sw_vers -productName) $(sw_vers -productVersion)"
  echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '?') · $(sysctl -n hw.ncpu) lõi logic"
} | tee "$OUT_DIR/env.txt"

git clone --depth 1 --branch "$AUDIOCPP_REF" --recurse-submodules --shallow-submodules \
  https://github.com/0xShug0/audio.cpp.git "$WORK_DIR/src"
for patch in vieneu_prefill_gallocr vieneu_codec_blas vieneu_prefill_blas vieneu_threadpool vieneu_acoustic_repack capi_log_file capi_abort_file; do
  python3 "$CI_DIR/audiocpp_patches/$patch.py" "$WORK_DIR/src"
done
python3 "$CI_DIR/audiocpp_profile/acoustic_threads_env.py" "$WORK_DIR/src"
cmake -S "$WORK_DIR/src" -B "$WORK_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DAUDIOCPP_DEPLOYMENT_BUILD=ON \
  -DAUDIOCPP_MODEL_SET=custom \
  -DAUDIOCPP_MODELS=vieneu_v3_turbo \
  -DENGINE_ENABLE_METAL=OFF \
  -DENGINE_ENABLE_OPENMP=OFF \
  -DENGINE_ENABLE_NATIVE_CPU=OFF \
  -DENGINE_ENABLE_CPU_ALL_VARIANTS=OFF \
  -DGGML_CPU_ARM_ARCH="$ARM_ARCH" \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple > "$WORK_DIR/configure.log" 2>&1 || { tail -n 60 "$WORK_DIR/configure.log" >&2; exit 1; }
cmake --build "$WORK_DIR/build" --target audiocpp_cli -j "$JOBS" > "$WORK_DIR/build.log" 2>&1 \
  || { grep -E 'error' "$WORK_DIR/build.log" | head -n 40 >&2; tail -n 40 "$WORK_DIR/build.log" >&2; exit 1; }
CLI="$(find "$WORK_DIR/build" -name audiocpp_cli -type f -perm -u+x | head -n 1)"
echo "cli: $CLI"

curl -fsSL -o "$WORK_DIR/model/turbo-q8_0.gguf" "$HF_BASE/vieneu-v3-turbo-q8_0.gguf"
for voice in $VOICES; do
  mkdir -p "$WORK_DIR/model/$voice"
  curl -fsSL -o "$WORK_DIR/model/$voice/ref_codes.txt" "$HF_BASE/voices/$voice/ref_codes.txt"
  curl -fsSL -o "$WORK_DIR/model/$voice/speaker.emb.txt" "$HF_BASE/voices/$voice/speaker.emb.txt"
done
set +e

# Ba độ dài, mỗi lượt một đoạn (text_chunk_size lớn) ⇒ mỗi run một dòng generated_codes ứng với cả WAV.
S="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
run_text() {
  local name="$1" text="$2"
  local dir="$OUT_DIR/runs/$name"
  mkdir -p "$dir"
  "$CLI" --task tts --family vieneu_v3_turbo \
    --model "$WORK_DIR/model/turbo-q8_0.gguf" --backend cpu --threads 2 \
    --log-file "$dir/run.log" --text "$text" \
    --request-option reference_codes_file="$WORK_DIR/model/mai_anh/ref_codes.txt" \
    --request-option speaker_embedding_file="$WORK_DIR/model/mai_anh/speaker.emb.txt" \
    --request-option do_sample=false --request-option seed=1 --request-option babble_retries=0 \
    --request-option text_chunk_size=1000 \
    --request-option codes_dump_file="$dir/codes.txt" \
    --session-option vieneu_v3_turbo.codec_blas=true --session-option vieneu_v3_turbo.prefill_blas=true \
    --session-option vieneu_v3_turbo.threadpool_poll=0 --session-option vieneu_v3_turbo.acoustic_repack=true \
    --out "$dir/out.wav" > "$dir/stdout.txt" 2>&1 || echo "::warning::run $name lỗi"
  echo "✓ $name: $(grep -c generated_codes "$dir/codes.txt" 2>/dev/null) đoạn"
}
run_text t1_short "$S"
run_text t2_medium "$S $S"
run_text t3_long "$S $S $S $S"

ONNX_REV="ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"
ONNX_BASE="https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX/resolve/$ONNX_REV"
mkdir -p "$WORK_DIR/onnx"
for f in moss_audio_tokenizer_decode_full.onnx moss_audio_tokenizer_decode_shared.data codec_browser_onnx_meta.json; do
  curl -fsSL -o "$WORK_DIR/onnx/$f" "$ONNX_BASE/$f"
done
# Python mặc định của runner có thể quá mới cho bánh onnxruntime ⇒ tìm 3.12/3.13 có sẵn, không có thì tải qua uv.
PYBIN=""
for candidate in /Users/runner/hostedtoolcache/Python/3.12*/arm64/bin/python3 \
                 /Users/runner/hostedtoolcache/Python/3.13*/arm64/bin/python3 \
                 "$(command -v python3.12 || true)" "$(command -v python3.13 || true)"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then PYBIN="$candidate"; break; fi
done
if [ -n "$PYBIN" ]; then
  "$PYBIN" -m venv "$WORK_DIR/venv"
else
  python3 -m pip install -q --user uv > "$WORK_DIR/uv.log" 2>&1 || tail -n 20 "$WORK_DIR/uv.log"
  "$(python3 -m site --user-base)/bin/uv" venv --python 3.12 "$WORK_DIR/venv" > "$WORK_DIR/uv.log" 2>&1 \
    || tail -n 20 "$WORK_DIR/uv.log"
  "$(python3 -m site --user-base)/bin/uv" pip install --python "$WORK_DIR/venv/bin/python" pip > /dev/null 2>&1 || true
fi
echo "python: $("$WORK_DIR/venv/bin/python" --version 2>&1)"
"$WORK_DIR/venv/bin/python" -m pip install -q onnxruntime numpy onnx > "$WORK_DIR/pip.log" 2>&1 || tail -n 20 "$WORK_DIR/pip.log"
"$WORK_DIR/venv/bin/python" "$CI_DIR/audiocpp_profile/codec_onnx_check.py" "$WORK_DIR/onnx" "$OUT_DIR/runs" \
  | tee "$OUT_DIR/summary.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$OUT_DIR/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
