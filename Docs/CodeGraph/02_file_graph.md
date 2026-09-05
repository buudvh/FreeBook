---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 4
---

# Đồ thị File & Quan hệ Import (File & Import Graph)

Tài liệu này chi tiết hóa toàn bộ các mối quan hệ phụ thuộc giữa 218 file mã nguồn Swift trong dự án FreeBook, tách biệt rõ ràng giữa Import Graph và Dependency Graph cho từng tệp.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## +1 file quét script; ba file phân hệ debug mở rộng (1.3.348)

| File | Nội dung | Dòng |
| --- | --- | --- |
| [`Services/Extensions/Debug/ExtensionDebugScriptScanner.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugScriptScanner.swift) | **mới** — quét gốc + `src/` tìm mọi `.js` có `execute`; đọc tối đa 256 KiB mỗi file | 55 |
| [`Services/Extensions/Debug/Staging/ExtensionDraftInstaller.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftInstaller.swift) | `markNewInstall` / `isDebugNewInstall` / `uninstallNewInstall`; `installNew` đánh dấu ở nhánh tạo mới | 205 → **250** |
| [`Services/Extensions/Debug/Server/ExtensionDebugCommandRouter+Draft.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter+Draft.swift) | rollback hai nhánh + `deleteLibraryRow` | 307 → **372** |
| [`Services/Extensions/Debug/Server/ExtensionDebugInstalledSnapshot.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugInstalledSnapshot.swift) | thêm `executableScripts` | 43 → **51** |
| [`Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift) | `ExtensionInfo.executableScripts` (mặc định rỗng ⇒ không phá client cũ) | 123 → **136** |

Client VSCode: `protocol.ts` khai `executableScripts?`, `extension.ts` đưa script quét được vào danh sách chọn Entrypoint. Thêm file Swift mới ⇒ máy macOS phải `xcodegen generate`.
## +1 file ở phân hệ debug; router ngắn đi (1.3.347)

| File | Vai trò | Dòng |
| --- | --- | --- |
| [`Services/Extensions/Debug/Server/ExtensionDebugEntrypointResolver.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugEntrypointResolver.swift) | **mới** — phân giải `payload` của `run.start` thành entrypoint, tách "tên lạ" khỏi "thiếu tham số" | 57 |
| [`Services/Extensions/Debug/Server/ExtensionDebugCommandRouter.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter.swift) | bỏ `entrypoint(from:)` (31 dòng) sang file trên, thêm switch ba nhánh ở `handleRunStart` | 357 → **343** |

Thêm file Swift mới ⇒ máy macOS phải `xcodegen generate` trước khi build.
## +7 file: hai tầng thuần trên đường dịch, năm khối UI Kệ sách (1.3.339)

| File mới | Vai trò | Dòng |
| --- | --- | --- |
| [`Services/Translation/Utils/TranslationTextPostProcessor.swift`](../../Sources/Services/Translation/Utils/TranslationTextPostProcessor.swift) | thân cũ của `postProcessText`, 4 regex thành `static let` (biên dịch một lần thay vì mỗi token) | 74 |
| [`Services/Translation/Utils/TokenizeMemo.swift`](../../Sources/Services/Translation/Utils/TokenizeMemo.swift) | `NSCache` 512 entry cho `VietPhraseTokenizer.tokenize`, khoá mang generation nên không cần ai `clear()` | 63 |
| [`Views/Shelf/ShelfMain/ShelfTabSelectorView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfTabSelectorView.swift) | hàng nút rời: 2 nút icon 40×40 + 2 pill chữ, màu semantic | 87 |
| [`Views/Shelf/ShelfMain/HistoryDayGrouper.swift`](../../Sources/Views/Shelf/ShelfMain/HistoryDayGrouper.swift) | gom `[Book]` thành từng ngày trong một pass, nhãn "Hôm nay"/"Hôm qua"/`dd/MM/yyyy` | 67 |
| [`Views/Shelf/Collections/CollectionCoverMosaicView.swift`](../../Sources/Views/Shelf/Collections/CollectionCoverMosaicView.swift) | ảnh ghép bìa 0/1/2/≥3 quyển + badge "còn N truyện" | 83 |
| [`Views/Shelf/Collections/CollectionGridCardView.swift`](../../Sources/Views/Shelf/Collections/CollectionGridCardView.swift) | một thẻ trong grid + `previewBooks` chọn 3 bìa bằng một pass | 74 |
| [`Views/Shelf/Collections/CollectionsReorderSheet.swift`](../../Sources/Views/Shelf/Collections/CollectionsReorderSheet.swift) | sheet `List` + `onMove` cho việc sắp xếp lại | 55 |

| File sửa | Nội dung | Dòng |
| --- | --- | --- |
| [`Services/Translation/Utils/TranslateUtils.swift`](../../Sources/Services/Translation/Utils/TranslateUtils.swift) | `postProcessText` còn một dòng forward; thân + 4 regex dời sang file mới | 968 → **934** |
| [`Services/Translation/Engine/VietPhraseTokenizer.swift`](../../Sources/Services/Translation/Engine/VietPhraseTokenizer.swift) | `tokenize` thành cửa vào có memo, thân cũ thành `tokenizeUncached`; 2 vòng `first(where:)` → `nextStartTable` + 2 bảng theo chỉ số | 284 → **345** |
| [`Models/Dictionaries/TextDictionary.swift`](../../Sources/Models/Dictionaries/TextDictionary.swift) | `maxWordLength` → `keyLengthsDescending` (chỉ thử độ dài khoá có thật), đếm theo UTF-16 | 185 → **191** |
| [`Services/Translation/Engine/QuickTranslationRuleIssue.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleIssue.swift) | `unusedCapture`: `hard` → `warning` | 72 → **76** |
| [`Services/Translation/Engine/QuickTranslationRuleCompiler.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleCompiler.swift) | đổi câu message của issue đó | 319 |
| [`Views/Settings/Translation/QuickTranslationRuleTokenPaletteView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTokenPaletteView.swift) | `ScrollView` ngang → `FlowLayout`, chia 2 nhóm | 111 → **133** |
| [`Views/Shelf/Collections/CollectionsTabView.swift`](../../Sources/Views/Shelf/Collections/CollectionsTabView.swift) | `List` → `ScrollView` + `LazyVGrid`; bỏ `listView`/`collectionRow`/`swipeActions`/`editMode`; thêm ô tạo mới + sheet sắp xếp | 220 → **243** |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | `Picker` → `ShelfTabSelectorView`; `historyTabView` nhóm theo ngày + tách `historyBookRow` | 842 → **856** |
| [`Views/Shelf/ShelfMain/ShelfTab.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfTab.swift) | `iconName`, `isIconOnly` | 38 → **52** |
| [`Views/Reader/Extensions/ReaderView+RuleTools.swift`](../../Sources/Views/Reader/Extensions/ReaderView+RuleTools.swift) | `refreshRuleTraces` debounce 150 ms + `Task.detached` | 327 → **348** |
| [`Views/Reader/Extensions/ReaderView+Selection.swift`](../../Sources/Views/Reader/Extensions/ReaderView+Selection.swift) | bỏ tokenize lại cả đoạn khi chỉ vùng chọn đổi; làm mới chip rule theo vùng chọn | 200 → **217** |
| [`Views/Reader/Extensions/ReaderViewModel+Translation.swift`](../../Sources/Views/Reader/Extensions/ReaderViewModel+Translation.swift) | `scope` được đọc: bỏ qua thay đổi của truyện khác | 254 → **269** |
| [`Views/Reader/ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift) | 2 `@State` mới (`ruleTracesTask`, `translationTokensSource`) | 1997 → **2001** |
| [`Views/Reader/ReaderView+DefinitionPanel.swift`](../../Sources/Views/Reader/ReaderView+DefinitionPanel.swift) | cập nhật bất biến trong doc (nay được cài thật) | 110 → **112** |

## +6 file: cấu hình thứ tự ưu tiên rule và cấu hình engine riêng theo truyện (1.3.338)

| File mới | Vai trò | Dòng |
| --- | --- | --- |
| [`Services/Translation/Engine/QuickTranslationRulePriorityConfiguration.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRulePriorityConfiguration.swift) | `Key` (4 tiêu chí xếp lại được) + `Preset` (3 bộ dựng sẵn) + `Configuration` bất biến có `signature` cho khoá cache; 2 khoá UserDefaults cho phạm vi chung | 203 |
| [`Services/Translation/Engine/QuickTranslationBookEngineConfigStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationBookEngineConfigStore.swift) | chủ `translate/books/<bookId>/QuickTranslateEngineConfig.json`; phân giải thứ tự ưu tiên + 10 token theo `bookId` với ngữ nghĩa kế thừa; cache RAM + `NSLock` | 240 |
| [`Views/Settings/Translation/QuickTranslationRulePriorityListView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulePriorityListView.swift) | các section dùng chung: 3 preset + 2 hàng khoá + 4 hàng kéo được (`onMove`), mỗi hàng bấm để đổi chiều | 126 |
| [`Views/Settings/Translation/QuickTranslationRulePrioritySettingsView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulePrioritySettingsView.swift) | màn phạm vi **chung**, vào từ section Công cụ của `QuickTranslationRulesView` | 33 |
| [`Views/Reader/ReaderBookRulePriorityView.swift`](../../Sources/Views/Reader/ReaderBookRulePriorityView.swift) | màn phạm vi **truyện**: công tắc "Đặt riêng" + cùng bộ section | 57 |
| [`Views/Reader/ReaderBookTokenSettingsView.swift`](../../Sources/Views/Reader/ReaderBookTokenSettingsView.swift) | 10 token × 3 trạng thái (`Chung`/`Bật`/`Tắt`) cho riêng một truyện | 121 |

| File sửa | Nội dung | Dòng |
| --- | --- | --- |
| [`Services/Translation/Engine/QuickTranslationRuleEngine.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleEngine.swift) | `Found.metric(for:)`; `select(from:priority:)`; `rewrite`/`preview` phân giải cấu hình theo `bookId` và ghép `priority.signature` vào khoá memo | 293 → **347** |
| [`Services/Translation/Engine/QuickTranslationRuleTokenSettings.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleTokenSettings.swift) | `Kind.label` + `Kind.isNumeralGroup` để hai màn token dùng chung một danh sách nhãn | 68 → **93** |
| [`Services/Translation/Engine/QuickTranslationRuleDiagnostics.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDiagnostics.swift) | dùng cùng bản chụp `tokenConfiguration` + `priority` theo `bookId` khi gọi `select` | 219 → **223** |
| [`Views/Reader/ReaderSettingsView.swift`](../../Sources/Views/Reader/ReaderSettingsView.swift) | nhận `bookId`; 2 hàng mới + 2 sheet lồng bọc `NavigationStack` | 182 → **257** |
| [`Views/Settings/Translation/QuickTranslationRulesView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulesView.swift) | 1 `NavigationLink` mới ở section Công cụ | 322 → **326** |
| [`Views/Reader/ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift) | truyền `bookId` vào `ReaderSettingsView` (giữ nguyên số dòng, file đang trong baseline) | 1997 |

## +4 file: bảng dấu câu, sheet phiên âm, khối quản lý bộ, khối hành động màn tìm kiếm (1.3.336)

483 → **487** file Swift ⇒ phải `xcodegen generate` khi lên macOS.

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Views/Settings/TTS/AddWordSheet.swift`](../../Sources/Views/Settings/TTS/AddWordSheet.swift) | sheet thêm phiên âm; dựng gợi ý trong `Task.detached`, `body` chỉ đọc `@State` | 202 |
| [`Views/Shelf/ShelfMain/Extensions/ShelfSearchView+Actions.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfSearchView+Actions.swift) | sheet/navigation phụ + chuyển `BookSheetAction` → `BookActionRunner` cho màn tìm kiếm | 118 |
| [`Services/Translation/Utils/TranslationPunctuationMapper.swift`](../../Sources/Services/Translation/Utils/TranslationPunctuationMapper.swift) | bảng dấu câu Trung → Latin, áp **sau** khi tra từ điển | 98 |
| [`Views/Shelf/Collections/CollectionDetailView+Manage.swift`](../../Sources/Views/Shelf/Collections/CollectionDetailView+Manage.swift) | menu `ellipsis.circle` + đổi tên + xoá bộ sưu tập | 68 |

* **Ba trong bốn file sinh ra vì trần dòng, không vì thiết kế lại**: `AddWordSheet` rời `TTSDictionaryEditView.swift` (702 → **559**, dưới baseline 641 ⇒ file đó rời danh sách violation), `ShelfSearchView+Actions` giữ `ShelfSearchView.swift` ở **292** (nếu để chung là 396/400), `CollectionDetailView+Manage` kéo `CollectionDetailView.swift` từ 405 về **354**.
* **File thứ tư (`TranslationPunctuationMapper`) là tách theo *vai*, không theo dòng**: bảng phải được gọi ở một mắt khác trong chuỗi xử lý, nên nó có tên riêng. Kèm theo, `TranslateUtils.swift` giảm 1023 → **968** (baseline 917 — vẫn vượt, nhưng chỉ đi xuống).
* **Không file nào bị xoá** ở lượt này.

## +8 file, −2 file: gộp tiền tố Google, panel Dịch kiêm Check rule, tải lẻ chương (1.3.334)

477 → **483** file Swift ⇒ phải `xcodegen generate` khi lên macOS.

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/TTS/TTSNextChapterPrefixSynthesizer.swift`](../../Sources/Services/TTS/TTSNextChapterPrefixSynthesizer.swift) | `enum` toàn `static nonisolated`: một chunk (`one`) và gộp Google (`googleBatch`) | 113 |
| [`Services/TTS/TTSNextChapterPrefixCache+GoogleBatch.swift`](../../Sources/Services/TTS/TTSNextChapterPrefixCache+GoogleBatch.swift) | dựng lượt gộp, phát kết quả về từng index, phục hồi khi lượt gộp lỗi | 158 |
| [`Views/Reader/ReaderRuleAction.swift`](../../Sources/Views/Reader/ReaderRuleAction.swift) | `enum ReaderRuleAction` — tách khỏi file overlay bị xoá | 13 |
| [`Views/Reader/ReaderView+DefinitionPanel.swift`](../../Sources/Views/Reader/ReaderView+DefinitionPanel.swift) | `definitionPanelOverlay(in:)` — chỗ nối 6 tham số rule vào panel Dịch | 107 |
| [`Views/Reader/ReaderDefinitionOverlayView+Rules.swift`](../../Sources/Views/Reader/ReaderDefinitionOverlayView+Rules.swift) | ô nghĩa rule (chỉ đọc), dải chip + nút `+`, popup 6 thao tác rule | 156 |
| [`Views/Reader/ReaderDefinitionOverlayView+Rows.swift`](../../Sources/Views/Reader/ReaderDefinitionOverlayView+Rows.swift) | ba hàng dưới của panel Dịch, dời nguyên khối để file gốc về dưới baseline | 164 |
| [`Views/Reader/Extensions/ReaderChapterListView+List.swift`](../../Sources/Views/Reader/Extensions/ReaderChapterListView+List.swift) | thân `List` của danh sách chương + nối `isDownloading`/`onDownload` | 179 |
| [`Views/Reader/Extensions/ReaderChapterListView+Download.swift`](../../Sources/Views/Reader/Extensions/ReaderChapterListView+Download.swift) | `canDownloadChapters` + `downloadChapter(_:)` | 74 |

| File bị xoá | Dòng | Vì sao |
|---|---|---|
| `Views/Reader/ReaderRuleTraceOverlayView.swift` | 396 | màn Check rule gộp vào panel Dịch; `RuleAction` dời sang `ReaderRuleAction.swift` |
| `Views/Reader/ReaderRuleTraceGuideSheet.swift` | 74 | nút `?` bị bỏ |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Reader/ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift) | 2052 → **1969** | bỏ `showingRuleTraceSheet`/`showingRuleGuide`; panel Dịch dời sang `+DefinitionPanel`; `onSearchWeb`; `refreshTitleTranslations` qua coordinator |
| [`Views/Reader/ReaderDefinitionOverlayView.swift`](../../Sources/Views/Reader/ReaderDefinitionOverlayView.swift) | 489 → **372** | detent 530 → 660; thân chia hai `Group` 6 con; `@State ruleActionTarget`/`showingRuleActions` |
| [`Views/Reader/ReaderChapterListView.swift`](../../Sources/Views/Reader/ReaderChapterListView.swift) | 468 → **295** | `@State downloadingChapterIndices`; thân `List` dời sang `+List` |
| [`Views/Reader/Extensions/ReaderView+RuleTools.swift`](../../Sources/Views/Reader/Extensions/ReaderView+RuleTools.swift) | 347 → **327** | `openDefinitionPanel`/`closeDefinitionPanel`/`handleDefinitionPanelClosed`; `SelectionPanel` còn `case copyOriginal` |
| [`Views/Reader/Extensions/ReaderView+Selection.swift`](../../Sources/Views/Reader/Extensions/ReaderView+Selection.swift) | 179 → **191** | `searchSelectionOnGoogle()` |
| [`Views/Reader/Components/ReaderChapterRowView.swift`](../../Sources/Views/Reader/Components/ReaderChapterRowView.swift) | 67 → **107** | tách vùng chạm; `trailingAccessory` ba trạng thái trong khung 30×30 |
| [`Views/Reader/Components/FloatingSelectionMenu.swift`](../../Sources/Views/Reader/Components/FloatingSelectionMenu.swift) | 202 → **202** | `onInspectRules` → `onSearchWeb`; nhãn "Rule"/`function` → "Tìm"/`magnifyingglass` |
| [`Views/Reader/ReaderFloatingMenuOverlayView.swift`](../../Sources/Views/Reader/ReaderFloatingMenuOverlayView.swift) | 92 → **92** | đổi tên tham số theo `FloatingSelectionMenu` |
| [`Views/Reader/ReaderHeaderFooterOverlayView.swift`](../../Sources/Views/Reader/ReaderHeaderFooterOverlayView.swift) | 202 → **202** | icon `ellipsis` → `ellipsis.circle` |
| [`Views/BookDetail/BookDetailView.swift`](../../Sources/Views/BookDetail/BookDetailView.swift) | 1197 → **1199** | `refreshTitleTranslations` qua coordinator (baseline 1201, còn **2 dòng**) |
| [`Views/BookDetail/Extensions/BookDetailView+Extensions.swift`](../../Sources/Views/BookDetail/Extensions/BookDetailView+Extensions.swift) | 345 → **345** | icon `ellipsis` → `ellipsis.circle` |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 772 → **840** | `pinnedShelfBooks`/`unpinnedShelfBooks`/`isShelfEmpty`; hai `Section`; `shelfBookRow`/`shelfSectionHeader` |
| [`Views/Shelf/Collections/CollectionDetailView.swift`](../../Sources/Views/Shelf/Collections/CollectionDetailView.swift) | 268 → **324** | cùng cách tách hai nhóm; `bookRow(_:)` |
| [`Views/Shelf/BookActions/BookActionSheet.swift`](../../Sources/Views/Shelf/BookActions/BookActionSheet.swift) | 270 → **307** | bỏ 2 hàng; phần đầu chạm/nhấn giữ; `canOpenDetail`/`canTogglePin`/`headerHint` |
| [`Services/TTS/TTSNextChapterPrefixCache.swift`](../../Sources/Services/TTS/TTSNextChapterPrefixCache.swift) | 380 → **339** | cửa `tool == "google" && missing.count >= 2`; helper dời sang synthesizer; nhiều `private` → `internal` |
| [`Services/Books/BookTransactionCoordinator.swift`](../../Sources/Services/Books/BookTransactionCoordinator.swift) | 288 → **312** | `refreshTitleTranslations(bookId:in:) -> Result<Bool, Error>` |
| [`Services/Translation/BookTitleTranslationMigrator.swift`](../../Sources/Services/Translation/BookTitleTranslationMigrator.swift) | 39 → **47** | `refreshTranslations(for:)` chỉ gán, trả `Bool didChange` |
| [`Views/Settings/Translation/QuickTranslationRulePatternStripView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulePatternStripView.swift) | 121 → **121** | doc comment trỏ về panel Dịch thay vì file đã xoá |
| [`Scripts/check_architecture.py`](../../Scripts/check_architecture.py) | 173 → **173** | regex gán `@Model` thêm lookbehind `(?<!\bself)` |

* **Cạnh mới**: `TTSNextChapterPrefixCache → TTSNextChapterPrefixCache+GoogleBatch → TTSNextChapterPrefixSynthesizer → GoogleTTSService.synthesizeBatch` + `→ TTSBatchAudioPayload`; `ReaderChapterListView+Download → ChapterContentRepository` + `→ ChapterStore.fetchChapter`; `ReaderView → BookTransactionCoordinator.refreshTitleTranslations` và `BookDetailView → …` (thay cho cạnh cũ tới `modelContext.save`).
* **Cạnh bị xoá**: `ReaderView → ReaderRuleTraceOverlayView`, `ReaderRuleTraceOverlayView → ReaderRuleTraceGuideSheet`, `ReaderView → BookTitleTranslationMigrator` và `BookDetailView → BookTitleTranslationMigrator` (giờ đi qua coordinator).
* `check_architecture.py` **12 → 8 violation**; hai file rời danh sách nhờ giảm dòng, hai vi phạm `VIEW_SWIFTDATA_MUTATION` được dọn hẳn.

## +3 file: gộp request Google, kiểu tab kệ sách (1.3.332)

474 → **477** file Swift ⇒ phải `xcodegen generate` khi lên macOS.

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/TTS/Extensions/TTSManager+RemoteBatchPrefetch.swift`](../../Sources/Services/TTS/Extensions/TTSManager+RemoteBatchPrefetch.swift) | gom cửa sổ nạp trước Google thành **một** request; dọn task nạp trước dùng chung | 205 |
| [`Services/TTS/TTSBatchAudioPayload.swift`](../../Sources/Services/TTS/TTSBatchAudioPayload.swift) | khung nhị phân đóng nhiều blob mp3 thành một `Data` để đi qua coordinator | 67 |
| [`Views/Shelf/ShelfMain/ShelfTab.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfTab.swift) | `enum ShelfTab: Int` — bốn tab theo đúng thứ tự hiển thị, thay số trần | 38 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/TTS/TTSManager.swift`](../../Sources/Services/TTS/TTSManager.swift) | 4015 → **4001** | `updatePrefetchWindow` gọi `pruneRemotePrefetchTasks(keeping:)` + `dispatchRemotePrefetch(for:)`; `startPrefetchTask`/`checkAndPromoteNextChapterAudioIfNeeded` thành `internal` |
| [`Services/TTS/Google/GoogleTTSService.swift`](../../Sources/Services/TTS/Google/GoogleTTSService.swift) | 210 → **260** | tách `makeRequest` / `audioParts(from:)` / `withRetry`; thêm `synthesizeBatch(parts:…)`; parser trả **mọi** audio thay vì `.first` |
| `Views/Reader/ReaderRuleTraceOverlayView.swift` *(xoá ở 1.3.334)* | 388 → **396** | `RuleAction.moveScope`; nút "Chuyển sang bộ …" trong popup chip |
| [`Views/Reader/Extensions/ReaderView+RuleTools.swift`](../../Sources/Views/Reader/Extensions/ReaderView+RuleTools.swift) | 299 → **347** | `moveRule(_:to:)` — ghi ở đích rồi xoá ở nguồn |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 780 → **772** | `selectedTab: ShelfTab`; Picker dựng từ `allCases`; bỏ `navigationTitleText` |
| [`Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift) | 273 → **273** | `selectedTab = .shelf` |
| [`Views/Search/SearchView.swift`](../../Sources/Views/Search/SearchView.swift) | 1003 → **1003** | gửi `ShelfTab.shelf/.history.rawValue` thay số trần |

* **Cạnh mới**: `TTSManager+RemoteBatchPrefetch → GoogleTTSService.synthesizeBatch` + `→ TTSBatchAudioPayload`; `ShelfView`/`ShelfView+BookImport`/`SearchView → ShelfTab`.
* **Không cạnh nào bị xoá**: đường một-đoạn-một-request vẫn còn nguyên và là đường **dự phòng** khi lượt gộp lỗi, cũng là đường duy nhất của Ext TTS.
* `check_architecture.py` giữ **12 violation** (cùng một tập); `TTSManager.swift` giảm 14 dòng.

## +3 file: hai cache và một cửa cooldown; ExtTTSService còn 65 dòng (1.3.330)

471 → **474** file Swift. Không thư mục mới, nhưng **có file mới** ⇒ phải `xcodegen generate` khi lên macOS.

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/TTS/Ext/ExtTTSScriptCache.swift`](../../Sources/Services/TTS/Ext/ExtTTSScriptCache.swift) | giữ `scriptContent` + config đã trộn + fingerprint của extension TTS; đường nóng còn **2 lần `stat()`** | 128 |
| [`Services/Extensions/Manager/RepositoryRefreshPolicy.swift`](../../Sources/Services/Extensions/Manager/RepositoryRefreshPolicy.swift) | cửa cooldown cho lượt **tự động** làm mới kho (mặc định 6 giờ) | 42 |
| [`Views/Common/ExtensionIconImageCache.swift`](../../Sources/Views/Common/ExtensionIconImageCache.swift) | cache `icon.png` theo `(path, modDate)`, ghi nhớ cả trường hợp **không có** ảnh | 45 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/TTS/Ext/ExtTTSService.swift`](../../Sources/Services/TTS/Ext/ExtTTSService.swift) | 230 → **65** | xoá `synthesize(...targetFormat:)`, `preprocessBufferForExtTTS`, `activeTempFiles`/`tempFileLock`/`cleanupTempFile`/`cleanupAllTempFiles`; bỏ `import AVFoundation`; `@unchecked Sendable` → `Sendable` |
| [`Services/Extensions/Manager/ExtensionManager.swift`](../../Sources/Services/Extensions/Manager/ExtensionManager.swift) | 1049 → **1015** | `ttsGenerate` + `getTTSRuntimeFingerprint` đọc qua cache; xoá `fingerprintCache`. **Về dưới baseline 1022** |
| [`Services/TTS/Ext/ExtTTSRuntime.swift`](../../Sources/Services/TTS/Ext/ExtTTSRuntime.swift) | 108 → **110** | `Identity` mang `fingerprint` thay cho `scriptContent` + `configurationData`; `generate` nhận thêm `fingerprint:` |
| [`Services/TTS/Google/GoogleTTSService.swift`](../../Sources/Services/TTS/Google/GoogleTTSService.swift) | 201 → **210** | `validVoiceIds` và key trong `Info.plist` thành `static let`; key cá nhân vẫn đọc mỗi lần |
| [`Services/TTS/TTSManager.swift`](../../Sources/Services/TTS/TTSManager.swift) | 4022 → **4015** | xoá hàm rỗng `cleanUpTempFile()` + 3 call site |
| [`Services/TTS/Extensions/TTSManager+PrefetchCache.swift`](../../Sources/Services/TTS/Extensions/TTSManager+PrefetchCache.swift) | 47 → **43** | bỏ nhánh gọi `cleanupAllTempFiles()` (tập luôn rỗng) |
| [`Views/Extensions/Manager/RepositoryManagerView.swift`](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift) | 728 → **734** | `refreshAllRepositories(force:)`; `filteredExtensions` tính một lần; `filterStatusBar(count:)`; icon dùng `ExtensionIconView` |
| [`Views/Common/ExtensionIconView.swift`](../../Sources/Views/Common/ExtensionIconView.swift) | 39 → **39** | đọc ảnh qua `ExtensionIconImageCache` thay vì `UIImage(contentsOfFile:)` mỗi lượt vẽ |

* **Cạnh mới**: `ExtensionManager → ExtTTSScriptCache → ExtensionManager` (cache gọi lại `getScriptPath`/`getCombinedConfigs`, cùng tầng Services, không tạo vòng phụ thuộc kiểu tầng); `RepositoryManagerView → RepositoryRefreshPolicy`; `ExtensionIconView → ExtensionIconImageCache`.
* **Cạnh bị xoá**: `ExtTTSService → AVFoundation` và `TTSManager+PrefetchCache → ExtTTSService.cleanupAllTempFiles`.
* `check_architecture.py` **13 → 12** violation: `ExtensionManager` rời danh sách nhờ giảm 34 dòng.

## +11 / -2 file: bộ sưu tập sách, ghim kệ, xoá màn Thử phiên âm (1.3.328)

462 → **471** file Swift. Hai thư mục mới ⇒ **phải** `xcodegen generate` khi lên macOS.

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Models/Database/BookCollection.swift`](../../Sources/Models/Database/BookCollection.swift) | `@Model` thứ **6**; quan hệ N-N với `Book`, `deleteRule: .nullify` ở cả hai đầu | 38 |
| [`Services/Books/BookCollectionCoordinator.swift`](../../Sources/Services/Books/BookCollectionCoordinator.swift) | chủ transaction bộ sưu tập: CRUD + thành viên; cưỡng chế "trong bộ ⇒ trên kệ" | 151 |
| [`Views/Shelf/BookActions/BookSheetAction.swift`](../../Sources/Views/Shelf/BookActions/BookSheetAction.swift) | `enum` hành động + `Mode` (shelf/history/collection) + `Target` cho `.sheet(item:)` | 43 |
| [`Views/Shelf/BookActions/BookActionRunner.swift`](../../Sources/Views/Shelf/BookActions/BookActionRunner.swift) | thân các hành động dùng chung ba màn; giữ luôn `newChapterTarget`/`checkNewChapters`/`showNewChapterSummary` | 188 |
| [`Views/Shelf/BookActions/BookActionSheet.swift`](../../Sources/Views/Shelf/BookActions/BookActionSheet.swift) | sheet nhấn-giữ: bìa + tên + tác giả + danh sách bộ sưu tập (có dấu "+" cuối) + mọi mục của context menu cũ | 264 |
| [`Views/Shelf/BookActions/ShelfBookRowView.swift`](../../Sources/Views/Shelf/BookActions/ShelfBookRowView.swift) | một dòng truyện: `BookListItemView` + ghim + badge chương mới | 30 |
| [`Views/Shelf/BookActions/NewChapterBadgeView.swift`](../../Sources/Views/Shelf/BookActions/NewChapterBadgeView.swift) | badge chương mới, tách khỏi `ShelfView+NewChapters` để màn Bộ sưu tập dùng chung | 28 |
| [`Views/Shelf/Collections/CollectionsTabView.swift`](../../Sources/Views/Shelf/Collections/CollectionsTabView.swift) | tab Bộ Sưu Tập: danh sách, tạo/đổi tên/xoá, kéo-thả thứ tự | 203 |
| [`Views/Shelf/Collections/CollectionDetailView.swift`](../../Sources/Views/Shelf/Collections/CollectionDetailView.swift) | danh sách truyện trong một bộ, **cùng bộ hành động** với kệ sách | 268 |
| [`Views/Shelf/Collections/CollectionPickerSheet.swift`](../../Sources/Views/Shelf/Collections/CollectionPickerSheet.swift) | chọn bộ (tuỳ chọn) sau khi thêm truyện vào kệ; có mục tạo bộ mới | 126 |
| [`Views/BookDetail/Extensions/BookDetailView+ShelfPlacement.swift`](../../Sources/Views/BookDetail/Extensions/BookDetailView+ShelfPlacement.swift) | `placeOnShelf(savedDesc:)` tách khỏi `BookDetailView` rồi mở `CollectionPickerSheet` | 33 |

| File xoá | Dòng | Lý do |
|---|---|---|
| `Views/Settings/TTS/TTSTransliterationTesterView.swift` | 277 | theo yêu cầu: bỏ màn "Thử phiên âm" |
| `Services/TTS/Preprocessing/TransliterationGoldenSet.swift` | 128 | chỉ có màn trên gọi; không còn caller nào |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 910 → **780** | 4 tab (thêm Bộ Sưu Tập = tag 2, Lịch Sử 2 → **3**); hai `.contextMenu` (121 dòng) thay bằng `onTapGesture` + `onLongPressGesture` mở sheet; `handleBookAction`; `shelfBooks` ghim-trước; xoá `bookItemView`/`retranslateChapterTitles`/`addToShelf`/`removeFromShelfOnly`/`removeFromHistory`/`clearReaderFallback` (dead) |
| [`Views/Shelf/ShelfMain/Extensions/ShelfView+NewChapters.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+NewChapters.swift) | 127 → **57** | `newChapterTarget`/`checkNewChapters` uỷ quyền `BookActionRunner`; xoá `newChapterBadge` + `showNewChapterSummary` |
| [`Models/Database/Book.swift`](../../Sources/Models/Database/Book.swift) | 79 → **90** | `isPinned: Bool = false`, `collections: [BookCollection] = []` (chiều nghịch khai ở `BookCollection`) |
| [`Services/Books/BookTransactionCoordinator.swift`](../../Sources/Services/Books/BookTransactionCoordinator.swift) | 239 → **288** | `setPinned`, `setHistory`; `removeFromShelf`/`setOnShelf(false)`/`addBookToShelf(isOnShelf: false)` dọn `collections` + `isPinned` |
| [`Models/Books/BookTransactionError.swift`](../../Sources/Models/Books/BookTransactionError.swift) | 13 → **19** | `collectionNotFound`, `invalidCollectionName`, `duplicateCollectionName` |
| [`App/FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) | 113 → **114** | `BookCollection.self` vào `ModelContainer` |
| [`Views/BookDetail/BookDetailView.swift`](../../Sources/Views/BookDetail/BookDetailView.swift) | 1207 → **1197** | `addToShelf()` gọi `placeOnShelf`; `@State collectionPickerBook` + `.sheet(item:)`. **Về dưới baseline 1201** |
| [`Views/Search/SearchView.swift`](../../Sources/Views/Search/SearchView.swift) | 858 → **859** | `targetShelfTab` cho Lịch Sử 2 → 3 (khớp số tab mới của `ShelfView`) |
| [`Services/Backup/BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) | 161 → **165** | entry `library/collections.json`, **không** thêm `BackupScope` |
| [`Services/Backup/BackupPayload.swift`](../../Sources/Services/Backup/BackupPayload.swift) | 217 → **240** | `CollectionRecord`; `BookRecord.isPinned: Bool?` (optional để archive cũ còn decode) |
| [`Services/Backup/BackupManifest.swift`](../../Sources/Services/Backup/BackupManifest.swift) | 114 → **120** | `Counts.collections` + `decodeIfPresent` |
| [`Services/Backup/BackupLibraryReader.swift`](../../Sources/Services/Backup/BackupLibraryReader.swift) | 139 → **159** | `Payload.collections`, `readCollections()`, đọc `isPinned` |
| [`Services/Backup/BackupLibraryWriter.swift`](../../Sources/Services/Backup/BackupLibraryWriter.swift) | 188 → **246** | `restoreCollections` (gộp theo tên), ghim cho truyện mới thêm |
| [`Services/Backup/BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) | 253 → **260** | stage `collections.json`, `counts.collections` |
| [`Services/Backup/BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) | 280 → **290** | decode + gọi `restoreCollections`, log thêm số bộ |
| [`Views/Settings/Backup/RestoreOptionsSheet.swift`](../../Sources/Views/Settings/Backup/RestoreOptionsSheet.swift) | 130 → **133** | hàng "Bộ sưu tập" khi `counts.collections > 0` |
| [`Views/Settings/TTS/NghiTTSSettingsView.swift`](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift) | 154 → **154** | bỏ `NavigationLink` Thử phiên âm; thêm `Toggle` "Dùng IPA của espeak cho tiếng Anh" (chuyển chỗ ở của `EnglishPhonemeTransliterator.useEspeakKey`) |
| [`Services/TTS/EspeakPhonemizer.swift`](../../Sources/Services/TTS/EspeakPhonemizer.swift) | 193 → **173** | xoá `probeVoices` (chỉ màn đã xoá gọi) |
| [`Services/TTS/Preprocessing/VietnameseTokenGate.swift`](../../Sources/Services/TTS/Preprocessing/VietnameseTokenGate.swift) | 110 → **95** | xoá `explain` (0 caller) |
| [`Services/TTS/Preprocessing/JapaneseTransliterator.swift`](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift) | 341 → **347** | 15 hàng `ư` → `u`; comment giải thích |

* **Cạnh mới**: `Views/Shelf/**` → `BookCollectionCoordinator` → `BookCollection` (Views → Services → Models, đúng chiều); `Services/Backup/**` → `BookCollectionCoordinator`. Không cạnh ngược nào.
* **Cạnh bị xoá**: `Views/Settings/TTS` → `EspeakPhonemizer.probeVoices` và → `TransliterationGoldenSet` (cả hai đầu đã biến mất).
* `ShelfView` giảm 130 dòng nên khoảng trống dưới baseline 942 nới ra; `BookDetailView` lần đầu **trở lại** dưới baseline sau nhiều lượt vượt.

## +1 file cho đường cài mới từ VS Code (1.3.325)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Extensions/Debug/Staging/ExtensionDraftMetadata.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftMetadata.swift) | DTO đọc `plugin.json` của bản nháp (`read(from:)`, `slug(forName:)`, `upsertCommand(localPath:)`) — nguồn duy nhất suy `packageId` + metadata cho hàng `Extension` khi cài mới | 136 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Debug/Server/ExtensionDebugCommandRouter+Draft.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter+Draft.swift) | 204 → **297** | `import SwiftData`; `handleDraftInstall` tách thành `installOverExisting` / `installAsNew`; thêm `writeLibraryRow`; `handleDraftStage` bỏ chốt "phải đã cài" |
| [`Debug/Server/ExtensionDebugCommandRouter.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter.swift) | 262 → **308** | `container` thành `internal`; `handleRunStart` cho phép `sourceMode: draft` khi chưa cài; tách `startRun(...)` dùng chung hai nguồn |
| [`Debug/Staging/ExtensionDraftInstaller.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftInstaller.swift) | 147 → **201** | thêm `installNew`, `newInstallSummary`, tách `backup(installedUrl:packageId:)` dùng chung; `InstallError.unsafePackageId` |
| [`Debug/Server/ExtensionDebugInstallGate.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugInstallGate.swift) | 113 → **134** | `Kind.installNew`; `Request.displayName`; `summary` ba nhánh |
| [`Views/Settings/Debug/ExtensionDebugServerView.swift`](../../Sources/Views/Settings/Debug/ExtensionDebugServerView.swift) | 130 → **151** | `approveLabel(for:)` / `installFooter(for:)`; header + bullet giới hạn nói riêng cho đường cài mới |

* Tổng file Swift 461 → **462**; không thư mục mới ⇒ **phải** `xcodegen generate` khi lên macOS.
* **Cạnh mới**: `ExtensionDebugCommandRouter` → `ExtensionTransactionCoordinator` + `ExtensionDraftMetadata` → `UpsertExtensionCommand` (Services → Models, đúng chiều); `ExtensionDraftInstaller` → `ExtensionManager.extensionsDirectory` (dùng lại chủ sở hữu duy nhất của đường dẫn `extensions/`, không nhân bản path). Không cạnh nào bị xoá.
* `Tools/VSCode/FreeBookExtDebug/src/{extension.ts,draft.ts}` + `README.md` sửa cùng lượt; `Tools/**` không thuộc phạm vi `validate_links.py`.

## Không file mới; recognizer bàn phím có đường gỡ (1.3.323)

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Common/Utils/KeyboardDismissGesture.swift`](../../Sources/Common/Utils/KeyboardDismissGesture.swift) | 112 → **149** | `activate()` đăng ký thêm observer `keyboardWillHideNotification`; thêm `keyboardWillHide()` + `uninstall()` (gỡ recognizer khỏi **mọi** window theo `UIGestureRecognizer.name`); phần tăng chủ yếu là comment giải thích vì sao phải gỡ |

* Tổng file Swift **không đổi** (không thêm/xoá/đổi tên file nào), không thư mục mới ⇒ không cần `xcodegen generate`.
* **Không cạnh phụ thuộc nào mới hay bị xoá**: file vẫn chỉ `import UIKit`, vẫn là lá của đồ thị, người gọi duy nhất vẫn là `AppLaunchRootView.onAppear`.
* Bảng ở mục 1.3.266 bên dưới liệt kê thành viên của file; danh sách đủ nay là `activate()`, `keyboardWillShow()`, `keyboardWillHide()`, `installIfNeeded()`, `uninstall()`, `handleTap(_:)`, `isEditableTextInput(_:)` + hai hàm `UIGestureRecognizerDelegate`.

## -3 file hub tu dien tham chieu (1.3.320)

464 -> **461** file Swift. Xoa `ReferenceDictionaryHubView.swift` (42), `ReferenceDictionaryListView.swift` (118), `ReferenceDictionaryReader.swift` (95) cung section "Tham Chieu" va ham `referenceStatusText()` trong `DictionaryHubView.swift` (169 → 152).

Khong them file nao: ca bon luot toi uu deu nam trong file san co, va hai file bi cham baseline dong (`TTSManager.swift` 4023 → 4022, `TextPreprocessor.swift` giu dung 1121) deu khong tang.

## +4 file: thu giong doc va hub tu dien tham chieu (1.3.318)

460 -> **464** file Swift. Khong file nao cham tran 400.

* [`Sources/Views/Settings/TTS/NghiTTSTextToolView.swift`](../../Sources/Views/Settings/TTS/NghiTTSTextToolView.swift) — **180** dong.
* `Sources/Services/Translation/Utils/ReferenceDictionaryReader.swift` — **96** dong (da xoa o 1.3.320).
* `Sources/Views/Dictionary/ReferenceDictionaryHubView.swift` — **43** dong (da xoa o 1.3.320).
* `Sources/Views/Dictionary/ReferenceDictionaryListView.swift` — **125** dong (da xoa o 1.3.320).

## -3 file dung cu do IPA, +2 file goi y phien am (1.3.317)

461 -> **460** file Swift.

Xoa:

* `Sources/Views/Settings/TTS/TTSIPAProbeSection.swift` (323 dong) — 4 section thi nghiem E1: nhap IPA tho roi phat bang Piper.
* `Sources/Services/TTS/NghiTTS/ONNXPiperEngine+Phonemes.swift` (151 dong) va `Sources/Services/TTS/NghiTTS/PiperPhonemeInventory.swift` (87 dong) — chi section tren goi, xoa no thi hai file nay mat het caller.

Them:

* [`Sources/Models/TTS/TTSPhoneticSuggestion.swift`](../../Sources/Models/TTS/TTSPhoneticSuggestion.swift) — **74** dong. Giu ca `Origin` (nguon goi y) va mau badge; mau dat o day chu khong o View vi `TTSDictionaryEditView.swift` dang vuot baseline dong va chi duoc phep giam.
* [`Sources/Services/TTS/Preprocessing/TTSPhoneticSuggestionBuilder.swift`](../../Sources/Services/TTS/Preprocessing/TTSPhoneticSuggestionBuilder.swift) — **80** dong.

`TTSDictionaryEditView.swift` **giam** 705 → 702 dong nho thay khoi dung goi y bang mot loi goi builder.

## +2 file: so thu tu TTS va kiem toan tien ich da cai (1.3.313)

459 -> **461** file Swift.

* [`Sources/Services/TTS/Preprocessing/VietnameseOrdinalSpeller.swift`](../../Sources/Services/TTS/Preprocessing/VietnameseOrdinalSpeller.swift) — **46** dong. File rieng chu khong them vao `TextPreprocessor.swift` vi file do dang **dung** baseline dong (1 121, chi duoc giam); cho stage moi lay bang cach bo mot dong log da comment.
* [`Sources/Services/Extensions/ExtensionInstallAudit.swift`](../../Sources/Services/Extensions/ExtensionInstallAudit.swift) — **80** dong. Doc dia nam o Services, ghi DB van o `ExtensionTransactionCoordinator`; View chi chuyen ke hoach giua hai ben.

## +1 file Views cho vi tri cuon Kham Pha (1.3.307)

458 -> **459** file Swift.

| Thay doi | File | Vai tro | Dong |
| --- | --- | --- | --- |
| Them | [`Views/Discovery/DiscoveryScrollAnchorStore.swift`](../../Sources/Views/Discovery/DiscoveryScrollAnchorStore.swift) | ghi nho `link` hang tren cung + tap hang dang hien cua tung tab | 59 |

`DiscoveryView.swift` 940 -> 984 dong (them `ScrollViewReader`, 2 modifier `onAppear/onDisappear` cho hang, 2 ham `captureAnchor`/`applyPendingRestore`); `QuickTranslationRuleTokenLengthBar.swift` 132 -> 145. Khong file nao cham tran 400 tru `DiscoveryView` (file legacy, baseline rieng, khong vuot baseline).

## Bo ghep noi: -2 file, +1 file (1.3.305)

459 -> **458** file Swift.

| Thay doi | File | Ly do |
| --- | --- | --- |
| Xoa | `Debug/Server/ExtensionDebugPairingAuthority.swift` | khong con token/het han/cua xac nhan ket noi |
| Xoa | `Settings/Debug/ExtensionDebugPairingQRView.swift` | khong con QR de quet; man hinh chi hien `ws://ip:port` |
| Them | [`Debug/Server/ExtensionDebugServerLauncher.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugServerLauncher.swift) | cho duy nhat biet co `extDebugServerEnabled` va cach bat lai luc khoi dong (22 dong) |

`ExtensionDebugServer` 248 -> 260 dong, `ExtensionDebugCommandRouter` 278 -> 239, `ExtensionDebugServerStatus` 91 -> 63, `ExtensionDebugServerView` 223 -> 133. Khong file nao cham tran 400.

## 18 file Swift + 1 package VS Code cua Phase 2-4 (1.3.303)

18 file moi (441 -> **459**). Khong file nao cham tran 400.

| File moi | Tang | Vai tro | Dong |
| --- | --- | --- | --- |
| [`Debug/Server/ExtensionDebugServer.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugServer.swift) | Services | actor: NWListener + Bonjour + vong doi client | 248 |
| [`Debug/Server/ExtensionDebugCommandRouter.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter.swift) | Services | dispatch + cuong che pairing | 278 |
| [`Debug/Server/ExtensionDebugCommandRouter+Draft.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugCommandRouter+Draft.swift) | Services | nhanh `draft.*` (Phase 3-4) | 183 |
| [`Debug/Server/ExtensionDebugConnection.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugConnection.swift) | Services | khung truyen WebSocket mot client | 117 |
| [`Debug/Server/ExtensionDebugProtocol.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugProtocol.swift) | Services | envelope + payload + ma loi v1 | 129 |
| `Debug/Server/ExtensionDebugPairingAuthority.swift` *(da xoa o 1.3.306)* | Services | token mot lan, het han, cua xac nhan | 101 |
| [`Debug/Server/ExtensionDebugInstallGate.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugInstallGate.swift) | Services | treo `draft.install`/`rollback` cho bam | 113 |
| [`Debug/Server/ExtensionDebugServerStatus.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugServerStatus.swift) | Services | snapshot trang thai cho Views | 76 |
| [`Debug/Server/ExtensionDebugInstalledSnapshot.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugInstalledSnapshot.swift) | Services | ban sao bat bien cua hang `Extension` | 43 |
| [`Debug/Server/ExtensionDebugNetworkAddress.swift`](../../Sources/Services/Extensions/Debug/Server/ExtensionDebugNetworkAddress.swift) | Services | IPv4 hien tai cho pairing URI (`getifaddrs`) | 50 |
| [`Debug/Staging/ExtensionDraftStagingStore.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftStagingStore.swift) | Services | actor: nhan chunk, checksum, discard | 162 |
| [`Debug/Staging/ExtensionDraftManifest.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftManifest.swift) | Services | manifest + quota + luat path an toan | 89 |
| [`Debug/Staging/ExtensionDraftValidator.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftValidator.swift) | Services | plugin.json, containment, `load()`, cu phap | 84 |
| [`Debug/Staging/ExtensionDraftInstaller.swift`](../../Sources/Services/Extensions/Debug/Staging/ExtensionDraftInstaller.swift) | Services | diff, backup, swap nguyen tu, rollback | 147 |
| [`Common/Extensions/Data+Crypto.swift`](../../Sources/Common/Extensions/Data+Crypto.swift) | Common | `Data.sha256Hex()` cho checksum nhi phan | 13 |
| [`Views/Settings/Debug/ExtensionDebugServerView.swift`](../../Sources/Views/Settings/Debug/ExtensionDebugServerView.swift) | Views | bat/tat server, QR, approve, diff cai dat | 191 |
| [`Views/Settings/Debug/ExtensionDebugServerReader.swift`](../../Sources/Views/Settings/Debug/ExtensionDebugServerReader.swift) | Views | gop stream server + install gate | 53 |
| `Views/Settings/Debug/ExtensionDebugPairingQRView.swift` *(da xoa o 1.3.306)* | Views | QR bang `CIFilter.qrCodeGenerator` | 39 |

File sua: `DeveloperSettingsSection.swift` (them link server), `MainTabView.swift` (tat server khi roi foreground + xoa staging luc khoi dong), `project.yml` (2 khoa Info.plist).

Package VS Code o `Tools/VSCode/FreeBookExtDebug/`: `package.json`, `tsconfig.json`, `src/protocol.ts` (mirror contract), `src/client.ts` (WebSocket), `src/draft.ts` (dung + gui snapshot), `src/extension.ts` (10 command, OutputChannel, DiagnosticCollection, SecretStorage), `README.md`. **Khong** thuoc target iOS va **khong** duoc CI bien dich.

## 13 file của phân hệ debug extension (1.3.302)

13 file mới (428 → **441**). Không file nào chạm trần 400.

| File mới | Tầng | Vai trò | Dòng |
| --- | --- | --- | --- |
| [`Services/Extensions/Debug/ExtensionDebugEvent.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugEvent.swift) | Services | Contract v1 của một dòng trace, `Codable` | 107 |
| [`.../ExtensionDebugSourceLocation.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugSourceLocation.swift) | Services | script path tương đối + line/column + revision | 39 |
| [`.../ExtensionDebugEventSink.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugEventSink.swift) | Services | Protocol đồng bộ + overload tiện dụng + `location(...)` | 60 |
| [`.../ExtensionDebugRedactor.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugRedactor.swift) | Services | Cổng duy nhất sinh chuỗi được phép hiện | 67 |
| [`.../ExtensionDebugEventHub.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugEventHub.swift) | Services | `actor`: ring buffer, quota, `AsyncStream` broadcast | 105 |
| [`.../ExtensionDebugSession.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugSession.swift) | Services | Sink của một run: runId + sequence | 70 |
| [`.../ExtensionDebugEntrypoint.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugEntrypoint.swift) | Services | 7 entrypoint + typed arguments khớp production | 105 |
| [`.../ExtensionDebugRunner.swift`](../../Sources/Services/Extensions/Debug/ExtensionDebugRunner.swift) | Services | `actor`: chạy/huỷ run, phát `runStarted`…`runFinished` | 206 |
| [`Services/Extensions/Engine/JSExecutor+Debug.swift`](../../Sources/Services/Extensions/Engine/JSExecutor+Debug.swift) | Services | 5 điểm phát của executor | 77 |
| [`Views/Settings/Debug/ExtensionDebugConsoleView.swift`](../../Sources/Views/Settings/Debug/ExtensionDebugConsoleView.swift) | Views | Màn chọn extension/entrypoint/input, chạy, huỷ | 217 |
| [`.../ExtensionDebugTraceReader.swift`](../../Sources/Views/Settings/Debug/ExtensionDebugTraceReader.swift) | Views | Projection reader đọc hub | 73 |
| [`.../ExtensionDebugEventRow.swift`](../../Sources/Views/Settings/Debug/ExtensionDebugEventRow.swift) | Views | Một dòng trace | 53 |
| [`Views/Settings/Main/DeveloperSettingsSection.swift`](../../Sources/Views/Settings/Main/DeveloperSettingsSection.swift) | Views | Mục "Nhà Phát Triển" trong Cài Đặt | 17 |

File sửa: `JSExecutor.swift` 1516 → **1553** (thêm `debugSink`, tham số init, 6 điểm phát một dòng); `SettingsView.swift` 447 → **450** (một dòng gọi `DeveloperSettingsSection`, vẫn dưới baseline 453). `ExtensionManager.swift` **không đổi**.

Mục "Nhà Phát Triển" phải ra file riêng vì `SettingsView.swift` chỉ còn 6 dòng dư trước baseline — đúng mẫu `BackupSettingsSection` / `TTSSettingsSection` đang dùng.

## Whitelist từ gốc Nhật (1.3.297)

1 file mới (426 → **427**): `Sources/Services/TTS/Preprocessing/JapaneseLoanwordList.swift` (~95) — `Set<String>` khoảng 200 từ gốc Nhật viết bằng chữ Latin, là lớp quyết định đầu tiên của `ForeignScriptClassifier`.

`ForeignScriptClassifier.swift` 189 → 213: whitelist chạy trước phép chấm điểm, thêm `romajiVowelSequences`, bỏ luật "từ dài không cụm phụ âm Anh". `TTSIPAProbeSection.swift` 221 → 323: thêm ca đối chứng lấy IPA thật từ espeak `vi`, và phép so bộ ký hiệu `vi` vs `en-us`.

## Ba file dụng cụ đo cho phiên âm (1.3.296)

3 file mới (423 → **426**):

* `Sources/Services/TTS/NghiTTS/PiperPhonemeInventory.swift` (87) — đọc `phoneme_id_map` từ `<giọng>.onnx.json`, đếm scalar ngoài từ vựng, và bảng hạ cấp cho ký hiệu không có.
* `Sources/Services/TTS/NghiTTS/ONNXPiperEngine+Phonemes.swift` (151) — tổng hợp từ **chuỗi IPA cho trước**, bỏ qua tầng phiên âm. Là file riêng vì `ONNXPiperEngine.swift` đang ở **đúng** baseline 469 dòng và chỉ được phép giảm; `CachedRuntime` và `getRuntime` đổi từ `private` sang internal (đổi từ khoá, **không** thêm dòng).
* `Sources/Views/Settings/TTS/TTSIPAProbeSection.swift` (221) — `View` riêng chứ không phải extension, vì state của `TTSTransliterationTesterView` là `private` nên extension ở file khác không đọc được.

## Chống mất chữ + xoá tất cả phiên âm (1.3.291)

| File mới | Tầng | Vai trò | Dòng |
|---|---|---|---|
| [`TextPreprocessor+Bulk.swift`](../../Sources/Services/TTS/Preprocessing/TextPreprocessor+Bulk.swift) | Services | `deleteAllWords()` — extension vì file gốc đúng bằng baseline 1121 | 30 |
| [`TTSDictionaryBulkActionsModifier.swift`](../../Sources/Views/Settings/TTS/TTSDictionaryBulkActionsModifier.swift) | Views | hai alert hàng loạt, khuôn `@MainActor ViewModifier` của `QuickTranslationRuleIOMenu` | 67 |

| File sửa | Thay đổi | Dòng |
|---|---|---|
| `IPAToVietnameseMapper.swift` | `assemble` trả `[String]`; cụm đầu/cuối thành âm tiết đệm | 176 → **210** |
| `JapaneseTransliterator.swift` | `ー` → rỗng (âm ngắn), thêm `ou`/`ei`, chốt chống rỗng | 320 → **311** |
| `EnglishTransliterator.swift` | chốt chống rỗng | 390 → **393** |
| `EnglishPhonemeTransliterator.swift` | `nonEmpty(_:fallback:)` ở cả hai nhánh dự phòng | 67 → **77** |
| `VietnameseTokenGate.swift` | đếm láng giềng lạ riêng từng phía, yêu cầu kẹp giữa | 106 → **110** |
| `TextPreprocessor.swift` | 4 thành viên `private` → `internal`; **không thêm dòng** | 1121 → **1121** |
| `TTSDictionaryEditView.swift` | thêm mục menu Xoá tất cả, dời 2 alert ⇒ **giảm** dòng | 706 → **705** |
| `TransliterationGoldenSet.swift` | sửa kỳ vọng ラーメン/ジェット, thêm `arigatou`/`street`/`text` | 114 → **117** |

* Tổng file Swift **423** (421 + 2). Hai file ở/vượt trần đều không phình: một giữ đúng số dòng, một giảm.

## Phiên âm Anh/Nhật: 6 file mới, 5 file sửa (1.3.290)

| File mới | Tầng | Vai trò | Dòng |
|---|---|---|---|
| [`Services/TTS/Preprocessing/IPAToVietnameseMapper.swift`](../../Sources/Services/TTS/Preprocessing/IPAToVietnameseMapper.swift) | Services | IPA → âm tiết Việt hợp lệ (onset/nucleus/coda + chuẩn hoá `c/k/g/gh`) | 182 |
| [`Services/TTS/Preprocessing/EnglishPhonemeTransliterator.swift`](../../Sources/Services/TTS/Preprocessing/EnglishPhonemeTransliterator.swift) | Services | espeak `en-us` → IPA → mapper, dự phòng về bộ luật cũ | 67 |
| [`Services/TTS/Preprocessing/ForeignScriptClassifier.swift`](../../Sources/Services/TTS/Preprocessing/ForeignScriptClassifier.swift) | Services | chấm điểm Nhật/Anh thay cho blacklist | 189 |
| [`Services/TTS/Preprocessing/VietnameseTokenGate.swift`](../../Sources/Services/TTS/Preprocessing/VietnameseTokenGate.swift) | Services | cổng "là từ tiếng Việt" theo ngữ cảnh láng giềng | 106 |
| `Services/TTS/Preprocessing/TransliterationGoldenSet.swift` *(xoá ở 1.3.328)* | Services | ~55 ca kiểm định hướng, dữ liệu thuần | 114 |
| `Views/Settings/TTS/TTSTransliterationTesterView.swift` *(xoá ở 1.3.328)* | Views | màn Thử phiên âm: probe giọng, soi một từ, chạy ca kiểm | 277 |

| File sửa | Thay đổi | Dòng |
|---|---|---|
| [`Services/TTS/EspeakPhonemizer.swift`](../../Sources/Services/TTS/EspeakPhonemizer.swift) | tách `initializeIfNeeded`/`textToPhonemes`, thêm `phonemizeEnglish` (đặt giọng `en-us` rồi trả về `vi` trong `defer`) và `probeVoices` | 141 → **193** |
| [`Services/TTS/Preprocessing/JapaneseTransliterator.swift`](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift) | xoá `englishBlacklist` (92 dòng) + `simplifySokuon` chết (18 dòng); sửa `ya/yu/yo`; trường âm `ー`; thêm katakana hiện đại | 411 → **320** |
| [`Services/TTS/Preprocessing/EnglishTransliterator.swift`](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift) | 3 alternation bọc ngoặc, `else if` cho tiền tố y/d, dời `ck`/`sh` xuống `tRules` | 383 → **390** |
| [`Services/TTS/Preprocessing/TextPreprocessor.swift`](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift) | 5 sửa **tại chỗ**: 3 call site sang `EnglishPhonemeTransliterator`, vòng lặp lấy `tokenIndex`, cổng sang `VietnameseTokenGate` | 1121 → **1121** |
| [`Services/TTS/NghiTTS/NghiTTSClient.swift`](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift) | `downloadDictionaries` trộn thay vì ghi đè `non-vietnamese-words.plist` | 175 → **188** |

* Tổng file Swift **421** (415 + 6). `TextPreprocessor.swift` và `JapaneseTransliterator.swift` đang ở/vượt trần baseline nên mọi logic mới nằm ở file mới; hai file đó chỉ sửa tại chỗ hoặc **giảm** dòng.
* Chiều phụ thuộc: 5 file Services mới không `import SwiftUI`; `EnglishPhonemeTransliterator` → `EspeakPhonemizer` là cạnh mới **trong** tầng Services, không có cạnh ngược từ Views.

## Con trỏ thật cho ô nhập mẫu: 2 file mới (1.3.289)

| File mới | Tầng | Vai trò | Dòng |
|---|---|---|---|
| [`Views/Settings/Translation/QuickTranslationRulePatternField.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulePatternField.swift) | Views | `UIViewRepresentable` bọc `UITextView`: báo con trỏ thật lên, nhận vùng chọn từ SwiftUI, quy đổi ký tự ⇄ UTF-16 | 149 |
| [`Views/Settings/Translation/QuickTranslationRuleEditorSheet+Editing.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleEditorSheet+Editing.swift) | Views | khối biên tập mẫu tách khỏi sheet: định vị token, chèn/thay, xoá lùi | 96 |

| File sửa | Thay đổi | Dòng |
|---|---|---|
| [`Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift) | `TextField` mẫu → `QuickTranslationRulePatternField` + placeholder overlay; bỏ `isProgrammaticPatternEdit`; `@FocusState` chỉ còn cho ô Bản dịch; helper dời sang file `+Editing` | 374 → **319** |
| [`Views/Settings/Translation/QuickTranslationRulePatternStripView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulePatternStripView.swift) | cập nhật doc vai trò (không còn là nguồn con trỏ duy nhất) | 123 → **121** |

* Tổng file Swift **415** (413 + 2). Mọi file mới ≤ 400 dòng; `Coordinator` của representable là type **lồng** nên không phạm `MULTI_PRIMARY_TYPES`.
* `QuickTranslationRuleEditorSheet.swift` **giảm** dòng dù thêm tính năng, nhờ dời 6 hàm biên tập sang file extension — đúng khuôn `X+Feature.swift` mà repo dùng cho god-object.

## Màn nhập rule: 6 file mới cho bản nháp + 3 công cụ nhập nhanh (1.3.288)

| File mới | Tầng | Vai trò | Dòng |
|---|---|---|---|
| [`Services/Translation/Engine/QuickTranslationRuleDraftAnalyzer.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDraftAnalyzer.swift) | Services | chấm điểm bản nháp (`Analysis`), cắt mẫu thành `Segment`, đọc/ghi `TokenSpec` | 238 |
| [`Views/Settings/Translation/QuickTranslationRuleDraftStore.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleDraftStore.swift) | Views | một slot bản nháp theo `Mode.id`, sống ngoài cây view | 66 |
| [`Views/Settings/Translation/QuickTranslationRulePatternStripView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulePatternStripView.swift) | Views | dải chip của mẫu: con trỏ, chọn chip, xoá lùi | 123 |
| [`Views/Settings/Translation/QuickTranslationRuleTokenPaletteView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTokenPaletteView.swift) | Views | 10 nút token + 4 nút cú pháp nhóm | 111 |
| [`Views/Settings/Translation/QuickTranslationRuleTokenLengthBar.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTokenLengthBar.swift) | Views | `[−] min [+]` / `[−] max [+]` bước 1 + công tắc `?` | 132 |
| [`Views/Settings/Translation/QuickTranslationRuleCaptureChipsView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleCaptureChipsView.swift) | Views | chip `{0}…{n-1}`, tô đỏ chip chưa dùng | 82 |
| [`Views/Settings/Translation/QuickTranslationRuleDraftIssuesView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleDraftIssuesView.swift) | Views | section Kiểm tra: mọi issue theo severity | 57 |

| File sửa | Thay đổi | Dòng |
|---|---|---|
| [`Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift) | seed/mirror bản nháp, `@FocusState`, vùng chọn, 4 subview mới, section Kiểm tra | 179 → **374** |
| [`Views/Reader/Extensions/ReaderView+RuleTools.swift`](../../Sources/Views/Reader/Extensions/ReaderView+RuleTools.swift) | sheet hướng dẫn dời xuống panel Check rule | 297 → **299** |
| [`Services/Translation/Engine/QuickTranslationRuleCompiler.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleCompiler.swift) | `parseTemplate` `private` → `internal` (+3 dòng doc) | 316 → **319** |

* Tổng file Swift **413** (406 + 7). Mọi file mới ≤ 400 dòng, đúng **một** primary type top-level (các `Segment`/`TokenSpec`/`Analysis`/`Draft`/`Field` đều là type lồng).
* Chiều phụ thuộc giữ nguyên Views → Services: analyzer nằm ở Services, không `import SwiftUI`; 6 file view mới chỉ đọc type của analyzer.

## Token số `<h>`/`<d>` + full-width digits (1.3.287)

| File sửa | Vai trò | Dòng |
|---|---|---|
| [`Services/Translation/Engine/QuickTranslationRuleElement.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleElement.swift) | `Kind.numeral` đổi thành `numeral(NumeralKind)`; thêm enum `NumeralKind` 4 loại | 146 |
| [`Services/Translation/Engine/QuickTranslationNumberFormatter.swift`](../../Sources/Services/Translation/Engine/QuickTranslationNumberFormatter.swift) | thêm `hanDigitsUnits`/`asciiDigitsUnits`, `units(for:)`, `renderHanDigits`/`renderAsciiDigits`, full-width trong `digitMap` | 161 |
| [`Services/Translation/Engine/QuickTranslationRuleMatcher.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleMatcher.swift) | `walkNumeral(kind:)` + switch render theo `NumeralKind` | 244 |
| [`Services/Translation/Engine/QuickTranslationRuleCompiler.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleCompiler.swift) | `applyBoundaryGuards` dùng `units(for:)` | 316 |
| [`Services/Translation/Engine/QuickTranslationRuleParser.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleParser.swift) | parse `<h>`→`.hanDigits`, `<d>`→`.asciiDigits`; `|` giữa token số parse theo loại đầu tiên | 361 |
| [`Services/Translation/Engine/QuickTranslationRuleTokenSettings.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleTokenSettings.swift) | thêm `hanDigits`/`asciiDigits` (8 → **10** token) + 2 khoá UserDefaults | 68 |
| [`Views/Settings/Translation/QuickTranslationRuleTokenSettingsView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTokenSettingsView.swift) | thêm 2 Toggle `<h>`, `<d>` | 67 |

* Không thêm/xoá file nên tổng file Swift không đổi. DSL token số mở rộng nhưng cấu trúc matcher/compiler giữ nguyên hướng greedy + boundary guard có điều kiện.

## Gộp dropdown rule theo tab hiện tại (1.3.286)

| File | Vai trò | Dòng |
|---|---|---|
| [`Views/Settings/Translation/QuickTranslationRuleIOMenu.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleIOMenu.swift) | Modifier toolbar duy nhất cho màn danh sách rule; `showingDisabled == false` hiện thao tác bộ rule, `true` hiện thao tác danh sách tắt | 304 |
| [`Views/Settings/Translation/QuickTranslationRuleIOMenu+DisabledActions.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleIOMenu+DisabledActions.swift) | `extension QuickTranslationRuleIOMenu` chứa menu item + import/export/bật lại/xoá rule tắt, thay cho `QuickTranslationRuleDisableIOMenu.swift` | 136 |
| [`Views/Settings/Translation/QuickTranslationRuleListView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleListView.swift) | Gắn một `.quickTranslationRuleIOMenu(scope:showingDisabled:)` duy nhất, bỏ modifier rule-tắt riêng | 381 |

* Xoá `Views/Settings/Translation/QuickTranslationRuleDisableIOMenu.swift` (237 dòng) và thêm file extension mới, nên tổng số file Swift không đổi. Cạnh mới vẫn chỉ nằm trong tầng Views; `QuickTranslationRuleIOMenu` tiếp tục là owner presentation, còn store/service không đổi.

## Copy gốc · Check rule · Bộ rule riêng/chung + file tắt (1.3.274)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Models/Translation/QuickTranslationRuleScope.swift`](../../Sources/Models/Translation/QuickTranslationRuleScope.swift) | `enum { global, book(String) }` + `rank` (0 riêng / 1 chung), `label`, `bookId` | 38 |
| [`Models/Translation/QuickTranslationRuleTrace.swift`](../../Sources/Models/Translation/QuickTranslationRuleTrace.swift) | DTO một lần khớp rule trên đoạn văn: `scope`, `pattern`, `sourceRange`, `captures`, `Status` 6 case; `id` xác định theo scope/pattern/location | 81 |
| [`Services/Translation/Engine/QuickTranslationRuleBookStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleBookStore.swift) | chủ bộ rule **riêng truyện**; LRU cap 3; CRUD + nhập/xuất; ghi TXT canonical qua `QuickTranslationRuleRecordStore` | 293 |
| [`…/QuickTranslationRuleDisableFile.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDisableFile.swift) | hàm thuần trên `String` cho file tắt: `parse`/`serialize`/`adding`/`removing`/`union` | 81 |
| [`…/QuickTranslationRuleDisableStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDisableStore.swift) | chủ **hai** file tắt; `Snapshot.isDisabled(pattern:scopeRank:)` là toàn bộ ngữ nghĩa | 239 |
| [`…/QuickTranslationRuleDiagnostics.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleDiagnostics.swift) | soi một đoạn, giữ cả rule thua/đang tắt; dùng lại `collectFound` + `select` | 196 |
| [`…/QuickTranslationRuleTransfer.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleTransfer.swift) | chuyển một rule sang phạm vi còn lại (**COPY**) + chia sẻ cả bộ riêng sang truyện khác | 71 |
| [`Services/Translation/Extensions/TranslationManager+BookScopedFiles.swift`](../../Sources/Services/Translation/Extensions/TranslationManager+BookScopedFiles.swift) | **một** nguồn khai tên file riêng truyện, thay 2 danh sách nhân bản cũ | 28 |
| [`Views/Reader/ReaderCopyOriginalOverlayView.swift`](../../Sources/Views/Reader/ReaderCopyOriginalOverlayView.swift) | panel Copy nội dung gốc; không có nút Hủy, mọi đường đóng đều copy | 202 |
| `Views/Reader/ReaderRuleTraceOverlayView.swift` *(xoá ở 1.3.334)* | màn Check rule: thanh gốc → nghĩa rule → nghĩa token → dải chip + popup ấn giữ | 383 |
| `Views/Reader/ReaderRuleTraceGuideSheet.swift` *(xoá ở 1.3.334)* | nội dung nút `?` | 74 |
| [`Views/Reader/Components/ReaderRuleChipStyle.swift`](../../Sources/Views/Reader/Components/ReaderRuleChipStyle.swift) | 3 mức màu chip + dấu ✓ của rule thắng | 61 |
| [`Views/Reader/Components/ReaderRuleTraceChip.swift`](../../Sources/Views/Reader/Components/ReaderRuleTraceChip.swift) | một chip + badge R/C + ấn giữ | 68 |
| [`Views/Reader/Extensions/ReaderView+RuleTools.swift`](../../Sources/Views/Reader/Extensions/ReaderView+RuleTools.swift) | hành vi + overlay của **cả hai** công cụ mới | 272 |
| [`Views/Reader/Extensions/ReaderView+Selection.swift`](../../Sources/Views/Reader/Extensions/ReaderView+Selection.swift) | khối biên tập vùng chọn dùng chung cho 4 panel (dời từ `ReaderView.swift`) | 179 |
| [`Views/Settings/Translation/QuickTranslationRuleEntryRow.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleEntryRow.swift) | hàng rule `[Sửa][Chuyển][Tắt][Xoá]`, mirror `DictionaryEntryRow` | 151 |
| [`Views/Settings/Translation/QuickTranslationRuleIOMenu.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleIOMenu.swift) | Nhập/Xuất/Xoá bộ rule riêng của một truyện | 168 |

* **`ReaderView.swift` 2286 → 2076 dòng.** Ngoài phần dời sang `+Selection`, lượt này **xoá 73 dòng code chết** không có caller nào: `sentenceSegments`, `translatedSentenceSegments`, `selectedTokens`, `isEditableSource`, `deleteMatch`.
* Thư mục: `Sources/Services/Translation/Engine/` 17 → **22** file, `Sources/Services/Translation/Extensions/` 3 → **4**, `Sources/Models/Translation/` +2, `Sources/Views/Reader/` +3, `Sources/Views/Reader/Components/` +2, `Sources/Views/Reader/Extensions/` +2, `Sources/Views/Settings/Translation/` 8 → **10**. Tổng Swift 388 → **404**. **Không** thêm resource bundled.

## Rule dịch Quick Translate: engine, màn hình quản lý và công tắc (1.3.272)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Translation/Engine/QuickTranslationRuleTokenSettings.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleTokenSettings.swift) | 8 `Kind` + khóa `UserDefaults` mặc định bật và `Configuration` bất biến/chữ ký cache cố định | 64 |
| [`Services/Translation/Engine/QuickTranslationRuleElement.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleElement.swift) | phần tử AST (`literal`/`numeral`/`chapterLabel`/`dictionary`/`group`) + `sourceTokenKinds` giữ cú pháp token gốc, width và literal edge cho prefilter/guard | 132 |
| [`…/QuickTranslationRuleIssue.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleIssue.swift) | 13 mã lỗi + 3 mức `Severity` (`hard`/`disabling`/`warning`) | 72 |
| [`…/QuickTranslationParsedRule.swift`](../../Sources/Services/Translation/Engine/QuickTranslationParsedRule.swift) | DTO rule đã tách dòng + dựng AST, chưa validate | 31 |
| [`…/QuickTranslationRuleParser.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleParser.swift) | text → AST: 4 định dạng dòng, token `<n y L ne pn vp hv w>`, group lồng đệ quy, `\x` escape, `<x>?`/`(a|b)?`, ghi `sourceTokenKinds` | 349 |
| [`…/QuickTranslationCompiledRule.swift`](../../Sources/Services/Translation/Engine/QuickTranslationCompiledRule.swift) | dạng thi hành + chỉ số ưu tiên/prefilter, `requiredTokenKinds` và `isEnabled(configuration:)` | 93 |
| [`…/QuickTranslationRuleCompiler.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleCompiler.swift) | validate + tính chỉ số ưu tiên + boundary guard + gộp token cả trong group | 310 |
| [`…/QuickTranslationNumberFormatter.swift`](../../Sources/Services/Translation/Engine/QuickTranslationNumberFormatter.swift) | lớp ký tự `<n>/<y>/<L>` + `chineseNumber` cộng dồn section (parity reference) | 112 |
| [`…/QuickTranslationDictionaryToken.swift`](../../Sources/Services/Translation/Engine/QuickTranslationDictionaryToken.swift) | ràng buộc từ điển qua `findAllPrefixMatches`; `<pn>` **không** phụ thuộc `isTranslationPronounsEnabled` | 131 |
| [`…/QuickTranslationLiteralIndex.swift`](../../Sources/Services/Translation/Engine/QuickTranslationLiteralIndex.swift) | prefilter theo literal bắt buộc + suy tập vị trí bắt đầu | 98 |
| [`…/QuickTranslationRuleMatcher.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleMatcher.swift) | AST-walk backtracking bằng stack frame + cap 4.000 bước | 200 |
| [`…/QuickTranslationRuleSnapshot.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleSnapshot.swift) | bản chụp bất biến: `sourceHash`, `generation`, rule/literal index và warning đã cắt | 56 |
| [`…/QuickTranslationRewriteResult.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRewriteResult.swift) | text + bản đồ đoạn nguồn↔output, `sourceRange(forOutputRange:)` | 62 |
| [`…/QuickTranslationRuleEngine.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleEngine.swift) | `rewrite`/`preview`: chụp cấu hình token → prefilter → lọc rule → matcher → sort/ghép; preview có 2 mode | 213 |
| [`…/QuickTranslationRuleStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleStore.swift) | `ObservableObject` singleton: nạp/tải/CRUD/import canonical TXT, `cacheTag` gồm chữ ký token, chẩn đoán | 352 |
| [`Services/Translation/Extensions/TranslateUtils+QuickTranslationRules.swift`](../../Sources/Services/Translation/Extensions/TranslateUtils+QuickTranslationRules.swift) | `translationSpansApplyingRules` + **nơi ở mới** của `buildTranslationSpans`/`findTranslatedTokenRange` | 131 |
| [`Views/Settings/Translation/QuickTranslationRulesView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRulesView.swift) | màn quản lý: trạng thái, tải/nhập/xuất/xoá, đường vào danh sách, cấu hình token và thử nhanh | 303 |
| [`Models/Dictionaries/DataImportMode.swift`](../../Sources/Models/Dictionaries/DataImportMode.swift) | enum 3 chế độ nhập dùng chung cho cả app (`replaceAll` / `overwriteExisting` / `keepExisting`) | 41 |
| [`Views/Settings/Translation/QuickTranslationRuleListView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleListView.swift) | **màn riêng**: danh sách key-stable + `.searchable`, đảo thứ tự file, phân trang 200, badge cảnh báo, nút `+` | 343 |
| [`Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleEditorSheet.swift) | sheet thêm/sửa **một** rule; giữ sheet mở khi `.rejected` và in đúng dòng lỗi | 132 |
| [`Services/Translation/Engine/QuickTranslationRuleRecordStore.swift`](../../Sources/Services/Translation/Engine/QuickTranslationRuleRecordStore.swift) | parse/merge/serialize TXT canonical: bỏ dòng hỏng, duplicate first-wins, update giữ vị trí, key mới append cuối | 128 |
| [`Services/Translation/Extensions/QuickTranslationRuleStore+Editing.swift`](../../Sources/Services/Translation/Extensions/QuickTranslationRuleStore+Editing.swift) | CRUD Store giữ mutation lock rồi sửa records theo `pattern` và ghi canonical | 53 |
| [`Views/Settings/Translation/QuickTranslationRuleIssueSheet.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleIssueSheet.swift) | sheet lỗi/cảnh báo theo dòng + copy toàn bộ | 98 |
| [`Views/Settings/Translation/QuickTranslationRuleTesterView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTesterView.swift) | ô thử nhanh: text/hit sau rewrite với mode theo cấu hình token hoặc coi mọi token bật | 117 |
| [`Views/Settings/Translation/QuickTranslationRuleTokenSettingsView.swift`](../../Sources/Views/Settings/Translation/QuickTranslationRuleTokenSettingsView.swift) | 8 `@AppStorage` Toggle, mỗi đổi dọn cache + phát một notification; không sửa file rule | 59 |
| [`Views/Settings/Main/QuickTranslateRuleSettingsRows.swift`](../../Sources/Views/Settings/Main/QuickTranslateRuleSettingsRows.swift) | hai dòng Settings (link + công tắc), bọc `Group` để thành hai row | 39 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/Translation/Utils/TranslateUtils.swift`](../../Sources/Services/Translation/Utils/TranslateUtils.swift) | 1041 → **1023** | `performTranslation` gọi `rewrite` ở đầu; tham số `applyingQuickTranslationRules` xuyên `translateMeta`/`translateContent`/`translateChapterTitle`/`translateText`; cache key `v3` → `v4` (+`q:`); `translationGenerationToken` nhúng `cacheTag`; `postProcessText`/`findTranslatedTokenRange` bỏ `private`; **dời** `buildTranslationSpans` + `findTranslatedTokenRange` sang file `+QuickTranslationRules` |
| [`Views/Settings/Main/SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) | 443 → **448** | chèn `QuickTranslateRuleSettingsRows` vào section "Dịch Thuật Quick Translate", dưới hai link TOC/lọc rác |
| [`App/FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) | 108 → **113** | `AppLaunchRootView.onAppear` chạy `Task.detached { QuickTranslationRuleStore.shared.prewarm() }` |
| [`Services/Extensions/Engine/JSExecutor.swift`](../../Sources/Services/Extensions/Engine/JSExecutor.swift) | 1514 → **1516** | `_nativeQtTranslate` truyền `applyingQuickTranslationRules: false` cho hai nhánh `translateChapterTitle`/`translateMeta` |
| [`Services/Backup/BackupConfigArchiver.swift`](../../Sources/Services/Backup/BackupConfigArchiver.swift) | 109 → **136** | `Report.quickTranslateRules`, stage file rule trên máy, `restoreQuickTranslateRules` (ghi + nạp lại store) |
| [`Services/Backup/BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) | 143 → **149** | `quickTranslateRules = "config/QuickTranslateRules.txt"`, `quickTranslateRulesFileName` |

* **Không có resource nào được bundled.** Bộ rule mặc định nằm trên HuggingFace (`datasets/raikiri1498/vietpharse/resolve/main/QuickTranslateRules.txt`, cùng chỗ với `vietpharse.txt`/`phienam.txt`) và được tải xuống `translate/QuickTranslateRules.txt` bằng nút trong màn quản lý — app không mang theo file rule nào.
* Tổng file Swift 362 → **388** (+26, không xoá file nào). Không thư mục resource nào mới. `Sources/Services/Translation/Engine/` 1 → **17** file; `Sources/Services/Translation/Extensions/` 1 → **3** file; `Sources/Views/Settings/Translation/` 2 → **8** file; `Sources/Models/Dictionaries/` +1 (`DataImportMode`).
* Cạnh mới: `TranslateUtils` → `QuickTranslationRuleEngine` → {`QuickTranslationRuleStore`, `QuickTranslationRuleTokenSettings`, `QuickTranslationRuleMatcher`, `QuickTranslationLiteralIndex`}; `QuickTranslationDictionaryToken` → {`TranslationManager`, `TrieDictionary`, `VietPhraseTokenizer`, `TranslateUtils.getFirstMeaning`}; `QuickTranslationRuleStore` → {`TranslationManager`, `TranslateUtils`, `AppLogger`}; `AppLaunchRootView` → `QuickTranslationRuleStore`; `BackupConfigArchiver` → `QuickTranslationRuleStore`; `SettingsView` → `QuickTranslateRuleSettingsRows` → `QuickTranslationRulesView` → `QuickTranslationRuleIssueSheet` / `QuickTranslationRuleTokenSettingsView` / `QuickTranslationRuleTesterView`.
* Không cạnh nào bị xoá. `TranslateUtils` ↔ store là **hai chiều** (store gọi `clearCache`, `TranslateUtils` đọc `cacheTag`) nhưng cả hai đều là type static/singleton không giữ nhau, nên không có vòng khởi tạo.

## Nút -/+ ngưỡng dọn truyện cũ, bấm ra ngoài là tắt bàn phím (1.3.266)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Common/Utils/KeyboardDismissGesture.swift`](../../Sources/Common/Utils/KeyboardDismissGesture.swift) | singleton `@MainActor` gắn `UITapGestureRecognizer` lên `UIWindow` level `.normal` để bấm ra ngoài ô nhập là tắt bàn phím: `activate()`, `installIfNeeded()`, `handleTap(_:)`, `isEditableTextInput(_:)` + hai hàm `UIGestureRecognizerDelegate` | 112 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift`](../../Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift) | 209 → **238** | `clampedInactiveDays`, `nudgeButton(systemImage:delta:)`; `thresholdSection` đổi bố cục: nút −/+ kẹp hai đầu slider, mốc 7/365 xuống dưới thanh trượt |
| [`App/FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) | 107 → **108** | `AppLaunchRootView.onAppear` gọi thêm `KeyboardDismissGesture.shared.activate()` (dòng đầu, trước hai lệnh drain của `BookStorageManager`) |

* Tổng file Swift 361 → **362** (+1, không xoá file nào). Không thư mục mới: `Sources/Common/Utils/` 7 → **8** file.
* Cạnh mới: `AppLaunchRootView` (App) → `KeyboardDismissGesture` (Common). `KeyboardDismissGesture` chỉ phụ thuộc `UIKit` — **không** `SwiftUI`, không type nào của repo, nên nó là lá của đồ thị và không tạo vòng. Không cạnh nào bị xoá.
* `Common/Extensions/View+Keyboard.swift` (`hideKeyboard()` gửi `resignFirstResponder`) **vẫn còn nguyên** và vẫn có người gọi (`ExtensionScriptEditorView`, `ReaderJunkDeleteOverlayView`, `ReaderDefinitionOverlayView` gọi thẳng `UIApplication.sendAction`): đó là các chỗ tắt bàn phím **chủ động** theo lệnh (nút Xong, đóng overlay), khác nhiệm vụ với recognizer nền.

## Backup quy tắc mục lục, xuất nhập công cụ tra cứu nhanh (1.3.265)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Backup/BackupConfigArchiver.swift`](../../Sources/Services/Backup/BackupConfigArchiver.swift) | chủ nhánh archive `config/`: `stage(into:) -> Int`, `restore(from:) -> Report` (`tocRules`/`searchEngines`/`errors`/`restoredFiles`) | 109 |
| [`Models/Dictionaries/SearchEngineTransfer.swift`](../../Sources/Models/Dictionaries/SearchEngineTransfer.swift) | codec + luật gộp công cụ tra cứu dùng chung cho View và archiver: `encode`, `decode(_:maxSizeBytes:) -> Result<_, Failure>`, `merged(current:imported:)`, `newCount`, `signature(of:)` | 107 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Settings/Search/SearchEnginesConfigView.swift`](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift) | 116 → **259** | `ExportDocument`, menu toolbar Nhập/Xuất JSON, `DocumentPickerPresenter` trong `.background`, `confirmationDialog` Gộp/Thay thế + `importDialogMessage`, `handlePickedFile`, `applyImport(replacing:)`, `exportEngines`, `cleanUpExportFile` |
| [`Services/Backup/BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) | 271 → **280** | `Outcome.config: BackupConfigArchiver.Report` (nối vào `errors`), gọi `BackupConfigArchiver.restore` dưới cùng cờ `restoreSettings` |
| [`Services/Backup/BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) | 136 → **143** | hằng `tocRules = "config/toc_rules.json"`, `searchEngines = "config/search_engines.json"`, `tocRulesFileName` |
| [`Services/Backup/BackupManifest.swift`](../../Sources/Services/Backup/BackupManifest.swift) | 108 → **114** | `Counts.config` + `CodingKeys` + `decodeIfPresent(…) ?? 0` (file tạo trước 1.3.265 đọc thành 0) |
| [`Views/Settings/Backup/RestoreOptionsSheet.swift`](../../Sources/Views/Settings/Backup/RestoreOptionsSheet.swift) | 123 → **130** | công tắc bật sẵn khi `counts.settings > 0 \|\| counts.config > 0`, `infoRow("File cấu hình", …)`, footer nói rõ gộp quy tắc mục lục + công cụ tra cứu |
| [`Models/Dictionaries/SearchEngine.swift`](../../Sources/Models/Dictionaries/SearchEngine.swift) | 49 → **54** | `static let storageKey = "custom_search_engines"`; `loadEngines`/`saveEngines` dùng hằng thay chuỗi trần |
| [`Services/Backup/BackupSettingsArchiver.swift`](../../Sources/Services/Backup/BackupSettingsArchiver.swift) | 123 → **127** | thêm `SearchEngine.storageKey` vào `deniedKeys` (chủ mới là `BackupConfigArchiver` để khôi phục gộp được) |
| [`Services/Backup/BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) | 252 → **253** | `counts.config = try BackupConfigArchiver.stage(into: staging)` |
| [`Services/Backup/BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) | 290 → **293** | nối ", N công cụ tra cứu" vào toast khi `outcome.config.searchEngines > 0` |
| [`Views/Settings/Backup/BackupHubView.swift`](../../Sources/Views/Settings/Backup/BackupHubView.swift) | 206 | **chỉ đổi chuỗi** footer: nêu quy tắc mục lục + công cụ tra cứu, và luật thay ký tự TTS đi theo nhóm `.dictCustom` |
| [`Services/Backup/BackupScope.swift`](../../Sources/Services/Backup/BackupScope.swift) | 55 | **chỉ đổi chuỗi** `subtitle` của `.dictCustom` (thêm "luật thay ký tự TTS") |

* Tổng file Swift 359 → **361** (+2, không xoá file nào). Không thư mục mới: `Sources/Models/Dictionaries/` và `Sources/Services/Backup/` (22 → **23** file) đều đã có.
* Cạnh mới: `BackupExportWorker`/`BackupRestoreWorker` → `BackupConfigArchiver` → {`BackupPaths`, `BackupZipArchive`, `TranslateUtils`, `TranslationManager`, `SearchEngine`, `SearchEngineTransfer`, `AppLogger`}; `SearchEnginesConfigView` → `SearchEngineTransfer`. `SearchEngineTransfer` chỉ phụ thuộc `Foundation` + `SearchEngine` (tầng `Models`, gọi được từ cả `Views` và `Services`).
* Không cạnh nào bị xoá. `BackupRestoreWorker.Outcome` thêm field nhưng khởi tạo nội bộ; chữ ký công khai của `BackupConfigArchiver` là hai hàm static nên không call site cũ nào phải sửa.

## Backup kèm cài đặt, sửa nghĩa tại chỗ, không dọn truyện trên kệ (1.3.264)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Views/Dictionary/ManageDefinitionsDraft.swift`](../../Sources/Views/Dictionary/ManageDefinitionsDraft.swift) | bản nháp thuần (không `import SwiftUI`) của màn Quản lý nghĩa: `Row` có `id: UUID`/`isDeleted`/`preservesEmpty`, `activeMeanings`, `move`/`insertEmptyRow`/`appendEmptyRow`, `splitMeanings` | 126 |
| [`Services/Backup/BackupSettingsArchiver.swift`](../../Sources/Services/Backup/BackupSettingsArchiver.swift) | chụp/ghi lại `UserDefaults` dạng plist nhị phân: `isExportable(key:)`, `exportableSnapshot()`, `stage(into:)`, `restore(from:) -> Report` | 123 |
| [`Views/Dictionary/ManageDefinitionRowView.swift`](../../Sources/Views/Dictionary/ManageDefinitionRowView.swift) | một hàng nghĩa: `TextField` + 4 nút icon `.borderless` (lên/xuống/chèn trên/xoá, hoặc hoàn tác khi đã xoá mềm) | 73 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Dictionary/ManageDefinitionsView.swift`](../../Sources/Views/Dictionary/ManageDefinitionsView.swift) | 343 → **186** | thay 4 khối `TextField` "thêm nghĩa" + `.alert` nhập nghĩa bằng `@State draft` + `ManageDefinitionRowView`; `textBinding(rowId:source:)`, `saveAllChangesToDisk()` lặp `editableSources` và bỏ qua nhóm không đổi, `mergedMatches(originals:draft:)` |
| [`Services/Backup/BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) | 249 → **271** | `Options.restoreSettings`, `Outcome.settings: BackupSettingsArchiver.Report`, gọi `BackupSettingsArchiver.restore` ở **bước cuối** của `restore()` |
| [`Services/Backup/BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) | 248 → **252** | `counts.settings = try BackupSettingsArchiver.stage(into: staging)` sau phần từ điển |
| [`Views/Settings/Backup/RestoreOptionsSheet.swift`](../../Sources/Views/Settings/Backup/RestoreOptionsSheet.swift) | 111 → **123** | `@State restoreSettings` (khởi tạo theo `manifest.counts.settings > 0`), section công tắc "Khôi phục cài đặt & cấu hình", `infoRow("Khoá cài đặt", …)` |
| [`Services/Backup/BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) | 130 → **136** | hằng `settings = "settings/user_defaults.plist"` |
| [`Services/Backup/BackupManifest.swift`](../../Sources/Services/Backup/BackupManifest.swift) | 103 → **108** | `Counts.settings` + `CodingKeys` + `decodeIfPresent(… ) ?? 0` (file tạo trước 1.3.264 đọc thành 0) |
| [`Services/Cleanup/StaleBookCleanupCoordinator.swift`](../../Sources/Services/Cleanup/StaleBookCleanupCoordinator.swift) | 120 → **126** | `guard !book.isOnShelf` trong `staleBookIds` + doc comment thu hẹp phạm vi về phần lịch sử |
| [`Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift`](../../Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift) | 208 → **209** | **chỉ đổi chuỗi** hai footer cho khớp phạm vi mới (không markdown `**` vì `Text` nối chuỗi không parse) |
| [`Services/Backup/BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) | 287 → **290** | nối "Mở lại app để cài đặt có hiệu lực" vào toast khi `outcome.settings.restoredKeys > 0` |
| [`Views/Settings/Backup/BackupHubView.swift`](../../Sources/Views/Settings/Backup/BackupHubView.swift) | 206 | **chỉ đổi chuỗi** footer: mọi bản sao lưu đều kèm cài đặt (trừ khoá API và token) |

* Tổng file Swift 356 → **359** (+3, không xoá file nào). Không thư mục mới: `Sources/Views/Dictionary/` và `Sources/Services/Backup/` đều đã có.
* Cạnh mới: `BackupExportWorker` → `BackupSettingsArchiver` → {`BackupPaths`, `BackupZipArchive`, `AppLogger`}; `BackupRestoreWorker` → `BackupSettingsArchiver`; `ManageDefinitionsView` → {`ManageDefinitionsDraft`, `ManageDefinitionRowView`}. `ManageDefinitionsDraft` **không** phụ thuộc gì ngoài `Foundation` + `DictionaryMatchInfo`.
* Cạnh bị xoá: `ManageDefinitionsView` không còn dựng `.alert` nhập nghĩa nào. `ManageDefinitionsView(word:bookId:matches:onChanged:)` **giữ nguyên chữ ký** nên call site duy nhất ([ReaderDefinitionOverlayView.swift](../../Sources/Views/Reader/ReaderDefinitionOverlayView.swift#L1)) không phải sửa; `BackupRestoreWorker.Options.init` thêm tham số **có giá trị mặc định** nên các call site cũ vẫn biên dịch.

## Tự xoá truyện cũ, tuỳ chọn số chương, backup từ điển TTS, xoá báo đã đọc (1.3.263)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift`](../../Sources/Views/Settings/Cleanup/StaleBookCleanupSettingsView.swift) | màn cấu hình dọn truyện cũ: bật/tắt, thanh kéo ngưỡng ngày, nhịp chạy, đếm trước số truyện sẽ xoá + nút "Dọn ngay" có `confirmationDialog` | 208 |
| [`Services/Cleanup/StaleBookCleanupPolicy.swift`](../../Sources/Services/Cleanup/StaleBookCleanupPolicy.swift) | nguồn duy nhất của khoá UserDefaults, hằng, `shouldRun()`/`markRun()`/`cutoffDate()`; mặc định **tắt**, hoãn khởi động 40s | 126 |
| [`Services/Cleanup/StaleBookCleanupCoordinator.swift`](../../Sources/Services/Cleanup/StaleBookCleanupCoordinator.swift) | `@MainActor enum` điều phối: `runIfDue`/`runNow`/`previewStaleCount`, lọc truyện được bảo vệ, gọi `BookStorageManager.deleteBooksAsync`, trả `Outcome` | 120 |
| [`Views/Settings/Main/StaleBookCleanupSettingsSection.swift`](../../Sources/Views/Settings/Main/StaleBookCleanupSettingsSection.swift) | một `Section` + `NavigationLink` mở màn trên, cùng khuôn `BackupSettingsSection` | 12 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Download/TaskOptionsSheet.swift`](../../Sources/Views/Download/TaskOptionsSheet.swift) | 209 → **277** | thêm `customLimit` + `customLimitRow` (thanh kéo 1...1000 step 1, hai nút −/+ `.borderless`), `clampCustomLimit`, `effectiveLimit`; `startTask()` enqueue `effectiveLimit` chứ không phải `limitOption` |
| [`Services/Download/DownloadManager.swift`](../../Sources/Services/Download/DownloadManager.swift) | 437 → **467** | `ChapterLimitOption` enum → struct `RawRepresentable, Hashable, Codable, CaseIterable, Sendable`; thêm `.custom` (−1), `customRange`, `title`, `limitValue`, `init(from:)`/`encode(to:)` |
| [`Services/Backup/BackupDictionaryRestorer.swift`](../../Sources/Services/Backup/BackupDictionaryRestorer.swift) | 127 → **242** | `restoreTTSDictionaries` + `mergeStringPlist`/`readStringPlist`/`mergeReplacementRules`; nạp lại `TextPreprocessor`/`TTSReplacementManager` sau khi gộp |
| [`Views/MainTabView.swift`](../../Sources/Views/MainTabView.swift) | 118 → **139** | `.task` thứ hai + `runStaleBookCleanupIfDue(container:)` trong extension, cùng khuôn `runAutoDriveBackupIfDue` |
| [`Services/Backup/BackupDictionaryArchiver.swift`](../../Sources/Services/Backup/BackupDictionaryArchiver.swift) | 93 → **114** | `stageTTSDictionaries` stage 3 file `FreeBook/TTS/` vào `dict/tts/`, cộng vào `Summary.customFiles` |
| [`Services/Backup/BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) | 113 → **130** | `ttsDictionaryFolder`, `ttsDictionaryFiles`, `ttsDictionaryDirectory` (getter thuần, không tạo thư mục) |
| [`Services/Backup/BackupPayload.swift`](../../Sources/Services/Backup/BackupPayload.swift) | 204 → **217** | `BookRecord.isLocalBook` **computed** — không thêm stored property/`CodingKeys` nên JSON cũ vẫn decode |
| [`Services/Backup/BackupSizeEstimator.swift`](../../Sources/Services/Backup/BackupSizeEstimator.swift) | 45 → **54** | `.dictCustom` cộng thêm 3 file TTS; `.content` ghi rõ ước tính **thiếu** phần truyện local khi nhóm này tắt |
| [`Services/Backup/BackupExportWorker.swift`](../../Sources/Services/Backup/BackupExportWorker.swift) | 240 → **248** | `contentBooks` = tất cả truyện khi bật `.content`, ngược lại chỉ `isLocalBook` |
| [`Common/Services/NotificationInboxManager.swift`](../../Sources/Common/Services/NotificationInboxManager.swift) | 88 → **93** | `deleteUnread()` → `deleteRead()`, thêm `hasRead` |
| [`Services/Backup/BackupRestoreWorker.swift`](../../Sources/Services/Backup/BackupRestoreWorker.swift) | 245 → **249** | `wantsContent = scopes.contains(.content) \|\| book.isLocalBook` |
| [`Services/Backup/BackupScope.swift`](../../Sources/Services/Backup/BackupScope.swift) | 55 | **chỉ đổi chuỗi** `subtitle` của `.content` và `.dictCustom`, không thêm/bớt case |
| [`Services/Download/DownloadManager+TaskStore.swift`](../../Sources/Services/Download/DownloadManager+TaskStore.swift) | 277 → **279** | bỏ `?? .all` khi dựng `limit` — `init(rawValue:)` của struct không thất bại |
| [`Views/Settings/Main/SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) | 441 → **443** | chèn `StaleBookCleanupSettingsSection()` ngay sau `BackupSettingsSection()` (baseline legacy 453) |
| [`Views/Shelf/ShelfMain/NotificationInboxView.swift`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift) | 307 | đổi nhãn + gọi `deleteRead()`, `.disabled(!inbox.hasRead)` |

* Tổng file Swift 352 → **356** (+4, không xoá file nào). Thư mục **mới**: `Sources/Services/Cleanup/` và `Sources/Views/Settings/Cleanup/`.
* Cạnh mới: `MainTabView` → `StaleBookCleanupPolicy` + `StaleBookCleanupCoordinator`; `SettingsView` → `StaleBookCleanupSettingsSection` → `StaleBookCleanupSettingsView` → {`StaleBookCleanupPolicy`, `StaleBookCleanupCoordinator`, `ToastManager`}; `StaleBookCleanupCoordinator` → {`StaleBookCleanupPolicy`, `BookStorageManager`, `TTSManager`, `DownloadManager`, `AppLogger`}; `BackupDictionaryRestorer` → {`TextPreprocessor`, `TTSReplacementManager`, `TTSReplacementRule`} (cạnh mới trong `Services/`, cùng tầng).
* Không có cạnh nào bị xoá. `deleteUnread()` chỉ có **một** call site (`NotificationInboxView.swift:246`) nên việc đổi tên không lan; `enqueueTask` cũng chỉ có **một** call site (`TaskOptionsSheet.swift:258`) nên `effectiveLimit` phủ hết đường vào hàng đợi.

## Nút back không chữ chạy thật, ô URL tự bôi đen, bypass browser nhiều tab (1.3.262)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Views/Common/BypassBrowserTabStore.swift`](../../Sources/Views/Common/BypassBrowserTabStore.swift) | chủ sở hữu **duy nhất** mọi `WKWebView` của phiên duyệt bypass; `WKNavigationDelegate` + `WKUIDelegate` dùng chung; trần 8 tab; mở tab mới cho `target="_blank"`/`window.open` | 149 |
| [`Views/Common/BypassBrowserHomePage.swift`](../../Sources/Views/Common/BypassBrowserHomePage.swift) | tách nguyên văn HTML trang Home (Google/Bing/Baidu + thẻ tiện ích đã cài) ra khỏi `BypassWebView` | 170 |
| [`Views/Common/BypassBrowserTab.swift`](../../Sources/Views/Common/BypassBrowserTab.swift) | một tab: `WKWebView` riêng + 6 `NSKeyValueObservation` phản chiếu tiêu đề/URL/tiến độ/cờ điều hướng; `pendingUrl` nạp một lần | 107 |
| [`Views/Common/URLBarTextField.swift`](../../Sources/Views/Common/URLBarTextField.swift) | bọc `UITextField` để **chạm là bôi đen toàn bộ** URL (SwiftUI `TextField` iOS 17 không có API chọn hết) | 102 |
| [`Views/Common/BypassBrowserTabBar.swift`](../../Sources/Views/Common/BypassBrowserTabBar.swift) | dải pill tab ngang, chỉ hiện khi > 1 tab; `TabPill` nest | 62 |
| [`Views/Common/BypassBrowserWebPane.swift`](../../Sources/Views/Common/BypassBrowserWebPane.swift) | `UIViewRepresentable` bọc `UIView` container; đổi tab = đổi subview nên giữ lịch sử + vị trí cuộn | 38 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Common/BypassWebView.swift`](../../Sources/Views/Common/BypassWebView.swift) | 599 → **350** | gỡ `WebViewStore`, `SwiftUIWebView` + Coordinator, `isDomainBlocked`, `generateHomeHtml()` và 6 `@State` phản chiếu trạng thái webview; nay chỉ giữ `@StateObject store`, thanh địa chỉ và logic import. API `BypassWebView(urlString:host:onImport:)` **không đổi** |
| [`Common/Utils/NavigationBarAppearance.swift`](../../Sources/Common/Utils/NavigationBarAppearance.swift) | 44 → **56** | dựng 4 `UINavigationBarAppearance()` **mới** thay vì đọc rồi sửa tại chỗ proxy (getter proxy không trả đối tượng đang hiệu lực ⇒ bản 1.3.260 vô tác dụng); thêm `.font` 0.1pt để nhãn không chiếm chỗ |

* Tổng file Swift 346 → **352** (+6, không xoá file nào).
* Cạnh mới: `BypassWebView` → {`BypassBrowserTabStore`, `BypassBrowserTabBar`, `BypassBrowserWebPane`, `BypassBrowserHomePage`, `URLBarTextField`}; `BypassBrowserTabStore` → {`BypassBrowserTab`, `isEngineDomainBlocked` (`Services/Extensions/Engine/Browser/WebViewLoader.swift`), `AppLogger`}; `BypassBrowserTabBar`/`BypassBrowserWebPane` → `BypassBrowserTab`. Danh sách tên miền chặn **không** bị nhân bản: store gọi lại `isEngineDomainBlocked` thay vì giữ bản sao như `BypassWebView` cũ.
* 6 call site của `BypassWebView` không phải sửa: `BookDetailActionSheetView.swift:20`, `DiscoveryView.swift:440` và `:846`, `ReaderView.swift:712` và `:736`, `ShelfView.swift:332`.

## Nhảy + tô kết quả tìm rồi tắt cuộn; tự tắt cuộn khi kéo tay; dọn tiện ích kho đã gỡ (1.3.261)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Views/Reader/Components/ReaderUserScrollDetector.swift`](../../Sources/Views/Reader/Components/ReaderUserScrollDetector.swift) | `UIViewRepresentable` gắn `UIPanGestureRecognizer` không tiêu thụ touch lên `UIScrollView` bao ngoài; báo lên khi ngón tay kéo dọc quá ngưỡng — phân biệt "người cuộn" với cú `scrollTo` của TTS. `Coordinator`/`ProbeView` nest | 143 |
| [`Models/Extensions/PruneRepositoryExtensionsCommand.swift`](../../Sources/Models/Extensions/PruneRepositoryExtensionsCommand.swift) | DTO bất biến: `repositoryUrl` + `keepPackageIds` cho lệnh dọn tiện ích kho đã gỡ; tập giữ rỗng = không xoá gì | 22 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Common/Utils/ReaderSearchMatcher.swift`](../../Sources/Common/Utils/ReaderSearchMatcher.swift) | 88 → **120** | thêm value type `Highlight` (nest) + `firstHighlightRange(of:in:)` trả `NSRange` UTF-16 trên chuỗi đang hiển thị |
| [`Views/Reader/ParagraphCardView.swift`](../../Sources/Views/Reader/ParagraphCardView.swift) | 101 → **106** | `displayText(for:isTranslationEnabled:)` thành `static` — nguồn duy nhất của luật "dịch hay gốc" để range tìm trỏ đúng chuỗi trong `UITextView` |
| [`Views/Reader/ReaderSearchView.swift`](../../Sources/Views/Reader/ReaderSearchView.swift) | 220 → **223** | `onSelect` mang thêm `query` đã trim lên `ReaderView` để tô lại đúng chữ |
| [`Views/Reader/ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift) | 2241 → **2286** | `@State searchHighlight`; `showingFloatingMenu` → `internal`; `jumpToReaderSearchResult` đặt vệt + tắt cuộn; `effectiveHighlightRange` (TTS thắng vệt tìm); gắn `ReaderUserScrollDetector` trong content ScrollView; xoá vệt cũ khi đổi chương |
| [`Views/Reader/Extensions/ReaderView+Controls.swift`](../../Sources/Views/Reader/Extensions/ReaderView+Controls.swift) | 211 → **248** | `searchHighlightRange(for:chapterIndex:isTranslationEnabled:)` + `handleUserScrollWhilePlaying()` (4 cửa chặn tự tắt oan) |
| [`Services/Extensions/ExtensionTransactionCoordinator.swift`](../../Sources/Services/Extensions/ExtensionTransactionCoordinator.swift) | 175 → **213** | `pruneRepositoryExtensions(command:in:)` — xoá bản ghi tiện ích kho đã gỡ, chừa tiện ích đã cài (`localPath` khác rỗng), một `save()` |
| [`Views/Extensions/Manager/RepositoryManagerView.swift`](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift) | 709 → **726** | `syncExtensions` gọi prune sau khi upsert thành công; tập giữ = `packageId` của command vừa ghi |

* Tổng file Swift 344 → **346** (+2, không xoá file nào).
* Cạnh mới: `ReaderView` → `ReaderUserScrollDetector` (lá, `import SwiftUI`+`UIKit`; dùng lại `extension UIView.parentScrollView` khai ở `ReaderTextView.swift`); `ReaderView`/`ReaderView+Controls` → `ReaderSearchMatcher.firstHighlightRange` + `ParagraphCardView.displayText`; `RepositoryManagerView` → `ExtensionTransactionCoordinator.pruneRepositoryExtensions` → `PruneRepositoryExtensionsCommand`.
* Vệt tìm **không** đi qua `ReaderSelectionMapper` (đã xoá 1.3.81): range tính lại mỗi lần render trên chuỗi hiển thị, TTS highlight vẫn thắng. Prune chỉ xoá bản ghi, không đụng file vì tiện ích đã cài bị loại ngay ở bộ lọc.


## Tự động sao lưu lên Drive, nút tìm ra header, thông báo đánh dấu đã đọc, nút back không chữ (1.3.260)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Common/Utils/NavigationBarAppearance.swift`](../../Sources/Common/Utils/NavigationBarAppearance.swift) | sửa **tại chỗ** `UINavigationBar.appearance()` để nút back mọi màn chỉ còn mũi tên (iOS 17 không có `.navigationBarBackButtonDisplayMode`) | 44 |
| [`Services/Backup/DriveAutoBackupPolicy.swift`](../../Sources/Services/Backup/DriveAutoBackupPolicy.swift) | nguồn duy nhất của "có được tự động sao lưu lúc này không" + mọi hằng điều tiết (`maxVersions = 5`, delay khởi động, nhóm mặc định) | 123 |
| [`Services/Backup/BackupCoordinator+AutoDrive.swift`](../../Sources/Services/Backup/BackupCoordinator+AutoDrive.swift) | một lượt tự động: export → upload → dọn bản `freebook-auto-*` cũ; trả `AutoDriveBackupOutcome`, không toast | 125 |
| [`Views/Settings/Backup/DriveAutoBackupSettingsView.swift`](../../Sources/Views/Settings/Backup/DriveAutoBackupSettingsView.swift) | bật/tắt, nhịp chạy, nhóm nội dung, trạng thái + nút chạy ngay; `@AppStorage` bind đúng key của policy | 143 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/Backup/BackupPaths.swift`](../../Sources/Services/Backup/BackupPaths.swift) | 96 → **113** | tách tiền tố `freebook-auto-` khỏi `freebook-`, thêm `makeAutoBackupFileName`/`isAutoBackupFileName` + helper `timestamp(at:)` dùng chung |
| [`Services/Backup/BackupCoordinator.swift`](../../Sources/Services/Backup/BackupCoordinator.swift) | 275 → **287** | mở đúng hai cửa nội bộ `setBusy`/`setProgress` cho extension `+AutoDrive` (hai thuộc tính là `private(set)`) |
| [`Views/Settings/Backup/BackupHubView.swift`](../../Sources/Views/Settings/Backup/BackupHubView.swift) | 190 → **206** | `NavigationLink` thứ hai trong `driveSection` mở màn tự động sao lưu + `autoBackupStateText` |
| [`Views/MainTabView.swift`](../../Sources/Views/MainTabView.swift) | 96 → **118** | `import SwiftData` + `.task { runAutoDriveBackupIfDue(container:) }` (hoãn ~25 s, một toast cho kết quả) |
| [`Views/Reader/ReaderHeaderFooterOverlayView.swift`](../../Sources/Views/Reader/ReaderHeaderFooterOverlayView.swift) | 210 → **215** | nút `magnifyingglass` cạnh nút cuộn-theo-TTS; gỡ mục "Tìm trong chương" khỏi menu `ellipsis` |
| [`Common/Services/NotificationInboxManager.swift`](../../Sources/Common/Services/NotificationInboxManager.swift) | 68 → **88** | thêm `hasUnread` + `markRead(_:)`; `clearAll()` → `deleteUnread()` (chỉ bỏ phần chưa đọc) |
| [`Views/Shelf/ShelfMain/NotificationInboxView.swift`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift) | 299 → **307** | hàng toast thành `Button` `.plain` gọi `markRead`; mục menu đổi thành "Xoá thông báo chưa đọc", `.disabled(!hasUnread)` |
| [`App/FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) | 105 → **107** | `init()` gọi `NavigationBarAppearance.applyTitlelessBackButton()` cạnh hai dòng `UITabBar.appearance()` |

* Tổng file Swift 340 → **344** (+4, không xoá file nào). `NotificationInboxStore.clearAll()` không còn caller nhưng **giữ lại** vì là primitive hợp lệ của store, không phải code chết của tính năng.
* Cạnh mới: `MainTabView` → `BackupCoordinator` (trước đây chỉ có `Views/Settings/Backup/**` đi vào coordinator — đây là đường vào **thứ hai**, chạy nền, dùng chung khoá `isBusy`); `BackupCoordinator+AutoDrive` → {`BackupExportWorker`, `GoogleDriveUploader`, `GoogleDriveClient`, `LocalBackupStore`, `DriveAutoBackupPolicy`, `BackupPaths`}; `DriveAutoBackupSettingsView` → {`DriveAutoBackupPolicy`, `BackupCoordinator`, `BackupScopeToggleList`}; `App/FreeBookApp` → `Common/Utils/NavigationBarAppearance` (lá, chỉ `import UIKit`).
* `Sources/Services/Backup/**` vẫn không `import SwiftUI` và không gọi `ToastManager.shared`: `+AutoDrive` **trả về** `AutoDriveBackupOutcome`, `MainTabView`/`DriveAutoBackupSettingsView` mới hiện toast.

## Gỡ tìm toàn văn toàn cục; tìm trong Reader + Trung tâm thông báo (1.3.258)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Common/Utils/ReaderSearchMatcher.swift`](../../Sources/Common/Utils/ReaderSearchMatcher.swift) | helper thuần: chuẩn hoá không dấu + case-insensitive, khớp `original`/`translated`, dựng snippet; `Paragraph`/`Chapter`/`Hit` nest | 88 |
| [`Views/Reader/ReaderSearchView.swift`](../../Sources/Views/Reader/ReaderSearchView.swift) | sheet tìm trong Reader: ô nhập + `List` kết quả nhóm theo chương, debounce 250 ms | 220 |
| [`Common/Services/NotificationInboxRecord.swift`](../../Sources/Common/Services/NotificationInboxRecord.swift) | DTO một toast đã hiện + `ToastType: Codable` (retroactive) | 54 |
| [`Common/Services/NotificationInboxStore.swift`](../../Sources/Common/Services/NotificationInboxStore.swift) | actor — chủ duy nhất `notifications.json`, `.atomic`, tối đa 200 record | 82 |
| [`Common/Services/NotificationInboxManager.swift`](../../Sources/Common/Services/NotificationInboxManager.swift) | `@MainActor ObservableObject` (Combine, không SwiftUI); gọi từ `ToastManager` | 68 |
| [`Views/Shelf/ShelfMain/NotificationInboxView.swift`](../../Sources/Views/Shelf/ShelfMain/NotificationInboxView.swift) | Trung tâm thông báo: gộp chương mới + toast, nhóm theo ngày; `InboxItem` nest | 299 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Views/Shelf/ShelfMain/ShelfSearchView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfSearchView.swift) | 264 → **219** | gỡ `SearchScope` + `Picker` phạm vi + nhánh `.content` → về đúng hình dạng cũ (chỉ tìm theo tên) |
| [`Services/ChapterText/ChapterPersistenceStore.swift`](../../Sources/Services/ChapterText/ChapterPersistenceStore.swift) | 926 → **915** | gỡ lời gọi `ChapterSearchIndex.indexChapter` |
| [`Common/Services/ToastManager.swift`](../../Sources/Common/Services/ToastManager.swift) | | `show(message:type:)` ghi vào `NotificationInboxManager` tại choke point |
| [`Views/Reader/ReaderView.swift`](../../Sources/Views/Reader/ReaderView.swift) | | `.sheet` ReaderSearch + `buildReaderSearchSnapshot`/`jumpToReaderSearchResult` |
| [`Views/Reader/ReaderHeaderFooterOverlayView.swift`](../../Sources/Views/Reader/ReaderHeaderFooterOverlayView.swift) | | mục "Tìm trong chương" trong menu `ellipsis` (`onOpenReaderSearch`) |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | | nút chuông leading `.toolbar` + `.sheet { NotificationInboxView }`, badge realtime |
| [`Views/MainTabView.swift`](../../Sources/Views/MainTabView.swift) | | preload inbox + `cleanupLegacyChapterSearchIndex()` |
| [`Views/Settings/Main/SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) | 443 → **441** | gỡ dòng `ChapterSearchSettingsSection()` |

* **File xoá (10)**: cả `Sources/Services/Search/` (7 file: `ChapterSearchPolicy`, `ChapterSearchIndexPath`, `ChapterSearchIndexDatabase`, `ChapterSearchHit`, `ChapterSearchSnippetBuilder`, `ChapterSearchIndex`, `ChapterSearchIndexBuilder`) + `ShelfContentSearchView.swift`, `ChapterSearchIndexSettingsView.swift`, `ChapterSearchSettingsSection.swift`. Thư mục `Sources/Views/Settings/Search/` biến mất.
* Tổng file Swift 344 → **340** (−10 +6). Không còn cạnh nào tới phân hệ Search đã gỡ. Cạnh mới: `ReaderView` → `ReaderSearchView` → `ReaderSearchMatcher` (lá, thuần); `ToastManager` → `NotificationInboxManager` → `NotificationInboxStore`; `NotificationInboxView` → {`NotificationInboxManager`, `NewChapterInboxManager`}.
* Trung tâm thông báo đặt ở `Common` vì `NotificationInboxManager` bị gọi từ `ToastManager` — luật cấm `Services/**` gọi `ToastManager`/`import SwiftUI`. Nguồn dữ liệu tìm-Reader là cache RAM (`ChapterCache`), không đọc đĩa/mạng, nên không tái lập đường crash của FTS5.

## Hộp thư chương mới (1.3.256)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/NewChapters/NewChapterRecord.swift`](../../Sources/Services/NewChapters/NewChapterRecord.swift) | DTO `Codable` cho một truyện: mốc `seen*` (người dùng đã thấy) vs kết quả `probed*` (lượt dò cuối) | 87 |
| [`Services/NewChapters/NewChapterStore.swift`](../../Sources/Services/NewChapters/NewChapterStore.swift) | actor — **chủ duy nhất** của `applicationSupportDirectory/new_chapters.json` | 107 |
| [`Services/NewChapters/NewChapterCheckPolicy.swift`](../../Sources/Services/NewChapters/NewChapterCheckPolicy.swift) | nguồn duy nhất của "có được kiểm tra lúc này không" + mọi hằng điều tiết | 110 |
| [`Services/NewChapters/NewChapterProbe.swift`](../../Sources/Services/NewChapters/NewChapterProbe.swift) | một lượt dò mục lục cho **một** truyện; không ghi đĩa, không toast, không SwiftData | 209 |
| [`Services/NewChapters/NewChapterInboxManager.swift`](../../Sources/Services/NewChapters/NewChapterInboxManager.swift) | `@MainActor ObservableObject` — điều phối lượt kiểm tra, `@Published records` cho badge | 138 |
| [`Views/Shelf/ShelfMain/Extensions/ShelfView+NewChapters.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+NewChapters.swift) | dựng `Target` từ `@Query`, badge, 3 đường refresh, một toast mỗi lượt | 127 |
| [`Views/Settings/NewChapters/NewChapterSettingsView.swift`](../../Sources/Views/Settings/NewChapters/NewChapterSettingsView.swift) | bật/tắt, chế độ chu kỳ hoặc mỗi ngày sau giờ chọn, trạng thái lượt gần nhất | 82 |
| [`Views/Settings/Main/NewChapterSettingsSection.swift`](../../Sources/Views/Settings/Main/NewChapterSettingsSection.swift) | section `Chương Mới` mở màn cài đặt, y hệt `BackupSettingsSection` | 12 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/Extensions/Workers/BookDetailLoader.swift`](../../Sources/Services/Extensions/Workers/BookDetailLoader.swift) | 97 → **112** | thêm `fetchPageTOC(snapshot:url:host:)` — mục lục của **đúng một** trang đã biết url |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 836 → **867** | `@Query allBooks`/`allExtensions` đổi `private` → `internal`, `@ObservedObject newChapters`, `.task`, 2 mục menu, `markSeen` lúc mở truyện, badge trong `bookItemView` |
| [`Views/MainTabView.swift`](../../Sources/Views/MainTabView.swift) | 76 → **79** | `.badge(newChapters.totalNewBooks)` trên tab Kệ Sách |
| [`Views/Settings/Main/SettingsView.swift`](../../Sources/Views/Settings/Main/SettingsView.swift) | 440 → **441** | một dòng `NewChapterSettingsSection()` |

* Tổng file Swift 326 → **334** (+8). Hai thư mục mới: [`Sources/Services/NewChapters/`](../../Sources/Services/NewChapters/NewChapterInboxManager.swift) (5 file) và [`Sources/Views/Settings/NewChapters/`](../../Sources/Views/Settings/NewChapters/NewChapterSettingsView.swift) (1 file). Không file nào bị xoá hay đổi tên.
* Chuỗi cạnh mới, một chiều: `ShelfView` → `ShelfView+NewChapters` → `NewChapterInboxManager` → {`NewChapterProbe`, `NewChapterStore`, `NewChapterCheckPolicy`} → `NewChapterProbe` → {[`BookDetailLoader`](../../Sources/Services/Extensions/Workers/BookDetailLoader.swift#L1), [`ChapterStore`](../../Sources/Services/ChapterText/ChapterStore/ChapterStoreActor.swift#L1)}. `NewChapterRecord` là lá (chỉ `Foundation`), `NewChapterStore` là **chủ duy nhất** của `new_chapters.json`.
* `NewChapterProbe` gọi **chỉ** `BookDetailLoader` ⇒ đường kiểm tra không thể vô tình tải nội dung chương; cạnh sang `ChapterStore.fetchOrderedTOC` chỉ dùng để lấy mốc lần đầu.
* Cạnh UI: `MainTabView` và `NewChapterSettingsView` cùng observe `NewChapterInboxManager.shared` (đúng tiền lệ `@ObservedObject … = X.shared`). [`BookListItemView`](../../Sources/Views/Common/BookListItemView.swift#L1) **không** bị sửa — badge là view em cạnh nó trong `HStack` của `ShelfView.bookItemView`, vì view đó dùng chung với Khám phá và sheet chia sẻ truyện.

## Nhập truyện PDF chỉ lấy lớp văn bản (1.3.255)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Import/PdfDocumentReader.swift`](../../Sources/Services/Import/PdfDocumentReader.swift) | **file duy nhất** `import PDFKit`: mở/mở khoá tài liệu, text từng trang, outline làm phẳng, metadata | 131 |
| [`Services/Import/PdfBookParser.swift`](../../Sources/Services/Import/PdfBookParser.swift) | outline → quy tắc TOC → mỗi trang một chương; đếm trang thiếu lớp văn bản để cảnh báo | 136 |

| File sửa | Dòng | Thay đổi |
|---|---|---|
| [`Services/Import/BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) | 107 → **125** | thêm `case pdf`, magic `%PDF-`, và `detect(fileNameOnly:) -> BookImportFormat?` để nhánh PDF không phải nạp `Data` |
| [`Services/Import/BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) | 214 → **257** | nhánh `.pdf`, `Request.password`, 3 `ImportError` mới (`passwordRequired`/`wrongPassword`/`noTextLayer`), `loadData(_:)` chỉ gọi khi nhánh cần byte |
| [`Services/Import/ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) | 27 → **30** | `warningNote` — cảnh báo mất mát nội dung người dùng phải tự chấp nhận |
| [`Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 307 → **342** | khối cảnh báo cam + `Toggle` chấp nhận, `canConfirm` chặn nút "Nhập", `.pdf` vào nhóm ẩn hàng Bảng mã |
| [`Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift) | 215 → **273** | `startImportParse`/`askImportPassword`/`submitImportPassword`/`cancelPasswordPrompt`; `reanalyzeImport` nhận `password` |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 811 → **836** | 3 `@State` mật khẩu, `PendingPasswordFile` (nest), `.alert` `SecureField`, `PendingImport.password` |

* Tổng file Swift 324 → **326** (+2), cả hai trong [`Sources/Services/Import/`](../../Sources/Services/Import/BookImportService.swift) (18 → **20** file). Không thư mục mới, không file bị xoá hay đổi tên.
* Quan hệ import mới: `Services/Import/PdfDocumentReader` → `PDFKit` (framework hệ thống, **không** sửa `project.yml`) — `PdfBookParser` chỉ nói chuyện với reader nên chỗ tách chương không biết gì về PDFKit; `PdfBookParser` → `TxtBookParser` (nhánh quy tắc TOC) + `XhtmlTextExtractor.dropLeadingTitle` (dùng chung với EPUB/DOCX/FB2).
* `Views/Shelf/ShelfMain/**` vẫn là phía gọi duy nhất của `Services/Import/**`; không có quan hệ mới nào theo chiều ngược.

## Sao lưu ảnh bìa của truyện nhập từ file (1.3.254)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Backup/BackupCoverArchiver.swift`](../../Sources/Services/Backup/BackupCoverArchiver.swift) | chủ duy nhất của entry `covers/<slug>.jpg`, cả hai chiều xuất/khôi phục | 80 |

* File sửa nội dung, quan hệ import không đổi: `BackupPaths.swift` 94 → **96** (`cover(slug:)`), `BackupPayload.swift` 196 → **204** (`BookRecord.hasUnrecoverableCover`), `BackupManifest.swift` 80 → **103** (`Counts.covers` + `CodingKeys` + `init(from:)` khoan nhượng), `BackupProgress.swift` 79 → **83** (19 pha: thêm `copyingCovers`/`restoringCovers`), `BackupExportWorker.swift` 232 → **240**, `BackupRestoreWorker.swift` 236 → **245** (`Outcome.covers`), `BackupCoordinator.swift` 259 → **275**, `BackupScope.swift` (chỉ sửa doc comment đã sai), `RestoreOptionsSheet.swift` 108 → **111**.
* Quan hệ mới: `Services/Backup/BackupCoverArchiver` → `Common/Services/ImageCacheManager` (`localCoverURL(for:)` — không đi qua `saveCover` để không nén lại JPEG) + `Services/Backup/BackupZipArchive`. Cả `BackupExportWorker` và `BackupRestoreWorker` gọi vào **một** file này, không tự dựng tên entry `covers/`.

## Xuất truyện TXT, EPUB, FB2, MOBI trong một tác vụ (1.3.253)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Export/BookExportRequest.swift`](../../Sources/Services/Export/BookExportRequest.swift) | DTO **bất biến** của một lần xuất; renderer không thấy `DownloadTask`/`Book`/SwiftData | 44 |
| [`Services/Export/BookExportFormat.swift`](../../Sources/Services/Export/BookExportFormat.swift) | `txt`/`epub3`/`fb2`/`mobi` + `fileExtension`/`taskType`/`supportsCover`/`supportsNavigation` | 72 |
| [`Services/Export/ExportRenderer.swift`](../../Sources/Services/Export/ExportRenderer.swift) | protocol `append(_:)`/`finish()`/`discard()` + `writtenChapterCount`/`hasContent` | 19 |
| [`Services/Export/ExportRendererFactory.swift`](../../Sources/Services/Export/ExportRendererFactory.swift) | `BookExportFormat` → renderer; `switch` liệt kê đủ case | 18 |
| [`Services/Export/ExportContentProvider.swift`](../../Sources/Services/Export/ExportContentProvider.swift) | lấy một chương (cache → tải → `.bin` → `ChapterStore`) + `Tally`; **dùng chung** cho tải và xuất | 111 |
| [`Services/Export/ExportChapterPayload.swift`](../../Sources/Services/Export/ExportChapterPayload.swift) | `ordinal`/`title`/`content` đưa vào renderer | 16 |
| [`Services/Export/ExportArtifact.swift`](../../Sources/Services/Export/ExportArtifact.swift) | kết quả `finish()` + `exists` — cổng chặn "hoàn thành mà không có file" | 23 |
| [`Services/Export/ExportStage.swift`](../../Sources/Services/Export/ExportStage.swift) | 3 giai đoạn hiển thị: đang lấy chương / đang tạo file / sẵn sàng chia sẻ | 21 |
| [`Services/Export/ExportRenderError.swift`](../../Sources/Services/Export/ExportRenderError.swift) | `cannotCreateFile`/`emptyExport`/`archiveTooLarge`/`sizeLimitExceeded` (thông báo tiếng Việt) | 23 |
| [`Services/Export/ExportFileNaming.swift`](../../Sources/Services/Export/ExportFileNaming.swift) | `Documents/Exports/<tên>-yyyyMMdd-HHmmss.<ext>` + khử trùng `-2…`, `stagingURL` = `.part` | 54 |
| [`Services/Export/ExportStagingFile.swift`](../../Sources/Services/Export/ExportStagingFile.swift) | `FileHandle` ghi thẳng xuống `.part`, `commit()` mới rename (kế thừa `TxtExportFileWriter`) | 74 |
| [`Services/Export/ExportParagraphSplitter.swift`](../../Sources/Services/Export/ExportParagraphSplitter.swift) | cắt đoạn **giống hệt** `DownloadManager.formatChapter` cũ, dùng chung 4 renderer | 15 |
| [`Services/Export/ExportTextEscaper.swift`](../../Sources/Services/Export/ExportTextEscaper.swift) | escape XML/HTML + bỏ ký tự điều khiển (một `\u{0}` là EPUB/FB2 sai chuẩn) | 41 |
| [`Services/Export/TxtExportRenderer.swift`](../../Sources/Services/Export/TxtExportRenderer.swift) | TXT **giữ nguyên từng byte** bố cục bản xuất cũ | 44 |
| [`Services/Export/ZipStoreWriter.swift`](../../Sources/Services/Export/ZipStoreWriter.swift) | ZIP stored-only (method 0) tự viết: local header + central directory + EOCD, CRC-32 bảng tra | 154 |
| [`Services/Export/EpubExportRenderer.swift`](../../Sources/Services/Export/EpubExportRenderer.swift) | EPUB 3: `mimetype` đầu tiên, `container.xml`, OPF, `nav.xhtml`, một XHTML mỗi chương | 180 |
| [`Services/Export/Fb2ExportRenderer.swift`](../../Sources/Services/Export/Fb2ExportRenderer.swift) | FB2 2.0 chảy thẳng ra đĩa; bìa base64 `<binary>` ghi ở `finish()` | 94 |
| [`Services/Export/MobiExportRenderer.swift`](../../Sources/Services/Export/MobiExportRenderer.swift) | PalmDB/PalmDOC không nén; text staged rồi copy, vá `filepos` mục lục 10 chữ số | 207 |
| [`Services/Export/MobiHeaderBuilder.swift`](../../Sources/Services/Export/MobiHeaderBuilder.swift) | record 0: PalmDOC 16 B + MOBI 232 B + EXTH (100/103/503/201) | 138 |
| [`Services/Export/BigEndianBytes.swift`](../../Sources/Services/Export/BigEndianBytes.swift) | nối UInt16/UInt32 **big-endian** (ngược với ZIP little-endian) | 27 |
| [`Views/Common/ExportShareCoordinator.swift`](../../Sources/Views/Common/ExportShareCoordinator.swift) | chủ `UIActivityViewController`; giữ pending khi app ở background rồi bàn giao lúc `.active` | 100 |

| File sửa nội dung | Dòng | Thay đổi |
|---|---|---|
| [`Services/Download/DownloadManager.swift`](../../Sources/Services/Download/DownloadManager.swift) | 484 → **437** | `TaskType` thêm 3 case xuất; vòng lặp dùng `ExportContentProvider` + `ExportRenderer`; **xoá** `formatChapter`/`presentShareSheet` và `import UIKit` |
| [`Services/Download/DownloadManager+TaskStore.swift`](../../Sources/Services/Download/DownloadManager+TaskStore.swift) | 249 → **277** | thêm `updateExportStage` + `markExportCompleted` (lưu path, tổng kết, phát `exportReady`) |
| [`Services/Download/DownloadTaskOutcomeCalculator.swift`](../../Sources/Services/Download/DownloadTaskOutcomeCalculator.swift) | 39 → **62** | nhánh xuất theo `renderedChapterCount` + `exportSummary(...)` |
| [`Services/Download/Events/DownloadPresentationEvent.swift`](../../Sources/Services/Download/Events/DownloadPresentationEvent.swift) | 5 → **11** | case `exportReady(filePath:bookTitle:)` |
| [`Views/Download/TaskOptionsSheet.swift`](../../Sources/Views/Download/TaskOptionsSheet.swift) | 148 → **209** | picker "Định dạng bản xuất" + xem trước `đã tải X/Y chương`, enqueue `effectiveTaskType` |
| [`Views/Download/DownloadTrackerView.swift`](../../Sources/Views/Download/DownloadTrackerView.swift) | 208 → **217** | dòng giai đoạn + dòng tổng kết thiếu chương; `exportFromCached` mở sheet thay vì enqueue TXT |
| [`App/FreeBookApp.swift`](../../Sources/App/FreeBookApp.swift) | 103 → **105** | `AppLaunchRootView` nhận `.exportReady` → `ExportShareCoordinator.requestShare` |
| [`Views/MainTabView.swift`](../../Sources/Views/MainTabView.swift) | 70 → **76** | `scenePhase == .active` → `flushPendingShare()` |
| [`Views/Shelf/ShelfMain/ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) | 811 (không đổi) | nhãn `"Xuất ebook TXT"` → `"Xuất ebook"` (2 chỗ) — định dạng chọn ở sheet |
| [`Views/BookDetail/BookDetailView.swift`](../../Sources/Views/BookDetail/BookDetailView.swift) | 1175 (không đổi) | nhãn `"Xuất TXT"` → `"Xuất ebook"` |

* File bị xoá: `Services/Download/TxtExportFileWriter.swift` (97 dòng) — thay bằng `Services/Export/ExportStagingFile.swift` dùng chung cho cả 4 renderer.
* Tổng file Swift 303 → **323** (+21 mới, −1 xoá). Thư mục mới duy nhất: [`Sources/Services/Export/`](../../Sources/Services/Export/BookExportRequest.swift) (20 file).
* Quan hệ import mới: `Services/Download/DownloadManager` → `Services/Export/*` (một chiều — không renderer nào biết `DownloadManager`); `App/FreeBookApp` + `Views/MainTabView` → `Views/Common/ExportShareCoordinator`. `Sources/Services/Export/**` **không** `import UIKit`/`SwiftUI`, **không** gọi `ToastManager.shared`, **không** `import ZIPFoundation` (EPUB dùng `ZipStoreWriter` tự viết).
* `project.yml` không cần sửa: target khai `sources: - path: Sources` nên `xcodegen generate` tự nhặt 21 file mới.

## Nhập truyện PRC, DOCX, FB2 và tách chương quá dài (1.3.252)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Import/ChapterLengthLimiter.swift`](../../Sources/Services/Import/ChapterLengthLimiter.swift) | hậu xử lý **chung** mọi format: tách chương > 30 000 ký tự theo đoạn → câu → dòng → biên `Character` | 182 |
| [`Services/Import/DocxArchiveReader.swift`](../../Sources/Services/Import/DocxArchiveReader.swift) | giải nén DOCX qua `BackupZipArchive`, lấy `word/document.xml` + `docProps/core.xml`, `defer` tự dọn thư mục tạm | 49 |
| [`Services/Import/DocxBookParser.swift`](../../Sources/Services/Import/DocxBookParser.swift) | OOXML `XMLParser` → `[Block]` → Heading 1–3 → mốc sang trang → quy tắc TOC → 1 chương | 315 |
| [`Services/Import/Fb2BookParser.swift`](../../Sources/Services/Import/Fb2BookParser.swift) | FB2 `section`/`title`/`p` + `title-info` + bìa `<binary>`; từ chối file khai `<!ENTITY` | 297 |

| File sửa nội dung | Dòng | Thay đổi |
|---|---|---|
| [`Services/Import/MobiArchiveReader.swift`](../../Sources/Services/Import/MobiArchiveReader.swift) | 305 → **336** | kiểm chữ ký PalmDB @60…67: `BOOKMOBI`/`TEXtREAd` hợp lệ, biến thể khác `throw .malformed`; `Package` thêm `isPlainText` |
| [`Services/Import/MobiBookParser.swift`](../../Sources/Services/Import/MobiBookParser.swift) | 63 → **101** | `TEXtREAd` (text thuần) rẽ sang `TxtBookParser` sau khi chuẩn hoá `\r\n`/`\r`/`\u{0C}`, thay vì luôn đi `HtmlBookParser` |
| [`Services/Import/BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) | 79 → **107** | thêm `docx`/`fb2`, picker mở thêm `prc`/`docx`/`fb2`, phân biệt ZIP `epub+zip` vs `word/document.xml` |
| [`Services/Import/BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) | 199 → **214** | 2 nhánh mới + **phần đuôi dùng chung** gọi `ChapterLengthLimiter.apply` đúng một lần cho mọi format |
| [`Services/Import/ParserChapter.swift`](../../Sources/Services/Import/ParserChapter.swift) | 10 → **24** | 4 field provenance tạm thời `originalTitle`/`sourceOrdinal`/`partIndex`+`partCount`/`splitReason` |
| [`Services/Import/ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) | 25 → **27** | `chapters` thành `var` để limiter thay danh sách ở bước hậu xử lý |
| [`Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 288 → **307** | dòng báo cáo tách chương (cam) + `showsDecodeRow` thành `switch` liệt kê đủ case |

* Tổng file Swift 299 → **303** (+4), tất cả nằm trong [`Sources/Services/Import/`](../../Sources/Services/Import/BookImportService.swift) (14 → **18** file). Không thư mục mới, không file nào bị xoá hay đổi tên.
* Quan hệ import mới: `Services/Import/DocxArchiveReader` → `Services/Backup/BackupZipArchive` (điểm gọi ZIPFoundation duy nhất — file mới **không** `import ZIPFoundation`, giống `EpubArchiveReader`); `DocxBookParser`/`Fb2BookParser` → `Foundation` (`XMLParser`) và `TxtBookParser` cho nhánh quy tắc TOC, **không** đi qua SwiftSoup nên `XhtmlTextExtractor` vẫn là file duy nhất của phân hệ `import SwiftSoup`; `Views/Shelf/ShelfMain/BookImportConfirmationSheet` → `Services/Import/ChapterLengthLimiter` (chỉ đọc `report(for:)`, đúng chiều Views → Services).
* `ChapterLengthLimiter` **không** có caller nào ngoài `BookImportService.parse` — cố ý: limiter là một bước của pipeline nhập, không phải tiện ích dùng chung. Tầng View chỉ gọi `report(for:)` để hiển thị.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` nên `xcodegen generate` tự nhặt 4 file mới.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Nhập truyện từ EPUB, HTML, MOBI/AZW3 ngoài TXT (1.3.251)

| File mới | Vai trò | Dòng |
|---|---|---|
| [`Services/Import/ParserChapter.swift`](../../Sources/Services/Import/ParserChapter.swift) | DTO một chương đã bóc tách (dời từ `ShelfView.swift`) | 10 |
| [`Services/Import/ParsedBook.swift`](../../Sources/Services/Import/ParsedBook.swift) | DTO cả sách; thêm `author/desc/coverData/remoteCoverUrl/structureNote` đều mặc định `nil` | 25 |
| [`Services/Import/BookImportFormat.swift`](../../Sources/Services/Import/BookImportFormat.swift) | 4 format + `detect(fileName:data:)` (đuôi file trước, magic bytes sau) + `pickerContentTypes` | 79 |
| [`Services/Import/BookImportService.swift`](../../Sources/Services/Import/BookImportService.swift) | điểm vào duy nhất `parse(_:)`; nest `StructureMode`/`Request`/`Result`/`ImportError` | 199 |
| [`Services/Import/TxtBookParser.swift`](../../Sources/Services/Import/TxtBookParser.swift) | `parseTxtBook` cũ dời nguyên văn khỏi tầng View | 57 |
| [`Services/Import/XhtmlTextExtractor.swift`](../../Sources/Services/Import/XhtmlTextExtractor.swift) | SwiftSoup → plain text (sentinel `@@FBNL@@`), `headingSections`, `anchorSegments(html:anchorIds:)`, `declaredCharsetName(in:)` | 242 |
| [`Services/Import/HtmlBookParser.swift`](../../Sources/Services/Import/HtmlBookParser.swift) | `<mbp:pagebreak>` → heading → quy tắc TOC → 1 chương | 138 |
| [`Services/Import/EpubArchiveReader.swift`](../../Sources/Services/Import/EpubArchiveReader.swift) | giải nén qua `BackupZipArchive`, `container.xml` → OPF, `resolve(href:)` chặn zip-slip | 98 |
| [`Services/Import/EpubOpfParser.swift`](../../Sources/Services/Import/EpubOpfParser.swift) | `XMLParser` một lượt: metadata + manifest + spine + `coverId` | 146 |
| [`Services/Import/EpubNavParser.swift`](../../Sources/Services/Import/EpubNavParser.swift) | `toc.ncx` (flatten navPoint lồng) và `nav` EPUB3 | 136 |
| [`Services/Import/EpubBookParser.swift`](../../Sources/Services/Import/EpubBookParser.swift) | `tocIndex` → `spine` → `tocRules`; `defer` dọn thư mục tạm | 306 |
| [`Services/Import/PalmDocDecompressor.swift`](../../Sources/Services/Import/PalmDocDecompressor.swift) | LZ77 PalmDOC + `stripTrailingEntries(record:flags:)` | 97 |
| [`Services/Import/MobiArchiveReader.swift`](../../Sources/Services/Import/MobiArchiveReader.swift) | PalmDB/PalmDOC/MOBI/EXTH, mọi offset kiểm biên trước khi đọc | 305 |
| [`Services/Import/MobiBookParser.swift`](../../Sources/Services/Import/MobiBookParser.swift) | ghép record text → decode → `HtmlBookParser` | 63 |
| [`Views/Shelf/ShelfMain/Extensions/BookImportConfirmationSheet+Pickers.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/BookImportConfirmationSheet+Pickers.swift) | 3 picker: bảng mã, quy tắc TOC, **Cấu trúc** (mới) | 203 |

| File đổi tên | Thành | Dòng |
|---|---|---|
| `Views/Shelf/ShelfMain/Extensions/ShelfView+TXTImport.swift` (283) | [`ShelfView+BookImport.swift`](../../Sources/Views/Shelf/ShelfMain/Extensions/ShelfView+BookImport.swift) | 215 |
| `Views/Shelf/ShelfMain/TXTImportConfirmationSheet.swift` (374) | [`BookImportConfirmationSheet.swift`](../../Sources/Views/Shelf/ShelfMain/BookImportConfirmationSheet.swift) | 288 |

* Tổng file Swift 284 → **299** (+15). Thư mục mới duy nhất: [`Sources/Services/Import/`](../../Sources/Services/Import/BookImportService.swift) (14 file).
* File sửa nội dung: [`ShelfView.swift`](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift) 827 → **811** (−16: xoá 3 DTO `ParserChapter`/`ParsedBook`/`TXTReanalysisResult` đã dời xuống Services, nhãn menu thành `"Nhập truyện từ file"`, picker dùng `BookImportFormat.pickerContentTypes`, `PendingImport` thêm `format`), [`TextEncodingDecoder.swift`](../../Sources/Common/Utils/TextEncodingDecoder.swift) 44 → **102** (thêm `option(forCharsetName:)` + `decodeDeclared(_:charsetName:)`, không thêm case mới cho `TextEncodingOption`).
* Quan hệ import mới: `Views/Shelf/ShelfMain/**` → `Services/Import/**` (một chiều, đúng chiều Views → Services); `Services/Import/EpubArchiveReader` → `Services/Backup/BackupZipArchive` (điểm gọi ZIPFoundation duy nhất — file mới **không** `import ZIPFoundation`); `XhtmlTextExtractor` → `SwiftSoup` (**file duy nhất** của phân hệ `import SwiftSoup`; `EpubNavParser` đi qua `XhtmlTextExtractor.inlineText` vì selector SwiftSoup không nhận tên thuộc tính có dấu `:` như `epub:type`); `MobiArchiveReader`/`EpubOpfParser`/`EpubNavParser` → `Foundation` (`XMLParser`, `Data`) không thư viện ngoài.
* `Services/Import/**` không file nào `import SwiftUI` hay gọi `ToastManager.shared`: lỗi đi bằng `throw BookImportService.ImportError` và tầng View đổ `localizedDescription` vào Toast.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` nên `xcodegen generate` tự nhặt 15 file mới và 2 file đổi tên.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Sửa trình soạn script, khôi phục giữ thứ tự, sắp ext có cập nhật lên đầu (1.3.247)

| File mới | Tách khỏi | Dòng |
|---|---|---|
| `Views/Extensions/Editor/ExtensionScriptEditorView+Picker.swift` | `ExtensionScriptEditorView.swift` | 117 |
| `Views/Extensions/Editor/ExtensionScriptEditorView+Toolbars.swift` | `ExtensionScriptEditorView.swift` | 119 |

* Tổng file Swift 277 → **279** (+2). Không file nào bị xoá, đổi tên hay đổi thư mục.
* `ExtensionScriptEditorView.swift` 583 → **384** (−199): sheet chọn file sang `+Picker`, hai thanh dưới cùng + `dismissKeyboard()` sang `+Toolbars`. File rời khỏi danh sách vi phạm `LINE_LIMIT_EXCEEDED` (baseline 474).
* `+Toolbars.swift` là file duy nhất trong `Views/Extensions/Editor/**` khai `import UIKit` bên cạnh `SwiftUI`: `dismissKeyboard()` gọi `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), …)` nên không dựa vào việc SwiftUI re-export UIKit.
* File sửa nội dung, quan hệ import không đổi: `CodeEditorTextView.swift` 111 → **170** (quan sát 3 notification bàn phím, cộng phần bị che vào `contentInset.bottom`), `HighlightingCodeEditor.swift` 169 → **204** (`tokenColors` + `applyHighlight` tại chỗ trên `textStorage`), `RepositoryFilterPolicy.swift` 49 → **55** (khoá sắp xếp `hasUpdate` đứng đầu), `AddBookToShelfCommand.swift` (+`lastReadDate`), `BookTransactionCoordinator.swift`, `BackupLibraryWriter.swift`, `BackupCoordinator.swift` 209 → **259** (tách `performRestore` + `restoreEverythingFromDrive`), `BackupHubView.swift`, `GoogleDriveBackupListView.swift` 168 → **211**.
* Quan hệ mới: `GoogleDriveBackupListView` → `TTSWidgetStateReader` + `modelContext.container` (một chạm khôi phục cần container và cờ TTS đang phát); `BackupCoordinator.restoreEverythingFromDrive` → `GoogleDriveClient` → `LocalBackupStore` → `BackupRestoreWorker` trong **một** lượt giữ khoá `isBusy`.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` theo thư mục nên `xcodegen generate` tự nhặt 2 file mới.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Sao lưu/khôi phục, tăng tốc cập nhật ext, sửa thông tin truyện (1.3.246)

| File mới | Vai trò | Dòng |
|---|---|---|
| `Models/Books/EditBookInfoCommand.swift` | command bất biến cho sửa tên/tác giả/bìa | 20 |
| `Services/Backup/BackupScope.swift` | 6 nhóm dữ liệu chọn được, `books` bắt buộc | 54 |
| `Services/Backup/BackupPaths.swift` | nguồn duy nhất của tên entry trong archive + thư mục `backups/` | 94 |
| `Services/Backup/BackupManifest.swift` | `manifest.json`, `schemaVersion 1`, `Counts` | 80 |
| `Services/Backup/BackupPayload.swift` | DTO Codable của Book/Repository/Extension/Chapter | 196 |
| `Services/Backup/BackupProgress.swift` | 17 pha tiến độ + nhãn tiếng Việt | 79 |
| `Services/Backup/BackupZipArchive.swift` | **điểm gọi ZIPFoundation duy nhất** của phân hệ backup | 93 |
| `Services/Backup/BackupLibraryReader.swift` | đọc SwiftData → DTO `Sendable` (MainActor, chỉ đọc) | 139 |
| `Services/Backup/BackupDictionaryArchiver.swift` | gom file từ điển nguyên trạng, không parse | 93 |
| `Services/Backup/BackupSizeEstimator.swift` | dung lượng ước tính từng nhóm cho UI | 45 |
| `Services/Backup/BackupExportWorker.swift` | actor dựng thư mục tạm rồi zip | 232 |
| `Services/Backup/BackupRestoreWorker.swift` | actor điều phối restore (chỉ merge, không xoá) | 236 |
| `Services/Backup/BackupLibraryWriter.swift` | ghi SwiftData qua coordinator, chỉ chèn cái thiếu | 187 |
| `Services/Backup/BackupChapterRestorer.swift` | TOC + cache chương, quyết định giữ/bỏ offset | 189 |
| `Services/Backup/BackupExtensionInstaller.swift` | cài ext, tính lại `localPath` trên máy đích | 120 |
| `Services/Backup/BackupDictionaryRestorer.swift` | merge từ điển, tombstone đi kèm miễn phí | 127 |
| `Services/Backup/LocalBackupStore.swift` | liệt kê/xoá/đổi tên/nhập file trong `backups/` | 105 |
| `Services/Backup/BackupCoordinator.swift` | `ObservableObject` cầu nối UI ↔ worker | 209 |
| `Services/Backup/GoogleDrive/GoogleDriveConfiguration.swift` | clientId (override + Info.plist), scope `drive.file`, endpoint | 64 |
| `Services/Backup/GoogleDrive/GoogleDriveAuthService.swift` | PKCE S256 + `ASWebAuthenticationSession` | 201 |
| `Services/Backup/GoogleDrive/GoogleDriveTokenStore.swift` | refresh token: Keychain + fallback file có file protection | 105 |
| `Services/Backup/GoogleDrive/GoogleDriveFile.swift` | DTO file Drive + tên/kích thước hiển thị | 54 |
| `Services/Backup/GoogleDrive/GoogleDriveClient.swift` | tìm/tạo thư mục, list, download, delete | 137 |
| `Services/Backup/GoogleDrive/GoogleDriveUploader.swift` | resumable upload chunk 8 MiB, xử lý 308 | 171 |
| `Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift` | tải/parse `plugin.json` song song ngoài main | 168 |
| `Views/BookDetail/BookInfoEditView.swift` | form sửa tên/tác giả/bìa (URL hoặc `PhotosPicker`) | 214 |
| `Views/Settings/Backup/BackupHubView.swift` | màn gốc Sao lưu & Khôi phục | 187 |
| `Views/Settings/Backup/BackupScopeToggleList.swift` | toggle nhóm + dung lượng ước tính | 94 |
| `Views/Settings/Backup/LocalBackupListView.swift` | danh sách file backup trong app | 134 |
| `Views/Settings/Backup/GoogleDriveBackupListView.swift` | danh sách file trên Drive + đăng nhập | 168 |
| `Views/Settings/Backup/RestoreOptionsSheet.swift` | tóm tắt manifest + chọn nhóm khôi phục | 108 |
| `Views/Settings/Main/BackupSettingsSection.swift` | section "Sao Lưu & Khôi Phục" trong Cài đặt | 12 |
| `Views/Settings/Main/TTSSettingsSection.swift` | section "Nghe Truyện (TTS)" trích từ `SettingsView` | 24 |
* Tổng file Swift 244 → **277** (+33). Không file nào bị xoá, đổi tên hay đổi thư mục.
* File sửa nội dung: `SettingsView.swift` 453 → **439** (−14: mục TTS chuyển sang `TTSSettingsSection`, thêm `BackupSettingsSection`), `RepositoryManagerView.swift` 751 → **709** (−42: `syncExtensions` chỉ còn snapshot → builder → batch upsert), `BookDetailView.swift` 1213 → **1181** (−32: `ellipsisMenu` chuyển sang file `+Extensions`), `BookDetailView+Extensions.swift` 285 → **343** (+58: `ellipsisMenu` + item "Sửa thông tin truyện"), `ExtensionTransactionCoordinator.swift` → **174** (thêm `upsertExtensions` + helper `apply` dùng chung), `BookTransactionCoordinator.swift` → **239** (thêm `updateBookInfo`), `ImageCacheManager.swift` → **204** (thêm `saveCover` + `downscaled`).
* Quan hệ mới: `Views/Settings/Backup/**` → `BackupCoordinator` → `BackupExportWorker` / `BackupRestoreWorker` / `LocalBackupStore` / `GoogleDrive*`; `BackupLibraryWriter` → `BookTransactionCoordinator` + `ExtensionTransactionCoordinator`; `BackupChapterRestorer` → `ChapterStore` + `BookBinManager`; `BackupDictionaryRestorer` → `DictionaryTextFileStore` + `TranslationManager`; `RepositoryManagerView` → `ExtensionSyncCommandBuilder`.
* [BackupZipArchive.swift:1](../../Sources/Services/Backup/BackupZipArchive.swift#L1) là consumer ZIPFoundation thứ hai của repo (sau `ExtensionManager.swift`) và chỉ dùng `FileManager.zipItem/unzipItem`: `Archive.init` đổi chữ ký giữa các bản 0.9.x mà `Package.resolved` không được commit, nên mọi lời gọi thư viện gói trong đúng một file để sửa nhanh nếu CI resolve bản khác.
* `project.yml` **có sửa** lần này: thêm khoá Info.plist `GOOGLE_DRIVE_CLIENT_ID: "$(GOOGLE_DRIVE_CLIENT_ID)"` ([project.yml:54](../../project.yml#L54)). Danh sách file vẫn tự nhặt vì target khai `sources: - path: Sources` theo thư mục.
* Không build được để xác minh biên dịch: host là Windows, `xcodebuild` chỉ chạy trên macOS.

## Tìm kiếm truyện đích, copy VP/Name, widget trình duyệt kéo được (1.3.244)

| File mới | Vai trò | Dòng |
|---|---|---|
| `Views/Common/BookSearchBarView.swift` | thanh tìm kiếm dùng chung (trích từ `ShelfSearchView`) | 41 |
| `Views/Common/FloatingWidgetGeometry.swift` | hình học kẹp/snap cạnh dùng chung cho hai widget nổi | 39 |
| `Views/Common/VisibleBrowserPulseMonitor.swift` | nguồn duy nhất của cờ nháy widget trình duyệt (ngưỡng 10 s) | 72 |
| `Views/Common/BrowserFloatingWidgetUIWindow.swift` | `UIWindow` overlay + `hitTest` của widget trình duyệt | 26 |
| `Views/Common/BrowserFloatingWidgetContainerViewController.swift` | pan/tap + layout frame trực tiếp của widget trình duyệt | 197 |
| `Views/Common/BrowserFloatingWidgetWindowManager.swift` | điều phối hiện/ẩn window, re-parent scene | 121 |
| `Views/Dictionary/DictionaryTransferTarget.swift` | enum đích copy (`globalCustom` / `privateBook`) | 12 |
| `Views/Dictionary/DictionaryEntryTransferAction.swift` | thực thi copy cho cả 8 tổ hợp nguồn→đích | 47 |
| `Views/Dictionary/DictionaryEntryRow.swift` | một hàng từ điển + 3 icon `[Sửa] [Chuyển] [Xóa]` | 119 |
| `Views/Dictionary/DictionaryListView+Transfer.swift` | keo dán giữa row và action (context bookId, toast) | 41 |
| `Services/Extensions/Engine/VisibleBrowserSettings.swift` | khoá + getter `UserDefaults` cho cài đặt mở thu nhỏ | 13 |
| `Views/Settings/Main/BrowserSettingsSection.swift` | section "Trình Duyệt Hiển Thị" trong Cài đặt | 22 |

* Tổng file Swift 232 → **244**. Không file nào bị xoá, đổi tên hay đổi thư mục.
* File sửa nội dung: `DictionaryListView.swift` 767 → **748** (−19: hàng inline chuyển sang `DictionaryEntryRow`), `BookShareTargetSheet.swift` 77 → 100, `DictionaryHubView.swift` 116 (truyền `contextBookId`), `ShelfSearchView.swift` 242 → 218 (dùng `BookSearchBarView`), `VisibleBrowserTabManager.swift` 234 → 263, `VisibleBrowserTabItem.swift` 18 → 28 (thêm `createdAt`), `VisibleBrowserReopenView.swift` 136 → 51, `VisibleBrowserReopenViewModel.swift` 48 → 61, `FloatingWidgetViewModel.swift` 101 → 108, `FloatingWidgetContainerViewController.swift` 240 → 246, `FreeBookApp.swift` 103 (đổi chỗ, không đổi số dòng), `SettingsView.swift` **453 dòng không đổi**.
* `Views/Common/SizeReader.swift` (17 dòng) nay **không còn consumer** trong `Sources/`: consumer duy nhất là viên pill SwiftUI cũ trong `VisibleBrowserReopenView.swift`. File được giữ nguyên vì xoá nó nằm ngoài phạm vi yêu cầu.
* `project.yml` không cần sửa: target khai `sources: - path: Sources` theo thư mục nên `xcodegen generate` tự nhặt 12 file mới.

## Thêm relay quan sát view model của Reader (1.3.243)

| File mới | Vai trò | Dòng |
|---|---|---|
| `Views/Reader/Components/ReaderViewModelInvalidationRelay.swift` | forward `ReaderViewModel.objectWillChange` → `ReaderView` | 40 |

* Consumer duy nhất: `ReaderView.swift` (`@StateObject viewModelObserver`, gọi `observe(_:)` ở `ensureViewModel` và `.onDisappear`). Không file nào khác import/khởi tạo type này.
* Tổng file Swift 231 → **232**. Không file nào bị xoá, đổi tên hay đổi thư mục.

## Tách `ReaderEnergyDiagnostics` khỏi `ReaderTextView` (1.3.239)

| File mới | Tách khỏi | Dòng |
|---|---|---|
| `Views/Reader/Components/ReaderEnergyDiagnostics.swift` | `ReaderTextView.swift` | 258 |

* Tổng file Swift: **230 → 231**. `ReaderTextView.swift` 647 → **450** (−197): phần đo đếm năng lượng chuyển hẳn sang file mới, phần còn lại là bridge UIKit thuần.
* `ReaderEnergyDiagnostics.swift` — *Uses*: `AppLogger` (`isLoggingEnabled` + `log`), `ProcessInfo`, `UIApplication`. *Used by*: `ReaderView.swift` (`beginReaderSession` + 3 `flush`), `ReaderTextView.swift` (6 điểm `record*`), `ReaderView+LoadingView.swift` (2), `ReaderScrollCoordinator.swift` (2), `ParagraphTracker.swift` (2). Quan hệ *uses/used by* không đổi so với khi type còn nằm trong `ReaderTextView.swift` — chỉ dịch chuyển khai báo, `import UIKit` thay cho `import SwiftUI` của file gốc.
* File sửa nội dung, không đổi quan hệ import: `ReaderView.swift` 2250 → 2248 (xoá `@State translationRefreshToken` + call site), `ParagraphCardView.swift` 102 → 101 (xoá tham số cùng tên khỏi struct và khỏi `==`), `ParagraphTracker.swift` 90 → 94 (chỉ thêm comment), `ReaderView+Controls.swift` 161 (đổi thân `completeReaderPositionRestore`).
* `project.yml` không cần sửa: target khai `sources: - path: Sources` theo thư mục nên `xcodegen generate` tự nhặt file mới.

## 14 file mới sinh ra từ phép tách một-primary-type (1.3.236)

| File mới | Tách khỏi | Dòng |
|---|---|---|
| `Common/Utils/TextEncodingOption.swift` | `TextEncodingDecoder.swift` | 102 |
| `Common/BookListItemStyle.swift` (Views) | `BookListItemView.swift` | 10 |
| `Views/Common/VisibleBrowserPresentationReader.swift` | `VisibleBrowserReopenView.swift` | 39 |
| `Views/Common/VisibleBrowserReopenViewModel.swift` | `VisibleBrowserReopenView.swift` | 48 |
| `Views/Common/SizeReader.swift` | `VisibleBrowserReopenView.swift` | 17 |
| `Views/Extensions/Editor/CodeEditorTextView.swift` | `HighlightingCodeEditor.swift` | 111 |
| `Views/Shelf/ShelfMain/ShelfBookSearchMatcher.swift` | `ShelfSearchView.swift` | 22 |
| `Views/TTSWidget/FloatingWidgetUIWindow.swift` | `TTSFloatingWidgetWindowManager.swift` | 29 |
| `Views/TTSWidget/FloatingWidgetContainerViewController.swift` | `TTSFloatingWidgetWindowManager.swift` | 240 |
| `Services/Translation/BookTitleTranslationBackfill.swift` | `BookTitleTranslationMigrator.swift` | 40 |
| `Services/Translation/Manager/DictionaryInvalidationScope.swift` | `TranslationManager.swift` | 7 |
| `Services/Extensions/Engine/VisibleWebViewController.swift` | `VisibleWebViewLoader.swift` | 122 |
| `Services/Extensions/Engine/VisibleBrowserTabItem.swift` | `VisibleBrowserTabManager.swift` | 18 |
| `Services/Extensions/Engine/TabbedVisibleBrowserViewController.swift` | `VisibleBrowserTabManager.swift` | 201 |

* Quan hệ *uses/used by* không đổi: mọi tham chiếu vẫn nằm trong cùng module nên chỉ là dịch chuyển khai báo. Hai type đổi access level (`SizeReader`, `BookTitleTranslationBackfill`) vì `private` ở file cũ là phạm vi file.
* Không file nào trong `Sources/Services/**` mới thêm `import SwiftUI`: `VisibleWebViewController.swift` và `TabbedVisibleBrowserViewController.swift` chỉ dùng `Foundation`/`UIKit`/`WebKit`, nên miễn trừ `SERVICE_SWIFTUI_IMPORT` cho `*WebViewLoader.swift` vẫn không bị nới rộng.
* File gốc sau khi tách: `TextEncodingDecoder.swift` 145 → 43, `BookListItemView.swift` 182 → 171, `VisibleBrowserReopenView.swift` 234 → 128, `HighlightingCodeEditor.swift` 278 → 166, `ShelfSearchView.swift` 263 → 240, `TTSFloatingWidgetWindowManager.swift` 375 → 112, `BookTitleTranslationMigrator.swift` 79 → 38, `TranslationManager.swift` 601 → 593, `VisibleBrowserTabManager.swift` 448 → 234, `VisibleWebViewLoader.swift` 404 → 285.

## File bị xoá/đổi tên khi dọn code chết (1.3.235)

* **Xoá**: `Sources/Services/TTS/Helpers/TTSHighlightCalculator.swift`, `Sources/Services/TTS/Helpers/TTSParagraphSplitter.swift`, `Sources/Services/TTS/Helpers/TTSVoiceResolver.swift` (cả ba đều 0 *used by*; thư mục `Helpers/` không còn tồn tại), `Sources/Views/Reader/ReaderViewModelObserver.swift` (0 *used by*).
* **Đổi tên**: `Sources/Views/Reader/ReaderParagraphBuilder.swift` → `Sources/Views/Reader/ReaderParagraphBuildResult.swift` (7 dòng). *Used by*: `Views/Reader/Extensions/ReaderViewModel+Translation.swift`. Enum `ReaderParagraphBuilder` bị xoá; đường dựng `[ParagraphItem]` của production nay là **một bản duy nhất** trong `ReaderViewModel+Translation.swift`.
* **Xoá `Tests/` (20 file) và target `FreeBookTests` trong `project.yml`** — không còn file nào ngoài `Sources/` được biên dịch, nên đồ thị import/dependency chỉ còn một target.
* Các file mất bớt thành viên nhưng giữ nguyên quan hệ *uses/used by*: `TTSManager.swift`, `TTSChapterPrefetcher.swift`, `TTSChapterTextWorker.swift`, `TTSNowPlayingController.swift`, `TTSParagraphBuilder.swift`, `ModelStore.swift`, `NghiTTSClient.swift`, `PiperTTSService.swift`, `ExtensionManager.swift`, `TranslationManager.swift`, `TranslateUtils.swift`, `BookTransactionCoordinator.swift`, `ExtensionTransactionCoordinator.swift`, `JunkFilterManager.swift`, `ReaderChapterListStore.swift`, `ImageCacheManager.swift`, `DisplayTextFormatter.swift`, `DoubleArrayTrie.swift`, `ToastManager.swift`, `BookDictionaryView.swift`.

## Next-chapter prefix audio files (1.3.234)

* `Sources/Services/TTS/TTSNextChapterPrefixCache.swift` (380 dòng, 1 primary type `TTSNextChapterPrefixCache`)
  - *Uses*: `TTSPreparedNextChapterKey`, `TTSParagraph`, `TTSBoundaryKind`, `TTSReplacementManager`, `TTSSynthesisIdentity`, `TTSAudioSynthesisWorker`, `RemoteTTSSynthesisCoordinator.Priority`, `PiperTTSService`, `SynthesisPriority`, `GoogleTTSService`, `ExtTTSService`, `WAVEncoder`, `AppLogger`, `TTSManager.RefillFailureState` + `TTSManager.evaluateRefillError` (tái sử dụng phân loại lỗi).
  - *Used by*: `TTSManager+NextChapterPrefix.swift` (chỉ một consumer duy nhất).
* `Sources/Services/TTS/Extensions/TTSManager+NextChapterPrefix.swift` (130 dòng, extension — không khai primary type)
  - *Uses*: `TTSManager` (nội bộ: `nextChapterPrefetcher`, `preloadedData`, `preloadedDurations`, `paragraphs`, `nghiTTSService`, `googleService`, `extService`, `audioSynthesisWorker`, `makeNextChapterKey`, `selectNghiOptionalRefillCandidate`), `TTSNextChapterPrefixCache`, `NghiUtteranceSegmenter`, `NghiSynthesisPolicy`, `ProcessedChapterDTO`, `WAVEncoder`, `AppLogger`.
  - *Used by*: `TTSManager.swift` (4 call site: `pause`, `applyNextChapter`, `updatePrefetchWindow`, `updateNghiPrefetchWindow`), `TTSManager+PrefetchCache.swift` (`clearAllTTSCaches`).
* `TTSManager.swift` mở rộng khả năng truy cập cho hai thành viên đã có (`nghiTTSService`, `makeNextChapterKey`) từ `private` sang `internal` để extension ở file khác dùng được; không thêm type mới. `NghiSynthesisPolicy.swift` thêm hằng `maxTotalAudioPayloads` (vẫn là single source cho mọi hằng số năng lượng của Nghi).

## Extension type constants (1.3.226)

* File mới `Sources/Models/Extensions/ExtensionType.swift` khai báo namespace public dùng chung cho các giá trị type chuẩn mà không thay `Extension.type: String` thành enum.
* `UpsertExtensionCommand` và `ExtensionManager` phụ thuộc `ExtensionType.novel` cho default/fallback; `RepositoryFilterPolicy`, `SearchView`, `DiscoveryView`, `TTSSettingsView`, `RepositoryManagerView`, `FilterSheet` và `RepositoryManagerView+Actions` phụ thuộc cùng namespace cho policy và presentation.

## Cấu Trúc Sơ Đồ File Hợp Nhất (Refactor v4.1/v5.0)

Sơ đồ liên kết file của toàn bộ dự án FreeBook sau refactor:
- **App**: `FreeBookApp.swift` -> Đăng ký `TTSPresentationEventCenter`, `DownloadPresentationEventCenter`.
- **Models**:
  - `Models/Books/`: `AddBookToShelfCommand.swift`, `BookTransactionError.swift`.
  - `Models/Extensions/`: `ExtensionConfigCommand.swift`, `ExtensionExecutionSnapshot.swift`, `ExtensionTransactionError.swift`, `ExtensionType.swift`, `UpdateExtensionFolderCommand.swift`, `UpsertExtensionCommand.swift`.
  - `Models/Reader/`: `ChapterRowItem.swift`, `ParagraphFrame.swift`, `ReaderChapterRowState.swift`, `ReaderScrollReason.swift`, `ReaderScrollTarget.swift`, `SearchChapterDTO.swift`.
  - `Models/Translation/`: `SentenceRange.swift`, `TOCImportPreview.swift`, `TOCRule.swift`, `TOCRuleImportError.swift`, `TranslatedTextResult.swift`, `TranslationSpan.swift`, `TranslationWordToken.swift`.
- **Services**:
  - `Services/Books/`: `BookTransactionCoordinator.swift`.
  - `Services/Extensions/`: `ExtensionTransactionCoordinator.swift`, `Policies/RepositoryFilterPolicy.swift`, `Workers/BookDetailLoader.swift`, `Engine/JSExecutor.swift`, `Engine/JSExecutor+Async.swift`.
  - `Services/ChapterText/`: `PrefetchManager.swift`, `ReaderChapterListStore.swift`, `Coordinators/ChapterListSearchCoordinator.swift`, `Workers/BackgroundPagingWorker.swift`, `BackgroundSearchWorker.swift`, `ReaderChapterListPageFetcher.swift`, `ChapterStore/ChapterTOCDiff.swift` (hàm thuần, không phụ thuộc sqlite — `ChapterStoreDatabase.swift` gọi vào để chọn `.unchanged`/`.appendOnly`/`.full`).
  - `Services/ReadingProgress/`: `ReaderProgressScheduler.swift`.
  - `Services/TTS/`: `TTSManager.swift`, `TTSAudioEngineController.swift`, `TTSAudioSessionController.swift`, `Events/TTSPresentationEventCenter.swift`, `Events/TTSPresentationEvent.swift`, `Extensions/TTSManager+*.swift`. `DisplayTextFormatter.swift` nằm ở `Common/Extensions/DisplayTextFormatter.swift`, không phải trong `Services/TTS/`.
  - `Services/Download/`: `DownloadManager.swift`, `DownloadManager+TaskStore.swift` (CRUD/tiến độ của `DownloadTaskModel`, giữ một `ModelContext` dùng lại), `DownloadTaskOutcomeCalculator.swift` (chính sách `completed`/`failed` + dòng tổng kết bản xuất thiếu chương), `Events/DownloadPresentationEventCenter.swift`, `Events/DownloadPresentationEvent.swift`.
  - `Services/Export/`: `BookExportRequest.swift` (DTO bất biến), `BookExportFormat.swift`, `ExportRenderer.swift` (protocol `append`/`finish`/`discard`), `ExportRendererFactory.swift`, `ExportContentProvider.swift` (lấy chương — dùng chung cho cả tác vụ tải), `ExportChapterPayload.swift`, `ExportArtifact.swift`, `ExportStage.swift`, `ExportRenderError.swift`, `ExportFileNaming.swift`, `ExportStagingFile.swift` (`.part` rồi rename), `ExportParagraphSplitter.swift`, `ExportTextEscaper.swift`, `TxtExportRenderer.swift`, `EpubExportRenderer.swift` + `ZipStoreWriter.swift`, `Fb2ExportRenderer.swift`, `MobiExportRenderer.swift` + `MobiHeaderBuilder.swift` + `BigEndianBytes.swift`. Phân hệ chỉ sinh file trong `Documents/Exports/`, không mở share sheet (`Sources/Views/Common/ExportShareCoordinator.swift` lo việc đó).
  - `Services/Import/`: `BookImportService.swift` (điểm vào duy nhất), `BookImportFormat.swift`, `ParsedBook.swift`, `ParserChapter.swift`, `ChapterLengthLimiter.swift` (hậu xử lý chung, chạy trong phần đuôi của `BookImportService.parse`), `TxtBookParser.swift`, `XhtmlTextExtractor.swift`, `HtmlBookParser.swift`, `EpubArchiveReader.swift`, `EpubOpfParser.swift`, `EpubNavParser.swift`, `EpubBookParser.swift`, `MobiArchiveReader.swift`, `PalmDocDecompressor.swift`, `MobiBookParser.swift`, `DocxArchiveReader.swift`, `DocxBookParser.swift`, `Fb2BookParser.swift`, `PdfDocumentReader.swift`, `PdfBookParser.swift`. Phân hệ chỉ sinh `ParsedBook`, không sở hữu lưu trữ.
  - `Services/Translation/`: `Utils/TranslateUtils.swift`, `Extensions/TranslateUtils+Tokenization.swift`, `Engine/VietPhraseTokenizer.swift`, `Utils/TOCRuleSaveCoordinator.swift`.
- **Views**:
  - `Views/BookDetail/`: `BookDetailView.swift`, `Extensions/BookDetailView+Extensions.swift`, `BookDetailView+TOCPreparation.swift`.
  - `Views/Reader/`: `ReaderView.swift`, `ReaderViewModel.swift`, `ReaderChapterListView.swift`, `Coordinators/ReaderScrollCoordinator.swift`, `ReaderSelectionCoordinator.swift`, `Extensions/ReaderView+Controls.swift`, `ReaderView+LoadingView.swift`, `ReaderView+Suggestions.swift`, `ReaderViewModel+Translation.swift`.
  - `Views/Extensions/`: `Manager/RepositoryManagerView.swift`, `Extensions/RepositoryManagerView+Actions.swift`, `RepositoryManagerView+RepoOps.swift`.
  - `Views/Shelf/`: `ShelfMain/ShelfView.swift`, `ShelfMain/Extensions/ShelfView+BookImport.swift` (nhập truyện từ file TXT/HTML/EPUB/MOBI–AZW3/PRC/DOCX/FB2/PDF; đọc/ghi `@State` của `ShelfView` nên chúng phải `internal`, không `private`), `ShelfMain/BookImportConfirmationSheet.swift` + `ShelfMain/Extensions/BookImportConfirmationSheet+Pickers.swift`. Logic bóc tách nằm ở `Services/Import/`.
  - `Views/Search/`: `SearchView.swift`.
  - `Views/Discovery/`: `DiscoveryView.swift`.
  - `Views/Common/`: `VisibleBrowserReopenView.swift`.
<!-- GENERATED END -->
