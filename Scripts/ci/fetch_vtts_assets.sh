#!/usr/bin/env bash
# Tài sản cho trình đọc vtts (Việt–Anh, runtime C99 — https://github.com/tuanpmt/vtts, Apache-2.0) + kiểm thử trên máy Mac.
# Máy Mac chạy script này TRƯỚC `xcodegen generate` (như `build_audiocpp_ios.sh`): `project.yml` khai
# `Vendor/vtts-assets/vtts` là folder resource ⇒ bundle app có thư mục `vtts/` gồm:
#   - vtts-vien-nu10-m-v0.4.q8.vtts, vtts-vien-nam1-m-v0.4.q8.vtts — model release v0.4.0, kiểm SHA256 (ghi cứng dưới
#     đây, chép từ `SHA256SUMS` của release);
#   - lex_en.bin — từ điển tiếng Anh VLEX (~1,9 MB). Upstream KHÔNG phát hành sẵn: dựng bằng
#     `scripts/frontend/build_lexicon.py` của vtts ở ĐÚNG commit ghim trong `Vendor/vtts/VTTS_COMMIT.txt` (runtime đọc
#     blob tại chỗ ⇒ định dạng phải khớp runtime đã vendor). Script tải CMUdict ghim commit + kiểm SHA256 rồi huấn luyện
#     bảng letter-to-sound bằng Python thuần (chỉ thư viện chuẩn, cần Python ≥ 3.11; ~8 phút).
#
# Idempotent: tài sản đã có và khớp `.stamp` (commit + release + hash script + hash từng file) ⇒ bỏ qua phần tải / dựng
# (CI cache `Vendor/vtts-assets` với khoá = hash script + commit + tên model). Phần kiểm thử shim LUÔN chạy.
#
# Kiểm thử (thoát mã ≠ 0 nếu hỏng):
#   1. (khi dựng tài sản) runtime đã vendor trùng từng byte với upstream ở commit ghim;
#   2. (khi dựng tài sản) dựng `vtts_say` của upstream bằng clang, với ĐÚNG cờ tắt ngôn ngữ của gói SPM, đọc thử câu
#      Việt + Anh bằng từng giọng ở chế độ auto: phải thấy bộ token vi-en, chế độ auto, đã nạp VLEX, id < vocab, WAV đủ
#      dài + đủ to;
#   3. (luôn) biên dịch shim `vtts_bridge` + runtime đã vendor + `vtts_bridge_smoke.c` với ASan/UBSan, chạy từng giọng:
#      câu thử, chuỗi rỗng, chỉ dấu câu, thẻ huỷ, (giọng đầu) đoạn dài bị chia nhiều phần. So WAV của shim với WAV của
#      `vtts_say` (lệch chỉ cảnh báo).
# WAV đọc thử nằm ở `build/vtts-smoke/` (workflow tải lên artifact `vtts-samples`).
#
# Cách gọi: `bash Scripts/ci/fetch_vtts_assets.sh [assets|smoke]` — không tham số = cả hai (build local).
#
# Biến môi trường (đều có mặc định):
#   OUT_DIR    thư mục tài sản (mặc định Vendor/vtts-assets — project.yml trỏ vào Vendor/vtts-assets/vtts)
#   WORK_DIR   thư mục tạm (mặc định build/vtts)
#   SMOKE_DIR  nơi ghi WAV đọc thử (mặc định build/vtts-smoke)
#
# Nâng phiên bản: xem `.claude/rules/ci-release.md` (mục vtts).
set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$CI_DIR/../.." && pwd)"
SCRIPT_PATH="$CI_DIR/$(basename "${BASH_SOURCE[0]}")"
VENDOR_DIR="$REPO_ROOT/Vendor/vtts"
BRIDGE_SRC="$VENDOR_DIR/Sources/CVTTS"
VTTS_COMMIT="$(tr -d '[:space:]' < "$VENDOR_DIR/VTTS_COMMIT.txt")"
VTTS_REPO="https://github.com/tuanpmt/vtts"
MODEL_RELEASE="v0.4.0"
MODEL_BYTES=2580320

OUT_DIR="${OUT_DIR:-$REPO_ROOT/Vendor/vtts-assets}"
WORK_DIR="${WORK_DIR:-$REPO_ROOT/build/vtts}"
SMOKE_DIR="${SMOKE_DIR:-$REPO_ROOT/build/vtts-smoke}"
ASSET_DIR="$OUT_DIR/vtts"
CACHED_SMOKE_DIR="$OUT_DIR/smoke"
STAMP="$OUT_DIR/.stamp"
LEX_NAME="lex_en.bin"

# "<id giọng> <file model> <sha256>" — id giọng trùng `VttsVoice.rawValue` (Swift).
MODELS=(
  "nu-10 vtts-vien-nu10-m-v0.4.q8.vtts 9381576754495146a4e376427e713763bd4511142cb96517f9c64db9b66d8931"
  "nam-1 vtts-vien-nam1-m-v0.4.q8.vtts 257e3c4ae6e10c192a73b62792ee42dfd9d785e20179fae84954a786543a7eaf"
)

# Phải khớp `disabledLanguages` trong Vendor/vtts/Package.swift (= OPT_LANGS của runtime/Makefile upstream).
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

file_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

# Python ≥ 3.11 (pyproject.toml của vtts) — không giả định phiên bản của runner.
pick_python() {
  local c
  for c in python3.13 python3.12 python3.11 python3; do
    if command -v "$c" >/dev/null 2>&1 &&
      "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

PY="$(pick_python || true)"
[ -n "$PY" ] || PY="$(command -v python3 || true)"
[ -n "$PY" ] || die "không có python3"

SCRIPT_SHA="$(sha256_of "$SCRIPT_PATH")"

stamp_header() {
  printf 'commit=%s\nrelease=%s\nscript=%s\n' "$VTTS_COMMIT" "$MODEL_RELEASE" "$SCRIPT_SHA"
}

# 0 khi tài sản đã có và khớp stamp (file nào bị sửa / thiếu ⇒ dựng lại hết).
assets_ready() {
  local line name want
  [ -f "$STAMP" ] || return 1
  [ "$(head -n 3 "$STAMP")" = "$(stamp_header)" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      file=*)
        line="${line#file=}"
        name="${line%% *}"
        want="${line##* }"
        [ -f "$ASSET_DIR/$name" ] || return 1
        [ "$(sha256_of "$ASSET_DIR/$name")" = "$want" ] || return 1
        ;;
    esac
  done < "$STAMP"
  for entry in "${MODELS[@]}"; do
    read -r _ name _ <<< "$entry"
    [ -f "$ASSET_DIR/$name" ] || return 1
  done
  [ -f "$ASSET_DIR/$LEX_NAME" ] || return 1
  return 0
}

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

# So WAV của shim với WAV của vtts_say (cùng câu, cùng giọng, cùng chế độ auto, cùng khoảng 150 ms giữa chunk): mong
# trùng tới làm tròn int16. Lệch chỉ cảnh báo — app vẫn chạy được, nhưng nghĩa là shim tổng hợp khác upstream.
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

build_assets() {
  local entry voice name want got src py_ver lex_bytes say_log wav summary chunks samples max_id vocab
  echo "▶ vtts: dựng tài sản (commit $VTTS_COMMIT, model $MODEL_RELEASE) → $ASSET_DIR"
  rm -rf "$ASSET_DIR" "$CACHED_SMOKE_DIR" "$STAMP" "$WORK_DIR"
  mkdir -p "$WORK_DIR/models" "$ASSET_DIR" "$CACHED_SMOKE_DIR"

  # 1. Model release v0.4.0 + kiểm SHA256.
  for entry in "${MODELS[@]}"; do
    read -r voice name want <<< "$entry"
    curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 30 \
      -o "$WORK_DIR/models/$name" "$VTTS_REPO/releases/download/$MODEL_RELEASE/$name" ||
      die "tải $name lỗi"
    got="$(sha256_of "$WORK_DIR/models/$name")"
    [ "$got" = "$want" ] || die "SHA256 của $name lệch: $got ≠ $want"
    [ "$(file_bytes "$WORK_DIR/models/$name")" = "$MODEL_BYTES" ] || die "$name không đúng $MODEL_BYTES byte"
    echo "  model $voice: $name OK ($MODEL_BYTES byte)"
  done

  # 2. Mã nguồn vtts ở commit ghim.
  src="$WORK_DIR/src"
  git init -q "$src"
  git -C "$src" remote add origin "$VTTS_REPO.git"
  git -C "$src" fetch -q --depth 1 origin "$VTTS_COMMIT" || die "không lấy được commit $VTTS_COMMIT"
  git -C "$src" -c advice.detachedHead=false checkout -q FETCH_HEAD
  [ "$(git -C "$src" rev-parse HEAD)" = "$VTTS_COMMIT" ] || die "checkout không ra commit $VTTS_COMMIT"

  # 3. Runtime đã vendor phải trùng từng byte với upstream (chép tay sai / sửa nhầm ⇒ dừng).
  diff -r "$src/runtime/include" "$BRIDGE_SRC/runtime/include" >/dev/null ||
    die "Vendor/vtts/Sources/CVTTS/runtime/include khác upstream ở $VTTS_COMMIT"
  diff -r "$src/runtime/src" "$BRIDGE_SRC/runtime/src" >/dev/null ||
    die "Vendor/vtts/Sources/CVTTS/runtime/src khác upstream ở $VTTS_COMMIT"
  cmp -s "$src/LICENSE" "$VENDOR_DIR/LICENSE" || die "Vendor/vtts/LICENSE khác upstream"
  cmp -s "$src/NOTICE" "$VENDOR_DIR/NOTICE" || die "Vendor/vtts/NOTICE khác upstream"
  echo "  runtime đã vendor trùng upstream ($VTTS_COMMIT)"

  # 4. Từ điển VLEX từ cùng commit.
  "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' ||
    die "cần Python ≥ 3.11 để dựng VLEX (đang có: $("$PY" --version 2>&1))"
  py_ver="$("$PY" --version 2>&1)"
  echo "  dựng VLEX bằng $py_ver (~8 phút)…"
  (cd "$src" && PYTHONPATH=src "$PY" scripts/frontend/build_lexicon.py --out "$WORK_DIR/$LEX_NAME")
  lex_bytes="$(file_bytes "$WORK_DIR/$LEX_NAME")"
  [ "$lex_bytes" -gt 1000000 ] || die "VLEX chỉ $lex_bytes byte"
  echo "  VLEX: $lex_bytes byte, sha256 $(sha256_of "$WORK_DIR/$LEX_NAME")"

  # 5. vtts_say của upstream, cùng cờ tắt ngôn ngữ với gói SPM (không -Werror: cảnh báo mới của Apple clang không được
  #    làm đỏ build).
  clang -std=c99 -O2 -ffp-contract=off "${VTTS_DEFINES[@]}" \
    -I"$src/runtime/include" -I"$src/runtime/src" \
    "$src"/runtime/src/*.c "$src/runtime/tools/vtts_say.c" -lm -o "$WORK_DIR/vtts_say" ||
    die "biên dịch vtts_say lỗi"

  # 6. Đọc thử từng giọng ở chế độ auto.
  for entry in "${MODELS[@]}"; do
    read -r voice name want <<< "$entry"
    wav="$CACHED_SMOKE_DIR/vtts_say-$voice.wav"
    say_log="$WORK_DIR/vtts_say-$voice.log"
    "$WORK_DIR/vtts_say" "$WORK_DIR/models/$name" "$wav" --lex "$WORK_DIR/$LEX_NAME" --lang auto \
      "$TEST_SENTENCE" > "$say_log" || { cat "$say_log"; die "vtts_say ($voice) lỗi — runtime $VTTS_COMMIT không nạp được model $MODEL_RELEASE?"; }
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

  # 7. Chép vào thư mục tài sản + stamp.
  for entry in "${MODELS[@]}"; do
    read -r voice name want <<< "$entry"
    cp "$WORK_DIR/models/$name" "$ASSET_DIR/$name"
  done
  cp "$WORK_DIR/$LEX_NAME" "$ASSET_DIR/$LEX_NAME"
  {
    stamp_header
    for f in "$ASSET_DIR"/*; do
      printf 'file=%s %s\n' "$(basename "$f")" "$(sha256_of "$f")"
    done
  } > "$STAMP"
  echo "  tài sản vtts sẵn sàng"
}

run_bridge_smoke() {
  local entry voice name want wav mode
  echo "▶ vtts: kiểm thử shim vtts_bridge (ASan + UBSan, runtime đã vendor)"
  mkdir -p "$WORK_DIR"
  # `-DVTTS_BRIDGE_SEGMENT_CP=150`: đường chia đoạn dài chạy được với vài câu (app chia ở 2000; `#error` trong shim giữ
  # ngưỡng dưới 4096). `-fno-sanitize=function`: Apple clang mới bật nó cho C trong `undefined`; upstream chưa chắc từng
  # chạy kiểm này với callback `vtts_par_run` của họ — đừng để một báo động nhầm làm đỏ build.
  clang -std=gnu11 -O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize=function \
    -fno-sanitize-recover=all -ffp-contract=off -DVTTS_BRIDGE_SEGMENT_CP=150 "${VTTS_DEFINES[@]}" \
    -Werror=implicit-function-declaration -Werror=incompatible-pointer-types -Werror=int-conversion \
    -Werror=return-type \
    -I"$BRIDGE_SRC/bridge/include" -I"$BRIDGE_SRC/runtime/include" -I"$BRIDGE_SRC/runtime/src" \
    "$BRIDGE_SRC"/runtime/src/*.c "$BRIDGE_SRC/bridge/vtts_bridge.c" "$CI_DIR/vtts_bridge_smoke.c" -lm \
    -o "$WORK_DIR/vtts_bridge_smoke" || die "biên dịch shim vtts_bridge lỗi"
  mode="--long" # đoạn dài (chia nhiều phần) chỉ chạy với giọng đầu — phần chia đoạn không phụ thuộc giọng
  for entry in "${MODELS[@]}"; do
    read -r voice name want <<< "$entry"
    wav="$SMOKE_DIR/bridge-$voice.wav"
    "$WORK_DIR/vtts_bridge_smoke" "$ASSET_DIR/$name" "$ASSET_DIR/$LEX_NAME" "$wav" "$TEST_SENTENCE" $mode ||
      die "shim vtts_bridge hỏng với giọng $voice"
    mode=""
    wav_check "$wav" 1.0 "shim $voice"
    if [ -f "$SMOKE_DIR/vtts_say-$voice.wav" ]; then
      wav_compare "$wav" "$SMOKE_DIR/vtts_say-$voice.wav" "$voice"
    fi
  done
}

# Bước: `assets` (tải / dựng tài sản + đọc thử bằng vtts_say), `smoke` (kiểm thử shim trên tài sản đã có), không ghi =
# cả hai. Workflow chạy hai bước riêng và lưu cache ngay sau `assets` ⇒ shim hỏng (đỏ ở `smoke` hay ở bước biên dịch app)
# không làm mất VLEX ~8 phút vừa dựng.
STEP="${1:-all}"
case "$STEP" in
  assets | smoke | all) ;;
  *) die "bước không hợp lệ: $STEP (assets | smoke | all)" ;;
esac

mkdir -p "$OUT_DIR" "$SMOKE_DIR"
if [ "$STEP" != "smoke" ]; then
  if assets_ready; then
    echo "▶ vtts: tài sản đã có, khớp stamp (commit $VTTS_COMMIT, model $MODEL_RELEASE) — bỏ qua tải / dựng"
  else
    build_assets
  fi
fi
if [ "$STEP" != "assets" ]; then
  assets_ready || die "chưa có tài sản hợp lệ ở $ASSET_DIR — chạy bước assets trước"
  if [ -d "$CACHED_SMOKE_DIR" ]; then
    cp "$CACHED_SMOKE_DIR"/*.wav "$SMOKE_DIR"/ 2>/dev/null || true
  fi
  run_bridge_smoke
fi
echo "▶ vtts: xong ($STEP) — $(ls "$ASSET_DIR" | tr '\n' ' ')"
ls -l "$ASSET_DIR"
