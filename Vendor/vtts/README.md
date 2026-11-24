# vtts trong FreeBook

Trình đọc **vtts Việt–Anh (Offline)**: runtime C99 + 2 giọng của https://github.com/tuanpmt/vtts (Apache-2.0) + 2 giọng
FreeBook tự train trên runtime / trainer cùng commit: **Ngọc Huyền** (1.3.1044) và **Google Dịch** (1.3.1046), cả hai
theo CC BY-NC 4.0. Mọi thứ
cần để build, kiểm thử và dựng lại đều nằm trong thư mục này — CI và app **không** tải gì từ upstream hay CMUdict (anh
Bửu, 2026-11-20: phòng repo upstream bị xoá).

| Đường dẫn | Nội dung |
|---|---|
| `VTTS_COMMIT.txt` | Commit upstream đang ghim (runtime, công cụ, VLEX cùng một commit) |
| `Package.swift`, `Sources/CVTTS/runtime/` | Gói SPM `CVTTS`: runtime chép nguyên văn, 27 ngôn ngữ phụ tắt (`VTTS_ENABLE_<L>=0`) |
| `Sources/CVTTS/bridge/` | Shim C của FreeBook (`vtts_bridge.h` — header duy nhất Swift thấy) |
| `assets/vtts/` | Đóng vào app (`FreeBook.app/vtts/`): 2 giọng M của release + `vtts-ngochuyen-m-k4.q8.vtts` + `vtts-googledich-m-k4.q8.vtts` + `lex_en.bin` — **chỉ** 5 file này (CI kiểm) |
| `assets/extra/` | Bản S của 2 giọng release (dự trữ, không vào app) |
| `assets/cmudict/cmudict.dict` | CMUdict nguồn để dựng lại `lex_en.bin` |
| `assets/SHA256SUMS` | 4 dòng vi-en (nguyên văn) của `SHA256SUMS` release model `v0.11.0`; `LOCAL_SHA256SUMS`: `lex_en.bin` + `cmudict.dict` + 2 giọng tự train |
| `tools/` | Công cụ upstream cùng commit: `build_lexicon.py` + module Python nó cần, `vtts_say.c`, `Makefile` |
| `rebuild_lex_en.sh` | Dựng lại `lex_en.bin` từ `tools/` + `cmudict.dict`, không mạng (Python ≥ 3.11, ~8 phút) |

CI: `Scripts/ci/check_vtts_assets.sh` (bước "Check vtts assets + smoke test" của `build-ipa.yml`) kiểm SHA256, dựng
`vtts_say` từ mã đã vendor và đọc thử câu Việt + Anh bằng từng giọng M, kiểm thử shim với ASan/UBSan. Bản quyền:
`THIRD_PARTY_NOTICES.md`.

## Kiểm `lex_en.bin` dựng lại được

```bash
bash Vendor/vtts/rebuild_lex_en.sh
```

Dựng vào thư mục tạm và so SHA256 với `assets/LOCAL_SHA256SUMS`. Bản trong repo dựng ngày 2026-11-20 bằng Python 3.12
(Windows) từ chính các file của `tools/` (trùng từng byte upstream ở commit ghim) và `cmudict.dict` này. Lượt đối chiếu
bằng `rebuild_lex_en.sh` trên máy đó **chưa chạy xong**: hết RAM ở bước huấn luyện letter-to-sound (`MemoryError`, máy
8 GB đang chạy nhiều thứ) — cần máy còn dư vài GB RAM.

## Nâng runtime (commit upstream mới)

1. Lấy bản LF của commit mới (máy Windows có `core.autocrlf` ⇒ đừng chép từ cây làm việc):
   `git -c core.autocrlf=false archive <commit> runtime/include runtime/src LICENSE NOTICE | tar -x -C <tạm>` rồi thay
   `Sources/CVTTS/runtime/{include,src}`, `LICENSE`, `NOTICE`; tương tự cho các file trong `tools/` (thêm module Python
   mới nếu `build_lexicon.py` import thêm). Sửa `VTTS_COMMIT.txt`.
2. Đối chiếu `OPT_LANGS` của `tools/runtime/Makefile` với `disabledLanguages` (`Package.swift`) và `VTTS_DISABLED_LANGS`
   (`Scripts/ci/check_vtts_assets.sh`); đọc lại `vtts.h` / `vtts_text.h` / `vtts_lex.h` xem API shim dùng có đổi.
3. `bash Vendor/vtts/rebuild_lex_en.sh --write` — định dạng VLEX đi theo commit (runtime đọc blob tại chỗ). Nếu
   `cmudict.py` ghim CMUdict khác, thay `assets/cmudict/cmudict.dict` (đúng commit + SHA256 nó ghim) trước.

## Nâng model (release mới)

Tải file `.vtts` + `SHA256SUMS` của release, kiểm khớp, thay trong `assets/vtts/` (M) và `assets/extra/` (S), thay
`assets/SHA256SUMS` bằng **đúng các dòng của file mình dùng**, giữ nguyên văn từng dòng (release từ `v0.11.0` gộp mọi
giọng — 22 file — nên không chép cả file; script đòi đúng 4 dòng); sửa tên file trong `VttsVoice` (`source: .bundled(fileName:)`, Swift) và `VOICES` trong
`Scripts/ci/check_vtts_assets.sh` + danh sách file của bước "Package IPA" (`build-ipa.yml`). `assets/vtts/` phải còn
đúng 5 file. Model mới phải đọc được bằng runtime ghim ở `VTTS_COMMIT.txt`: so header (dims + bảng tensor) với file cũ,
và bước đọc thử của CI là phép kiểm cuối. Lần gần nhất: 1.3.1052 — release `v0.11.0`, `nu-10` đổi sang model train
giai đoạn joint 80k bước (v0.9.1 / v0.10.2), `nam-1` trùng byte v0.4.0.

## Giọng tự train (Ngọc Huyền, Google Dịch)

`assets/vtts/vtts-ngochuyen-m-k4.q8.vtts` = `M-vocos-p-bi.q8.vtts` của lượt chưng cất `vtts-k4` (Kaggle, 2026-11-22):
thầy VITS warm-start từ Piper `vi_VN/vais1000/medium`, train trên dataset `pnnbao-ump/ngochuyen_voice` (~20 giờ) + câu
Anh / câu trộn nhân bản bằng VoxCPM2, rồi chưng cất sang bản M bằng trainer vtts cùng commit `VTTS_COMMIT.txt` (runtime
đọc được). SHA256 ở `LOCAL_SHA256SUMS`; CI đọc thử như hai giọng release. Thay bằng lượt train mới: thay file (giữ tên
hoặc sửa cả `VttsVoice.ngocHuyen` + `VOICES`), cập nhật dòng `LOCAL_SHA256SUMS`.

`assets/vtts/vtts-googledich-m-k4.q8.vtts` (1.3.1046) = `M-vocos-p-bi.q8.vtts` của chuỗi `gg` cùng lượt `vtts-k4`: tiếng
Google Dịch (notebook `vtts-gg-data`, ~42 giờ, lọc ASR còn ~35 giờ) cho thầy VITS warm-start từ thầy Ngọc Huyền, rồi
chưng cất như trên. Tiếng thầy lấy qua endpoint **không chính thức** của Google Dịch — rủi ro bị yêu cầu gỡ, anh Bửu đã
nghe báo và vẫn chọn đóng vào app; bị yêu cầu gỡ thì xoá file + `VttsVoice.googleDich` + dòng `VOICES` /
`LOCAL_SHA256SUMS`, sửa số file mong đợi của script.
