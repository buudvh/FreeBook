# Bản quyền phần vtts trong FreeBook (Tàng Công Các)

Ghi chú của FreeBook, đặt cạnh `LICENSE` / `NOTICE` nguyên văn của vtts. Không thay thế hai file đó.

## Mã nguồn

- `Sources/CVTTS/runtime/` — runtime C của vtts (https://github.com/tuanpmt/vtts), commit ở `VTTS_COMMIT.txt`, chép
  nguyên văn. Giấy phép Apache-2.0 (`LICENSE`), thông báo của tác giả ở `NOTICE` (giữ nguyên, phải đi kèm khi phân phối).
- `tools/` — phần công cụ của cùng commit, chép nguyên văn (Apache-2.0): `scripts/frontend/build_lexicon.py` + các module
  `src/vtts/...` nó cần (dựng lại từ điển VLEX), `runtime/tools/vtts_say.c` + `runtime/Makefile` (đọc thử trên CI).
- `Sources/CVTTS/bridge/`, `rebuild_lex_en.sh` — của FreeBook (không sửa file nào của vtts).

## Tài sản (`assets/`, lưu sẵn trong repo)

| File | Nguồn | Giấy phép | Vào IPA? |
|---|---|---|---|
| `vtts/vtts-vien-nu10-m-v0.4.q8.vtts`, `vtts/vtts-vien-nam1-m-v0.4.q8.vtts` | GitHub release `v0.4.0` của `tuanpmt/vtts`, khớp `SHA256SUMS` (nguyên văn file của release) | Apache-2.0, như repo vtts | Có (`FreeBook.app/vtts/`) |
| `extra/vtts-vien-nu10-s-v0.4.q8.vtts`, `extra/vtts-vien-nam1-s-v0.4.q8.vtts` | Như trên (bản S, dự trữ) | Apache-2.0 | Không |
| `vtts/lex_en.bin` (VLEX: từ điển tiếng Anh + bảng letter-to-sound) | Dựng bằng `tools/scripts/frontend/build_lexicon.py` từ `cmudict/cmudict.dict` (SHA256 ở `LOCAL_SHA256SUMS`) | Phần dẫn xuất từ CMUdict theo **BSD 2-clause** — `LICENSE-cmudict.txt` | Có |
| `cmudict/cmudict.dict` | **CMU Pronouncing Dictionary**, `cmusphinx/cmudict` commit `74790861f652b15e4ac49015a90074ad62a27690` (SHA256 trùng mức `tools/src/vtts/frontend/en/cmudict.py` ghim) | **BSD 2-clause** — `LICENSE-cmudict.txt` | Không |

**CMUdict** — Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. Repo phân phối CMUdict ở dạng
nguồn (`cmudict.dict`, điều khoản 1) và IPA phân phối dạng nhị phân dẫn xuất (`lex_en.bin`, điều khoản 2) ⇒ cả hai phải
kèm thông báo bản quyền, danh sách điều kiện và lời từ chối bảo đảm: toàn văn ở `LICENSE-cmudict.txt` (lấy từ đúng
commit ghim ở trên). `NOTICE` của vtts cũng ghi CMUdict cho blob từ điển này.
