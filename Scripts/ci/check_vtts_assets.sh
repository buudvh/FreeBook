#!/usr/bin/env bash
# Kiểm tài sản vtts (trình đọc Việt–Anh, runtime C99 — https://github.com/tuanpmt/vtts, Apache-2.0) đã lưu sẵn trong repo
# + đọc thử trên máy Mac. CI chạy trước `xcodegen generate`. KHÔNG tải gì từ mạng: model, từ điển, mã nguồn và công cụ
# dựng lại đều nằm trong `Vendor/vtts` (anh Bửu: phòng repo upstream / CMUdict bị xoá) — xem `Vendor/vtts/README.md`.
#
# Kiểm (thoát mã ≠ 0 nếu hỏng):
#   1. SHA256 của 4 model (theo `assets/SHA256SUMS` — 4 dòng vi-en nguyên văn của release v0.11.0) và của `lex_en.bin` /
#      `cmudict.dict` / 2 giọng tự train (theo `assets/LOCAL_SHA256SUMS`); `assets/vtts/` (thư mục đóng vào bundle app)
#      có đúng 4 giọng M + `lex_en.bin`, không thừa file nào;
#   2. dựng `vtts_say` của upstream (đã vendor ở `tools/runtime/tools/`) bằng clang trên runtime đã vendor, với ĐÚNG cờ
#      tắt ngôn ngữ của gói SPM (+ stub `vtts_say_lex_stubs.c` cho 3 hàm init ZH / JA / RU đã tắt); đọc thử câu Việt + Anh bằng từng giọng M ở chế độ auto: phải thấy bộ token vi-en, chế độ
#      auto, đã nạp VLEX, id < vocab, WAV ≥ 1 s và không im lặng;
#   3. biên dịch shim `vtts_bridge` + runtime đã vendor + `vtts_bridge_smoke.c` với ASan/UBSan, chạy từng giọng M: câu
#      thử, chuỗi rỗng, chỉ dấu câu, thẻ huỷ, (giọng đầu) đoạn dài bị chia nhiều phần; so WAV của shim với `vtts_say`
#      (lệch chỉ cảnh báo).
# WAV đọc thử ⇒ `build/vtts-smoke/` (workflow tải lên artifact `vtts-samples`).
#
# Biến môi trường: WORK_DIR (mặc định build/vtts), SMOKE_DIR (mặc định build/vtts-smoke).
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$CI_DIR/../.." && pwd)"
VENDOR_DIR="$REPO_ROOT/Vendor/vtts"
RUNTIME_DIR="$VENDOR_DIR/Sources/CVTTS/runtime"
BRIDGE_DIR="$VENDOR_DIR/Sources/CVTTS/bridge"
ASSETS="$VENDOR_DIR/assets"
BUNDLED="$ASSETS/vtts"
LEX="$BUNDLED/lex_en.bin"
WORK_DIR="${WORK_DIR:-$REPO_ROOT/build/vtts}"
SMOKE_DIR="${SMOKE_DIR:-$REPO_ROOT/build/vtts-smoke}"

# "<id giọng> <file model>" — giọng đóng vào app; id trùng `VttsVoice.id` (Swift). `ngoc-huyen` (1.3.1044) và
# `google-dich` (1.3.1046) do FreeBook tự train (chưng cất bản M từ thầy VITS) — không có trong release upstream, SHA256
# ở `LOCAL_SHA256SUMS` (`Vendor/vtts/THIRD_PARTY_NOTICES.md`).
VOICES=(
  "nu-10 vtts-vien-nu10-m-v0.11.q8.vtts"
  "nam-1 vtts-vien-nam1-m-v0.11.q8.vtts"
  "ngoc-huyen vtts-ngochuyen-m-k4.q8.vtts"
  "google-dich vtts-googledich-m-k4.q8.vtts"
)

# Phải khớp `disabledLanguages` trong Vendor/vtts/Package.swift (= OPT_LANGS của tools/runtime/Makefile).
VTTS_DISABLED_LANGS=(ZH KO JA HI TH ES ID PT FR DE IT TR RU PL AR FI EL MS TL SW NL SV NO DA LO KM MY)
VTTS_DEFINES=()
for L in "${VTTS_DISABLED_LANGS[@]}"; do VTTS_DEFINES+=("-DVTTS_ENABLE_${L}=0"); done

TEST_SENTENCE="Đã kết nối Bluetooth với AirPods, chương này tên là The Last Train."

die() {
  echo "❌ [vtts] $*" >&2
  exit 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Chỉ dùng để đọc WAV (thư viện chuẩn) ⇒ phiên bản nào cũng được.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && [ "$("$c" -c 'print("ok")' 2>/dev/null)" = "ok" ]; then
    PY="$c"
    break
  fi
done
[ -n "$PY" ] || die "không có python3"

# WAV 16-bit mono: in thời lượng + RMS, hỏng nếu ngắn hơn $2 giây hoặc gần như im lặng.
wav_check() {
  "$PY" - "$1" "$2" "$3" <<'PY'
import array, math, sys, wave
path, min_seconds, label = sys.argv[1], float(sys.argv[2]), sys.argv[3]
with wave.open(path, "rb") as w:
    rate, frames, width, channels = w.getframerate(), w.getnframes(), w.getsampwidth(), w.getnchannels()
    data = w.readframes(frames)
if width != 2 or channels != 1:
    sys.exit(f"❌ [vtts] {label}: WAV {width * 8}-bit {channels} kênh, mong 16-bit mono")
pcm = array.array("h")
pcm.frombytes(data)
seconds = frames / rate if rate else 0.0
rms = math.sqrt(sum(s * s for s in pcm) / len(pcm)) / 32768.0 if pcm else 0.0
print(f"{label}: {seconds:.2f} s, {rate} Hz, rms {rms:.4f}")
if seconds < min_seconds or rms < 0.005:
    sys.exit(f"❌ [vtts] {label}: tiếng quá ngắn / quá nhỏ (cần ≥ {min_seconds} s, rms ≥ 0.005)")
PY
}

# So WAV của shim với WAV của vtts_say (cùng câu, cùng giọng, chế độ auto, cùng 150 ms giữa chunk): mong trùng tới làm
# tròn int16. Lệch chỉ cảnh báo — app vẫn chạy được, nhưng nghĩa là shim tổng hợp khác upstream.
wav_compare() {
  "$PY" - "$1" "$2" "$3" <<'PY' || true
import array, sys, wave
def load(path):
    with wave.open(path, "rb") as w:
        pcm = array.array("h")
        pcm.frombytes(w.readframes(w.getnframes()))
        return pcm
a, b, label = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]
if len(a) != len(b):
    print(f"::warning::vtts {label}: shim {len(a)} mẫu ≠ vtts_say {len(b)} mẫu")
    sys.exit(0)
diff = max((abs(x - y) for x, y in zip(a, b)), default=0)
if diff > 2:
    print(f"::warning::vtts {label}: shim lệch vtts_say tối đa {diff} (int16)")
else:
    print(f"{label}: shim trùng vtts_say ({len(a)} mẫu, lệch tối đa {diff})")
PY
}

check_hashes() {
  local want name path got count=0
  echo "▶ vtts: kiểm SHA256 tài sản trong $ASSETS"
  # Model: các dòng vi-en nguyên văn của SHA256SUMS release (tên trần) — giọng M nằm ở vtts/, bản S dự trữ ở extra/.
  while read -r want name; do
    [ -n "${name:-}" ] || continue
    name="${name#\*}"
    if [ -f "$BUNDLED/$name" ]; then
      path="$BUNDLED/$name"
    elif [ -f "$ASSETS/extra/$name" ]; then
      path="$ASSETS/extra/$name"
    else
      die "thiếu $name (có trong SHA256SUMS)"
    fi
    got="$(sha256_of "$path")"
    [ "$got" = "$want" ] || die "SHA256 của $name lệch: $got ≠ $want"
    echo "  ${path#"$ASSETS/"} OK"
    count=$((count + 1))
  done < "$ASSETS/SHA256SUMS"
  [ "$count" -eq 4 ] || die "SHA256SUMS có $count model, mong 4"
  # Từ điển dựng tại chỗ + CMUdict nguồn + giọng tự train (đường dẫn tương đối trong assets/).
  while read -r want name; do
    [ -n "${name:-}" ] || continue
    [ -f "$ASSETS/$name" ] || die "thiếu assets/$name"
    got="$(sha256_of "$ASSETS/$name")"
    [ "$got" = "$want" ] || die "SHA256 của assets/$name lệch: $got ≠ $want"
    echo "  $name OK"
  done < "$ASSETS/LOCAL_SHA256SUMS"
  # Thư mục đóng vào bundle: đúng 4 giọng M + VLEX (file thừa ⇒ IPA phình âm thầm).
  count="$(find "$BUNDLED" -type f | wc -l | tr -d '[:space:]')"
  [ "$count" -eq 5 ] || die "assets/vtts/ có $count file, mong đúng 5 (4 giọng M + lex_en.bin)"
}

check_vtts_say() {
  local entry voice name wav say_log summary chunks samples max_id vocab
  echo "▶ vtts: dựng vtts_say (mã upstream đã vendor) + đọc thử từng giọng"
  # Không -Werror: cảnh báo mới của Apple clang không được làm đỏ build.
  # `vtts_say.c` luôn gọi `vtts_{zlex,jlex,rlex}_init`, mà ZH / JA / RU đã tắt ⇒ link kèm stub trả lỗi
  # (`vtts_say_lex_stubs.c`) để giữ ĐÚNG cờ của gói SPM.
  clang -std=c99 -O2 -ffp-contract=off "${VTTS_DEFINES[@]}" -I"$RUNTIME_DIR/include" -I"$RUNTIME_DIR/src" \
    "$RUNTIME_DIR"/src/*.c "$VENDOR_DIR/tools/runtime/tools/vtts_say.c" "$CI_DIR/vtts_say_lex_stubs.c" \
    -lm -o "$WORK_DIR/vtts_say" ||
    die "biên dịch vtts_say lỗi"
  for entry in "${VOICES[@]}"; do
    read -r voice name <<< "$entry"
    wav="$SMOKE_DIR/vtts_say-$voice.wav"
    say_log="$WORK_DIR/vtts_say-$voice.log"
    "$WORK_DIR/vtts_say" "$BUNDLED/$name" "$wav" --lex "$LEX" --lang auto "$TEST_SENTENCE" > "$say_log" ||
      { cat "$say_log"; die "vtts_say ($voice) lỗi — runtime $(cat "$VENDOR_DIR/VTTS_COMMIT.txt") không nạp được model?"; }
    head -n 1 "$say_log"
    # vtts_say vẫn chạy tiếp khi VLEX hỏng (bỏ tiếng Anh) ⇒ WAV có tiếng chưa chứng minh gì: kiểm từng trường.
    grep -q '^token_set vi-en ' "$say_log" || die "$voice: model không phải bộ token vi-en"
    grep -q ' mode auto lex 1 ' "$say_log" || die "$voice: không chạy chế độ auto với VLEX"
    summary="$(grep '^chunks ' "$say_log" | tail -n 1)"
    echo "  $voice: $summary"
    read -r _ chunks _ samples _ max_id _ vocab <<< "$summary"
    [ "${chunks:-0}" -gt 0 ] || die "$voice: front-end không ra chunk nào"
    [ "${max_id:--1}" -ge 0 ] && [ "$max_id" -lt "${vocab:-0}" ] || die "$voice: id $max_id ngoài từ vựng $vocab"
    wav_check "$wav" 1.0 "vtts_say $voice"
  done
}

check_bridge() {
  local entry voice name wav mode
  echo "▶ vtts: kiểm thử shim vtts_bridge (ASan + UBSan, runtime đã vendor)"
  # `-DVTTS_BRIDGE_SEGMENT_CP=150`: đường chia đoạn dài chạy được với vài câu (app chia ở 2000; `#error` trong shim giữ
  # ngưỡng dưới 4096). `-fno-sanitize=function`: Apple clang mới bật nó cho C trong `undefined`; upstream chưa chắc từng
  # chạy kiểm này với callback `vtts_par_run` của họ — đừng để một báo động nhầm làm đỏ build.
  clang -std=gnu11 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize=function \
    -fno-sanitize-recover=all -ffp-contract=off -DVTTS_BRIDGE_SEGMENT_CP=150 "${VTTS_DEFINES[@]}" \
    -Werror=implicit-function-declaration -Werror=incompatible-pointer-types -Werror=int-conversion \
    -Werror=return-type \
    -I"$BRIDGE_DIR/include" -I"$RUNTIME_DIR/include" -I"$RUNTIME_DIR/src" \
    "$RUNTIME_DIR"/src/*.c "$BRIDGE_DIR/vtts_bridge.c" "$CI_DIR/vtts_bridge_smoke.c" -lm \
    -o "$WORK_DIR/vtts_bridge_smoke" || die "biên dịch shim vtts_bridge lỗi"
  mode="--long" # đoạn dài (chia nhiều phần) chỉ chạy với giọng đầu — phần chia đoạn không phụ thuộc giọng
  for entry in "${VOICES[@]}"; do
    read -r voice name <<< "$entry"
    wav="$SMOKE_DIR/bridge-$voice.wav"
    "$WORK_DIR/vtts_bridge_smoke" "$BUNDLED/$name" "$LEX" "$wav" "$TEST_SENTENCE" $mode ||
      die "shim vtts_bridge hỏng với giọng $voice"
    mode=""
    wav_check "$wav" 1.0 "shim $voice"
    wav_compare "$wav" "$SMOKE_DIR/vtts_say-$voice.wav" "$voice"
  done
}

mkdir -p "$WORK_DIR" "$SMOKE_DIR"
check_hashes
check_vtts_say
check_bridge
echo "▶ vtts: tài sản + runtime + shim OK (commit $(cat "$VENDOR_DIR/VTTS_COMMIT.txt"))"
