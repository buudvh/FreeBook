#!/usr/bin/env bash
# Đo repack trọng số bộ giải mã âm học của VieNeu Turbo (bản vá vieneu_acoustic_repack, báo cáo tối ưu Turbo §16)
# trên runner macOS. (Lượt trước của script này đo threadpool — §15.)
#
# Build `audiocpp_cli` đúng cấu hình bản iOS (mọi bản vá của app, ggml-blas = Accelerate, cờ armv8.2-a+dotprod+fp16,
# không OpenMP / Metal) rồi chạy xen kẽ các cấu hình, cùng câu / giọng / seed (greedy):
#   base  = như app 1.3.929: codec_blas + prefill_blas + threadpool_poll=0
#   rp    = base + acoustic_repack=true (5 ma trận q8_0 của bộ giải mã âm học vào CPU_REPACK, kernel q8_0_4x4 dotprod)
# Ghi: thời gian từng phần (bộ đếm giờ có sẵn của audio.cpp qua --log-file), CPU-time tiến trình (/usr/bin/time),
# và so mã với base. Repack đổi thứ tự cộng fp32 ⇒ không trùng từng byte: chấm thêm logit của bộ giải mã âm học
# (VIENEU_LOGITS_DUMP) so với base tới khung đầu tiên lệch mã. Máy ảo không AMX ⇒ số tuyệt đối
# không nói gì về iPhone; chỉ so tương đối giữa các cấu hình trong cùng lượt.
set -uo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIOCPP_REF="${AUDIOCPP_REF:-$(tr -d '[:space:]' < "$CI_DIR/audiocpp_ref.txt")}"
WORK_DIR="${WORK_DIR:-build/audiocpp-profile}"
OUT_DIR="${OUT_DIR:-build/audiocpp-profile-out}"
REPEATS="${REPEATS:-1}"
ARM_ARCH="armv8.2-a+dotprod+fp16"
HF_REV="61b85e3d937fbbacb387714180e8182823512523"
HF_BASE="https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/$HF_REV/gguf"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 3)"
VOICES="mai_anh minh_quan_pro"
MODES="base rp"

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

# Câu mẫu của doc audio.cpp (~70 byte phiên âm) × 8 ≈ 560 byte ⇒ audio.cpp tự cắt ~3 đoạn ở 200 byte như app, ~20 s
# tiếng mỗi lượt ⇒ chi phí nạp model mỗi tiến trình (giống nhau ở mọi cấu hình) loãng đi trong CPU-time.
S="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
TEXT="$S $S $S $S $S $S $S $S"

run_one() {
  local mode="$1" voice="$2" rep="$3"
  local dir="$OUT_DIR/runs/${mode}__${voice}__r${rep}"
  mkdir -p "$dir"
  printf 'mode=%s\nvoice=%s\nrep=%s\n' "$mode" "$voice" "$rep" > "$dir/meta.txt"
  local -a extra=(--session-option vieneu_v3_turbo.codec_blas=true --session-option vieneu_v3_turbo.prefill_blas=true
    --session-option vieneu_v3_turbo.threadpool_poll=0)
  case "$mode" in
    rp) extra+=(--session-option vieneu_v3_turbo.acoustic_repack=true) ;;
  esac
  if ! /usr/bin/time -l "$CLI" --task tts --family vieneu_v3_turbo \
      --model "$WORK_DIR/model/turbo-q8_0.gguf" --backend cpu --threads 2 \
      --log-file "$dir/run.log" \
      --text "$TEXT" \
      --request-option reference_codes_file="$WORK_DIR/model/$voice/ref_codes.txt" \
      --request-option speaker_embedding_file="$WORK_DIR/model/$voice/speaker.emb.txt" \
      --request-option do_sample=false \
      --request-option seed=1 \
      --request-option babble_retries=0 \
      --request-option codes_dump_file="$dir/codes.txt" \
      "${extra[@]}" \
      --out "$dir/out.wav" > "$dir/stdout.txt" 2> "$dir/time.txt"; then
    echo "::warning::Lượt $mode/$voice/r$rep lỗi"
    tail -n 5 "$dir/time.txt" || true
    return 0
  fi
  echo "✓ $mode $voice r$rep"
}

# Hâm nóng (bỏ): đưa model vào page cache.
run_one base mai_anh 0
rm -rf "$OUT_DIR/runs/base__mai_anh__r0"

# Lặp ngoài cùng, cấu hình trong cùng ⇒ mỗi cấu hình rải đều theo thời gian (runner dùng chung lệch ±15–25%).
for rep in $(seq 1 "$REPEATS"); do
  for voice in $VOICES; do
    for mode in $MODES; do
      run_one "$mode" "$voice" "$rep"
    done
  done
done

# Chấm logit: một lượt mỗi cấu hình với VIENEU_LOGITS_DUMP (ghi logit 16 bước của mọi khung), cùng câu / giọng.
for mode in $MODES; do
  rm -f "$OUT_DIR/logits_$mode.txt"
  export VIENEU_LOGITS_DUMP="$OUT_DIR/logits_$mode.txt"
  run_one "$mode" mai_anh dump
  unset VIENEU_LOGITS_DUMP
done
python3 "$CI_DIR/audiocpp_profile/rp_logits_check.py" "$OUT_DIR/logits_base.txt" "$OUT_DIR/logits_rp.txt" \
  | tee "$OUT_DIR/logits_check.txt"
# Lượt dump không tính vào bảng tốc độ; file logit vài chục MB — chỉ giữ kết quả chấm.
rm -rf "$OUT_DIR"/runs/*__rdump
for mode in $MODES; do rm -f "$OUT_DIR/logits_$mode.txt"; done

python3 "$CI_DIR/audiocpp_profile/tp_summarize.py" "$OUT_DIR"
{ echo; echo '### Logit bộ giải mã âm học: rp so với base'; echo; echo '```'; cat "$OUT_DIR/logits_check.txt"; echo '```'; }   >> "$OUT_DIR/summary.md"
{ echo; echo '### Trọng số repack (log nạp)'; echo; echo '```';
  grep -h 'acoustic_repack.weights\|acoustic_decoder.repack.buffer' "$OUT_DIR"/runs/rp__mai_anh__r1/run.log | sort -u | head -n 6; echo '```'; }   >> "$OUT_DIR/summary.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$OUT_DIR/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
