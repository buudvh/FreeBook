---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 3
---

# Đồ thị Kiểu dữ liệu (Type Graph)

Tài liệu này liệt kê chi tiết định nghĩa và mối quan hệ giữa các kiểu dữ liệu (Class, Struct, Enum, Protocol, Actor, Extension) trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Reader paragraph and selection types (1.3.14)

* `TranslationSpan` stores original and translated UTF-16 offsets/lengths; `TranslatedTextResult` returns translated text with those spans.
* `ParagraphItem` owns its original text, translated text, title flag, and backward-compatible translation spans.
* `ReaderParagraphBuilder` returns `ReaderParagraphBuildResult` with one paragraph item per original line; `ReaderSelectionMapper` resolves a translated `NSRange` back to the original paragraph.
* `ReaderTextView` emits only a UTF-16 `NSRange`; `ParagraphCardView` attaches the paragraph id before forwarding the selection.

## Reader type updates (1.3.13, supersedes 1.3.11)

* `ReaderNavigationSource` supports history, footer buttons, chapter-list selection, TTS sync, and reload. Horizontal swipe is no longer a navigation source.
* `ReaderNavigationDirection`, `ReaderNavigationCommit`, and `ReaderChapterLoadFailure` retain the generation-checked single-chapter navigation contract.
* `ReaderChapterListStore` owns stable `ReaderChapterRowState` objects for the Reader lifetime. `markCached(index:)` mutates one row without rebuilding the chapter list.
* `ParagraphCardView` and `ReaderTextView` no longer expose selection-activity callbacks; text selection itself still flows through `onSelectionChange`.
* `ExtensionManagerError.sourceResponse(message:)` preserves the exact message returned by JavaScript `Response.error(message)`.

## Đánh giá mức độ tin cậy (Confidence Level)

*   **Mức độ tin cậy**: **High**
*   **Lý do**: Được phân tích trực tiếp từ cấu trúc định nghĩa type và phân tích cú pháp tĩnh của các file Swift.

---

## Thống kê số lượng kiểu dữ liệu
*   **Class**: 43
*   **Struct**: 99
*   **Enum**: 18
*   **Protocol**: 2
*   **Actor**: 3
*   **Extension**: 15

---

## Chi tiết các Kiểu dữ liệu

### 1. AddRepositoryView (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Manager/RepositoryManagerView.swift:565](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift#L565)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `ExtensionConfigView`, `ExtensionManager`, `ExtensionRegistryItem`, `ExtensionStoreView`, `Repository`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 1. AddWordSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:496](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L496)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 2. AllCommentsView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/AllCommentsView.swift:2](../../Sources/Views/BookDetail/AllCommentsView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `CommentSectionView`

---

### 3. AppDiagnostics (CLASS)

*   **Định nghĩa tại**: [Services/Logging/AppLogger.swift:83](../../Sources/Services/Logging/AppLogger.swift#L83)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `CategoryResult`, `ChapterResult`, `ExtensionManager`, `ExtensionRegistryItem`, `NovelDetailResult`, `RegistryMetadata`, `RegistryResponse`, `SearchNovelResult`

---

### 4. AppLaunchRootView (STRUCT)

*   **Định nghĩa tại**: [App/FreeBookApp.swift:19](../../Sources/App/FreeBookApp.swift#L19)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLoadingView`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `MainTabView`, `Repository`, `TTSFloatingWidgetView`, `TTSManager`, `ToastManager`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 5. AppLoadingView (STRUCT)

*   **Định nghĩa tại**: [Views/AppLoadingView.swift:2](../../Sources/Views/AppLoadingView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `FreeBookApp`

---

### 6. AppLogger (CLASS)

*   **Định nghĩa tại**: [Services/Logging/AppLogger.swift:2](../../Sources/Services/Logging/AppLogger.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `AudioConfig`, `BackgroundTaskSession`, `CachedChapter`, `CachedSession`, `CategoryNovelsListView`, `CategoryResult`, `ChapterCache`, `ChapterLimitOption`, `ChapterLoadState`, `ChapterResult`, `DictionaryCard`, `DictionaryMatchInfo`, `DictionaryType`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `EspeakPhonemizer`, `ExtTTSService`, `ExtensionManager`, `ExtensionRegistryItem`, `ExtensionSelectorView`, `ImageCacheManager`, `ImportMode`, `JSExecutor`, `LoadedChapter`, `ModelsResponse`, `NghiTTSClient`, `NovelDetailResult`, `ONNXPiperEngine`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `PiperConfig`, `PrefetchManager`, `PrefetchResult`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ReadingProgress`, `ReadingProgressRepository`, `RegistryMetadata`, `RegistryResponse`, `ScrollTarget`, `SearchNovelResult`, `SettingsView`, `ShelfView`, `TTSManager`, `TTSReplacementManager`, `TTSReplacementRule`, `TaskStatus`, `TaskType`, `TextChunk`, `TextPreprocessor`, `UnitPatternSpec`, `WebViewLoader`, `WordToken`

---

### 7. AudioConfig (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:6](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L6)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Decodable`
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 8. AutoSizingTextView (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:319](../../Sources/Views/Reader/ReaderTextView.swift#L319)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ReaderUITextView`
*   **Sử dụng (Uses)**: `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 9. BackgroundTaskSession (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/BackgroundTaskSession.swift:5](../../Sources/Services/TTS/BackgroundTaskSession.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `ModelsResponse`, `NghiTTSClient`, `PrefetchResult`

---

### 10. Book (CLASS)

*   **Định nghĩa tại**: [Models/Database/Book.swift:7](../../Sources/Models/Database/Book.swift#L7)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Chapter`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `BookDetailView`, `Chapter`, `ChapterLimitOption`, `ChapterRowInfo`, `DictionaryMatchInfo`, `DownloadManager`, `DownloadTask`, `DownloadTrackerView`, `FreeBookApp`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ReadingProgressRepository`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `ShelfView`, `SourceSearchState`, `TTSManager`, `TaskOptionsSheet`, `TaskStatus`, `TaskType`
*   **Các Extension của kiểu này**:
    *   Tại [Models/Database/Book.swift:64](../../Sources/Models/Database/Book.swift#L64) : Identifiable

---

### 11. BookCoverView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/BookCoverView.swift:2](../../Sources/Views/Common/BookCoverView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `ImageCacheManager`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `CategoryNovelsListView`, `DownloadTrackerView`, `ParsedBook`, `ParserChapter`, `ShelfView`, `SuggestRowView`, `TaskOptionsSheet`

---

### 12. BookDetailView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/BookDetailView.swift:3](../../Sources/Views/BookDetail/BookDetailView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookCoverView`, `BookDictionaryView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Chapter`, `ChapterResult`, `CommentSectionView`, `Extension`, `ExtensionIconView`, `ExtensionManager`, `JSExecutor`, `ReaderView`, `SearchView`, `SkeletonView`, `SuggestRowView`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `CategoryNovelsListView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `ShelfView`, `SourceSearchState`, `SuggestRowView`

---

### 13. BookDictionaryView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/BookDictionaryView.swift:7](../../Sources/Views/Dictionary/BookDictionaryView.swift#L7)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictionaryHubView`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 14. BypassWebView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/BypassWebView.swift:4](../../Sources/Views/Common/BypassWebView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `ShelfView`

---

### 15. CacheSummary (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ModelStore.swift:2](../../Sources/Services/TTS/NghiTTS/ModelStore.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 16. CachedChapter (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:23](../../Sources/Views/Reader/ChapterCache.swift#L23)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 17. CachedSession (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:12](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L12)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 18. CallInfo (STRUCT)

*   **Định nghĩa tại**: [Services/Logging/AppLogger.swift:89](../../Sources/Services/Logging/AppLogger.swift#L89)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `CategoryResult`, `ChapterResult`, `ExtensionManager`, `ExtensionRegistryItem`, `NovelDetailResult`, `RegistryMetadata`, `RegistryResponse`, `SearchNovelResult`

---

### 19. CategoryNovelsListView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/CategoryNovelsListView.swift:2](../../Sources/Views/Common/CategoryNovelsListView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookCoverView`, `BookDetailView`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`

---

### 20. CategoryResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:821](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L821)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `BookDetailView`, `CategoryNovelsListView`, `CommentSectionView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `SuggestRowView`

---

### 21. Chapter (CLASS)

*   **Định nghĩa tại**: [Models/Database/Chapter.swift:5](../../Sources/Models/Database/Chapter.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Book`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `Book`, `BookDetailView`, `ChapterLimitOption`, `ChapterRowInfo`, `DictionaryMatchInfo`, `DownloadManager`, `DownloadTask`, `FreeBookApp`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `ShelfView`, `SourceSearchState`, `TaskStatus`, `TaskType`

---

### 22. ChapterCache (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:41](../../Sources/Views/Reader/ChapterCache.swift#L41)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`

---

### 23. ChapterLimitOption (ENUM)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:4](../../Sources/Services/Download/DownloadManager.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Int`, `CaseIterable`, `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `TaskOptionsSheet`

---

### 24. ChapterLoadState (ENUM)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:12](../../Sources/Views/Reader/ChapterCache.swift#L12)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 25. ChapterResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:53](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L53)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `ChapterRowInfo`, `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ScrollTarget`

---

### 26. ChapterRowInfo (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderChapterListView.swift:3](../../Sources/Views/Reader/ReaderChapterListView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `Book`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ReaderTheme`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 27. CollapsedCircleView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/CollapsedCircleView.swift:2](../../Sources/Views/Reader/CollapsedCircleView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 28. CommentSectionView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/CommentSectionView.swift:2](../../Sources/Views/BookDetail/CommentSectionView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AllCommentsView`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`

---

### 29. ConfigItem (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Config/ExtensionConfigView.swift:17](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift#L17)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `Extension`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 30. Coordinator (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:194](../../Sources/Views/Reader/ReaderTextView.swift#L194)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `UITextViewDelegate`, `UIGestureRecognizerDelegate`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`, `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 31. DictEntry (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/DictionaryCache.swift:220](../../Sources/Services/Translation/Utils/DictionaryCache.swift#L220)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryListView`, `ShareSheet`

---

### 32. DictEntrySheet (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:508](../../Sources/Views/Dictionary/DictionaryListView.swift#L508)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 33. DictSheetMode (ENUM)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:496](../../Sources/Views/Dictionary/DictionaryListView.swift#L496)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 34. DictType (ENUM)

*   **Định nghĩa tại**: [Services/Translation/Utils/DictionaryCache.swift:201](../../Sources/Services/Translation/Utils/DictionaryCache.swift#L201)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`
*   **Sử dụng (Uses)**: `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryHubView`, `DictionaryListView`, `DictionaryNavRow`, `ShareSheet`

---

### 35. DictionaryCache (CLASS)

*   **Định nghĩa tại**: [Services/Translation/Utils/DictionaryCache.swift:8](../../Sources/Services/Translation/Utils/DictionaryCache.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryCard`, `DictionaryListView`, `SettingsView`, `ShareSheet`, `TranslationManager`

---

### 36. DictionaryCard (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/Main/SettingsView.swift:376](../../Sources/Views/Settings/Main/SettingsView.swift#L376)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `DictionaryCache`, `DocumentPickerPresenter`, `NghiTTSSettingsView`, `SearchEnginesConfigView`, `TTSDictionaryEditView`, `TTSModelManagerView`, `TTSReplacementManagerView`, `TTSSettingsView`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 37. DictionaryHubView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryHubView.swift:2](../../Sources/Views/Dictionary/DictionaryHubView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictType`, `DictionaryListView`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `BookDictionaryView`, `SearchBar`

---

### 38. DictionaryListView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:3](../../Sources/Views/Dictionary/DictionaryListView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictionaryHubView`, `DictionaryNavRow`

---

### 39. DictionaryMatchInfo (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:1780](../../Sources/Views/Reader/ReaderView.swift#L1780)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: `ManageDefinitionsView`

---

### 40. DictionaryNavRow (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryHubView.swift:91](../../Sources/Views/Dictionary/DictionaryHubView.swift#L91)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictType`, `DictionaryListView`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 41. DictionaryType (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:873](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L873)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 42. DiscoveryCategoryTabView (STRUCT)

*   **Định nghĩa tại**: [Views/Discovery/DiscoveryView.swift:409](../../Sources/Views/Discovery/DiscoveryView.swift#L409)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookDetailView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Extension`, `ExtensionConfigView`, `ExtensionIconView`, `ExtensionManager`, `SearchNovelResult`, `SearchView`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 43. DiscoveryView (STRUCT)

*   **Định nghĩa tại**: [Views/Discovery/DiscoveryView.swift:3](../../Sources/Views/Discovery/DiscoveryView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookDetailView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Extension`, `ExtensionConfigView`, `ExtensionIconView`, `ExtensionManager`, `SearchNovelResult`, `SearchView`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 44. DocumentPicker (STRUCT)

*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:136](../../Sources/Views/Common/DocumentPicker.swift#L136)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewControllerRepresentable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AddWordSheet`, `EditWordSheet`, `EditingEntry`, `ParsedBook`, `ParserChapter`, `ShelfView`, `TTSDictionaryEditView`

---

### 45. DocumentPickerHostViewController (CLASS)

*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:15](../../Sources/Views/Common/DocumentPicker.swift#L15)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewController`, `UIDocumentPickerDelegate`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 46. DocumentPickerPresenter (STRUCT)

*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:79](../../Sources/Views/Common/DocumentPicker.swift#L79)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewControllerRepresentable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryCard`, `DictionaryListView`, `SettingsView`, `ShareSheet`, `TTSModelManagerView`, `TTSReplacementManagerView`

---

### 47. DoubleArrayTrie (CLASS)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrie.swift:25](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift#L25)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `TrieDictionary`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryListView`, `ShareSheet`, `TranslationManager`

---

### 48. DoubleArrayTrieBuilder (CLASS)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrieBuilder.swift:2](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryListView`, `ShareSheet`, `TranslationManager`

---

### 49. DownloadManager (CLASS)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:61](../../Sources/Services/Download/DownloadManager.swift#L61)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DownloadTrackerView`, `MainTabView`, `ParsedBook`, `ParserChapter`, `ShelfView`, `TaskOptionsSheet`

---

### 50. DownloadTask (STRUCT)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:41](../../Sources/Services/Download/DownloadManager.swift#L41)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DownloadTrackerView`

---

### 51. DownloadTaskModel (CLASS)

*   **Định nghĩa tại**: [Models/Database/DownloadTaskModel.swift:5](../../Sources/Models/Database/DownloadTaskModel.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `ChapterLimitOption`, `DownloadManager`, `DownloadTask`, `FreeBookApp`, `TaskStatus`, `TaskType`

---

### 52. DownloadTrackerView (STRUCT)

*   **Định nghĩa tại**: [Views/Download/DownloadTrackerView.swift:3](../../Sources/Views/Download/DownloadTrackerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookCoverView`, `DownloadManager`, `DownloadTask`, `TaskOptionsSheet`, `TaskStatus`, `TaskType`
*   **Được sử dụng bởi (Used by)**: `ParsedBook`, `ParserChapter`, `ShelfView`

---

### 53. EdgeDirection (ENUM)

*   **Định nghĩa tại**: [Views/TTSWidget/WidgetState.swift:8](../../Sources/Views/TTSWidget/WidgetState.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `FloatingWidgetViewModel`

---

### 54. EditWordSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:558](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L558)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 55. EditingEntry (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:484](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L484)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 56. EnglishTransliterator (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/EnglishTransliterator.swift:2](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `PreprocessorRegex`, `RegexRule`
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 57. EspeakPhonemizer (CLASS)

*   **Định nghĩa tại**: [Services/TTS/EspeakPhonemizer.swift:6](../../Sources/Services/TTS/EspeakPhonemizer.swift#L6)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `TTSError`
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `ONNXPiperEngine`, `PiperConfig`, `TextChunk`

---

### 58. ExpandedControlPanel (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ExpandedControlPanel.swift:2](../../Sources/Views/Reader/ExpandedControlPanel.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 59. ExtTTSService (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Ext/ExtTTSService.swift:3](../../Sources/Services/TTS/Ext/ExtTTSService.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `ExtensionManager`
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 60. Extension (CLASS)

*   **Định nghĩa tại**: [Models/Database/Extension.swift:5](../../Sources/Models/Database/Extension.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Repository`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `AppLaunchRootView`, `BookDetailView`, `BypassWebView`, `ChapterLimitOption`, `ChapterRowInfo`, `ConfigItem`, `Coordinator`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `ExtensionConfigView`, `ExtensionSelectorView`, `FreeBookApp`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `Repository`, `RepositoryManagerView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `SourceSearchState`, `SwiftUIWebView`, `TTSSettingsView`, `TaskStatus`, `TaskType`, `WebViewStore`

---

### 61. ExtensionConfigView (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Config/ExtensionConfigView.swift:3](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `RepositoryManagerView`, `TTSSettingsView`

---

### 62. ExtensionIconView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/ExtensionIconView.swift:2](../../Sources/Views/Common/ExtensionIconView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`

---

### 63. ExtensionManager (CLASS)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:61](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L61)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `AllCommentsView`, `BookDetailView`, `CategoryNovelsListView`, `ChapterLimitOption`, `ChapterRowInfo`, `CommentSectionView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `ExtTTSService`, `ExtensionSelectorView`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `RepositoryManagerView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `SourceSearchState`, `SuggestRowView`, `TTSSettingsView`, `TaskStatus`, `TaskType`

---

### 64. ExtensionRegistryItem (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:16](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L16)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `RepositoryManagerView`

---

### 65. ExtensionSelectorView (STRUCT)

*   **Định nghĩa tại**: [Views/Discovery/DiscoveryView.swift:620](../../Sources/Views/Discovery/DiscoveryView.swift#L620)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookDetailView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Extension`, `ExtensionConfigView`, `ExtensionIconView`, `ExtensionManager`, `SearchNovelResult`, `SearchView`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 66. FloatingWidgetViewModel (CLASS)

*   **Định nghĩa tại**: [Views/TTSWidget/FloatingWidgetViewModel.swift:5](../../Sources/Views/TTSWidget/FloatingWidgetViewModel.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `EdgeDirection`, `WidgetMode`
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 67. FreeBookApp (STRUCT)

*   **Định nghĩa tại**: [App/FreeBookApp.swift:5](../../Sources/App/FreeBookApp.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `App`
*   **Sử dụng (Uses)**: `AppLoadingView`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `MainTabView`, `Repository`, `TTSFloatingWidgetView`, `TTSManager`, `ToastManager`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 68. ImageCacheManager (CLASS)

*   **Định nghĩa tại**: [Common/Services/ImageCacheManager.swift:3](../../Sources/Common/Services/ImageCacheManager.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `BookCoverView`, `TTSManager`

---

### 69. ImportMode (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TTSReplacementManager.swift:144](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift#L144)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 70. JSExecutor (CLASS)

*   **Định nghĩa tại**: [Services/Extensions/Engine/JSExecutor.swift:4](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `BypassWebView`, `CategoryResult`, `ChapterResult`, `Coordinator`, `ExtensionManager`, `ExtensionRegistryItem`, `NovelDetailResult`, `RegistryMetadata`, `RegistryResponse`, `SearchNovelResult`, `SwiftUIWebView`, `WebViewStore`

---

### 71. JapaneseTransliterator (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/JapaneseTransliterator.swift:2](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `PreprocessorRegex`
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 72. Layout (ENUM)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSFloatingWidgetView.swift:11](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift#L11)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `CollapsedCircleView`, `ExpandedControlPanel`, `FloatingWidgetViewModel`, `TTSManager`, `TTSPlayStateReader`, `TTSSettingsView`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 73. LoadedChapter (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2728](../../Sources/Views/Reader/ReaderView.swift#L2728)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 74. MainTabView (STRUCT)

*   **Định nghĩa tại**: [Views/MainTabView.swift:2](../../Sources/Views/MainTabView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DiscoveryView`, `DownloadManager`, `RepositoryManagerView`, `SettingsView`, `ShelfView`, `TTSManager`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `FreeBookApp`

---

### 75. ManageDefinitionsView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/ManageDefinitionsView.swift:2](../../Sources/Views/Dictionary/ManageDefinitionsView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictionaryMatchInfo`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 76. ModelStore (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ModelStore.swift:8](../../Sources/Services/TTS/NghiTTS/ModelStore.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `ModelsResponse`, `NghiTTSClient`, `PiperEngine`, `PiperTTSService`, `PrefetchResult`, `TTSManager`, `TTSModelManagerView`, `TTSSettingsView`, `UnavailablePiperEngine`

---

### 77. ModelsResponse (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:27](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L27)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `BackgroundTaskSession`, `ModelStore`, `TTSError`, `TextPreprocessor`, `Voice`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 78. NghiTTSClient (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:2](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `BackgroundTaskSession`, `ModelStore`, `TTSError`, `TextPreprocessor`, `Voice`
*   **Được sử dụng bởi (Used by)**: `TTSManager`, `TTSModelManagerView`, `TTSSettingsView`

---

### 79. NghiTTSSettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/NghiTTSSettingsView.swift:2](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `PreprocessorSettingKey`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 80. NovelDetailResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:39](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L39)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 81. ONNXPiperEngine (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:3](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `PiperEngine`
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: `PiperEngine`, `PiperTTSService`, `TTSManager`, `UnavailablePiperEngine`

---

### 82. PageFlipModifier (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2749](../../Sources/Views/Reader/ReaderView.swift#L2749)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ViewModifier`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 83. ParagraphCardView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ParagraphCardView.swift:2](../../Sources/Views/Reader/ParagraphCardView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `ReaderTextView`, `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`
*   **Các Extension của kiểu này**:
    *   Tại [Views/Reader/ParagraphCardView.swift:31](../../Sources/Views/Reader/ParagraphCardView.swift#L31) : Equatable

---

### 84. ParagraphItem (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ParagraphCardView.swift:45](../../Sources/Views/Reader/ParagraphCardView.swift#L45)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Codable`, `Equatable`
*   **Sử dụng (Uses)**: `ReaderTextView`, `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: `CachedChapter`, `ChapterCache`, `ChapterLoadState`, `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ReadingProgress`, `ScrollTarget`

---

### 85. ParagraphTracker (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2779](../../Sources/Views/Reader/ReaderView.swift#L2779)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 86. ParsedBook (STRUCT)

*   **Định nghĩa tại**: [Views/Shelf/ShelfMain/ShelfView.swift:527](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift#L527)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookCoverView`, `BookDetailView`, `BypassWebView`, `Chapter`, `DocumentPicker`, `DownloadManager`, `DownloadTrackerView`, `ReaderView`, `TTSManager`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 87. ParserChapter (STRUCT)

*   **Định nghĩa tại**: [Views/Shelf/ShelfMain/ShelfView.swift:522](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift#L522)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookCoverView`, `BookDetailView`, `BypassWebView`, `Chapter`, `DocumentPicker`, `DownloadManager`, `DownloadTrackerView`, `ReaderView`, `TTSManager`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 88. PiperConfig (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:5](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Decodable`
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 89. PiperEngine (PROTOCOL)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/PiperTTSService.swift:2](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `ModelStore`, `ONNXPiperEngine`, `TTSError`, `TextPreprocessor`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `ONNXPiperEngine`, `PiperConfig`, `TextChunk`

---

### 90. PiperTTSService (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/PiperTTSService.swift:6](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift#L6)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `ModelStore`, `ONNXPiperEngine`, `TTSError`, `TextPreprocessor`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 91. PrecisionSliderView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/NghiTTSSettingsView.swift:47](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift#L47)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `PreprocessorSettingKey`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 92. PrefetchManager (ACTOR)

*   **Định nghĩa tại**: [Views/Reader/PrefetchManager.swift:2](../../Sources/Views/Reader/PrefetchManager.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`

---

### 93. PrefetchResult (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:221](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L221)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `BackgroundTaskSession`, `ModelStore`, `TTSError`, `TextPreprocessor`, `Voice`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 94. PreprocessorConfig (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:8](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 95. PreprocessorRegex (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:36](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L36)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: `EnglishTransliterator`, `JapaneseTransliterator`

---

### 96. PreprocessorRuntimeConfig (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:14](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L14)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 97. PreprocessorSettingKey (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:2](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: `NghiTTSSettingsView`, `PrecisionSliderView`

---

### 98. ReaderChapterListView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderChapterListView.swift:12](../../Sources/Views/Reader/ReaderChapterListView.swift#L12)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ReaderTheme`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 99. ReaderSettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:1697](../../Sources/Views/Reader/ReaderView.swift#L1697)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 100. ReaderTextView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:3](../../Sources/Views/Reader/ReaderTextView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewRepresentable`
*   **Sử dụng (Uses)**: `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: `ParagraphCardView`, `ParagraphItem`

---

### 101. ReaderTheme (ENUM)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:4](../../Sources/Views/Reader/ReaderView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `CaseIterable`, `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: `AutoSizingTextView`, `ChapterRowInfo`, `Coordinator`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderTextView`, `ReaderUITextView`

---

### 102. ReaderUITextView (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:289](../../Sources/Views/Reader/ReaderTextView.swift#L289)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UITextView`
*   **Sử dụng (Uses)**: `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 103. ReaderView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:28](../../Sources/Views/Reader/ReaderView.swift#L28)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `ParsedBook`, `ParserChapter`, `ShelfView`
*   **Các Extension của kiểu này**:
    *   Tại [Views/Reader/ReaderView.swift:1788](../../Sources/Views/Reader/ReaderView.swift#L1788)

---

### 104. ReaderViewModel (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderViewModel.swift:8](../../Sources/Views/Reader/ReaderViewModel.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `ChapterCache`, `ChapterResult`, `Extension`, `ExtensionManager`, `ParagraphItem`, `PrefetchManager`, `ReadingProgress`, `ReadingProgressRepository`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 105. ReadingProgress (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:3](../../Sources/Views/Reader/ChapterCache.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`, `ReadingProgressRepository`

---

### 106. ReadingProgressRepository (ACTOR)

*   **Định nghĩa tại**: [Services/ReadingProgress/ReadingProgressStore.swift:18](../../Sources/Services/ReadingProgress/ReadingProgressStore.swift#L18)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ModelActor`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `ReadingProgress`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`

---

### 107. RegexRule (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/RegexRule.swift:2](../../Sources/Services/TTS/Preprocessing/RegexRule.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `EnglishTransliterator`

---

### 108. RegistryMetadata (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:11](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L11)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 109. RegistryResponse (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:7](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L7)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 110. Repository (CLASS)

*   **Định nghĩa tại**: [Models/Database/Repository.swift:5](../../Sources/Models/Database/Repository.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Extension`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `AppLaunchRootView`, `Extension`, `FreeBookApp`, `RepositoryManagerView`

---

### 111. RepositoryManagerView (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Manager/RepositoryManagerView.swift:3](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `ExtensionConfigView`, `ExtensionManager`, `ExtensionRegistryItem`, `Repository`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 112. ScrollTarget (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2742](../../Sources/Views/Reader/ReaderView.swift#L2742)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 113. SearchBar (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/BookDictionaryView.swift:17](../../Sources/Views/Dictionary/BookDictionaryView.swift#L17)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictionaryHubView`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 114. SearchEngine (STRUCT)

*   **Định nghĩa tại**: [Models/Dictionaries/SearchEngine.swift:2](../../Sources/Models/Dictionaries/SearchEngine.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `SearchEnginesConfigView`
*   **Các Extension của kiểu này**:
    *   Tại [Models/Dictionaries/SearchEngine.swift:14](../../Sources/Models/Dictionaries/SearchEngine.swift#L14)

---

### 115. SearchEnginesConfigView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/Search/SearchEnginesConfigView.swift:2](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `SearchEngine`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`

---

### 116. SearchNovelResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:30](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L30)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `CategoryNovelsListView`, `CommentSectionView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `SearchNovelResultWithExt`, `SearchView`, `SourceSearchState`, `SuggestRowView`

---

### 117. SearchNovelResultWithExt (STRUCT)

*   **Định nghĩa tại**: [Views/Search/SearchView.swift:3](../../Sources/Views/Search/SearchView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `Book`, `BookDetailView`, `Chapter`, `Extension`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 118. SearchView (STRUCT)

*   **Định nghĩa tại**: [Views/Search/SearchView.swift:9](../../Sources/Views/Search/SearchView.swift#L9)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookDetailView`, `Chapter`, `Extension`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`

---

### 119. SentenceRange (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:821](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L821)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 120. SettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/Main/SettingsView.swift:3](../../Sources/Views/Settings/Main/SettingsView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `DictionaryCache`, `DocumentPickerPresenter`, `NghiTTSSettingsView`, `SearchEnginesConfigView`, `TTSDictionaryEditView`, `TTSModelManagerView`, `TTSReplacementManagerView`, `TTSSettingsView`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 121. ShareSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:578](../../Sources/Views/Dictionary/DictionaryListView.swift#L578)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewControllerRepresentable`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 122. ShelfView (STRUCT)

*   **Định nghĩa tại**: [Views/Shelf/ShelfMain/ShelfView.swift:4](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookCoverView`, `BookDetailView`, `BypassWebView`, `Chapter`, `DocumentPicker`, `DownloadManager`, `DownloadTrackerView`, `ReaderView`, `TTSManager`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 123. Sibling (STRUCT)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrieBuilder.swift:5](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 124. SiriTTSService (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Siri/SiriTTSService.swift:3](../../Sources/Services/TTS/Siri/SiriTTSService.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `@preconcurrency AVSpeechSynthesizerDelegate`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 125. SkeletonView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/SkeletonView.swift:2](../../Sources/Views/Common/SkeletonView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `BookDetailView`

---

### 126. SourceSearchState (ENUM)

*   **Định nghĩa tại**: [Views/Search/SearchView.swift:59](../../Sources/Views/Search/SearchView.swift#L59)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Book`, `BookDetailView`, `Chapter`, `Extension`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 127. SuggestRowView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/SuggestRowView.swift:2](../../Sources/Views/BookDetail/SuggestRowView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `BookCoverView`, `BookDetailView`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`

---

### 128. SwiftUIWebView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/BypassWebView.swift:445](../../Sources/Views/Common/BypassWebView.swift#L445)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewRepresentable`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 129. TOCRule (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:2](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 130. TTSChapterInfo (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:83](../../Sources/Services/TTS/TTSModels.swift#L83)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Equatable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `TTSManager`

---

### 131. TTSDictionaryEditView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:5](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 132. TTSError (ENUM)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:64](../../Sources/Services/TTS/TTSModels.swift#L64)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `LocalizedError`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `EspeakPhonemizer`, `ModelsResponse`, `NghiTTSClient`, `ONNXPiperEngine`, `PiperConfig`, `PiperEngine`, `PiperTTSService`, `PrefetchResult`, `TextChunk`, `UnavailablePiperEngine`

---

### 133. TTSExtensionInfo (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:97](../../Sources/Services/TTS/TTSModels.swift#L97)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Equatable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `TTSManager`

---

### 134. TTSFloatingWidgetView (STRUCT)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSFloatingWidgetView.swift:2](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `CollapsedCircleView`, `ExpandedControlPanel`, `FloatingWidgetViewModel`, `TTSManager`, `TTSPlayStateReader`, `TTSSettingsView`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `FreeBookApp`

---

### 135. TTSManager (CLASS)

*   **Định nghĩa tại**: [Services/TTS/TTSManager.swift:10](../../Sources/Services/TTS/TTSManager.swift#L10)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `ExtTTSService`, `ImageCacheManager`, `ModelStore`, `NghiTTSClient`, `ONNXPiperEngine`, `PiperTTSService`, `SiriTTSService`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSParagraph`, `TTSReplacementManager`, `TranslateUtils`, `Voice`
*   **Được sử dụng bởi (Used by)**: `AddWordSheet`, `AppLaunchRootView`, `DictionaryMatchInfo`, `EditWordSheet`, `EditingEntry`, `FreeBookApp`, `Layout`, `LoadedChapter`, `MainTabView`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `ShelfView`, `TTSDictionaryEditView`, `TTSFloatingWidgetView`, `TTSModelManagerView`, `TTSPlayStateReader`, `TTSSettingsView`

---

### 136. TTSModelManagerView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSModelManagerView.swift:3](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPickerPresenter`, `ModelStore`, `NghiTTSClient`, `TTSManager`, `Voice`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 137. TTSParagraph (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:52](../../Sources/Services/TTS/TTSModels.swift#L52)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Hashable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 138. TTSPlayStateReader (CLASS)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSPlayStateReader.swift:9](../../Sources/Views/TTSWidget/TTSPlayStateReader.swift#L9)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `TTSManager`
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 139. TTSReplacementManager (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TTSReplacementManager.swift:16](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift#L16)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `TTSManager`, `TTSReplacementManagerView`

---

### 140. TTSReplacementManagerView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSReplacementManagerView.swift:3](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPickerPresenter`, `TTSReplacementManager`, `TTSReplacementRule`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 141. TTSReplacementRule (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TTSReplacementManager.swift:2](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`, `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `TTSReplacementManagerView`

---

### 142. TTSSettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSSettingsView.swift:4](../../Sources/Views/TTSWidget/TTSSettingsView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `ExtensionConfigView`, `ExtensionManager`, `ModelStore`, `NghiTTSClient`, `NghiTTSSettingsView`, `TTSDictionaryEditView`, `TTSManager`, `TTSModelManagerView`, `TTSReplacementManagerView`, `Voice`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `Layout`, `SettingsView`, `TTSFloatingWidgetView`

---

### 143. TaskOptionsSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Download/TaskOptionsSheet.swift:3](../../Sources/Views/Download/TaskOptionsSheet.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookCoverView`, `ChapterLimitOption`, `DownloadManager`, `TaskType`, `ToastManager`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DownloadTrackerView`, `ParsedBook`, `ParserChapter`, `ShelfView`

---

### 144. TaskStatus (ENUM)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:33](../../Sources/Services/Download/DownloadManager.swift#L33)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DownloadTrackerView`

---

### 145. TaskType (ENUM)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:27](../../Sources/Services/Download/DownloadManager.swift#L27)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`, `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DownloadTrackerView`, `ParsedBook`, `ParserChapter`, `ShelfView`, `TaskOptionsSheet`

---

### 146. TextChunk (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:37](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L37)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 147. TextDictionary (CLASS)

*   **Định nghĩa tại**: [Models/Dictionaries/TextDictionary.swift:2](../../Sources/Models/Dictionaries/TextDictionary.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `TrieDictionary`
*   **Sử dụng (Uses)**: `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 148. TextPreprocessor (ACTOR)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:114](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L114)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: `AddWordSheet`, `EditWordSheet`, `EditingEntry`, `ModelsResponse`, `NghiTTSClient`, `PiperEngine`, `PiperTTSService`, `PrefetchResult`, `TTSDictionaryEditView`, `UnavailablePiperEngine`

---

### 149. ToastManager (CLASS)

*   **Định nghĩa tại**: [Common/Services/ToastManager.swift:3](../../Sources/Common/Services/ToastManager.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `ChapterLimitOption`, `DownloadManager`, `DownloadTask`, `FreeBookApp`, `TaskOptionsSheet`, `TaskStatus`, `TaskType`

---

### 150. TranslateUtils (CLASS)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:10](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L10)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `BookDetailView`, `CategoryNovelsListView`, `CategoryResult`, `ChapterLimitOption`, `ChapterResult`, `ChapterRowInfo`, `CommentSectionView`, `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryCard`, `DictionaryListView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `ExtensionManager`, `ExtensionRegistryItem`, `ExtensionSelectorView`, `LoadedChapter`, `NovelDetailResult`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `RegistryMetadata`, `RegistryResponse`, `ScrollTarget`, `SearchNovelResult`, `SearchNovelResultWithExt`, `SearchView`, `SettingsView`, `ShareSheet`, `ShelfView`, `SourceSearchState`, `SuggestRowView`, `TTSManager`, `TaskStatus`, `TaskType`, `TranslationManager`

---

### 151. TranslationManager (CLASS)

*   **Định nghĩa tại**: [Services/Translation/Manager/TranslationManager.swift:2](../../Sources/Services/Translation/Manager/TranslationManager.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `DictionaryCache`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryCard`, `DictionaryHubView`, `DictionaryListView`, `DictionaryMatchInfo`, `DictionaryNavRow`, `FreeBookApp`, `LoadedChapter`, `ManageDefinitionsView`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `SentenceRange`, `SettingsView`, `ShareSheet`, `SourceSearchState`, `TOCRule`, `TranslateUtils`, `TranslationWordToken`

---

### 152. TranslationWordToken (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:806](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L806)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 153. TrieDictionary (PROTOCOL)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrie.swift:2](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `SentenceRange`, `TOCRule`, `TextDictionary`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`

---

### 154. UnavailablePiperEngine (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/PiperTTSService.swift:67](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift#L67)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `PiperEngine`
*   **Sử dụng (Uses)**: `ModelStore`, `ONNXPiperEngine`, `TTSError`, `TextPreprocessor`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 155. UnitPatternSpec (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:123](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L123)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 156. VietnameseNumberSpeller (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/VietnameseNumberSpeller.swift:2](../../Sources/Services/TTS/Preprocessing/VietnameseNumberSpeller.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 157. VietnameseWordChecker (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/VietnameseWordChecker.swift:4](../../Sources/Services/TTS/Preprocessing/VietnameseWordChecker.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 158. Voice (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:2](../../Sources/Services/TTS/TTSModels.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `ModelsResponse`, `NghiTTSClient`, `PrefetchResult`, `TTSManager`, `TTSModelManagerView`, `TTSSettingsView`
*   **Các Extension của kiểu này**:
    *   Tại [Services/TTS/TTSModels.swift:45](../../Sources/Services/TTS/TTSModels.swift#L45)

---

### 159. WAVEncoder (ENUM)

*   **Định nghĩa tại**: [Services/TTS/WAVEncoder.swift:2](../../Sources/Services/TTS/WAVEncoder.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `ONNXPiperEngine`, `PiperConfig`, `PiperEngine`, `PiperTTSService`, `TextChunk`, `UnavailablePiperEngine`

---

### 160. WebViewLoader (CLASS)

*   **Định nghĩa tại**: [Services/Extensions/Engine/JSExecutor.swift:722](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L722)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `WKNavigationDelegate`
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 161. WebViewStore (CLASS)

*   **Định nghĩa tại**: [Views/Common/BypassWebView.swift:573](../../Sources/Views/Common/BypassWebView.swift#L573)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 162. WidgetMode (ENUM)

*   **Định nghĩa tại**: [Views/TTSWidget/WidgetState.swift:2](../../Sources/Views/TTSWidget/WidgetState.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `FloatingWidgetViewModel`

---

### 163. WordToken (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:894](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L894)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

## Các Extension trên các kiểu dữ liệu hệ thống (System Types Extensions)

### 1. Extension trên `String`
*   **Định nghĩa tại**: [Common/Extensions/String+Crypto.swift:3](../../Sources/Common/Extensions/String+Crypto.swift#L3)

### 2. Extension trên `String`
*   **Định nghĩa tại**: [Common/Extensions/String+HTML.swift:2](../../Sources/Common/Extensions/String+HTML.swift#L2)

### 3. Extension trên `View`
*   **Định nghĩa tại**: [Common/Extensions/View+Keyboard.swift:2](../../Sources/Common/Extensions/View+Keyboard.swift#L2)

### 4. Extension trên `Data`
*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrie.swift:7](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift#L7)

### 5. Extension trên `String`
*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:12](../../Sources/Services/TTS/TTSModels.swift#L12)

### 6. Extension trên `Data`
*   **Định nghĩa tại**: [Services/TTS/WAVEncoder.swift:34](../../Sources/Services/TTS/WAVEncoder.swift#L34)

### 7. Extension trên `CharacterSet`
*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:229](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L229)

### 8. Extension trên `UTType`
*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:4](../../Sources/Views/Common/DocumentPicker.swift#L4)

### 9. Extension trên `UIView`
*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:337](../../Sources/Views/Reader/ReaderTextView.swift#L337)

### 10. Extension trên `AnyTransition`
*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2763](../../Sources/Views/Reader/ReaderView.swift#L2763)


#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- `TTSFloatingWidgetView` composes the capsule and `TTSCoverView`; `FloatingWidgetViewModel` owns `WidgetMode`, edge persistence, drag snapping, and the cancellable idle-collapse task.
- `DictionaryMatchInfo` is a module-level `Identifiable/Equatable` value shared by Reader and definition management. `ReaderSettingsView` and generic `ReaderViewModelObserver` are standalone Reader UI types.
- `ChapterKey` identifies shared loads; `BookMetadataSnapshot`, `ChapterMetadataSnapshot`, and `PersistedChapterSnapshot` cross actor boundaries; `ChapterPersistenceStore` owns pending SwiftData writes and retries.
- `RepositoryManagerView` adds `repositoryToDelete` plus confirmation presentation state while persisted `Repository.isEnabled` remains schema-only compatibility data.

<!-- GENERATED END -->
