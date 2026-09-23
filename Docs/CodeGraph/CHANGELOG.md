# CHANGELOG - Nhật ký Thay đổi CodeGraph FreeBook

Tài liệu này ghi nhận lịch sử thay đổi, cập nhật của bộ tài liệu CodeGraph sống (Living Documentation) trong dự án **FreeBook**.

> Chỉ giữ các version gần đây. Lịch sử cũ hơn nằm ở [CHANGELOG.archive.md](CHANGELOG.archive.md).

## [1.3.387] - 2026-09-23

### fix: nang cap chan doan ci va tranh xung dot type trong ai harness

Cải thiện workflow CI và refactor kiểu dữ liệu trong `Sources/Services/AI/`:

- **Đổi tên kiểu AnyCodable (`OpenAITypes.swift`)**:
  - Đổi tên `OpenAIChatRequest.AnyCodable` thành `OpenAIChatAnyCodable` và bổ sung typealias tương thích ngược nhằm phòng tránh xung đột định danh tiềm ẩn.
- **Nâng cấp công cụ chẩn đoán lỗi CI (`.github/workflows/build-ipa.yml`)**:
  - Bổ sung bước đọc trực tiếp `build_error.log` và trích xuất toàn bộ chuỗi thông báo lỗi/note từ các file serialized diagnostics (`.dia`) để hiển thị tường minh nguyên nhân thất bại trên GitHub Actions.


### fix: sua cac loi bien dich trong phan he ai harness

Sửa **4** file Swift trong `Sources/Services/AI/` và `Sources/Views/Reader/Extensions/`.

- **Sửa API nạp tên riêng trong truyện (`AIBookDataInspector.swift`)**:
  - Đọc danh sách từ/tên riêng từ `Names.txt` qua `DictionaryTextFileStore.loadEntries(from: txtUrl)` thay vì gọi `allWords()` không tồn tại trên `TrieDictionary`.
- **Sửa gọi thêm quy tắc lọc rác (`AIHarnessService.swift`)**:
  - Sử dụng `JunkFilterManager.shared.addRule(pattern:)` trên `MainActor` thay vì `addPattern`.
- **Sửa nạp nội dung chương cho Reader AI (`ReaderView+AI.swift`)**:
  - Truy xuất chương đang đọc qua `viewModel?.cache.get(readerPresentedChapterIndex)` thay vì `cachedChapters`.
- **Loại bỏ non-sendable stored property (`AIChatHistoryStore.swift`)**:
  - Dùng trực tiếp `FileManager.default` trong các hàm thay vì lưu trữ thuộc tính `private let fileManager`, tương thích hoàn toàn với chế độ Swift 6.

## [1.3.385] - 2026-09-23

### feat: them che do ai agent harness toan man hinh o reader voi 3 mode ask plan bypass

Thêm **24** file Swift mới và sửa **3** file Swift trong `Sources/Views/Reader/` và `Sources/Views/Settings/`.

- **Màn hình AI Agent Harness toàn màn hình (`ReaderAIFullScreenView.swift`, `ReaderView+AI.swift`)**:
  - Mở dạng `.fullScreenCover` từ nút icon `sparkles` trên Header và Action Menu của Reader.
  - Hỗ trợ streaming SSE phản hồi theo thời gian thực từ bất kỳ endpoint nào tương thích OpenAI API (Gemini, OpenAI, Claude/OpenRouter, DeepSeek, Groq, Ollama, Custom).
  - Tách `ReaderAIFullScreenView+Actions.swift` giữ cả 2 file dưới trần 400 dòng vật lý.
- **3 chế độ Harness ngay trên khung chat (`ReaderAIInputBarView.swift`, `AIHarnessMode.swift`)**:
  - `Manual (Ask)`: Tạo ActionPlan và hỏi người dùng trước khi áp dụng thay đổi vào dữ liệu truyện.
  - `Plan`: Lập kế hoạch chi tiết các bước, người dùng ấn "Duyệt kế hoạch" mới thực thi.
  - `Bypass permissions`: Tự động thực thi ngay lập tức.
  - Menu chuyển đổi mode dạng Pill Menu ngay trên Input Bar, kèm Model Picker Menu tức thì.
- **Quản lý cấu hình & Model trong Cài đặt (`AISettingsView.swift`, `AISettingsStore.swift`)**:
  - Hỗ trợ preset cho các nhà cung cấp phổ biến kèm cấu hình tùy chỉnh endpoint / API key / timeout.
  - Nút "Load danh sách từ API" (`GET /models`) và TextEditor nhập danh sách model thủ công (mỗi model một dòng).
  - `AISettingsSection.swift` giúp `SettingsView.swift` giảm dòng và loại bỏ khỏi baseline vi phạm kiến trúc.
- **Phân tích raw chapter & Trích xuất tên riêng (`AIBookDataInspector.swift`, `AINameExtractionBatchProcessor.swift`)**:
  - Sử dụng văn bản gốc Hán tự (raw text) từ `ChapterStore` / `BookBinManager` để LLM phân tích chính xác tên riêng, nhân vật, địa danh.
  - Quét batch offline các chương đã tải theo lô 5 chương kèm thanh tiến trình và nút Dừng.
  - Thẻ `ReaderAINameReviewCardView` cho phép duyệt, tick chọn, sửa nghĩa và lưu thẳng vào từ điển truyện (`TranslationManager.shared.saveCustomEntry(..., isName: true, bookId:)`), tự động kích hoạt bảo vệ Name riêng trước Rule dịch.
- **Lưu trữ phiên trò chuyện (`AIChatHistoryStore.swift`, `ReaderAISessionListView.swift`)**:
  - Tự động lưu session chat theo từng truyện dưới `Application Support/ai_chats/<sha256(bookId)>.json`.
  - Hỗ trợ New Chat (`+ Mới`), xem danh sách session cũ và xóa từng session hoặc xóa tất cả.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `03_type_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `08_lifecycle.md`, `09_dependency_rules.md`, `10_risk_report.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `14_complexity_report.md`, `rules.md` và `CHANGELOG.md`.

## [1.3.384] - 2026-09-18

### feat: dua rule tranh chap name rieng len thanh chip o trang thai thua

Sửa **2** file Swift trong `Sources/Services/Translation/Engine/`.

- **Thu thập đầy đủ Rule tranh chấp Name riêng vào thanh chip (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`)**:
  - `QuickTranslationRuleMatcher.walkNumeral`: Đếm `run` số tự nhiên (không ngắt sớm tại ký tự Name riêng) để matcher nhận diện được đầy đủ cụm khớp quét qua Name.
  - `QuickTranslationRuleEngine.collectFound`: Khi `hasConflict == true` ở chế độ `includesDisabled: true`, match tranh chấp vẫn được đưa vào `found` và dịch `cursor = match.start + 1` để không bỏ sót các lượt thử hợp lệ tiếp theo (như `start = 3` ngay sau Name riêng).
  - `QuickTranslationRuleDiagnostics.diagnose`: Match tranh chấp Name riêng không được vào `winners`, tự động nhận `status = .lostOverlap` và hiển thị trên thanh chip ở trạng thái tranh chấp thua (chip mờ).
- **Tài liệu CodeGraph**: Cập nhật `07_dataflow.md`, `11_subsystems.md` và `CHANGELOG.md`.

## [1.3.383] - 2026-09-18

### feat: bao ve name rieng truoc rule dich va co dinh nghia rule panel dich

Sửa **4** file Swift trong `Sources/Services/Translation/Engine/`, `Sources/Views/Reader/` và thêm **1** file Swift mới trong `Sources/Services/Translation/Extensions/`.

- **Cố định ô "Nghĩa rule" trong panel Dịch (`ReaderView+DefinitionPanel.swift`)**:
  - `isLoadingRules` chỉ theo dõi `definitionSession.loadingRules` (bỏ `definitionSession.loading`), giữ nguyên nội dung nghĩa rule khi tra từ điển lúc nới/thu token, loại bỏ triệt để hiện tượng chớp giật.
- **Bảo vệ Name riêng trước Rule dịch (`QuickTranslationRuleMatcher.swift`, `QuickTranslationRuleEngine.swift`, `QuickTranslationRuleEngine+NameProtection.swift`, `QuickTranslationRuleDiagnostics.swift`)**:
  - Thêm `scanBookNameOccupiedIndices(text:bookId:)` quét cây Double Array Trie `bookNames` của truyện để tạo bản đồ `bookNameRanges` và tập hợp `bookNameOccupiedIndices`.
  - `QuickTranslationRuleMatcher.walkNumeral`: Coi ranh giới Name riêng là ranh giới số hợp lệ (bỏ qua chặn `guardsLeft` nếu ký tự liền kề thuộc Name riêng), cho phép các token số (`<n>`, `<y>`, `<h>`, `<d>`) khớp độc lập ngay sát cạnh Name riêng (ví dụ `比唐三六个月` -> `唐三` giữ nguyên "Đường Tam", `六个月` khớp "6 tháng" -> "hơn Đường Tam 6 tháng").
  - `ruleMatchConflictsWithBookNames`: Bất kỳ rule nào cắt ngang hoặc nuốt một phần Name riêng đều bị loại trừ khỏi danh sách trúng tuyển trong cả dịch thật lẫn chẩn đoán (`.lostOverlap`).
  - Tách `QuickTranslationRuleEngine+NameProtection.swift` (50 dòng) để `QuickTranslationRuleEngine.swift` giảm về 372 dòng (< 400 dòng trần kiến trúc).
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `07_dataflow.md`, `09_dependency_rules.md`, `11_subsystems.md`, `14_complexity_report.md` và `CHANGELOG.md`.

## [1.3.382] - 2026-09-18

### feat: tu dong cuon va chon token khi bam chip rule trong panel dich

Sửa **2** file Swift trong `Sources/Views/Reader/`.

- **Tự động chọn token của rule (`ReaderDefinitionOverlayView+Rules.swift`)**:
  - Khi người dùng bấm vào chip rule trên thanh chip rule, gán `selectedWordOffset` và `selectedWordLength` theo `trace.sourceRange`, đồng thời gọi `onUpdateEditorFromSelection()`.
  - Tự động bôi chọn các ký tự câu gốc và token tương ứng, đồng thời nạp nghĩa từ điển và gợi ý cho cụm từ khớp với rule.
- **Tự động cuộn đến vị trí token tương ứng (`ReaderDefinitionOverlayView.swift`)**:
  - Bổ sung `@State internal var ruleScrollTrigger: Int = 0` được tăng mỗi lần bấm chip.
  - Cả hàng ký tự gốc (`originalSentenceRowView`) và hàng token dịch (`translatedTokensRowView`) đều lắng nghe `ruleScrollTrigger` để kích hoạt cuộn mượt (animated) về vị trí ký tự / token tương ứng ở tâm màn hình.
- **Tài liệu CodeGraph**: Cập nhật `04_call_graph.md`, `11_subsystems.md` và `CHANGELOG.md`.

## [1.3.381] - 2026-09-18

### fix: cap nhat rule trace khi mo panel dich va loc signal theo truyen

Sửa **5** file Swift trong `Sources/Services/Translation/Engine/`, `Sources/Views/Reader/` và `Sources/Views/Reader/Extensions/`.

- **Cập nhật rule traces khi mở panel Dịch (`ReaderView+RuleTools.swift`, `ReaderView.swift`)**:
  - Gọi `refreshRuleTraces()` trong `openDefinitionPanel()` và trong `.onChange(of: showingDefinitionSheet)` (khi `newValue == true`) để thanh chip rule nạp dữ liệu chẩn đoán của cả đoạn văn ngay khi mở.
- **Chống reload dải chip khi nới/thu token (`ReaderView+DefinitionLoading.swift`, `ReaderView+DefinitionPanel.swift`)**:
  - `refreshDefinitionRules()` chuyển sang kiểm tra theo đoạn văn gốc `originalSentence == text` và `definitionSession.identity == sessionID`, bỏ phụ thuộc vào selection `range`/`word` của `currentDefinitionSnapshot()`.
  - Khi mở rộng / thu hẹp vùng chọn token trong câu, editor chỉ gọi `loadDefinitionData()` để cập nhật nghĩa từ điển, thanh chip rule giữ nguyên trạng thái hiển thị.
- **Phát và lọc sự kiện rule theo truyện (`QuickTranslationRuleBookStore.swift`, `ReaderView.swift`)**:
  - `QuickTranslationRuleBookStore.notifyChange(bookId:)` gọi thêm `TranslationManager.shared.notifyRulesDidUpdate(bookId: bookId)`.
  - `ReaderView` đăng ký nhận `.quickTranslationRulesDidUpdate` và chỉ reload bản dịch / thanh chip rule khi `targetBookId == nil` (rule chung) hoặc `targetBookId == bookId` (rule riêng đang đọc). Bỏ qua hoàn toàn nếu là thay đổi rule riêng của truyện khác.
- **Tài liệu CodeGraph**: Cập nhật `00_index.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `07_dataflow.md`, `11_subsystems.md`, `rules.md` và `CHANGELOG.md`.

## [1.3.380] - 2026-09-17

### fix: khong dung rule trace khi cap nhat name vp

Sửa **1** file Swift trong `Sources/Views/Reader/Extensions/`.

- **Panel Dịch không đụng task rule khi chỉ reload nghĩa/token (`ReaderView+DefinitionLoading.swift`)**:
  - Bỏ `definitionSession.ruleTask?.cancel()` khỏi `loadDefinitionData()`.
  - Khi người dùng cập nhật Name/VP, notification từ điển vẫn reload nghĩa/token qua `loadDefinitionData(preservingMeaning: true)` nhưng không hủy và không lấy lại rule trace của cả đoạn văn.
  - Rule trace vẫn chỉ do luồng rule tự quản: `refreshDefinitionRules()` tự cancel lượt rule cũ khi thật sự cần refresh.
- **Tài liệu CodeGraph**: ghi nhận các doc stale theo validator; không cần cập nhật nội dung mô tả hệ thống.
- Gate: `validate_links.py` và `check_architecture.py` sẽ chạy sau khi ghi nhận doc; host Windows không build Xcode tại chỗ.

## [1.3.379] - 2026-09-17

### fix: tach signal rule khoi signal tu dien trong panel dich

Sửa **11** file Swift trong `Sources/Services/TTS/`, `Sources/Services/Translation/` và `Sources/Views/Reader|Settings/`.

- **Tách kênh event rule khỏi kênh từ điển (`TranslationManager.swift`)**:
  - Thêm `.quickTranslationRulesDidUpdate` và `notifyRulesDidUpdate(bookId:)`.
  - Rule/token/priority change phát rule signal; dictionary change giữ `notifyDictionariesDidUpdate(bookId:scope:)`.
- **Giảm lag panel Dịch (`ReaderView.swift`, `ReaderView+DefinitionLoading.swift`)**:
  - `refreshRuleTraces()` không còn chạy sau mỗi `loadDefinitionData()` hoặc mỗi lần `selectedWordOffset` đổi.
  - Panel re-diagnose rule khi mở, khi `originalSentence` đổi hoặc khi nhận rule signal.
- **Đồng bộ Reader/TTS theo signal mới (`TTSManager.swift`, các store rule/settings)**:
  - `TTSManager` lắng nghe thêm `.quickTranslationRulesDidUpdate` để huỷ prepared chapter, claimed synthesis, next-chapter prefetch/prefix và metadata tĩnh.
  - `QuickTranslationRuleStore`, `QuickTranslationRuleDisableStore`, token settings, priority settings và công tắc áp dụng rule phát rule signal đúng một lần sau khi cache/generation đã invalidated.
  - Sửa lỗi compile đã làm CI fail: `QuickTranslationRuleDisableStore` dùng đúng `TranslateUtils.invalidateCache(bookId:)` thay vì `clearCache(bookId:)`; bỏ notify dư ở CRUD rule.
- **Tài liệu CodeGraph**: cập nhật `00_index.md`, `02_file_graph.md`, `04_call_graph.md`, `05_state_graph.md`, `06_event_graph.md`, `07_dataflow.md`, `08_lifecycle.md`, `11_subsystems.md`, `rules.md` và `CHANGELOG.md`.
- Gate: `validate_links.py` sẽ được chạy lại sau khi accept doc; `check_architecture.py` dự kiến vẫn đỏ bởi baseline legacy, không do lượt này mở luật mới.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`; CI GitHub là nguồn build.

## [1.3.378] - 2026-09-15

### fix: tach cac chu so han liet ke bang dau phay trong rule dich

Sửa **1** file Swift trong `Sources/Services/Translation/Engine/`.

- **Tách các chữ số Hán liệt kê bằng dấu phẩy trong rule dịch (`QuickTranslationNumberFormatter.swift`)**:
  - Gỡ bỏ ràng buộc bắt buộc tăng liền kề đúng 1 đơn vị (`digit == last + 1`) và `parsed <= last` trong hàm `enumeratedNumbers`.
  - Hỗ trợ đầy đủ các chuỗi số Hán trần 2-3 chữ số đứng liền nhau được liệt kê theo thứ tự bất kỳ (bao gồm tăng dần cách quãng như `二四` → `2, 4`, `三五` → `3, 5`, `二四六` → `2, 4, 6`; giảm dần hoặc ngẫu nhiên như `九五二` → `9, 5, 2`, `五三` → `5, 3`, `四二` → `4, 2`).
  - Khắc phục triệt để lỗi `第二四个` bị dịch sai thành "cái thứ 24" nay chuyển thành "cái thứ 2, 4"; `第九五二个` nay chuyển thành "cái thứ 9, 5, 2".
  - Bảo tồn nguyên vẹn các số chính thức có từ chỉ bậc (`二十四` = 24, `九百五十二` = 952, `八千三` = 8300, `一万二` = 12000), số năm/mã số chứa `零`/`〇` (`二零二五` = 2025), và số năm 4 chữ số trần (`一九九八` = 1998) qua guard `runLength >= 4`.
- **Tài liệu CodeGraph**: cập nhật `11_subsystems.md` (`--accept`); `07_dataflow.md` ghi `--no-change-needed`.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (`QuickTranslationNumberFormatter.swift` 342 dòng $\le 400$ dòng); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`.

## [1.3.377] - 2026-09-15

### fix: dieu chinh chieu cao ban dau cua context menu sach va man hinh hen gio tts

Sửa **2** file Swift trong `Sources/Views/Shelf/BookActions/` và `Sources/Views/TTSWidget/`.

- **Điều chỉnh chiều cao ban đầu của Context Menu sách (`BookActionSheet.swift`)**:
  - Nâng `presentationDetents` từ `[.medium, .large]` lên `[.fraction(0.85), .large]`.
  - Giúp sheet mở ban đầu ở mức 85% chiều cao màn hình, hiển thị trọn vẹn toàn bộ các tuỳ chọn hành động ("Đổi nguồn", "Tải truyện", "Xuất ebook", "Dịch lại tên chương", "Bỏ khỏi bộ sưu tập", "Xoá"), khắc phục lỗi chỉ thấy đến "Đổi nguồn" khi mở ở mức `.medium`.
- **Điều chỉnh chiều cao ban đầu của Màn hình Hẹn giờ TTS (`TTSQuickTimerSheet.swift`)**:
  - Nâng `presentationDetents` từ `[.fraction(0.78), .large]` lên `[.fraction(0.88), .large]`.
  - Mở ban đầu ở mức 88% chiều cao màn hình, bổ sung ~85–90 pt không gian, giúp nút "Hẹn giờ 90 phút" và khối card tuỳ chỉnh phía dưới hiển thị trọn vẹn, không còn bị cắt ở góc trên của nút.
- **Tài liệu CodeGraph**: cập nhật `11_subsystems.md` (`--accept`); `03_type_graph.md`, `05_state_graph.md` ghi `--no-change-needed`.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (vẫn đúng 6 vi phạm nền); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`.

## [1.3.376] - 2026-09-13

### fix: bao ton chu hoa thuong trong panel dich va rule, them nut x clear, bat goi y ban phim toan app

Sửa **31** file Swift trong `Sources/Services/Translation/`, `Sources/Views/Reader/`, `Sources/Views/Settings/`, `Sources/Views/Dictionary/`, `Sources/Views/BookDetail/`, `Sources/Views/Search/`, `Sources/Views/Discovery/`, `Sources/Views/Common/`, `Sources/Views/Extensions/`, `Sources/Views/TTSWidget/`.

- **Bảo tồn hoa/thường nghĩa từ điển trong Panel Dịch & Rule Editor (`TranslationTextPostProcessor.swift`, `TranslateUtils.swift`, `TranslateUtils+Tokenization.swift`)**:
  - `TranslationTextPostProcessor.apply(to:capitalizeFirstLetter:)`, `TranslateUtils.postProcessText(_:capitalizeFirstLetter:)`, và `TranslateUtils.performTranslation(_:bookId:applyingQuickTranslationRules:capitalizeFirstLetter:)` hỗ trợ cờ `capitalizeFirstLetter: Bool = true`.
  - Thêm `TranslateUtils.translateTerm(_:bookId:shouldConvertTraditionalToSimplified:)` (đặt trong `TranslateUtils+Tokenization.swift` để giữ `TranslateUtils.swift` nguyên baseline 917 dòng vật lý, tuân thủ `Scripts/check_architecture.py`) với `capitalizeFirstLetter: false`. Tuyệt đối không dùng `.lowercased()` hay ép thường vì sẽ làm hỏng tên riêng / danh từ viết hoa.
  - `ReaderDefinitionWorker.swift`: Gọi `TranslateUtils.translateTerm` cho mode "VP", hiển thị nguyên vẹn chữ hoa/thường của nghĩa từ điển.
  - `ReaderSelectionCoordinator.swift`: Bỏ `.capitalized` trong `hanViet(for:)`, trả về âm Hán-Việt nguyên bản.
- **Thêm nút xoá (x) và cấu hình bàn phím trong màn hình Thêm / Sửa Rule (`QuickTranslationRuleEditorSheet+Editing.swift`, `QuickTranslationRulePatternField.swift`)**:
  - Thêm nút `x` (clear) tròn 28pt cho cả ô Mẫu (`patternSection`) và ô Bản dịch (`replacementSection`).
  - Trong `QuickTranslationRulePatternField.swift`, đặt `view.autocorrectionType = .yes`, `view.spellCheckingType = .yes` và giữ `view.autocapitalizationType = .none` ở cả `makeUIView` và `updateUIView`.
- **Bật thanh gợi ý từ bàn phím (QuickType) toàn bộ ứng dụng (Lựa chọn C)**:
  - Gỡ bỏ `.autocorrectionDisabled()` / `.disableAutocorrection(true)` tại 24 vị trí trong toàn bộ ứng dụng (Tìm kiếm, Từ điển, Thay thế TTS, Lọc rác, Cấu hình TOC...).
  - Giữ nguyên tắt autocorrection cho các ô code/URL đặc thù: `URLBarTextField.swift`, `CodeEditorTextView.swift`, `ReaderTextView.swift`, `ExtensionDebugConsoleView.swift`.
- **Tài liệu CodeGraph**: cập nhật `04_call_graph.md`, `07_dataflow.md`, `11_subsystems.md` (`--accept`); `03_type_graph.md`, `05_state_graph.md`, `12_ownership_graph.md`, `13_resource_lifecycle.md` ghi `--no-change-needed`.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (vẫn đúng 6 vi phạm nền, `DictionaryListView.swift` giảm dòng từ 710 xuống 708); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`.

## [1.3.375] - 2026-09-13

### fix: bo tai lai noi dung khi chi ban dich loi thoi, dat tran cache chuong va noi tran memo rule rewrite

Sửa **4** file Swift trong `Sources/Views/Reader/` và `Sources/Services/Translation/Engine/`.

- **Chuyển chương khi chỉ bản dịch lỗi thời không còn tải lại nội dung (`ReaderViewModel.swift`)**:
  - `loadChapterContentFromExtension` thoát sớm trả `.memory` khi `forceRefresh == false` **và** cache Reader đã có `state == .loaded` với `originalContent` khác rỗng. Tiền đề: khi đó lý do duy nhất phải qua hàm này là token dịch đã đổi (sửa từ điển/rule), còn nội dung chương không đổi — `runNavigationWorker` tự gọi `processAndSaveChapter(originalContent: cached.originalContent)` ngay sau đó.
  - Trước 1.3.375, mỗi lần lật trang sau khi sửa từ điển vẫn tốn thêm một vòng `ChapterContentRepository.load` (DB/extension) chỉ để lấy lại nội dung đã nằm trong RAM.
  - `forceRefresh: true` **không** đi nhánh mới, nên "Cập nhật mục lục" và `reloadDisplayedChapter` giữ nguyên hành vi; `retryPendingNavigation` cũng vậy vì chương lỗi có `state != .loaded`.
- **`ChapterCache` có trần thật, lần đầu được thi hành (`ReaderView.swift`, `ChapterCache.swift`)**:
  - `queueReleaseAllNonVisible` là **code chết** từ trước tới nay (không có caller), nên cache chương chỉ được dọn khi Memory Warning — mà `handleMemoryWarning` chỉ giữ **đúng** chương đang đọc.
  - `ReaderView.applyNavigationCommit` gọi nó sau mỗi commit với cửa sổ **±3** quanh chương vừa tới và ân hạn 5 s (`queueRelease` huỷ hẹn nếu `get()` chạm lại chương đó).
  - `queueRelease` đổi sang `Task { @MainActor }`: `performRelease` gỡ khoá trong `cache` (`@Observable`) nên không được chạy nền. Lỗi này chưa từng lộ vì hàm chưa có caller.
- **Memo rewrite của rule engine từ 64 lên 2048 entry (`QuickTranslationRuleEngine.swift`)**:
  - Pipeline gọi `rewrite` hai lần cho cùng một chuỗi (một lần dịch, một lần dựng span) nên 64 entry **nhỏ hơn một chương** ⇒ memo thrash ngay trong một lượt dựng chương. Trần bộ nhớ thật vẫn là `maxCost` 2 MiB nên nâng `maxEntries` **không** nới bộ nhớ.
- **Tài liệu CodeGraph**: cập nhật vùng GENERATED của `04_call_graph.md`, `05_state_graph.md`, `08_lifecycle.md`, `10_risk_report.md`, `11_subsystems.md`, `13_resource_lifecycle.md`, `rules.md` (`--accept`); `03_type_graph.md`, `07_dataflow.md`, `12_ownership_graph.md` ghi `--no-change-needed`.
  - `05_state_graph.md` chứa một khẳng định **nay đã sai** và đã được sửa: mục 1.3.240 viết "`ChapterCache` thực tế không evict (`queueRelease*` không có caller)" — tiền đề đó không còn đúng từ 1.3.375.
  - **Lưu ý về nợ tài liệu**: 10 doc này đã stale sẵn từ commit `fbbeef1` (phiên trước commit mà không `--accept`); `validate_links.py` khi đó vẫn báo PASS vì công cụ **short-circuit khi cây làm việc sạch**. Lượt này ghi nhận cả 10.
- Gate: `check_architecture.py` không phát sinh vi phạm mới (vẫn đúng 6 vi phạm nền: `ChapterPersistenceStore`, `JSDom`, `JSExecutor`, `TTSManager`, `DictionaryListView`, `ReaderViewModel`); `validate_links.py` PASS 100%.
- **Chưa kiểm chứng biên dịch tại chỗ**: workspace Windows, không chạy được `xcodegen`/`xcodebuild`/Instruments. Mọi số đo hiệu năng phải lấy lại trên máy thật.

## [1.3.374] - 2026-09-13

### feat: tai thiet ke sheet hen gio va muc luc tts, nen xam widget dem nguoc va tab the loai kham pha

Sửa **6** file trong `Sources/Services/TTS/`, `Sources/Views/Reader/`, `Sources/Views/TTSWidget/`, `Sources/Views/Discovery/` và `.github/workflows/build-ipa.yml`.

- **Màn hình Sheet Điều khiển Hẹn giờ & Mục lục TTS (`TTSQuickTimerSheet.swift`)**:
  - Bỏ navigation header "Hẹn giờ tắt" và bỏ card cài đặt giọng đọc ở dưới (truy cập cài đặt qua icon bánh răng ⚙️ trên toolbar).
  - Tích hợp Card thông tin truyện đang phát:
    - Bìa sách: Chạm vào bìa sách tự động đóng sheet và bắn notification `openCurrentlyPlayingReader` để mở Reader tại chương đang phát.
    - Tên truyện: Hiển thị đầy đủ toàn bộ số hàng, kèm badge số chương bên cạnh.
    - Tác giả: Hiển thị icon `person.fill` + tên tác giả (`displayedAuthor`). Nếu rỗng chỉ hiển thị biểu tượng tác giả và để trống text (tuyệt đối không điền "Không rõ").
    - Slot bộ đếm giờ cố định 22pt: Hiển thị badge xám `Color(white: 0.22)` + nút "Hủy" khi có hẹn giờ hoặc text mờ khi không hẹn giờ, giữ layout 100% ổn định không bị nhảy/giật khi bật/tắt hẹn giờ.
  - Hàng tên chương đang phát: Nằm giữa card thông tin và thanh tab con, hiển thị đúng 1 hàng kèm icon `waveform`.
  - 2 Tab con chuẩn 1 hàng ngang với cử chỉ vuốt chuyển tab (`.tabViewStyle(.page(indexDisplayMode: .never))`):
    - Tab 1 ("⏱️ Hẹn giờ tắt"): Lưới chọn nhanh mốc hẹn giờ + bộ tuỳ chỉnh thời gian với slider 1-180 phút.
    - Tab 2 ("📑 Danh sách chương"): Danh sách toàn bộ chương của truyện đang phát, mỗi chương tối đa 2 hàng (`lineLimit(2)`), đánh dấu chương đang phát, tự động cuộn đến chương đang phát, chạm vào chương nào thì chuyển phát ngay chương đó qua `TTSManager.jumpToChapter(at:)`.
  - Thiết lập `.presentationDetents([.fraction(0.78), .large])` giúp mở vừa vặn không thừa đáy.
- **Widget TTS (`TTSFloatingWidgetView.swift`)**:
  - Thêm nền xám `Color(white: 0.22)` cho badge đếm ngược thời gian tạm dừng/hẹn giờ ngủ trên widget capsule.
- **Màn hình Khám phá (`DiscoveryView.swift`)**:
  - Đưa tab Thể loại hình tròn `Circle()` vào bên trong `ScrollView` ngang như tab đầu tiên, cuộn mượt cùng hàng với các tab Home.
- **TTS Core & Reader (`TTSManager.swift`, `TTSManager+Playback.swift`, `ReaderView.swift`)**:
  - `TTSManager`: Thêm `playingAuthor`, public `@Published chaptersQueue`, nhận `author` trong `startSpeaking`.
  - `TTSManager+Playback`: Bổ sung `displayedBookTitle`, `displayedAuthor`, `displayedChapterTitle`, `displayTitle(for:)` (tự động dịch VietPhrase nếu áp dụng) và `jumpToChapter(at:)` với Toast thông báo đã dịch.
  - `ReaderView`: Truyền `author` khi gọi `ttsManager.startSpeaking`.
- **CI Workflow (`build-ipa.yml`)**:
  - Tối ưu bắt log lỗi và thêm filter trigger cho thư mục workflow.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.373] - 2026-09-12

### feat: triet tieu 100% rung vat ly khi boi den va fix loi tu scroll token man hinh dich

Sửa **3** file và cập nhật **1** file trong `Sources/Views/Reader/`.

- **Triệt tiêu 100% rung vật lý Taptic Engine (`SelectionHapticsSilencer.swift`)**:
  - Mở rộng swizzle toàn diện bằng `method_setImplementation`: vô hiệu hóa cả `UIImpactFeedbackGenerator.impactOccurred()`, `UIImpactFeedbackGenerator.impactOccurred(intensity:)`, `UISelectionFeedbackGenerator.selectionChanged()`, `UIFeedbackGenerator.prepare` và các lớp private `_UIFeedbackGenerator` / `_UISelectionFeedbackGenerator`.
  - Triệt tiêu hoàn toàn phản hồi rung vật lý của máy cả khi ấn giữ (long-press) để bắt đầu chọn lẫn khi kéo thanh neo bôi đen text.
- **Tự động scroll đến đúng token đã chọn trong màn hình Dịch (`ReaderDefinitionOverlayView.swift`, `ReaderJunkDeleteOverlayView.swift`)**:
  - Khắc phục triệt để lỗi race condition "lúc cuộn được lúc không": bổ sung `.onChange(of: translationTokens.count)` và `.onChange(of: translationTokens.map(\.id))` để tự động cuộn đến đúng token ngay khi dữ liệu nạp bất đồng bộ hoàn tất.
  - Tích hợp hàm `scrollToSelectedToken(proxy:)` với nhiều mốc retry trong `.onAppear`.
- **Chặn Layout loop trong `AutoSizingTextView` (`ReaderTextView.swift`)**:
  - Chặn `invalidateIntrinsicContentSize()` khi `selectedRange.length > 0`, ngăn việc đo lại kích thước thẻ liên tục gây rung giật hình ảnh khi bôi đen.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.372] - 2026-09-12

### feat: tat rung mac dinh khi boi den, tu dong tat auto-scroll tts va toi uu do muot boi den reader

Sửa **2** file và thêm **1** file Swift mới trong `Sources/Views/Reader/`.

- **Triệt tiêu rung phản hồi xúc giác (Haptic Feedback) (`SelectionHapticsSilencer.swift`, `ReaderTextView.swift`)**:
  - Tạo `SelectionHapticsSilencer` swizzle phương thức `UISelectionFeedbackGenerator.selectionChanged()` thành no-op để chặn hoàn toàn lệnh kích hoạt rung Taptic Engine từ UIKit khi người dùng bôi đen văn bản.
  - Quá trình kéo thanh bôi đen chữ trên iPhone trở nên 100% êm ái, loại bỏ hoàn toàn cảm giác rung giật vật lý của máy.
- **Tối ưu độ mượt bôi đen text (`ReaderTextView.swift`)**:
  - Áp dụng debounce 120 ms cho `textViewDidChangeSelection` khi đang kéo chọn chữ (`length > 0`), cho phép UIKit render kính lúp loupe và các thanh neo ở 60/120fps native mà không bị giật lag do liên tục re-render SwiftUI.
  - Xử lý bỏ chọn tức thì (0 ms delay) khi `length == 0`, tắt Floating Menu ngay lập tức khi chạm ra ngoài.
  - Xóa lệnh dispatch async `UIMenuController.shared.hideMenu()` thừa thãi; tăng ngưỡng chống rung toạ độ `isSamePosition` lên 1.0 pt.
- **Tự động tắt cuộn theo highlight TTS (`ReaderView.swift`)**:
  - Trong `onSelectionChangeInParagraph`, tự động gán `isAutoScrollDisabled = true` khi phát hiện bắt đầu bôi đen (`selectionRange.length > 0`), ngăn TTS tự động cuộn trang tranh chấp với ngón tay người dùng.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.371] - 2026-09-12

### feat: chuyen sheet the loai thanh tab, dong bo mau chip man hinh dich va bo chu chuyen chuong reader

Sửa **4** file và thêm **1** file Swift mới trong `Sources/Views/`.

- **Màn hình Khám phá (`DiscoveryView.swift`, `DiscoveryGenresTabView.swift`)**:
  - Chuyển modal sheet thể loại thành một Tab chính thức (`genresTabId = "__genres__"`) trên thanh tab và vùng nội dung `TabView`, cho phép vuốt chuyển qua lại mượt mà giữa lưới thể loại và các danh mục truyện khác.
  - Nút Thể loại giữ nguyên dạng nút tròn `Circle()` 38x38 với icon `square.grid.2x2` ở đầu hàng tab.
  - Đồng bộ hoàn toàn kiểu dáng màu sắc của các tab không được chọn giống với Kệ sách: nền `Color(.secondarySystemBackground)`, chữ & icon màu `Color.secondary` (trắng nhạt), viền `Color.secondary.opacity(0.25)`.
  - Tách `DiscoveryGenresTabView.swift` giúp file `DiscoveryView.swift` giảm dòng và luôn nằm dưới giới hạn baseline (998 dòng).
- **Điều hướng chương Reader (`ReaderHeaderFooterOverlayView.swift`)**:
  - Bỏ chữ "Chương trước" và "Chương sau", chỉ hiển thị icon mũi tên `chevron.left` và `chevron.right` với vùng chạm rộng 50% mỗi bên màn hình.
- **Màn hình Dịch (`ReaderDefinitionOverlayView.swift`, `ReaderRuleChipStyle.swift`, `ReaderRuleTraceChip.swift`)**:
  - Chip gợi ý từ điển Names: chữ trắng, viền đỏ nhạt.
  - Chip gợi ý từ điển VietPhrase: chữ trắng, viền xanh nhạt.
  - Chip gợi ý phiên âm Hán Việt: giữ nguyên (chữ xám sáng, viền xám mờ).
  - Chip Rule đang áp dụng: chữ trắng in đậm (bold), viền trắng đậm 1.5pt.
  - Chip Rule tranh chấp / thua đè: chữ trắng nhạt, viền trắng nhạt 1.0pt.
  - Chip Rule tắt: chữ xám sáng, viền xám mờ 1.0pt.
  - Khi chip Rule được bấm chọn: chữ trắng đậm (bold), viền trắng đậm 1.6pt.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.370] - 2026-09-12

### feat: cap nhat nut chi tiet truyen xam dam dac, dieu huong chuong 50-50, icon the loai va co dinh chieu cao rule

Sửa **4** file Swift trong `Sources/Views/`.

- **Màn hình Chi tiết truyện (`BookDetailView.swift`)**:
  - Đổi màu nền của 5 nút nổi (`+`, `Đọc ngay / Đọc tiếp`, `Thêm vào kệ / Đã ở kệ`, `Tải truyện`, `Xuất ebook`) sang màu xám đậm đặc `Color(white: 0.22)` không trong suốt, viền trắng `Color.white.opacity(0.35)` và chữ/icon màu trắng nổi bật tương tự các tab được chọn ở màn hình Khám phá.
- **Điều hướng chương Reader (`ReaderHeaderFooterOverlayView.swift`)**:
  - Tái cấu trúc thanh footer điều hướng: mở rộng 2 nút "Chương trước" và "Chương sau" thành 2 nửa 50% chiều rộng thanh (nửa trái `onPrevChapter`, nửa phải `onNextChapter`).
  - Giữ cụm thông tin tiến độ / loading ở giữa nhưng vô hiệu hóa cản trở chạm (`allowsHitTesting(false)`).
  - Thêm hiệu ứng nhấn nảy `ReaderNavPressButtonStyle` (scale 0.96, opacity 0.7, highlight background) kèm phản hồi rung nhẹ `UIImpactFeedbackGenerator(style: .light)`.
- **Màn hình Khám phá (`DiscoveryView.swift`)**:
  - Sửa lỗi không hiển thị icon thể loại: đổi từ `Image(systemName: "shapes")` sang `Image(systemName: "square.grid.2x2")` dạng nút tròn 38x38 kính mờ.
- **Màn hình Dịch (`ReaderDefinitionOverlayView+Rules.swift`)**:
  - Cố định chiều cao hàng nghĩa rule `minHeight: 50, maxHeight: 50` và chuẩn hóa khung thẻ `background(Color.secondary.opacity(0.08)).cornerRadius(8)` cho mọi trạng thái (đang tải, thông báo, hoặc có rule), loại bỏ hiện tượng giật/nhấp nháy thay đổi chiều cao panel khi chuyển token.
- Gate: `check_architecture.py` không phát sinh vi phạm mới; `validate_links.py` PASS 100%.

## [1.3.369] - 2026-09-12

### feat: cap nhat ui dich, icon shapes kham pha, thanh keo trang va nut copy paste rule editor

Sửa **16** file Swift trong `Sources/Views/`.

- **Màn hình Dịch (Reader Definition)**:
  - Token được chọn: chữ trắng in đậm, có gạch chân (`.underline(true)`), các ký tự không chọn màu trắng nhạt `Color.white.opacity(0.45)`.
  - Hàng nhập nghĩa: cố định 2 dòng (`lineLimit(2, reservesSpace: true)`), chặn phím Enter và tự động lọc bỏ ký tự xuống dòng `\n`, `\r` khi gõ và dán.
  - Đổi màu biểu tượng ghim `pin.fill` sang màu trắng `.white`.
  - Icon nút Dán là `Image(systemName: "doc.on.clipboard")`.
  - Nút thêm rule: đổi icon sang `plus.circle` màu trắng trên nền kính mờ `Color.white.opacity(0.12)`.
- **Màn hình Khám Phá (Discovery)**:
  - Nút thể loại: đổi icon sang `Image(systemName: "shapes")` (tam giác, vuông, tròn) và đổi kiểu nút thành nút tròn `Circle()` kích thước 38x38 với viền kính mờ.
- **Cài đặt TTS & Thanh kéo Sliders**:
  - Thêm `.tint(.white)` cho `TTSSettingsSheet`, `TTSSettingsView`, `TTSModelManagerView`, `NghiTTSSettingsView`, `TTSDictionaryEditView`, `NghiTTSTextToolView`, `TaskOptionsSheet`, `QuickTranslationRuleTokenLengthBar`, `StaleBookCleanupSettingsView`.
  - Đổi toàn bộ các nút back `<`, nút Xong, các giá trị lựa chọn trong menu Picker, icon điều hướng và thanh kéo Slider trên toàn app sang màu trắng sáng tinh tế.
- **Màn hình Thêm/Sửa Rule**:
  - `QuickTranslationRulePatternField`: Chặn ký tự xuống dòng `\n`, tự động ẩn bàn phím khi bấm Return, bật gợi ý từ (`autocorrectionType = .default`, `spellCheckingType = .default`).
  - Bổ sung cụm nút Sao chép (`doc.on.doc`) và Dán (`doc.on.clipboard`) cạnh ô nhập Mẫu và ô nhập Bản dịch.
- Gate: `check_architecture.py` không phát sinh lỗi mới (tất cả file mới/sửa đều ≤ 400 dòng hoặc dưới baseline); `validate_links.py` PASS 100%.

## [1.3.368] - 2026-09-12

### fix: sua loi scope onRulesChanged trong TOCRulesConfigView

Sửa **1** file Swift: `TOCRulesConfigView.swift`.

- Khôi phục hàm gọi `onRulesChanged(updated)` trong closure toggle của hàng quy tắc TOC, sửa lỗi biên dịch `cannot find 'saveRules' in scope`.
- Gate: `check_architecture.py` không phát sinh lỗi mới; `validate_links.py` PASS 100%.

## [1.3.367] - 2026-09-12

### feat: sua loi nut primary sang frosted pill, doi cong tac gat sang xam dam va chuan hoa cai dat tts

Sửa **41** file Swift trong Views và Models.

- Thay thế toàn bộ các nút `.borderedProminent` và nút bấm primary bị lỗi nền trắng chữ trắng sang phong cách Frosted Glass Pill Dark Mode (`Color.white.opacity(0.18)` fill + viền `Color.white.opacity(0.35)` + chữ `.white`).
- Đổi màu toàn bộ công tắc gạt (`Toggle`) sang màu xám đậm `Color(white: 0.35)` khi bật ở root `MainTabView` và tất cả các form / sheet cài đặt / reader / download, giúp nút tròn trắng nổi bật rõ ràng trên nền tối.
- Chuẩn hoá toàn bộ các màn hình Cài đặt TTS, Quản lý Model, Từ điển phiên âm, Thay thế ký tự, Cấu hình quy tắc dịch nhanh sang tone trắng và frosted glass.
- Gate: `check_architecture.py` không phát sinh lỗi mới; `validate_links.py` PASS 100%.

## [1.3.366] - 2026-09-12

### feat: cap nhat giao dien dark mode frosted pill, bo kiem tra chuong moi o context menu va tu dong dich lai muc luc o reader

Sửa **37** file Swift trong Views/Models/Services.

- Chuyển đổi toàn bộ màu chữ, icon và nút bấm màu xanh (primary) / cam trên toàn bộ ứng dụng sang tông màu trắng `.white` và phong cách pill kính mờ Dark Mode (`Color.white.opacity(0.12...0.18)` kèm viền `Color.white.opacity(0.25...0.35)`).
- Loại bỏ tuỳ chọn "Kiểm tra chương mới" trong menu thao tác khi nhấn giữ truyện (`BookActionSheet.swift`).
- Thêm cơ chế tự động dịch lại mục lục khi bật/tắt chế độ dịch ở Reader (`ReaderView.swift`).
- Chuyển toàn bộ các thành phần màu cam trên màn hình hẹn giờ TTS (`TTSQuickTimerSheet.swift`, `TTSFloatingWidgetView.swift`) sang phong cách kính mờ trắng trong suốt thanh lịch.
- Gate: `check_architecture.py` giữ 6 violation line-limit nền, không có violation mới; `validate_links.py` PASS 100%.

## [1.3.365] - 2026-09-12

### Xoá bỏ hoàn toàn chế độ E-Ink và khôi phục giao diện CardView nguyên bản

Xoá **7** file Swift, sửa các file View/Services/Common liên quan.

- Xoá bỏ hoàn toàn 7 tệp chuyên trách E-Ink (`View+EInk.swift`, `EInkModeSettings.swift`, `EInkRefreshOverlay.swift`, `EInkPalette.swift`, `EInkAppearance.swift`, `ReaderTheme+EInk.swift`, `EInkSettingsSection.swift`) và tất cả các tham chiếu E-Ink (`isEInkEnabled`, `paperColorRaw`, các hàm mở rộng `.eink*`) trên toàn bộ ứng dụng.
- Khôi phục tất cả CardView, RowView, Sheet, Badge và Chip về giao diện tiêu chuẩn (màu sắc, bo góc, nền chuẩn và drop shadow).
- Giữ lại các cải tiến độc lập hợp lệ: nút sửa thông tin trên header `BookActionSheet.swift`, đồng bộ selection `SelectionSnapshot` trong `ReaderDefinitionSession.swift`, và cố định chiều cao hàng trong `ReaderDefinitionOverlayView.swift`.
- Gate: `check_architecture.py` giữ 6 violation line-limit nền, không có violation mới; `validate_links.py` PASS 100%.

## [1.3.364] - 2026-09-12

### Hoàn thiện theme E-Ink 2 tầng nền, 4 preset giấy, sắc xám ngữ nghĩa và đơn sắc hoá icon

Sửa **56** file Swift, không thêm/xoá file.

- Áp dụng triệt để phân cấp 2 tầng nền E-Ink (`paperCanvas` cho nền toàn màn hình/khung nhìn và `paperCard` cho các card, list row, form row, popup, sheet) trên toàn bộ ứng dụng qua `einkListRowBackground()` và `einkBackground()`.
- Cung cấp 4 preset nền giấy E-Ink chuyên dụng (`kindlePaperwhite`, `koboComfortLight`, `pureBalanced`, `pureDeep` [mặc định]).
- Phân biệt sắc xám ngữ nghĩa (`grayDark`, `grayMedium`, `grayLight`) kết hợp nét đứt/liền cho chip từ điển, gợi ý phiên âm TTS, token quy tắc và trạng thái.
- Đơn sắc hoá 100% icon, badge, nút bấm và cover vinyl TTS widget khi bật E-Ink.
- Menu giữ truyện (`BookActionSheet`): Căn chỉnh icon thông tin (32x32), đưa nút sửa thông tin lên header, xoá hàng sửa thông tin ở danh sách, đơn sắc hoá các icon.
- Gate: `check_architecture.py` chỉ có 5 violation line-limit nền, không có violation mới; `validate_links.py` PASS 100%.

## [1.3.363] - 2026-09-12

### Cố định độ cao panel dịch và áp dụng nền E-Ink cho các màn hình

Sửa **28** file Swift, không thêm/xoá file.

- Cố định độ cao từng thành phần trong panel dịch (`ReaderDefinitionOverlayView` & `ReaderDefinitionOverlayView+Rules`), loại bỏ khoảng trống thừa phía dưới và chống giật nhảy khi nạp dữ liệu.
- Áp dụng nền giấy E-Ink theo cấu hình (`paperColor`) cho toàn bộ các màn hình Kệ sách, Chi tiết truyện, Khám phá, Tìm kiếm, Kho tiện ích và Cài đặt.
- Gate: `check_architecture.py` giữ đúng 6 violation line-limit nền, không có violation mới; `validate_links.py` PASS 100%.

## [1.3.362] - 2026-09-12

### Ổn định panel Dịch và hoàn thiện nền E-Ink

Sửa **34** file Swift, không thêm/xoá file.

- Panel Dịch dùng `SelectionSnapshot` trong `ReaderDefinitionSession` để chặn kết quả cũ ghi lên selection mới; request mới không xoá trắng nghĩa/chip/token đang hiển thị trước khi kết quả thắng quay về.
- Nút `Cập nhật` chỉ bật khi dữ liệu hiển thị còn khớp selection hiện tại; `saveDefinition()` cũng guard cùng điều kiện để tránh lưu nghĩa vào sai key VP/Names.
- Custom overlay của panel Dịch tự clamp chiều cao theo `GeometryProxy`, giữ header cố định và đưa body vào `ScrollView`; bỏ `.presentationDetents` vì overlay không phải sheet.
- Chuẩn hoá thêm surface E-Ink trong các màn Views còn sót: browser chrome, discovery/search/shelf/download, editor chrome, TOC, TTS widget và các overlay Reader dùng nền giấy reactive qua `@AppStorage(EInkModeSettings.Key.paperColor)` hoặc helper `eink*`.
- Gate: `git diff --check` chỉ còn cảnh báo CRLF của Windows; `check_architecture.py` giữ đúng **6 violation** line-limit nền, không có violation mới. Host Windows không có Swift/Xcode nên chưa compile local. Không dùng `Tests/`.

## [1.3.361] - 2026-09-12

### Sửa nền E-Ink toàn app và cập nhật bar đang mở

Sửa **6** file Swift, không thêm/xoá file.

- `AppLaunchRootView` phủ nền giấy ở root khi bật E-Ink, ẩn `scrollContentBackground`, ép giao diện sáng như trước và gọi lại `EInkAppearance.apply()` khi `isEnabled` hoặc `paperColor` đổi.
- `EInkAppearance.apply()` chuyển toàn bộ thao tác UIKit về main thread, dựng cấu hình mặc định/E-Ink, cài proxy cho bar dựng sau và quét window hiện có để cập nhật `UINavigationBar`/`UITabBar` đang mở ngay.
- `EInkPalette` thêm helper `paperColor(for:)`/`paperUIColor(for:)`; `View+EInk` đọc `paperColor` qua `@AppStorage`, thêm `einkBackground(_:)`, và dùng màu giấy reactive cho surface/tag/selection.
- Gate: `git diff --check` sạch; `check_architecture.py` vẫn có **6 violation** line-limit nền, không nằm trong file sửa. Host Windows không có Swift/Xcode nên chưa compile local. Không dùng `Tests/`.

## [1.3.360] - 2026-09-12

### Sửa lỗi biên dịch UI E-Ink còn sót

Sửa **2** file Swift, không thêm/xoá file.

- `ReaderDefinitionOverlayView.isEInkEnabled` bỏ `private` để `ReaderDefinitionOverlayView+Rules.swift` cùng type nhưng khác file truy cập được. Đây là sửa phạm vi truy cập, không đổi state hay luồng hiển thị.
- `TTSQuickTimerSheet.presetButton(...)` thêm `return` sau các biến local để Swift suy ra đúng opaque return type `some View`.
- Gate: `check_architecture.py` vẫn có **6 violation** line-limit nền, không nằm trong hai file sửa. Host Windows không có Swift/Xcode nên chưa compile local; lỗi gốc lấy từ CI macOS. Không dùng `Tests/`.

## [1.3.359] - 2026-09-11

### Sửa UI còn màu sang kiểu E-Ink và thêm tuỳ chọn màu nền

Sửa **12** file Swift, không thêm file mới (mọi file đã sửa đều ≤ 400 dòng, đúng 1 type top level).

- **Tuỳ chọn màu nền E-Ink**: thêm `EInkPaperColor` (White #F2F1EC / Gray #D8D8D2 mặc định / Warm #E5DED0) lồng trong `EInkModeSettings` — tầng `Services` cấm SwiftUI nên enum chỉ mang `Int` + nhãn, việc đổi sang `Color`/`UIColor` nằm ở `EInkPalette`. `EInkPalette.paper`/`paperUIColor` đổi từ hằng sang `var` tính toán từ `EInkModeSettings.shared.paperColor`, nên mọi bề mặt (panel trình đọc, badge, tab, nav/tab bar qua `EInkAppearance`, FlashView làm mới) nhận màu mới ngay khi đổi; `setPaperColor` gọi `EInkAppearance.apply()`. `EInkSettingsSection` thêm `Picker` phân đoạn ba tông, mặc định Gray.
- **Sửa chỗ UI còn màu**: `BookListItemView` ("Đang đọc" xanh) và `ShelfView` (tiêu đề "Đang ghim" cam + badge số) → `einkAccentForeground`/viền đen; `BookActionSheet` (nhãn ghim cam, nút xoá khỏi kệ đỏ, bỏ khỏi bộ sưu tập đỏ, hàng Xoá destructive, icon accent) → mực đen khi bật; `ReaderDefinitionOverlayView` + `ReaderDefinitionOverlayView+Rules` (mũi tên xanh, chữ chọn xanh, notice cam, chip gợi ý 3 màu, nút + rule xanh) và `ReaderRuleTraceChip` (chip tối → nền giấy + viền đen) → đen/đảo ngược/viền; `ReaderJunkDeleteOverlayView` (mũi tên đỏ, chữ chọn đỏ, nút Xác nhận đỏ) → đen/đảo ngược; `FloatingSelectionMenu` ("Xoá" đỏ trên bong bóng tối) → trắng + gạch chân nét đứt; `TTSQuickTimerSheet` (cam: thanh/chấm ±/nút, xanh: gear, slider tint) → đen/đảo ngược/viền.
- **Quy ước tái sử dụng**: mọi accent gọi `.einkAccentForeground(fallback)` (tự đọc `@AppStorage`) để thành mực đen; chỗ cần nền đổi sang `EInkPalette.paper` + `strokeBorder(EInkPalette.ink)`. Vùng chọn/chữ đang chọn giữ nguyên tắc "đảo ngược = đang chọn" (nền đen, chữ trắng).
- Gate: `check_architecture.py` giữ đúng **6 violation** line-limit nền, **không** có violation mới (không file nào vượt baseline). `validate_links.py` PASS 16 doc. Host Windows không có Swift/Xcode nên **chưa compile**; cần `xcodegen generate` + build trên macOS. Không dùng `Tests/`.

## [1.3.358] - 2026-09-11

### Sửa lỗi biên dịch chế độ E-Ink

Sửa hai lỗi Swift compiler được CI phát hiện sau khi thêm chế độ E-Ink.

- `ExtensionSelectorView` tự quan sát khoá E-Ink bằng `@AppStorage`, thay vì tham chiếu nhầm `isEInkEnabled` chỉ tồn tại trong `DiscoveryView`.
- `EInkEffect.Selection` và `einkSelection` ràng buộc shape bằng `InsettableShape`, đúng yêu cầu của API `strokeBorder` đang được gọi trong modifier.
- Gate kiến trúc trước sửa có 6 violation line-limit nền. Host Windows không có Swift/Xcode nên việc biên dịch được xác minh bằng CI macOS sau khi push. Không dùng `Tests/`.

## [1.3.357] - 2026-09-11

### Thêm chế độ E-Ink cho trình đọc và thiết lập trong Cài đặt

Thêm **7** file Swift, sửa **40** file Swift trên toàn bộ 5 tầng (`App`, `Common`, `Models`, `Services`, `Views`). Mọi quyết định "đang bật e-ink" chạy qua chính sách render (chỉ đen/trắng, viền thay bóng, đảo ngược thay tô màu nhạt, bỏ hiệu ứng nền mờ) chứ không phải "thêm theme màu".

- `EInkModeSettings` (singleton `ObservableObject`) là nguồn sự thật duy nhất: `isEnabled` + 4 công tắc phụ (`monochromeCovers`, `hideCovers`, `instantChapterTurn`, `showsRefreshButton`); khoá `UserDefaults` công khai để `View+EInk` bind `@AppStorage` **cùng khoá**, nhờ đó mọi màn tự cập nhật khi đổi chế độ mà không observe singleton ở từng chỗ.
- `View+EInk.swift` gom toàn bộ logic e-ink vào một `ViewModifier` (`einkOutline`, `einkShadow`, `einkSurface`, `einkMonochrome`, `einkRule`, `einkAccentForeground`, `einkTag`, `einkSelection`): đảo ngược thay tint, dashed = cảnh báo, grayscale + contrast cho ảnh.
- `EInkAppearance.apply()` đẩy nav/tab bar sang nền trắng đục + kẻ đen 1px (appearance proxy UIKit **không retroactive** nên gọi lại khi đổi chế độ); `EInkPalette` cung cấp `paper`/`ink` + độ rộng viền. `FreeBookApp.init()` và `AppLaunchRootView` áp màu sắc + `.preferredColorScheme(.light)` khi bật.
- Reader: thêm case `.eink` vào `ReaderTheme` (loại khỏi `allCases` để Picker không hiện), `panelBackground()`/`scrimColor`/`effective(theme)` giữ nguyên 11 component dùng `selectedTheme` không đổi một dòng; `instantChapterTurn` chặn animation lật chương; `EInkRefreshOverlay.flash()` phủ cửa sổ đen→trắng xoá ghosting, gọi từ nút "Làm mới màn hình ngay" (chỉ hiện khi `showsRefreshButton`).
- Editor (option C, §4b.5): chỉ đổi nền editor sang trắng khi bật e-ink, **giữ nguyên 7 màu syntax** Dark+ (nợ option-B — màn e-ink phải dither 7 màu, chữ có thể khó đọc trên nền sáng; ghi nợ đợt sau).
- Settings: `EInkSettingsSection` mount bằng **đúng 1 dòng** trong `SettingsView.swift` (vẫn 453 dòng, không vượt ngân sách), công tắc chính + 4 công tắc phụ + nút làm mới, ghi qua singleton để cả luồng đọc singleton (`ReaderViewModel`, `ReaderView`) và `@AppStorage` (`BookCoverView`, `ExtensionIconView`) đồng bộ.
- Gate: `check_architecture.py` giữ **6** violation line-limit nền, không có violation mới; `validate_links.py` PASS 16 doc. Host Windows không có Swift/Xcode nên **chưa compile**; có 7 file Swift mới nên cần `xcodegen generate` + build trên macOS. Không dùng `Tests/`.

## [1.3.356] - 2026-09-11

### Thêm nút dọn dẹp toàn bộ bản sao lưu trong máy và xoá bản local sau khi upload thành công

Thêm **1** file Swift, sửa **3** file Swift trong phân hệ Backup và màn Sao lưu.

- `LocalBackupStore.deleteAll()` xoá mọi file `.fbbackup` trong `backups/`, duyệt từng archive thay vì xoá cả thư mục (thư mục còn chứa file tạm của worker đang chạy). Lỗi một phần vẫn tiếp tục rồi mới ném `Failure.deleteAllPartial(deleted:failed:)`.
- `LocalBackupListView` thêm hàng "Xoá tất cả bản sao lưu trong máy" (role destructive) kèm hộp thoại xác nhận nêu rõ số bản sẽ xoá và việc bản trên Google Drive / Telegram không bị ảnh hưởng; gộp hai luồng xoá vào một enum `DeleteTarget`.
- **`uploadToDrive` / `uploadToTelegram` xoá bản trong máy sau khi đích tự xác nhận thành công** (`removeLocalCopyAfterUpload`). Chỉ chạy ở nhánh thành công; xoá hỏng thì `lastMessage` nói rõ "(chưa xoá được bản trong máy)" thay vì im lặng. Hệ quả: một archive chỉ gửi được cho một đích ở đường bấm tay — muốn lên cả Drive lẫn Telegram thì dùng lượt tự động.
- Cố ý **không** lọc tiền tố `freebook-auto-` ở `deleteAll()`: hàng rào đó dành cho phép dọn **ngầm**, còn đây là hành động người dùng đã xác nhận.
- **Tách `BackupCoordinator+LocalCleanup.swift` (50 dòng)** thay vì nhồi vào coordinator: `BackupCoordinator.swift` từng chạm **402**/400 và sinh `NEW_FILE_TOO_LARGE` — đã tách extension chứ không nới baseline hay thêm entry allowlist. Coordinator về **361** dòng.
- Gate: `check_architecture.py` về đúng **6** violation line-limit nền, không có violation mới. Host Windows không có Swift/Xcode nên **chưa compile**; có file Swift mới nên cần `xcodegen generate` + build trên macOS. Không dùng `Tests/`.

## [1.3.355] - 2026-09-11

### Thêm sao lưu Telegram, chia file lớn và lịch tự động đa đích

Thêm **6** file Swift, sửa **8** file Swift trong phân hệ Backup và UI cài đặt.

- Bot Token lưu bằng Keychain, có file bảo vệ làm đường lùi cho LiveContainer; Chat ID ở UserDefaults. Màn cấu hình gọi `getMe` + `getChat`, không gửi tin nhắn khi kiểm tra.
- Backup tối đa 49 MiB gửi một document. File lớn hơn chia streaming thành part, ghi SHA-256 từng part/toàn file, gửi manifest cuối; khôi phục chọn manifest + đủ part và xác minh toàn bộ trước khi nhập.
- Backup local có action gửi Telegram; màn hub có tạo-và-gửi. Import Files hỗ trợ nhiều file và giữ security-scoped access suốt lượt ghép/copy.
- Lịch tự động dùng chung scopes/cooldown, export một archive rồi gửi độc lập tới Drive/Telegram đã bật. Một đích lỗi không huỷ đích kia; chỉ dọn Drive khi upload Drive thành công.
- Gate: `check_architecture.py` giữ **6** violation line-limit nền, không có violation mới; `git diff --check` sạch. Host Windows không có Swift/Xcode nên chưa compile hay gửi Telegram thật; thêm file Swift nên cần `xcodegen generate` + build trên macOS. Không dùng `Tests/`.

## [1.3.354] - 2026-09-11

### Tuần tự hoá cập nhật từ điển, snapshot dịch và loại cache Reader/TTS cũ

Thêm **14** file Swift, sửa translation core, Reader, TTS và panel quản lý VP/rule.

- Mỗi lượt dịch dùng một snapshot bất biến (`TranslationReadContext` + `FrozenTrieDictionary`); custom VP/Names runtime ghi tuần tự qua actor writer và chỉ notify sau persist/publish.
- Cache dịch/token/rule có ngân sách LRU + epoch chống task cũ chèn lại. Lookup và so độ dài được thống nhất theo UTF-16.
- Panel Dịch mở ngay, tokenize/tra nghĩa/chẩn đoán chạy nền có cancellation + request identity. Copy panel không còn làm phần tra nghĩa/rule không cần thiết.
- Reader gom refresh 500 ms, hoãn apply khi selection/overlay mở, chỉ giữ kết quả latest-wins; chương cache tiếp theo bị hạ token để không dùng bản dịch cũ.
- TTS gắn translation token vào prepared/next key và DTO, huỷ prepared/claimed/prefix/audio cũ khi từ điển đổi, stale DTO xử lý lại **cùng chương**.
- Sửa rule giữ đúng ngữ nghĩa đổi mẫu = thêm mẫu mới, giữ mẫu cũ; restore tombstone cũng đi qua writer.
- Gate: `check_architecture.py` **7 → 6** violation (TranslateUtils về baseline; 6 lỗi line-limit nền còn lại). Host Windows không có Swift/Xcode nên chưa compile; có file mới nên cần `xcodegen generate` và build trên macOS. Không dùng `Tests/`.

## [1.3.353] - 2026-09-10

### Đặt badge số chương lên tab Mục lục, dùng số đếm chung với danh sách chương

Thay thế badge số chương mới (từ `NewChapterInboxManager`) bằng badge hiển thị **tổng số chương** của truyện — cùng số xuất hiện ở dòng "Danh sách chương (N)".

- **Badge trên tab "Mục lục"** hiển thị tổng số chương (`totalChaptersCount`), phản ánh ngay khi dữ liệu mục lục cập nhật; **`N = 0` thì ẩn badge**. Số liệu dùng chung computed property với `tocTab` và `floatingActionButton` (cùng logic: `chapterSnapshots.count` → `localBook?.chapters.count` → `onlineChapters.count`).
- **Xóa tích hợp `NewChapterInboxManager`** khỏi `BookDetailView`: bỏ `@ObservedObject`, computed `newChapterBadgeCount` và lượt `newChapters.check(target:)` trong `.onAppear`. Hệ thống kiểm tra chương mới tiếp tục chạy trên `ShelfView`; badge ở đây chỉ là tổng số chương của mục lục.
- `customTabBar` đã được rút sang `BookDetailView+TabBar.swift` ở phiên bản trước; badge dùng `totalChaptersCount` và hiển thị đầy đủ số (không giới hạn `99+`).
- **Badge đặt ngay bên cạnh chữ "Mục lục"** trong `customTabBar` thông qua `HStack`; bỏ `ZStack` + `offset(x:10, y:-10)` trước đó gây lệch ra mép.
- Gate: `check_architecture.py` **7 → 7** violation (không vi phạm mới). `validate_links.py` PASS 16 doc, 503 file. **Chưa biên dịch** vì host Windows; `xcodegen generate` khi lên macOS.

## [1.3.351] - 2026-09-10

### Bật lại cuộn TTS từ widget, gắn badge debug và chạy script trong editor

Sửa **14** file Swift và cập nhật **10** doc CodeGraph.

- **Bấm widget TTS để nhảy về highlight nay bật lại cuộn theo highlight.** `ReaderView` xử lý `navigateReaderToPlayingChapter` bằng cách gọi `reenableTTSAutoScrollFromWidgetJump()` trước khi đổi chương/cuộn. Cờ chỉ đổi trong phiên Reader hiện tại, không ghi `UserDefaults`.
- **Extension import zip/debug server có badge `debug`.** `Extension.installOrigin` là field additive có default `repository`; import zip ghi `importZip`, debug server ghi `debugServer`, cài/cập nhật từ kho ghi lại `repository`. Hàng cũ vẫn được nhận diện bằng fallback `repository == nil && downloadUrl.isEmpty && localPath != ""`.
- **Script Editor có nút Run cho file JS có `execute(...)`.** Editor dùng `ExtensionDebugScriptScanner.containsExecute(in:)`, lưu file bẩn trước khi chạy, map file đang mở về entrypoint chuẩn hoặc custom, rồi mở `ExtensionDebugConsoleView` seed sẵn extension/script. Việc chạy JS vẫn qua `ExtensionDebugRunner`, không thêm executor riêng.
- Gate: `check_architecture.py` vẫn FAIL với **7** violation line-limit nền, cùng tập file không liên quan. `validate_links.py --explain` yêu cầu ghi nhận 10 doc đã cập nhật. **Chưa biên dịch** vì host Windows; không thêm/xoá/đổi tên file Swift nên không cần `xcodegen generate`.

## [1.3.350] - 2026-09-09

### Đổi bước hẹn giờ TTS thành 1 phút

Sửa **1** file Swift và cập nhật **1** doc CodeGraph.

- **Tuỳ chỉnh thời gian trong màn hình Hẹn giờ tắt mịn hơn.** Hai nút `+/-` của `TTSQuickTimerSheet` đổi từ nhảy 5 phút sang 1 phút, và thanh trượt đổi từ `5...180, step: 5` sang `1...180, step: 1`.
- **Preset nhanh giữ nguyên** (`15`, `30`, `45`, `60`, `90`, `Hết chương`); thay đổi chỉ áp dụng cho vùng tuỳ chỉnh số phút.
- Gate: `validate_links.py` PASS sau khi ghi nhận doc stale. `check_architecture.py` vẫn FAIL với **7** violation line-limit nền, cùng tập file không liên quan. **Chưa biên dịch** vì host Windows; không thêm/xoá/đổi tên file Swift nên không cần `xcodegen generate`.

## [1.3.349] - 2026-09-05

### Cài từ debug không cần bấm xác nhận, mặc định bật

Sửa **4** file Swift.

- **`draft.install` và `draft.rollback` chạy ngay, không hỏi gì.** `ExtensionDebugInstallGate.requestApproval` trả `.approved` lập tức khi `isAutoApproveEnabled` và **không** đặt `pending`, nên màn Debug server không hiện hộp xác nhận nào. Mặc định là **bật**, tức hành vi mới là hành vi ngay sau khi cập nhật.
- **Đánh đổi, ghi ra để không ai phải đoán**: server **không có ghép nối** (bỏ từ 1.3.305), nên trong lúc nó bật, bất kỳ máy nào tới được cổng đó đều ghi được extension vào thư viện — tức chạy được JavaScript tuỳ ý trong app. Cửa bấm tay vốn là chốt duy nhất còn lại trên đường ghi; nay chốt đó mở sẵn. Hai thứ bù lại: công tắc **"Không cần bấm xác nhận"** ở màn Debug server tắt được để quay về đường bấm tay, và **mỗi** lần cho phép tự động đều ghi `app_logs.txt` (`⚠️ [ExtDebug] Tự động cho phép…`) để truy lại được về sau. Chốt thực tế còn lại là tắt server khi không dùng.
- **Không xoá `ExtensionDebugInstallGate`.** Toàn bộ `pending`/`waiters`/`pendingStream` và phần UI hiện trước danh sách file sẽ đổi giữ nguyên, vẫn chạy khi công tắc tắt. Xoá đi là mất đường lùi và mất luôn màn diff.
- **Khoá đọc bằng `object(forKey:)` chứ không `bool(forKey:)`**: phải phân biệt "chưa đặt" (⇒ `true`, hành vi mặc định mới) với "đã đặt `false`" (⇒ người dùng chủ động bật lại cửa bấm). Khoá `extDebugAutoApproveInstall` bắt đầu bằng chữ thường nên `BackupSettingsArchiver` tự sao lưu.
- **Ba chú thích khẳng định "phải bấm trên thiết bị" đã sửa** ở `ExtensionDebugCommandRouter`, `ExtensionDebugCommandRouter+Draft` và header của chính gate. Chú thích nói sai về một chốt an toàn là loại nợ tệ nhất trong phân hệ này.
- **Kèm theo, đo trên máy hai thứ của 1.3.348** (không cần bấm gì): `extensions.list` trả `executableScripts` cho **26/26** extension, và `ttkan.co` khai 6 script trong `plugin.json` nhưng có **10** file chạy được — `comment.js`, `gen.js`, `gen2.js`, `recommend.js` trước đây client không liệt kê được. Chạy thử `qidian/src/chap.js` qua đường `custom`: `runStarted → fetchFailed → console → responseValidated → runFinished`. Chốt an toàn của rollback cũng đúng: `draft.rollback` trên `qidian` (extension người dùng tự cài) trả `DRAFT_MISSING` với câu "…không do debug cài mới trong phiên hiện tại".
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `ExtensionDebugInstallGate` 134 → **157**/400, `ExtensionDebugServerView` 152 → **166**/400. `validate_links.py` PASS. **Chưa biên dịch** (host Windows); không thêm file Swift nên không cần `xcodegen generate`. **Chưa kiểm chạy**: máy đang ở 1.3.348 nên `draft.install`/`draft.rollback` vẫn đòi bấm; cài IPA mới thì cả chuỗi cài mới → rollback chạy được không cần tay, và đó cũng là lúc kiểm luôn bản sửa rollback của 1.3.348 (hiện vẫn chưa được đo).

## [1.3.348] - 2026-09-05

### Rollback tháo được bản debug cài mới, Entrypoint quét theo hàm execute

Thêm **1** file Swift, sửa **4** file Swift + **2** file TypeScript.

**`draft.install` / `draft.rollback` đo lần đầu**, có người bấm xác nhận trên máy — hai lệnh cuối chưa từng chạy qua client thật.

- **`draft.install` chạy đúng.** Cài mới `probe.debug.sandbox` ⇒ app trả `packageId: "probe_debug_sandbox"`: app tự chuẩn hoá id từ `plugin.json` của bản nháp, **không** lấy từ client, đúng như doc đã ghi. Hàng thư viện được ghi, extension hiện trong `extensions.list`, và `run.start` trên bản **đã cài** trả `runStarted → responseValidated → runFinished` với đúng kết quả script sinh ra.
- **`draft.rollback` trả `DRAFT_MISSING` trong 40 ms, không hiện hộp xác nhận.** `draft.install` có **hai** đường vào (ghi đè / cài mới, đường thứ hai thêm ở 1.3.325) nhưng `draft.rollback` chỉ có nhánh "trả lại backup", mà đường cài mới không tạo backup. Hệ quả: giao thức **tạo được một hàng thư viện mà chính nó không tháo được** — extension nằm lại trong app, phải xoá tay.
- **Nay rollback rẽ hai nhánh theo `hasBackup`**: có backup ⇒ trả lại bản cũ như trước; không có backup **và** có dấu debug-cài-mới ⇒ xoá thư mục extension rồi xoá hàng `Extension` qua `ExtensionTransactionCoordinator.deleteExtension`. Cả hai nhánh vẫn đi qua cửa xác nhận trên thiết bị, chỉ khác câu mô tả thay đổi.
- **Điều kiện tháo là dấu do chính luồng debug ghi (`.newinstall/<packageId>`), không phải sự vắng mặt của backup.** Extension người dùng tự cài từ kho cũng không có backup; suy từ `hasBackup == false` là cho client debug xoá được chúng, tức biến một công cụ debug thành đường xoá dữ liệu người dùng. Dấu chỉ do `installNew` ghi ở **nhánh tạo mới**.
- **Vòng đời của dấu bằng vòng đời `.backup`** (cùng nằm dưới vùng staging, bị xoá sạch khi tắt server hoặc mở lại app), nên rollback — cả hai nhánh — là khái niệm **trong một phiên debug**. Qua phiên khác thì vẫn phải xoá tay.
- **Lớp lỗi này khác năm lỗi trước.** Năm lỗi đầu của phân hệ đều là "server biết mà client không dùng được"; lỗi này là **thiếu đối xứng của một cặp lệnh**. Bài học ghi vào `11_subsystems`: mỗi đường **tạo** phải có đúng một đường **tháo**.
- **Entrypoint không còn giới hạn ở mục `script` của `plugin.json`.** `ExtensionDebugScriptScanner` (file mới) quét gốc extension và `src/`, trả path tương đối của mọi `.js` có hàm `execute` — nhận `function execute(`, `async function execute(`, `execute = function`/`execute: function`, `execute = (`/`execute = async (`. `extensions.list` mang thêm `executableScripts`; giá trị mặc định rỗng nên client cũ không vỡ, và phía TypeScript khai `optional` nên client mới vẫn chạy với app cũ.
- **Vì sao chỉ quét gốc và `src/`**: production cũng chỉ resolve hai chỗ đó (`ExtensionDraftValidator.resolvedScriptPath`, `ExtensionManager.executeCustomScript`) — liệt kê file ngoài đó là hứa một việc runtime không chạy được. Đọc tối đa **256 KiB** mỗi file vì `execute` luôn khai ở top level, và một file JS bệnh lý vài MB không được làm `extensions.list` treo.
- **Client VSCode**: danh sách chọn Entrypoint nay là *6 entrypoint chuẩn + custom + mọi script quét được*. Chọn một file `.js` thì chạy qua đường `custom` với **tên file trần** — production resolve gốc rồi `src/`, gửi cả tiền tố `src/` là trượt. File trùng tên với entrypoint chuẩn bị loại để không có hai lối vào cùng một script.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; file mới **55**/400, `ExtensionDebugCommandRouter+Draft` 307 → **372**/400 (còn 28 dòng dư — lần mở rộng luồng draft tiếp theo nên tách file), `ExtensionDraftInstaller` 205 → **250**/400. `npx tsc --noEmit` của client **pass**. `validate_links.py` PASS. **Chưa biên dịch** (host Windows); **có file Swift mới nên máy macOS phải `xcodegen generate`**. Bản sửa rollback chưa được kiểm chạy — phải cài IPA mới rồi làm lại đúng chuỗi cài mới → rollback.

## [1.3.347] - 2026-09-05

### Thiếu tham số entrypoint thôi bị báo là entrypoint lạ

Thêm **1** file Swift, sửa **1** file. Vòng đo thứ tư trên máy iOS, chạy trên bản đã cài 1.3.346: **13/13 pass**.

- **Bản sửa 1.3.346 đo lại: đúng.** Manifest khai 300 file ⇒ `QUOTA_EXCEEDED` message "quá 200 file"; manifest khai một file 2 MiB ⇒ `QUOTA_EXCEEDED` message gọi đúng file và con số; `size < 0` ⇒ vẫn `DRAFT_INVALID`, không bị gộp vào nhóm quota.
- **`run.start` với entrypoint đúng tên nhưng thiếu tham số bị báo là "entrypoint lạ".** `entrypoint(from:)` gộp hai loại thất bại thành `nil` nên router trả `UNKNOWN_ENTRYPOINT` cho cả "tên không có trong allowlist" và "tên đúng, thiếu tham số bắt buộc". Đo được: `entrypoint: "search"` không kèm `keyword` trả `UNKNOWN_ENTRYPOINT` — câu đó đẩy người viết client đi kiểm danh sách script trong khi lỗi nằm ở payload của họ. Bốn entrypoint bị ảnh hưởng: `search` (thiếu `keyword`), `detail`/`toc`/`chap` (thiếu `url`), `custom` (thiếu `scriptFileName`).
- **Tách thành `ExtensionDebugEntrypointResolver` với ba kết quả**: `resolved`; `unknownName` ⇒ `UNKNOWN_ENTRYPOINT` **kèm danh sách tên được phép** (`allowedNames` đặt cạnh bảng `switch` nên câu lỗi không thể lệch khỏi thứ engine thật nhận); `missingArgument` ⇒ `MALFORMED_MESSAGE` gọi đúng tên field còn thiếu. Router **ngắn đi 14 dòng** (357 → 343) dù trả về nhiều thông tin hơn.
- **Sáu đường đo lần đầu, không có lỗi**: `genre`/`home` chạy được; `sourceMode: "draft"` với revision không tồn tại trả `DRAFT_MISSING`; `events.subscribe` gọi **hai lần** không nhân đôi event (5 event qua stream, 0 trùng, khớp đúng 5 event trong store); hai `run.start` song song nhận hai `runId` khác nhau; `hello` gọi lại vẫn trả reply bình thường.
- **Tổng kết bốn vòng đo**: mọi lệnh trong `CommandType` trừ `draft.install`/`draft.rollback` đã được chạy thật ít nhất một lần. Năm lỗi tìm được qua bốn vòng **đều** thuộc một lớp — "server biết mà client không dùng được" — không một lỗi logic nào. `draft.install`/`draft.rollback` cố ý chưa test vì chúng ghi vào thư viện extension của người dùng và cần một cú bấm trên máy.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; file mới **57**/400. `validate_links.py` PASS. **Chưa biên dịch** (host Windows); **có file Swift mới nên máy macOS phải `xcodegen generate`**. Bản sửa lượt này chưa được kiểm chạy — phải cài IPA mới rồi đo lại ca `search` thiếu `keyword`.

## [1.3.346] - 2026-09-05

### Trần dung lượng bản nháp trả QUOTA_EXCEEDED thay vì DRAFT_INVALID

Sửa **2** file Swift.

Vòng đo thứ ba trên máy iOS, chạy trên bản đã cài 1.3.345.

- **Bản sửa 1.3.345 đo lại: đúng.** Envelope đúng header với `payload` sai shape nay trả lỗi trong **13 ms**, kèm `requestId` của client và câu "Payload của lệnh 'draft.stage' không đúng dạng". Trước đó treo hết 20 giây timeout.
- **`QUOTA_EXCEEDED` khai trong giao thức từ đầu mà chưa chỗ nào phát.** Tìm ra bằng cách đếm số chỗ phát của từng mã trong `ErrorCode` — nó là mã **cuối cùng** còn 0 lời gọi, sau `UNKNOWN_RUN` ở 1.3.344. Đo trên máy để xác nhận: manifest khai 300 file ⇒ `DRAFT_INVALID`; manifest khai một file 2 MiB ⇒ `DRAFT_INVALID`. Client vì thế không phân biệt được "workspace quá to" (phải bớt file) với "manifest sai" (phải sửa manifest).
- **`ExtensionDraftManifest.quotaIssues()` tách riêng ba trần** (200 file / 4 MiB tổng / 1 MiB mỗi file). `shapeIssues()` gọi nó **trước** phần hình dạng để `message` của reply gọi đúng cái đang chặn — trước đây "thiếu plugin.json" chen lên trước "quá 200 file". `handleDraftStage` phân loại mã bằng cách hỏi lại `quotaIssues()`, **không** dò chữ trong câu lỗi: dò chữ là buộc mã lỗi vào lời tiếng Việt.
- **Chính sách khi lẫn hai loại vấn đề**: có **bất kỳ** vấn đề dung lượng ⇒ `QUOTA_EXCEEDED`, kể cả lúc manifest còn lỗi khác. Trần là thứ phải sửa trước, sửa manifest không cứu được workspace 10 MiB; mảng `issues` vẫn mang đủ mọi vấn đề nên client hiện được cả danh sách.
- **`size < 0` chuyển từ nhóm dung lượng sang nhóm hình dạng.** Trước đây nó bị gộp một câu với "vượt trần" (`size ... không hợp lệ`), nhưng size âm là manifest sai chứ không phải workspace to.
- **Ba đường đo lần đầu, không có lỗi**: `run.cancel` **giữa dòng** dừng run thật (chuỗi `runStarted → fetchStarted → cancelled → fetchFailed → cancelled`); client thứ hai bị chặn mà client thứ nhất không bị ảnh hưởng; luồng staging vẫn chặn đúng path lạ, traversal và sha/size lệch. Riêng việc chặn client thứ hai hiện ra ở phía client thành *handshake timeout* chứ không phải một lời từ chối rõ ràng — đúng như doc của `ExtensionDebugServer` đã tự ghi nhận, để lại làm việc riêng.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `ExtensionDraftManifest` 88 → **106**/400, `ExtensionDebugCommandRouter+Draft` 297 → **307**/400. `shapeIssues()` giữ nguyên chữ ký nên `ExtensionDraftStagingStore` — caller duy nhất — không phải sửa. `validate_links.py` PASS. **Chưa biên dịch** (host Windows) và bản sửa lượt này **chưa được kiểm chạy**: phải cài IPA mới rồi đo lại đúng hai ca manifest 300 file và file 2 MiB.

## [1.3.345] - 2026-09-05

### Payload sai shape thôi làm client debug treo tới hết timeout

Sửa **2** file Swift.

Vòng đo thứ hai trên máy iOS, lần này chạy trên bản đã cài 1.3.344.

- **Xác nhận cả ba bản sửa 1.3.344 chạy đúng**: `run.get` và `run.cancel` với `runId` không tồn tại nay trả `UNKNOWN_RUN`, còn một run thật vẫn trả reply bình thường (5 event, không bị `UNKNOWN_RUN` oan).
- **Envelope đúng header nhưng `payload` sai shape làm client treo tới hết timeout.** `handle(_:)` chỉ có **một** nhánh cho mọi lỗi decode và luôn trả `requestId: "-"`, nên client không ghép lỗi vào request nào được và cứ chờ. Đo được: `draft.stage` với `manifest` thiếu field ⇒ **không nhận reply nào trong 20 giây**, và trên dây chỉ có một envelope `requestId: "-"` trôi nổi. Đây là ca **hay gặp nhất** khi đang viết client — không phải JSON rác.
- **Nay vớt `requestId` bằng một lượt decode tối thiểu** (`EnvelopeHeader`, chỉ `requestId` + `type`) trước khi báo lỗi, và câu lỗi gọi tên đúng lệnh có payload sai. JSON rác thật thì vẫn `"-"`, và đường đó đã được client 1.3.344 hiện thành event nên không còn im lặng.
- **Câu lỗi của `draft.discard`/`draft.install` gọi sai tên field**: nói "Thiếu packageId hoặc revision" trong khi field trên dây là `sourceRevision` — người viết client đọc câu đó sẽ sửa sai chỗ (chính tôi đã bị). Đổi cho khớp giao thức. Client VSCode vốn gửi đúng `sourceRevision` nên đường thật không hỏng.
- **Luồng staging `draft.*` đo lần đầu, không có lỗi**: chặn đúng path không khai trong manifest, `../../evil.js`, size/sha lệch, và `draft.finish` bắt đúng `plugin.json` thiếu mục `script`.
- **Luật rút ra cho các lệnh thêm sau**: mọi đường trả lỗi phải giữ `requestId` của client nếu message có nó; `requestId: "-"` chỉ dành cho message không đọc nổi header.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `ExtensionDebugCommandRouter` 334 → **357**/400, `ExtensionDebugCommandRouter+Draft` giữ **297**/400. `validate_links.py` PASS. **Chưa biên dịch** — host là Windows. Bản sửa lượt này lại **chưa được kiểm chạy** vì máy đang chạy 1.3.344; phải cài IPA mới rồi đo lại đúng ca `draft.stage` với manifest sai field.

## [1.3.344] - 2026-09-05

### Debug server nói ra lý do ở ba ca đang im lặng

Sửa **3** file Swift + **1** file TypeScript của client VSCode.

Ba lỗi dưới đây **đo được bằng client thật** nối vào server trên máy iOS (`ws://<ip>:17772`), chạy 15 ca giao thức: `hello`, `extensions.list` (25 extension), `events.subscribe`, một `run.start` thật (`search` của `ttkan.co`, nhận đủ chuỗi `runStarted → fetchStarted → fetchFinished → responseError → runFinished`), các ca lỗi, JSON rác, và message vượt trần. **13 pass / 2 fail**.

- **`run.get` với `runId` bịa ra trả reply thành công.** Guard cũ chỉ chặn chuỗi không phải UUID; một UUID hợp lệ nhưng không thuộc run nào đi qua và trả `events: []`, `droppedCount: 0` — **không phân biệt được** với "run có thật mà chưa có event". `ErrorCode.unknownRun` đã khai sẵn cho đúng ca này mà chưa chỗ nào phát. Nay hỏi `runner.activeRunIds` và `hub.hasRun(_:)` trước, không thấy thì trả `UNKNOWN_RUN`.
- **`run.cancel` với `runId` bịa ra cũng trả thành công.** Nay cùng cách kiểm. Khác một điểm có chủ ý: run **đã kết thúc** vẫn trả thành công — huỷ cái đã xong là no-op hợp lệ, không phải lỗi của client.
- **`hub.hasRun(_:)` xét cả `droppedByRun`, không chỉ `countByRun`**: `countByRun` bị trừ dần khi buffer tràn và bị xoá khi về 0, nên một mình nó sẽ báo "không có run" cho một run đã từng chạy thật.
- **Message vượt trần 512 KiB đóng kết nối mà không nói gì.** `close(reason:)` gọi `connection.cancel()` thẳng nên client chỉ thấy WebSocket close code **1006** (đóng bất thường, không có close frame); server biết lý do mà chỉ ghi vào `AppLogger`. Nay gửi một envelope `error` rồi mới đóng, qua `sendThenClose(_:reason:)` — đóng **trong** completion của lượt gửi, vì `cancel()` có thể bỏ frame đang xếp hàng nên gửi-rồi-đóng-ngay sẽ mất đúng lời giải thích vừa thêm.
- **Client VSCode bỏ lặng mọi `error` không thuộc request nào.** Server phát hai loại envelope kiểu đó — `requestId: "-"` cho message không parse được, và envelope vừa thêm ở trên. `handleMessage` cũ `return` lặng khi không tìm thấy waiter nên cả hai ca không để lại dấu vết gì cho người dùng. Nay chúng thành một event `level: error, category: exception` đẩy vào panel đang mở.
- **Điểm chung của cả ba**: không phải lỗi logic — server tính đúng, chỉ không có đường đưa lý do sang client. Luật rút ra cho các lệnh thêm sau: **mọi mã lỗi đã khai phải có đúng một chỗ phát**.
- **Không phải bug, đã kiểm rồi loại**: một run trên `qidian` chỉ có 2 event sau 6 giây trông như treo, nhưng chạy lại trên `ttkan.co` thì hoàn tất trong 5 giây với đủ 5 event — đó là fetch chậm ra site Trung Quốc, không phải server đứng.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `ExtensionDebugConnection` 148 → **185**/400, `ExtensionDebugCommandRouter` 308 → **334**/400, `ExtensionDebugEventHub` 103 → **114**/400. `npx tsc --noEmit` của client VSCode **pass**. `validate_links.py` PASS. **Phần Swift chưa được kiểm chạy**: máy iOS đang chạy bản cũ nên lượt đo trên chỉ chứng minh *lỗi có thật*, chưa chứng minh *bản sửa chạy đúng* — phải cài IPA mới rồi đo lại. Host là Windows nên cũng chưa biên dịch tại chỗ; không thêm file Swift nên không cần `xcodegen generate`.

## [1.3.343] - 2026-09-05

### Sửa số Hán viết tắt đọc sai, thanh kéo độ dài token sinh rác, ô thử nói rõ phạm vi

Sửa **5** file Swift.

- **`八千三` ra `8003` thay vì `8300`, `一万二` ra `10002` thay vì `12000`.** `parseChineseNumeral` cộng thẳng chữ số cuối vào kết quả, trong khi tiếng Trung viết tắt: **một chữ số trần đứng cuối, ngay sau ký tự bậc, mang bậc thấp hơn một cấp**. Hệ số luôn là `bậc / 10` nên không cần bảng riêng: `八千三` = 8 nghìn + 3 **trăm**, `一万二` = 1 vạn + 2 **nghìn**, `三百五` = 350, `一亿二` = 120000000. Bậc `十` cho hệ số 1 nên `二十三` = 23 **không đổi** — đó là lý do lỗi này sống từ bản đầu mà không ai thấy: nó chỉ lộ ra từ bậc `百` trở lên.
- **Hai cửa hẹp giữ đúng nghĩa các chuỗi khác**: ký tự liền trước chữ số đuôi **phải là bậc** — điều kiện này tự loại `一万零二`, vốn đúng nghĩa là `10002` vì liền trước `二` là `零`; và `零`/`〇` không tính là chữ số đuôi. Đường liệt kê nhiều số (`十三四` → "13, 14") không bị ảnh hưởng: các chuỗi nó dựng ra đi qua nhánh viết tắt với hệ số 1 nên kết quả giữ nguyên. **Đổi hành vi cần biết**: `三百五` từ `305` thành `350` — đó chính là phần sửa, `305` viết đúng là `三百零五` và vẫn ra `305`.
- **Kéo thanh "Tối đa" ở màn thêm/sửa rule sinh rác `<n:1-8>1-9>`.** `Slider` bắn callback **nhiều lần trong một cú kéo**, còn bên ngoài định vị token bằng một `Segment` đã chụp lúc dựng body; giữa hai lần bắn SwiftUI chưa chắc dựng lại body nên lần sau dùng range cũ. Với mẫu `<n>` (3 ký tự): lần 1 ghi ra `<n:1-9>` (7 ký tự) đúng, lần 2 vẫn thay 3 ký tự đầu của chuỗi 7 ký tự nên `1-9>` còn nguyên ở đuôi — số ở đuôi khác nhau vì đó là giá trị cú kéo vừa đi qua. `replacing(range:in:with:)` chỉ kẹp về biên chuỗi nên range lệch bị cắt sai **im lặng**. Nút `+`/`−` gần như không bị vì hai lần bấm cách nhau đủ xa để body dựng lại.
- **Sửa ở hai lớp cho cùng lớp lỗi đó**: (a) thanh kéo giữ giá trị đang kéo ở `@State` cục bộ và chỉ ghi ra ngoài **một lần** ở `onEditingChanged` khi nhả tay — nhãn số vẫn nhảy mượt; (b) `applyTokenSpec` nhận `tokenOrdinal` thay cho `Segment` và gọi `replacing(tokenOrdinal:in:with:)`, hàm **đã có sẵn từ trước mà chưa ai gọi**, tự định vị lại token trên mẫu hiện tại. Lớp (b) đóng cả những đường gọi khác có thể xuất hiện về sau. `TokenSpec.clamp()` vẫn là chỗ duy nhất kẹp biên và hai nút vẫn đi qua cùng `adjust`.
- **Ô "Thử nhanh một câu" nay nói rõ nó chỉ áp bộ rule chung.** `preview(_:bookId:mode:)` được gọi với `bookId` mặc định `nil` vì màn này mở từ Cài đặt, không có truyện nào đang mở — nên bộ rule **riêng của truyện**, công tắc token riêng và thứ tự ưu tiên riêng đều không được tính. Mà nút `+` trong panel Dịch **mặc định lưu vào bộ riêng**, nên một rule vừa thêm sẽ "có trong Danh sách rule mà không ăn ở ô thử" — người dùng không có cách nào biết. Thêm một dòng chú thích chỉ sang panel Dịch trong Reader, là chỗ vốn đã chạy đúng `bookId`. Cố ý **không** thêm bộ chọn truyện vào màn Cài đặt: kéo `@Query` trên `Book` vào đây là mở một đường phụ thuộc mới cho việc đã có chỗ làm tốt hơn.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `QuickTranslationNumberFormatter` 287 → **339**/400, `QuickTranslationRuleTokenLengthBar` 145 → **172**/400, `QuickTranslationRuleEditorSheet` 377 → **378**/400, `QuickTranslationRuleTesterView` 113 → **125**/400. `validate_links.py` PASS sau khi cập nhật `07_dataflow`, `11_subsystems`. **Chưa biên dịch** — host là Windows; không thêm file Swift nên không cần `xcodegen generate`.

## [1.3.342] - 2026-09-05

### Token bậc trả chữ đơn vị mươi/trăm/vạn thay vì số

Sửa **6** file Swift.

- **`<m>` trả chữ đơn vị tiếng Việt, không phải giá trị số**: `十` → `mươi`, `百` → `trăm`, `千` → `nghìn`, `万/萬` → `vạn`, `亿/億` → `ức`, `兆` → `triệu`. Bản 1.3.341 trả `10`/`100`/`1000` — sai mục đích của token: `几<m>年 = mấy {0} năm` phải đọc thành "mấy mươi năm", không phải "mấy 10 năm".
- **Bảng chữ đơn vị là bảng riêng `magnitudeWords`**, cố ý **không** dùng lại `smallMagnitudes`/`largeMagnitudes`: hai bảng kia là **giá trị số** để `<n>` tính toán, trộn hai mục đích vào một bảng là mở đường cho một lần sửa làm sai chỗ kia. Cần con số thì vẫn dùng `<n>`, nó đọc `十` thành `10`.
- **`兆` đọc "triệu" theo Hán-Việt dù giá trị số của nó là 10¹²** — theo lối đọc quen của bản dịch truyện, không theo giá trị. Ghi rõ ở doc của bảng vì đây là chỗ dễ bị coi là bug.
- Lớp ký tự `magnitudeUnits`, boundary guard, và việc parser ép `<m>` về đúng 1 ký tự **không đổi**. Nhãn token, chú thích ở màn công tắc chung và chú thích ở màn thêm/sửa rule đều cập nhật theo.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt. `validate_links.py` PASS. **Chưa biên dịch** — host là Windows; không thêm file Swift nên không cần `xcodegen generate`.

## [1.3.341] - 2026-09-05

### Thêm token bậc số Hán và token chữ A-Z cho rule dịch

Sửa **10** file Swift. DSL rule lên **12** token.

- **`<m>` — bậc số Hán.** Khớp **đúng một** ký tự trong `十百千万萬亿億兆` và render ra số: `十` → `10`, `百` → `100`, `千` → `1000`, `万/萬` → `10000`, `亿/億` → `100000000`, `兆` → `1000000000000`. Mục đích là một rule phủ mọi bậc thay cho nhóm `(十|百|千)` viết tay — `几<m>年 = mấy {0} năm` cho cả mấy mươi / mấy trăm / mấy nghìn năm, `几<m>次 = mấy {0} lần`. Parser **ép về 1 ký tự** bất kể `:min-max` (giống `<L>`/`<hv>`) nên thanh chỉnh độ dài bị ẩn: nối hai ký tự bậc không thành một bậc mới. Hệ quả cố ý: `几<m>年` **không** khớp `几万亿年` — dải bậc ở đó dài 2 ký tự, guard bên phải buộc nuốt hết nên rule trượt; ca đó thuộc `<n>`, vốn đọc `万亿` thành một số.
- **`<a>` — chữ cái A-Z.** Khớp một dải chữ cái Latin hoa/thường, **kể cả full-width** `Ａ-Ｚ`/`ａ-ｚ`, trả **nguyên văn** và chỉ hạ full-width về ASCII (cùng chính sách `<d>`, để `ＳＳＳ` và `SSS` ra một kết quả). Giữ đúng hoa/thường — `SSS级` ra `SSS`, không phải `sss`. Có `:min-max` vì cấp bậc dài nhiều ký tự: `<a>级 = cấp {0}` phủ `A级`, `BB级`, `SSS级`. Không nhận chữ số, phần số đã có `<n>`/`<d>`.
- **Cả hai dùng lại nguyên bộ máy char-class**, không thêm nhánh nào ở matcher ngoài hai case render: chúng là phần tử `Kind.numeral` với `NumeralKind` mới, nên boundary guard hai đầu, thử độ dài dài → ngắn, `literalLength`, `wildcardCapacity`, `minimumWidth`/`maximumWidth` đều không phải sửa. Guard làm việc theo lớp ký tự của chính token: `<a>` từ chối ăn một phần dải chữ dài hơn (start 1 của `SSS级` bị loại vì ký tự liền trước cũng là chữ cái).
- **Tranh chấp với rule `<n>` sẵn có tự giải quyết ở tiêu chí 1 (vị trí)**: trên `几十年`, `几<m>年` khớp từ vị trí 0 còn `<n>年` chỉ từ vị trí 1, nên rule có literal `几` thắng và rule kia bị loại vì chồng lấn.
- **Config và nhập nhanh đều có.** Công tắc chung (Cài đặt → Quản lý rule dịch → Cấu hình token rule) thêm 2 hàng; công tắc riêng theo truyện và dải nút chèn token trong màn thêm/sửa rule **tự có** vì cả hai dựng từ `Kind.allCases` + `Kind.isNumeralGroup`. Nhóm token đầu đổi tên "Token số và nhãn" → **"Token lớp ký tự và nhãn"** ở cả ba màn vì nó không còn chỉ chứa số. Chú thích trong màn thêm/sửa rule liệt kê đủ 12 token và nói rõ `<L>`, `<hv>`, `<m>` luôn đúng một ký tự nên không có thanh độ dài.
- **Nhân đó bỏ một chỗ trùng lặp**: 12 `Toggle` của màn công tắc chung nay đọc `Kind.label` thay vì tự viết nhãn, nên nhãn token chỉ còn **một** nguồn cho cả ba màn.
- **Token mới phải thêm vào cuối `Kind`**: `Configuration.signature` là chuỗi bit theo thứ tự `allCases` và nằm trong khoá cache dịch, nên chèn vào giữa làm mọi chữ ký cũ trượt một bit — đã ghi thành chú thích tại chỗ.
- **Nợ tên đã ghi nhận, không che**: `NumeralKind` giờ chứa `.latinLetters`, tức tên hẹp hơn nghĩa (thật ra là "lớp ký tự"). Giữ nguyên tên vì đổi là sửa 14 chỗ `switch` trên phân hệ nóng mà không có compiler tại chỗ; đã ghi ở doc của enum, `11_subsystems` và `rules.md` để đổi khi có macOS.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `QuickTranslationNumberFormatter` 244 → **287**/400, `QuickTranslationRuleTokenSettings` 93 → **105**/400, `QuickTranslationRuleElement` 146 → **158**/400, `QuickTranslationRuleTokenSettingsView` 67 → **71**/400. `validate_links.py` PASS (16 doc, 500 file) sau khi cập nhật `04_call_graph`, `07_dataflow`, `11_subsystems` và ghi `no-change-needed` cho `13_resource_lifecycle`. **Chưa biên dịch** — host là Windows; lượt này không thêm file Swift nên không cần `xcodegen generate`.

## [1.3.340] - 2026-09-05

### Ô tạo bộ sưu tập không còn lệch hàng, nút thêm rule điền sẵn nghĩa

Sửa **4** file Swift.

- **Ô "tạo bộ mới" trong grid bộ sưu tập bị đẩy tụt xuống so với thẻ bên cạnh.** Nguyên nhân: `LazyVGrid` lấy chiều cao hàng theo ô **cao nhất** rồi **căn giữa** những ô thấp hơn. Thẻ thường là `[ảnh ghép + tên]`, còn ô tạo mới chỉ có `[ô vuông]`, nên nó thấp hơn đúng phần chữ và bị dịch xuống nửa khoảng đó. Cùng cơ chế đó, một tên bộ dài **2 dòng** cũng làm hàng cao hơn hàng khác. Sửa bằng `CollectionGridCardView.titleReserve` — một `Text("A\nA")` **ẩn** (`.hidden()` giữ layout, chỉ bỏ vẽ) làm sàn chiều cao đúng 2 dòng: thẻ đặt nó trong `ZStack(alignment: .topLeading)` cùng tên bộ nên tên 1 dòng hay 2 dòng đều cùng chiều cao và cùng căn trên, còn ô tạo mới dùng nó một mình. Cố ý **không** dùng chiều cao pt cố định để còn đúng khi người dùng đổi cỡ chữ hệ thống.
- **Nút `+` ở panel Dịch nay điền sẵn cả ô Bản dịch.** Trước đây chỉ ô Mẫu được điền bằng cụm gốc đang chọn, ô Bản dịch để trống dù nghĩa đã nằm ngay trên màn hình. `Mode.add` mang thêm `prefilledReplacement`, lấy từ `customMeaning` — tức **đúng chữ trong ô nhập nghĩa của panel Dịch**, kể cả nghĩa người dùng vừa sửa tay, không phải nghĩa từ điển thô. Đường mở từ màn danh sách rule truyền chuỗi rỗng như cũ.
- **Khoá bản nháp đổi theo**: `Mode.id` của chế độ thêm thành `"add:\(pattern)|\(replacement)"`. Cần thiết vì `QuickTranslationRuleDraftStore` khoá nháp theo `id` — nếu để `id` chỉ mang mẫu thì đổi nghĩa ở panel Dịch rồi bấm `+` sẽ khôi phục nháp của lần trước và ghi đè giá trị điền sẵn mới.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt; `QuickTranslationRuleEditorSheet.swift` 359 → **377**/400, `CollectionGridCardView` 74 → **93**/400, `CollectionsTabView` 243 → **249**/400, `ReaderView+DefinitionPanel` 112 → **119**/400. `validate_links.py` PASS (16 doc, 500 file) sau khi cập nhật `04_call_graph`, `11_subsystems` và ghi `no-change-needed` cho `13_resource_lifecycle`. **Chưa biên dịch** — host là Windows; lượt này không thêm file Swift nên không cần `xcodegen generate`.

## [1.3.339] - 2026-09-05

### Grid bộ sưu tập, tab icon, lịch sử theo ngày, và fix nóng máy khi sửa VP/rule

Thêm **7** file Swift, sửa **13** file. Sáu việc: ba việc UI ở Kệ sách, hai việc ở màn rule dịch, một lượt điều tra + fix hiệu năng đường dịch.

- **Điều tra nóng máy: nguyên nhân không phải bộ rule.** Người dùng báo sửa VP/rule ngay trong Reader làm giật và nóng, **với bộ chỉ ~50 rule**. Bốn nguyên nhân thật, tất cả độc lập với số rule: (a) `postProcessText` biên dịch lại **4** `NSRegularExpression` mỗi lần gọi, mà `translatedCandidate(for:)` gọi nó **cho từng token** khi dựng span ⇒ ~24.000 lượt compile pattern ICU cho **một** lần dựng lại chương; (b) mỗi dòng bị `tokenize` **hai lần** — một lần ở `translateContent`, một lần nữa ở `getTranslationTokens` khi dựng span — và `tokenize` không có cache ở tầng nào (chương ~200 dòng ⇒ ~400 lượt, mỗi lượt O(số ký tự × số từ điển)); (c) `TextDictionary.findAllPrefixMatches` dựng chuỗi tạm cho **mọi** độ dài từ `maxWordLength` xuống 1, mà `maxWordLength` là entry dài nhất của cả file — nên thêm một mục VP dài trong Reader làm chậm vĩnh viễn mọi lượt tokenize sau đó, và từ điển custom/riêng của truyện đi đúng đường này; (d) vòng dựng output của tokenizer dùng `first(where:)` bên trong `while` ⇒ O(n²). Vì sao "sau vài commit hôm qua": bốn chi phí này có từ trước, nhưng 1.3.334 đưa công cụ sửa rule vào panel Dịch **trong Reader** nên từ đó mỗi lần tinh chỉnh đều kéo theo một lượt dựng lại cả chương ngay tại chỗ đang đọc — tần suất đổi, không phải đơn giá.
- **Sửa cả bốn.** `postProcessText` dời thân + 4 regex sang `TranslationTextPostProcessor` (`static let`, biên dịch một lần); `TranslateUtils.postProcessText` còn một dòng forward nên hai caller không phải sửa và **thứ tự các bước không đổi**. `TokenizeMemo` (`NSCache` 512 entry) ghi nhớ kết quả tokenize, khoá = `translationGenerationToken` + `bookId` + hai cờ đại từ/luật nhân + `md5(text)`; generation nằm trong khoá nên **không ai phải gọi `clear()`**. `TextDictionary` đổi `maxWordLength` thành `keyLengthsDescending` — chỉ thử những độ dài khoá **có thật**, và đếm theo UTF-16 cho khớp với `[UInt16]` mà hai hàm tra làm việc trên (sửa một lệch có thật với khoá ngoài BMP). Tokenizer thay hai vòng `first(where:)` bằng `nextStartTable` (một pass ngược, tra O(1)) + hai bảng theo chỉ số bắt đầu; kết quả token không đổi.
- **Ba việc phụ trên cùng đường**: nới/thu vùng chọn không còn tokenize lại cả đoạn (`translationTokens` chỉ phụ thuộc đoạn văn + generation); `updateCachedTranslatedContent` **đọc** `scope` thay vì nhận rồi bỏ, nên thay đổi thuộc một truyện khác không kéo theo dựng lại chương đang đọc (thông báo thường có `userInfo["bookId"] == nil` nên bộ lọc ở tầng View không chặn được — chỗ chặn đúng là view model); `refreshRuleTraces` debounce 150 ms + chạy `Task.detached`, an toàn vì đó đúng call graph mà `performChapterTranslationOffMainActor` đã dùng off-main và `QuickTranslationRuleTrace` là `Sendable`. Kèm theo, chip rule nay làm mới **theo vùng chọn** — bất biến đã ghi trong doc panel Dịch từ 1.3.334 nhưng chưa từng được cài.
- **Rule `第<n><L> = Chương {0}` nay hợp lệ.** `UNUSED_CAPTURE` hạ từ `hard` xuống `warning`: token không được `{i}` nào tham chiếu vẫn **khớp và nuốt** ký tự, chỉ không xuất ra bản dịch — đó chính là cách ăn luôn chữ `章`. Trước đây compiler bỏ **cả dòng** một cách im lặng. Kéo theo: `validRecords`/`hasHardError` lọc theo `.hard` nên các dòng này nay được ghi vào file canonical, lưu rule kiểu này từ panel Dịch không còn bị `.rejected`, và số hard error của `rule-aio.txt` còn **1** (dòng 916) chứ không phải 2. Đánh đổi: rule gõ nhầm chỉ số `{i}` nay sẽ chạy và cho bản dịch thiếu chữ, chỉ còn cảnh báo chứ không bị chặn.
- **Dải nút chèn token hiện đủ 10 token.** Không phải thiếu token — palette vốn dựng từ `Kind.allCases` — mà là 10 chip nằm trong `ScrollView(.horizontal, showsIndicators: false)` nên trên iPhone chỉ 5–6 chip đầu lọt màn hình, `<ne> <pn> <vp> <hv> <w>` bị cắt **không có dấu hiệu nào** báo cuộn được. Đổi sang `FlowLayout` (custom `Layout`, **không** lazy — giữ đúng bài học crash 1.3.269, tuyệt đối không `LazyHStack` trong hàng `Form`), chia hai nhóm "Số & nhãn" / "Từ điển" theo `Kind.isNumeralGroup`.
- **Tab Bộ sưu tập thành grid thẻ ảnh ghép bìa**: bìa lớn bên trái + hai bìa nhỏ bên phải, badge "còn N truyện" trên bìa nhỏ cuối khi bộ có hơn 3 quyển, tên bộ viết hoa bên dưới, ô "tạo mới" ở cuối grid. Ba khối mới: `CollectionCoverMosaicView` (5 bố cục cho 0/1/2/≥3 quyển), `CollectionGridCardView` (thẻ + `previewBooks` chọn 3 bìa bằng **một pass** thay vì `sorted()` cả mảng, vì hàm chạy lại mỗi lần vẽ mỗi thẻ), `CollectionsReorderSheet`. `LazyVGrid` nằm trong `ScrollView`, **không** trong `List`. Mất có chủ ý: swipe-to-delete/rename — hai việc đó ở `.contextMenu` (nhấn giữ) và ở menu trong `CollectionDetailView`; `onMove` chuyển sang sheet vì `LazyVGrid` không có.
- **Thanh chọn tab Kệ sách thành hàng nút rời**: Downloads + Bộ Sưu Tập thu về nút icon 40×40, Kệ Sách + Lịch Sử giữ pill chữ co theo nội dung. `ShelfTab` mang thêm `iconName`/`isIconOnly`; `rawValue` **không đổi** nên hợp đồng `userInfo["shelfTab"]` với `SearchView` và `ShelfView+BookImport` giữ nguyên. Nút icon có `accessibilityLabel` bắt buộc, màu dùng semantic chứ không hardcode màu tối.
- **Tab Lịch sử nhóm theo ngày**, mỗi ngày một `Section` với nhãn "Hôm nay"/"Hôm qua"/`dd/MM/yyyy`. `HistoryDayGrouper` gom một pass (các ngày liền khối vì `@Query` đã sắp `lastReadDate` giảm dần) và giữ **một** `DateFormatter` static; header dùng lại đúng `shelfSectionHeader` mà tab Kệ sách dùng. Gom **sau** `prefix(historyLimit)` nên phân trang +50 giữ nguyên.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt, không phát sinh mới và không nới baseline nào — `TranslateUtils.swift` 968 → **934** (lần đầu đi xuống, vẫn trên baseline 917 là violation cũ), `ShelfView` 842 → **856**/942, `ReaderView` 1997 → **2001**/2053, 7 file mới đều dưới 90 dòng. `validate_links.py` PASS (16 doc, 500 file) sau khi cập nhật 11 doc và ghi `no-change-needed` cho `08_lifecycle`, `13_resource_lifecycle`. **Chưa biên dịch** — host là Windows; 7 file Swift mới nên phải `xcodegen generate` khi lên macOS. Phần "đã bớt nóng" **phải** đo trên máy thật, CI xanh chỉ chứng minh biên dịch được.

## [1.3.338] - 2026-09-05

### Cấu hình thứ tự ưu tiên rule dịch, đặt riêng theo truyện, mặc định ưu tiên độ dài

Thêm **6** file Swift, sửa **6** file. Thứ tự phá tranh chấp giữa hai rule chồng nhau trở thành dữ liệu cấu hình, có phạm vi chung và phạm vi riêng theo truyện; công tắc token cũng có phạm vi riêng.

- **Đổi mặc định của engine.** Preset mới **Ưu tiên độ dài** (`chữ ghim ↓ → số chữ khớp ↓ → hạn mức token ↑ → bộ riêng ↑`) thay cho ngữ nghĩa `executeRules` của reference. Lý do: `wildcardCapacity` đếm **mức trần khai báo** (`<n>` trần = 12) nên nó cộng theo *số token*, làm rule mô tả cấu trúc đầy đủ hơn luôn thua rule con của nó — `<n>米<n>` (24) thua `<n>米` (12) trước khi tiêu chí "độ dài match" được xét lần nào. Hệ quả thấy được: `三米五` ra "3 mét 5" thay vì "3 mét" + `五` dịch rời. Hai preset còn lại: **Như engine gốc** (đường lùi về hành vi cũ) và **Xuất hiện trước rồi dài hơn** (leftmost-longest thuần).
- **`select` đọc thứ tự từ dữ liệu, hai đầu bị khoá.** `QuickTranslationRuleEngine.select(from:priority:)` giữ `start` làm khoá đầu và `sourceLine` làm khoá cuối; bốn tiêu chí giữa lấy thứ tự + chiều từ `QuickTranslationRulePriorityConfiguration`. `start` phải đứng đầu vì vòng chọn là một pass tuyến tính theo `cursor` — khoá chính khác `start` thì match ở vị trí 50 lấy trước sẽ đẩy `cursor` lên 54 và giết match ở vị trí 10. `sourceLine` phải nằm **dưới** `scopeRank` vì số dòng của hai bộ đều đếm từ 1 nên hai rule khác bộ có thể trùng số dòng. Bốn tiêu chí giữa cho 4! × 2⁴ = 384 tổ hợp, tổ hợp nào cũng là strict weak ordering hợp lệ vì cả bốn là khoá tổng so theo cặp độc lập ngữ cảnh. Ghi chú đã ghi vào `rules.md`: **không** được thêm luật so sánh có điều kiện theo cặp (kiểu "chỉ ưu tiên độ dài giữa hai rule toàn token số") — mất tính bắc cầu và `sorted(by:)` thành không xác định.
- **Cấu hình riêng theo truyện, ngữ nghĩa kế thừa.** `QuickTranslationBookEngineConfigStore` là chủ mới của `translate/books/<bookId>/QuickTranslateEngineConfig.json`, giữ cả thứ tự ưu tiên và trạng thái 10 token. Trường vắng = *theo cài đặt chung*, nên sửa cấu hình chung vẫn lan tới truyện chưa đặt riêng — cố ý **không** lưu bản copy, vì bản copy làm truyện đóng băng giá trị chung ngay lần đầu mở màn cấu hình. Token có **ba** trạng thái (`Chung`/`Bật`/`Tắt`); `inherit` không ghi vào file, file rỗng thì bị xoá thay vì ghi `{}`, file hỏng thì truyện chạy theo bộ chung. Đọc có cache RAM + `NSLock` vì `rewrite` chạy theo từng dòng văn.
- **Áp cho cả trình đọc và đọc thành tiếng bằng đường đã có.** `TTSBackgroundProcessor` vốn truyền `bookId` xuống `TranslateUtils` giống Reader, nên không thêm tham số nào ở tầng TTS. `priority.signature` được ghép vào khoá memo của engine cạnh `tokenConfiguration.signature` — thiếu bước này thì đổi thứ tự mà cache cũ vẫn trả kết quả cũ. `QuickTranslationRuleDiagnostics` dùng **cùng** hai bản chụp nên panel rule ở Reader không nói khác bản dịch thật.
- **Ba màn mới, mỗi tiêu chí đều có mô tả trong app.** Cài đặt → Quản lý rule dịch → Công cụ → **Thứ tự ưu tiên rule** (chung); Cài đặt trình đọc → **Thứ tự ưu tiên rule** + **Token rule của truyện** (riêng, có nhãn phụ nói rõ đang theo cài đặt chung hay đang đặt riêng). Chữ mô tả nằm ở tầng Service (`Key.explanation`, `Key.directionLabel(descending:)`, `Preset.explanation`, `Kind.label`) để View không viết lại. Bảng cài đặt trình đọc là sheet trần không có `NavigationStack` nên hai màn con mở bằng sheet lồng — đúng cách `ReaderView` mở `BookDictionaryView`. Phần ghi đĩa gọi từ `onChange` chứ không từ setter của `Binding`, vì setter là closure escaping mà `ToastManager` là `@MainActor`.
- **Rủi ro đã ghi vào `10_risk_report`**: đổi mặc định là đổi hành vi thấy được cho mọi người dùng, và **không đo được trong repo** — ba bộ rule (`rule-aio.txt`, `Rule_new.txt`, bộ chuẩn v21) do người dùng import lúc chạy, không nằm trong repo. Xác minh phải làm bằng panel rule trong Reader trên máy thật. Ghi nhận thêm: cấu hình riêng của truyện **không** bị xoá khi xoá truyện — giống hệt bộ rule riêng, file tắt riêng và từ điển riêng, vì `BookStorageManager` không chạm `translate/`; đây là hành vi có từ trước, và không nên "sửa" bằng cách xoá cả thư mục vì sẽ xoá luôn từ điển người dùng nhập tay.
- Gate: `check_architecture.py` giữ đúng **7 violation** cũ, tập y hệt, không phát sinh mới và không nới baseline nào (`ReaderView.swift` giữ 1997/2053 dòng vì tham số `bookId` ghép vào dòng gọi có sẵn). `validate_links.py` PASS sau khi cập nhật `00_index`, `02_file_graph`, `07_dataflow`, `09_dependency_rules`, `10_risk_report`, `11_subsystems`, `14_complexity_report`, `rules` và ghi `no-change-needed` cho `04_call_graph`, `08_lifecycle`, `13_resource_lifecycle`. **Chưa biên dịch** — viết trên Windows, và lượt này thêm file Swift nên máy macOS phải `xcodegen generate` trước khi build.

## [1.3.337] - 2026-09-04

### Gộp hai hàng kệ sách thành nút icon, bỏ header sheet, nhấn giữ nhanh hơn, nút Tìm dùng chữ đang thấy

Sửa **7** file Swift, không thêm/xoá file nào. Đợt 5: năm việc A–E.

- **A — Bỏ hai hàng "Thêm vào kệ sách" / "Xoá khỏi kệ sách"** khỏi danh sách hành động của `BookActionSheet`. Nhánh `target.mode == .history` vì thế còn rỗng nên gộp thẳng thành `if target.mode != .history, !book.isLocalBook` cho hàng "Kiểm tra chương mới". Hai case `.addToShelf` / `.removeFromShelfOnly` **giữ nguyên** trong `BookSheetAction`, nên `handle(_:for:)` của Kệ sách, màn bộ sưu tập và màn tìm kiếm không phải sửa một dòng.
- **B — Thêm nút icon kệ sách ở góc dưới phải phần đầu** (`shelfToggleButton`): `bookmark.fill` (xanh) khi chưa trên kệ, `bookmark.slash.fill` (đỏ) khi đang trên kệ — chiều suy ra từ `book.isOnShelf` nên không bao giờ hiện cả hai. Phần đầu tách hai vùng **cạnh nhau**: `headerTappableContent` (bìa + tên, mang `onTapGesture`/`onLongPressGesture`) và `headerTrailingColumn` (`info.circle` trên, nút kệ dưới). Cố ý **không** dùng `overlay` đè lên vùng cử chỉ. Cột phải để `.frame(minHeight: 84, maxHeight: .infinity)` — `minHeight` khớp ảnh bìa để nút nằm đúng đáy khi tên ngắn, `maxHeight` để cột giãn khi tên dài hơn bìa; thiếu một trong hai thì nút trôi lên giữa panel.
- **C — Nhấn giữ nhanh hơn và có nhịp rung.** `BookSheetAction.longPressMinimumDuration = 0.25` thay cho 0.35/0.4 rải rác ở **5** chỗ (Kệ sách ×2, bộ sưu tập, màn tìm kiếm, phần đầu sheet), cộng `playLongPressFeedback()` (`UIImpactFeedbackGenerator(.medium)`, cùng cường độ với các chỗ rung khác trong app). Lý do cảm giác chậm: `.contextMenu` hệ thống phóng to bản xem trước **ngay khi** ngón tay chạm, còn menu tự dựng không có gì báo cho tới lúc sheet hiện — nên ngoài việc hạ ngưỡng phải có một phản hồi tại đúng thời điểm kích hoạt. `maximumDistance` mặc định (10pt) vẫn huỷ cử chỉ khi đang cuộn nên hạ ngưỡng không sinh kích hoạt oan.
- **D — Bỏ header và nút "Xong" của sheet**: xoá luôn `NavigationStack` (không còn `navigationTitle` "Tuỳ chọn truyện" lẫn `toolbar`), thêm `.presentationDragIndicator(.visible)` vì vuốt xuống nay là **đường đóng duy nhất**. Ràng buộc mới cần nhớ: sheet này không còn navigation nên không thêm được `.toolbar`/`navigationDestination` — hành động cần navigation vẫn phải phát `BookSheetAction` cho màn chủ.
- **E — Nút "Tìm" tra chữ đang bôi đen, không tra chuỗi gốc.** `performQuickLookup` nhận thêm `query: String? = nil`; `searchSelectionOnGoogle()` truyền `selectedDisplayedText` (bản dịch khi bật dịch), có đường lùi về `nil` nếu chuỗi đó rỗng. Các link tra Hán-Việt ở panel Dịch **giữ nguyên** hành vi cũ (`selectedTextForDefinition`, tức text gốc) — đúng với việc chúng tra từ điển chữ Hán. Bẫy kèm theo: `onPerformQuickLookup` phải bọc `{ performQuickLookup(using: $0) }` chứ không truyền thẳng tên hàm, vì function reference có default argument **không** tự chuyển sang `(SearchEngine) -> Void`.
- Gate: `check_architecture.py` giữ **7 violation** cũ, không phát sinh mới (`BookActionSheet.swift` 307 → **341**/400, `BookSheetAction.swift` 43 → **59**). `validate_links.py` PASS (16 doc, 487 file) sau khi cập nhật `04_call_graph`, `05_state_graph`, `11_subsystems` và ghi `no-change-needed` cho `13_resource_lifecycle`.
- **Chưa biên dịch, chưa chạy thử** — host là Windows. Không thêm/xoá file Swift nên **không** cần `xcodegen generate`. Việc phải nhìn đầu tiên: nút kệ sách có nằm đúng góc dưới phải với cả tên truyện ngắn và tên 3 dòng, và chạm nút đó **không** kích hoạt luôn cử chỉ chạm/nhấn giữ của phần đầu.

## [1.3.336] - 2026-09-04

### Sửa VP có dấu không khớp, gợi ý phiên âm ra khỏi main thread, 4 việc UI

Thêm **4** file Swift (483 → **487**), sửa **14**. Đợt 4: sáu việc A–F trong một lượt.

- **A — "Mở thêm phiên âm" chậm là main thread chờ lock của espeak.** `AddWordSheet.suggestions` là computed property đọc **trong `body`**, và nó gọi `EnglishPhonemeTransliterator.detailed` → `EspeakPhonemizer.phonemizeEnglish`: hàm C đồng bộ giữ **một `NSLock` dùng chung với đường tổng hợp NghiTTS**, lần đầu còn chạy `espeak_Initialize` (có nhánh dự phòng quét đệ quy bundle). Mở sheet lúc đang nghe TTS là đóng băng UI tới khi lượt đọc nhả lock, và **mỗi lượt vẽ** lặp lại đúng việc đó. Nay gợi ý nằm trong `@State`, dựng bằng `Task { @MainActor }` (debounce 300 ms, lượt đầu bỏ debounce) → `TextPreprocessor.lookupWord` → **`Task.detached`** gọi `TTSPhoneticSuggestionBuilder`. `Task.detached` chứ không `Task`: `Task` thừa hưởng actor của chỗ tạo nên espeak vẫn chạy trên main thread. Sheet dời ra [file riêng](../../Sources/Views/Settings/TTS/AddWordSheet.swift) (202 dòng) nên [`TTSDictionaryEditView.swift`](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift) 702 → **559**, dưới baseline 641. `TTSPhoneticSuggestion` + `Origin` khai `Sendable` vì struct/enum `public` không được suy ra ngầm.
- **B — Nút xoá bộ sưu tập thấy được.** Trước đó xoá/đổi tên **chỉ** có ở swipe action của tab Bộ sưu tập. Thêm menu `ellipsis.circle` (Đổi tên / Xoá bộ sưu tập, có confirm) trong màn chi tiết bộ — [`CollectionDetailView+Manage`](../../Sources/Views/Shelf/Collections/CollectionDetailView+Manage.swift), xoá xong `dismiss()` thay vì để lại màn "Bộ sưu tập không còn tồn tại" — cộng `.contextMenu` cho hàng ở `CollectionsTabView`. Swipe action cũ giữ nguyên; chủ transaction vẫn **chỉ** là `BookCollectionCoordinator` và cả hai đường đều xử lý `Result`.
- **C — Chip `{0} {1}…` chèn tại con trỏ** thay vì `replacement += "{i}"` (nối vào cuối). Ô Bản dịch dùng chính [`QuickTranslationRulePatternField`](../../Sources/Views/Settings/Translation/QuickTranslationRulePatternField.swift) của vế trái, thêm đúng một tham số `usesMonospacedFont` (khai bằng `var` có mặc định để init memberwise vẫn cấp, và đặt **trước** `onFocusChange` để trailing closure không lệch). Thêm `insertIntoReplacement(_:)` + `reconcileReplacementSelection(after:)`, hai `@State` con trỏ mới, và 2 field trong `Draft` để lượt dựng lại sheet không đẩy con trỏ về cuối. Bỏ `@FocusState isReplacementFocused` — cả hai ô nay báo focus qua `onFocusChange`, một cơ chế thay vì hai.
- **D — Tên chương trong Trung tâm thông báo được dịch.** `NotificationInboxView` hiện `record.latestChapterTitle` thô trong khi tên truyện ngay trên nó đã dịch. Thêm `displayedChapterTitle(for:)` với đúng guard của `BookListItemView` (`isTranslationEnabled && containsChinese` rồi mới `translateChapterTitle`), áp cho cả dòng "Mới nhất:" và nhánh dự phòng của `bookTitle`. `NewChapterProbe`/`NewChapterRecord` **không đổi**: chuỗi nguyên văn vẫn được lưu, chỉ chỗ hiển thị dịch.
- **E — Nhấn giữ một kết quả ở màn tìm trong Kệ sách & Lịch sử** mở `BookActionSheet` như Kệ sách: cùng sheet, cùng `BookActionRunner`, cùng bộ sheet/navigation phụ (chi tiết, đổi nguồn, sửa thông tin, tải/xuất, overlay xoá). Chế độ suy ra từ dữ liệu — `book.isOnShelf ? .shelf : .history` — vì danh sách kết quả trộn hai loại. Hàng đổi từ `Button` sang `contentShape` + `onTapGesture` + `onLongPressGesture(0.35)`: bọc `Button` thì nhả tay sau khi giữ vẫn kích hoạt action và mở luôn Reader. Khối hành động ở [`ShelfSearchView+Actions`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfSearchView+Actions.swift) để file gốc không vượt trần (396/400 nếu gộp → **292**).
- **F — VP có dấu (`弹指、遮天`) không bao giờ khớp: nguyên nhân là vị trí trong chuỗi xử lý.** `performTranslation` áp bảng dấu câu (`。．，、；：！？…～—　`) **trước** `tokenize`, nên tới lúc tra trie thì `、` đã thành `", "` — mọi khoá từ điển chứa 1 trong 12 ký tự đó không thể khớp. Bộ nạp từ điển vô can (`TextDictionary`/`DoubleArrayTrie` giữ nguyên mọi ký tự của khoá). Dấu hiệu chéo đã dùng để xác nhận: panel Dịch tokenize chuỗi **gốc** nên nó hiện đúng nghĩa của mục đó, trong khi đọc chương thì không áp. Sửa: bảng thành [`TranslationPunctuationMapper`](../../Sources/Services/Translation/Utils/TranslationPunctuationMapper.swift) và chạy **sau** khi tra từ điển, ngay **trước** `postProcessText` — hai đầu đều bị kẹp: sớm hơn là bug này, muộn hơn là mất viết hoa sau `。` (hàm đó chỉ nhận `.!?:：`) và dư khoảng trắng trước dấu phẩy. `translatedCandidate(for:)` áp cùng bản đồ khi dò span, nếu không token dấu câu không bao giờ dò thấy. Đánh đổi có chủ ý: **nghĩa** từ điển giờ cũng đi qua bảng (`—`→`-`, `…`→`...`, `～`→`~`); và từ nay khoá **được phép** trùm qua dấu câu, nên một entry viết hỏng kiểu `了。=rồi` sẽ bắt đầu có tác dụng và ăn mất dấu kết câu.
- Kèm theo: bỏ `.rotationEffect(.degrees(90))` khỏi icon `ellipsis.circle` ở Reader và Chi tiết truyện (thay đổi có sẵn trong cây làm việc, không phải của lượt này).
- Gate: `check_architecture.py` **8 → 7 violation** — `TTSDictionaryEditView` rời danh sách; `TranslateUtils.swift` 1023 → **968** (baseline 917, vẫn vượt nhưng chỉ đi xuống), không nới baseline nào, không phát sinh vi phạm mới. Hai file chạm trần rồi lùi lại: `ShelfSearchView` 396→292, `CollectionDetailView` 405→354 (**vi phạm thật**, bắt được trước khi commit). `validate_links.py` PASS (16 doc, **487** file) sau khi cập nhật 10 doc.
- **Chưa biên dịch, chưa chạy thử** — host là Windows. Có **4 file Swift mới** nên khi lên macOS **phải** `xcodegen generate`. Việc phải nhìn đầu tiên: một chương có nhiều dấu `。，、` xem chữ có bị dính/mất viết hoa không (việc F đổi đúng chỗ sinh khoảng trắng), và mở "Thêm phiên âm" từ Reader **trong lúc đang nghe TTS** để xác nhận không còn đứng.

## [1.3.335] - 2026-09-04

### Sửa lỗi biên dịch: tách thân ReaderView thành nhiều tầng thuộc tính

Sửa **1** file Swift ([`ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift), 1969 → **1997** dòng, baseline 2053).

- **CI của 1.3.334 đỏ với đúng một lỗi**: `Sources/Views/Reader/ReaderView.swift:350:9: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions`. Không phải lỗi logic: `readerPresentationView` đã là **một** biểu thức dài 330 dòng (`GeometryReader` + `ZStack` 7 con + 21 modifier gồm 6 `sheet`, 2 `fullScreenCover`, 10 `onChange`, `onReceive`, `toolbar`, `background`), và việc thêm `definitionPanelOverlay(in: geometry)` của việc **B** đẩy nó vượt ngân sách suy luận kiểu.
- **Tách theo đúng khuôn đã có trong file** (`readerLifecycleView` → `readerDataObservationView` vốn đã xếp tầng như vậy): thêm 4 thuộc tính + 2 hàm `@ViewBuilder`, mỗi cái là một đơn vị type-check riêng — `readerOverlayStack` (`GeometryReader` + `ZStack` + `.toolbar`), `readerSheetLayer` (4 `sheet`), `readerObserverLayer` (10 `onChange` + `onReceive`), `readerPresentationNavigationLayer` (2 `sheet` + 2 `fullScreenCover` + `background`), cộng `floatingSelectionMenuOverlay(in:)` (50 dòng gọi `ReaderFloatingMenuOverlayView`) và `junkDeleteOverlay(in:)` (54 dòng panel xoá rác). `readerPresentationView` còn đúng một dòng trỏ vào tầng ngoài cùng.
- **Thứ tự áp modifier giữ y nguyên** (`toolbar` → 4 `sheet` → 10 `onChange` + `onReceive` → 2 `sheet` + 2 `fullScreenCover` → `background`) nên cây view sinh ra giống hệt trước khi tách: không đổi hành vi, không đổi mốc vòng đời, không đổi vùng an toàn. Hai overlay rút ra vẫn nhận `GeometryProxy` tường minh vì panel xoá rác đọc `geometry.safeAreaInsets.bottom`.
- **Giữ trong `ReaderView.swift`, không dời sang file `+`**: các tầng này chạm `@State` còn `private` (28/86 khai báo), mà `private` của Swift là phạm vi **file** — dời ra là vỡ ngay. Đây cũng là lớp lỗi đã làm CI 1.3.331 đỏ.
- Gate: `check_architecture.py` giữ **8 violation** cũ (`ReaderView.swift` 1997/2053 dòng, không phát sinh vi phạm mới); `validate_links.py` PASS (16 doc, 483 file) — sửa `08_lifecycle`, `10_risk_report`, `rules.md`, ghi nhận `no-change-needed` cho `04_call_graph`, `11_subsystems`, `13_resource_lifecycle`.
- **Vẫn chưa biên dịch tại chỗ** — host là Windows, `xcodebuild` chỉ chạy trên macOS. Bằng chứng của lượt này là đọc code + hai validator; CI xanh chỉ chứng minh **biên dịch được**. Không thêm/xoá file Swift nên lượt này **không** cần `xcodegen generate`.

## [1.3.334] - 2026-09-04

### Check rule về panel Dịch, gộp tiền tố Google, tải lẻ chương, tách nhóm ghim

Thêm **8** file Swift (477 → **483**), xoá **2**, sửa **18**, cộng `Scripts/check_architecture.py`. Đợt 3 của loạt tối ưu: 8 việc A–H trong một lượt.

- **A — Gộp request Google TTS của cache tiền tố chương sau.** 1.3.332 đã gộp cửa sổ nạp trước của chương *đang đọc*; nay tiền tố *chương sau* cũng đi một request. File mới [`TTSNextChapterPrefixCache+GoogleBatch`](../../Sources/Services/TTS/TTSNextChapterPrefixCache+GoogleBatch.swift) (158 dòng) xếp lượt, [`TTSNextChapterPrefixSynthesizer`](../../Sources/Services/TTS/TTSNextChapterPrefixSynthesizer.swift) (113 dòng, 2 `static func`, **không** giữ state) gọi engine. Cùng ba lớp chặn lệch chỉ số như 1.3.332: chunk rỗng (sau `applyReplacements` + trim) **bị loại khỏi lượt gộp** và đi đường một-request, `googleBatch` throw nếu `audios.count != texts.count`, và việc gán vẫn theo `batchIndices[i]` chứ không phải `offset + i`. Khoá riêng `gbatch|<synthesisKey>|…` nên không đụng không gian khoá của cache từng chunk; `guard batchIndices.count >= 2` để không đánh đổi độ bền lấy con số không có thật; một `nextTaskToken` cho **mọi** index của lượt; `CancellationError` `return` thẳng, còn lỗi thật thì `recoverBatchFailure` xếp lại từng chunk. Retry vẫn **đúng một tầng** — trong `RemoteTTSSynthesisCoordinator`, `TTSManager` không bọc thêm.
- **B — Check rule chuyển hẳn vào panel Dịch, chẩn đoán cả đoạn.** Xoá `ReaderRuleTraceOverlayView.swift` (396 dòng) và `ReaderRuleTraceGuideSheet.swift` (74 dòng, cùng nút `?`). Panel Dịch nhận việc qua ba file mới: [`+Rules`](../../Sources/Views/Reader/ReaderDefinitionOverlayView+Rules.swift) (156 dòng — dải chip, focus, **ô nghĩa rule chỉ đọc** nằm dưới ô nghĩa dịch, ba câu thông báo phân biệt "chưa có rule" / "công tắc đang tắt" / "không rule nào chạm đoạn"), [`+Rows`](../../Sources/Views/Reader/ReaderDefinitionOverlayView+Rows.swift) (164 dòng, dời nguyên trạng để file gốc về dưới baseline), [`ReaderView+DefinitionPanel`](../../Sources/Views/Reader/ReaderView+DefinitionPanel.swift) (107 dòng) + [`ReaderRuleAction`](../../Sources/Views/Reader/ReaderRuleAction.swift) (13 dòng). Nút `+` giữ ở **đầu** dải chip như màn cũ; chiều cao lên `.presentationDetents([.height(660), .large])`. Khác biệt duy nhất so với màn cũ: `focusedRuleRange` = `trace.sourceRange`, tức tô phạm vi **rule chạm được**, không snap về vùng bôi đen — snap là mất ngữ cảnh mà rule thật khớp. Hậu xử lý khi đóng nằm ở `.onChange(of: showingDefinitionSheet)` chứ không ở `closeDefinitionPanel()`, vì kéo xuống và tap ra ngoài chỉ hạ binding `isPresented`. Tầng Services **không đổi một dòng**: `QuickTranslationRuleDiagnostics` vẫn là bộ soi duy nhất.
- **C — Nút "Rule" trên menu bôi đen thành nút "Tìm"** (`function`/"Rule" → `magnifyingglass`/"Tìm"), mở Google Search cho cụm đang bôi đen (`searchSelectionOnGoogle()`). Đổi tên callback `onInspectRules` → `onSearchWeb` ở cả hai đầu để không còn tên gợi sai việc.
- **D — Sheet ấn giữ truyện bỏ hai hàng "Xem chi tiết" và "Ghim".** Thay bằng cử chỉ trên header: tap → xem chi tiết, ấn giữ (0.4 s) → ghim/bỏ ghim. `.onTapGesture` phải đăng ký **trước** `.onLongPressGesture`, nếu không một cú tap nhanh bị đọc thành ấn giữ. `headerHint` có 4 nhánh nên người dùng biết header đang làm được gì (truyện local không có màn chi tiết, mục lịch sử không ghim được).
- **E — Tách ghim và không ghim thành hai section riêng** ở cả tab Kệ Sách và màn bộ sưu tập: "Đang ghim" (`pin.fill`, cam) và "Truyện khác". Phân trang **chỉ** áp lên nhóm không ghim nên truyện ghim luôn thấy được mà không cần cuộn; chưa ghim gì thì không bọc section nào.
- **F — Đồng bộ icon dropdown**: Reader và Chi tiết truyện đổi `ellipsis` → `ellipsis.circle` cho khớp Kệ sách. Đúng hai dòng.
- **G — Nút tải cho từng chương trong danh sách chương**, chỉ hiện ở chương **chưa** tải, có `ProgressView` xoay khi đang tải. `ReaderChapterListView` tách ba (468 → **295**): file gốc, [`+List`](../../Sources/Views/Reader/Extensions/ReaderChapterListView+List.swift) (179 dòng), [`+Download`](../../Sources/Views/Reader/Extensions/ReaderChapterListView+Download.swift) (74 dòng). Ba trạng thái của hàng dùng **cùng một** khung 30×30 (`ReaderChapterRowView.trailingAccessory`) để hàng không giật khi đổi trạng thái. Nút này **mồi cache** qua `ChapterContentRepository.load(forceRefresh: false)` + `ChapterStore.markCached`, **không** tạo `DownloadTaskModel` và không vào hàng đợi `BookDownloadWorker`; nó cố ý không đi qua `ReaderViewModel.loadChapterContentFromExtension` vì đường đó còn dịch chương và dựng `[ParagraphItem]`. `Task` không giữ handle nên **không huỷ được** — đúng luật "nội dung đã qua checkpoint cancel cuối thì lệnh ghi nền không được cancel", hệ quả là toast có thể hiện sau khi danh sách đã đóng.
- **H — Trả nợ hai vi phạm `VIEW_SWIFTDATA_MUTATION` cuối cùng.** `ReaderView.initializeReaderIfNeeded` và `BookDetailView.task(id:)` từng gọi `BookTitleTranslationMigrator.refreshTranslations(for:)` (gán thẳng `titleTrans`/`authorTrans` của `@Model`) rồi tự `try? modelContext.save()`; nay đi qua `BookTransactionCoordinator.refreshTitleTranslations(bookId:in:)` và **xử lý `Result`**. Migrator hạ xuống vai "chỉ gán, trả `Bool` didChange"; coordinator `save()` **chỉ khi** có field đổi nên mở truyện không còn mở transaction rỗng. `BookDetailView` tra `localBook` bằng `detailUrl` + `extensionPackageId` nên nó truyền `localBook?.bookId`. Còn `DiscoveryView` là **báo oan**: `self.currentChapterIndex = …` là `@State` của chính struct View — sửa regex ở [`check_architecture.py:144`](../../Scripts/check_architecture.py) bằng lookbehind `(?<!\bself)`, mọi `<biến khác>.currentChapterIndex = …` vẫn bị bắt.
- Gate: `check_architecture.py` **12 → 8 violation** — hết hẳn `VIEW_SWIFTDATA_MUTATION`, 8 chỗ còn lại đều là nợ dòng cũ. Hai baseline `ReaderChapterListView` (408) và `ReaderDefinitionOverlayView` (468) **cố ý giữ nguyên** dù file đã về 295/372, nên có ~200 dòng dư — không phải chỗ để tiêu. `validate_links.py` PASS (16 doc, **483** file) sau khi cập nhật 15 doc; `03_type_graph` không đụng.
- **Chưa biên dịch, chưa chạy thử** — host là Windows. Có **8 file Swift mới** nên khi lên macOS **phải** `xcodegen generate`. Việc phải nghe/nhìn đầu tiên: mở chương mới ngay sau khi tiền tố nạp xong (kiểm câu đầu chương có đúng câu đầu không) và panel Dịch trên máy màn nhỏ (660pt có thể chạm trần khi bật cỡ chữ trợ năng lớn). Headroom cần nhớ: [`BookDetailView.swift`](../../Sources/Views/BookDetail/BookDetailView.swift) đang **1199/1201** — file chật nhất repo, lần sửa sau ở đó phải tách file trước.

## [1.3.333] - 2026-09-04

### Sửa lỗi biên dịch: withUnsafeBytes trong extension Data khớp instance method

Sửa **1** file Swift ([`TTSBatchAudioPayload.swift`](../../Sources/Services/TTS/TTSBatchAudioPayload.swift), 67 → **80** dòng).

- **CI của 1.3.332 đỏ với đúng một lỗi**: `TTSBatchAudioPayload.swift:57: error: use of 'withUnsafeBytes' refers to instance method rather than global function 'withUnsafeBytes(of:_:)' in module 'Swift'`. Trong một `extension Data`, tên `withUnsafeBytes` không qualify **luôn** khớp vào `Data.withUnsafeBytes(_:)` chứ không phải hàm toàn cục `Swift.withUnsafeBytes(of:_:)` — hai hàm khác signature nên lỗi nổ ngay chỗ gọi.
- **Không chữa bằng cách viết `Swift.withUnsafeBytes(...)`**, mà bỏ hẳn con trỏ: `append(uint32:)` lắp 4 byte bằng dịch bit, `readUInt32(at:)` đọc 4 byte rồi ghép lại. Đổi lại được ba thứ cùng lúc — hết bẫy phân giải tên, hết phụ thuộc endianness của máy (khung là little-endian **tường minh** ở cả hai chiều), và không còn `loadUnaligned` để phải nghĩ về alignment.
- Thêm magic `"FBT1"` vào đầu khung (đã có từ 1.3.332) được ghi rõ trong doc: một `Data` không phải khung — ví dụ blob mp3 lọt vào đường gộp — bị `decode` từ chối ngay thay vì trả ra rác.
- Bài học: hàm toàn cục trùng tên với method của type đang `extension` là lớp lỗi mà cả `check_architecture.py` lẫn `validate_links.py` đều không thấy; chỉ `xcodebuild` bắt.
- Gate: `check_architecture.py` giữ **12 violation**, `validate_links.py` PASS.



### Gộp request Google TTS, chuyển phạm vi rule, đảo thứ tự tab kệ sách

Thêm **3** file Swift (474 → **477**), sửa **7**. Đợt 2 của loạt tối ưu, cộng ba việc lẻ.

- **Đo API trước khi viết code.** Chạy thử thật với key của người dùng trên endpoint `readaloud.googleapis.com/v1:generateAudioDocStream`: `textParts` **nhận mảng**, và phản hồi là `[{metadata}, {text}, {audio}, {text}, {audio}, …]` — một cặp `text`+`audio` cho **mỗi** part, đúng thứ tự. Kiểm ánh xạ bằng 3 part dài 4/64/130 ký tự → audio 4128/20352/33408 byte, tăng đúng thứ tự; `metadata.fullText` + `textLocation.offset` cho phép đối chiếu tường minh. Số đo: 1 đoạn **370 ms**, 5 đoạn tuần tự 1469 ms, **5 đoạn/1 request 655 ms**, **10 đoạn 735 ms** (~5×), **20 đoạn 559 ms** (~13×) — độ trễ bị chi phối bởi một lần round trip, gần như không phụ thuộc số part.
- **Cái bẫy đã đo được: part rỗng bị API bỏ im lặng.** Gửi `["Câu một", "", "Câu ba"]` chỉ nhận **2** audio và `metadata.textParts` cũng chỉ có 2 mục ⇒ lập chỉ mục theo vị trí sẽ **lệch một nhịp** và mọi đoạn sau đó nghe sai đoạn. Chặn ba lớp: `makeGoogleBatch` loại text rỗng trước khi gửi (những index đó đi đường một-đoạn), `synthesizeBatch` từ chối part rỗng, và **bắt buộc** `audios.count == parts.count` — không khớp thì `throw` để rơi về đường cũ.
- **Chỉ cửa sổ nạp trước được gộp.** Đoạn đang chờ nghe giữ nguyên một request riêng: 370 ms một mình vẫn nhanh hơn chờ một batch lớn, và đó là chỗ người dùng đang đợi. File mới [`TTSManager+RemoteBatchPrefetch`](../../Sources/Services/TTS/Extensions/TTSManager+RemoteBatchPrefetch.swift) (205 dòng) là chủ sở hữu duy nhất của việc xếp hàng nạp trước remote; `updatePrefetchWindow` từ 26 dòng còn 12 nên `TTSManager.swift` **giảm** 4015 → 4001.
- **Lượt gộp vẫn là một job của `RemoteTTSSynthesisCoordinator`** nên bất biến "một lượt tổng hợp remote tại một thời điểm" không bị nới. Vì job của coordinator chuyển đúng kiểu `Data`, nhiều blob mp3 đi qua khung nhị phân của file mới [`TTSBatchAudioPayload`](../../Sources/Services/TTS/TTSBatchAudioPayload.swift) (`[magic][count][len]×n[bytes]…`) thay vì đổi actor đó thành generic — sửa nó là chạm vào dedupe/huỷ/telemetry đang chạy đúng.
- **Dọn task nạp trước đổi từ "theo index" sang "theo định danh task".** Một task gộp được ghi vào `prefetchTasks` cho **mọi** index nó phục vụ; cửa sổ trượt một nhịp là index cũ nhất rơi ra, và cách huỷ cũ sẽ giết luôn phần đang cần cho các đoạn còn lại. `pruneRemotePrefetchTasks(keeping:)` chỉ huỷ task không còn phục vụ index nào trong cửa sổ.
- **`GoogleTTSService` tách lại thành ba phần** — `makeRequest` (nhận `String` hoặc `[String]`), `audioParts(from:)` trả **mọi** audio thay vì `.first`, và `withRetry` dùng chung cho cả hai đường (retry vẫn **đúng một tầng**, 2 lượt). Đường một-đoạn giữ nguyên hành vi: nó là `.first` của cùng một parser. Lượt đo thử gặp một **503 UNAVAILABLE** thật nên fallback không phải phòng xa: lỗi gộp thì `fallbackToPerParagraphPrefetch` xếp lại từng đoạn.
- **Ext TTS không gộp được** và đó là do API: `execute(text, voice)` của JavaScript nhận một đoạn mỗi lần. `dispatchRemotePrefetch` vì vậy chỉ rẽ nhánh gộp khi `tool == "google"`.
- **Chip Check rule thêm "Chuyển sang bộ chung / bộ riêng của truyện".** `RuleAction.moveScope` + `moveRule(_:to:)`: ghi ở đích **rồi** xoá ở nguồn. Thứ tự đó là có lý do — lỗi giữa đường thì rule người dùng tự viết vẫn còn, và nếu xoá thất bại thì toast nói thẳng "rule đang ở cả hai nơi" chứ không im lặng. `QuickTranslationRuleTransfer.copy` **giữ nguyên** ngữ nghĩa copy vì nút Chuyển của từ điển dùng chung nó.
- **Thứ tự tab Kệ sách: Downloads → Bộ Sưu Tập → Kệ Sách → Lịch Sử.** Kèm file mới [`ShelfTab`](../../Sources/Views/Shelf/ShelfMain/ShelfTab.swift) — số tab là hợp đồng liên màn (`SearchView` gửi qua `userInfo["shelfTab"]`), trước đây cả hai đầu viết số trần nên đảo thứ tự là đổi ngầm nghĩa của payload. Nay bên gửi dùng `rawValue`, bên nhận ép qua `ShelfTab(rawValue:)` và **bỏ qua** số lạ. `ShelfView.swift` giảm 780 → 772.
- Gate: `check_architecture.py` giữ **12 violation** (cùng một tập). `validate_links.py` PASS (16 doc, 477 file) sau khi cập nhật 8 doc và ghi `--no-change-needed` cho 4 doc. **Chưa biên dịch, chưa nghe thử** — host là Windows; có **3 file Swift mới** nên khi lên macOS **phải** chạy `xcodegen generate`. Lưu ý headroom: `ReaderRuleTraceOverlayView.swift` **396/400** dòng và **không có baseline** — lần sửa sau ở file đó phải tách file.
- **Chưa làm trong lượt này**: gộp Check rule vào màn Dịch (hình dạng UI còn hai cách hiểu, và `ReaderDefinitionOverlayView` đang 489/468 nên phải tách file trước), và `timingInfo` của phản hồi Google (mốc thời gian **theo từng từ** — cho thời lượng chính xác từng đoạn và bôi sáng theo từ, hiện chưa dùng gì).



### Sửa lỗi biên dịch: startBackgroundRemainingPagesLoading là private

Sửa **1** file Swift ([`BookDetailView.swift`](../../Sources/Views/BookDetail/BookDetailView.swift), 1 từ khoá).

- **CI của 1.3.330 đỏ với đúng một lỗi**: `BookDetailView+ShelfPlacement.swift:28: error: 'startBackgroundRemainingPagesLoading' is inaccessible due to 'private' protection level`. Nguyên nhân là bẫy cũ của repo: `private` trong Swift là phạm vi **file**, nên hàm đó không nhìn được từ file `+ShelfPlacement` mới tách ở 1.3.328. Đổi `private` → `internal`, đúng khuôn mọi member mà `BookDetailView` chia sẻ với các file `+` của nó (`createBookOnShelf`, `tocPages`, `remainingPagesLoaded`… đều đã `internal`).
- Đã soát lại **toàn bộ** symbol mà `BookDetailView+ShelfPlacement.swift` dùng (`localBook`, `modelContext`, `detailErrorMessage`, `createBookOnShelf`, `tocPages`, `remainingPagesLoaded`, `collectionPickerBook`): tất cả đã `internal`, không còn chỗ nào hở.
- Bài học ghi lại cho lượt sau: tách một hàm sang file `X+Feature.swift` thì phải kiểm access level của **mọi** thứ nó gọi, không chỉ của chính nó — `check_architecture.py` và `validate_links.py` đều không bắt được lớp lỗi này, chỉ `xcodebuild` bắt.
- Gate: `check_architecture.py` giữ **12 violation**, `validate_links.py` PASS.



### Cache script Ext TTS, cooldown làm mới kho, cache icon tiện ích

Thêm **3** file Swift (471 → **474**), sửa **8**. Đợt 1 của loạt tối ưu Google TTS / Ext TTS / tab Tiện Ích.

- **Ext TTS: mỗi đoạn văn từ 6 lần I/O xuống 2 lần `stat()`.** Trước lượt này, cứ 2–4 giây một lần suốt cả truyện, `ExtensionManager.ttsGenerate` **và** `getTTSRuntimeFingerprint` cộng lại làm **4 lần đọc `plugin.json` + 2 lần đọc trọn `tts.js` + 4 lần parse JSON + 2 lần serialize** — tất cả cho ra cùng một kết quả. `getTTSRuntimeFingerprint` cũ còn đọc script **trước** khi tra cache nên cache chỉ tiết kiệm SHA256, không tiết kiệm I/O. File mới [`ExtTTSScriptCache`](../../Sources/Services/TTS/Ext/ExtTTSScriptCache.swift) (128 dòng) giữ `scriptContent` + config đã trộn + fingerprint, hết hạn theo `(configJson, modDate của plugin.json, modDate của script)`. Phải canh cả `plugin.json` vì nó quyết định *tên* file script.
- **`ExtTTSRuntime.Identity` so fingerprint thay vì so cả chuỗi script.** Cùng độ phân giải (fingerprint băm script + config + đường dẫn) nhưng bỏ được phép so O(len(script)) mỗi đoạn. `resetTTSRuntime()` gọi `invalidateAll()` **trước** `ttsRuntime.reset()` — đảo lại là để hở khe dựng executor mới bằng payload cũ.
- **Bỏ khe hở lệch fingerprint/nội dung**: hai lối vào đọc đĩa riêng nghĩa là một lần cài lại đúng giữa hai lần đọc sẽ tạo `synthesisKey` của bản cũ nhưng chạy bản mới, tức audio sai bị cache dưới khoá đúng. Giờ cả hai lấy từ một `Payload`.
- **Xoá đường PCM chết của Ext TTS** — `ExtTTSService.swift` **230 → 65** dòng. `synthesize(...targetFormat:)` (102 dòng), `preprocessBufferForExtTTS` (45) và bộ theo dõi file tạm (`activeTempFiles`/`tempFileLock`/`cleanupTempFile`/`cleanupAllTempFiles`) **không có caller nào** trong `Sources/` — đã grep toàn cây. Bản cũ còn mang lỗi thật: `preprocessBufferForExtTTS` chạy **hai lần** trên cùng buffer (input block của converter rồi output), tức chuẩn hoá biên độ và fade áp đôi. Kéo theo `TTSManager.cleanUpTempFile()` (hàm **rỗng** còn được gọi ở 3 chỗ) và nhánh gọi `cleanupAllTempFiles()` ở `TTSManager+PrefetchCache`. Ext TTS giờ không tạo file nào, `@unchecked Sendable` → `Sendable`.
- **Tab Tiện Ích không còn quét mạng mỗi lần mở.** `.onAppear` gọi `refreshAllRepositories()` vô điều kiện, mà một lượt làm mới là 1 request registry cho **mỗi kho** cộng một request `plugin.json` cho **mỗi tiện ích chưa cài** (`ExtensionSyncCommandBuilder`, 6 luồng, timeout 10 s) — kho 100 tiện ích mà máy cài 5 là ~95 request. File mới [`RepositoryRefreshPolicy`](../../Sources/Services/Extensions/Manager/RepositoryRefreshPolicy.swift) (cooldown mặc định 6 giờ, `UserDefaults`) chặn lượt **tự động**; nút refresh trên toolbar gọi `force: true` nên **không** qua cửa. `markRefreshed()` chỉ ghi khi ≥ 1 kho cập nhật được — một lượt trắng vì mất mạng không khoá 6 giờ tiếp theo.
- **`filteredExtensions` tính một lần mỗi lượt vẽ thay vì 3 lần.** Thanh đếm, nhánh `isEmpty` và `List` trước đây gọi riêng, mỗi lần là 4 vòng `filter` + một `sorted` dùng `localizedCompare` (so sánh chuỗi đắt nhất trong Foundation) — nhân với **từng ký tự** gõ vào ô tìm kiếm. `filterStatusBar` đổi thành `filterStatusBar(count:)`.
- **Icon extension có cache** — file mới [`ExtensionIconImageCache`](../../Sources/Views/Common/ExtensionIconImageCache.swift), khoá `(đường dẫn icon.png, modDate)`, **ghi nhớ cả trường hợp không có ảnh**. `UIImage(contentsOfFile:)` không dùng cache dùng chung của UIKit (chỉ `UIImage(named:)` có), nên mỗi lượt SwiftUI dựng lại một dòng là một lần đọc đĩa + giải mã PNG — và `ExtensionIconView` nằm trong **mọi** dòng Kệ sách, Khám phá, mục lục Reader. Đây là phần lan ra ngoài tab Tiện Ích.
- **Hàng ở tab Tiện Ích đổi `AsyncImage` → `ExtensionIconView`**: đọc `icon.png` cục bộ trước rồi mới ra mạng, nên tiện ích đã cài không tải icon lần nào và hiện đúng cả khi offline. Giữ nguyên fallback theo loại (`waveform` cho TTS, `book.closed` cho truyện) cho hàng không có cả `localPath` lẫn `iconUrl`.
- **Google TTS**: `validVoiceIds` và key nhúng trong `Info.plist` thành `static let` (trước đây mỗi lượt tổng hợp dựng lại `Set` và tra `Bundle`). Key **cá nhân** của người dùng vẫn đọc `UserDefaults` mỗi lần vì đổi được ngay trong Cài đặt.
- Gate: `check_architecture.py` **13 → 12 violation** — `ExtensionManager.swift` 1049 → **1015** ≤ baseline 1022 nhờ dời phần băm sang cache, không violation mới nào. `validate_links.py` PASS (16 doc, 474 file) sau khi cập nhật 11 doc và ghi `--no-change-needed` cho 2 doc. **Chưa biên dịch, chưa nghe thử** — host là Windows; có **3 file Swift mới** nên khi lên macOS **phải** chạy `xcodegen generate`. Việc gộp nhiều đoạn vào một request Google (đã đo được 5–13× trên máy này) để **đợt 2**.


## [1.3.329] - 2026-09-03

### Thông báo chương mới không mất khi đánh dấu đã đọc, ẩn nút tải rule mặc định khi đã có rule

Sửa **5** file Swift; không thêm/xoá file nào.

- **Nguyên nhân dòng thông báo biến mất: "có chương mới" và "dòng trong Trung tâm thông báo" dùng chung một con số.** `NewChapterRecord.markSeen()` đưa `newChapterCount` về 0 và `firstFoundAt` về `nil`, còn `NotificationInboxView` lọc dòng bằng `hasNew` ⇒ bấm vào dòng (hoặc mở truyện từ kệ) là dòng mất. Giữ lại con số cũ cũng không đủ: `NewChapterProbe.applyDiff` **luôn** ghi lại `newChapterCount` ở mọi lượt dò, nên lượt kiểm tra kế tiếp sẽ xoá nó lần nữa.
- **Tách hai thứ ra**: [`NewChapterRecord`](../../Sources/Services/NewChapters/NewChapterRecord.swift) thêm nhóm `announced*` (`announcedChapterCount`, `announcedIsCountExact`, `announcedAt`, `announcementReadAt`) là **thông báo đã phát**, sống độc lập với `newChapterCount` là **trạng thái badge**. Probe gọi `announceCurrentFinding()` khi tìm ra chương mới; `markSeen()` cố ý **không** đụng nhóm này, chỉ thêm `markAnnouncementRead()`.
- **Badge giữ nguyên hành vi**: `hasNew`, `totalNewBooks`, `NewChapterBadgeView` vẫn đọc `newChapterCount` nên badge kệ sách và badge chuông vẫn tắt ngay khi đánh dấu đã đọc — không call site nào ở tầng View phải sửa. Đây là lý do chọn thêm field thay vì đổi nghĩa `hasNew`.
- **Luật một đợt thông báo**: đợt mới (chưa có thông báo, hoặc thông báo trước **đã đọc**) mở một dòng chưa đọc lấy mốc `firstFoundAt`; đợt đang chờ đọc mà dò thêm được chương thì chỉ cập nhật con số và giữ nguyên mốc phát hiện đầu tiên. Đọc rồi mà có thêm chương ⇒ nổi lên lại như thông báo mới; ba lượt kiểm tra trong cùng một đợt ⇒ vẫn một dòng.
- **Trung tâm thông báo đối xử hai loại nội dung như nhau**: dòng chương mới có dấu chấm chưa đọc, icon đổi `bell.badge.fill` → `bell` khi đã đọc, swipe để xoá, và "Xoá thông báo đã đọc" nay dọn **cả** toast lẫn dòng chương mới. Xoá một dòng chỉ gọi `clearAnnouncement()` chứ **không** xoá record — record giữ mốc `seen*`, xoá nó là lượt dò sau báo lại từ đầu như truyện mới.
- **Vá dữ liệu của bản cũ**: `loadIfNeeded()` chạy `backfillAnnouncements()` dựng thông báo từ `newChapterCount` đã lưu, nếu không thì người vừa cập nhật thấy badge sáng mà Trung tâm thông báo trống. Chạy được vì `NewChapterRecord.init(from:)` vốn `decodeIfPresent` mọi khoá.
- **`markAllAnnouncementsRead()` gộp một lần ghi đĩa** thay cho vòng lặp gọi `markSeen` từng truyện của "Đánh dấu đã đọc hết" (trước đây là N lần ghi file). Vòng lặp chụp `Array(records.values)` trước khi sửa dictionary.
- **Ẩn nút "Tải bộ rule mặc định" khi `ruleCount > 0`** ([`QuickTranslationRulesView`](../../Sources/Views/Settings/Translation/QuickTranslationRulesView.swift)). Nút đó ghi **đè** bộ đang chạy và màn này không có undo, nên với người đã sửa/nhập bộ riêng thì đó là một cú mất dữ liệu cách đúng một lần bấm. Không tạo đường cụt: "Xoá bộ rule khỏi máy" đưa `ruleCount` về 0 và nút hiện lại, "Nhập file rule (.txt)" vẫn luôn có, footer đổi chữ để nói rõ vì sao nút biến mất. Điều kiện là `ruleCount == 0` chứ không phải `!isLoaded` — `makeStatus` đặt `isLoaded = true` cho mọi snapshot kể cả file phân tích ra 0 rule, đúng lúc người dùng cần tải lại nhất.
- Gate: `check_architecture.py` giữ **13 violation** (cùng một tập, không có mục nào mới); `validate_links.py` PASS sau khi cập nhật `11_subsystems.md`. **Chưa biên dịch** — host là Windows, không có `xcodebuild`; không file Swift nào được thêm/xoá nên **không** cần `xcodegen generate`.
