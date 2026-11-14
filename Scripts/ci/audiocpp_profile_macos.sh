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
VOICES="mai_anh minh_quan_pro"
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

# Ngữ cảnh mô tả tensor của audio.cpp: mặc định giữ chỗ hàng GB địa chỉ ảo (talker constants 4 GB, code predictor
# 1,5 GB, codec weights 1,5 GB × 2) — trên iPhone cộng Nano là vượt giới hạn địa chỉ ảo ⇒ app sập (log 20, build 1270).
# So cấu hình app (base) với base + ba option hạ còn 64 MB (mức sàn audio.cpp tự đặt): tiếng phải trùng từng byte.
S="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
APP=(--session-option vieneu_v3_turbo.codec_blas=true --session-option vieneu_v3_turbo.prefill_blas=true
     --session-option vieneu_v3_turbo.threadpool_poll=0 --session-option vieneu_v3_turbo.acoustic_repack=true)
SMALL=(--session-option vieneu_v3_turbo.talker_constant_context_mb=64
       --session-option vieneu_v3_turbo.code_predictor_constant_context_mb=64
       --session-option vieneu_v3_turbo.speech_decoder_constant_context_mb=64)
run_case() {
  local name="$1" voice="$2" text="$3"
  shift 3
  local dir="$OUT_DIR/runs/$name"
  mkdir -p "$dir"
  /usr/bin/time -l "$CLI" --task tts --family vieneu_v3_turbo \
    --model "$WORK_DIR/model/turbo-q8_0.gguf" --backend cpu --threads 2 \
    --log-file "$dir/run.log" --text "$text" \
    --request-option reference_codes_file="$WORK_DIR/model/$voice/ref_codes.txt" \
    --request-option speaker_embedding_file="$WORK_DIR/model/$voice/speaker.emb.txt" \
    --request-option do_sample=false --request-option seed=1 --request-option babble_retries=0 \
    --request-option codes_dump_file="$dir/codes.txt" \
    "${APP[@]}" "$@" --out "$dir/out.wav" > "$dir/stdout.txt" 2> "$dir/time.txt" \
    || { echo "::error::run $name lỗi"; tail -n 8 "$dir/time.txt"; }
}
TEXTS=("$S" "$S $S $S $S" "$S $S $S $S $S $S $S $S")
FAIL=0
{
  echo "## Ngữ cảnh audio.cpp 64 MB so với mặc định"
  echo
  echo "| Câu | Giọng | Mã + WAV trùng | RSS mặc định (MB) | RSS 64 MB (MB) |"
  echo "|---|---|---|---|---|"
} > "$OUT_DIR/summary.md"
for voice in $VOICES; do
  for index in 0 1 2; do
    run_case "base_${voice}_$index" "$voice" "${TEXTS[$index]}"
    run_case "small_${voice}_$index" "$voice" "${TEXTS[$index]}" "${SMALL[@]}"
    a="$OUT_DIR/runs/base_${voice}_$index"; b="$OUT_DIR/runs/small_${voice}_$index"
    same="KHÔNG"
    if cmp -s "$a/codes.txt" "$b/codes.txt" && cmp -s "$a/out.wav" "$b/out.wav"; then same="trùng"; else FAIL=1; fi
    rss_a=$(awk '/maximum resident set size/ {print int($1/1048576)}' "$a/time.txt")
    rss_b=$(awk '/maximum resident set size/ {print int($1/1048576)}' "$b/time.txt")
    echo "| $((index + 1)) | $voice | $same | ${rss_a:-?} | ${rss_b:-?} |" >> "$OUT_DIR/summary.md"
  done
done
{
  echo
  echo "### Giữ chỗ ngữ cảnh (log audio.cpp)"
  echo
  echo '```'
  echo "-- mặc định --"
  grep -h "ctx_reserved_mb\|ctx_used_mb\|constant" "$OUT_DIR/runs/base_mai_anh_2/run.log" | sed 's/\[TIMING ts=[^]]*\] //' | sort -u | head -20
  echo "-- 64 MB --"
  grep -h "ctx_reserved_mb\|ctx_used_mb\|constant" "$OUT_DIR/runs/small_mai_anh_2/run.log" | sed 's/\[TIMING ts=[^]]*\] //' | sort -u | head -20
  echo '```'
} >> "$OUT_DIR/summary.md"
cat "$OUT_DIR/summary.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$OUT_DIR/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
[ "$FAIL" = 0 ] || echo "::error::hạ ngữ cảnh làm đổi tiếng"
exit 0
