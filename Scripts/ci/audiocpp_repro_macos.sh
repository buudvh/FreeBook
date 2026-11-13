#!/usr/bin/env bash
# Tái hiện lỗi 1.3.924 trên runner macOS: bật codec qua Accelerate (`vieneu_v3_turbo.codec_blas`) làm app chết trên
# iPhone ở lượt tổng hợp đầu tiên, trong khi job parity (CLI, cờ CPU native, luồng chính) không sập.
# Thử từng khác biệt giữa CI và iPhone, mỗi ca một tiến trình riêng (ca nào chết không che ca khác):
#   - cờ CPU đúng bản iOS (`armv8.2-a+dotprod+fp16`, không native) cho cả CLI lẫn thư viện C API;
#   - gọi C API y như app (Scripts/ci/audiocpp_repro/amx_repro.c) ở luồng chính / hàng đợi GCD / pthread stack 512 KB;
#   - lấy mẫu như trình đọc, đoạn dài tới ~5 lần câu mẫu (audio.cpp tự cắt ở 200 byte như app), 3 giọng.
# Bản vá capi_abort_file ghi câu báo của GGML_ASSERT ra file ⇒ in kèm khi một ca chết. Chỉ chẩn đoán: luôn exit 0,
# kết quả ở log + tóm tắt của job.
set -uo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIOCPP_REF="${AUDIOCPP_REF:-$(tr -d '[:space:]' < "$CI_DIR/audiocpp_ref.txt")}"
WORK_DIR="${WORK_DIR:-build/audiocpp-repro}"
HF_REV="61b85e3d937fbbacb387714180e8182823512523"
HF_BASE="https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/$HF_REV/gguf"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 3)"
ARM_ARCH="armv8.2-a+dotprod+fp16"
VOICES="mai_anh minh_quan_pro adam_bua"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/model" "$WORK_DIR/out"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
SUMMARY="$WORK_DIR/out/summary.md"

set -e
git clone --depth 1 --branch "$AUDIOCPP_REF" --recurse-submodules --shallow-submodules \
  https://github.com/0xShug0/audio.cpp.git "$WORK_DIR/src"
for patch in vieneu_prefill_gallocr vieneu_codec_blas capi_log_file capi_abort_file; do
  python3 "$CI_DIR/audiocpp_patches/$patch.py" "$WORK_DIR/src"
done
cmake -S "$WORK_DIR/src" -B "$WORK_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DAUDIOCPP_BUILD_C_API=ON \
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
cmake --build "$WORK_DIR/build" --target audiocpp audiocpp_cli -j "$JOBS" > "$WORK_DIR/build.log" 2>&1 \
  || { grep -E 'error' "$WORK_DIR/build.log" | head -n 40 >&2; tail -n 40 "$WORK_DIR/build.log" >&2; exit 1; }
CLI="$(find "$WORK_DIR/build" -name audiocpp_cli -type f -perm -u+x | head -n 1)"
DYLIB="$(find "$WORK_DIR/build" -name 'libaudiocpp*.dylib' -type f | head -n 1)"
echo "cli: $CLI"
echo "dylib: $DYLIB"
xcrun clang -O1 -fblocks -I "$WORK_DIR/src/include" "$CI_DIR/audiocpp_repro/amx_repro.c" "$DYLIB" \
  -Wl,-rpath,"$(dirname "$DYLIB")" -o "$WORK_DIR/amx_repro"

curl -fsSL -o "$WORK_DIR/model/turbo-q8_0.gguf" "$HF_BASE/vieneu-v3-turbo-q8_0.gguf"
for voice in $VOICES; do
  mkdir -p "$WORK_DIR/model/$voice"
  curl -fsSL -o "$WORK_DIR/model/$voice/ref_codes.txt" "$HF_BASE/voices/$voice/ref_codes.txt"
  curl -fsSL -o "$WORK_DIR/model/$voice/speaker.emb.txt" "$HF_BASE/voices/$voice/speaker.emb.txt"
done
set +e

# Câu mẫu của doc audio.cpp (phiên âm sea-g2p, ~70 byte). T1 = 1 lần … T5 = 5 lần (~350 byte ⇒ audio.cpp cắt 2 đoạn).
S="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
T1="$S"
T2="$S $S"
T3="$S $S $S"
T4="$S $S $S $S"
T5="$S $S $S $S $S"

{
  echo "## Tái hiện sập codec AMX (1.3.924)"
  echo
  echo "| Ca | Kết quả | Ghi chú |"
  echo "|---|---|---|"
} > "$SUMMARY"

# $1 tên ca · còn lại: lệnh. Ghi exit code (128+N = chết vì tín hiệu N) + câu báo abort nếu có.
run_case() {
  local name="$1"
  shift
  local abort_file="$WORK_DIR/out/$name.abort.txt"
  rm -f "$abort_file"
  "$@" > "$WORK_DIR/out/$name.log" 2>&1
  local rc=$?
  local result note
  if [ "$rc" -eq 0 ]; then
    result="✓ chạy hết"
  elif [ "$rc" -gt 128 ]; then
    result="💥 chết (tín hiệu $((rc - 128)))"
    echo "::error::$name: tiến trình chết, tín hiệu $((rc - 128))"
  else
    result="⚠️ lỗi (exit $rc)"
  fi
  note="$(tail -n 2 "$WORK_DIR/out/$name.log" | tr '\n' ' ' | cut -c1-200)"
  if [ -s "$abort_file" ]; then
    note="abort: $(tr '\n' ' ' < "$abort_file" | cut -c1-300)"
  fi
  echo "$name: $result — $note"
  echo "| $name | $result | ${note//|//} |" >> "$SUMMARY"
  echo "----- $name (cuối log) -----"
  tail -n 25 "$WORK_DIR/out/$name.log"
}

harness() {
  local mode="$1" blas="$2" voice="$3"
  shift 3
  run_case "harness_${mode}_blas${blas}_${voice}_$#cau" \
    "$WORK_DIR/amx_repro" "$WORK_DIR/model/turbo-q8_0.gguf" \
    "$WORK_DIR/model/$voice/ref_codes.txt" "$WORK_DIR/model/$voice/speaker.emb.txt" \
    "$mode" "$blas" "$WORK_DIR/out/harness_${mode}_blas${blas}_${voice}_$#cau.abort.txt" "$@"
}

# 1. CLI cờ iOS, luồng chính, bật codec_blas — khác parity chỉ ở cờ CPU.
for t in 1 2 4; do
  var="T$t"
  run_case "cli_ios_flags_blas1_T$t" "$CLI" --task tts --family vieneu_v3_turbo \
    --model "$WORK_DIR/model/turbo-q8_0.gguf" --backend cpu --threads 2 \
    --text "${!var}" \
    --request-option reference_codes_file="$WORK_DIR/model/mai_anh/ref_codes.txt" \
    --request-option speaker_embedding_file="$WORK_DIR/model/mai_anh/speaker.emb.txt" \
    --request-option seed=7 \
    --session-option vieneu_v3_turbo.codec_blas=true \
    --out "$WORK_DIR/out/cli_T$t.wav"
done

# 2. Gọi C API như app: luồng chính / GCD / pthread 512 KB, bật codec_blas; ca đối chứng GCD tắt.
harness main 1 mai_anh "$T1" "$T2" "$T3" "$T4" "$T5"
harness gcd 1 mai_anh "$T1" "$T2" "$T3" "$T4" "$T5"
harness pthread 1 mai_anh "$T1" "$T2" "$T3" "$T4" "$T5"
harness gcd 0 mai_anh "$T1" "$T2" "$T3" "$T4" "$T5"
for voice in minh_quan_pro adam_bua; do
  harness gcd 1 "$voice" "$T2" "$T4"
done

echo
cat "$SUMMARY"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
