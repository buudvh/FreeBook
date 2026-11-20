# CHANGELOG - Nhật ký Thay đổi CodeGraph Tàng Công Các

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **Tàng Công Các**.

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

## [1.3.1009] - 2026-11-19

### fix: Sửa VP / Name / rule lúc đang nghe — Reader hiện bản dịch mới cho mọi đoạn như cũ, chỉ tiếng TTS giữ chữ cũ ở đoạn đang đọc và đoạn đó được tô cả đoạn

Trước (bản đã build): Reader ghim chữ TTS cho các dòng ≤ mốc nối — anh Bửu báo các đoạn trước đoạn đang nghe không hiển
thị đúng nghĩa đã cập nhật. Anh chốt: "Hiển thị phải thay đổi cho đúng (như cũ …). Việc để nguyên đoạn trước khi nghe chỉ
nên làm với nghe chứ không phải làm với đọc" + chọn "Tô cả đoạn".

Nay:
- Reader dựng lại bản dịch như trước tính năng (bản mới cho mọi đoạn, vẫn hoãn khi panel / menu chọn chữ mở). Gỡ hẳn phần
  ghim chữ: ReaderViewModel+TTSRetranslation (alignedWithTTSAnchor / chờ mốc 3 s / nắn lại cache / trả bản gốc), lượt chờ
  trong processAndSaveChapter, giữ lượt nối khi panel mở (setReaderHold), trường ghim của CachedChapter
  (ttsAnchorStamp / unalignedParagraphItems, ttsSnapshot*), getPretranslatedSnapshot về lại paragraphItems.
- TTS giữ cơ chế nối: chunk của dòng ≤ L (dòng đang đọc + chunk đã xếp sẵn hàng đợi NghiTTS / VieNeu) đọc chữ cũ, dòng sau
  đọc bản mới, tiếng không cắt; không còn chờ Reader. TTSRetranslationCoordinator gọn lại: bỏ mốc / pending / hold / người
  chờ, còn staleLineIds (dòng ≤ L có chữ TTS khác bản mới, cả dòng đã nghe qua, tên chương = -1) + FullRetranslation (bản
  mới đầy đủ), xoá khi chapterContent đổi (didSet) — TTS đọc lại / chuyển chương / thay cả chương.
- Highlight "tô cả đoạn": ReaderTTSHighlightReader lấy chữ TTS đang đọc của dòng đang đọc / đang chuẩn bị qua
  TTSManager.spokenLineText(lineId:) (tra normalizedChapterText — chữ trộn sau lượt nối; tên chương = chapterTitle);
  ReaderTTSHighlightBinder so với ParagraphCardView.displayText: khác ⇒ tô cả đoạn bằng kiểu vệt chuẩn bị (nhạt hơn),
  trùng ⇒ vệt câu như thường. ReaderView chỉ đổi tham số truyền vào binder (không thêm dòng).
- Lùi / tua về dòng mà từ đó còn dòng chunk chữ cũ (TTSManager+RetranslationRewind, mới): adoptFullRetranslationIfStale thay
  cả chương bằng bản mới đầy đủ (bỏ tiếng nạp trước) rồi đọc từ đầu dòng đích — cắt tiếng như mọi lần tua. Gọi ở
  seekToParagraph (vạch tua sheet nghe mini) và skipBackward (sheet, màn khoá; đổi đúng một dòng gán chỉ số). Đổi độ dài
  chunk / hiện tên chương sau lượt nối ⇒ chia lại từ chữ bản mới như resumeAfterSettings; bản mới đã cũ (token / cấu hình
  đổi) ⇒ đọc chunk hiện có + log. "Nghe từ đây" / nút tai nghe Reader dựng lại phiên bằng bản dịch sẵn của Reader (đã là
  bản mới) nên không cần lối này.
- Ghi chú luật: .claude/rules/tts.md, .claude/rules/reader-text-pipeline.md.

Khác gợi ý của spec: binder so thẳng chữ TTS đang đọc với chữ đang hiện thay vì chỉ dựa vào tập dòng chữ cũ — phủ cả lúc panel
đang mở (Reader chưa dựng lại, TTS đã đọc bản mới) và khoảng trước khi TTS kịp nối. Hệ quả: mọi lệch chữ TTS ↔ Reader có sẵn
(bộ dịch tiện ích ra chữ khác, bật / tắt dịch lúc đang tạm dừng…) nay hiện tô cả đoạn thay vì vệt câu lệch chỗ.

Chưa đồng bộ (biết, chưa sửa): bong bóng / dòng trích của vạch tua sheet nghe mini lấy chữ chunk TTS, kéo lùi qua dòng chữ cũ
vẫn xem trước câu cũ; thả tay thì TTS thay chương và đọc bản mới.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift);
TTSManager.swift 3413 dòng, ReaderView.swift 1924 dòng (không tăng).

## [1.3.1008] - 2026-11-19

### fix: Danh sách VietPhrase.dat / Names.dat — thêm nhiều từ một lượt ghi lớp sửa đổi, không dịch lại N lần

Thuộc commit trước (danh sách từ điển gốc VietPhrase.dat / Names.dat).
Trước: nút "+" dán N dòng gọi DictionaryCache.upsertEntry N lần ⇒ ghi lại CustomVietPhrase.txt / CustomNames.txt N lần và phát N thông báo đổi từ điển (Reader / TTS — kể cả dịch lại từ đoạn sau khi đang nghe — chạy N lượt); hỏng giữa chừng thì ghi dở một nửa.
Nay: nhiều dòng ⇒ **một** TranslationDictionaryWriter.mutate(isName:bookId: nil) (mục mới / đè lên đầu, mục cũ cùng khoá bỏ) rồi DictionaryCache.refreshFromPublishedState — một lượt ghi, một thông báo, như danh sách Chung (DictionaryListView). Một dòng vẫn đi đường .term thường (saveCustomEntry).

File: Views/Dictionary/GlobalBaseDictionaryListView.

Chưa kiểm: chưa build, chưa chạy máy.

## [1.3.1007] - 2026-11-19

### feat: Thẻ VietPhrase.txt / Name.txt › Sửa mở danh sách từ điển gốc VietPhrase.dat / Names.dat, nghĩa hiệu lực kèm lớp sửa đổi

Trước: Cài đặt dịch thuật › thẻ VietPhrase.txt / Name.txt › Sửa mở danh sách Chung cũ (DictionaryListView) — chỉ thấy lớp sửa đổi (CustomVietPhrase.txt / CustomNames.txt), không thấy từ nào của VietPhrase.dat / Names.dat.
Nay (anh Bửu: "Sửa vietphrase thì hiển thị danh sách của vietphrase.dat chứ không phải custom vietphrase nhé"; chọn "Lớp sửa đổi, hiện chung", Name cũng vậy):
- GlobalBaseDictionaryListView (mới): danh sách từ điển gốc với **nghĩa hiệu lực** = .dat + lớp sửa đổi Chung — từ đã sửa hiện nghĩa mới + nhãn "đã sửa"; từ đã xoá (tombstone) ẩn; từ chỉ có ở lớp sửa đổi (tự thêm) đứng đầu, nhãn "đã thêm". Kiểu hàng VP/Name (.headline khoá, .subheadline nghĩa màu phụ), chạm thân hàng ⇒ DictEntrySheet chế độ sửa (như DictionaryListView), icon Xoá, "+" nổi thêm từ, .backPageTitle("VietPhrase.dat" / "Names.dat"), .searchable(..., placement: .navigationBarDrawer(displayMode: .always), prompt:). Ngăn kéo "…" có "Từ đã sửa / đã xoá" ⇒ đẩy DictionaryListView Chung cũ (xem / khôi phục).
- Lưu / xoá / thêm **chỉ** ghi lớp sửa đổi Chung qua đường có sẵn DictionaryCache.upsertEntry / deleteEntry ⇒ TranslationManager.saveCustomEntry / deleteCustomEntry (scope .term ⇒ Reader / TTS dịch lại); không ghi lại .dat. Xoá một từ gốc = tombstone (ẩn khỏi danh sách), xoá từ tự thêm = bỏ hẳn.
- Hiệu năng (VietPhrase cỡ triệu mục): mở màn đọc **mảng khoá** một lần ở nền (vòng quay "Đang đọc VietPhrase.dat…") từ cây đã nạp — FrozenTrieDictionary+Walk (mới): walkEntries duyệt cây tiền thứ tự chỉ giữ đường đi hiện tại (bộ nhớ O(độ sâu)) và allKeys() không giữ nghĩa; allEntries() cũng chuyển sang walkEntries (cùng tập entry, thứ tự nay là tiền thứ tự của cây — khoá cha trước khoá con; bớt các mảng nút cỡ triệu phần tử khi xuất / gộp). Nghĩa của hàng tra lúc hàng hiện (lớp sửa đổi trước, rồi cây). Danh sách hiện theo lượt 200 hàng (nạp sớm khi còn 50). Tìm theo từ gốc **và** nghĩa (BaseDictionaryBrowser.search, Service mới): chạy nền, chờ 300 ms sau phím cuối, gõ tiếp thì huỷ lượt cũ (huỷ cả task nền đang duyệt cây), dừng ở 500 kết quả — dòng tổng ghi "500 kết quả đầu".
- Danh sách VP / Name Chung cũ vẫn mở từ Từ điển của truyện như trước; Nhập / Xuất / Xoá của thẻ không đổi.

File: Models/Dictionaries/{FrozenTrieDictionary, FrozenTrieDictionary+Walk (mới)}, Services/Translation/Manager/BaseDictionaryBrowser (mới), Views/Dictionary/GlobalBaseDictionaryListView (mới), Views/Settings/Translation/{GlobalDictionaryCardPresentations, GlobalDictionaryCardController (chỉ comment)}, .claude/rules/translation.md.

Chưa kiểm: chưa build (máy Windows), chưa chạy máy — cần đo trên máy thời gian / RAM khi đọc mảng khoá VietPhrase cỡ triệu mục và tốc độ tìm theo nghĩa. Thứ tự hàng là thứ tự cây (gần theo chữ, không sắp xếp lại). File .txt xuất từ thẻ (GlobalDictionaryTextExporter) nay ra theo thứ tự cây mới — cùng nội dung, khác thứ tự dòng.

## [1.3.1006] - 2026-11-19

### fix: Danh sách tab danh mục ở Khám phá không còn tự kéo lệch khi quay về từ Chi tiết / tab khác

Anh Bửu: "khi scroll list ở Khám phá rồi chuyển tab khác hoặc vào chi tiết rồi trở về thì danh sách có cảm giác bị chạy đi" → "tra xong nguyên nhân thì fix rồi push luôn".

- **Nguyên nhân** (`DiscoveryCategoryTabView`, tab `home` kiểu cũ — kiểu Danh sách lẫn Lưới): mỗi lần nội dung tab hiện lại (back từ Chi tiết, đổi tab chính rồi về, quay về tab danh mục kề bên), `.onAppear` lấy neo của `DiscoveryScrollAnchorStore` (link hàng trên cùng lúc rời) và 0,2 s sau `scrollTo(neo, .top)` — kể cả khi trang **không** bị dỡ và `UIScrollView` vẫn giữ đúng chỗ cuộn. Hàng neo thường đang bị che một phần ⇒ cả danh sách bị kéo lệch; neo không bao giờ xoá nên lần nào về cũng nhảy. Biến thể nhảy xa: lúc đẩy Chi tiết các hàng có thể báo tắt trước tab ⇒ không chốt neo mới ⇒ về lại thì kéo tới neo cũ từ lần đổi tab trước.
- **Sửa**: lượt khôi phục từ `.onAppear` chỉ chạy khi **hàng đầu tiên đang hiện** (danh sách đang ở đầu = trang vừa bị `TabView(.page)` dỡ / ra ngoài cửa sổ ±3 tab) — kiểm lúc cuộn, sau 0,2 s; trang còn giữ chỗ cuộn thì để nguyên. Lượt khôi phục khi danh sách vừa nạp xong hàng đầu (từ 0 mục) giữ như cũ.
- Chưa sửa (ghi nhận từ lúc tra): bộ dịch tiện ích thay bản QT có thể đổi số dòng tên / mô tả của hàng phía trên ⇒ lệch nhẹ; tiêu đề lớn mới (1.3.984) của Thể loại / Xem thêm có thể bung / thu khi back — cần thử trên máy.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1005] - 2026-11-19

### fix: Kệ ở "Chỉ NSFW" vẫn có thanh chip Tất cả / Truyện chữ / Truyện tranh / Phim / Âm thanh

Anh Bửu: "chỉ nsfw của tab kệ sách thiếu chip tất cả/truyện chữ/truyện tranh/phim/âm thanh" → duyệt plan.

- **Trước**: thanh chip loại của Kệ + Lịch sử chỉ hiện khi danh sách **đã lọc NSFW** có từ 2 loại trở lên (`ShelfKindFilter.showsFilterBar`) ⇒ ở "Chỉ NSFW", truyện NSFW cùng một loại là mất cả thanh chip, trong khi "Tất cả" vẫn có.
- **Nay**: số loại đếm trên kệ ∪ lịch sử **chưa** lọc NSFW (`ShelfKindFilter(_:kindFilter:kindSource:)`, `ShelfView` truyền thêm một `ShelfBookPartition(allBooks)` khi bộ lọc NSFW không phải "Tất cả") ⇒ thanh chip hiện như nhau ở cả ba chế độ. Chọn loại không có truyện nào sau lọc NSFW ⇒ màn rỗng "Chưa có … trên kệ" sẵn có, thanh chip vẫn ở trên. Thanh chip luôn đủ 5 chip cố định nên không lộ loại của truyện NSFW đang ẩn.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1004] - 2026-11-19

### fix: Từ điển gốc xếp hàng mọi lượt ghi, thay file .dat an toàn; toast nhập rule đếm đúng "cập nhật"

Ba lỗi review phản biện tìm ra ở việc 6–8 (thẻ Từ điển chung, danh sách Phiên âm / Pronouns, nhập rule):
1. Mất dữ liệu khi sửa trong lúc nhập — Trước: nhập ở danh sách Phiên âm / Pronouns (và ở thẻ) chạy ngoài actor GlobalDictionaryEditor; trong vài giây importer nạp lại (loadAllDictionaries), sửa / xoá một hàng đọc phienAmMap / cây Pronouns còn bản cũ trong RAM rồi ghi đè file ⇒ mất mọi mục vừa nhập (toast vẫn báo thêm X); Pronouns còn dùng chung file tạm Pronouns.dat.importing giữa hai đường. Nay: GlobalDictionaryEditor là hàng đợi duy nhất cho mọi lượt ghi từ điển gốc (nhập ở thẻ, nhập ở danh sách, sửa / xoá hàng, xoá cả từ điển) — chuỗi `serialized`: lượt sau chờ lượt trước ghi **và nạp lại** xong (actor thường cho lượt khác chen ở mỗi await). GlobalDictionaryImporter luôn đọc từ điển gốc **trên đĩa** (bỏ nhánh đọc bản RAM), vẫn so số mục với wordCount. BaseDictionaryListView khoá "+", chạm hàng, nút xoá và thao tác trợ năng "Sửa" trong lúc đang nhập.
2. Thay file không an toàn — Trước: GlobalDictionaryImporter.write xoá .dat đích rồi mới moveItem file tạm (app bị tắt giữa hai bước ⇒ mất VietPhrase / Names / Pronouns); "Thay thế toàn bộ" qua TranslationManager.importDictionary cũng xoá đích trước rồi dựng thẳng vào đích. Nay: mọi đường (gộp, chỉ thêm, thay thế toàn bộ, sửa hàng) dựng / chép vào file tạm cùng thư mục tên duy nhất `<tên>.importing-<UUID>` rồi FileManager.replaceItemAt (đích chưa có ⇒ moveItem); lỗi giữa chừng ⇒ xoá file tạm, bản cũ còn nguyên. File tạm sót của lượt bị tắt được dọn ở lượt ghi kế tiếp. "Thay thế toàn bộ" giữ đúng ngữ nghĩa cũ (dựng .dat từ file nhập bằng DoubleArrayTrieBuilder.build(fromTxtFile:), PhienAm chép nguyên file).
3. Toast nhập rule đếm sai "cập nhật" — Trước: thẻ Rule dịch, ngăn kéo "…" của danh sách rule và chia sẻ bộ rule riêng lấy số mẫu trùng (importPreview.overlapping) làm "cập nhật", nên nhập lại đúng file vừa xuất vẫn báo "cập nhật N". Nay: QuickTranslationRuleRecordStore.importCounts(current:imported:mode:) chỉ đếm mẫu có vế phải thực sự đổi, và chỉ ở "Gộp" ("Chỉ thêm key mới" ⇒ cập nhật 0); QuickTranslationRuleTransfer.sharePreview đổi thành shareCounts(from:to:mode:).

File: Services/Translation/Manager/{GlobalDictionaryEditor, GlobalDictionaryImporter}, Services/Translation/Engine/{QuickTranslationRuleRecordStore, QuickTranslationRuleTransfer}, Views/Dictionary/BaseDictionaryListView, Views/Settings/Translation/{GlobalDictionaryCardController, QuickTranslationRuleIOMenu, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Ngoài hàng đợi vẫn còn hai đường ghi VietPhrase.dat có sẵn từ trước, không đổi ở đây: "Tải từ điển mặc định" (downloadDefaultDictionaries) và gộp lớp custom vào VietPhrase (DictionaryMergeTask ⇒ TranslationManager.importDictionary, vẫn xoá đích trước rồi dựng).

## [1.3.1003] - 2026-11-19

### feat: Thử rule ở danh sách rule chung / tên chương mở từ Reader kèm bộ rule riêng của truyện đang đọc

Trước: sheet "Thử rule" ở danh sách rule chung / tên chương luôn chỉ áp bộ chung (+ bộ tên chương), kể cả khi danh sách mở từ hub Từ điển của Reader — rule riêng của truyện đang đọc không được tính, kết quả khác lúc đọc.
Nay (anh Bửu chốt "Kèm bộ riêng"): danh sách mở từ Reader (có contextBookId) thử như lúc đọc truyện đó — QuickTranslationRuleEngine.preview(_:scope:contextBookId:mode:) thêm bộ riêng của truyện và dùng bookId của nó (file tắt riêng, công tắc token, thứ tự ưu tiên, bộ ngoặc, Name riêng); danh sách tên chương áp riêng + tên chương + chung, danh sách chung áp riêng + chung. Mẫu rule đã khớp tra theo cặp (bộ, dòng) gồm cả bộ riêng ⇒ hiện đúng bộ ("bộ riêng" / "bộ tên chương" / "bộ chung"). Nút "?" của ô nhập nói rõ đang kèm bộ riêng. Mở từ Cài đặt (không có truyện) giữ như cũ.

File: Services/Translation/Engine/QuickTranslationRuleEngine+Preview, Views/Settings/Translation/{QuickTranslationRuleTesterPanel, QuickTranslationRuleTesterSheet, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy.

## [1.3.1002] - 2026-11-19

### fix: Reader bỏ chữ ghim khi mốc dịch lại của TTS hết hiệu lực, tua đoạn chặn lúc đang dựng chương, vạch tua không giữ danh sách đoạn cũ

Vá các lỗi review phản biện tìm ra ở ba commit dịch lại khi đang nghe + tua theo đoạn:

1. Reader giữ chữ cũ của dòng ≤ mốc sau khi mốc hết hiệu lực ⇒ lệch highlight. Trước: Reader ghi chữ TTS vào cache
   cho dòng ≤ L kèm token hiện hành; TTS dựng lại chương (chương trước → chương kế, nghe tiếp từ chương trước tự sang,
   jumpToChapter không truyền snapshot) thì mốc chết nhưng isTranslationFresh vẫn đúng ⇒ Reader không dựng lại, TTS
   đọc bản mới từ dòng 0 còn Reader hiện chữ cũ dòng 0…L; bấm Nghe từ Reader còn đưa chữ ghim làm snapshot ⇒ dòng ≤ L
   đọc bản dịch cũ mãi. Nay:
   - CachedChapter lưu ttsAnchorStamp + unalignedParagraphItems (bản dựng gốc) khi ghim (ChapterCache.swift).
   - TTSManager.chapterContent có didSet ⇒ TTSRetranslationCoordinator.ttsTextRevision; Reader nghe nó và trả chương
     đang ghim về bản gốc ngay khi mốc không còn sống (restoreChaptersWithDeadTTSAnchor).
   - Mốc còn hiệu lực phải khớp cả cờ phồn → giản + vân tay bộ dịch của phiên TTS (Anchor.convertsTraditional /
     engineFingerprint) và công tắc dịch + phồn → giản của bản Reader dựng.
   - getPretranslatedSnapshot (ReaderView.swift) dùng CachedChapter.ttsSnapshotParagraphItems / ttsSnapshotTitle — luôn
     bản gốc, không chữ ghim.
2. Danh sách đầu đoạn của vạch tua có thể cũ khi chương mới cùng số chunk (startSpeaking đổi chương trước khi gán chunk).
   Nay TTSManager.paragraphs có didSet ⇒ layoutRevision tăng mỗi lần gán mảng chunk (khoá outline đã có layoutRevision).
3. Tua trong lúc startSpeaking đang dựng chương ⇒ phát nhầm chunk chương cũ, lưu sai tiến độ, lượt dựng xong đè mất chỗ
   tua. Nay didSet của paragraphs ghi chủ mảng chunk (phiên / truyện / chương); seekToParagraph và lượt nối bản dịch bỏ
   qua khi chủ lệch phiên / chương đang phát (isChunkLayoutCurrent).
4. Hàng rào refill NghiTTS so cả struct chunk (range / sourceRange) trong khi tiêu chí "đổi" của lượt nối chỉ so chữ +
   kiểu ranh giới ⇒ chunk cùng chữ dời range bị bỏ kết quả. Nay cùng so chữ + boundaryKind.
5. Reader chờ mốc bằng continuation không nghe huỷ ⇒ lượt dựng đã huỷ chặn lượt mới (refreshParagraphItems await lượt
   cũ) tới 3 s. Nay waitForAnchor bọc withTaskCancellationHandler, huỷ là thôi chờ ngay.

File: TTSRetranslationCoordinator.swift, TTSManager.swift (didSet paragraphs / chapterContent, hàng rào refill),
TTSManager+Retranslation.swift, TTSManager+RetranslationSplice.swift, TTSManager+ParagraphSeek.swift,
ReaderViewModel+TTSRetranslation.swift, ReaderViewModel+TranslationPresentation.swift, ReaderViewModel+Translation.swift,
ReaderTranslationPresentation.swift, ChapterCache.swift, CachedChapter+TranslationFreshness.swift, ReaderView.swift
(getPretranslatedSnapshot), .claude/rules/tts.md, .claude/rules/reader-text-pipeline.md.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.1001] - 2026-11-19

### fix: NSFW chỉ tắt công tắc chung khi mở lại app, chặn nhập file quy tắc mục lục rỗng, ô tiêu đề thu gọn không chiếm chỗ

Sửa theo review phản biện của đợt 1.3.982–1.3.1000.

- **NSFW khi rời app** (anh Bửu chọn "Tắt khi mở lại app"): bản 1.3.985 tắt công tắc NSFW chung ngay lúc vào nền ⇒ khoá máy lúc đang xem phim 18+ thì phim tắt tiếng + thu vào hub (guard NSFW của phiên phim), playlist toàn mục 18+ dừng sau bài hiện tại, Reader truyện nguồn 18+ bị đóng (Chi tiết có `closesWhenNsfwHidden`), và tranh thứ tự với luồng rời app của `VideoLeaveToHubCoordinator`. Nay `ShelfNsfwFilterState`: vào nền ⇒ chỉ Kệ về "Không hiển thị NSFW" ngay (ảnh màn chuyển app không lộ); `willEnterForeground` ⇒ mới tắt công tắc chung; trong lúc ở nền ngưng đồng bộ từ công tắc chung. Nút Home vẫn tắt cả hai ngay.
- **Quy tắc mục lục**: nhập file `[]` bị chặn (toast lỗi) — "Thay thế toàn bộ" không còn thêm lại quy tắc mặc định (1.3.988) nên file rỗng sẽ xoá sạch quy tắc, nhập truyện TXT không tách được chương (`TOCRulesConfigView`).
- **Tiêu đề thu gọn** (1.3.984): ô `topBarLeading` chỉ dựng khi tiêu đề lớn đã thu — trước đó chữ trong suốt rộng tới 230pt luôn chiếm góc trái, có thể đẩy nút back tự dựng của trang con trong sheet (`HubStyleActionSheet`, `NotificationInboxView`) và chen cụm nút phải trên máy hẹp.
- Tài liệu: `ui-conventions.md` mục Màn danh sách (bỏ bút chì, chạm hàng = sửa; nhập dữ liệu qua `.dataImportModePopup`, ngoại lệ lọc rác); chú thích popup bỏ "lọc rác" khỏi danh sách màn dùng popup; 19 entry CHANGELOG cũ nhất (1.3.951–1.3.970) chuyển sang `CHANGELOG.archive.md`.
- Kiểm: chỉ đọc code, **không build tại chỗ (Windows), chưa chạy trên máy**.

## [1.3.1000] - 2026-11-19

### fix: Dịch lại khi đang nghe chờ lượt dựng chương đang chạy, tua đoạn huỷ lượt chuyển chương, Reader không rơi bản dựng chờ mốc

Vá ba khe hở của hai commit trước (rà lại sau khi viết, chưa gặp trên máy):
- TTSManager+Retranslation: chỉ chờ startSpeakingTask / chapterAdvanceTask trước khi dịch lại ⇒ người dùng đọc lại
  chương ("Nghe từ đây", bật/tắt dịch, rereadCurrentChapter) trong lúc tải / dịch / chờ panel thì lượt nối chèn vào
  mảng chunk sắp bị thay, tiếng nạp trước theo phiên mới có thể sống sót với chữ sai. Nay chờ lượt dựng đang chạy
  (awaitChapterBuildsInFlight, lặp nếu có lượt mới chen vào) cả trước khi dịch lẫn ngay trước khi nối.
- TTSManager+ParagraphSeek: tua lúc vừa đọc hết chunk cuối và chương kế đang tải / tổng hợp ⇒ lượt chuyển chương vẫn
  qua mọi kiểm tra rồi nhảy sang chương sau giữa đoạn vừa tua tới. Nay seekToParagraph huỷ lượt chuyển chương
  (cancelChapterAdvanceTask — private ⇒ internal) + đóng đo AutoAdvance như pause().
- ReaderViewModel+TranslationPresentation: nhả panel mà TTS đang nối ⇒ bản dựng chờ mốc tối đa 3 s; panel mở lại
  trong lúc chờ thì bản dựng bị bỏ và không ai dựng lại (ReaderView đã thôi hoãn) ⇒ chương kẹt chữ cũ. Nay trả bản
  dựng về hàng chờ (translationPresentation.pending) để lần đóng panel sau áp.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.999] - 2026-11-19

### feat: Sheet nghe mini kéo vạch tiến độ để tua theo đoạn, số N/M đếm theo đoạn

Trước: vạch tiến độ của sheet điều khiển nhanh TTS chỉ để xem (ProgressView), "N/M" đếm chunk
(currentParagraphIndex + 1 / paragraphs.count — tính cả chunk tên chương và chunk con của NghiTTS / VieNeu).

Nay (anh Bửu: "cho thanh tiến độ đọc trên sheet nghe truyện mini có thể kéo để tua được, không tua thời gian mà
tua theo đoạn", duyệt mockup):
- TTSQuickControlNowReading: "N/M" theo đoạn = dòng cha (M = số paragraphIndex ≥ 0 khác nhau, N = thứ tự dòng
  đang đọc; đang đọc tên chương ⇒ 0/M). Danh sách đầu đoạn (outline: id dòng + câu chunk đầu) dựng lại theo
  phiên / chương / số chunk / layoutRevision của lượt nối bản dịch — kéo không đọc TTSManager mỗi nhịp.
- TTSParagraphSeekBar (mới): cử chỉ theo mẫu VideoSeekBar (chạm là nhảy núm, kéo theo tay, thả mới báo), màu
  như vạch cũ (phần đã đọc theo màu nhấn, núm trắng), bong bóng "Đoạn N/M" trên núm lúc kéo.
- TTSQuickControlNowReadingBlock (mới, tách khỏi TTSQuickControlSheet): lúc kéo câu đầu của đoạn đích thay dòng
  trích; thả tay ⇒ seek; thả lại đúng đoạn đang đọc ⇒ không làm gì. Dưới vạch giữ badge nhiệt / dự phòng / engine
  / RTF bên trái, "N/M" bên phải.
- TTSManager+ParagraphSeek (mới): seekToParagraph(lineId:) nhảy tới chunk đầu của dòng, khuôn skipForward nhưng
  chạy cả khi tạm dừng: dừng phát hiện tại, huỷ task phát Nghi / remote + lượt đọc song song dự phòng (để
  resume không chờ task chết), NghiTTS / VieNeu huỷ refill ngoài cửa sổ (cancelNghiRefill) và bỏ tiếng đã nạp
  ngoài cửa sổ; đặt chỉ số, highlightRange = nil, checkpointProgress; đang phát ⇒ speakCurrent, đang dừng ⇒
  publishLifecycleState + Now Playing, không tự phát. Log ⏩ [TTSSeek]. Màn khoá không đổi.
- TTSManager.checkpointProgress() private ⇒ internal (file mới gọi).
- Ghi chú luật: .claude/rules/tts.md (mục widget TTS).

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy (cử chỉ kéo trong sheet có tranh với vuốt đóng sheet
không, vị trí bong bóng ở hai đầu vạch); check_architecture.py chỉ còn vi phạm có sẵn (JSDom.swift).

## [1.3.998] - 2026-11-19

### feat: Sửa rule / VP / Name lúc đang nghe ⇒ TTS đọc bản dịch mới từ đoạn sau đoạn đang đọc, highlight không lệch

Trước: sửa từ điển (VP / Name…) hay rule dịch lúc truyện đang nghe thì TTS chỉ bỏ bản chuẩn bị sẵn
(invalidatePreparedTranslationState) — phần còn lại của chương vẫn đọc bản cũ, trong khi Reader dựng lại cả
chương theo bản mới ⇒ chữ TTS đọc khác chữ Reader hiện, vệt highlight lệch tới hết chương.

Nay (anh Bửu: "áp dụng bản dịch mới từ đoạn sau của đoạn đang nghe — đoạn sau không phải chunk sau; highlight
phải đúng"):
- TTS (TTSManager+Retranslation): hai observer cũ ở init chuyển ra installTranslationChangeObservers() (vẫn bỏ
  bản chuẩn bị sẵn ngay). Có phiên (đang phát hoặc tạm dừng) + truyện bật dịch ⇒ gộp sự kiện 400 ms (rule riêng
  truyện bắn cả hai thông báo), chờ startSpeakingTask / chapterAdvanceTask đang chạy, tải chương thô qua
  ChapterContentRepository rồi dựng lại bằng cùng processChapterWithEngine với cờ của phiên (bộ dịch tiện ích
  chạy lại qua cache RAM).
- Nối trong một nhịp main (TTSManager+RetranslationSplice): mốc L = dòng của chunk xa nhất đã cam kết tiếng
  (chunk đang đọc / đang chuẩn bị; NghiTTS / VieNeu thêm currentItem + nextItem của hàng đợi — chunk kế đã hẹn
  giờ phát trên phần cứng, huỷ là cắt tiếng). Chunk của dòng ≤ L giữ nguyên ⇒ currentParagraphIndex không đổi,
  tiếng không cắt; chunk dòng > L lấy từ bản mới (cùng NghiUtteranceSegmenter.expand). Tiếng nạp trước chỉ bỏ ở
  chỉ số có chữ / kiểu ranh giới đổi (preloadedData, task nạp trước — task gộp Google phủ chỉ số đổi thì huỷ cả
  task —, lượt / dấu dự phòng qua TTSOnlineFallbackState.forgetChunks(_:session:chapterIndex:) mới, refill Nghi
  ⇒ cancelNghiRefill nếu dính chỉ số đổi) rồi updatePrefetchWindow. Không đổi sessionID /
  ttsProcessingGeneration, không xoá cả bộ đệm.
- Hàng rào so chữ chunk trước khi ghi tiếng nạp trước: startPrefetchTask, nạp gộp Google (rawTexts), lượt thử
  online của giọng dự phòng, refill NghiTTS — vì speakCurrent đọc preloadedData[index] không kiểm chữ.
- chapterContent / normalizedChapterText thành bản trộn (dòng ≤ L chữ đang đọc, sau đó chữ mới) để
  resumeAfterSettings không đưa bản cũ quay lại; chapterTitle giữ (chunk tiêu đề không bị thay).
- Mốc TTSRetranslationCoordinator (Services/TTS/Retranslation, mới): token, L, các dòng ≤ L mà chữ TTS khác
  bản mới, contentStamp (TTS dựng lại chương ⇒ mốc hết hiệu lực), layoutRevision cho sheet nghe mini.
- Reader (ReaderViewModel+TTSRetranslation, mới): applyPreparedTranslation áp mốc cùng token — dòng ≤ L hiện
  đúng chữ TTS đọc (giữ đoạn đang hiện nếu trùng, không thì dựng từ chữ TTS, span rỗng), dòng sau dùng bản mới.
  processAndSaveChapter chờ mốc tối đa 3 s khi TTS đang dịch lại đúng chương; mốc tới muộn ⇒ nắn lại cache.
  Panel / menu chọn chữ đang mở (Reader hoãn dựng lại, còn chữ cũ) ⇒ setTranslationRefreshDeferred giữ lượt nối
  của TTS tới khi đóng.
- Sheet nghe mini làm mới "N/M" khi chương được nối lại.
- Log: 🔁 [TTSRetranslate] (L, splice, số chunk cũ / mới / đổi, số dòng giữ chữ cũ, ms).
- Ghi chú luật: .claude/rules/tts.md, .claude/rules/reader-text-pipeline.md.

Khác thiết kế đã duyệt: mốc tính cả chunk đã xếp sẵn trong hàng đợi Nghi (có thể thuộc dòng kế) ⇒ với
NghiTTS / VieNeu bản mới có thể áp từ dòng sau nữa; Reader dùng chữ TTS cho dòng ≤ L thay vì luôn giữ đoạn cũ
(đúng cả khi Reader bỏ lỡ một lượt sửa); panel đang mở thì TTS chờ đóng mới nối.

Chưa kiểm: máy Windows — chưa build, chưa chạy trên máy; check_architecture.py chỉ còn vi phạm có sẵn
(JSDom.swift).

## [1.3.997] - 2026-11-19

### fix: Gộp / sửa thẳng từ điển gốc dừng lại khi đọc từ điển cũ không trọn — không ghi đè làm mất mục

Thuộc việc 6–7 (thẻ Từ điển chung "Gộp" / "Chỉ thêm key mới", danh sách Phiên âm / Pronouns sửa thẳng).
Trước (hai commit vừa rồi): GlobalDictionaryImporter đọc từ điển gốc đang có bằng allEntries() mà không so với wordCount, và nếu VietPhrase.dat / Names.dat / Pronouns.dat có trên máy nhưng không mở được thì lùi sang .txt hoặc danh sách rỗng — rồi ghi lại **cả** từ điển gốc từ danh sách đó ⇒ có thể mất mục (mỗi lần lưu ở danh sách Pronouns lại ghi lại cả Pronouns.dat).
Nay: như GlobalDictionaryTextExporter, số mục duyệt được phải khớp wordCount (cả cây đã nạp lẫn .dat đọc từ đĩa), lệch ⇒ báo lỗi enumerationMismatch, không ghi; .dat có mà không mở được ⇒ lỗi unreadableBase, không lùi sang .txt / rỗng. Toast lỗi ở thẻ / danh sách như các lỗi nhập khác.

File: Services/Translation/Manager/GlobalDictionaryImporter.

Chưa kiểm: chưa build, chưa chạy máy.

## [1.3.996] - 2026-11-19

### feat: Nhập từ điển và rule dịch luôn chọn 3 cách qua popup — Thay thế toàn bộ / Gộp / Chỉ thêm key mới

Trước: danh sách VP / Name (Chung + Riêng) nhập file rồi mới hỏi 2 lựa chọn (Thay thế / Gộp) bằng hộp thoại dictionaryModeDialog; "Nhập từ truyện khác" / "Chia sẻ sang truyện khác" (từ điển và bộ rule riêng) cũng chỉ 2 lựa chọn (callback isMerge); danh sách rule 3 bộ và nhập danh sách rule tắt chọn file trước rồi mới hỏi chế độ bằng confirmationDialog; không có "Chỉ thêm key mới" cho từ điển.
Nay: mọi chỗ nhập dùng popup chung `.dataImportModePopup` (hợp đồng d0929e34) — chọn 1 trong 3 chế độ **trước**, nút cuối mở bộ chọn file (onConfirm chạy sau khi popup đóng hẳn):
- Danh sách VP / Name: Nhập file; "Nhập từ truyện khác" (confirmTitle "Nhập") và "Chia sẻ sang truyện khác" (confirmTitle "Chia sẻ") — BookImportSourceSheet / BookShareTargetSheet trả DataImportMode thay cho isMerge, popup hiện sau khi chọn truyện.
- TranslationDictionaryWriter.importEntries(mode:) (thay isMerge), trả ImportCounts (thêm / cập nhật). Thêm "Chỉ thêm key mới" (.keepExisting): riêng truyện ⇒ mục chưa có lên đầu, mục cũ giữ nguyên; lớp Chung ⇒ tombstone (`từ=`) coi là khoá đã có — từ đã xoá trên máy vẫn xoá dù file có nghĩa, tombstone của file chỉ thêm khi máy chưa có khoá đó. "Gộp" giữ đúng luật cũ (Chung: mục sống của file khôi phục từ đã xoá). DictionaryCache.importEntries(mode:) trả số liệu; BookSourceMigrator (Đổi nguồn) đổi isMerge: true ⇒ mode: .overwriteExisting, hành vi không đổi.
- Danh sách rule (chung / tên chương / riêng): Nhập file rule và Nhập file rule tắt đều popup trước; bỏ hai confirmationDialog chọn chế độ. Chia sẻ bộ rule riêng nhận đủ 3 chế độ (trước chỉ Thay thế / Gộp).
- Toast sau khi nhập ở tầng View: "thêm X, cập nhật Y" (Thay thế toàn bộ ⇒ số mục mới / "thay toàn bộ"); số liệu rule lấy từ importPreview trước khi ghi (QuickTranslationRuleTransfer.sharePreview mới cho chia sẻ bộ riêng). Danh sách rule tắt chỉ có khoá: "Gộp" và "Chỉ thêm key mới" cùng kết quả, vẫn hiện đủ 3.
- Bỏ DictionaryImportModeDialog.swift (dictionaryModeDialog) — đã grep, không còn ai dùng. Chỗ "Lưu tên AI" (ReaderAINameReviewSheet) không phải nhập — giữ nguyên.
(5 thẻ Từ điển chung và hai danh sách Phiên âm / Pronouns đã dùng popup từ hai commit trước.)

File: Services/Translation/Manager/TranslationDictionaryWriter, Services/Translation/Utils/DictionaryCache, Services/Translation/Engine/QuickTranslationRuleTransfer, Services/Download/BookSourceMigrator (chỉ đổi tham số, ngoài phân hệ dịch), Views/Dictionary/{DictionaryListView, DictionaryListView+Transfer, BookImportSourceSheet, BookShareTargetSheet, DictionaryImportModeDialog (xoá)}, Views/Settings/Translation/{QuickTranslationRuleIOMenu, QuickTranslationRuleIOMenu+DisabledActions, QuickTranslationRuleListView}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy — cần thử popup (fullScreenCover) mở đúng từ trong sheet chọn truyện và từ ngăn kéo, rồi bộ chọn file mở sau khi popup đóng. Không đọc / chạy Tests/ nên chưa biết test nào còn gọi importEntries(isMerge:).

## [1.3.995] - 2026-11-19

### feat: Danh sách Phiên âm và Pronouns — sửa thẳng từ điển gốc từ thẻ PhienAm.txt / Pronouns.txt

Trước: PhienAm (ChinesePhienAmWords.txt) và Pronouns (Pronouns.dat) chỉ thay được bằng cách nhập cả file; không xem / sửa / xoá được từng mục; thẻ của hai từ điển này không có mục Sửa.
Nay:
- Thẻ PhienAm.txt / Pronouns.txt › Sửa ⇒ BaseDictionaryListView (mới), kiểu hàng VP/Name: dòng 1 .headline từ gốc, dòng 2 .subheadline nghĩa màu phụ, icon [Xoá]; chạm thân hàng ⇒ sheet sửa (BaseDictionaryEntrySheet mới: Từ gốc + Nghĩa, nút Lưu chữ ở header, vuốt xuống hỏi bỏ thay đổi, nền kính); "+" nổi .floatingAddButton thêm mục; ngăn kéo "…" có Nhập file (popup 3 cách nhập ⇒ GlobalDictionaryImporter) / Xuất file (GlobalDictionaryTextExporter); .backPageTitle; ô tìm .searchable(..., placement: .navigationBarDrawer(displayMode: .always), prompt:).
- Lưu / xoá sửa thẳng cả file: actor GlobalDictionaryEditor (mới) đọc từ điển gốc, đổi, ghi lại qua GlobalDictionaryImporter.writeBase (Pronouns dựng lại .dat vì .txt đã bị xoá sau lần nạp đầu; PhienAm ghi lại file text), nạp lại **riêng** từ điển đó (TranslationManager+BaseDictionaryReload mới: reloadPronounsDictionary / reloadPhienAmMap — không nạp lại cả bộ), rồi TranslateUtils.clearCache + notifyDictionariesDidUpdate để Reader / TTS dịch lại.
- PhienAm vài chục nghìn dòng: nạp một lần sắp theo khoá, lọc trên RAM, List hiện theo lượt 200 hàng (nạp sớm khi còn 50 hàng).
- GlobalDictionaryImporter tách phần ghi thành writeBase / baseEntries dùng chung; TranslationManager.loadPhoneticMap thành internal.

File: Services/Translation/Manager/{GlobalDictionaryEditor (mới), TranslationManager+BaseDictionaryReload (mới), GlobalDictionaryImporter, TranslationManager}, Views/Dictionary/{BaseDictionaryListView (mới), BaseDictionaryEntrySheet (mới)}, Views/Settings/Translation/{GlobalDictionaryCardController, GlobalDictionaryCardPresentations}, .claude/rules/translation.md.

Chưa kiểm: chưa build, chưa chạy máy. Mỗi lần lưu PhienAm ghi lại cả file (~vài chục nghìn dòng) — chưa đo thời gian trên máy. Ghi lại PhienAm sắp theo khoá nên comment / thứ tự dòng của file gốc không giữ.
