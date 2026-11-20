# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

## [1.3.1039] - 2026-11-20

### feat: Kệ — nút ⋮ mở tuỳ chọn truyện, nhấn giữ để chọn nhiều (Chọn tất cả, Thêm vào playlist, Thêm vào bộ sưu tập, Xoá)

Anh Bửu: thêm nút ba chấm dọc trên mỗi sách ở Kệ mở menu của sách; nhấn giữ lâu = chọn nhiều sách, có Chọn tất cả / Bỏ chọn tất cả, Xoá, Thêm vào playlist, Thêm vào bộ sưu tập → plan + mockup https://claude.ai/artifact/Es6YfEe94Zyi2uigCzMTPX → "Duyệt" (theo đề xuất: chỉ Kệ Sách + Lịch Sử, thanh thao tác đè thanh tab, Xoá ở Kệ hỏi hai hướng).

- **⋮** (`ShelfBookMoreButton`, mới): kiểu Danh sách cuối hàng sau badge chương mới (17pt, khung 32×44), kiểu Lưới cuối dòng "icon · Ch. N" (15pt), kiểu Chỉ bìa vòng tròn 26 nền đen 50% góc trên phải bìa (badge chương mới lùi sang trái). Bấm ⇒ `BookActionSheet` như nhấn giữ trước đây. Là tham số **opt-in** `onMore` của `ShelfBooksLayoutView`; thẻ lưới nhận `ShelfBookGridCardView.Accessory`.
- **Chọn nhiều** (`ShelfBookSelection` + `ShelfView+Selection`, mới): nhấn giữ (0,25 s, rung) ⇒ vào chế độ, truyện đó chọn sẵn. Header ✕ + "Đã chọn N" (`pageTitle(_:leadingIcon:)`) + "Chọn tất cả" / "Bỏ chọn tất cả" thay cụm 🔍 | …; nút "+" nổi ẩn. Chạm / nhấn giữ = chọn / bỏ, không mở truyện. Vòng chọn `ShelfBookSelectionMark` (mới); hàng đã chọn nền nhấn 18% + viền 60% (`bookListPanel(_:isHighlighted:)`), bìa đã chọn viền nhấn 3pt. Chỉ giữ `bookId`, mọi phép đếm / thao tác giao với danh sách đang hiện của trang (chip loại + NSFW, kể cả phần chưa phân trang tới — "Chọn tất cả" chọn hết). Thoát: ✕, đổi trang, mở Reader (thông báo / đĩa nghe), thao tác xong.
- **Thanh thao tác** `ShelfSelectionActionBar` (mới): cùng khuôn `MainTabBar`, `overlay` đè đúng chỗ thanh tab (không sửa thanh tab dùng chung). Thêm vào playlist · Thêm vào bộ sưu tập · Xoá.
- **Xoá**: Kệ Sách hỏi "Bỏ khỏi kệ (về Lịch sử)" (một lần lưu, `BookTransactionCoordinator+Batch.removeFromShelf(bookIds:)` chép luật bản một truyện) hoặc "Xoá hẳn khỏi máy" (`BookStorageManager.deleteBooksAsync`, lớp chờ "Đang dọn dẹp sách...", toast theo số thật đã xoá — truyện đang nghe TTS được giữ). Lịch Sử hỏi "Xoá N truyện khỏi lịch sử": trên kệ ⇒ `setHistory(bookIds:isHistory: false)`, không ở kệ ⇒ xoá khỏi máy.
- **Thêm vào bộ sưu tập**: sheet kính `CollectionBatchAddSheet` (mới) — chạm một bộ ⇒ `BookCollectionCoordinator.addBooks` (mới, **chỉ thêm**, một lần lưu; truyện ở Lịch sử lên kệ theo bất biến), "Tạo bộ sưu tập mới" tạo xong thêm luôn, toast "Đã thêm N truyện vào …".
- **Thêm vào playlist**: chỉ album âm thanh / phim (`PlaylistKind` qua `BookContentKindResolver`). Không có cuốn nào hợp ⇒ ô mờ + toast; có cả hai loại ⇒ hỏi Nhạc / Video; lấy mục lục **lần lượt** (`PlaylistAlbumItemsLoader.items`, ô hiện "Đang lấy i/N · Huỷ", bấm lại ⇒ huỷ) rồi mở `PlaylistAddSheet` (thêm tham số tuỳ chọn `onAdded`); truyện khác loại / album lỗi mục lục báo gộp một toast.
- Thêm xong (playlist / bộ sưu tập) ⇒ thoát chế độ chọn khi sheet đóng hẳn; vuốt đóng mà chưa thêm ⇒ giữ lựa chọn.
- Bộ sưu tập và Tìm trên kệ giữ nguyên (nhấn giữ vẫn mở sheet, không ⋮). Cụm nút phải header Kệ tách ra `headerTrailingButtons` (ngân sách type-check của `body`).
- `.claude/rules/ui-conventions.md` thêm luật. CHANGELOG: chuyển bản 1.3.1009 sang archive. Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **chưa build tại chỗ (Windows), chưa thử máy**.

## [1.3.1038] - 2026-11-20

### fix: vtts — phiên âm tiếng Nhật đọc được tên viết hoa, thêm "vtts tự đọc nhanh tối đa" để chỉnh độ rõ lời

Anh Bửu thử 1.3.1036: hết tiếng "vụt" nhưng "âm điệu nghe khác ver trước", "nghe không được rõ lời lắm" (hai file tự đọc nhanh thường / bản 4 "nghe như nhau" ⇒ do tự đọc nhanh, không do bản 4); "tôi bật phiên âm tiếng nhật nhưng không thấy hoạt động". Log máy: `speed=1.80`, `NghiHandoff delayMs` 12–39 ms (đổi file không gây hở tiếng). Anh duyệt plan + mockup.

- **Phiên âm tiếng Nhật**: `TTSJapaneseTextTransliterator` (dùng chung Siri / Google / tiện ích / vtts) chỉ đổi từ `ForeignScriptClassifier` chấm ≥ 4 điểm hoặc có trong `JapaneseLoanwordList` ⇒ "Konoha", "Naruto", "Sasuke" (1 điểm) không bao giờ đổi, vtts đọc tiếng Anh. `spokenForm` nhận thêm luật tên viết hoa của VieNeu (`VieNeuJapaneseNameReader.reads`). Không hạ ngưỡng bộ chấm điểm. vtts đọc kết quả ("Kô nô ha", "Na ru tô") bằng tiếng Việt — đã đối chiếu `word_tag` / `parse_syl` của runtime. Log `🗣️ [Vtts] Đoạn` thêm `jp=off` / `jp=on(N: Konoha→Kô nô ha, …)` (tối đa 2 cặp, `applyReportingChanges`).
- **"vtts tự đọc nhanh tối đa"** (mockup https://claude.ai/artifact/XPxHGwcaoi3ZF9GsC2apAM): `VttsNativeSpeedRow` (mới, `Views/Settings/TTS/`) ngay dưới thanh Tốc độ ở Cài đặt TTS và màn Giọng dự phòng khi chọn vtts, 1,0–2,0 bước 0,1, khoá `vttsNativeSpeedMax` (`@AppStorage`), mặc định 1,4 (ước lượng), dòng số "vtts đọc X · trình phát kéo thêm Y", giải thích sau nút "?" của "Cấu hình giọng nói", "Đặt lại" về mặc định. Thanh Tốc độ giữ nghĩa tốc độ nghe: `TTSManager.vttsNativeSpeed(forListeningSpeed:)` = min(tốc độ, tối đa) kẹp 1,0–2,0; `localPlaybackRate` / `remotePlaybackRate` kéo phần còn lại. Giá trị nằm trong `TTSSettingsSnapshot` (`vttsNativeSpeedMax`) và fingerprint giọng dự phòng ⇒ đóng Cài đặt là dựng lại đoạn như đổi tốc độ.
- Dọn: entry 1.3.1008 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi luật tên viết hoa + hàng mới. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1037] - 2026-11-20

### fix: Danh sách VietPhrase.dat / Names.dat (thẻ › Sửa) mở và tìm chậm — chỉ mục dựng một lần, trang đầu hiện ngay, tìm trên byte, kết quả hiện dần

Anh Bửu: "vietpharse tìm quá lâu, hiển thị ra cũng lâu, vì sao vậy?" → "tôi đang nói trong danh sách khi nhấn sửa ấy nhé" → plan → "Duyệt".

- **Nguyên nhân**: mở màn duyệt **hết** cây và dựng `String` cho từng khoá (cỡ triệu) rồi mới hiện; mỗi lượt tìm dựng lại bảng con của cây (vài mảng cỡ triệu phần tử) và dựng `String` + `range(of:options: .caseInsensitive)` cho **từng nghĩa** — từ hiếm phải quét hết cây, kết quả chỉ hiện khi quét xong.
- **Chỉ mục** `BaseDictionaryIndex` (`Models/Dictionaries/`, mới): dựng một lần mỗi lần mở màn ở nền — khoá dạng đơn vị UTF-16 nối liền một mảng + vị trí nghĩa trong pool `.dat`, thứ tự tiền thứ tự của cây như cũ. Phép duyệt **chép riêng** cùng phép tính của `walkEntries` (hàm đó giữ nguyên vì nuôi `allEntries` của nhập / gộp); không kiểm UTF-8 nghĩa lúc dựng (nghĩa hỏng hiện rỗng). 200 khoá đầu gửi về màn ngay khi có (`onFirstPage`), phần sau dựng chuỗi theo lượt 200 khi cuộn; tổng số từ lấy số mục chỉ mục (lúc đang dựng: `wordCount` ở đầu file). Lượt dựng không theo huỷ của `.task` (quay về từ "Từ đã sửa / đã xoá" không dựng lại).
- **Tìm** `BaseDictionaryIndexSearch` (mới): lớp sửa đổi (như cũ) ⇒ khoá **bắt đầu bằng** ⇒ khoá **chứa** (quét tuyến tính mảng UTF-16, không dựng chuỗi) ⇒ **nghĩa** chứa, so trên byte bằng `BaseDictionaryMeaningMatcher` (parser UTF-8 của stdlib, hạ thường theo `lowercaseMapping` dưới U+2000, không bỏ dấu, chuỗi tìm NFC; nghĩa có dấu rời / NFD đi đường Foundation cũ), quét theo lượt chia 2–3 luồng (1 luồng khi NghiTTS / VieNeu đang đọc). Kết quả gửi dần qua `AsyncStream` (`BaseDictionaryBrowser.searchUpdates`), dòng tổng ghi "Đang tìm… N kết quả" khi chưa xong; gõ tiếp ⇒ huỷ lượt quét; chỉ mục chưa xong thì lượt tìm chờ rồi tự chạy. Mỗi khoá một lần trong kết quả.
- Bỏ `FrozenTrieDictionary.allKeys()` và `BaseDictionaryBrowser.keys` / `search` cũ (không còn ai gọi). `walkEntries` / `allEntries` không đổi.
- Log `📚 [VPList]` (số mục, ms dựng, ms tới trang đầu) và `🔎 [VPList]` (ms phần khoá / nghĩa, số luồng, số nghĩa phải so bằng Foundation, đối chiếu 1000 nghĩa đầu giữa đường byte và Foundation — số lệch phải là 0) để đo trên máy.
- `translation.md`: sửa câu mô tả danh sách từ điển gốc. CHANGELOG: chuyển bản 1.3.1007 sang archive.
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy, chưa đo được nhanh lên bao nhiêu**. Cần thử: bật Ghi log, Cài đặt dịch thuật › thẻ VietPhrase.txt › Sửa — trang đầu phải hiện gần như ngay; tìm một chữ Hán, một chữ Việt hiếm, một chữ Việt thông dụng (vd "của"); gửi log.

## [1.3.1036] - 2026-11-20

### fix: vtts — tự đọc nhanh theo thanh Tốc độ, làm nhỏ dần đuôi cụt, tiếng sáng và to hơn

Anh Bửu nghe 4 bản vtts tạo tiếng nhanh 1,8× ngay từ gốc (CI 1.3.1035, câu "…phiên bản, đem mệnh danh…"): "4 cái đều không có tiếng vụt" ⇒ tiếng "vụt" ở 1,8× là do `AVAudioPlayer` kéo nhanh tiếng vtts. Duyệt plan bước 2 kèm "bản 4" (anh đã chọn trong lượt nghe so âm lượng).

- **Tự đọc nhanh**: `TTSManager.localSynthesisSpeed(forTool: "vtts")` = `vttsSynthesisSpeed` (khoá `vttsRate` kẹp `VttsTTSService.nativeSpeedRange` 1,0–2,0, chung trình đọc chính và giọng dự phòng) ⇒ `VttsTTSService` đưa `length_scale = 1 / tốc độ` vào vtts, khoảng lặng đuôi chia cho tốc độ, khoá tổng hợp mặc định có tốc độ. Trình phát chỉ kéo phần còn lại: `TTSManager.localPlaybackRate` (sửa tại chỗ 2 dòng `NghiAudioPlayerQueue.start` / `updateRate` của `TTSManager.swift`, không thêm dòng) và `remotePlaybackRate` khi vtts là giọng dự phòng. NghiTTS / VieNeu không đổi. Tốc độ chỉ đổi ở sheet Cài đặt TTS, nằm trong `TTSSettingsSnapshot` ⇒ đóng sheet là xoá hết đệm (cả đầu chương kế).
- **Đuôi cụt** — `VttsEdgeFade` (mới): WAV CI cho thấy mảnh vtts kết thúc ở dấu phẩy (vtts tự cắt câu > 40 âm tiết) bị cắt lúc âm còn −36 dBFS rồi rơi thẳng về 0 (cả hai giọng ở 1×). Làm nhỏ dần 20 ms trước mỗi khe số 0 tuyệt đối ≥ 100 ms (khe 150 ms bridge chèn) và ở cuối tiếng, to dần 5 ms sau khe; log `cut=`.
- **Bản 4** — `VttsLoudness.process` (viết lại): lọc thông cao 150 Hz + nâng +6 dB quanh 2,8 kHz (biquad RBJ) → RMS khung 20 ms có tiếng về −14 dBFS (≈ −16 LUFS; trước −16 dBFS), tăng tối đa +18 dB → ghìm đỉnh ≤ −1 dBFS (cực tiểu ±5 ms, trung bình trượt ±5 ms, nhả 80 ms) thay cho cách hạ cả đoạn của 1.3.1033 (cách cũ chặn mức to ~−17,5 LUFS). `VttsVoice.defaultLoudnessGainDb` theo mốc mới (nu-10 +10,5, nam-1 +7 dB). Log `🗣️ [Vtts] Đoạn` thêm `speed=`, `limit=`. Thuật toán trùng bản Python đã dựng 4 file anh nghe (nu-10 tốc độ gốc: +11,6 dB, ghìm −3,8 dB).
- CI: gỡ `render_listening_samples` (tạm của 1.3.1035) — `check_vtts_assets.sh` / `build-ipa.yml` về như trước 1.3.1034.
- Dọn: entry 1.3.1006 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi tự đọc nhanh, `VttsEdgeFade`, bản 4. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`. Chưa thử máy.

## [1.3.1035] - 2026-11-20

### fix: vtts — độ dài phân đoạn mặc định 500, log độ trễ chuyển đoạn, CI dựng câu nghe thử ở tốc độ gốc

Anh Bửu: "chỗ ngắt đoạn cũ đoạn mới hay có tiếng xoẹt xoẹt hoặc vấp". Anh thử câu "…Thổ Nạp Thuật phiên bản, đem mệnh danh là “Cá Trê Thổ Nạp Thuật”." (lỗi ở dấu phẩy): 1× + phân đoạn 500 sạch, 1× + 150 bị, 1,8× + 150 bị, 1,8× + 500 còn "vụt" nhẹ. vtts không có nhiễu ngẫu nhiên (cùng chữ ⇒ cùng mẫu) và tự cắt câu > 40 âm tiết **đúng dấu phẩy đó** (`MAX_SYL` của `vtts_text.c`; log máy `chars=187 chunks=2`) ⇒ ở 150 tiếng hai nửa câu y hệt, khác duy nhất là app xẻ thành 2 file ⇒ một lần đổi `AVAudioPlayer` giữa câu. Phần "vụt" ở 1,8× + 500 nằm trong một file ⇒ do trình phát kéo nhanh (chưa rõ cơ chế).

- `TTSManager.VttsSettings.defaultChunkLength` 150 → **500**: `NghiUtteranceSegmenter` luôn cắt ở dấu hết câu đầu tiên nên chunk vẫn là từng câu, chỉ câu > 150 ký tự thôi bị xẻ. Máy đã lưu `vttsChunk` giữ giá trị cũ (máy anh đã để 500).
- `NghiAudioPlayerQueue.lastHandoffDelayMs` (mới): ms từ delegate phát xong tới khi `play()` của player kế đã gọi; log `🔊 [TTSPerf] NghiHandoff` thêm `delayMs=` (sửa tại chỗ dòng log trong `TTSManager.swift`, không thêm dòng). Dùng chung NghiTTS / VieNeu / vtts — đo xem chỗ vấp có phải main kẹt lúc bàn giao (log anh có main kẹt 554 / 1045 ms).
- CI (tạm): bỏ phần đo Google (`Scripts/ci/tts_loudness_probe.py` xoá, `build-ipa.yml` thôi đưa `GOOGLE_CLOUD_TTS_API_KEY` vào bước vtts); `check_vtts_assets.sh` › `render_listening_samples` dựng câu của anh bằng 2 giọng: cả câu 1×, cả câu tốc độ gốc 1,8× (`vtts_say --speed 0.5556` — tham số này là `length_scale`), và 2 mảnh như khi cắt ở 150 ⇒ artifact `vtts-samples` để anh nghe so với app. Kết quả đo 1.3.1034: Google readaloud 6 giọng −19,8 LUFS, vtts 1.3.1033 đã ngang / to hơn (nu-10 −19,4, nam-1 −17,8) ⇒ vtts nghe nhỏ là do chất tiếng; bản "sáng và to hơn" anh chọn còn giữ tới khi nghe xong bản tốc độ gốc.
- Dọn: entry 1.3.1005 chuyển sang `CHANGELOG.archive.md`. `.claude/rules/tts.md` ghi lý do mặc định 500 + `delayMs`. Chưa build được tại chỗ (Windows); `check_architecture.py` chỉ còn violation cũ `JSDom.swift`.

## [1.3.1034] - 2026-11-20

### chore: vtts — CI đo tạm mức to Google TTS so với vtts để chọn mốc âm lượng

Anh Bửu: sau 1.3.1033 vtts vẫn "không to bằng google tts". Đo lại 2 WAV mẫu của CI: bản 1.3.1033 chỉ đưa vtts lên ~−17,7 LUFS (nu-10 −26,4 → −17,8; nam-1 −22,4 → −17,6 và đỉnh đã chạm trần −1 dBFS) — giữ đỉnh ≤ −1 dBFS bằng cách hạ **cả đoạn** nên mức to bị chặn, đoạn truyện dài đỉnh cao hơn còn được tăng ít hơn. Mốc −16 dBFS là ước lượng, chưa từng đo Google. Lượt này chỉ đo, chưa đổi app:

- `Scripts/ci/tts_loudness_probe.py` (mới, **tạm thời**, chỉ thư viện chuẩn): gọi Google readaloud đúng body của `GoogleTTSService.makeRequest` với cả 6 giọng (câu thử + một đoạn truyện ~30 s có thoại, câu cảm thán), giải mã bằng `afconvert` (lùi `ffmpeg`), đo LUFS tích hợp BS.1770, RMS lúc có tiếng (đúng cách `VttsLoudness` đo), đỉnh; vtts đọc cùng đoạn dài bằng 2 giọng, đo mức gốc + mô phỏng `VttsLoudness` 1.3.1033. In ra log CI + `loudness.txt` trong artifact `vtts-samples` (kèm WAV đoạn dài của vtts; audio Google không lưu). Không in key, lỗi gì cũng không làm đỏ build.
- `check_vtts_assets.sh`: hàm `probe_loudness` (tạm) chạy sau kiểm shim. `build-ipa.yml`: bước vtts nhận `GOOGLE_CLOUD_TTS_API_KEY` từ secret (tạm).
- Gỡ cả hai ở lượt sửa `VttsLoudness` tiếp theo. Dọn: 3 entry cũ nhất (1.3.1002–1.3.1004) chuyển sang `CHANGELOG.archive.md`.

## [1.3.1033] - 2026-11-20

### fix: vtts — giọng nhỏ, tự kéo âm lượng mỗi đoạn về mức TTS thường

Anh Bửu: "giọng nhỏ quá". Đo WAV đọc thử của CI (run 44685147889): model xuất nhỏ — `nu-10` đỉnh −11,3 dBFS, RMS lúc có tiếng −24,1 dBFS; `nam-1` −5,9 / −19,8 dBFS (TTS thường ~−16…−18 dBFS).

- `VttsLoudness` (mới, `Services/TTS/Vtts/`): đo RMS trên khung 20 ms có tiếng (> −45 dBFS) của **mỗi đoạn**, tăng về −16 dBFS; chỉ tăng 0…+12 dB, giới hạn để đỉnh ≤ −1 dBFS (không để `WAVEncoder` kẹp cứng gây rè); đoạn có tiếng < 0,4 s dùng mức cố định theo giọng (`VttsVoice.defaultLoudnessGainDb`: nu-10 +8, nam-1 +3,5 dB). Dùng Accelerate (`vDSP`).
- `VttsTTSService` gọi trước khi nối khoảng lặng đuôi ⇒ áp cho trình đọc chính, giọng dự phòng và ▶ thử giọng (cùng đi qua service). Log `🗣️ [Vtts] Đoạn` thêm `gain=+X.XdB`.
- Mô phỏng thuật toán trên 2 WAV mẫu: nu-10 +8,6 dB (đỉnh −2,7 dBFS), nam-1 +4,8 dB (đỉnh −1,1 dBFS), cả hai RMS −16 dBFS. Mốc −16 dBFS là ước lượng, chưa so với VieNeu / Google. Không thêm giao diện.
- Chưa thử máy; `.claude/rules/tts.md` ghi thêm.

## [1.3.1032] - 2026-11-20

### fix: vtts — CI dựng vtts_say kèm stub ZH/JA/RU, kiểm tài sản trong IPA, toast lỗi ghi đúng trình đọc

Sửa sau review phản biện (2 agent, chỉ đọc) trước lượt push đầu của vtts:

- **CI sẽ đỏ chắc chắn**: `check_vtts_assets.sh` dựng `vtts_say` với đúng cờ tắt ngôn ngữ của gói SPM, nhưng `vtts_say.c` (upstream) luôn gọi `vtts_zlex_init` / `vtts_jlex_init` / `vtts_rlex_init` — chỉ được định nghĩa trong `#if VTTS_ENABLE_ZH / _JA / _RU` ⇒ `Undefined symbols` lúc link. Thêm `Scripts/ci/vtts_say_lex_stubs.c` (3 hàm trả `-1`, chỉ link vào `vtts_say`), giữ nguyên cờ của app; `build-ipa.yml` thêm file này vào `paths`.
- **Bước Package IPA kiểm `FreeBook.app/vtts/`** có đủ `lex_en.bin` + 2 giọng M (folder reference nằm trong thư mục gói SPM cục bộ — chưa từng build; thiếu thì vtts lỗi ngay đoạn đầu).
- Toast / log lỗi tổng hợp của đường phát local chung ghi tên trình đọc đang dùng (`TTSManager.localReaderLabel`: NghiTTS / VieNeu / vtts) thay cho luôn "NghiTTS" — sửa tại chỗ 2 dòng `TTSManager.swift`, không thêm dòng.
- Dọn: 7 entry cũ nhất (1.3.995–1.3.1001) chuyển sang `CHANGELOG.archive.md` (file chính giữ 30 entry); `AGENTS.md` + `ci-release.md` ghi điều kiện chạy CI mới.
- Review không thấy lỗi biên dịch Swift / C nào khác (đối chiếu code, máy Windows không biên dịch được). Để sau (ghi nhận, chưa sửa): lỗi front-end hiếm của một đoạn vtts làm dừng cả phiên đọc; runtime có thể nạp lại ngay sau khi vừa nhả (chỉ tốn ~4,7 MB, không lỗi).

## [1.3.1031] - 2026-11-20

### feat: vtts — lưu sẵn model, từ điển và công cụ dựng lại trong repo, CI không tải gì từ upstream

Anh Bửu (qua session chính): lưu sẵn toàn bộ dữ liệu vtts trong repo, phòng repo upstream / CMUdict bị xoá — CI và app không phụ thuộc mạng tới `tuanpmt/vtts` hay `cmusphinx`. Thay phần tài sản của 1.3.1028–1029.

- **`Vendor/vtts/assets/`** (commit, `-text` trong `.gitattributes` ⇒ giữ nguyên byte): `vtts/` = **đúng** 3 file đóng vào app (2 giọng M release `v0.4.0` + `lex_en.bin`), `extra/` = 2 bản S dự trữ (không vào app), `cmudict/cmudict.dict` (commit `74790861…`, SHA256 trùng mức `cmudict.py` ghim), `SHA256SUMS` nguyên văn của release (4 model đã kiểm khớp trước khi commit) + `LOCAL_SHA256SUMS` (`lex_en.bin`, `cmudict.dict`). `lex_en.bin` dựng trên máy này bằng `build_lexicon.py` ở commit ghim `c5c8c00` (1 860 736 byte).
- **`Vendor/vtts/tools/`**: công cụ upstream cùng commit, chép nguyên văn (đã so hash git từng file): `scripts/frontend/build_lexicon.py` + 8 module `src/vtts/...` nó import (chỉ thư viện chuẩn), `runtime/tools/vtts_say.c`, `runtime/Makefile`. Nằm ngoài target SPM ⇒ không vào app. **`Vendor/vtts/rebuild_lex_en.sh`** (mới): dựng lại `lex_en.bin` từ `tools/` + `cmudict.dict` trong thư mục tạm, chặn mạng bằng proxy chết, so SHA256 (hoặc `--write` để ghi đè) — đã thử import + đọc CMUdict offline (126 052 từ); lượt dựng đầy đủ trên máy này hết RAM (`MemoryError` ở bước huấn luyện letter-to-sound, máy 8 GB chỉ còn ~0,8 GB trống) nên **chưa đối chiếu lại từng byte**. `Vendor/vtts/README.md` (mới): bố cục + cách dựng lại / nâng runtime / nâng model.
- **`Scripts/ci/check_vtts_assets.sh`** thay `fetch_vtts_assets.sh` (xoá): không mạng, không cache — kiểm SHA256 mọi tài sản + `assets/vtts/` đúng 3 file, dựng `vtts_say` từ mã đã vendor đọc thử câu Việt + Anh bằng từng giọng M (kiểm `token_set vi-en`, `mode auto lex 1`, id < vocab, WAV ≥ 1 s, không im lặng), kiểm thử shim với ASan/UBSan như trước. `build-ipa.yml`: một bước "Check vtts assets + smoke test" thay 4 bước cache / tải / lưu / smoke; `paths` đổi sang `check_vtts_assets.sh`. `project.yml`: folder resource `Vendor/vtts/assets/vtts` (bundle vẫn là `vtts/`, Swift không đổi đường tra). `.gitignore` bỏ `/Vendor/vtts-assets/`.
- Bản quyền: `THIRD_PARTY_NOTICES.md` ghi thêm `tools/`, bản S, CMUdict nguồn trong repo (BSD-2 điều khoản 1) bên cạnh VLEX trong IPA (điều khoản 2). Chú thích `Package.swift`, `VttsVoice`, `VttsRuntime`, `vtts_bridge_smoke.c`, `ci-release.md` cập nhật theo.
- Dung lượng thêm vào git: ~13,1 MB tài sản (4 model 7,57 MB + `lex_en.bin` 1,86 MB + `cmudict.dict` 3,62 MB) + ~85 KB công cụ.
- Kiểm: `bash -n`, thử phần kiểm SHA256 của script mới trên Windows (bắt được file thừa trong `assets/vtts/`), YAML hợp lệ, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`). **Không biên dịch / chạy `vtts_say` được tại chỗ (Windows)** — chỉ CI.

## [1.3.1030] - 2026-11-20

### chore: Màn tự thử nhịp dọc header (tạm thời), đầu dò header sửa cho iOS 26, mũi back tự dựng trùng chỗ mũi back hệ thống

Anh Bửu chọn mốc B ("đáy thanh +16": nội dung đầu tiên cách đáy thanh tiêu đề / đáy ô tìm 16pt) sau log đo 1.3.1025 (iPhone 11: Form không tiêu đề nhóm 35pt, dưới ô tìm 50pt, List trơn 0pt, panel 4pt; mũi back hệ thống x=12 trong khi nội dung x=20) → duyệt bản đo.

- **Màn "Thử nhịp dọc header"** (tạm thời, Cài đặt › Ghi log hệ thống › Chẩn Đoán; `Views/Settings/Logs/HeaderSpacingLab/`): một nút **Chạy** tự đẩy lần lượt 22 trang mẫu — Form không / có tiêu đề nhóm, Form dưới ô tìm, List trơn (có / không ô tìm), panel ScrollView, header tự dựng — mỗi kiểu với các cách chỉnh khoảng trên (`contentMargins` top 0 / 16, `defaultMinListHeaderHeight` 0, `listSectionSpacing(.compact)`, đệm panel 16). Mỗi trang ~1,7 s: đầu dò UIKit (`HeaderSpacingLabProbe`) chụp đáy thanh, đáy ô tìm, mũi back hệ thống, ô / khung tiêu đề nhóm đầu; `labMeasure` (khung SwiftUI) đo chữ tiêu đề nhóm, chữ hàng đầu, panel đầu, icon "…" phải, mũi back tự dựng. Kết quả hiện trên màn + log `📐 [HeaderLab]` (kèm một lần cây view con của thanh: lớp + khung, để biết iOS 26 dựng ô nút toolbar bằng gì) + nút chia sẻ báo cáo. Gỡ cả thư mục khi đã áp.
- **Đầu dò `📐 [HeaderLayout]`** (`PageHeaderLayoutProbe`, vẫn tạm): iOS 26 không còn lớp "HostingView" trong thanh (1.3.1025 ra `left=- right=-`) ⇒ đo **view lá** nhìn thấy ở hàng nút, chia trái / phải (số mảnh, mép trái nhất – phải nhất); trang có tab vuốt (Kệ, Kho tiện ích) ⇒ đo scroll view dọc trong trang đang hiện; chọn scroll view theo phần **nằm trong cửa sổ**; `note=scrolled / offscreen / nobar` đánh dấu dòng nhiễu.
- **Mũi back tự dựng trùng chỗ mũi back hệ thống**: `HeaderBackButton` lùi `HeaderMetrics.backChevronOutdent` (8pt) ra ngoài lề (bề ngang bố cục 30pt, vùng chạm vẫn 38pt) ⇒ mũi ở `lề − 8` như nút back hệ thống (đo: x=12 khi lề 20). Áp cho trang con trong sheet, sheet hub, Reader, truyện tranh, trang xem phim mở bằng UIKit. Khoảng mũi → chữ tiêu đề giữ ~8pt.
- `ui-conventions.md`: luật nút back tự dựng thêm phần lùi 8pt.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần: mở Cài đặt › Ghi log hệ thống › Thử nhịp dọc header, bấm Chạy, để yên ~50 s, bấm chia sẻ gửi báo cáo; nhìn mũi back ở trang con sheet hub / Reader có thẳng với mũi back của trang Cài đặt không.

## [1.3.1029] - 2026-11-20

### chore: vtts — CI giữ cache từ điển khi build đỏ, kiểm thử shim nhanh hơn

Tiếp 1.3.1028 (rà lại trước khi đẩy; chưa lượt CI nào chạy bản vtts).

- **Cache tài sản vtts tách `actions/cache/restore` + `save`**: `actions/cache` gộp chỉ lưu khi cả job xanh ⇒ lượt đầu mà shim C / code Swift còn lỗi biên dịch sẽ dựng lại VLEX ~8 phút mỗi lần đẩy sửa. Nay `fetch_vtts_assets.sh` có hai bước — `assets` (tải model, dựng VLEX, `vtts_say` đọc thử) rồi lưu cache ngay, sau đó `smoke` (kiểm thử shim) — không tham số vẫn chạy cả hai (build local). Bước `smoke` từ chối chạy khi chưa có tài sản khớp stamp.
- **Kiểm thử shim nhẹ hơn**: bản dựng thử đặt `-DVTTS_BRIDGE_SEGMENT_CP=150` ⇒ đường chia đoạn dài chạy với 8 bản câu thử (~550 code point, 4 phần) thay vì ~60 bản (~4 phút tiếng dưới ASan, mỗi giọng); chỉ giọng đầu chạy đoạn dài (`--long`), vẫn đòi đúng 8 lần tiếng câu thử + khoảng 150 ms. `vtts_bridge.c` thêm `#error` khi `VTTS_BRIDGE_SEGMENT_CP` ra ngoài `[1, VTTS_TEXT_MAX_CP)` ⇒ không phần nào chạm mức 4096 code point mà front-end cắt im lặng. Thêm `-fno-sanitize=function` (Apple clang mới bật nó cho C; tránh báo động nhầm ở callback nội bộ của upstream).
- `ci-release.md`: mục vtts ghi hai bước + cách lưu cache.
- Kiểm: `bash -n`, thử lại các hàm kiểm stamp / WAV của script trên Windows, YAML hợp lệ, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`). **Không biên dịch được C / Swift tại chỗ (Windows).**

## [1.3.1028] - 2026-11-20

### feat: vtts Việt–Anh — runtime C, tài sản đóng trong IPA, service tổng hợp

Anh Bửu duyệt plan `Docs/Plans/2026-11-20-vtts-integration.md` (phần A — nền tảng; phần B là 1.3.1027). Nguồn ghim: `tuanpmt/vtts` commit `c5c8c0018dc6a1651d8ee6d4ec3635f6ff2f8e1e` (Apache-2.0) cho runtime lẫn script dựng từ điển, model release `v0.4.0` (`nu-10` nữ, `nam-1` nam, bản M, 2 580 320 byte mỗi file).

- **Gói SPM cục bộ `Vendor/vtts`** (product `CVTTS`, `project.yml` dùng `path:`): `Sources/CVTTS/runtime/{include,src}` chép nguyên văn ở commit ghim (`VTTS_COMMIT.txt`), kèm `LICENSE` / `NOTICE` của vtts; mọi ngôn ngữ phụ tắt bằng `VTTS_ENABLE_<L>=0` (27 ngôn ngữ, cấu hình `langs_test_none` của upstream) ⇒ chỉ còn Việt / Anh / auto. Bridging header của app không đổi.
- **Shim C `vtts_bridge`** (`Sources/CVTTS/bridge/`, header công khai duy nhất Swift thấy — không struct nào của vtts lộ ra): `create` mmap model + VLEX và giữ suốt đời handle (cả hai được đọc tại chỗ), workspace front-end ~145 KB trên heap, fd đóng ngay sau mmap; `synthesize` = `vtts_text_to_ids_ex` chế độ `VTTS_LANG_AUTO` (chọn Việt / Anh theo từng từ, có VLEX) ⇒ mỗi chunk ≤ 40 âm tiết tổng hợp riêng, nối với 150 ms im lặng như `tools/vtts_say.c`. Khác `vtts_say`: lấy số khung thật bằng `vtts_durations` rồi mới cấp arena / PCM đúng cỡ (vtts_say cấp theo n × max_duration — hàng chục MB với 320 id); id ngoài từ vựng ⇒ lỗi thay vì đọc lố bảng embedding; đoạn > 2000 code point tự chia ở ranh giới câu (front-end cắt **im lặng** phần sau 4096 code point); thẻ huỷ nguyên tử xét trước mỗi chunk. Model không phải bộ token vi-en / không có chế độ auto ⇒ mã lỗi riêng.
- **`Scripts/ci/fetch_vtts_assets.sh`** (máy Mac chạy trước `xcodegen`, idempotent theo `.stamp`): tải + kiểm SHA256 2 model; clone vtts ở commit ghim, so runtime đã vendor **từng byte** (lệch ⇒ đỏ); dựng `lex_en.bin` bằng `scripts/frontend/build_lexicon.py` (CMUdict ghim + SHA256, Python ≥ 3.11 chỉ thư viện chuẩn, ~8 phút — đo trên máy Windows: 1 860 736 byte); dựng `vtts_say` bằng clang với đúng cờ tắt ngôn ngữ của gói, đọc thử "Đã kết nối Bluetooth với AirPods, chương này tên là The Last Train." bằng từng giọng (kiểm `token_set vi-en`, `mode auto lex 1`, id < vocab, WAV ≥ 1 s, không im lặng); **luôn** biên dịch shim + runtime đã vendor + `Scripts/ci/vtts_bridge_smoke.c` với ASan/UBSan và chạy từng giọng (câu thử, chuỗi rỗng, chỉ dấu câu, đoạn > 4096 code point, thẻ huỷ), so WAV shim với `vtts_say` (lệch chỉ cảnh báo). Tài sản ⇒ `Vendor/vtts-assets/vtts` (gitignore), `project.yml` khai folder resource ⇒ `FreeBook.app/vtts/`.
- **`build-ipa.yml`**: bước Cache (khoá = hash script + `VTTS_COMMIT.txt` + tên model) + chạy script trước `xcodegen generate` (`pipefail`); artifact `vtts-samples` (WAV đọc thử); `paths` của `push` / `pull_request` thêm `Vendor/vtts/**`, `fetch_vtts_assets.sh`, `vtts_bridge_smoke.c`.
- **Swift `Services/TTS/Vtts/`**: `VttsVoice` (2 giọng, `resolve` id lạ ⇒ `nu-10`), `VttsRuntime` (handle theo giọng, **mọi** lượt gọi C trên **một** hàng đợi nối tiếp — front-end vtts có mảng `static` toàn cục, runtime có setter toàn cục; tra / nhả handle chỉ trong hàng đợi; `releaseAll` không chặn), `VttsTTSService` (`LocalTTSEngine`, qua `PiperSynthesisCoordinator`; tổng hợp `length_scale = 1`, tốc độ do `NghiAudioPlayerQueue`; khoảng lặng đuôi `VieNeuTTSEngine.pauseSeconds(for:)` như Turbo; áp "Phiên âm tiếng Nhật" của chính trình đọc ở tầng service (`TTSJapaneseTextTransliterator.apply(_, tool: "vtts")`) rồi NFC; WAV 22 050 Hz `WAVEncoder.encodePCM16`; `TTSEngineRTFStore` chia cho phần lời đọc; log `🗣️ [Vtts]` nạp giọng + mỗi đoạn (ký tự, số câu, ms, RTF), lỗi có `❌`, `CancellationError` không ghi lỗi).
- Bản quyền: `Vendor/vtts/THIRD_PARTY_NOTICES.md` + `LICENSE-cmudict.txt` (VLEX dẫn xuất từ CMUdict, BSD-2, phân phối trong IPA). `ci-release.md`: mục vtts (bước tài sản, commit ghim, cách nâng runtime / model).
- Kiểm: đọc code, `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`), `bash -n` + thử các hàm kiểm stamp / WAV của script trên Windows, YAML hợp lệ; tải 2 model và kiểm SHA256, dựng VLEX thành công trên máy này. **Không biên dịch được C / Swift tại chỗ (Windows)** — biên dịch, đọc thử và kiểm thử shim chỉ chạy trên CI; chưa thử trên máy iOS.

## [1.3.1027] - 2026-11-20

### feat: vtts Việt–Anh — nối trình đọc vào app, Cài đặt TTS, sheet chọn giọng, giọng dự phòng

Anh Bửu duyệt plan `Docs/Plans/2026-11-20-vtts-integration.md` + mockup màn Cài đặt TTS (phần B; phần A — runtime C, tài sản, `Services/TTS/Vtts/` — là commit riêng).

- **Nối vào `TTSManager`** (`TTSManager+Vtts.swift`, mới; khuôn VieNeu): `tool = "vtts"`; `isLocalEngine` **và** `isExtensionTool` thêm `"vtts"` cùng lúc; `localEngine` ⇒ `VttsTTSService.shared`. Khoá riêng `vttsVoice` / `vttsRate` / `vttsPitch` / `vttsChunk` (mặc định 150 ký tự) — `persistSpeed` / `persistPitch` / `persistVoice` / `persistChunkLength` / `resetPrefetchSettings` có nhánh vtts (không lọt vào `extRate_vtts`…). `TTSManager.swift` **không thêm dòng ròng nào** (3413 dòng): đổi tại chỗ dòng log của `tool.didSet` ⇒ `noteReaderToolChanged(from:)` và nhánh `vieneu` của `loadParamsForCurrentTool` ⇒ `applyOfflineModelParamsIfNeeded()` (VieNeu / vtts).
- **Nhả runtime**: trình đọc rời vtts ⇒ `releaseVttsRuntimeIfUnused` (giữ nếu vtts là giọng dự phòng của trình đọc online mới); sheet chọn giọng đóng sau lượt thử giọng vtts cũng gọi hàm này. Chuyển **sang** vtts không nhả VieNeu / Piper — đường cũ NghiTTS ↔ VieNeu cũng không nhả nhau khi đổi trình đọc.
- **Rà mọi chỗ so `"nghitts"` / `"vieneu"`**: vtts đi nhánh "không phải vieneu" (nhẹ như Piper) — ngưỡng đệm chung `nghittsSafeCachedTimeThreshold`, 1 lượt refill, 2 optional reserve; prefix chương kế chờ còn ≤ 2 dòng cha như VieNeu (`!= "nghitts"` ở `checkAndPromoteNextChapterAudioIfNeeded` / `TTSChapterPrefetcher`), nhịp nhiệt gọi `triggerNextChapterPrefetch` như VieNeu; khoá `nghittsPrefetchDelay` (Piper) không đụng. `currentPrefetchCount` rơi vào `extPrefetchCount` nhưng chỉ đường remote đọc nó.
- **Cài đặt TTS** (mockup): Picker thêm "vtts Việt–Anh (Offline)" sau VieNeu; "Giọng đọc" = hàng chung (`TTSVoiceEngine.vtts`: "Nữ · nu-10", "Có sẵn trong app · 2,6 MB", badge Nhẹ) ⇒ sheet chọn giọng chung (`VttsVoicePickerList`, mới: 2 giọng, ▶ thử giọng qua `TTSVoicePreviewPlayer` `.vtts`, không tải / xoá); "Quản lý riêng" chỉ "Phiên âm tiếng Nhật" (khoá `ttsJapaneseTransliterationEnabled.vtts`, mặc định tắt, giải thích sau "?"); nhánh cấu hình tiện ích của mục này nay xét `isExtensionTool` thay `!= "system"`; dòng cao độ "(*) Engine offline (NghiTTS/VieNeu/vtts)…"; "Tải trước dữ liệu" chỉ "Độ dài phân đoạn (vtts)" (50…500, bước 10) — `TTSSettingsView+Vtts.swift`, mới.
- **Giọng dự phòng**: `TTSOnlineFallbackSettings.Engine.vtts` ("vtts Việt–Anh (Offline)"); các toán tử ba ngôi hai engine đổi thành `switch` (`title`, `pickerTitle`, `speedKey`, giọng — `onlineFallbackVoice(for:)` mới); `fingerprint` có nhánh vtts; bản build thiếu dữ liệu ⇒ `engineUnavailable`. Màn Giọng dự phòng: hàng giọng + mục Quản lý riêng của vtts; chọn giọng ở đây chỉ ghi `vttsVoice` (`selectVttsVoice`), không đổi giọng trình đọc online.
- `TTSSettingsSnapshot` / `TTSSynthesisIdentity` không thêm trường: `tool` + `selectedVoice` + `chunkLength` + cờ tiếng Nhật theo `tool` + `fingerprint` đã phủ vtts. Khối đầu phiên log "vtts · <giọng>"; tab Cài đặt hiện "vtts".
- `tts.md`: thêm gạch "vtts Việt–Anh".
- Kiểm: đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows)** — biên dịch phụ thuộc type của phần A (`VttsVoice`, `VttsTTSService`), chỉ CI kiểm được; chưa chạy trên máy.

## [1.3.1026] - 2026-11-20

### fix: TTS tạm dừng lâu rồi bấm phát ở sheet nghe mini không phát lại — luôn bật lại phiên âm thanh, VieNeu / NghiTTS kiểm tiếng chạy thật

Anh Bửu: "có lỗi để pause truyện lâu bấm start bằng sheet mini thì không phát lại, phải bấm tai nghe mới được. Phần nghe nhạc thì chưa biết" → plan → "Duyệt".

- **Nguyên nhân (đọc code, chưa có log máy)**: nút tai nghe Reader (trang đã cuộn khỏi đoạn đang dừng) dừng hẳn phiên rồi dựng phiên mới ⇒ bật lại phiên âm thanh; nút ⏯ của sheet mini chỉ `resume()`. Đường đó (1) không bật lại `AVAudioSession` vì tin cờ `isAudioSessionConfigured` — trong lúc tạm dừng phiên có thể bị app khác phát tiếng, phim trong app trả phiên, nghe thử giọng ở Cài đặt TTS, cuộc gọi tắt mà cờ vẫn `true` (ngắt lúc TTS không phát trước đây không hạ cờ); (2) với VieNeu / NghiTTS không kiểm `play()` có chạy thật — trình phát báo `true` mà thời gian đứng yên ⇒ kẹt "đang phát" không tiếng (đường Google / tiện ích đã có bước kiểm `verifyRemoteResumeProgress`).
- **Sửa** (`TTSManager+ResumeRecovery`, mới): `resume()` đường tạm dừng → phát gọi `reactivateAudioSessionForResume()` (hạ cờ rồi `setCategory` + `setActive` lại) thay cho `configureAudioSession()`; VieNeu / NghiTTS phát tiếp được ⇒ `didResumeNghiPlayer()` kiểm sau 0,25 s, `currentTime` không tiến ⇒ dừng player, bật lại phiên, đọc lại đoạn hiện tại từ đầu đoạn. `handleInterruption` `.began` lúc TTS đang tạm dừng cũng hạ cờ phiên.
- Log `🔊 [TTSResume]` (bật lại phiên OK / lỗi; play() trả true mà không tiến ⇒ đọc lại đoạn) để xác nhận trên máy.
- **Nghe nhạc**: nút phát của trình nghe (`AudioPlaybackSession.play` → `prepareAudioForPlayback`) luôn `setActive(true)` trước khi phát ⇒ không dính lỗi này, không sửa.
- `tts.md`: thêm gạch "Phát tiếp sau tạm dừng".
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: tạm dừng TTS, mở app khác phát video / nhạc (hoặc nghe thử giọng ở Cài đặt TTS), quay lại bấm ⏯ ở sheet mini — phải đọc tiếp (VieNeu / NghiTTS có thể đọc lại từ đầu đoạn đang dừng); bật Ghi log để xem dòng `🔊 [TTSResume]`.

## [1.3.1025] - 2026-11-20

### chore: Log đo bố cục header 📐 [HeaderLayout] (tạm thời) để chỉnh khoảng cách dọc dưới tiêu đề

Anh Bửu: "hàng 1 với hàng 2 nhiều lúc cách khoảng rỗng, nhiều lúc khoảng hẹp", "hàng icon và hàng tiêu đề cũng có khoảng cách khác nhau giữa các màn hình" → plan header (đo trước khi chốt nhịp dọc 16pt) → "Làm tiếp".

- Mới `PageHeaderLayoutProbe` (`Views/Common/PageHeader/`, **tạm thời**): đầu dò UIKit 0×0 gắn ở mọi trang dùng `PageTitleModifier`. Chỉ khi công tắc Ghi log bật: ~0,8 s sau khi trang hiện ghi **một** dòng `📐 [HeaderLayout]` toạ độ cửa sổ (pt):
  - tiêu đề, kiểu tiêu đề, cách trình bày (gốc tab / đẩy vào / sheet / toàn màn), bề ngang cửa sổ, vùng an toàn trên;
  - thanh điều hướng: y, cao, lề trong (`layoutMargins`);
  - mũi back hệ thống (x, rộng, cao, tâm y);
  - các ô SwiftUI của toolbar bên trái / phải (x đầu–cuối, y, cao) — tiêu đề cạnh nút trái, cụm icon phải;
  - ô tìm `.searchable` (x, y đầu–cuối);
  - scroll view chính của trang (loại, y, inset trên, offset, gốc nội dung) và ô / tiêu đề nhóm đầu tiên của List (y, x đầu–cuối, cao).
- Không đổi gì trên màn. Có số thật rồi mới chốt cách đưa khoảng chân header → nội dung đầu tiên về một nhịp (Form / List thẻ đang chừa nhiều, List trơn / panel gần như sát) và vị trí mũi back hệ thống; xong thì **gỡ đầu dò**.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần: bật Ghi log, mở các màn mẫu, xuất log phiên gửi lại.

## [1.3.1024] - 2026-11-20

### fix: Header — mũi ‹ trang con sheet hub cùng màu nhấn, khoảng tiêu đề cạnh nút back thành token chung

Gom ba bản header (1.3.1020, 1.3.1022, 1.3.1023) từ session con; dọn hai chỗ session con để ngỏ.

- **Mũi ‹ trang con Tác vụ AI / Kiểm tra nguồn của sheet hub** (`FloatingHubAITaskListView`, `FloatingHubSourceCheckListView`): bỏ `tint: Color.primary` ⇒ màu nhấn như trang con Thông báo / màn kiểm tra trong cùng sheet hub (trước một sheet có hai màu mũi).
- **Khoảng tiêu đề lùi về nút back 17pt** thành `HeaderBackButton.titleOverlap` (trước là hằng `private` ở `PageTitleModifier` + chép tay ở hai file hub).
- Entry 1.3.1023 sửa câu "vùng chạm không đổi": khoảng 19 nút trước chưa có khung nay có khung 36×38 nên vùng chạm rộng thêm về bên trái.
- `CHANGELOG.md` dời 1.3.987–994 sang `CHANGELOG.archive.md` (giữ ~30 entry).
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1023] - 2026-11-20

### feat: Toolbar — nút ngoài cùng bên phải canh icon vào lề 16pt, icon tài sản trên toolbar 20pt

- Anh Bửu: "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau" — phần còn lại của lưới header chung (1.3.1017–1021): toolbar của thanh điều hướng hệ thống.
- Trước: icon nằm giữa khung chạm (36 hoặc 32 rộng) nên icon ngoài cùng lùi vào 6–10pt so với lề 16pt của tiêu đề / ô tìm / thẻ danh sách. Nay nút **ngoài cùng bên phải** của mỗi toolbar thêm `alignment: .trailing` vào `.frame(width:height:)` của icon (nút đã có khung giữ nguyên rộng / cao; khoảng 19 nút trước chưa có khung nay có khung 36×38 ⇒ vùng chạm rộng thêm về bên trái, icon vốn đã sát lề); nút bên trong cụm (🔍, ↻, nút dịch, Lọc, Chia sẻ) giữ canh giữa. Nút chữ (Lưu, Xong, `.headerTextButton()`), capsule "Áp dụng", nút "?" `SectionHelpButton`, `EditButton` không đổi.
- Số trần `17` của icon SF trong các nút đó → `HeaderMetrics.iconFontSize`; khung `36` / `38` → `HeaderMetrics.iconFrameWidth` / `iconFrameHeight` (đúng giá trị cũ, khung cao `36` giữ nguyên để không đổi cỡ thật). Icon tài sản `AppGlyph` trên toolbar → `HeaderMetrics.assetIconSize` (20pt, trước 17): nút sao chép của Gỡ lỗi từng bước (Legado), Lỗi & cảnh báo rule dịch nhanh; nút dịch `ReaderTranslationScopeMenuView(iconSize:)` của Chi tiết truyện; phễu `FilterGlyph` (đã 20, nay dùng token).
- Màn đã đổi: Kệ (🔍 | … — "…" ngoài cùng, chấm đỏ thông báo vẫn nằm đúng góc trên phải icon), Hộp thông báo, Chi tiết bộ sưu tập, Chi tiết truyện (nút dịch | …), Danh sách thể loại / Xem thêm (Lọc | Kiểu hiển thị), Tìm kiếm (Kiểu hiển thị), từ điển (VP / Name riêng, VP / Name chung, Phiên âm / Pronouns, sheet sửa từ có bút chì), Báo cáo kiểm tra (danh sách + chi tiết: Chia sẻ | Xoá), Gỡ lỗi từng bước (Legado), Danh sách kho (↻ | +), tab Legado + tab Tất cả tiện ích của Kho tiện ích, Bộ lọc tiện ích (Đặt lại), Playlist chi tiết, Cấu hình AI (+), Lịch sử phiên chat AI (thùng rác), Theo dõi nhiệt, Log phiên, Công cụ tra cứu nhanh, Dung lượng (↻ / vòng xoay đo), từ điển phiên âm NghiTTS / VieNeu, Thay thế TTS, Quản lý lọc rác, Bộ ngoặc, rule dịch nhanh (`QuickTranslationRuleIOMenu`), Quy tắc TOC.
- Không đụng (session khác làm hoặc đang làm): `PageHeader`, `HubStyleSheet`, `FloatingHub`, `TTSWidget`, `AudioPlayer`, `Reader`, `ComicReader`, `VideoPlayer`, `Discovery`, `SleepTimer`, `AppUpdate`, `ChapterTOCPanel`, `SideDrawerMenuPanel`, `SourceCheck`, `ExtensionCheckView`, `LegadoSourceCheckView`. `SideDrawerMenuModifier` chỉ có ví dụ trong comment, không có frame ⇒ không sửa.
- Kiểm: chỉ đọc code + check_architecture.py (chỉ còn violation cũ `JSDom.swift`); không build tại chỗ (Windows), chưa chạy trên máy. Cần thử: icon ngoài cùng ở các màn trên chạm đúng lề 16pt (so với tiêu đề / ô tìm / thẻ), chấm đỏ của "…" ở Kệ vẫn đúng góc, nút dịch ở Chi tiết truyện và sao chép ở Gỡ lỗi từng bước (20pt) không lệch hàng với nút bên cạnh.

## [1.3.1022] - 2026-11-20

### feat: Header sheet tự dựng — sheet hub, điều khiển nhanh TTS / nhạc, hẹn giờ, mục lục, cập nhật app về lề 16pt chung, nút back chung, tiêu đề 22pt

- Anh Bửu: "các header custom cho cảm giác logic thiết kế không giống", "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau" — áp tiếp lưới header chung (1.3.1017–1021) cho các sheet / panel tự dựng, giữ nguyên bố cục.
- Sheet hub (`FloatingHubSheet`): lề ngang trang chính / trang con nhỏ 20 → `HeaderMetrics.horizontalMargin` (16, máy ≥ 414pt 20). Tiêu đề "Lối tắt nổi" giữ `.headline` (cùng khuôn sheet kiểu hub).
- Trang con Tác vụ AI / Kiểm tra nguồn của hub (`FloatingHubAITaskListView`, `FloatingHubSourceCheckListView`): bỏ nút `chevron.left` tự vẽ + `.padding(.leading, -10)` ⇒ `HeaderBackButton` (mũi chạm lề, giữ màu chữ `Color.primary`); tiêu đề `.headline` → 22pt đậm (`rowTitleFontSize`) ngay cạnh nút, lùi 17pt như trang con có nút ‹ của `PageTitleModifier`, một dòng, dài thì cắt đuôi.
- Sheet hành động kiểu hub (`HubStyleActionSheet`): lề 20 → `horizontalMargin`; tiêu đề giữ `.headline`.
- Sheet điều khiển nhanh TTS / nhạc (`TTSQuickControlSheet`, `AudioQuickControlSheet`) và sheet "đang đọc chương này" (`ReaderTTSSameChapterSheet`): lề 20 → `horizontalMargin`; nút ⏱ khung tối thiểu 44×44 canh giữa → 36×38 (`iconFrameWidth` / `iconFrameHeight`) canh phải ⇒ chưa hẹn giờ thì icon chạm lề (đang hẹn: viên "Hủy" ngoài cùng, giữ nguyên). Bìa 52 + tên giữ.
- Sheet Hẹn giờ TTS (`TTSQuickTimerSheet` + `TTSQuickTimerHeader`): lề header 12, hàng tên chương đang phát + tab con 16 → `horizontalMargin`; nút ⚙ `gearshape.fill` trong vòng 28 nền `tertiarySystemFill` → icon trơn `gearshape` 17pt nửa đậm khung 36×38 canh phải, lề phải 10 → `horizontalMargin` (vòng nền chỉ cho header nổi trên ảnh / phim).
- Header mục lục Reader / truyện tranh (`ReaderChapterListView`, `ComicChapterListSheet+Header`): lề 12 → `horizontalMargin`; cụm nút phụ 14pt khung 32 cách 4 giữ, chỉ nút đứng cuối canh icon phải (Reader: cập nhật / vòng xoay, truyện TXT trên máy thì nút dịch lại; truyện tranh: dịch lại, chưa có mục lục thì nút kệ).
- Đầu panel Mục lục (`ChapterTOCPanelHeader`, dùng chung Chi tiết / Reader / truyện tranh / danh sách tập): lề trái 16 / phải 10 → `horizontalMargin` hai bên; nút ↓↑ khung 36 canh phải; "Mục lục" 22 → `rowTitleFontSize`, bỏ `minimumScaleFactor(0.8)` (không co chữ, dài thì cắt đuôi); ô tìm kéo ra 6pt bù khoản đệm phải sẵn có của `ChapterTOCSearchField` để hai mép ô tìm vẫn bằng lề.
- Ngăn kéo menu (`SideDrawerMenuPanel`): tiêu đề 22 → `rowTitleFontSize`, bỏ co chữ; lề phải khi có phụ kiện 10 → 16 như lề hàng ngăn kéo ⇒ viên NSFW của bảng chọn nguồn Khám phá chạm lề 16.
- Sheet "Tất cả tập" (`VideoWatchEpisodeSheet`): hàng tiêu đề lề 16 / 10 → `horizontalMargin`, "Danh sách tập (N)" 22 → token, bỏ co chữ; nút đổi kiểu Lưới / Danh sách canh icon phải khi là nút ngoài cùng (kiểu Lưới), giữa khi đứng trước ↓↑ (kiểu Danh sách).
- Sheet Hẹn giờ tắt phim / nhạc (`MediaSleepTimerSheet`), "Bản cập nhật mới" (`AppUpdateSheet`), "Có gì mới ở bản này" (`AppReleaseNotesSheet`): lề ngang 20 → `horizontalMargin` (lề dọc 20 giữ), tiêu đề 22 → `rowTitleFontSize`; hai sheet cập nhật bỏ co chữ tiêu đề, icon cạnh tiêu đề cùng token cỡ.
- Chưa sửa (ngoài phạm vi): nội dung dưới vài header vẫn lề cứng 16 — `SleepTimerOptionsView`, `TTSQuickTimerChapterList`, `VideoEpisodeGridView`, `.padding(.horizontal)` của `ChapterTOCPanelBackground` ⇒ máy ≥ 414pt lệch 4pt so với tiêu đề.
- Kiểm: chỉ đọc code + check_architecture.py (chỉ còn vi phạm cũ JSDom.swift); không build tại chỗ (Windows), chưa chạy trên máy. Cần thử: sheet hub (trang chính, Tác vụ AI, Kiểm tra nguồn hai lượt — mũi ‹ chạm lề, chữ 22pt), sheet nghe TTS / nhạc (⏱ chưa hẹn và đang hẹn + "Hủy"), sheet Hẹn giờ TTS (⚙ trơn góc phải), mục lục Reader / truyện tranh / tab Mục lục Chi tiết (nút ↓↑ và hai mép ô tìm thẳng lề), ngăn kéo chọn nguồn Khám phá (viên NSFW), "Tất cả tập" hai kiểu, hai sheet cập nhật app.

## [1.3.1021] - 2026-11-20

### feat: Nút ⌄ của sheet Kiểm tra tiện ích / Kiểm tra nguồn và màn AI toàn màn dời sang trái, tiêu đề 22pt kế bên

Anh Bửu (sau danh sách các màn có 2 nút bên phải): "Kiểm tra tiện ích / Kiểm tra nguồn, khi mở dạng sheet / Màn AI toàn màn của Reader dời ⌄", "size tiêu đề bằng size tiêu đề bình thường nhé".

- Mới `HeaderLeadingIconButton` (`Views/Common/PageHeader/`): nút icon đứng **trước tiêu đề** ở hàng nút — icon SF 17pt nửa đậm, khung 36×44 canh trái (icon chạm lề), tiêu đề lùi `titleOverlap` 10pt vào khung để icon cách chữ ~10pt, tiêu đề đè lên không nhận chạm.
- `PageTitleModifier` thêm `leadingIcon` (kiểu `.leading`) + `.pageTitle(_:style:leadingIcon:)`: nút và tiêu đề 22pt đậm chung một `ToolbarItem`; tiêu đề cạnh nút có trần bề ngang như cạnh nút back.
- **Kiểm tra tiện ích / Kiểm tra nguồn mở dạng sheet** (`ExtensionCheckView`, `LegadoSourceCheckView`): lượt đang chạy ⇒ ⌄ thu nhỏ đứng trước tiêu đề (`SourceCheckHeaderButtons.leadingMinimize`), cụm phải chỉ còn Chia sẻ (canh icon vào lề phải). Mở dạng trang (có nút back) và trang con trong sheet hub giữ như cũ.
- **Màn AI toàn màn của Reader** (`ReaderAIFullScreenView`): ⌄ Đóng (trước là `chevron.down.circle` ngoài cùng bên phải) thành `chevron.down` trước tiêu đề "Trợ lý AI" 22pt đậm + tên phiên; bên phải chỉ còn "…" (khung 36, canh vào lề).
- `ui-conventions.md`: thêm luật nút ⌄ trước tiêu đề.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: Tiện ích › Kiểm tra (mở dạng sheet) lúc đang chạy — ⌄ bên trái thu nhỏ đúng, hết lượt thì ⌄ biến mất, tiêu đề về sát lề; màn AI toàn màn — ⌄ đóng màn, "…" mở ngăn kéo.

## [1.3.1020] - 2026-11-20

### feat: Header tự dựng màn đọc / xem / nghe + Khám phá — lề 16pt chung, nút back chung, "…" có vòng, khối tiêu đề hai dòng

- Anh Bửu: "các header custom cho cảm giác logic thiết kế không giống", "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau" — đưa header tự dựng của màn đọc / xem / nghe + Khám phá về lưới chung `HeaderMetrics` (1.3.1017); bố cục từng màn giữ nguyên, chỉ đồng bộ lề, cỡ, nút.
- Reader (`ReaderHeaderFooterOverlayView`): lề 10 → `HeaderMetrics.horizontalMargin` (cả hàng 2); `chevron.left` tự vẽ → `HeaderBackButton` màu chữ theo nền đọc; "…" ngoài cùng canh phải trong khung 36×38; cụm phải giữ cách 6 khung 36 (ngoại lệ đã ghi trong chuẩn); nút dịch hàng 2 icon 19 → 20 (`assetIconSize`); tên truyện 16 đậm → 16 nửa đậm, chương 13 medium → 13 thường (giữ mũi ⌄ và màu chữ 72%).
- Tấm phủ Reader Xoá từ rác / Dịch / Copy nội dung gốc: tiêu đề 20 → 22 đậm (`rowTitleFontSize`); lề ngang cả panel 12 → `horizontalMargin` để tiêu đề thẳng hàng với các hàng bên dưới (panel Dịch của truyện tranh dùng chung view nên đổi theo). Nút chọn chữ chevron 13pt trong vòng 28 giữ nguyên.
- Truyện tranh (`ComicReaderChromeView`): lề thanh trên 8 → `horizontalMargin` (thanh dưới giữ 8); back → `HeaderBackButton` trắng; tiêu đề đảo về đúng thứ tự bằng `HeaderTitleBlock`: tên truyện dòng 1 (16 nửa đậm trắng), chương dòng 2 (13, trắng 60%) — lối mở không mang tên truyện ⇒ chỉ một dòng tên chương; icon dịch 17 → 20; "…" canh phải.
- Trình phát phim (`VideoPlayerTopBar`, `VideoWatchPosterView`): lề 8 → `horizontalMargin`; ⌄ ngoài cùng trái canh trái trong khung 32×38 (cặp ⌄ ✕ giữ cách 2); menu `ellipsis` trơn → `ellipsis.circle` canh phải; cụm phải giữ cách 6 khung 36; tên phim / tập → `HeaderTitleBlock` (16 nửa đậm trắng / 13 trắng 70%). `VideoPlayerIconLabel` / `VideoPlayerIconButton` thêm tham số `alignment` (mặc định canh giữa — thanh dưới, danh sách tập không đổi).
- Trang đè lên màn xem (`VideoWatchPagePresenter`): nút back tự vẽ trong toolbar → `HeaderBackButton` (màu nhấn, giữ nhãn "Quay lại màn xem phim").
- Màn nghe (`AudioPlayerHeader`): lề 6 → `horizontalMargin`; ⌄ khung 44×44 → 38×44 canh trái (icon thường 17pt); `ellipsis` trơn 44×44 → `ellipsis.circle` khung 36×38 canh phải; giữa thành `HeaderTitleBlock` căn giữa: tên album dòng 1 (16 nửa đậm), "Phát từ album" dòng 2 (13, trắng 65%) — trước đây "Phát từ album" nhỏ nằm trên. Hàng giữ cao 48.
- Khám phá (`DiscoveryView`, `DiscoverySourceMenuButton`): ba nút lọc / lưới / tìm thôi là vòng tròn nền 38 cách 4 → nút trơn khung 32×38 cách 2 như cụm 🔍 | … của Kệ (nút lọc dùng kiểu `.toolbar` của `FilterGlyph`, icon 20), Tìm ngoài cùng canh phải; `.padding(.horizontal)` → `horizontalMargin`. Vòng tròn ảnh nguồn + tên / link nguồn bên trái giữ nguyên.
- Kiểm: chỉ đọc code + check_architecture.py (chỉ còn violation cũ JSDom.swift); không build tại chỗ (Windows), chưa chạy trên máy. Cần thử: mũi back / ⌄ / "…" chạm lề 16pt (20pt ở máy Plus / Pro Max và phim nằm ngang) ở Reader, truyện tranh, phim dọc + ngang, màn bìa phim, màn nghe, Khám phá; tên phim dài không đè cụm nút phải khi hiện đủ nút (hẹn giờ, phụ đề, khoá xoay); panel Dịch (Reader + truyện tranh) không xuống dòng khác trước ở máy 375pt; màu chữ header Reader ở nền Sáng / Trầm ấm.

## [1.3.1019] - 2026-11-20

### feat: Công tắc Mờ bìa NSFW ở sheet Kiểu hiển thị, đổi mọi chữ 18+ thành NSFW

Anh Bửu: "sửa những chỗ có chữ 18+ thành nsfw hết, ghi vào rule là nội dung nhạy cảm thì ghi là nsfw hoặc nội dung nhạy cảm thôi", "thêm config làm mờ cover nội dung nhạy cảm … có thể bật tắt ở kiểu hiển thị" → chọn mặc định **tắt**, bìa lớn Chi tiết **cũng mờ**, bỏ chỗ đặt ở Kiểu hiển thị danh sách, công tắc ở **góc phải hàng tiêu đề** sheet (mockup A) → duyệt.

- **Mờ bìa NSFW** (`Views/Common/NsfwCoverBlur/NsfwCoverBlurModifier.swift`, khoá `nsfwCoverBlurEnabled`, mặc định tắt):
  - Công tắc "Mờ bìa NSFW" ở góc phải hàng tiêu đề `BookListLayoutSheet` (mọi màn mở sheet Kiểu hiển thị; sheet không cao thêm) + "Làm mờ bìa nội dung nhạy cảm" ở Cài đặt › Giao diện › Nội dung nhạy cảm (`NsfwSettingsView`, thêm đoạn giải thích trong "?").
  - `BookCoverView` tự xét `RepositoryFilterPolicy.isNsfwBook` (chỉ khi công tắc bật) ⇒ Kệ, Lịch sử, Bộ sưu tập, Tìm trong Kệ, tab Tải, sheet nhấn giữ, Chi tiết (cả bìa lớn), đầu mục lục, widget TTS.
  - `RemoteCoverImage` mờ theo cờ môi trường `coversAreNsfw` do màn của nguồn đặt (`.nsfwCoverContext`): Khám phá (trang chủ section + tab danh mục — `DiscoveryView`), Thể loại / Xem thêm (`CategoryNovelsListView`), Tìm kiếm (`searchResultCover` + lưới `SearchSingleSourceResultsView`), đề xuất ở Chi tiết (`SuggestRowView`). Màn xem phim / nghe, playlist, avatar bình luận không gắn cờ ⇒ không mờ.
  - `.blur` luôn gắn (bán kính 0 khi không mờ, theo cạnh ngắn ×0,12, tối thiểu 6) để bật / tắt không đổi danh tính view (ô bìa không nháy placeholder); nhãn tag / dải tên đè ngoài nên vẫn rõ.
- **Đổi "18+" ⇒ "NSFW"** ở 133 chỗ (53 file `Sources/` + `.claude/rules` + `rules.md`): chữ trên màn hình ("Phim NSFW", "Chỉ nguồn NSFW", "Đánh dấu / Bỏ đánh dấu NSFW", "ẩn N nguồn NSFW", "Mục NSFW được bỏ qua", toast, lỗi sao lưu, tên che "mục NSFW" ở playlist), comment, log. "Nội dung 18+" ⇒ "Nội dung nhạy cảm" (bộ chọn Cấu hình tiện ích, nhãn trợ năng). Nhãn đỏ trên icon tiện ích (`ExtensionNsfwBadge`) thành "NSFW", chữ hệ số 0,22 (trước 0,28), dời phải thêm chút.
  - Giữ: từ khoá nhận diện `"18+"` trong `ExtensionNsfwClassifier`, ví dụ dữ liệu thẻ `"18+,nsfw"`, emoji 🔞 đầu log, "iOS 18+" trong `rules.md`, entry CHANGELOG cũ.
- Luật mới trong `AGENTS.md` (Quy ước đặt tên): nội dung nhạy cảm chỉ ghi "NSFW" / "nội dung nhạy cảm"; kèm ghi chú cách gắn mờ bìa cho màn danh sách mới.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: bật công tắc ở sheet Kiểu hiển thị (Kệ, Khám phá nguồn NSFW, Thể loại, Tìm một nguồn) và ở Cài đặt; nhãn NSFW trên icon ở cỡ nhỏ (danh sách Kho) và lớn (đầu Cấu hình tiện ích); bìa lớn Chi tiết.

## [1.3.1018] - 2026-11-20

### feat: Tiêu đề trang có nút trái luôn nằm cạnh nút trái, bỏ tiêu đề hàng 2

Anh Bửu (sau khi duyệt cỡ 28 cho hàng 2): "tôi đổi ý, đừng hiện tiêu đề 2 hàng nữa, để nó luôn hiển thị cạnh nút trái nếu có nút trái".

- **Trang có nút back** (`.backPageTitle` / `PageTitleStyle.centered`, ~64 trang): bỏ tiêu đề lớn hàng 2 của iOS (1.3.984–1.3.1017) ⇒ `navigationBarTitleDisplayMode(.inline)`, tiêu đề **22pt đậm** (cùng cỡ tiêu đề tab gốc / gốc sheet) ở ô `topBarLeading` ngay cạnh nút back, một dòng, không co chữ, trần bề ngang `HeaderMetrics.besideLeftButtonTitleMaxWidth` (rộng màn − 150, chừa nút back + cụm hai nút phải), dài thì cắt đuôi. Hết cảnh khoảng hở giữa hàng nút và hàng tiêu đề mỗi trang một khác, hết tiêu đề thu / bung khi cuộn.
- Bỏ đầu dò `PageTitleCollapseProbe` (dò nhãn tiêu đề lớn để hiện tiêu đề nhỏ khi thu) và cỡ tiêu đề lớn ở `NavigationBarAppearance` (`applyLargeTitleFont`); `HeaderMetrics` bỏ `largeTitleFontSize` / `inlineTitleFontSize` — tiêu đề trang còn **một cỡ** `rowTitleFontSize` 22.
- **Trang con trong sheet** (sheet hub: Thông báo, màn kiểm tra của một lượt; sheet kiểu hub: "Từ URL"…): nút ‹ (`HeaderBackButton`) và tiêu đề do `PageTitleModifier` dựng **chung một** `ToolbarItem` khi có `\.sheetPageBack` ⇒ thứ tự luôn ‹ rồi chữ, mũi cách chữ ~8pt. Bỏ `.sheetPageBackButton()` (mục toolbar riêng — hai mục `topBarLeading` thì iOS tự xếp); `SheetPageBackButtonModifier.swift` → `SheetPageBackEnvironment.swift` chỉ còn khoá environment.
- `ui-conventions.md`, `floating-pills.md` cập nhật theo.
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: trang có nút back (tiêu đề cạnh nút back, tên dài cắt đuôi, không đè nút phải), cuộn không còn thu / bung, trang con trong sheet hub và sheet "+" của Kệ ("Từ URL"): nút ‹ đứng trước tiêu đề, bấm về trang chính.

## [1.3.1017] - 2026-11-20

### feat: Header thống nhất — bộ số chung HeaderMetrics, tiêu đề hàng 2 28pt, tiêu đề hàng 1 không co chữ, nút back trang con trong sheet chạm lề

Anh Bửu: "hàng 1 và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau, title lớn chưa đủ to", "các header custom cho cảm giác logic thiết kế không giống" → mockup so sánh trước / sau (lề 16pt chung, 6 header tự dựng, nhịp dọc) → "Duyệt, cỡ 28".

- **Bộ số chung** `HeaderMetrics` (`Sources/Common/Utils/`): lề ngang = lề thanh hệ thống (16pt, máy ≥ 414pt 20pt), hàng 44, icon SF 17 / icon tài sản `AppGlyph` 20, khung 36×38 / back 38×44, tiêu đề hàng 1 22 / hàng 2 28 / cạnh nút back 17 / khối tiêu đề màn đọc-xem-nghe 16 + 13. Luật: mép vật nhìn thấy ngoài cùng chạm lề, nút ngoài cùng canh icon vào lề trong khung thay vì canh giữa.
- **Thành phần dùng chung** (`Views/Common/PageHeader/`): `HeaderBackButton` (`chevron.backward` 17pt nửa đậm cỡ ảnh lớn như mũi back hệ thống, khung 38×44, mũi canh trái) và `HeaderTitleBlock` (dòng 1 16pt nửa đậm, dòng 2 13pt màu phụ) — header tự dựng chuyển sang ở các bản sau.
- **Tiêu đề lớn hàng 2: 22 → 28pt đậm** (`NavigationBarAppearance.applyLargeTitleFont` đọc `HeaderMetrics.largeTitleFontSize`). Trước 22pt bằng tiêu đề hàng 1, nằm lọt thỏm trong ô iOS dựng cho chữ 34pt. Đầu dò thu tiêu đề (`PageTitleCollapseProbe`, ngưỡng ≥ 20pt) không đổi.
- **Tiêu đề hàng 1 không co chữ** (`PageTitleModifier`: bỏ `.minimumScaleFactor(0.8)`) — trước đây tên dài co còn 17,6pt nên mỗi trang một cỡ; nay dài thì cắt đuôi.
- **Nút ‹ của trang con trong sheet** (`SheetPageBackButtonModifier`: sheet hub, sheet kiểu hub, Thông báo, kiểm tra nguồn) dùng `HeaderBackButton`: trước là `chevron.left` nhỏ hơn mũi hệ thống, nằm giữa khung 38pt ⇒ mũi lùi vào ~30pt trong khi tiêu đề hàng 2 ở 16pt.
- `ui-conventions.md`: thêm mục "Lưới header chung".
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: tiêu đề hàng 2 các trang có nút back (cỡ, thu vào cạnh nút back khi cuộn), trang con trong sheet hub (mũi ‹ thẳng hàng tiêu đề).

## [1.3.1016] - 2026-11-20

### feat: Cài đặt dịch thuật — hàng con hiện theo công tắc QT / Áp dụng rule dịch, bỏ công tắc Dịch đại từ

Anh Bửu: "Bật dịch quick trans mới hiển thị các nav con", "bỏ config dịch đại từ đi vì nó trùng với cấu hình token rule <pn>", "quản lý rule dịch … là con của áp dụng rule dịch", "nav cấu hình dịch theo nguồn và truyện đổi thành cấu hình dịch riêng biệt" → qua 3 bản mockup: TOC / Lọc rác / Riêng biệt "luôn hiện và nằm panel khác", "từ điển chung phải cùng panel với Dịch Thuật Quick Translate", đại từ "tắt hẳn" → duyệt.

- **Màn Cài đặt dịch thuật** (`TranslationSettingsView`):
  - Panel "Dịch Thuật Quick Translate": công tắc QT; **chỉ khi bật** mới hiện các hàng con thụt 16pt — "Áp dụng rule dịch" ⇒ (chỉ khi công tắc này bật) "Quản lý rule dịch" thụt 32pt (`QuickTranslateRuleSettingsRows`, bỏ tham số `isTranslationEnabled`; chữ công tắc lên `.body` vì trước nhỏ hơn chính hàng con của nó), rồi **Từ điển chung** gộp vào cùng panel (nhãn "Từ điển chung" + lưới 5 thẻ, Tải từ điển mặc định / tiến độ, Làm mới dữ liệu dịch, Cấu hình công cụ tra cứu — `globalDictionaryRows`), trước là section riêng.
  - Panel riêng không tiêu đề, **luôn hiện**: Quản lý quy tắc TOC, Quản lý lọc rác, **Cấu hình dịch riêng biệt** (đổi tên từ "Cấu hình dịch theo Nguồn & Truyện"; tiêu đề trang đích vốn đã là tên này) — ba thứ vẫn có tác dụng khi tắt QT.
- **Bỏ công tắc "Dịch Đại từ (Pronouns)" ở cả 3 chỗ**: Cài đặt dịch thuật, Cài đặt trình đọc (`ReaderSettingsView` mất binding `isPronounsEnabled`, `ReaderView` mất `@AppStorage` + `onChange`), sheet Cài đặt dịch truyện tranh (`ComicTranslationSettingsSheet`, bỏ cả dòng giải thích + `notifyEngineSettingChanged` hết người gọi).
- **Engine — cố định tắt**: tách từ (`VietPhraseTokenizer`) và `TranslateUtils.lookupRawTranslation` **không** tra Pronouns nữa (thứ tự còn Name ⇒ VietPhrase); bỏ `TranslationReadContext.pronounsEnabled` và cờ đại từ trong khoá `TokenizeMemo` / `mappingMemo`. Đại từ chỉ dịch qua rule `<pn>` (`QuickTranslationDictionaryToken`, vốn đã bỏ qua công tắc). Pronouns.txt vẫn nạp cho `<pn>`, thẻ Pronouns.txt, panel tra từ. Không còn ai đọc khoá `isTranslationPronounsEnabled` (giá trị cũ trong UserDefaults / bản sao lưu vô hại).
- Câu hướng dẫn của panel rule ở Reader (`ReaderDefinitionOverlayView+Rules`) thêm bước "bật Áp dụng rule dịch".
- `CHANGELOG.md` dời 1.3.971–986 sang `CHANGELOG.archive.md` (giữ ~30 entry).
- Kiểm: chỉ đọc code + `check_architecture.py` (chỉ còn violation cũ `JSDom.swift`); **không build tại chỗ (Windows), chưa chạy trên máy**. Cần thử: bật/tắt hai công tắc ở Cài đặt dịch thuật (hàng hiện/ẩn, thụt lề, vạch ngăn), thẻ Từ điển chung trong panel QT (menu thẻ, nhập / xuất). Nếu máy đang bật Dịch đại từ: chữ ngoài rule đổi sang nghĩa VP; tên chương đã lưu (`title_trans`) giữ bản cũ tới khi "Dịch lại tên chương".

## [1.3.1015] - 2026-11-20

### feat: Nhấn giữ một phiên log ⇒ Xem log / Xuất log / Xoá log, màn Xem log ngay trong app

Anh Bửu: "làm thêm option xem log nữa" → "Màn Ghi log hệ thống — nhấn giữ một phiên sẽ hiển thị các option xem log, xoá log, xuất log" → duyệt mockup; push chung với lưới sheet nhấn giữ (1.3.1014).

- **Trước**: màn Ghi log hệ thống chỉ chọn phiên (nhiều) rồi Xuất `.txt` / Xoá; muốn đọc log phải xuất ra file.
- **Nay**:
  - `LogSettingsView`: nhấn giữ một phiên ⇒ menu Xem log / Xuất log (.txt) / Xoá log (đỏ, hỏi lại; phiên đang ghi không có). Danh sách chọn nhiều + các nút cũ giữ nguyên.
  - Mới `LogSessionViewerView` (trang đẩy vào): thẻ đầu = khối đầu phiên như file xuất (bản app, máy, iOS, nhiệt / RAM / ổ trống, TTS, trạng thái cuối); chip "Tất cả / Chỉ lỗi (N)" + chip đảo "Mới nhất trước / Cũ nhất trước"; ô lọc chữ luôn hiện (300 ms); mỗi dòng `HH:mm:ss.SSS` + nội dung chữ đơn cách 11pt, dòng ❌ chữ đỏ nền đỏ mờ; nhấn giữ dòng ⇒ "Sao chép dòng" (`ClipboardCopier`, có toast); nạp 500 dòng mỗi lượt, tới chân thì nạp tiếp (`LoadMoreFooter` id cố định); nút chia sẻ góc phải xuất cả phiên.
  - Mới `AppLogger+Browse` (`loadLines`, `loadSessionHeader`): ghi nốt dòng chờ trên `queue` rồi đọc bằng kết nối riêng như đường xuất (không chặn ghi log); `AppLogDatabase.lines(sessionId:cursor:limit:newestFirst:onlyErrors:contains:)` — phân trang theo id, lọc lỗi + `LIKE` ở SQLite, tham số gắn bằng `bind` (thoát `%` `_` `\`). `SessionSummary` thêm `Hashable`; `header(for:)` dùng chung.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: menu nhấn giữ phiên (có lẫn với chạm chọn phiên không), phiên lớn cuộn nạp tiếp, lọc chữ tiếng Việt (LIKE chỉ không phân biệt hoa thường với chữ ASCII), đảo thứ tự, xuất từ màn xem.

## [1.3.1014] - 2026-11-20

### feat: Sheet nhấn giữ truyện — thao tác dưới Bộ sưu tập thành lưới 4 cột, Đổi nguồn thành dải dài

Anh Bửu: "sửa các option phía dưới bộ sưu tập của context menu thành dạng lưới, cho tôi mockup" → "nếu nút không đủ hàng 4 cái thì căn cho chúng được nằm giữa" → "để nút đổi nguồn giống 'Chuyển sang nguồn …' trong mockup" → duyệt mockup bản 3.

- **Trước**: phần dưới "Bộ sưu tập" của `BookActionSheet` là các hàng "icon + chữ" của `List` (Chuyển sang nguồn …, Đổi nguồn, Mở trong trình duyệt, Tải, Xuất, Dịch lại tên chương, Thêm cả phim / album vào playlist, Bỏ khỏi bộ sưu tập này, Xoá bản tải, Đánh dấu NSFW, Xoá / Xóa lịch sử).
- **Nay** (section "Thao tác", một hàng `List` không nền, không lề):
  - Dải dài viền màu nhấn (`BookActionStrip`, nền nhấn 16%, viền 55%): "Chuyển sang nguồn …" (chỉ truyện mất nguồn, `MissingSourceRebindActionRows`) rồi "Đổi nguồn" (truyện không phải nhập từ file).
  - Lưới 4 cột (`BookActionTileGrid` — `Layout` riêng: cột bằng nhau, cách 8, hàng cuối không đủ 4 ô thì ô giữ bề rộng và nằm giữa; hàng cao bằng ô cao nhất): ô `BookActionTile` = icon 22pt màu nhấn trên, chữ 2 dòng dưới, nền `AppGlassSheetModifier.rowFill`, bo 12. Thứ tự: Mở trình duyệt, Tải, Xuất, Dịch lại tên chương, Thêm cả phim / album vào playlist (vòng xoay thay icon khi tải mục lục), Bỏ khỏi bộ sưu tập này, Đánh dấu NSFW, rồi ô đỏ: Xoá bản tải (dòng phụ "5 tập · 2,3 GB", vẫn hỏi xác nhận), Xoá / Xoá lịch sử.
  - Ô "Xoá bản tải" chỉ thêm vào lưới khi phim còn file tải (kiểm ở sheet) để lưới không giữ chỗ trống. Điều kiện hiện từng ô giữ nguyên như trước.
- `PlaylistAddBookActionRow`, `VideoDownloadsActionRow` vẽ thành ô; `MissingSourceRebindActionRows` vẽ thành dải. Phần Truyện (bìa, tên, nút sửa / kệ) và Bộ sưu tập không đổi.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy** — cần thử: chạm từng ô có đúng ô đó (không kích hoạt cả hàng), sheet chọn playlist / hộp xác nhận xoá bản tải mở từ ô, hàng cuối căn giữa, chữ dài 2 dòng.

## [1.3.1013] - 2026-11-19

### feat: Nhập từ điển và rule dịch — chọn file trước, popup chọn cách nhập hiện sau kèm tên file

Trước: mọi chỗ nhập file của phân hệ dịch hiện popup 3 cách nhập (Thay thế toàn bộ / Gộp / Chỉ thêm key mới) **trước**, chọn xong mới mở bộ chọn file; popup không biết file nào sẽ được nhập. Hai sheet chọn truyện ("Nhập từ truyện khác" / "Chia sẻ sang truyện khác") đã chọn truyện trước nhưng tên truyện nằm lẫn trong tiêu đề popup.
Nay (anh Bửu: "popup option nhập file hiển thị sau khi nhập file, hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập"): dùng khung chung `.dataImportFilePicker` (1ea15164) — hàng "Nhập file…" chỉ mở bộ chọn file; chọn xong mới hiện popup chọn cách nhập, tên file ở dòng dưới tiêu đề, nút "Nhập"; huỷ chọn file / chạm ra ngoài popup ⇒ không nhập. Logic 3 chế độ, toast "thêm X, cập nhật Y", chặn lúc đang nhập và loại file cho phép giữ nguyên:
- 5 thẻ Từ điển chung (GlobalDictionaryCardPresentations + GlobalDictionaryCardController: requestImport chỉ mở bộ chọn file, importFile(url, mode:) thay handlePickedFile / confirmImportMode / pendingMode).
- Danh sách VP / Name (DictionaryListView, Nhập từ điển — .plainText như cũ).
- Danh sách Phiên âm / Pronouns (BaseDictionaryListView; importFile(url, mode:) thêm chặn khi đang nhập).
- Danh sách rule 3 bộ: Nhập file rule và Nhập file rule tắt (QuickTranslationRuleIOMenu + DisabledActions: readImport / readDisabledImport nhận url + mode).
- Bỏ các .dataImportModePopup + DocumentPickerPresenter riêng + state chế độ chờ cũ ở những chỗ trên.
- BookImportSourceSheet / BookShareTargetSheet (không qua file, vẫn chọn truyện trước): popup tiêu đề "Nhập từ truyện khác" / "Chia sẻ sang truyện khác", tên truyện đã chọn ở dòng dưới tiêu đề (message:).
Danh sách VietPhrase.dat / Names.dat không có nhập nên không đổi.

File: Views/Settings/Translation/{GlobalDictionaryCardPresentations, GlobalDictionaryCardController, QuickTranslationRuleIOMenu, QuickTranslationRuleIOMenu+DisabledActions}, Views/Dictionary/{DictionaryListView, DictionaryListView+Transfer (chỉ comment), BaseDictionaryListView, BookImportSourceSheet, BookShareTargetSheet}, .claude/rules/translation.md.

Chưa kiểm: chưa build (máy Windows), chưa chạy máy — cần thử popup hiện đúng sau khi bộ chọn file đóng ở cả màn đẩy (Cài đặt, danh sách) lẫn danh sách mở trong sheet (hub Từ điển của Reader), và hai bộ chọn file của menu rule (rule / rule tắt) gắn cùng một view không lẫn nhau.

## [1.3.1012] - 2026-11-19

### feat: Nhập phiên âm, thay thế TTS, quy tắc mục lục, công cụ tra cứu — chọn file trước, popup chọn cách nhập hiện sau kèm tên file

Anh Bửu: "Hiện tại popup option nhập file hiển thị trước khi nhập file, sửa lại hiển thị sau khi nhập file. Hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập."

Trước: hàng "Nhập…" trong ngăn kéo … mở popup chọn cách nhập (`.dataImportModePopup`) trước, bấm "Nhập file" mới mở bộ chọn file; chế độ đã chọn giữ tạm ở `pendingImportMode` chờ file.
Nay: 5 màn chuyển sang khung chung `.dataImportFilePicker` (commit 1ea15164): hàng "Nhập…" chỉ mở bộ chọn file; chọn xong mới hiện popup Thay thế toàn bộ / Gộp / Chỉ thêm key mới với tên file ở dòng dưới tiêu đề, nút "Nhập"; bấm "Nhập" ⇒ gọi đúng hàm nhập cũ với file + chế độ (giữ nguyên logic 3 chế độ, khoá so trùng và toast "thêm X, cập nhật Y"). Huỷ chọn file ⇒ không có popup; chạm ra ngoài popup ⇒ bỏ file, không nhập. Giữ nguyên loại file cho phép của từng màn (NghiTTS .plist / .json / .csv / .txt, VieNeu .plist / .json, ba màn còn lại .json) và câu báo khi đuôi file sai (nay báo sau khi bấm "Nhập"). Bỏ state `showingImportModes` / `pendingImportMode`, `DocumentPicker` dạng sheet (hai màn phiên âm) và `DocumentPickerPresenter` riêng của từng màn. Lọc rác không đổi (không popup, chỉ thêm mẫu chưa có).

File đã đụng:
- `Sources/Views/Settings/TTS/TTSDictionaryEditView.swift` (phiên âm NghiTTS)
- `Sources/Views/Settings/TTS/VieNeuJapaneseDictionaryView.swift` (phiên âm VieNeu)
- `Sources/Views/Settings/TTS/TTSReplacementManagerView.swift` (thay thế ký tự TTS, cả tầng chung lẫn tầng riêng của truyện)
- `Sources/Views/Settings/Translation/TOCRulesConfigView.swift` (quy tắc mục lục)
- `Sources/Views/Settings/Search/SearchEnginesConfigView.swift` (công cụ tra cứu)

Chưa kiểm: không build được (máy Windows) — chỉ đọc code + `check_architecture.py` (không lỗi mới); chưa chạy trên máy, nhất là hai màn phiên âm (trước dùng `DocumentPicker` dạng sheet, nay bộ chọn bản sao `asCopy` của khung chung — file nằm ở thư mục tạm, đọc trong `Task` sau khi popup đóng) và màn mở dạng sheet (Thay thế TTS từ Cài đặt TTS / hub truyện, Công cụ tra cứu từ Reader).

## [1.3.1011] - 2026-11-20

### feat: Khung nhập file mới — chọn file trước, popup chọn cách nhập hiện sau kèm tên file

Anh Bửu: "Hiện tại popup option nhập file hiển thị trước khi nhập file, sửa lại hiển thị sau khi nhập file. Hiển thị tên file nhập ở phần mô tả dưới tiêu đề nhập."

- Mới `DataImportFilePickerModifier` (`.dataImportFilePicker(isPresented:allowedContentTypes:title:modes:initialMode:onImport:)`, `Views/Common/DataImportModePopup/`): gộp `DocumentPickerPresenter` + popup chọn cách nhập. Mở bộ chọn file trước; chọn xong, **chờ bộ chọn đóng hẳn** (`isPresented` về `false` sau `onFinished` của host) rồi mới hiện popup — trình bày cover khi host còn đang đóng thì UIKit bỏ qua. Huỷ chọn file ⇒ không popup; chạm ra ngoài popup ⇒ bỏ file. `onImport(url, mode)` chạy sau khi popup đóng hẳn; `url` là bản sao trong thư mục tạm (`asCopy`) nên đọc sau vẫn được.
- `DataImportModePopup` / `.dataImportModePopup`: thêm `message` — dòng dưới tiêu đề hiện **tên file** (icon tài liệu, dài thì cắt giữa để thấy đuôi file); không có ⇒ "Chọn cách nhập" như cũ. Nút cuối mặc định đổi "Nhập file" ⇒ "Nhập".
- Các màn nhập chuyển sang khung mới ở các commit kế tiếp của đợt này. `ui-conventions.md` cập nhật.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1010] - 2026-11-19

### fix: Import truyện từ trình duyệt không còn báo "Không tìm thấy tiện ích bóc tách" khi tiện ích tra được trễ — Chi tiết chờ một lát và tự nạp lại

Trước (anh Bửu báo): Import từ trình duyệt thỉnh thoảng hiện "Không tìm thấy tiện ích bóc tách của truyện này!", bấm "Thử
lại" thì được. Màn Chi tiết tra tiện ích (ext = danh mục tiện ích theo extensionPackageId) đúng một lần lúc hiện
(loadBookData ⇒ loadBookDetailOnly / loadTOCDataOnly), không thấy là báo lỗi ngay và không tự thử lại; "Thử lại" chạy
đúng hàm đó và thành công ⇒ lúc màn vừa hiện tiện ích chưa tra được, lát sau mới có — màn dựng trước khi mã tiện ích của
lượt Import kịp tới, hoặc danh mục tiện ích đang dựng lại đúng lúc đó (log cũ không ghi mã tiện ích nên chưa phân biệt).

Nay (BookDetailView+ExtensionWait, mới):
- Nhánh "không có ext" của chi tiết / mục lục gọi waitForExtension: giữ vòng xoay đang tải, chờ tối đa 1,5 s; hết giờ mới
  báo lỗi như cũ, kèm log ❌ [BookDetail] (packageId, số tiện ích đã cài / trong danh mục, có trong đã cài hay không).
- BookDetailView có .onChange(of: ext?.localPath): tiện ích vừa tra được (mã tiện ích của màn đổi hoặc danh mục có thêm)
  ⇒ nạp ngay phần đang chờ, hoặc phần đã báo lỗi "không tìm thấy" — khỏi bấm "Thử lại". Log ℹ️ [BookDetail].
- BookDetailView.swift: isLoadingDetail / isLoadingTOC private ⇒ internal, thêm @State extensionWaitTargets, thay hai chỗ
  báo lỗi (số dòng không đổi). Không đụng trình duyệt / Kệ / Khám phá.
- Đánh đổi: tiện ích thật sự đã gỡ thì lỗi hiện chậm ~1,5 s.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; nguyên nhân gốc chưa có log xác nhận (nếu còn gặp, log ❌
[BookDetail] cho biết mã tiện ích nhận được); check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).
