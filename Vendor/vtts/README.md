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
| `assets/vtts/` | Đóng vào app (`FreeBook.app/vtts/`): 2 giọng M của release + `vtts-ngochuyen-m-k6.q8.vtts` + `vtts-googledich-m-k6.q8.vtts` + `lex_en.bin` — **chỉ** 5 file này (CI kiểm) |
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

`assets/vtts/vtts-ngochuyen-m-k6.q8.vtts` (1.3.1131, thay `vtts-ngochuyen-m-k4.q8.vtts` của 1.3.1044) =
`distill_nh/snapshots/M-vocos-p-bi-joint_0080000.q8.vtts` của lượt Kaggle `vtts-k6` (2026-11-28; trùng byte
`distill_nh/M-vocos-p-bi.q8.vtts`): thầy VITS warm-start từ Piper `vi_VN/vais1000/medium`, train trên dataset
`pnnbao-ump/ngochuyen_voice` (~20 giờ) + câu Anh / câu trộn nhân bản bằng VoxCPM2, rồi chưng cất sang bản M bằng trainer
vtts cùng commit `VTTS_COMMIT.txt` (runtime đọc được). Lượt `vtts-k4` (2026-11-22) dừng ở giai đoạn joint 20k bước;
`vtts-k6` chạy tiếp joint 20k → **80k** theo công thức chưng cất upstream v0.9.1 (cách upstream chữa lớp ồn "buzzy" của
`nu-10`, 1.3.1052).

`assets/vtts/vtts-googledich-m-k6.q8.vtts` (1.3.1131, thay `vtts-googledich-m-k4.q8.vtts` của 1.3.1046) =
`distill_gg/snapshots/M-vocos-p-bi-joint_0060000.q8.vtts` của chuỗi `gg` cùng lượt `vtts-k6` — mốc joint **60k**, không
phải file cuối `distill_gg/M-vocos-p-bi.q8.vtts` (80k). Tiếng Google Dịch (notebook `vtts-gg-data`, ~42 giờ, lọc ASR còn
~35 giờ) cho thầy VITS warm-start từ thầy Ngọc Huyền, rồi chưng cất như trên. Tiếng thầy lấy qua endpoint **không chính
thức** của Google Dịch — rủi ro bị yêu cầu gỡ, anh Bửu đã nghe báo và vẫn chọn đóng vào app; bị yêu cầu gỡ thì xoá file +
`VttsVoice.googleDich` + dòng `VOICES` / `LOCAL_SHA256SUMS`, sửa số file mong đợi của script.

**Chọn mốc**: notebook `vtts-k6` chấm từng mốc 10k bằng runtime C (`vtts_say --lang auto`, 12 câu tiếng Việt kiểu truyện
+ 4 câu trộn / Anh), luật anh Bửu duyệt = lấy mốc **UTMOS tiếng Việt cao nhất**:

| Giọng | Bản | UTMOS tiếng Việt | UTMOS câu trộn / Anh | whistle (rít, thấp = ít) |
|---|---|---|---|---|
| Ngọc Huyền | k4 joint 20k (bản cũ) | 2,284 | 2,74 | 1,09 |
| Ngọc Huyền | **k6 joint 80k** (đóng vào app) | **2,619** | 2,946 | 0,50 |
| Google Dịch | k4 joint 20k (bản cũ) | 2,70 | 2,749 | 3,97 |
| Google Dịch | **k6 joint 60k** (đóng vào app) | **2,907** | 2,94 | 4,12 |
| Google Dịch | k6 joint 80k | 2,665 | 2,716 | 0,75 |

Thầy VITS: Ngọc Huyền 3,157, Google Dịch 3,554. Google Dịch 80k ít rít hơn hẳn nhưng UTMOS tiếng Việt thấp hơn cả bản
cũ ⇒ theo luật lấy 60k (rít nhỉnh hơn bản cũ chút). UTMOS không trùng hẳn với "rè" tai nghe — không hứa hết rè; rè của
Google Dịch có sẵn trong tiếng Google Dịch gốc.

Cả hai: SHA256 ở `LOCAL_SHA256SUMS`; header (33 dim, 122 tensor, `token_set` vi-en) trùng từng byte với bản k4; CI đọc
thử như hai giọng release. Thay bằng lượt train mới: thay file (giữ tên hoặc sửa cả `VttsVoice` + `VOICES`), cập nhật
dòng `LOCAL_SHA256SUMS`.
