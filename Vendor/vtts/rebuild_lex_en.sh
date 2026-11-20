#!/usr/bin/env bash
# Dựng lại từ điển VLEX `assets/vtts/lex_en.bin` từ mã Python đã vendor (`tools/`, commit ở `VTTS_COMMIT.txt`) + CMUdict
# đã vendor (`assets/cmudict/cmudict.dict`) — KHÔNG cần mạng (proxy chết chặn mọi lượt tải lén). Python ≥ 3.11, chỉ thư
# viện chuẩn, ~8 phút (huấn luyện bảng letter-to-sound bằng Python thuần). Chạy được trên macOS / Linux / Git Bash.
#
#   bash Vendor/vtts/rebuild_lex_en.sh           dựng vào thư mục tạm, so SHA256 với LOCAL_SHA256SUMS (lệch ⇒ mã ≠ 0)
#   bash Vendor/vtts/rebuild_lex_en.sh --write   ghi đè assets/vtts/lex_en.bin + dòng của nó trong LOCAL_SHA256SUMS
#
# Dùng khi nâng runtime vtts (định dạng VLEX đi theo commit — runtime đọc blob tại chỗ): thay `tools/` bằng bản của commit
# mới trước, rồi `--write`. Xem `README.md`.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$HERE/assets"
MODE="${1:-check}"
case "$MODE" in
  check | --write) ;;
  *) echo "usage: $0 [--write]" >&2; exit 2 ;;
esac

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

PY=""
for c in python3.13 python3.12 python3.11 python3 python; do
  if command -v "$c" >/dev/null 2>&1 &&
    [ "$("$c" -c 'import sys; print(sys.version_info >= (3, 11))' 2>/dev/null)" = "True" ]; then
    PY="$c"
    break
  fi
done
[ -n "$PY" ] || { echo "❌ cần Python ≥ 3.11" >&2; exit 1; }

want_cmudict="$(awk '$2 == "cmudict/cmudict.dict" { print $1 }' "$ASSETS/LOCAL_SHA256SUMS")"
[ "$(sha256_of "$ASSETS/cmudict/cmudict.dict")" = "$want_cmudict" ] || { echo "❌ cmudict.dict lệch SHA256" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$HERE/tools/." "$WORK/"
# cmudict.py tìm `<gốc repo vtts>/data/cmudict/cmudict.dict` (parents[4] của chính nó) — ở đây gốc là $WORK.
mkdir -p "$WORK/data/cmudict"
cp "$ASSETS/cmudict/cmudict.dict" "$WORK/data/cmudict/cmudict.dict"

echo "▶ dựng lex_en.bin bằng $("$PY" --version 2>&1) (~8 phút)…"
(
  cd "$WORK"
  export https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
  PYTHONPATH=src "$PY" scripts/frontend/build_lexicon.py --out "$WORK/lex_en.bin"
)

new_sha="$(sha256_of "$WORK/lex_en.bin")"
old_sha="$(awk '$2 == "vtts/lex_en.bin" { print $1 }' "$ASSETS/LOCAL_SHA256SUMS")"
echo "  mới: $new_sha ($(wc -c < "$WORK/lex_en.bin" | tr -d '[:space:]') byte)"
echo "  cũ : $old_sha"
if [ "$MODE" = "--write" ]; then
  cp "$WORK/lex_en.bin" "$ASSETS/vtts/lex_en.bin"
  printf '%s  vtts/lex_en.bin\n%s  cmudict/cmudict.dict\n' "$new_sha" "$want_cmudict" > "$ASSETS/LOCAL_SHA256SUMS"
  echo "✅ đã ghi assets/vtts/lex_en.bin + LOCAL_SHA256SUMS"
elif [ "$new_sha" = "$old_sha" ]; then
  echo "✅ dựng lại trùng từng byte với bản trong repo"
else
  echo "❌ bản dựng lại khác bản trong repo" >&2
  exit 1
fi
