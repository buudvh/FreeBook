#!/usr/bin/env bash
# Kiểm bản vá audio.cpp của app (Scripts/ci/audiocpp_patches/) không đổi tiếng: build `audiocpp_cli` cho macOS hai
# lần — bản gốc và bản vá — đọc cùng các chuỗi phiên âm bằng VieNeu Turbo GGUF q8_0 với **greedy** (`do_sample=false`,
# seed cố định, tắt babble guard), rồi so **mã âm thanh** (`codes_dump_file`) và file WAV từng byte. Lệch ⇒ exit 1.
# Kèm đo RAM tối đa (`/usr/bin/time -l`) của từng bản để thấy bản vá bớt được bao nhiêu.
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

build_cli() {
  local src="$1" build="$2"
  cmake -S "$src" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DAUDIOCPP_DEPLOYMENT_BUILD=ON \
    -DAUDIOCPP_MODEL_SET=custom \
    -DAUDIOCPP_MODELS=vieneu_v3_turbo \
    -DENGINE_ENABLE_METAL=OFF \
    -DENGINE_ENABLE_OPENMP=OFF \
    -DGGML_BLAS=OFF > "$build.configure.log" 2>&1 || { tail -n 60 "$build.configure.log" >&2; exit 1; }
  cmake --build "$build" --target audiocpp_cli -j "$JOBS" > "$build.build.log" 2>&1 \
    || { grep -E 'error' "$build.build.log" | head -n 40 >&2; tail -n 40 "$build.build.log" >&2; exit 1; }
  find "$build" -name audiocpp_cli -type f -perm -u+x | head -n 1
}
CLI_BASE="$(build_cli "$WORK_DIR/src_base" "$WORK_DIR/build_base")"
CLI_PATCHED="$(build_cli "$WORK_DIR/src_patched" "$WORK_DIR/build_patched")"
echo "cli gốc: $CLI_BASE"
echo "cli vá:  $CLI_PATCHED"

curl -fsSL -o "$WORK_DIR/model/turbo-q8_0.gguf" "$HF_BASE/vieneu-v3-turbo-q8_0.gguf"
curl -fsSL -o "$WORK_DIR/model/voice/ref_codes.txt" "$HF_BASE/voices/minh_quan_pro/ref_codes.txt"
curl -fsSL -o "$WORK_DIR/model/voice/speaker.emb.txt" "$HF_BASE/voices/minh_quan_pro/speaker.emb.txt"

# Câu mẫu trong doc của audio.cpp (đã là phiên âm sea-g2p) — một câu ngắn và một bản dài ~4 lần (prompt dài hơn,
# đúng chỗ bản vá đụng tới). `text_chunk_size` lớn để mỗi lượt là một đoạn.
SHORT="sˈin tʃˈaː2w tˈeɜ zˈəːɜj. ɗˈəɪ lˌaː2 bˈaː4n tˈy4 ŋˈiɛ6m."
LONG="$SHORT $SHORT $SHORT $SHORT"

run_case() {
  local cli="$1" tag="$2" text="$3"
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
    --out "$WORK_DIR/out/$tag.wav" > "$WORK_DIR/out/$tag.log" 2> "$WORK_DIR/out/$tag.time"
  local rss
  rss="$(grep -E 'maximum resident set size' "$WORK_DIR/out/$tag.time" | awk '{print $1}')"
  echo "$tag: RAM tối đa $((rss / 1024 / 1024)) MB, $(grep -c . "$WORK_DIR/out/$tag.codes.txt") dòng mã"
}

FAIL=0
for name in short long; do
  if [ "$name" = short ]; then text="$SHORT"; else text="$LONG"; fi
  run_case "$CLI_BASE" "base_$name" "$text"
  run_case "$CLI_PATCHED" "patched_$name" "$text"
  if cmp -s "$WORK_DIR/out/base_$name.codes.txt" "$WORK_DIR/out/patched_$name.codes.txt" \
     && cmp -s "$WORK_DIR/out/base_$name.wav" "$WORK_DIR/out/patched_$name.wav"; then
    echo "✓ $name: mã âm thanh + WAV giống hệt"
  else
    echo "::error::$name: bản vá cho kết quả KHÁC bản gốc"
    diff <(head -c 4000 "$WORK_DIR/out/base_$name.codes.txt") <(head -c 4000 "$WORK_DIR/out/patched_$name.codes.txt") | head -n 20 || true
    FAIL=1
  fi
done
exit "$FAIL"
