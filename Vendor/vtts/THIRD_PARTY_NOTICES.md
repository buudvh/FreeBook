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
| `vtts/vtts-vien-nu10-m-v0.11.q8.vtts` | GitHub release `v0.11.0` của `tuanpmt/vtts` (từ 1.3.1052; `nu-10` = model v0.9.1 train joint 80k bước), khớp dòng tương ứng của `SHA256SUMS` release | Apache-2.0, như repo vtts | Có (`FreeBook.app/vtts/`) |
| `extra/vtts-vien-nu10-s-v0.11.q8.vtts` | Như trên (bản S, dự trữ) | Apache-2.0 | Không |
| `vtts/vtts-ngochuyen-m-k6.q8.vtts` (giọng "Nữ · Ngọc Huyền", 1.3.1044; bản k6 từ 1.3.1131) | FreeBook tự train (mục bên dưới), SHA256 ở `LOCAL_SHA256SUMS` | **CC BY-NC 4.0** (theo dữ liệu train) | Có |

Giọng `nam-1` (release, Apache-2.0) và giọng "Nữ · Google Dịch" (tự train, 1.3.1046) **đã gỡ khỏi repo và IPA ở 1.3.1135**
(anh Bửu); bản từ 1.3.1046 tới 1.3.1134 có chứa chúng — mục Google Dịch bên dưới giữ để ghi nguồn cho các bản đó.
| `vtts/lex_en.bin` (VLEX: từ điển tiếng Anh + bảng letter-to-sound) | Dựng bằng `tools/scripts/frontend/build_lexicon.py` từ `cmudict/cmudict.dict` (SHA256 ở `LOCAL_SHA256SUMS`) | Phần dẫn xuất từ CMUdict theo **BSD 2-clause** — `LICENSE-cmudict.txt` | Có |
| `cmudict/cmudict.dict` | **CMU Pronouncing Dictionary**, `cmusphinx/cmudict` commit `74790861f652b15e4ac49015a90074ad62a27690` (SHA256 trùng mức `tools/src/vtts/frontend/en/cmudict.py` ghim) | **BSD 2-clause** — `LICENSE-cmudict.txt` | Không |

**CMUdict** — Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. Repo phân phối CMUdict ở dạng
nguồn (`cmudict.dict`, điều khoản 1) và IPA phân phối dạng nhị phân dẫn xuất (`lex_en.bin`, điều khoản 2) ⇒ cả hai phải
kèm thông báo bản quyền, danh sách điều kiện và lời từ chối bảo đảm: toàn văn ở `LICENSE-cmudict.txt` (lấy từ đúng
commit ghim ở trên). `NOTICE` của vtts cũng ghi CMUdict cho blob từ điển này.

## Giọng Ngọc Huyền (`vtts/vtts-ngochuyen-m-k6.q8.vtts`)

Model dẫn xuất (adapted material) do FreeBook train, phân phối theo **Creative Commons Attribution-NonCommercial 4.0
International** (https://creativecommons.org/licenses/by-nc/4.0/) — **chỉ dùng phi thương mại**: app phát hành miễn
phí, không quảng cáo, không thu phí; muốn thương mại hoá phải bỏ giọng này. Không có bảo đảm nào đi kèm.

- **Dữ liệu giọng**: dataset `pnnbao-ump/ngochuyen_voice` (https://huggingface.co/datasets/pnnbao-ump/ngochuyen_voice),
  tác giả `pnnbao-ump`, giấy phép CC BY-NC 4.0 (card không ghi thêm điều kiện). Thay đổi của FreeBook: chuyển wav
  22 kHz, nối 24 lời thoại có xuống dòng, lọc câu theo điểm khớp ASR, train thầy VITS rồi chưng cất sang kiến trúc vtts.
- **Câu Anh / câu trộn**: sinh bằng VoxCPM2 của OpenBMB (https://github.com/OpenBMB/VoxCPM, Apache-2.0) nhân bản từ
  giọng trong dataset trên. Không dùng để mạo danh / lừa đảo (điều kiện sử dụng của VoxCPM2).
- **Điểm khởi đầu của thầy**: checkpoint Piper `vi_VN/vais1000/medium` (`rhasspy/piper-checkpoints`; bản phát hành
  `rhasspy/piper-voices` gắn MIT, model card ghi dữ liệu VAIS-1000 theo CC BY 4.0 —
  https://ieee-dataport.org/documents/vais-1000-vietnamese-speech-synthesis-corpus).
- **Kiến trúc + trainer + runtime**: vtts (Apache-2.0, như mục Mã nguồn).
- **Lượt train của file đang đóng vào app**: lượt Kaggle `vtts-k6` (2026-11-28) chạy tiếp bản trò từ checkpoint joint
  20k bước của lượt `vtts-k4` (2026-11-22) lên joint **80k** bước theo công thức chưng cất của upstream v0.9.1; cùng thầy,
  cùng dữ liệu (không thêm nguồn dữ liệu nào) ⇒ giấy phép giữ nguyên.

Trong app, dòng phụ của giọng ghi "pnnbao-ump · CC BY-NC 4.0" (`VttsVoice.credit`).

## Giọng Google Dịch (đã gỡ ở 1.3.1135; có trong bản 1.3.1046 – 1.3.1134)

Model dẫn xuất do FreeBook train, phân phối (trong các bản trên) theo **CC BY-NC 4.0** như giọng Ngọc Huyền (cùng điều
kiện phi thương mại, cùng dòng ghi nguồn trong app):

- **Tiếng dùng để train thầy**: tiếng đọc của Google Dịch (translate.google.com, giọng tiếng Việt) cho ~17.700 câu, lấy
  qua endpoint web **không chính thức** — không có giấy phép nào của Google cấp cho việc này. Tên "Google Dịch" chỉ để mô
  tả nguồn tiếng, FreeBook không liên kết với Google.
- **Câu chữ**: lời thoại của dataset Ngọc Huyền, câu Anh / câu trộn (Việt chen chữ Anh) và câu Wikipedia tiếng Việt
  (chỉ dùng làm câu cho máy đọc, không phân phối lại).
- **Điểm khởi đầu của thầy**: thầy Ngọc Huyền (mục trên) ⇒ kế thừa CC BY-NC 4.0 của dataset `pnnbao-ump/ngochuyen_voice`.
- **Lượt train của file đang đóng vào app**: mốc joint **60k** bước của lượt Kaggle `vtts-k6` (2026-11-28), chạy tiếp từ
  checkpoint joint 20k của lượt `vtts-k4` theo công thức chưng cất của upstream v0.9.1; cùng thầy, cùng dữ liệu ⇒ giấy
  phép giữ nguyên.
