#!/usr/bin/env bash
# P0a của báo cáo tối ưu VieNeu Turbo (Docs/Reports/2026-11-13-vieneu-turbo-toi-uu.md, gitignored): đo thời gian
# TỪNG PHẦN của Turbo trong audio.cpp trên runner macOS (Apple ARM) — nạp prompt, 1 lượt backbone mỗi khung, 16 bước
# bộ giải mã âm học mỗi khung, codec MOSS — để biết phần nào thật sự tốn thời gian trước khi chọn hướng tối ưu.
#
# Không đụng app, không đổi mã audio.cpp: build `audiocpp_cli` đúng cấu hình bản iOS (bản vá gallocr của app, CPU,
# không OpenMP / BLAS / Metal, cờ ARM `armv8.2-a+dotprod+fp16` như build_audiocpp_ios.sh) rồi bật bộ đếm giờ có sẵn
# của audio.cpp bằng `--log-file` (dòng `[TIMING …]`). Kèm:
# - microbench `cblas_sgemm` của Accelerate: một luồng vượt hẳn ~100 GFLOPS (trần NEON fp32 một lõi M1) ⇒ runner có
#   AMX ⇒ số đo hướng Accelerate trên CI mới có nghĩa;
# - vài lượt "đáp án fp32" của talker (`vieneu_v3_turbo.weight_type=f32`) để biết nó chạy được và chậm cỡ nào
#   (cổng chất lượng của P1).
#
# Biến môi trường (đều có mặc định): WORK_DIR, OUT_DIR, REPEATS (số lần lặp mỗi cấu hình greedy).
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIOCPP_REF="${AUDIOCPP_REF:-$(tr -d '[:space:]' < "$CI_DIR/audiocpp_ref.txt")}"
WORK_DIR="${WORK_DIR:-build/audiocpp-profile}"
OUT_DIR="${OUT_DIR:-build/audiocpp-profile-out}"
REPEATS="${REPEATS:-3}"
ARM_ARCH="armv8.2-a+dotprod+fp16"
HF_REV="61b85e3d937fbbacb387714180e8182823512523"
HF_BASE="https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/$HF_REV/gguf"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 3)"
# Giọng: Minh Quân Pro 68 khung mẫu (mặc định), Mai Anh 73 (giọng anh Bửu hay nghe), Adam bựa 91 (dài nhất hay dùng).
VOICES="minh_quan_pro mai_anh adam_bua"

rm -rf "$WORK_DIR" "$OUT_DIR"
mkdir -p "$WORK_DIR/model" "$OUT_DIR/runs"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# ---- Máy ---------------------------------------------------------------------------------------------------------
{
  echo "audio.cpp $AUDIOCPP_REF · cờ ARM $ARM_ARCH · runner $(sw_vers -productName) $(sw_vers -productVersion)"
  echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo '?') · $(sysctl -n hw.ncpu) lõi logic · RAM $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
  echo "FEAT_DotProd=$(sysctl -n hw.optional.arm.FEAT_DotProd 2>/dev/null || echo '?') FEAT_FP16=$(sysctl -n hw.optional.arm.FEAT_FP16 2>/dev/null || echo '?') FEAT_I8MM=$(sysctl -n hw.optional.arm.FEAT_I8MM 2>/dev/null || echo '?')"
} | tee "$OUT_DIR/env.txt"

# ---- Microbench Accelerate (kiểm AMX) ----------------------------------------------------------------------------
xcrun clang -O2 -framework Accelerate "$CI_DIR/audiocpp_profile/sgemm_bench.c" -o "$WORK_DIR/sgemm_bench"
{
  VECLIB_MAXIMUM_THREADS=1 "$WORK_DIR/sgemm_bench"
  echo
  "$WORK_DIR/sgemm_bench"
} | tee "$OUT_DIR/sgemm.txt"

# ---- Build audiocpp_cli như bản iOS ------------------------------------------------------------------------------
git clone --depth 1 --branch "$AUDIOCPP_REF" --recurse-submodules --shallow-submodules \
  https://github.com/0xShug0/audio.cpp.git "$WORK_DIR/src"
python3 "$CI_DIR/audiocpp_patches/vieneu_prefill_gallocr.py" "$WORK_DIR/src"
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
  -DGGML_BLAS=OFF > "$WORK_DIR/configure.log" 2>&1 || { tail -n 60 "$WORK_DIR/configure.log" >&2; exit 1; }
cmake --build "$WORK_DIR/build" --target audiocpp_cli -j "$JOBS" > "$WORK_DIR/build.log" 2>&1 \
  || { grep -E 'error' "$WORK_DIR/build.log" | head -n 40 >&2; tail -n 40 "$WORK_DIR/build.log" >&2; exit 1; }
CLI="$(find "$WORK_DIR/build" -name audiocpp_cli -type f -perm -u+x | head -n 1)"
echo "cli: $CLI"
grep -E 'llamafile|LLAMAFILE|ARM_ARCH|march' "$WORK_DIR/configure.log" | head -n 10 || true

# ---- Model + giọng -----------------------------------------------------------------------------------------------
curl -fsSL -o "$WORK_DIR/model/turbo-q8_0.gguf" "$HF_BASE/vieneu-v3-turbo-q8_0.gguf"
for voice in $VOICES; do
  mkdir -p "$WORK_DIR/model/$voice"
  curl -fsSL -o "$WORK_DIR/model/$voice/ref_codes.txt" "$HF_BASE/voices/$voice/ref_codes.txt"
  curl -fsSL -o "$WORK_DIR/model/$voice/speaker.emb.txt" "$HF_BASE/voices/$voice/speaker.emb.txt"
done

# Câu mẫu trong doc của audio.cpp (đã là phiên âm sea-g2p, ~52 ký tự). "vua" ≈ một đoạn ~100 chữ của trình đọc
# (`vieneuChunk` mặc định 100 ⇒ ~110 ký tự phiên âm); "dai" = gấp đôi, để thấy đoạn dài hơn đổi tỉ lệ thế nào.
SHORT="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
text_for() {
  case "$1" in
    ngan) echo "$SHORT" ;;
    vua) echo "$SHORT $SHORT" ;;
    dai) echo "$SHORT $SHORT $SHORT $SHORT" ;;
  esac
}

# Một lượt = một tiến trình CLI = một đoạn (`text_chunk_size=1000` ⇒ audio.cpp không tự cắt). Lượt lỗi chỉ cảnh báo:
# thiếu một ô trong bảng vẫn hơn mất cả lượt đo.
run_one() {
  local mode="$1" voice="$2" text="$3" threads="$4" rep="$5"
  local dir="$OUT_DIR/runs/${mode}__${voice}__${text}__t${threads}__r${rep}"
  mkdir -p "$dir"
  printf 'mode=%s\nvoice=%s\ntext=%s\nthreads=%s\nrep=%s\n' "$mode" "$voice" "$text" "$threads" "$rep" > "$dir/meta.txt"
  local -a extra=()
  case "$mode" in
    greedy) extra=(--request-option do_sample=false --request-option seed=1 --request-option babble_retries=0) ;;
    sample) extra=(--request-option seed=7) ;;
    # Chỉ talker: codec MOSS vốn đã nạp trọng số transformer thành F32 (`MossAudioTokenizerCodecRuntimeOptions`
    # mặc định), còn `speech_decoder_weight_type` ở v0.9.4 chỉ được kiểm chứ không truyền xuống codec.
    f32) extra=(--request-option do_sample=false --request-option seed=1 --request-option babble_retries=0
                --session-option vieneu_v3_turbo.weight_type=f32) ;;
  esac
  if ! /usr/bin/time -l "$CLI" --task tts --family vieneu_v3_turbo \
      --model "$WORK_DIR/model/turbo-q8_0.gguf" --backend cpu --threads "$threads" \
      --log-file "$dir/run.log" \
      --text "$(text_for "$text")" \
      --request-option reference_codes_file="$WORK_DIR/model/$voice/ref_codes.txt" \
      --request-option speaker_embedding_file="$WORK_DIR/model/$voice/speaker.emb.txt" \
      --request-option text_chunk_size=1000 \
      --request-option codes_dump_file="$dir/codes.txt" \
      "${extra[@]}" \
      --out "$dir/out.wav" > "$dir/stdout.txt" 2> "$dir/time.txt"; then
    echo "::warning::Lượt $mode/$voice/$text/t$threads/r$rep lỗi — xem $dir/time.txt"
    tail -n 5 "$dir/time.txt" || true
    return 0
  fi
  echo "✓ $mode $voice $text t$threads r$rep: $(grep -c . "$dir/run.log" 2>/dev/null || echo 0) dòng log"
}

# Lượt hâm nóng (bỏ): đưa file model vào page cache, để lượt đầu không chịu phí đọc đĩa.
run_one greedy minh_quan_pro ngan 2 0
rm -rf "$OUT_DIR/runs/greedy__minh_quan_pro__ngan__t2__r0"

# Vòng lặp ngoài cùng là lần lặp ⇒ mỗi cấu hình rải đều theo thời gian, runner chậm dần không dồn vào một ô.
for rep in $(seq 1 "$REPEATS"); do
  for voice in $VOICES; do
    for text in ngan vua dai; do
      run_one greedy "$voice" "$text" 2 "$rep"
    done
  done
  # 1 luồng: phần nào ăn theo số luồng (gợi ý cho "bước âm học chạy 1 luồng").
  run_one greedy minh_quan_pro vua 1 "$rep"
done
# Lấy mẫu như trình đọc: đếm lượt sinh lại (chạm trần khung / nghi nói lan).
for rep in 1 2; do
  for voice in $VOICES; do
    run_one sample "$voice" vua 2 "$rep"
  done
done
# Đáp án fp32 (cổng chất lượng P1): chạy được không, chậm cỡ nào.
run_one f32 minh_quan_pro ngan 2 1
run_one f32 minh_quan_pro vua 2 1

python3 "$CI_DIR/audiocpp_profile/summarize.py" "$OUT_DIR"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$OUT_DIR/summary.md" >> "$GITHUB_STEP_SUMMARY"
fi
