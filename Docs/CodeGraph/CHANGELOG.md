# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

## [1.3.606] - 2026-10-26

### feat: ba panel bôi đen thành sheet kéo được, ✕ xoá hẳn name AI, thẻ đầu tiện ích kiểu avatar

Người dùng: *"sửa lại các sheet khác thủ công ở màn hình dịch luôn"* (chọn cả 3 panel; *"độ cao của 3 sheet phải bằng độ cao hiện tại"*), *"phần ai, danh sách name nếu bấm x thì xoá luôn đi, tôi không muốn lần sau vào thấy lại nữa"* (chọn xoá dòng khỏi tin nhắn), *"sửa lại phần cấu hình tiện ích để cover của ext ở giữa, kiểu như avatar"* (PA2 bo góc; *"ngôn ngữ, tên tác giả, loại tiện ích, version hiển thị badge trên 1 hàng"*, *"ngôn ngữ dùng cờ đi"*), *"script editor path của script hiển thị sai: chữ private dính vào chữ sau, không có dấu /"*. Plan duyệt: `Docs/Plans/2026-10-26-plan-reader-panels-ai-names-ext-header-script-path.md`.

- **Panel Dịch / Xoá từ rác / Copy nội dung gốc là sheet gốc** (mới `ReaderView+SelectionSheets.swift`, `FittedSheetDetentModifier`; xoá `ReaderView+DefinitionPanel.swift`, `junkDeleteOverlay`, `ruleToolsOverlay`/`bottomPanel`): thanh kéo hệ thống, kéo bám ngón tay, chạm vùng mờ là đóng. **Một nấc** cao đúng bằng nội dung (`.fixedSize` rồi đo bằng `GeometryReader` + `PreferenceKey`, chiều cao giữ ở `@State` của `ReaderView` để lần mở sau không nháy `.medium`); padding trên = chỗ capsule giả cũ nên cao như panel trước. Bỏ capsule giả và `.presentationDetents([.height(660), .large])` thừa trong `ReaderDefinitionOverlayView`. Copy gốc: `onDismiss` là đường **duy nhất** copy (nút Copy/✕ chỉ hạ cờ) ⇒ mọi đường đóng copy đúng một lần (toast hiện sau khi sheet đóng). Presentation con của panel Dịch (sửa/thêm rule, cấu hình công cụ tìm, cover tra cứu nhanh) dời **vào trong** sheet Dịch; `performQuickLookup` đi `definitionLookupRoute` khi sheet Dịch mở, nút "Tìm" vẫn `lookupRoute`. `handleDefinitionPanelClosed` trả các cờ con về. Hậu xử lý khi đóng giữ ở `.onChange` sẵn có. Panel Dịch từng là `.sheet` trước 2026-07-18 (`de6f4432` chuyển sang overlay, không ghi lý do) — cần thử máy. `ReaderView.swift` 2020 → 1957.
- **✕ xoá hẳn name** (mới `ReaderAIFullScreenView+NameDeletion.swift`): `ReaderAINameReviewSheet.Target` thêm `messageId`, sheet thêm `onDeleteName`; ✕ bỏ **mọi** dòng `khoá=…` trùng khoá khỏi tin nguồn rồi lưu phiên, và sửa luôn tin trong phiên đang chạy của coordinator (`updateMessage`) để `mergeRunningSession` không chép ngược. `ReaderAINameReviewCardView.deleteItem` báo nơi dùng trước khi tự xoá.
- **Thẻ đầu Cấu hình tiện ích** (`ExtensionConfigHeaderCard`): icon bo góc 84pt ở giữa, tên căn giữa, một hàng badge cờ ngôn ngữ (`ExtensionFilterGroups.localeGroupFlag`, VoiceOver đọc tên ngôn ngữ) · tác giả (co "…") · loại · `vN`; bỏ dòng "tác giả · Phiên bản N".
- **Script editor** (`ExtensionScriptEditorView.loadScriptFiles`): `/var` là symlink tới `/private/var` — giải symlink thư mục lẫn từng file rồi cắt theo tiền tố (trước `replacingOccurrences` để sót `/private` ⇒ "/privatesrc/chap.js"). `fileUrl` nay cùng dạng `ext.localPath` nên phép so script chuẩn ở `+Toolbars` khớp lại.
- `rules.md`: bullet ba panel bôi đen là sheet gốc + presentation con gắn trong sheet Dịch + đường copy duy nhất. Chuyển entry `[1.3.576]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (bàn phím trong sheet cố định chiều cao chưa kiểm chứng).

## [1.3.605] - 2026-10-26

### feat: nút dịch dùng icon Lucide languages thay character.bubble

Người dùng: *"Tôi muốn đổi icon nút dịch thành icon ngoài"* → chọn Lucide `languages` (文A), đổi ở **tất cả** nút dịch. Plan duyệt trong chat.

- **`AppGlyph.translate`** (mới): asset `LucideLanguages` sẵn có (cùng ảnh với `originalText`), nhãn VoiceOver "Dịch". Icon ngoài không có bản "fill" ⇒ bật/tắt chỉ khác màu (nút header Reader vốn đổi màu theo trạng thái; menu có chữ "Bật/Tắt").
- Thay `character.bubble`/`character.bubble.fill` ở: nút dịch header Reader + màn Chi tiết (`ReaderTranslationScopeMenuView`, 2 nhánh), hàng "Dịch văn bản" của popup dịch (`TranslationScopePopupView`), nút "Dịch lại chương và mục lục" (`ReaderChapterListView`), mục "Bật/Tắt Dịch Nghĩa" menu Kệ (`ShelfView`, `Label(_:image:)`), mục "Dịch văn bản" menu Khám phá (`DiscoverySourceMenuButton`).
- **Không đổi**: icon dự phòng nhóm tiện ích "Dịch thuật" (`ExtensionFilterGroups.typeGroupSymbol`, API chỉ nhận SF Symbol, không phải nút dịch). Nút "Gốc" của menu chọn chữ (`FloatingSelectionMenu`) vốn dùng cùng ảnh 文A — giữ nguyên theo plan; nay 文A vừa là bật/tắt dịch vừa là "Gốc" ở menu chọn chữ.
- Chuyển entry `[1.3.575]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.604] - 2026-10-26

### feat: danh sách chương Reader kéo được như Hẹn giờ, thêm nút kệ, chữ trên bìa rõ hơn

Người dùng: *"Sửa lại sheet danh sách truyện của reader, hiện tại sheet này kéo không được để nó kéo được như sheet hẹn giờ"*, *"Thêm nút thêm vào kệ vào sheet danh sách truyện của reader"*, *"Bỏ phần số thứ tự ở danh sách chương của màn hình hẹn giờ"*, *"số lượng chương trên cover giống hiển thị chỉ bìa … Tăng cover danh sách chương của reader lên chút"*, *"điều chỉnh luôn kiểu chỉ bìa của danh sách truyện để phần chữ ghi trên cover nhìn rõ hơn"*. Plan duyệt: `Docs/Plans/2026-10-26-plan-reader-toc-sheet-shelf-toggle.md` (mockup duyệt trong chat).

- **Danh sách chương Reader chữ là sheet gốc** (`ReaderView.readerChapterListSheet`, thay overlay `readerChapterListOverlay`): `.presentationDetents([.fraction(0.88), .large])` + thanh kéo hệ thống như `TTSQuickTimerSheet`, kéo theo ngón tay, kéo xuống/chạm ngoài để đóng. Bỏ `Capsule` giả và `dismissGesture` ở header. Chọn chương: đóng sheet trước, `selectChapter` ở lượt main kế tiếp. Không mở sheet khi store chưa dựng được. Sheet dựng lại view mỗi lần mở nên ô tìm lấy lại truy vấn từ store (`ReaderChapterListStore.activeSearchQuery`, mới) và nút sắp xếp đọc thẳng `store.isAscending` (bỏ `@State isAscending` vốn lệch với store khi mở lại). `ReaderChapterListHost` + `.equatable()` giữ nguyên (doc comment cập nhật). Lần thử cùng hướng ngày 19/8 (`716ae779`) bị revert không rõ lý do — cần thử trên máy.
- **Nút thêm/bỏ kệ chỉ có icon** (mới `ShelfToggleFlowModifier`, `ReaderChapterListView+Shelf.swift`): đầu hàng nút header danh sách chương Reader chữ và cạnh nút tải ở `ComicChapterListSheet`. `bookmark.fill` (chưa ở kệ) / `bookmark.slash.fill` đỏ (đã ở kệ) — cặp icon của `BookActionSheet`. Thêm ⇒ `BookActionRunner.addToShelf` rồi mở `CollectionPickerSheet`; bỏ ⇒ hộp xác nhận rồi `BookActionRunner.removeFromShelfOnly` (giữ file/tiến độ, về Lịch sử). **Không** dùng `BookDetailView.removeFromShelf` — đường đó xoá hẳn truyện. Chưa có bản ghi `Book` ⇒ ẩn nút. Hộp xác nhận/sheet chọn bộ sưu tập gắn ở gốc view, không trong `ToolbarItem`; tên trong hộp là tên đang hiển thị (đã dịch).
- **Header danh sách chương**: bìa 72×100 → 86×120; "N chương" chuyển từ hàng nút xuống dải đáy bìa; hàng nút dồn phải sát đáy bìa.
- **Chữ trên bìa kiểu "Chỉ bìa" rõ hơn** (mới `CoverCaptionStrip`, dùng ở `ShelfBookGridCardView`, `DiscoveryNovelGridCardView` và header trên): nền trong suốt → đen 75% trên đoạn chuyển phía trên chữ → 95% ở đáy, phần chuyển không chiếm chỗ bố cục (hàng badge tag/loại ở Kệ giữ vị trí, `zIndex(1)` để vẽ đè); tên 13pt bold, dòng phụ 11pt semibold trắng 100%, bóng chữ nhẹ trên từng `Text`; bìa 16:9 dùng đoạn chuyển thấp. Trước đó Kệ dùng nền đặc 60% (dòng "Ch. N" 10pt trắng 85%), Khám phá dùng dải chuyển 0 → 75% chỉ cao 14pt. Vẫn không dùng `.ultraThinMaterial`.
- **Sheet Hẹn giờ** (`TTSQuickTimerSheet.chapterRow`): bỏ cột số thứ tự; chương đang phát giữ icon loa.
- `rules.md`: bullet luật công tắc kệ trong Reader. Chuyển entry `[1.3.574]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`ReaderView.swift` 2034 → 2020). Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.603] - 2026-10-26

### fix: quét tên coi Không có name là lượt hợp lệ, tên chương dịch theo cấu hình

Người dùng (sau 1.3.602): *"coi câu trả lời đúng "Không có name" là lượt hợp lệ: không gửi lại, không tính lỗi, không chặn Tiếp nối"* → sửa lại *""Không có name" là lượt hợp lệ nhưng vẫn phải thử lại nhé"*; *"tên chương cần được dịch theo config"*.

- **"Không có name"** (`AINameExtractionBatchProcessor.extractNamesFromText` trả thêm `saidNoNames`; `+Turns`): lượt không có tên vẫn được gửi lại một lần như 1.3.602; vẫn rỗng mà một trong hai lần AI trả lời đúng câu "Không có name" (prompt mặc định dặn câu này; so khớp bỏ hoa thường, code fence, dấu chấm cuối) ⇒ **lượt hợp lệ**: không tính lỗi, không vào danh sách "Thử lại", không chặn điểm tiếp nối (log thường, không ❌). Trả lời từ chối/sai định dạng khác giữ luật cũ (vẫn rỗng ⇒ lượt lỗi).
- **Tên chương dịch theo cấu hình** (`ReaderAIBatchPromptSheet`, `ReaderAINameScanChapterPickerView`, `AIBookDataInspector.nameScanChapters`): khi Reader đang bật dịch cho truyện, tên chương ở 4 dòng chọn chương bắt đầu, tóm tắt và màn "Chọn chương…" hiện bản dịch — đúng luật danh sách chương Reader (`TranslateUtils.translateChapterTitle` khi còn chữ Hán, kèm chuyển phồn → giản của truyện). Cấu hình đi từ `ReaderView` qua `AIRuntimeCoordinator.ActiveContext` / `ReaderAIFullScreenView` (tham số mới `translatesChapterTitles`, `convertsTraditionalToSimplified`, mặc định `false`) — màn AI không tự resolve vì không biết nguồn của truyện (bật dịch quyết theo truyện → nguồn → chung). Dịch lúc nạp danh sách, ngoài main thread; ô tìm khớp cả tên dịch lẫn tên gốc (`AINameScanChapter.rawTitle`).
- `rules.md`: bullet quét tên 1.3.602 thêm hai luật trên. Chuyển entry `[1.3.573]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.602] - 2026-10-26

### feat: quét tên chọn chương bắt đầu, chuẩn bị nhanh hơn, Gemini Web bớt lỗi

Người dùng: *"sửa lại app phần lọc name nhiều chương cho phép chọn chương bắt đầu lọc"*, *"tối ưu quét nội dung chương, hiện tại tôi thấy khá chậm"* (chậm ở bước "Đang chuẩn bị quét…", không gửi song song lượt API), *"Gemini Web dễ lỗi quá … dù tôi chỉ quét name 1 truyện vẫn lỗi"*, *"comment lại log [FD] đi"*, *"check vế phải của name để bỏ các trường hợp vế phải lộn tiếng trung"*, *"các trường hợp không trả về name hãy thử lại"*. Plan duyệt trong chat (1097 ⇒ mở chat mới; điểm tiếp nối dừng trước lượt lỗi; giữ `[FD] FAILURE`).

- **Chọn chương bắt đầu** (`ReaderAIBatchPromptSheet`, mới `ReaderAINameScanChapterPickerView`, `AINameScanChapter`): bỏ công tắc "Từ chương đang đọc", thay bằng 4 lựa chọn *Chương đang đọc* / *Tiếp nối lần quét trước* / *Chương đầu tiên* / *Chọn chương…* (danh sách chương **đã tải**, tìm theo số hoặc tên, tự cuộn tới chương đang chọn). Số chương hiện 1-based (trước hiện `ch.\(chapterIndex)` 0-based, lệch 1). Tóm tắt "Sẽ quét K chương: ch.a → ch.b". `onStart` → `(prompt, fromChapterIndex, limit)`; nhãn tin người dùng ghi đúng chương bắt đầu.
- **Điểm tiếp nối** (`AINameScanScopeStore` key `FreeBook_AI_NameScanResume_V1`, `AINameScanResumeTracker`): chương cuối của dãy lượt liên tiếp từ lượt 1 đều thành công — lượt lỗi chặn, lượt chưa gửi không tính, chỉ tính chương nằm trọn trong phần thật sự gửi (cắt 15.000/40.000 ký tự). Mở sheet mặc định chọn *Tiếp nối* khi còn chương sau điểm đó. Coordinator ghi điểm **sau** khi lưu phiên chứa tên của chính lượt đó; nút "Thử lại k lượt lỗi" đẩy điểm đi tiếp, context thử lại đồng bộ sau từng lượt (`syncNameScanRetry`). Dừng vì hạn mức/tài khoản: tên đã quét ở lại tin kết quả, lỗi thành tin riêng.
- **Bước chuẩn bị nhanh hơn** (mới `AINameScanTextLoader`, `BookBinManager.readChapterContents`): đọc khối 48 chương bằng **một** `FileHandle` mỗi lần gọi actor (trước: mỗi chương một lần nhảy actor + `fileExists` + mở/đóng file), chuẩn hoá song song tối đa 4 luồng qua `ChapterTextNormalizer.normalize`, giữ thứ tự; `makeBatches` đếm ký tự cộng dồn thay vì gọi `current.count` mỗi vòng (O(n²) grapheme). Dải tiến độ hiện "Đã đọc k/N chương"; log thường ghi ms đọc/chuẩn hoá/chia lượt. Ngữ nghĩa chia lượt không đổi.
- **Lọc name**: bỏ dòng có vế phải lẫn chữ Hán (`TranslateUtils.containsChinese`) ở `parseNamesFromText` và sheet "Thêm vào VP-Name" (`ReaderAINameReviewSheet`). Lượt không trả về name ⇒ nghỉ (Gemini Web 2 s, API 1 s) rồi gửi lại đúng lượt đó một lần, vẫn rỗng tính là lượt lỗi (vào vòng tự thử lại và nút Thử lại). `runTurns` tách sang `AINameExtractionBatchProcessor+Turns.swift` (file gốc 391 → 313 dòng).
- **Gemini Web — lượt quét tạm dừng khi app ở nền** (mới `GeminiWebForegroundGate`, `GeminiWebClient+NameScan`): log `app_logs (117)` (21–26/10) có ~30 lượt `StreamGenerate lỗi sau ~150 000 ms, chunk=0`, **tất cả** lúc app ở nền (iOS treo tiến trình web của WKWebView ẩn dù TTS giữ app sống). Nay lượt chờ app về trước (nghỉ 2 s), đang chạy mà app vào nền thì huỷ cả fetch trong trang rồi gửi lại đúng lượt khi mở lại app (tối đa 3 lần, không tính là lỗi, không nổi lên `CancellationError`; nút Dừng vẫn dừng ngay; lỗi tài khoản/hạn mức không gửi lại). Chỉ `didEnterBackground` tính là vào nền.
- **Gemini Web — 1097 ⇒ mở cuộc chat mới**: ~40 lượt `mã lỗi server 1097`, đều ở lượt nối tiếp lúc app đang mở; chat đã dính thì mọi lượt sau (kể cả thử lại sau 5 s) đều dính, mà luật 1.3.527 cấm lượt quét mở chat mới. Case mới `GeminiWebError.conversationBroken`; lượt quét bỏ lần chờ 5 s, mở chat mới với đủ ngữ cảnh và ghi nhớ cho phiên (chính lượt đó lỗi thì ném, không lặp). Google không công bố nghĩa 1097; cách khắc phục cộng đồng hay nêu là mở chat mới.
- **Gemini Web — fetch mồ côi**: huỷ `fetch` trong trang ở mọi lần stream kết thúc (trước đó watchdog timeout bỏ qua); `fetchStream` gắn `onTermination` ngay lúc tạo stream (`GeminiWebStreamTermination`) để lượt bị huỷ sớm không còn chạy fetch; `consumeGeneration` ném `CancellationError` khi bị huỷ (trước đó thành `protocolChanged` "không có ứng viên", bị coi như Google từ chối). Các dòng ❌ của luồng ghi kèm `(app ở nền)`/`(app đang mở)`.
- **Tắt log `[FD]`** (`FileDescriptorCensus`, `FileDescriptorStepProbe`, `FileDescriptorSweeper`): comment các dòng định kỳ (launch, chương, nền/active, `chunks=`, `step`, `tick`, `sweep`) và phần đếm chỉ phục vụ chúng. Giữ: nâng giới hạn fd, tự dọn fd mồ côi, `openCount()` cho màn log, `[FD] FAILURE` + bảng chụp lúc lỗi.
- `rules.md`: bullet mới về chọn chương/điểm tiếp nối và tạm dừng khi nền; luật 1.3.527 thêm ngoại lệ 1097. Chuyển entry `[1.3.572]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + 2 agent review phản biện (đã sửa 5 điểm: điểm tiếp nối vượt tên đã giữ khi thử lại bị dừng, đuôi lượt API bị cắt vẫn tính là đã quét, sheet nạp lại mục lục, fetch mồ côi khi huỷ sớm, lỗi tài khoản bị gửi lại); `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy. Còn để ngỏ: lượt bị huỷ vì vào nền vẫn giữ metadata dở (`rememberPartial`) nên lượt gửi lại có thể dính 1097 rồi tự mở chat mới.

## [1.3.601] - 2026-10-25

### fix: chip gợi ý màn Dịch hiện đủ nghĩa như màn quản lý, hoàn tác 1.3.600

Người dùng: *"lỗi là lỗi thỉnh thoảng có token dù có nghĩa vp/name nhưng chip chỉ hiển thị hán việt"*, *"màn quản lý nghĩa hiển thị được đầy đủ, chỉ chip thiếu"* → *"dựng thẳng từ đúng danh sách mà màn quản lý đang dùng"*; chọn hoàn tác 1.3.600.

- **Nguyên nhân**: thanh chip gợi ý (viền đỏ/xanh/xám, cạnh nút ⚙) tự tra lại từ điển bằng `buildSuggestionChips`, lệch với `dictionaryMatches` mà màn quản lý định nghĩa dùng ở hai chỗ: bỏ **cả mục** VietPhrase chung khi nghĩa dài ≥ 100 ký tự (giới hạn có từ bản đầu, không ghi lý do — từ thông dụng nhiều nghĩa rất hay vượt), và không tra Xưng hô / Luật nhân ⇒ thanh chỉ còn chip Hán-Việt.
- **Sửa** (`ReaderView+Suggestions`): chip dựng thẳng từ `dictionaryMatches` — `suggestionChips(from:)` tách mỗi nguồn theo `/` và `¦`, bỏ nghĩa trùng, giữ thứ tự nguồn; nhãn "Names (…)" viền đỏ, "Phiên âm" viền xám (chữ thường như cũ), còn lại viền xanh. `ReaderDefinitionWorker` dùng **chính** mảng `matches` vừa tính cho màn quản lý; `buildSuggestionChips` còn là lớp bọc (bỏ khoảng trắng hai đầu rồi gọi `dictionaryMatches`).
- **Hoàn tác code của 1.3.600**: chẩn đoán "rule dịch" ở 1.3.600 không phải nguyên nhân của báo lỗi này (người dùng xác nhận từ lỗi không nằm trong rule, và thanh lỗi là thanh chip gợi ý chứ không phải hàng token gạch chân). `getRuleAwareTokens`, `Segment.captures` và lời gọi trong worker trở về như trước 1.3.600; entry 1.3.600 giữ nguyên làm lịch sử.
- Đánh đổi: từ nhiều nghĩa ra nhiều chip (thanh cuộn ngang); Xưng hô / Luật nhân hiện cả khi công tắc tắt — giống màn quản lý.
- Chuyển entry `[1.3.571]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy — chạm lại token từng lỗi, thanh chip phải có chip xanh/đỏ bên cạnh chip xám.

## [1.3.600] - 2026-10-25

### fix: chip token ở màn Dịch tách từ theo rule dịch giống trang đọc

Người dùng: *"bị lỗi ở màn hình dịch của reader, thỉnh thoảng xuất hiện vài token thanh chip không có nghĩa, mặc dù sự thật chúng có nghĩa ở vp, name"* — chip hiện Hán-Việt, trang đọc dịch đúng, truyện không bật Phồn → Giản; duyệt phương án "mỗi từ một chip".

- **Nguyên nhân**: trang đọc (`performTranslation`) áp rule dịch (bật sẵn) **trước** khi tách token — rule tự bắt từ VP/Names (thử mọi độ dài, quay lui) rồi thay cả cụm bằng nghĩa. Thanh token của panel Dịch (`ReaderDefinitionWorker` → `getTranslationTokens`) tách thẳng chữ gốc, không qua rule: ở cụm rule đã xử lý, tokenizer chọn mục dài nhất toàn cục có thể vớ một mục VP vắt qua ranh giới token của rule và bỏ lại chữ lẻ không có mục riêng ⇒ chip hiện Hán-Việt. Đoạn không có rule khớp thì hai bên tách giống hệt — vì vậy chỉ "thỉnh thoảng".
- **Sửa**: `TranslateUtils.getRuleAwareTokens(for:bookId:)` (mới, `TranslateUtils+Tokenization`) — không có rule khớp ⇒ trả nguyên `getTranslationTokens`; đoạn đi qua ⇒ tách từ điển trên khúc gốc rồi dời offset; cụm rule ⇒ mỗi token rule một chip mang đúng nghĩa trang đang hiện, chữ giữa các token (literal của mẫu) tách từ điển; token rỗng/còn chữ Hán ⇒ tách chữ gốc; rule không có token ⇒ một chip cho cả cụm với kết quả rule. `QuickTranslationRewriteResult.Segment` thêm `captures` (mặc định `[]`), `QuickTranslationRuleEngine.assemble` ghi `match.captures` vào đoạn rule. `ReaderDefinitionWorker` gọi hàm mới ⇒ áp cho cả panel Dịch, Copy nội dung gốc, Xoá từ rác.
- **Không đổi**: `getTranslationTokens` (span, `mapSelection`, `snapToToken` vẫn tách thô); chip chưa áp Phồn → Giản (trang có áp).
- Chuyển entry `[1.3.570]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`QuickTranslationRuleEngine.swift` giữ 399 dòng). CI là cổng biên dịch; chưa thử trên máy — mở lại đoạn từng lỗi, chip ở chỗ rule khớp phải hiện đúng nghĩa như trang.

## [1.3.599] - 2026-10-25

### feat: tab Chi tiết bìa lớn, cỡ dòng danh sách 7 nấc, tên phim hiện đầy đủ

Người dùng: *"mockup lại UI của tab 1 trên màn chi tiết tương tự hình này"* (chọn phương án A qua 4 bản mockup), *"làm thêm phần điều chỉnh kích thước đối với kiểu hiển thị danh sách nữa"* → *"nhiều cỡ lên"* (7 nấc), *"tên video trong phần phát hãy hiển thị đầy đủ thay vì chỉ 2 hàng"*.

- **Tab Chi tiết** (`BookDetailHeaderView`): khối đầu mới `BookDetailHeroView` — nền là bìa làm mờ nhạt dần về màu nền, bìa lớn ở giữa, tên 22pt căn giữa, chip tác giả, chip nguồn (icon tiện ích + tên miền của host sách, không có thì tên tiện ích). Bìa dọc 150×210 hay ngang gần hết bề ngang theo **tỉ lệ thật của ảnh** (`BookCoverView.onImageSize` mới, thumbnail giữ tỉ lệ gốc; ≥ 1,15 là ngang, tối đa 2,4); chưa có ảnh thì video đoán ngang 16:9. Thông tin (`detail`), Thể loại, Giới thiệu thành thẻ bo góc `BookDetailSectionCard` (tiêu đề xanh nhạt). Đề xuất, bình luận, nút "+" và thanh tab Chi tiết/Mục lục giữ nguyên; thẻ Giới thiệu chỉ hiện khi có mô tả.
- **Thanh điều hướng màn Chi tiết**: bỏ chữ "Chi Tiết Truyện" (mục `.principal` rỗng; `navigationTitle` giữ làm nhãn quay lại của màn con), nút quay lại chỉ còn icon (`.toolbarRole(.editor)`). Nút dịch và ⋮ giữ nguyên.
- **Cỡ dòng kiểu Danh sách** (`BookListRowSize`, mới): 7 nấc, nấc 4 = cỡ cũ (bìa 50×70, tên 14.5pt) và là mặc định — ở nấc này mọi dòng dùng đúng font cũ. Nấc 1–2 là dòng gọn (tên 1 dòng, dòng phụ "tác giả · Ch./Tập N" hoặc mô tả 1 dòng). Lưu theo scope ở `bookListLayout.rowSize.<scope>` (sao lưu tự gói, "Đặt lại mặc định" xoá luôn). Sheet "Kiểu hiển thị" và màn Cài đặt có thanh trượt "Cỡ dòng" khi chọn Danh sách (sheet cao 240 → 268). Áp cho Kệ/Lịch sử/Bộ sưu tập (`ShelfBookRowView` → `BookListItemView`), Tìm trên kệ, tab Khám phá và màn Thể loại (`DiscoveryNovelRowView`), kết quả tìm trong một nguồn. `BookListItemView` thay `coverWidth`/`coverHeight` bằng `rowSize` (không caller nào truyền hai tham số cũ).
- **Màn phát video** (`VideoPlayerDetailsView`): tên phim và tên tập bỏ giới hạn 2 dòng.
- Chuyển entry `[1.3.569]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (đặc biệt: `.principal` rỗng có ẩn hẳn tiêu đề không, nền mờ khi kéo làm mới, chuyển bìa dọc → ngang khi ảnh về).

## [1.3.598] - 2026-10-25

### fix: tạm dừng rồi tiếp tục TTS không còn lùi lại vài đoạn

Người dùng: *"có lỗi tạm dừng tts rồi tiếp tục lại không phát tiếp tục mà lui lại vài đoạn"* (tiếp tục từ màn khoá/tai nghe); duyệt phương án A.

- **Nguyên nhân**: `ReaderView.updateScrollReadingProgress` (chạy mỗi lần một đoạn hiện/khuất, kể cả do TTS tự cuộn) hẹn 1,5 s sau gọi `TTSManager.updateParagraphPositionWithoutPlaying(đoạn trên cùng màn hình)` khi `isPlaying || showFloatingWidget`. Lúc phát thì hàm bỏ qua, nhưng đã tạm dừng thì nó kéo `currentParagraphIndex` về chunk đầu của đoạn trên cùng màn hình — thường ở trên đoạn đang đọc vài đoạn, vì TTS chỉ tự cuộn khi vệt đọc ra khỏi vùng an toàn. Audio đang dừng không được giải phóng nên Google/tiện ích phát nốt chunk cũ rồi `nextParagraph()` nhảy về "đoạn trên cùng + 1", NghiTTS nạp tiếp "đoạn trên cùng + 1".
- **Sửa**: cuộn trang không còn dời con trỏ TTS (xoá khối đồng bộ, `updateTTSPositionWorkItem`, `updateParagraphPositionWithoutPlaying`). Tiếp tục từ widget, màn khoá, tai nghe, sau cuộc gọi đều phát tiếp đúng chunk đang dừng.
- **Nút tai nghe trong Reader**: đang tạm dừng truyện này, cùng chương, đoạn đang dừng còn trong vùng an toàn của màn hình (`ParagraphTracker.isParagraphInsideSafeViewport`, cùng điều kiện tự cuộn) ⇒ `resume()`; đã kéo đi chỗ khác ⇒ giữ như cũ (dừng rồi đọc từ đoạn trên cùng). Muốn nghe chỗ khác vẫn có bôi đen → "Nghe".
- **Siri (`system`)**: `pause()` không tăng `audibleHandoffGeneration` cho Siri nữa — trước đây `onFinish` của utterance được `continueSpeaking()` bị `isContextValid` loại nên đọc xong chunk là im. Stop/skip vẫn tăng qua `stopCurrentPlayback()`.
- Đánh đổi: mất kiểu "dừng → kéo trang → tiếp tục ở widget/màn khoá thì đọc từ chỗ mới" (có từ 07/2026). `TTSChunkPositionMapper.indexForParagraphPosition` không còn caller trong `Sources/` nhưng giữ nguyên.
- Chuyển entry `[1.3.568]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới** (`TTSManager.swift` 3510 → 3500 dòng). CI là cổng biên dịch; chưa thử trên máy.

## [1.3.597] - 2026-10-25

### feat: kết quả tìm trong một nguồn theo kiểu hiển thị của loại nguồn

Người dùng: *"màn hình search chưa theo config layout, video, truyện, commic đang chỉ 1 kiểu, tôi đang nói search 1 nguồn"*.

- **Tìm trong một nguồn** (`SearchSingleSourceResultsView`, mới): dựng theo `BookListLayout` của loại nguồn đang tìm — `BookListLayoutScope(kind: SearchExtensionScopePolicy.kind(of:))`, cùng phạm vi với Khám phá của nguồn đó. Kiểu Danh sách giữ nguyên dòng cũ (bìa 50×70, mô tả → nội dung → tác giả, chip tên nguồn); kiểu Lưới / Chỉ bìa dùng `ScrollView` + `LazyVGrid` của `DiscoveryNovelGridCardView` (video bìa ngang 16:9, số cột theo cài đặt). Đang đổi nguồn thì chạm vẫn hỏi xác nhận; còn lại mở Chi tiết truyện, `bookId` giữ dạng cũ.
- **`SearchView`**: nút "Kiểu hiển thị" (icon theo kiểu đang chọn, 17pt semibold) ở góc phải thanh điều hướng, chỉ hiện khi tìm trong một nguồn (kể cả trước khi có kết quả), mở `BookListLayoutSheet`; đang tìm ở kiểu lưới thì hiện khung chờ dạng lưới (`DiscoverySkeletonGridView`). `searchResultCover` thành `static` để view mới dùng chung.
- Không đổi: tìm trên mọi nguồn (dải bìa ngang theo nguồn), chỉ tải trang 1, công tắc dịch của màn Tìm kiếm.
- Chuyển entry `[1.3.567]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.596] - 2026-10-24

### feat: màn Thông báo hiện phần trăm từng tập khi tải video

Người dùng: *"Cho màn hình thông báo cũng xem được phần trăm tải của từng tập"*.

- **Màn Thông báo** (`NotificationInboxView+StoryTasks`, hàng tác vụ đang chạy): tác vụ tải video ghi "Tải video · 3/10 tập · 34%" (trước là "Tải truyện · … chương"), thanh tiến độ chạy mượt theo phần trăm tập đang tải, thêm dòng "Tập 4: 45% · 210 MB" và nút **"Chi tiết tập (N)"** dùng chung `VideoEpisodeProgressList` với tab Tải. Tác vụ truyện/xuất ebook giữ nguyên.
- `DownloadTask.smoothProgressCount` / `videoProgressPercent` (mới, cạnh `VideoEpisodeProgress`): một chỗ tính tiến độ mượt + phần trăm cho cả tab Tải lẫn màn Thông báo.
- Chuyển entry `[1.3.566]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.595] - 2026-10-24

### feat: tab Tải hiện phần trăm từng tập của tác vụ tải video

Người dùng: *"vì tải video khả năng sẽ tốn khá nhiều thời gian, do đó đối với video tôi cần xem được phần trăm tải của từng video"*; chọn hiện ở **tab Tải** (không thêm gì lên ô tập trong trình phát), mockup đã duyệt.

- **`VideoEpisodeProgress`** (mới, `Services/Download`): trạng thái một tập — chờ / đang tải (phần trăm + byte) / xong (byte) / có sẵn / lỗi / đã huỷ. **`DownloadTask.videoEpisodes`**: trạng thái tạm, không lưu CSDL (không đổi `DownloadTaskModel`); app khởi động lại thì mất, thử lại tác vụ dựng lại.
- **`DownloadManager+Video`**: dựng danh sách lúc bắt đầu (tất cả "Chờ"), tập bỏ qua ⇒ "Có sẵn", bắt đầu ⇒ "Đang tải 0%", xong ⇒ "Xong" kèm dung lượng từ manifest, lỗi ⇒ lý do, huỷ ⇒ tập đang tải và các tập còn chờ thành "Đã huỷ". `VideoDownloadDetailReporter` (≤ 1 lần/giây) cập nhật trạng thái tập **và** dòng `mediaDetail` trong một lần ghi `tasks` (`updateVideoEpisode`; thay `updateMediaDetail`); nhịp đến muộn không kéo tập đã xong về "đang tải".
- **Tab Tải** (`DownloadTrackerView`): tác vụ video có thanh tiến độ chạy mượt trong tập (`progressCount` + phần trăm tập đang tải) và chữ "Tiến độ: 3/10 tập · 34%"; nút **"Chi tiết tập (N)"** (`VideoEpisodeProgressList`, mới) mở/thu danh sách "✓ Xong · 480 MB", "✓ Có sẵn", "↓ 45% · 210 MB", "Chờ", "✕ Lỗi: …", "Đã huỷ" — hiện ở mọi trạng thái tác vụ khi có danh sách. Trên 60 tập thì chỉ hiện mọi tập lỗi (tối đa 50), 10 tập xong gần nhất, tập đang tải, 5 tập chờ kế tiếp, kèm dòng đếm "Xong · Đang tải · Lỗi · Chờ · Đã huỷ".
- Chuyển entry `[1.3.565]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy.

## [1.3.594] - 2026-10-24

### feat: bấm PiP thì trình phát tự thu nhỏ về màn trước

Người dùng: *"khi nhấn video sang pip hãy tự trở về màn hình trước khi vào màn hình phát"*.

- `VideoPictureInPictureCoordinator.onDidStart` (mới) báo khi PiP **đã bật xong**; `VideoPlaybackSession.pictureInPictureStartCount` tăng mỗi lần. `VideoPlayerScreen` nghe số này: PiP đang bật và app đang `.active` (tức người dùng bấm nút PiP) ⇒ `leave(stopPlayback: false)` — thu nhỏ như vuốt xuống, phim chạy tiếp trong cửa sổ PiP, hub hiện mục Video; khôi phục từ PiP mở lại màn qua `requestScreen` như cũ.
- Chờ `didStart` chứ không rời màn ở `willStart`: gỡ layer khỏi cửa sổ lúc PiP đang bật dở có thể làm PiP hỏng. PiP **tự bật khi rời app** (app không còn `.active`) giữ nguyên màn như trước.
- Chuyển entry `[1.3.564]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; chưa thử trên máy (PiP chạy tiếp khi màn đóng, nút khôi phục mở lại đúng màn).

## [1.3.593] - 2026-10-24

### fix: bản tải video phát lại được sau khi app ra nền, ẩn nút xoá khi đã hết bản tải

Rà lại sau 1.3.592 (chưa thử máy), ba lỗi trong code mới:

- **Phát bản tải sau khi app bị treo nền**: listener 127.0.0.1 có thể đã chết nhưng URL item vẫn trỏ cổng cũ, và lượt tự nạp lại chỉ được **một lần mỗi tập** ⇒ tạm dừng / khoá máy lần hai trên cùng tập là báo lỗi, "Tải lại" cũng dùng lại cổng cũ. Nay mỗi lượt nạp HLS bản tải bật server mới (`VideoOfflineHTTPServer.stop()` trước `url(forRelativePath:)`, queue nối tiếp nên tắt xong mới bật); tự nạp lại sau lỗi tối đa một lần mỗi 20 giây (`offlineRetryWindow`, thay `offlineRetriedEpisodeIndex` bằng `offlineLastRetryUptime`).
- **Server không sẵn sàng**: `ensureRunning()` không có hạn chót — listener kẹt ở `.setup`/`.waiting` làm tập quay mãi ở "đang phân giải". Nay quá 3 giây chưa `.ready` ⇒ log ❌, tắt, trả `nil` ⇒ trình phát chuyển sang trực tuyến.
- **Nút "Xoá bản tải" còn hiện khi đã hết bản tải**: xoá dần từng tập / huỷ tập duy nhất để lại thư mục sách rỗng ⇒ `summary.hasFiles` vẫn `true`, nút hiện "0 byte". Nay `hasFiles` chỉ đúng khi còn tập trọn vẹn hoặc còn byte; xoá tập / bỏ bản dở thì dọn luôn thư mục sách rỗng.
- Chuyển entry `[1.3.563]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. CI là cổng biên dịch; vẫn chưa thử trên máy.

## [1.3.592] - 2026-10-24

### feat: tải video về máy để xem offline

Người dùng: *"làm thêm chức năng tải video nữa"*; chốt qua grill-me + mockup (plan `Docs/Plans/2026-10-24-plan-tai-video-offline.md`), rồi *"tự làm đi không cần hỏi nữa"*. Quyết định: tự tải từng đoạn + server nội bộ phát lại; chất lượng mặc định tối đa 720p (chọn lại trong sheet, nhớ cho lần sau); server đã nhớ trước, lỗi thì thử server khác; lối vào ở trang chi tiết + nhấn giữ trên kệ, menu `⋯` trình phát, nhấn giữ ô tập (không có dấu đã tải trên ô); mở tập đã tải phát bản tải + chip "Trực tuyến"; có nút xoá hết bản tải kèm dung lượng.

- **Lưu trữ** (`Services/Video/Offline/`): `VideoOfflineStore` — `videos/<sha256(bookId)>/<episodeIndex>/`, `manifest.json` (`VideoEpisodeManifest`) ghi **sau cùng**, `partial.json` = chữ ký nguồn bỏ query để tải tiếp bản dở, `validatePathSafety` riêng, `videos/` đặt `isExcludedFromBackup`; Backup không gói. `VideoDownloadQuality` (Cao nhất / Tối đa 1080p / 720p / 480p, UserDefaults `videoDownloadQuality`), `VideoDownloadRequestStore` (sidecar tập bắt đầu của "Tải tập này" theo `taskId` — không đổi `DownloadTaskModel`).
- **Bộ tải**: `VideoHLSOfflinePlanner` (thuần: biến thể + rendition của playlist gốc, playlist con ⇒ danh sách khoá/init/đoạn + playlist local URI tương đối; byterange tách file; giữ `MEDIA-SEQUENCE` cho IV AES-128; từ chối `SAMPLE-AES`/`skd://`/live), `VideoHLSDownloader` (chọn mức theo chất lượng, kèm luồng tiếng `EXT-X-MEDIA TYPE=AUDIO` của nhóm, playlist `fbhls://` ghép tiếng đọc từ `subPlaylists`), `VideoFileDownloader` (mp4 ghi luồng ra đĩa, tải tiếp bằng `Range`), `VideoOfflineHTTPClient` (header tiện ích, thử lại 3 lượt; 401/403/404/410 ⇒ phân giải lại link một lần). Tất cả **tuần tự**.
- **Tác vụ** (`DownloadManager+Video`, `VideoEpisodeDownloadPipeline`): nhánh video của `executeMediaTaskIfNeeded` không còn báo "không hỗ trợ"; server → track → `VideoSourceResolver` (bỏ `.embed`) → bộ tải → phụ đề đầu tiên → manifest; `isInteractive: false`. Bỏ qua tập đã có manifest cùng URL tập; còn dưới 1 GB trống ⇒ dừng; huỷ ⇒ bỏ bản dở của tập đang tải, lỗi/khởi động lại ⇒ giữ để tải tiếp. Mỗi phim chỉ một tác vụ video chạy một lúc (`runNextTasksIfNeeded`); "Tải tập này" trùng tập đang chờ/đang tải thì không thêm. `DownloadTask.mediaDetail` (tạm) = "Tập 4: 45% · 210 MB"; `displayTypeName` = "Tải video" (rawValue "Tải truyện" giữ nguyên vì được lưu bền).
- **Phát bản tải** (`VideoPlaybackSession+Offline`): `runEpisodeLoad` thử bản tải **trước** khi tra tiện ích ⇒ xem được khi không mạng / tiện ích đã gỡ. HLS qua `VideoOfflineHTTPServer` + `VideoOfflineHTTPResponder` (`NWListener` **chỉ 127.0.0.1**, cổng + token ngẫu nhiên, chỉ file dưới `videos/`, `GET`/`HEAD` + `Range`), mp4 phát `file://`; phụ đề + mốc "Bỏ qua" từ manifest. Bản tải không kiểm tiếng; item lỗi ⇒ bật lại server, nạp lại một lần. Chip "Bản tải" / "Trực tuyến" ở hàng server và menu server.
- **UI**: `VideoOfflineLibrary` (`@MainActor @Observable`) là nguồn trạng thái đã tải/đang tải/dung lượng cho View. Menu `⋯`: "Tải tập này" / "Xoá bản tải tập này" + "Tải nhiều tập…" (`TaskOptionsSheet`). Nhấn giữ ô tập: "Tải tập này" / "Xoá bản tải". Trang chi tiết: "Tải video offline" + "Xoá bản tải · N tập · X GB" (`VideoDownloadsDeletePill`). Nhấn giữ trên kệ: "Tải video offline" + "Xoá bản tải (…)" (`VideoDownloadsActionRow`, xử lý ngay trong sheet). `TaskOptionsSheet` chế độ video ("Tải từ tập đang xem", "Số lượng tập", "Chất lượng"). Tab Tải: "Tải video", "x/y tập", dòng phần trăm trong tập.
- **Xoá**: `BookStorageManager` (cả 3 đường xoá) và `BookSourceMigrator` xoá `videos/<sha256(bookId)>`; `BookContentDestination` mở phim đã tải bằng trình phát khi tiện ích đã gỡ.
- Tài liệu: `rules.md` mục "Tải video offline (1.3.592)"; `CLAUDE.md`/`AGENTS.md` thêm `videos/` vào danh sách lưu trữ + mục Comic & Video. Chuyển entry `[1.3.562]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code + agent soát lỗi biên dịch; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch. **Chưa thử trên máy**: AVPlayer phát HLS qua `http://127.0.0.1` trong LiveContainer, `NWListener` loopback (có hỏi quyền Mạng cục bộ không), khoá AES-128, nguồn ngụy trang đoạn `.jpg/.png`, tải tiếp sau khi app ra nền. Thử lần đầu: bật log, tải 1 tập từ menu `⋯` → tab Tải có % → bật chế độ máy bay → mở tập (chip "Bản tải") → tua, phụ đề; lỗi thì gửi `app_logs.txt` (dòng `[VideoOffline]`, `[VideoOfflineServer]`).

## [1.3.591] - 2026-10-24

### feat: tắt NSFW ẩn khỏi Kệ/Bộ sưu tập/Tải/hub/phạm vi dịch, video trình duyệt phát tại chỗ, player chọn chất lượng

Người dùng: *"khi tắt nfsw thì cũng phải ẩn ở kệ sách nữa"*, *"nói chung tắt nfsw thì mọi danh sách phim, comic, truyện đều phải ẩn. liệt kê ra chỗ còn sót rồi tôi sẽ duyệt"*; *"browser của app khi click vào video luôn tự mở rồi phóng to lên…"*; *"thêm mục chọn chất lượng cho player nếu được"*. Duyệt: Kệ sách, Bộ sưu tập, tab Tải, hub nổi, phạm vi dịch + plan video trình duyệt + chất lượng; **không** lọc Thông báo (chương mới) và thứ đang phát (widget TTS, màn khoá, PiP). Tải video tách sang phiên riêng.

- **`RepositoryFilterPolicy.excludingNsfwSources(_:includeNsfw:packageId:)`** (mới, generic): bỏ phần tử của nguồn NSFW, giữ thứ tự, mỗi `packageId` tra một lần — dùng chung cho các danh sách dưới đây. Chỉ ẩn hiển thị, dữ liệu giữ nguyên.
- **Kệ sách** (`ShelfBookPartition(hidesNsfw:)`, đổi từ `hidesNsfwHistory`): tắt NSFW bỏ **mọi** sách của nguồn NSFW, cả ghim/chưa ghim lẫn lịch sử (chip loại suy ra từ partition nên tự theo). **Tìm trong Kệ** quan sát công tắc, bỏ cả sách trên kệ.
- **Bộ sưu tập**: danh sách trong bộ (`CollectionDetailView`), 3 bìa xem trước + số truyện của thẻ (`CollectionGridCardView.visibleBooks(of:includeNsfw:)`), số truyện ở màn sắp xếp bộ.
- **Tab Tải** (`DownloadTrackerView`): ẩn tác vụ tải/xuất của truyện nguồn NSFW (tác vụ vẫn chạy).
- **Hub nổi** (`FloatingHubPresentationReader`): "AI đang chạy" bỏ truyện của nguồn NSFW — run AI không lưu `packageId` nên suy từ tiền tố `bookId` (`BookIdUtils.make` = `<packageId viết thường>_<16 hex>`), không khớp tiện ích nào thì không ẩn; mục Video coi phim NSFW thu nhỏ như không có video (nút hub không nháy vì nó). `VideoMiniPlayerState.packageId` (mới, ghi trước `isActive`). Công tắc theo dõi qua `UserDefaults.didChangeNotification` rút về một bit.
- **Quản lý phạm vi dịch** (`TranslationScopeManagementView`): không liệt kê nguồn NSFW và truyện của nguồn NSFW (truyện đã xoá khỏi thư viện thì không biết nguồn ⇒ vẫn liệt kê); cấu hình vẫn có hiệu lực, "Đặt lại tất cả" vẫn xoá cả mục bị ẩn.
- **Video trong trình duyệt phát tại chỗ**: `BypassBrowserTabStore` bật `allowsInlineMediaPlayback`; **`InlineMediaScript`** (mới, `Services/Browser`) gắn `playsinline`/`webkit-playsinline` cho mọi `<video>` ở mọi frame (quét DOM, `MutationObserver`, `loadstart` + chạm ở pha capture — không sửa prototype). Tab mở từ link dùng config WebKit chép từ tab mẹ nên cũng có. Nút toàn màn hình của trang vẫn dùng được.
- **Chất lượng** (`VideoPlaybackSession+Quality`, `VideoQualityOption` — mới): sau mỗi item đọc `AVAsset.variants`, mỗi độ phân giải giữ biến thể bitrate cao nhất, bỏ biến thể chỉ tiếng; từ 2 mức ⇒ menu `⋯` có "Chất lượng · <mức>" (Tự động + 1080p/720p…). Chọn = **trần** (`preferredPeakBitRate` + `preferredMaximumResolution`) — mạng yếu vẫn có thể thấp hơn. Lựa chọn giữ qua các tập (áp mức cao nhất không vượt lựa chọn), `stop()` về Tự động. `refreshBandwidthLimit` gộp: đang ẩn ⇒ thấp nhất, hiện ⇒ trần đã chọn hoặc không giới hạn. mp4 / HLS một mức / playlist ghép hình + tiếng ⇒ không có mục.
- Cài đặt › Nội dung nhạy cảm: dòng Kệ đổi thành danh sách các chỗ ẩn mới.
- Chuyển entry `[1.3.561]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (đặc biệt: `variants` với asset qua resource loader `fbhls://`, `playsinline` trên các trang thật).

## [1.3.590] - 2026-10-24

### feat: Google/Bing/Baidu lên đầu, tắt NSFW giữa lượt tìm bỏ nguồn NSFW, player ẩn điều khiển khi vuốt và hạ chất lượng khi phát ẩn

Người dùng: *"để google, bing, baidu lên đầu danh sách. khi tìm tất cả nếu tắt nsfw thì không tìm các nguồn nsfw. ở phần player, nếu vuốt tua nhanh, tăng giảm sáng, tăng giảm âm lượng hãy tự ẩn phần đường timeline và các nút tua 10s. nếu được thì khi video phát ở chế độ ẩn thì hãy phát audio của nó thôi để giảm lưu lượng tốn"*; duyệt plan (ẩn **cả** lớp điều khiển khi vuốt; **giữ** ngoại lệ đổi nguồn cho truyện NSFW — *"bật nsfw mới xem được nsfw"*).

- **Truy cập nhanh** (`BypassBrowserHomeView`): Google, Bing, Baidu đứng đầu rồi mới tới tiện ích; tiện ích trùng đúng URL của một trong ba thì bỏ ô trùng.
- **Tìm mọi nguồn**: tắt NSFW từ trước thì vốn đã không tìm nguồn NSFW (`searchableExtensions` → `applyNsfwFilter`). Sửa ca **tắt giữa lượt tìm**: `SearchView.dropHiddenNsfwSources` gỡ nguồn NSFW khỏi `sourceStates` (số "Tìm thấy N", trạng thái rỗng, vòng "đang tìm" tính lại), kết quả về muộn của khoá đã gỡ bị bỏ; `LegadoSearchScheduler.searchAll(shouldStart:)` xét lại nguồn Legado **đang xếp hàng** lúc tới lượt — NSFW mà công tắc đã tắt thì không chạy (báo `nil`). Request của tiện ích JS đã gửi thì không thu hồi được. Ngoại lệ đổi nguồn cho sách của nguồn NSFW giữ nguyên, tách thành `SearchExtensionScopePolicy.keepsNsfw` dùng chung cho cả lọc lẫn bộ lập lịch.
- **Player — vuốt** (`VideoPlayerController.handlePanBegan`): bắt đầu vuốt tua / độ sáng / âm lượng ⇒ ẩn **cả** lớp điều khiển (kiểu YouTube), nhả tay vẫn ẩn, chạm để hiện lại; vuốt xuống thu nhỏ không đổi.
- **Player — phát ẩn** (`VideoPlaybackSession.refreshBandwidthLimit`): khi đã tách hình (thu nhỏ / nền không PiP — vốn đã chỉ phát tiếng) đặt `preferredPeakBitRate = 1` ⇒ HLS xuống biến thể thấp nhất; gắn lại hình ⇒ `0`. Gọi ở `refreshLayerAttachment` và sau `replaceCurrentItem` (tập kế tự phát lúc đang ẩn). Chỉ đỡ dữ liệu với HLS **nhiều** mức chất lượng; mp4, playlist một mức, playlist ghép hình + tiếng (`VideoAudioRenditionComposer`) không giảm được; không đổi sang luồng chỉ tiếng (thay item lúc PiP/nền/thu nhỏ làm hỏng các ca đó). Về lại màn hình thì vài giây đầu hình còn mờ.
- Chuyển entry `[1.3.560]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.589] - 2026-10-24

### feat: tắt NSFW tự đóng màn của nguồn NSFW, Home trình duyệt chỉ giữ Google/Bing/Baidu

Người dùng: *"khi tôi xem các màn khác của nguồn nfsw mà nếu sau đó tôi tắt nfsw đi thì hãy tự tắt các màn đó đi giúp tôi, phím tắt nhanh ở home ngoài các tiện ích ra hãy chỉ giữ lại google, bing, baidu thôi"*; duyệt plan (đóng cả màn của truyện trên Kệ, làm luôn vuốt lùi về Home hết ẩn danh).

- **`NsfwSourceScreenGuard`** (mới, `Views/Common`, `.closesWhenNsfwHidden(packageId:isEnabled:)`): màn của một nguồn tự `dismiss` khi công tắc NSFW toàn app bị tắt mà màn đã **thấy NSFW bật** lúc đang mở (bật lúc mở hoặc bật trong lúc mở) — màn mở khi NSFW đang tắt (sách NSFW trên Kệ) không bị đụng. `packageId` chụp ở lần xuất hiện đầu: Khám phá đổi nguồn khi NSFW tắt và dựng lại màn thể loại đang mở với nguồn **mới**, đọc giá trị sống thì không bao giờ đóng. Xét cả ở `onAppear` (màn ở tab khác / dưới stack có thể chưa nhận `onChange` tới khi hiện lại); `dismiss()` chạy ở lượt main kế tiếp; log không ghi tên nguồn.
- Gắn vào **Chi tiết truyện** (`BookDetailView` — mọi lối vào, kể cả truyện trên Kệ), **danh sách thể loại / xem thêm** (`CategoryNovelsListView`), **tìm trong một nguồn** (`SearchView` ở chế độ một nguồn, không phải đổi nguồn — `isEnabled` đọc sống theo công tắc "tìm mọi nguồn"). Tìm mọi nguồn: `SearchView` quan sát công tắc NSFW và truyền thẳng vào `searchableExtensions` ⇒ nhóm kết quả của nguồn NSFW biến mất ngay; dòng "Tìm thấy N truyện" giữ số cũ tới lượt tìm sau.
- Không cần guard: Reader / truyện tranh / video / trình duyệt (toàn màn hình) và cấu hình tiện ích / chi tiết nguồn Legado (sheet) — lúc chúng mở không với tới công tắc NSFW. TTS đang đọc truyện NSFW và widget nổi **không** bị dừng.
- **Home trình duyệt**: Truy cập nhanh ngoài ô tiện ích chỉ còn Google, Bing, Baidu (bỏ YouTube, Bilibili, Weibo, Zhihu, Wikipedia, Dịch GG, Tangthuvien, Qidian, 69shu).
- **Ẩn danh**: lùi/tiến về Home (`about:blank` của khung chính, `navigationType == .backForward`) cũng tắt `isIncognito` như nút Home; cửa sổ mới mở trống (cũng `about:blank`, loại `.other`) giữ ẩn danh thừa hưởng. **Chưa kiểm trên máy** việc WebKit có gọi `decidePolicyFor` cho trang lấy từ bộ đệm lùi/tiến hay không.
- Cài đặt › Nội dung nhạy cảm thêm dòng giải thích màn tự đóng.
- Chuyển entry `[1.3.559]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.588] - 2026-10-24

### feat: trình duyệt ẩn nguồn NSFW ở Home và tự ẩn danh với nguồn không lưu lịch sử

Người dùng: *"khi tắt nsfw thì đừng hiển thị các nguồn đó ở home của trình duyệt, tự động duyệt ẩn danh nếu config lựa chọn không lưu lịch sử"*; duyệt plan (ẩn danh theo tab, ẩn cả lịch sử duyệt cũ, thêm giải thích ở Cài đặt).

- **`BrowserSourceSiteIndex`** (mới, `Services/Browser`): dò trang thuộc nguồn **đã cài** nào theo tên miền — host của trang trùng tên miền `sourceUrl` hoặc là tên miền con của nó, so **một chiều** (nguồn ở `xyz.blogspot.com` không kéo `blogspot.com`), bỏ `www.` hai phía. Gồm cả nguồn Legado; tra một host thì lọc thô bằng chuỗi con tên miền gốc trước khi phân tích URL, tra cả danh sách thì dựng chỉ mục một lần.
- **Ẩn danh theo tab** (`BypassBrowserTab.isIncognito`): áp cho nguồn đang tắt "Lưu lịch sử đọc/xem" (`ExtensionHistoryPolicy`, mặc định = nguồn NSFW), **không** phụ thuộc công tắc NSFW. `BypassBrowserTabStore` bật cờ ở mọi điều hướng khung chính (kể cả chuyển hướng sang mirror) và xét lại ở `didFinish` (trang khôi phục từ bộ đệm lùi/tiến); tab ẩn danh không ghi `BrowserHistoryStore`. Tab mở từ tab ẩn danh (`createWebViewWith`, mở cửa sổ đã chặn) thừa hưởng; về Home (`loadHome`, tab mới) thì hết. Ô URL hiện icon `eye.slash`. Ẩn danh **chỉ** bỏ ghi lịch sử: cookie vẫn ở kho WebKit mặc định — dùng chung với trình duyệt ẩn của tiện ích — để vượt Cloudflare/đăng nhập ở đây vẫn có tác dụng cho nguồn. Log không ghi host.
- **Home trình duyệt khi tắt NSFW**: Truy cập nhanh bỏ tiện ích NSFW (`RepositoryFilterPolicy.applyNsfwFilter`); Lịch sử truy cập ở Home và màn "Xem thêm" (`BrowserHistorySheetView`) ẩn mục thuộc trang của nguồn NSFW (chỉ ẩn, không xoá; "Xóa toàn bộ" vẫn xoá cả mục bị ẩn). Nút Import truyện không đổi.
- **Giải thích**: Cài đặt › Nội dung nhạy cảm thêm dòng cho danh sách chọn truyện chia sẻ/nhập từ điển riêng (1.3.587), Home trình duyệt và ẩn danh; dòng Kệ đổi thành "vẫn hiện ở Kệ và Tìm trong Kệ". Chú thích công tắc "Lưu lịch sử đọc/xem" (`ExtensionConfigView+History`) nhắc trình duyệt tự ẩn danh.
- Chuyển entry `[1.3.558]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: đọc code; `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.587] - 2026-10-24

### fix: danh sách chọn truyện chia sẻ/nhập từ điển riêng theo công tắc NSFW

Người dùng: danh sách truyện để chia sẻ VP và nhập VP *"chưa theo config nsfw"*.

- **Nguyên nhân**: `BookShareTargetSheet` / `BookImportSourceSheet` (3 lối vào: chia sẻ + nhập từ điển riêng ở `DictionaryListView`, chia sẻ rule dịch nhanh ở `QuickTranslationRuleListView`) nạp mọi `Book` rồi chỉ bỏ truyện đang mở, không xét công tắc NSFW toàn app.
- **Sửa**: `loadBooks()` của hai sheet đọc `RepositoryFilterPolicy.includesNsfwPreference` một lần; tắt ⇒ bỏ **mọi** truyện có `RepositoryFilterPolicy.isNsfwSource` (cả nguồn Legado), **kể cả truyện trên kệ** — người dùng chọn chặt hơn Kệ/Lịch sử (vốn giữ sách trên kệ). Truyện không ở kệ cũng không ở lịch sử vẫn hiện như cũ. Sheet modal nạp một lần nên không theo dõi công tắc khi đang mở.
- Màn Cài đặt › Nội dung nhạy cảm chưa nhắc hai sheet này (dòng "Sách đã thêm lên Kệ vẫn hiện bình thường" chỉ đúng cho Kệ).
- Chuyển entry `[1.3.557]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.586] - 2026-10-22

### merge: đưa nguồn Legado (đợt 1–3) vào main

Gộp nhánh `claude/legado-source-bb5e46` (nguồn truyện Legado viết mới theo đặc tả — engine rule/mạng/JS, tab Nguồn Legado, tranh/video, đăng nhập, quản lý, bộ chạy nghiệm thu) vào `main`.

- **Đánh lại số phiên bản**: `main` đã dùng 1.3.557–1.3.561 cho năm commit của các phiên khác, nên các mục của nhánh **1.3.557–1.3.580 nay là 1.3.562–1.3.585** (cộng 5; đổi cả chỗ nhắc trong `rules.md`, `check_architecture.py`, comment `AppFilledButtonStyle`). Số cũ còn gặp trong ghi chú/hội thoại trước ngày 2026-10-22 thì cộng 5.
- **Xung đột**: chỉ ở `CHANGELOG.md` / `CHANGELOG.archive.md` — giữ mục của cả hai phía (Legado ở trên), phần đã chuyển sang lưu trữ theo nhánh; đối chiếu đủ mọi phiên bản của hai phía, không mất mục nào (ba số trùng 1.3.172/173/180 có sẵn từ trước). Đẩy 1.3.551–1.3.556 sang lưu trữ để file chính còn ~30 mục.
- **File Swift tự gộp** (`SearchView`, `DiscoveryView`, `ExtensionSelectorView`, `BookDetailView`, `SearchExtensionScopePolicy`): đã đọc lại hai phía — `kindScopePackageId` của `main` và bộ lọc/lịch tìm nguồn Legado của nhánh cùng tồn tại; `main` không thêm lời gọi `ExtensionManager.shared.<x>` trực tiếp nào bỏ qua `SourceRuntime`.
- **Kiểm chứng**: xem commit merge. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.585] - 2026-10-22

### fix: ô Khám phá của nguồn Legado hiện đủ chữ: 3 dòng, tự co chữ, cao bằng hàng

Người dùng: tag ở Khám phá của nguồn Legado *"nhỏ quá"*, chữ bị cắt — nhiều nguồn khai 4 ô/hàng (`style.layout_flexBasisPercent: 0.25`) cho nhãn tiếng Trung 2–3 chữ, bật dịch thì nhãn tiếng Việt dài gấp đôi. Người dùng chọn **giữ số ô/hàng nguồn khai**, chỉ tinh chỉnh để chữ hiện đủ.

- **`LegadoExploreTabView`** (ô bấm, kể cả tag tìm nhanh): `lineLimit` 2 → **3**; `minimumScaleFactor(0.75)` + `allowsTightening` ⇒ chữ co (15pt → ~11pt) trước khi phải cắt "…"; đệm ngang 6 → 4, thêm đệm dọc 4; khung `maxHeight: .infinity` ⇒ các ô cùng hàng cao bằng ô cao nhất (`LegadoFlexLayout` đã tính chiều cao hàng theo ô cao nhất, không sửa).
- Tiêu đề nhóm, ô chọn / ô nhập / nút của nguồn giữ nguyên. Đánh đổi: ô có nhãn quá dài có chữ nhỏ hơn ô bên cạnh.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.584] - 2026-10-22

### fix: nguồn Legado dùng bộ giới hạn nhịp kiểu Java (69書吧) dựng được URL tìm kiếm

Từ báo cáo `kiem-tra-nguon-legado-20261022-160304.json`: 69書吧 báo *"Nguồn không có URL gốc để ghép"* dù `searchUrl` là `@js:` dựng URL tuyệt đối.

- **Nguyên nhân**: hàm `buildRequest` trong `jsLib` của nguồn kiểm chữ ký `bookSourceComment`, giới hạn nhịp bằng `java.lang.System.getProperties().computeIfAbsent(…, k => new AtomicLong(0))` + `System.nanoTime()` + `compareAndSet` + `LockSupport.parkNanos`, rồi ký request. Giả lập `java.lang.System` của app chỉ có `currentTimeMillis` ⇒ JS ném `TypeError`, URL thành rỗng, `LegadoURLBuilder` báo nhầm thành `missingBaseURL`. Không phải thiếu cấu hình đăng nhập (`loginUi` chỉ có 2 nút).
- **Script `concurrent`** (`LegadoJSBootstrap+Concurrent`, nạp sau `classes`): `java.util.concurrent.atomic.AtomicLong` / `AtomicInteger` (get/set/compareAndSet/getAndSet/addAndGet/increment…), `System.getProperties()` (bảng `get`/`put`/`putIfAbsent`/`computeIfAbsent`/`getProperty`/`setProperty`…), `System.nanoTime()`, `getProperty`/`setProperty`/`clearProperty`/`lineSeparator`, `LockSupport.parkNanos`/`parkUntil` (qua lệnh `sleep` sẵn có: ≤ 5 giây, huỷ được).
- **Ô dùng chung toàn tiến trình** (`LegadoJavaSharedCells` + lệnh native `javaCell`/`nanoTime` ở `LegadoJSRuntime+Concurrent`): mỗi tác vụ một `JSContext`, nên `AtomicLong` đặt vào bảng thuộc tính được gắn với ô native theo khoá — nhờ vậy bộ giới hạn nhịp của nguồn có tác dụng giữa các chương. Chỉ giữ số, tối đa 512 ô, không ghi đĩa. Nguồn này tự giãn: tìm ~5 s/lần, nội dung ~2 s/lần — là ý của nguồn.
- **`java.lang.System`**: thành viên chưa có ⇒ lỗi "chưa hỗ trợ" thay vì `TypeError … is not a function`, để Kiểm tra nguồn quy về giới hạn của app.
- **`LegadoURLBuilder`**: URL không thành tuyệt đối mà JS dựng URL vừa lỗi ⇒ báo đúng lỗi đó (`unsupportedSyntax` trước, rồi `javaScript`); URL rỗng ⇒ `invalidURL`; `missingBaseURL` chỉ còn cho URL tương đối khi nguồn không có URL gốc.
- **Kiểm chứng**: chạy `jsLib` thật của nguồn cùng các script bootstrap trích từ Swift trong Node `vm` ⇒ ra đúng URL tìm kiếm kèm header ký. `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (tìm → chi tiết → mục lục → nội dung).

## [1.3.583] - 2026-10-22

### fix: trình duyệt ẩn của nguồn Legado chờ trang thử thách JS tự tải lại rồi mới lấy HTML

Từ báo cáo `kiem-tra-nguon-legado-20261022-160304.json`: 起点小说 và 🎉起点中文网 (tìm kiếm `webView:true`) luôn nhận trang ~1 KB và bị kết luận nhầm "nguồn lỗi thời".

- **Nguyên nhân**: lần tải đầu, qidian trả HTTP 202, 209 byte — thân rỗng + `probe.js`; trong trình duyệt, script này đặt cookie rồi tự tải lại đúng URL (trang thật ~60 KB, 11 mục `.res-book-item`). `WebViewLoader` báo xong ngay lần tải đầu nên `LegadoWebViewFetcher` lấy HTML trang thử thách rồi dọn WebView — JS không kịp đặt cookie, lần nào cũng gặp lại trang thử thách.
- **Chờ trang lắng** (`LegadoWebViewFetcher+Settle`, file mới): sau lần tải đầu, mỗi 0,25 s kiểm `webView.isLoading`; trang phải yên liên tục 0,5 s mới xét. Một đoạn JS đếm chữ / ảnh / script / meta refresh: dưới 64 ký tự chữ, dưới 3 ảnh, có script hoặc meta refresh ⇒ coi là trang chờ, chờ tiếp tối đa 8 s kể từ lần tải xong gần nhất. Trần cứng vẫn là timeout của request (không kéo dài tổng thời gian chờ); huỷ thì dừng ở lượt kiểm kế tiếp. Trang thường chỉ chậm thêm ~0,5 s.
- **Sửa kèm**: `webViewDelayTime` giờ tính **sau** khi trang lắng, và HTML được đọc lại sau khoảng chờ đó (trước đây dùng bản chụp cũ, sai spec §4.4). `java.webView(html, …)` (nạp chuỗi HTML) không qua bước chờ lắng; đường `sourceRegex` không đổi.
- **Kiểm chứng**: cơ chế tải lại và ngưỡng phân loại đã quan sát trên trình duyệt Chromium, **chưa** trên WKWebView của iPhone. `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy (thử sau khi xoá cookie, vì kho cookie WebKit giữ lại giữa các lần).

## [1.3.582] - 2026-10-22

### fix: kiểm tra nguồn Legado không kết luận nhầm "lỗi thời" với trang báo lỗi ngắn, từ khoá mặc định dài hơn

Từ báo cáo `kiem-tra-nguon-legado-20261022-160304.json`: 抖音小说 bị kết luận **"Nguồn lỗi thời"**, nhưng web thực ra trả trang 444 byte chỉ có `alert("关键字最少 10 个字符")` — chê từ khoá mặc định `我的` quá ngắn. 起点 cũng bị kết luận lỗi thời với trang tìm kiếm ~1 KB (trang thử thách JS, sửa riêng).

- **Bộ phân xử** (`LegadoFailureArbiter`): trang 2xx dưới **3 KB** (`minimumOutdatedPageBytes`) hoặc trang có `alert(...)` **không** còn đủ để kết luận "nguồn lỗi thời" — rơi về "Chưa rõ" kèm lý do cụ thể:
  - có `alert(...)` ⇒ *"Web báo: «…»"*, ở bước tìm kiếm thêm gợi ý thử từ khoá khác;
  - trang quá ngắn ⇒ *"Trang trả về rất ngắn (HTTP …, N KB) — thường là trang báo lỗi, chặn, hoặc trang thử thách JS chưa chạy xong"*.
- **Dò bộ chọn** (`LegadoSelectorProbe`): thêm `alertMessage` — câu trong `alert("…")` đầu tiên của trang ≤ 4 KB (gọn khoảng trắng, tối đa 200 ký tự).
- **Từ khoá mặc định** khi nguồn không khai `checkKeyWord`: `我的` → `斗罗大陆` (Kiểm tra nguồn `LegadoCorpusRequest` và Gỡ lỗi nguồn `LegadoDebugInput`) — đủ dài để web có giới hạn độ dài từ khoá không chặn, và là tên truyện phổ biến nên dễ có kết quả.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.581] - 2026-10-22

### fix: chia sẻ báo cáo và xuất nguồn Legado báo nhầm "truy cập file ngoài thư mục" từ lần thứ hai

Người dùng: *"có thông báo truy cập file ngoài thư mục chia sẻ báo cáo bị từ chối"*.

- **Nguyên nhân**: thư mục tạm của iOS nằm dưới `/private/var/…`, và `URL.standardizedFileURL` chỉ bỏ tiền tố `/private` khi đường dẫn **đã tồn tại**. Lần đầu thư mục chia sẻ chưa có ⇒ hai bên cùng `/private/var/…`, khớp. Từ lần thứ hai thư mục đã có (rút thành `/var/…`) còn tệp mới chưa có (giữ `/private/var/…`) ⇒ `validatePathSafety` tưởng tệp nằm ngoài thư mục và từ chối.
- **Sửa**: `LegadoCorpusReportShare` (chia sẻ báo cáo Kiểm tra nguồn) và `LegadoSourceExporter` (xuất / chia sẻ nguồn — cùng ghi vào thư mục tạm, cùng lỗi) so sánh thành phần đường dẫn sau khi **tự bỏ `/private`** (`comparableComponents`), không phụ thuộc tệp đã tồn tại hay chưa. Các kho khác của nguồn Legado ghi vào Application Support (`/var/…`, không có `/private`) nên không bị.
- Chuyển entry `[1.3.546]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.580] - 2026-10-22

### fix: nút chia sẻ chỉ chạy được lần đầu: bảng chia sẻ đóng xong không báo SwiftUI

Người dùng: *"tôi bấm chia sẻ kiểm tra nguồn nhưng không thấy hoạt động, trước đây có thành công 1 lần"*.

- **Nguyên nhân**: `UIActivityViewController` tự đóng khi chia sẻ xong (hoặc huỷ) mà SwiftUI không biết ⇒ cờ `isPresented` / `item` của `.sheet` kẹt ở "đang mở"; lần bấm sau gán URL mới khi cờ vẫn `true` nên không có gì hiện ra.
- **`ShareSheet`** (dùng chung cả app — sao lưu, từ điển, rule dịch, lọc rác, công cụ tìm kiếm, xuất nguồn Legado…): trong `completionWithItemsHandler` gọi `dismiss` của chính sheet (`context.environment.dismiss`, trên MainActor) sau `onComplete` ⇒ SwiftUI hạ trạng thái, lần sau trình bày lại được.
- **Màn Kiểm tra nguồn**: `onComplete` hạ `shareURL`; nếu cờ vẫn kẹt khi bấm lại thì hạ trước, chờ ~0,4 s cho sheet cũ gỡ xong rồi mới trình bày.
- Chuyển entry `[1.3.545]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.579] - 2026-10-22

### feat: tự kết luận lỗi nguồn Legado do web, do nguồn hay do app, chia sẻ báo cáo kiểm tra

Người dùng: *"nhiều nguồn lỗi nhưng không biết lỗi do nguồn hay do app"*; xem mockup rồi bảo *"tiếp tục"*.

- **Bộ phân xử** (`LegadoFailureArbiter` + `+Evidence`, `LegadoFailureVerdict`, hàm thuần, `Services/LegadoSource/Diagnostics/`) — dừng ở luật đầu khớp:
  1. **Cần xác minh / đăng nhập**: trang thử thách/captcha (dấu `challenge-platform` chỉ tính khi mã ≥ 400 vì Cloudflare chèn cả vào trang thường; chữ yếu như "captcha" chỉ tính trong `<title>`, trang < 6 KB hoặc mã ≥ 400), nguồn có `loginUrl` bị 401/403, hoặc engine báo cần trình duyệt/mã xác minh khi chạy không tương tác.
  2. **Web chặn / sập**: trang chặn theo vùng / từ chối truy cập (`LegadoPageMarker`), lỗi mạng, engine quá thời gian, HTTP 403 / 404 ở bước đầu / 410 / 429 / 451 / 5xx.
  3. **Nghi do app**: cú pháp/hàm chưa hỗ trợ (trừ lớp dò app `io.legado.*`/`io.legato.*`), lỗi JS chỉ vào phần app giả lập, hoặc **đầu dò bộ chọn** thấy trang 2xx có đủ class/id của rule mà rule khớp 0 (thêm điều kiện: rule không có JS sau bộ chọn, khớp 0 chứ không phải lọc hết, thẻ cuối có thật trong phần tử chứa — trang tìm không có kết quả không bị kết luận oan; bước nội dung cần ≥ 50 ký tự chữ).
  4. **Nguồn lỗi thời**: trang 2xx mà không token class/id nào của rule có trong trang, hoặc nguồn thiếu rule.
  5. **Chưa rõ**: còn lại, kèm lý do (404 ở bước sau, máy mất mạng, lỗi JS của chính script nguồn…).
- **Đầu dò bộ chọn** (`LegadoSelectorProbe`, `LegadoRuleSelectorTokens`): khi bước danh sách/nội dung ra rỗng sau trang 2xx, tách token `class.X`/`.X`/`id.X`/`#X`/`tag.X` của rule và kiểm trong **toàn bộ** HTML trang, ghi vào run log.
- **Bằng chứng cho bộ chạy hàng loạt**: `LegadoRunLog.current` (task-local) — `runSession` dùng `log ?? LegadoRunLog.current` (đọc trước khi sang thread engine); bộ chạy bọc **từng bước** của mỗi nguồn. Không đổi chữ ký facade.
- **Báo cáo**: `SourceResult.verdict` + `verdictReason` (tuỳ chọn), báo cáo tổng thêm `byVerdict`; mirror `protocol.ts` (trường tuỳ chọn, không nâng version; `tsc --noEmit` sạch).
- **UI** (khớp mockup): màn Kiểm tra nguồn có ô đếm "Lỗi do ai" (`LegadoSourceCheckVerdictPanel`, chỉ ô > 0), chip lọc theo kết luận (`LegadoSourceCheckFilter`), dòng lỗi "Kết luận · bước · lý do" theo màu kết luận (`LegadoFailureVerdictStyle`), nút **chia sẻ báo cáo** ở toolbar (`LegadoCorpusReportShare` ghi JSON đã redact ra file tạm, `ShareSheet`); màn Gỡ lỗi từng bước có dải "Kết luận: …" (`LegadoFailureVerdictBanner`, nền nhạt — không nền màu nhấn đặc) dùng chung bộ phân xử.
- Chuyển entry `[1.3.544]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới** (kể cả `WHITE_TINT_FILL`); không đụng engine `{JS,Engine,Net,Rule}`. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.578] - 2026-10-22

### fix: chặn tận gốc lỗi nút trắng trên trắng: kiểu nút appFilled và luật WHITE_TINT_FILL

Người dùng: *"Trắng trên trắng tìm cách fix luôn lỗi này đi, tôi thấy thêm nút mới hay bị lắm"*.

- **Nguyên nhân gốc**: `MainTabView` đặt `.tint(.white)` toàn cục ⇒ `Color.accentColor` là **trắng**, `.borderedProminent` không kèm `.tint(…)` là nền trắng; nút mới tô nền bằng màu nhấn rồi đặt chữ trắng là vô hình. Đã gặp ở 1.3.447 (thư viện giọng VieNeu) và 1.3.572 (các màn nguồn Legado, sửa ở 1.3.575). Rà toàn app: hiện không còn chỗ nào dính — mọi `.borderedProminent` đều kèm tint màu.
- **`AppFilledButtonStyle`** (mới, `Views/Common/`): kiểu nút nền đặc chuẩn, chữ trắng trên màu cố định (mặc định xanh), mờ khi nhấn/tắt; `.buttonStyle(.appFilled)`, `.appFilled(.green, fullWidth: false)`. Nút "Mở trang đăng nhập" (`LegadoLoginView`) dùng kiểu này.
- **Luật mới `WHITE_TINT_FILL`** trong `Scripts/check_architecture.py` (quét `Sources/Views/**`, bỏ dòng comment): báo lỗi `.borderedProminent` mà chuỗi modifier của chính nút không có `.tint(<màu khác trắng>)`, và `.background(…Color.accentColor…)` đặc (mờ < 50% thì được; `.background(.tint)` cũng bị bắt). `.fill(Color.accentColor)` cho hình vẽ (thanh tua video) không bị cấm. Thử trên mẫu: bắt đúng 5/5 mẫu sai, không báo nhầm 3 mẫu đúng; trên code thật 0 vi phạm mới.
- **Tài liệu**: `CLAUDE.md` + `AGENTS.md` (bảng luật 5 → 6, ghi chú "màu nhấn của app là trắng"), `rules.md` §5.4 thêm quy tắc kèm ví dụ đúng/sai.
- Chuyển entry `[1.3.543]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.

## [1.3.577] - 2026-10-22

### feat: danh mục tìm nhanh ở Khám phá cho nguồn Legado không có Khám phá

Người dùng: *"các nguồn không khai báo exploreUrl/ruleExplore của legado hãy thêm danh sách các từ tìm kiếm nhanh để người dùng có thể dùng để tìm kiếm nhanh. Tham khảo danh sách của …/wcshuba/src/genre.js"* (kèm báo 69書吧 không có ở Khám phá — nguồn này không khai `exploreUrl`).

- **`LegadoQuickSearch`** (mới, `Services/LegadoSource/Search/`): 70 từ khoá tiếng Trung lấy theo danh mục tìm của tiện ích `wcshuba` (诸天, 聊天群, 万界, 斗罗, 遮天, 凡人, 火影, 柯南…), bỏ các mục phân loại riêng của trang đó; mục "木叶" tìm đúng "木叶" (bản tham khảo trỏ nhầm sang "火影"). Áp cho nguồn **có rule tìm kiếm** mà **không có Khám phá dùng được** (thiếu `exploreUrl`/rule khám phá, hoặc `enabledExplore = false`).
- **Khám phá**: `SearchExtensionScopePolicy.isDiscoverable` nhận thêm nguồn Legado `LegadoSourcePolicy.isQuickSearchable` ⇒ hiện ở bảng chọn nguồn. Tab lưới của nguồn (`LegadoExploreTabView`) hiện các ô từ khoá (4 ô một hàng; tên ô dịch QT khi bật dịch như tên thể loại) — `LegadoSourceRuntime.exploreEntries`/`exploreCategories` trả mục tìm nhanh, không chạy engine.
- **Bấm ô** ⇒ đi đường của mục khám phá (`legadoExploreScriptName`, URL mang tiền tố `legado-quick-search:`); `SourceRuntime.executeCustomScript` nhận ra và chạy **tìm kiếm** của nguồn với từ khoá đó; có trang sau khi trang có kết quả và `searchUrl` có dùng `page` (`PaginatedNovelLoader` vẫn dừng khi trang không thêm mục mới).
- Nguồn có Khám phá riêng giữ nguyên danh mục của nguồn; tiện ích JS không đổi.
- Chuyển entry `[1.3.542]` sang `CHANGELOG.archive.md` để giữ 30 entry.
- **Kiểm chứng**: `check_architecture.py` 2 violation nền, **0 mới**. Không build tại chỗ (Windows) — CI là cổng biên dịch; chưa thử trên máy.
