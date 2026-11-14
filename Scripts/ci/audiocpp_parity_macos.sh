#!/usr/bin/env bash
# Kiểm bản vá audio.cpp của app (Scripts/ci/audiocpp_patches/) không đổi tiếng: build `audiocpp_cli` cho macOS hai
# lần — bản gốc và bản vá — đọc cùng các chuỗi phiên âm bằng VieNeu Turbo GGUF q8_0 với **greedy** (`do_sample=false`,
# seed cố định, tắt babble guard), rồi so **mã âm thanh** (`codes_dump_file`) và file WAV từng byte. Lệch ⇒ exit 1.
# Kèm đo RAM tối đa (`/usr/bin/time -l`) của từng bản để thấy bản vá bớt được bao nhiêu.
#
# Bản vá build kèm ggml-blas (Accelerate) như bản iOS. Thêm một phép so cho bản vá `vieneu_codec_blas`: cùng bản vá,
# bật `vieneu_v3_turbo.codec_blas` ⇒ mã âm thanh phải trùng (talker không đổi), WAV ≥ 90 dB so với khi tắt (chỉ đổi
# thứ tự cộng fp32 — Nano đo 99–136 dB), và log phải báo codec thật sự chạy qua BLAS. Runner là máy ảo không có AMX
# ⇒ phép này chỉ kiểm ĐÚNG SỐ, không kiểm tốc độ (tốc độ đo trên iPhone).
#
# Bản vá `vieneu_threadpool` (1.3.929): cấu hình của app (codec_blas + prefill_blas) thêm `threadpool_poll=0` ⇒ mã
# và WAV phải trùng TỪNG BYTE với khi không có (cùng số luồng ⇒ cùng cách chia việc), log phải báo đã tạo pool.
#
# Bản vá `vieneu_acoustic_repack` (1.3.930): cấu hình app 1.3.929 thêm `acoustic_repack=true` ⇒ log phải báo đủ 5 ma
# trận nằm trong CPU_REPACK, mã greedy + WAV phải trùng (logit chỉ lệch cỡ một nấc lượng tử q8 ở vài bước — đo CI
# 2026-11-14: greedy trùng hết trên 237 khung).
#
# Chạy trên runner macOS (CPU, không Metal, không OpenMP — giống bản iOS). Tải model ~188 MB từ HF (revision ghim).
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIOCPP_REF="${AUDIOCPP_REF:-$(tr -d '[:space:]' < "$CI_DIR/audiocpp_ref.txt")}"
WORK_DIR="${WORK_DIR:-build/audiocpp-parity}"
HF_REV="61b85e3d937fbbacb387714180e8182823512523"
HF_BASE="https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/$HF_REV/gguf"
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 3)"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/model/voice" "$WORK_DIR/out"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

git clone --depth 1 --branch "$AUDIOCPP_REF" --recurse-submodules --shallow-submodules \
  https://github.com/0xShug0/audio.cpp.git "$WORK_DIR/src_base"
cp -R "$WORK_DIR/src_base" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/vieneu_prefill_gallocr.py" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/vieneu_codec_blas.py" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/vieneu_prefill_blas.py" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/vieneu_threadpool.py" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/vieneu_acoustic_repack.py" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/capi_log_file.py" "$WORK_DIR/src_patched"
python3 "$CI_DIR/audiocpp_patches/capi_abort_file.py" "$WORK_DIR/src_patched"

# Tham số 3: ON = build kèm ggml-blas / Accelerate (như bản iOS từ bản vá vieneu_codec_blas), OFF = như upstream.
build_cli() {
  local src="$1" build="$2" blas="$3"
  cmake -S "$src" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DAUDIOCPP_DEPLOYMENT_BUILD=ON \
    -DAUDIOCPP_MODEL_SET=custom \
    -DAUDIOCPP_MODELS=vieneu_v3_turbo \
    -DENGINE_ENABLE_METAL=OFF \
    -DENGINE_ENABLE_OPENMP=OFF \
    -DGGML_BLAS="$blas" -DGGML_BLAS_VENDOR=Apple > "$build.configure.log" 2>&1 || { tail -n 60 "$build.configure.log" >&2; exit 1; }
  cmake --build "$build" --target audiocpp_cli -j "$JOBS" > "$build.build.log" 2>&1 \
    || { grep -E 'error' "$build.build.log" | head -n 40 >&2; tail -n 40 "$build.build.log" >&2; exit 1; }
  find "$build" -name audiocpp_cli -type f -perm -u+x | head -n 1
}
CLI_BASE="$(build_cli "$WORK_DIR/src_base" "$WORK_DIR/build_base" OFF)"
CLI_PATCHED="$(build_cli "$WORK_DIR/src_patched" "$WORK_DIR/build_patched" ON)"
echo "cli gốc: $CLI_BASE"
echo "cli vá:  $CLI_PATCHED"

curl -fsSL -o "$WORK_DIR/model/turbo-q8_0.gguf" "$HF_BASE/vieneu-v3-turbo-q8_0.gguf"
curl -fsSL -o "$WORK_DIR/model/voice/ref_codes.txt" "$HF_BASE/voices/minh_quan_pro/ref_codes.txt"
curl -fsSL -o "$WORK_DIR/model/voice/speaker.emb.txt" "$HF_BASE/voices/minh_quan_pro/speaker.emb.txt"

# Câu mẫu trong doc của audio.cpp (đã là phiên âm sea-g2p) — một câu ngắn và một bản dài ~4 lần (prompt dài hơn,
# đúng chỗ bản vá đụng tới). `text_chunk_size` lớn để mỗi lượt là một đoạn.
SHORT="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
LONG="$SHORT $SHORT $SHORT $SHORT"

# Tham số từ thứ 4 trở đi: thêm vào dòng lệnh CLI (vd `--session-option …`, `--log-file …`).
run_case() {
  local cli="$1" tag="$2" text="$3"
  shift 3
  rm -f "$WORK_DIR/out/$tag.codes.txt"
  /usr/bin/time -l "$cli" --task tts --family vieneu_v3_turbo \
    --model "$WORK_DIR/model/turbo-q8_0.gguf" --backend cpu --threads 2 \
    --text "$text" \
    --request-option reference_codes_file="$WORK_DIR/model/voice/ref_codes.txt" \
    --request-option speaker_embedding_file="$WORK_DIR/model/voice/speaker.emb.txt" \
    --request-option do_sample=false \
    --request-option seed=1 \
    --request-option babble_retries=0 \
    --request-option text_chunk_size=1000 \
    --request-option codes_dump_file="$WORK_DIR/out/$tag.codes.txt" \
    "$@" \
    --out "$WORK_DIR/out/$tag.wav" > "$WORK_DIR/out/$tag.log" 2> "$WORK_DIR/out/$tag.time"
  local rss
  rss="$(grep -E 'maximum resident set size' "$WORK_DIR/out/$tag.time" | awk '{print $1}')"
  echo "$tag: RAM tối đa $((rss / 1024 / 1024)) MB, $(grep -c . "$WORK_DIR/out/$tag.codes.txt") dòng mã"
}

FAIL=0
for name in short long; do
  if [ "$name" = short ]; then text="$SHORT"; else text="$LONG"; fi
  run_case "$CLI_BASE" "base_$name" "$text"
  run_case "$CLI_PATCHED" "patched_$name" "$text" --log-file "$WORK_DIR/out/patched_$name.trace"
  if cmp -s "$WORK_DIR/out/base_$name.codes.txt" "$WORK_DIR/out/patched_$name.codes.txt" \
     && cmp -s "$WORK_DIR/out/base_$name.wav" "$WORK_DIR/out/patched_$name.wav"; then
    echo "✓ $name: mã âm thanh + WAV giống hệt"
  else
    echo "::error::$name: bản vá cho kết quả KHÁC bản gốc"
    diff <(head -c 4000 "$WORK_DIR/out/base_$name.codes.txt") <(head -c 4000 "$WORK_DIR/out/patched_$name.codes.txt") | head -n 20 || true
    FAIL=1
  fi

  # Codec qua Accelerate (bản vá vieneu_codec_blas) — cùng bản vá, chỉ bật session option.
  run_case "$CLI_PATCHED" "blas_$name" "$text" \
    --session-option vieneu_v3_turbo.codec_blas=true --log-file "$WORK_DIR/out/blas_$name.trace"
  active="$(grep -c 'moss.audio_tokenizer.decode.blas_active 1' "$WORK_DIR/out/blas_$name.trace" || true)"
  nodes="$(grep -E 'moss.audio_tokenizer.decode.blas_nodes ' "$WORK_DIR/out/blas_$name.trace" | tail -n 1 | awk '{print $NF}')"
  codec_off="$(grep -E 'moss.audio_tokenizer.decode.graph_compute_ms ' "$WORK_DIR/out/patched_$name.trace" | tail -n 1 | awk '{print $NF}')"
  codec_on="$(grep -E 'moss.audio_tokenizer.decode.graph_compute_ms ' "$WORK_DIR/out/blas_$name.trace" | tail -n 1 | awk '{print $NF}')"
  # Vùng nhớ ggml_backend_sched dành sẵn: máy ảo macOS cho malloc vài GB nên lỗi 1.3.924 (~2,6 GB ⇒ iPhone trả NULL,
  # app chết) không lộ ra ở đây ⇒ chặn bằng con số thay vì chờ máy thật.
  sched_mb="$(grep -E 'moss.audio_tokenizer.decode.sched_context_mb ' "$WORK_DIR/out/blas_$name.trace" | tail -n 1 | awk '{print $NF}')"
  graph_nodes="$(grep -E 'moss.audio_tokenizer.decode.graph_nodes ' "$WORK_DIR/out/blas_$name.trace" | tail -n 1 | awk '{print $NF}')"
  echo "$name: codec CPU ${codec_off:-?} ms · codec BLAS ${codec_on:-?} ms (máy ảo không AMX — chỉ tham khảo) · ${nodes:-0}/${graph_nodes:-?} node chạy BLAS · scheduler dành sẵn ${sched_mb:-?} MB"
  if [ -z "${sched_mb:-}" ] || ! awk -v mb="$sched_mb" 'BEGIN { exit !(mb + 0 <= 512) }'; then
    echo "::error::$name: ggml_backend_sched dành sẵn ${sched_mb:-?} MB (> 512 MB hoặc không đọc được) — trên iPhone malloc cỡ này có thể trả NULL"
    FAIL=1
  elif [ "${active:-0}" -lt 1 ] || [ "${nodes:-0}" -lt 1 ]; then
    echo "::error::$name: bật codec_blas mà codec KHÔNG chạy qua BLAS (blas_active=${active:-0}, blas_nodes=${nodes:-0})"
    grep -E 'blas|sched' "$WORK_DIR/out/blas_$name.trace" | head -n 10 || true
    FAIL=1
  elif ! cmp -s "$WORK_DIR/out/patched_$name.codes.txt" "$WORK_DIR/out/blas_$name.codes.txt"; then
    echo "::error::$name: bật codec_blas làm ĐỔI mã âm thanh (talker không được đổi)"
    FAIL=1
  elif python3 "$CI_DIR/audiocpp_wav_snr.py" "$WORK_DIR/out/patched_$name.wav" "$WORK_DIR/out/blas_$name.wav" --min-db 90; then
    echo "✓ $name: codec BLAS cùng mã, WAV đạt ngưỡng 90 dB"
  else
    echo "::error::$name: codec BLAS cho WAV lệch quá ngưỡng 90 dB"
    FAIL=1
  fi
done

# Nạp prompt qua Accelerate (bản vá vieneu_prefill_blas, 1.3.927): không trùng từng byte với đường q8 (bỏ lượng tử
# activation) ⇒ chấm bằng vector ẩn cuối của bước nạp so với đáp án fp32 — phải gần fp32 hơn đường q8 đang chạy.
prefill_case() {
  local tag="$1"
  shift
  rm -f "$WORK_DIR/out/$tag.dump"
  export VIENEU_LOGITS_DUMP="$WORK_DIR/out/$tag.dump"
  run_case "$CLI_PATCHED" "$tag" "$SHORT" --log-file "$WORK_DIR/out/$tag.trace" "$@"
  unset VIENEU_LOGITS_DUMP
}
prefill_case prefill_q8
prefill_case prefill_blas --session-option vieneu_v3_turbo.prefill_blas=true
prefill_case prefill_f32 --session-option vieneu_v3_turbo.weight_type=f32
prefill_active="$(grep -c 'vieneu_v3_turbo.talker.prefill.blas_active 1' "$WORK_DIR/out/prefill_blas.trace" || true)"
prefill_mb="$(grep -E 'vieneu_v3_turbo.talker.prefill.sched_context_mb ' "$WORK_DIR/out/prefill_blas.trace" | tail -n 1 | awk '{print $NF}')"
prefill_q8_ms="$(grep -E 'vieneu_v3_turbo.talker.prefill_ms ' "$WORK_DIR/out/prefill_q8.trace" | head -n 1 | awk '{print $NF}')"
prefill_blas_ms="$(grep -E 'vieneu_v3_turbo.talker.prefill_ms ' "$WORK_DIR/out/prefill_blas.trace" | head -n 1 | awk '{print $NF}')"
echo "prefill: q8 ${prefill_q8_ms:-?} ms · BLAS ${prefill_blas_ms:-?} ms (máy ảo không AMX — chỉ tham khảo) · scheduler dành sẵn ${prefill_mb:-?} MB"
if [ "${prefill_active:-0}" -lt 1 ]; then
  echo "::error::prefill: bật prefill_blas mà bước nạp prompt KHÔNG chạy qua BLAS"
  grep -E 'prefill' "$WORK_DIR/out/prefill_blas.trace" | head -n 10 || true
  FAIL=1
elif [ -z "${prefill_mb:-}" ] || ! awk -v mb="$prefill_mb" 'BEGIN { exit !(mb + 0 <= 512) }'; then
  echo "::error::prefill: ggml_backend_sched dành sẵn ${prefill_mb:-?} MB (> 512 MB hoặc không đọc được)"
  FAIL=1
elif python3 "$CI_DIR/audiocpp_prefill_check.py" "$WORK_DIR/out/prefill_q8.dump" \
    "$WORK_DIR/out/prefill_blas.dump" "$WORK_DIR/out/prefill_f32.dump"; then
  echo "✓ prefill: BLAS gần bản fp32 hơn đường q8 đang chạy"
else
  echo "::error::prefill: đường BLAS không đạt cổng chất lượng"
  FAIL=1
fi

# Threadpool giữ lâu (bản vá vieneu_threadpool, 1.3.929): đúng cấu hình app, chỉ thêm option ⇒ trùng từng byte.
APP_OPTS=(--session-option vieneu_v3_turbo.codec_blas=true --session-option vieneu_v3_turbo.prefill_blas=true)
run_case "$CLI_PATCHED" "app_long" "$LONG" "${APP_OPTS[@]}" --log-file "$WORK_DIR/out/app_long.trace"
run_case "$CLI_PATCHED" "pool_long" "$LONG" "${APP_OPTS[@]}" \
  --session-option vieneu_v3_turbo.threadpool_poll=0 --log-file "$WORK_DIR/out/pool_long.trace"
pool_made="$(grep -c 'vieneu_v3_turbo.threadpool_poll 0' "$WORK_DIR/out/pool_long.trace" || true)"
acoustic_app="$(grep -E 'vieneu_v3_turbo.talker.code_predictor_ms ' "$WORK_DIR/out/app_long.trace" | tail -n 1 | awk '{print $NF}')"
acoustic_pool="$(grep -E 'vieneu_v3_turbo.talker.code_predictor_ms ' "$WORK_DIR/out/pool_long.trace" | tail -n 1 | awk '{print $NF}')"
echo "threadpool: âm học ${acoustic_app:-?} ms → ${acoustic_pool:-?} ms (máy ảo — chỉ tham khảo)"
if [ "${pool_made:-0}" -lt 1 ]; then
  echo "::error::threadpool: có threadpool_poll=0 mà log không báo đã tạo pool"
  FAIL=1
elif cmp -s "$WORK_DIR/out/app_long.codes.txt" "$WORK_DIR/out/pool_long.codes.txt" \
    && cmp -s "$WORK_DIR/out/app_long.wav" "$WORK_DIR/out/pool_long.wav"; then
  echo "✓ threadpool: mã âm thanh + WAV giống hệt cấu hình app"
else
  echo "::error::threadpool: giữ pool làm ĐỔI kết quả (phải trùng từng byte)"
  FAIL=1
fi

# Repack bộ giải mã âm học (bản vá vieneu_acoustic_repack, 1.3.930): so với cấu hình app 1.3.929 (pool_long).
run_case "$CLI_PATCHED" "repack_long" "$LONG" "${APP_OPTS[@]}" \
  --session-option vieneu_v3_turbo.threadpool_poll=0 --session-option vieneu_v3_turbo.acoustic_repack=true \
  --log-file "$WORK_DIR/out/repack_long.trace"
repack_weights="$(grep -E 'vieneu_v3_turbo.talker.acoustic_repack.weights ' "$WORK_DIR/out/repack_long.trace" | head -n 1 | awk '{print $NF}')"
repack_buffer="$(grep -E 'vieneu_v3_turbo.acoustic_decoder.repack.buffer_name ' "$WORK_DIR/out/repack_long.trace" | head -n 1 | awk '{print $NF}')"
acoustic_repack="$(grep -E 'vieneu_v3_turbo.talker.code_predictor_ms ' "$WORK_DIR/out/repack_long.trace" | tail -n 1 | awk '{print $NF}')"
echo "repack: ${repack_weights:-0} ma trận trong ${repack_buffer:-?} · âm học ${acoustic_pool:-?} ms → ${acoustic_repack:-?} ms (máy ảo — chỉ tham khảo)"
if [ "${repack_weights:-0}" != "5" ] || [ "${repack_buffer:-}" != "CPU_REPACK" ]; then
  echo "::error::repack: bật acoustic_repack mà log không báo đủ 5 ma trận trong CPU_REPACK"
  grep -E 'repack' "$WORK_DIR/out/repack_long.trace" | head -n 10 || true
  FAIL=1
elif cmp -s "$WORK_DIR/out/pool_long.codes.txt" "$WORK_DIR/out/repack_long.codes.txt" \
    && cmp -s "$WORK_DIR/out/pool_long.wav" "$WORK_DIR/out/repack_long.wav"; then
  echo "✓ repack: mã âm thanh + WAV giống hệt cấu hình app 1.3.929"
else
  echo "::error::repack: đổi mã âm thanh so với cấu hình app 1.3.929"
  FAIL=1
fi
exit "$FAIL"
