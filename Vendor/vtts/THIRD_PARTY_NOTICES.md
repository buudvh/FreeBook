# Bản quyền phần vtts trong FreeBook (Tàng Công Các)

Ghi chú của FreeBook, đặt cạnh `LICENSE` / `NOTICE` nguyên văn của vtts. Không thay thế hai file đó.

## Mã nguồn

- `Sources/CVTTS/runtime/` — runtime C của vtts (https://github.com/tuanpmt/vtts), commit ở `VTTS_COMMIT.txt`, chép
  nguyên văn. Giấy phép Apache-2.0 (`LICENSE`), thông báo của tác giả ở `NOTICE` (giữ nguyên, phải đi kèm khi phân phối).
- `Sources/CVTTS/bridge/` — shim C của FreeBook gọi runtime trên (không sửa file nào của vtts).

## Tài sản đóng trong IPA (không commit, `Scripts/ci/fetch_vtts_assets.sh` tải / dựng lúc build)

Nằm ở thư mục `vtts/` trong bundle app:

| File | Nguồn | Giấy phép |
|---|---|---|
| `vtts-vien-nu10-m-v0.4.q8.vtts`, `vtts-vien-nam1-m-v0.4.q8.vtts` | GitHub release `v0.4.0` của `tuanpmt/vtts` (kiểm SHA256 theo `SHA256SUMS` của release) | Apache-2.0, như repo vtts |
| `lex_en.bin` (VLEX: từ điển tiếng Anh + bảng letter-to-sound) | Dựng bằng `scripts/frontend/build_lexicon.py` của vtts (cùng commit) từ **CMU Pronouncing Dictionary** (`cmusphinx/cmudict` commit `74790861f652b15e4ac49015a90074ad62a27690`, kiểm SHA256) | Phần dẫn xuất từ CMUdict theo **BSD 2-clause** — `LICENSE-cmudict.txt` |

**CMUdict** — Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. `lex_en.bin` là dạng nhị phân
dẫn xuất từ CMUdict được phân phối trong IPA ⇒ điều khoản 2 của BSD 2-clause yêu cầu kèm thông báo bản quyền, danh sách
điều kiện và lời từ chối bảo đảm: toàn văn ở `LICENSE-cmudict.txt` (lấy từ đúng commit ghim ở trên). `NOTICE` của vtts
cũng ghi CMUdict cho blob từ điển này.
