---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-14T09:15:00+07:00
git_commit: UNKNOWN
source_files: 87
document_version: 1
---

# Đồ thị Kiểu dữ liệu (Type Graph)

Tài liệu này liệt kê chi tiết định nghĩa và mối quan hệ giữa các kiểu dữ liệu (Class, Struct, Enum, Protocol, Actor, Extension) trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
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

### 2. AddWordSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:496](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L496)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 3. AllCommentsView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/AllCommentsView.swift:2](../../Sources/Views/BookDetail/AllCommentsView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `CommentSectionView`

---

### 4. AppDiagnostics (CLASS)

*   **Định nghĩa tại**: [Services/Logging/AppLogger.swift:83](../../Sources/Services/Logging/AppLogger.swift#L83)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `CategoryResult`, `ChapterResult`, `ExtensionManager`, `ExtensionRegistryItem`, `NovelDetailResult`, `RegistryMetadata`, `RegistryResponse`, `SearchNovelResult`

---

### 5. AppLaunchRootView (STRUCT)

*   **Định nghĩa tại**: [App/FreeBookApp.swift:19](../../Sources/App/FreeBookApp.swift#L19)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLoadingView`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `MainTabView`, `Repository`, `TTSFloatingWidgetView`, `TTSManager`, `ToastManager`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 6. AppLoadingView (STRUCT)

*   **Định nghĩa tại**: [Views/AppLoadingView.swift:2](../../Sources/Views/AppLoadingView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `FreeBookApp`

---

### 7. AppLogger (CLASS)

*   **Định nghĩa tại**: [Services/Logging/AppLogger.swift:2](../../Sources/Services/Logging/AppLogger.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `AudioConfig`, `BackgroundTaskSession`, `CachedChapter`, `CachedSession`, `CategoryNovelsListView`, `CategoryResult`, `ChapterCache`, `ChapterLimitOption`, `ChapterLoadState`, `ChapterResult`, `DictionaryCard`, `DictionaryMatchInfo`, `DictionaryType`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `EspeakPhonemizer`, `ExtTTSService`, `ExtensionManager`, `ExtensionRegistryItem`, `ExtensionSelectorView`, `ImageCacheManager`, `ImportMode`, `JSExecutor`, `LoadedChapter`, `ModelsResponse`, `NghiTTSClient`, `NovelDetailResult`, `ONNXPiperEngine`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `PiperConfig`, `PrefetchManager`, `PrefetchResult`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ReadingProgress`, `ReadingProgressRepository`, `RegistryMetadata`, `RegistryResponse`, `ScrollTarget`, `SearchNovelResult`, `SettingsView`, `ShelfView`, `TTSManager`, `TTSReplacementManager`, `TTSReplacementRule`, `TaskStatus`, `TaskType`, `TextChunk`, `TextPreprocessor`, `UnitPatternSpec`, `WebViewLoader`, `WordToken`

---

### 8. AudioConfig (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:6](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L6)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Decodable`
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 9. AutoSizingTextView (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:319](../../Sources/Views/Reader/ReaderTextView.swift#L319)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ReaderUITextView`
*   **Sử dụng (Uses)**: `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 10. BackgroundTaskSession (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/BackgroundTaskSession.swift:5](../../Sources/Services/TTS/BackgroundTaskSession.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `ModelsResponse`, `NghiTTSClient`, `PrefetchResult`

---

### 11. Book (CLASS)

*   **Định nghĩa tại**: [Models/Database/Book.swift:7](../../Sources/Models/Database/Book.swift#L7)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Chapter`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `BookDetailView`, `Chapter`, `ChapterLimitOption`, `ChapterRowInfo`, `DictionaryMatchInfo`, `DownloadManager`, `DownloadTask`, `DownloadTrackerView`, `FreeBookApp`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ReadingProgressRepository`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `ShelfView`, `SourceSearchState`, `TTSManager`, `TaskOptionsSheet`, `TaskStatus`, `TaskType`
*   **Các Extension của kiểu này**:
    *   Tại [Models/Database/Book.swift:64](../../Sources/Models/Database/Book.swift#L64) : Identifiable

---

### 12. BookCoverView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/BookCoverView.swift:2](../../Sources/Views/Common/BookCoverView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `ImageCacheManager`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `CategoryNovelsListView`, `DownloadTrackerView`, `ParsedBook`, `ParserChapter`, `ShelfView`, `SuggestRowView`, `TaskOptionsSheet`

---

### 13. BookDetailView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/BookDetailView.swift:3](../../Sources/Views/BookDetail/BookDetailView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookCoverView`, `BookDictionaryView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Chapter`, `ChapterResult`, `CommentSectionView`, `Extension`, `ExtensionIconView`, `ExtensionManager`, `JSExecutor`, `ReaderView`, `SearchView`, `SkeletonView`, `SuggestRowView`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `CategoryNovelsListView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `ShelfView`, `SourceSearchState`, `SuggestRowView`

---

### 14. BookDictionaryView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/BookDictionaryView.swift:7](../../Sources/Views/Dictionary/BookDictionaryView.swift#L7)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictionaryHubView`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 15. BypassWebView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/BypassWebView.swift:4](../../Sources/Views/Common/BypassWebView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `ShelfView`

---

### 16. CacheSummary (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ModelStore.swift:2](../../Sources/Services/TTS/NghiTTS/ModelStore.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 17. CachedChapter (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:23](../../Sources/Views/Reader/ChapterCache.swift#L23)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 18. CachedSession (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:12](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L12)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 19. CallInfo (STRUCT)

*   **Định nghĩa tại**: [Services/Logging/AppLogger.swift:89](../../Sources/Services/Logging/AppLogger.swift#L89)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `CategoryResult`, `ChapterResult`, `ExtensionManager`, `ExtensionRegistryItem`, `NovelDetailResult`, `RegistryMetadata`, `RegistryResponse`, `SearchNovelResult`

---

### 20. CategoryNovelsListView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/CategoryNovelsListView.swift:2](../../Sources/Views/Common/CategoryNovelsListView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookCoverView`, `BookDetailView`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`

---

### 21. CategoryResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:821](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L821)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `BookDetailView`, `CategoryNovelsListView`, `CommentSectionView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `SuggestRowView`

---

### 22. Chapter (CLASS)

*   **Định nghĩa tại**: [Models/Database/Chapter.swift:5](../../Sources/Models/Database/Chapter.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Book`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `Book`, `BookDetailView`, `ChapterLimitOption`, `ChapterRowInfo`, `DictionaryMatchInfo`, `DownloadManager`, `DownloadTask`, `FreeBookApp`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `ShelfView`, `SourceSearchState`, `TaskStatus`, `TaskType`

---

### 23. ChapterCache (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:41](../../Sources/Views/Reader/ChapterCache.swift#L41)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`

---

### 24. ChapterLimitOption (ENUM)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:4](../../Sources/Services/Download/DownloadManager.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Int`, `CaseIterable`, `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `TaskOptionsSheet`

---

### 25. ChapterLoadState (ENUM)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:12](../../Sources/Views/Reader/ChapterCache.swift#L12)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 26. ChapterResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:53](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L53)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `ChapterRowInfo`, `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ScrollTarget`

---

### 27. ChapterRowInfo (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderChapterListView.swift:3](../../Sources/Views/Reader/ReaderChapterListView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `Book`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ReaderTheme`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 28. CollapsedCircleView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/CollapsedCircleView.swift:2](../../Sources/Views/Reader/CollapsedCircleView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 29. CommentSectionView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/CommentSectionView.swift:2](../../Sources/Views/BookDetail/CommentSectionView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AllCommentsView`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`

---

### 30. ConfigItem (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Config/ExtensionConfigView.swift:17](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift#L17)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `Extension`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 31. Coordinator (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:194](../../Sources/Views/Reader/ReaderTextView.swift#L194)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `UITextViewDelegate`, `UIGestureRecognizerDelegate`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`, `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 32. DictEntry (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/DictionaryCache.swift:220](../../Sources/Services/Translation/Utils/DictionaryCache.swift#L220)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryListView`, `ShareSheet`

---

### 33. DictEntrySheet (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:508](../../Sources/Views/Dictionary/DictionaryListView.swift#L508)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 34. DictSheetMode (ENUM)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:496](../../Sources/Views/Dictionary/DictionaryListView.swift#L496)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 35. DictType (ENUM)

*   **Định nghĩa tại**: [Services/Translation/Utils/DictionaryCache.swift:201](../../Sources/Services/Translation/Utils/DictionaryCache.swift#L201)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`
*   **Sử dụng (Uses)**: `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryHubView`, `DictionaryListView`, `DictionaryNavRow`, `ShareSheet`

---

### 36. DictionaryCache (CLASS)

*   **Định nghĩa tại**: [Services/Translation/Utils/DictionaryCache.swift:8](../../Sources/Services/Translation/Utils/DictionaryCache.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryCard`, `DictionaryListView`, `SettingsView`, `ShareSheet`, `TranslationManager`

---

### 37. DictionaryCard (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/Main/SettingsView.swift:376](../../Sources/Views/Settings/Main/SettingsView.swift#L376)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `DictionaryCache`, `DocumentPickerPresenter`, `NghiTTSSettingsView`, `SearchEnginesConfigView`, `TTSDictionaryEditView`, `TTSModelManagerView`, `TTSReplacementManagerView`, `TTSSettingsView`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 38. DictionaryHubView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryHubView.swift:2](../../Sources/Views/Dictionary/DictionaryHubView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictType`, `DictionaryListView`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `BookDictionaryView`, `SearchBar`

---

### 39. DictionaryListView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:3](../../Sources/Views/Dictionary/DictionaryListView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictionaryHubView`, `DictionaryNavRow`

---

### 40. DictionaryMatchInfo (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:1780](../../Sources/Views/Reader/ReaderView.swift#L1780)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: `ManageDefinitionsView`

---

### 41. DictionaryNavRow (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryHubView.swift:91](../../Sources/Views/Dictionary/DictionaryHubView.swift#L91)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictType`, `DictionaryListView`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 42. DictionaryType (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:873](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L873)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 43. DiscoveryCategoryTabView (STRUCT)

*   **Định nghĩa tại**: [Views/Discovery/DiscoveryView.swift:409](../../Sources/Views/Discovery/DiscoveryView.swift#L409)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookDetailView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Extension`, `ExtensionConfigView`, `ExtensionIconView`, `ExtensionManager`, `SearchNovelResult`, `SearchView`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 44. DiscoveryView (STRUCT)

*   **Định nghĩa tại**: [Views/Discovery/DiscoveryView.swift:3](../../Sources/Views/Discovery/DiscoveryView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookDetailView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Extension`, `ExtensionConfigView`, `ExtensionIconView`, `ExtensionManager`, `SearchNovelResult`, `SearchView`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 45. DocumentPicker (STRUCT)

*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:136](../../Sources/Views/Common/DocumentPicker.swift#L136)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewControllerRepresentable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AddWordSheet`, `EditWordSheet`, `EditingEntry`, `ParsedBook`, `ParserChapter`, `ShelfView`, `TTSDictionaryEditView`

---

### 46. DocumentPickerHostViewController (CLASS)

*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:15](../../Sources/Views/Common/DocumentPicker.swift#L15)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewController`, `UIDocumentPickerDelegate`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 47. DocumentPickerPresenter (STRUCT)

*   **Định nghĩa tại**: [Views/Common/DocumentPicker.swift:79](../../Sources/Views/Common/DocumentPicker.swift#L79)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewControllerRepresentable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictEntrySheet`, `DictSheetMode`, `DictionaryCard`, `DictionaryListView`, `SettingsView`, `ShareSheet`, `TTSModelManagerView`, `TTSReplacementManagerView`

---

### 48. DoubleArrayTrie (CLASS)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrie.swift:25](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift#L25)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `TrieDictionary`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryListView`, `ShareSheet`, `TranslationManager`

---

### 49. DoubleArrayTrieBuilder (CLASS)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrieBuilder.swift:2](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryListView`, `ShareSheet`, `TranslationManager`

---

### 50. DownloadManager (CLASS)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:61](../../Sources/Services/Download/DownloadManager.swift#L61)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DownloadTrackerView`, `MainTabView`, `ParsedBook`, `ParserChapter`, `ShelfView`, `TaskOptionsSheet`

---

### 51. DownloadTask (STRUCT)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:41](../../Sources/Services/Download/DownloadManager.swift#L41)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DownloadTrackerView`

---

### 52. DownloadTaskModel (CLASS)

*   **Định nghĩa tại**: [Models/Database/DownloadTaskModel.swift:5](../../Sources/Models/Database/DownloadTaskModel.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `ChapterLimitOption`, `DownloadManager`, `DownloadTask`, `FreeBookApp`, `TaskStatus`, `TaskType`

---

### 53. DownloadTrackerView (STRUCT)

*   **Định nghĩa tại**: [Views/Download/DownloadTrackerView.swift:3](../../Sources/Views/Download/DownloadTrackerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookCoverView`, `DownloadManager`, `DownloadTask`, `TaskOptionsSheet`, `TaskStatus`, `TaskType`
*   **Được sử dụng bởi (Used by)**: `ParsedBook`, `ParserChapter`, `ShelfView`

---

### 54. EdgeDirection (ENUM)

*   **Định nghĩa tại**: [Views/TTSWidget/WidgetState.swift:8](../../Sources/Views/TTSWidget/WidgetState.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `FloatingWidgetViewModel`

---

### 55. EditWordSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:558](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L558)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 56. EditingEntry (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:484](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L484)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 57. EnglishTransliterator (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/EnglishTransliterator.swift:2](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `PreprocessorRegex`, `RegexRule`
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 58. EspeakPhonemizer (CLASS)

*   **Định nghĩa tại**: [Services/TTS/EspeakPhonemizer.swift:6](../../Sources/Services/TTS/EspeakPhonemizer.swift#L6)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `TTSError`
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `ONNXPiperEngine`, `PiperConfig`, `TextChunk`

---

### 59. ExpandedControlPanel (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ExpandedControlPanel.swift:2](../../Sources/Views/Reader/ExpandedControlPanel.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 60. ExtTTSService (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Ext/ExtTTSService.swift:3](../../Sources/Services/TTS/Ext/ExtTTSService.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `ExtensionManager`
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 61. Extension (CLASS)

*   **Định nghĩa tại**: [Models/Database/Extension.swift:5](../../Sources/Models/Database/Extension.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Repository`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `AppLaunchRootView`, `BookDetailView`, `BypassWebView`, `ChapterLimitOption`, `ChapterRowInfo`, `ConfigItem`, `Coordinator`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `ExtensionConfigView`, `ExtensionSelectorView`, `ExtensionStoreView`, `FreeBookApp`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `Repository`, `RepositoryManagerView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `SourceSearchState`, `SwiftUIWebView`, `TTSSettingsView`, `TaskStatus`, `TaskType`, `WebViewStore`

---

### 62. ExtensionConfigView (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Config/ExtensionConfigView.swift:3](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `ExtensionStoreView`, `RepositoryManagerView`, `TTSSettingsView`

---

### 63. ExtensionIconView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/ExtensionIconView.swift:2](../../Sources/Views/Common/ExtensionIconView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`

---

### 64. ExtensionManager (CLASS)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:61](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L61)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `AllCommentsView`, `BookDetailView`, `CategoryNovelsListView`, `ChapterLimitOption`, `ChapterRowInfo`, `CommentSectionView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `ExtTTSService`, `ExtensionSelectorView`, `ExtensionStoreView`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `RepositoryManagerView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `SourceSearchState`, `SuggestRowView`, `TTSSettingsView`, `TaskStatus`, `TaskType`

---

### 65. ExtensionRegistryItem (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:16](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L16)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `ExtensionStoreView`, `RepositoryManagerView`

---

### 66. ExtensionSelectorView (STRUCT)

*   **Định nghĩa tại**: [Views/Discovery/DiscoveryView.swift:620](../../Sources/Views/Discovery/DiscoveryView.swift#L620)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `BookDetailView`, `BypassWebView`, `CategoryNovelsListView`, `CategoryResult`, `Extension`, `ExtensionConfigView`, `ExtensionIconView`, `ExtensionManager`, `SearchNovelResult`, `SearchView`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 67. ExtensionStoreView (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Store/ExtensionStoreView.swift:3](../../Sources/Views/Extensions/Store/ExtensionStoreView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `ExtensionConfigView`, `ExtensionManager`, `ExtensionRegistryItem`, `Repository`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `RepositoryManagerView`

---

### 68. FloatingWidgetViewModel (CLASS)

*   **Định nghĩa tại**: [Views/TTSWidget/FloatingWidgetViewModel.swift:5](../../Sources/Views/TTSWidget/FloatingWidgetViewModel.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `EdgeDirection`, `WidgetMode`
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 69. FreeBookApp (STRUCT)

*   **Định nghĩa tại**: [App/FreeBookApp.swift:5](../../Sources/App/FreeBookApp.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `App`
*   **Sử dụng (Uses)**: `AppLoadingView`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `MainTabView`, `Repository`, `TTSFloatingWidgetView`, `TTSManager`, `ToastManager`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 70. ImageCacheManager (CLASS)

*   **Định nghĩa tại**: [Common/Services/ImageCacheManager.swift:3](../../Sources/Common/Services/ImageCacheManager.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `BookCoverView`, `TTSManager`

---

### 71. ImportMode (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TTSReplacementManager.swift:144](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift#L144)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 72. JSExecutor (CLASS)

*   **Định nghĩa tại**: [Services/Extensions/Engine/JSExecutor.swift:4](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `BypassWebView`, `CategoryResult`, `ChapterResult`, `Coordinator`, `ExtensionManager`, `ExtensionRegistryItem`, `NovelDetailResult`, `RegistryMetadata`, `RegistryResponse`, `SearchNovelResult`, `SwiftUIWebView`, `WebViewStore`

---

### 73. JapaneseTransliterator (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/JapaneseTransliterator.swift:2](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `PreprocessorRegex`
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 74. Layout (ENUM)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSFloatingWidgetView.swift:11](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift#L11)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `CollapsedCircleView`, `ExpandedControlPanel`, `FloatingWidgetViewModel`, `TTSManager`, `TTSPlayStateReader`, `TTSSettingsView`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 75. LoadedChapter (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2728](../../Sources/Views/Reader/ReaderView.swift#L2728)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 76. MainTabView (STRUCT)

*   **Định nghĩa tại**: [Views/MainTabView.swift:2](../../Sources/Views/MainTabView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DiscoveryView`, `DownloadManager`, `RepositoryManagerView`, `SettingsView`, `ShelfView`, `TTSManager`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `FreeBookApp`

---

### 77. ManageDefinitionsView (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/ManageDefinitionsView.swift:2](../../Sources/Views/Dictionary/ManageDefinitionsView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictionaryMatchInfo`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 78. ModelStore (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ModelStore.swift:8](../../Sources/Services/TTS/NghiTTS/ModelStore.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `ModelsResponse`, `NghiTTSClient`, `PiperEngine`, `PiperTTSService`, `PrefetchResult`, `TTSManager`, `TTSModelManagerView`, `TTSSettingsView`, `UnavailablePiperEngine`

---

### 79. ModelsResponse (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:27](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L27)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `BackgroundTaskSession`, `ModelStore`, `TTSError`, `TextPreprocessor`, `Voice`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 80. NghiTTSClient (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:2](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `BackgroundTaskSession`, `ModelStore`, `TTSError`, `TextPreprocessor`, `Voice`
*   **Được sử dụng bởi (Used by)**: `TTSManager`, `TTSModelManagerView`, `TTSSettingsView`

---

### 81. NghiTTSSettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/NghiTTSSettingsView.swift:2](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `PreprocessorSettingKey`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 82. NovelDetailResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:39](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L39)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 83. ONNXPiperEngine (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:3](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `PiperEngine`
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: `PiperEngine`, `PiperTTSService`, `TTSManager`, `UnavailablePiperEngine`

---

### 84. PageFlipModifier (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2749](../../Sources/Views/Reader/ReaderView.swift#L2749)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ViewModifier`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 85. ParagraphCardView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ParagraphCardView.swift:2](../../Sources/Views/Reader/ParagraphCardView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `ReaderTextView`, `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`
*   **Các Extension của kiểu này**:
    *   Tại [Views/Reader/ParagraphCardView.swift:31](../../Sources/Views/Reader/ParagraphCardView.swift#L31) : Equatable

---

### 86. ParagraphItem (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ParagraphCardView.swift:45](../../Sources/Views/Reader/ParagraphCardView.swift#L45)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Codable`, `Equatable`
*   **Sử dụng (Uses)**: `ReaderTextView`, `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: `CachedChapter`, `ChapterCache`, `ChapterLoadState`, `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `ReadingProgress`, `ScrollTarget`

---

### 87. ParagraphTracker (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2779](../../Sources/Views/Reader/ReaderView.swift#L2779)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 88. ParsedBook (STRUCT)

*   **Định nghĩa tại**: [Views/Shelf/ShelfMain/ShelfView.swift:527](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift#L527)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookCoverView`, `BookDetailView`, `BypassWebView`, `Chapter`, `DocumentPicker`, `DownloadManager`, `DownloadTrackerView`, `ReaderView`, `TTSManager`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 89. ParserChapter (STRUCT)

*   **Định nghĩa tại**: [Views/Shelf/ShelfMain/ShelfView.swift:522](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift#L522)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookCoverView`, `BookDetailView`, `BypassWebView`, `Chapter`, `DocumentPicker`, `DownloadManager`, `DownloadTrackerView`, `ReaderView`, `TTSManager`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 90. PiperConfig (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:5](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Decodable`
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 91. PiperEngine (PROTOCOL)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/PiperTTSService.swift:2](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `ModelStore`, `ONNXPiperEngine`, `TTSError`, `TextPreprocessor`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `ONNXPiperEngine`, `PiperConfig`, `TextChunk`

---

### 92. PiperTTSService (CLASS)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/PiperTTSService.swift:6](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift#L6)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `ModelStore`, `ONNXPiperEngine`, `TTSError`, `TextPreprocessor`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 93. PrecisionSliderView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/NghiTTSSettingsView.swift:47](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift#L47)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `PreprocessorSettingKey`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 94. PrefetchManager (ACTOR)

*   **Định nghĩa tại**: [Views/Reader/PrefetchManager.swift:2](../../Sources/Views/Reader/PrefetchManager.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`

---

### 95. PrefetchResult (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/NghiTTSClient.swift:221](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift#L221)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `BackgroundTaskSession`, `ModelStore`, `TTSError`, `TextPreprocessor`, `Voice`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 96. PreprocessorConfig (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:8](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 97. PreprocessorRegex (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:36](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L36)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: `EnglishTransliterator`, `JapaneseTransliterator`

---

### 98. PreprocessorRuntimeConfig (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:14](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L14)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 99. PreprocessorSettingKey (ENUM)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:2](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: `NghiTTSSettingsView`, `PrecisionSliderView`

---

### 100. ReaderChapterListView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderChapterListView.swift:12](../../Sources/Views/Reader/ReaderChapterListView.swift#L12)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ReaderTheme`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 101. ReaderSettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:1697](../../Sources/Views/Reader/ReaderView.swift#L1697)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 102. ReaderTextView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:3](../../Sources/Views/Reader/ReaderTextView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewRepresentable`
*   **Sử dụng (Uses)**: `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: `ParagraphCardView`, `ParagraphItem`

---

### 103. ReaderTheme (ENUM)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:4](../../Sources/Views/Reader/ReaderView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `CaseIterable`, `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: `AutoSizingTextView`, `ChapterRowInfo`, `Coordinator`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderTextView`, `ReaderUITextView`

---

### 104. ReaderUITextView (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderTextView.swift:289](../../Sources/Views/Reader/ReaderTextView.swift#L289)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UITextView`
*   **Sử dụng (Uses)**: `ReaderTheme`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 105. ReaderView (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:28](../../Sources/Views/Reader/ReaderView.swift#L28)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `ParsedBook`, `ParserChapter`, `ShelfView`
*   **Các Extension của kiểu này**:
    *   Tại [Views/Reader/ReaderView.swift:1788](../../Sources/Views/Reader/ReaderView.swift#L1788)

---

### 106. ReaderViewModel (CLASS)

*   **Định nghĩa tại**: [Views/Reader/ReaderViewModel.swift:8](../../Sources/Views/Reader/ReaderViewModel.swift#L8)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `ChapterCache`, `ChapterResult`, `Extension`, `ExtensionManager`, `ParagraphItem`, `PrefetchManager`, `ReadingProgress`, `ReadingProgressRepository`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 107. ReadingProgress (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ChapterCache.swift:3](../../Sources/Views/Reader/ChapterCache.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `ParagraphItem`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`, `ReadingProgressRepository`

---

### 108. ReadingProgressRepository (ACTOR)

*   **Định nghĩa tại**: [Views/Reader/ReadingProgressRepository.swift:5](../../Sources/Views/Reader/ReadingProgressRepository.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ModelActor`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `ReadingProgress`
*   **Được sử dụng bởi (Used by)**: `ReaderViewModel`

---

### 109. RegexRule (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/RegexRule.swift:2](../../Sources/Services/TTS/Preprocessing/RegexRule.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `EnglishTransliterator`

---

### 110. RegistryMetadata (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:11](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L11)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 111. RegistryResponse (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:7](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L7)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 112. Repository (CLASS)

*   **Định nghĩa tại**: [Models/Database/Repository.swift:5](../../Sources/Models/Database/Repository.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Extension`
*   **Được sử dụng bởi (Used by)**: `AddRepositoryView`, `AppLaunchRootView`, `Extension`, `ExtensionStoreView`, `FreeBookApp`, `RepositoryManagerView`

---

### 113. RepositoryManagerView (STRUCT)

*   **Định nghĩa tại**: [Views/Extensions/Manager/RepositoryManagerView.swift:3](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `ExtensionConfigView`, `ExtensionManager`, `ExtensionRegistryItem`, `ExtensionStoreView`, `Repository`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 114. ScrollTarget (STRUCT)

*   **Định nghĩa tại**: [Views/Reader/ReaderView.swift:2742](../../Sources/Views/Reader/ReaderView.swift#L2742)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookDetailView`, `BookDictionaryView`, `BypassWebView`, `CachedChapter`, `Chapter`, `ChapterResult`, `Extension`, `ExtensionManager`, `ManageDefinitionsView`, `ParagraphCardView`, `ParagraphItem`, `ReaderChapterListView`, `ReaderViewModel`, `SearchEngine`, `SentenceRange`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSManager`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 115. SearchBar (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/BookDictionaryView.swift:17](../../Sources/Views/Dictionary/BookDictionaryView.swift#L17)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DictionaryHubView`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 116. SearchEngine (STRUCT)

*   **Định nghĩa tại**: [Models/Dictionaries/SearchEngine.swift:2](../../Sources/Models/Dictionaries/SearchEngine.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `SearchEnginesConfigView`
*   **Các Extension của kiểu này**:
    *   Tại [Models/Dictionaries/SearchEngine.swift:14](../../Sources/Models/Dictionaries/SearchEngine.swift#L14)

---

### 117. SearchEnginesConfigView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/Search/SearchEnginesConfigView.swift:2](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `SearchEngine`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`

---

### 118. SearchNovelResult (STRUCT)

*   **Định nghĩa tại**: [Services/Extensions/Manager/ExtensionManager.swift:30](../../Sources/Services/Extensions/Manager/ExtensionManager.swift#L30)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `AppDiagnostics`, `AppLogger`, `CallInfo`, `JSExecutor`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `CategoryNovelsListView`, `CommentSectionView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`, `SearchNovelResultWithExt`, `SearchView`, `SourceSearchState`, `SuggestRowView`

---

### 119. SearchNovelResultWithExt (STRUCT)

*   **Định nghĩa tại**: [Views/Search/SearchView.swift:3](../../Sources/Views/Search/SearchView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`
*   **Sử dụng (Uses)**: `Book`, `BookDetailView`, `Chapter`, `Extension`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 120. SearchView (STRUCT)

*   **Định nghĩa tại**: [Views/Search/SearchView.swift:9](../../Sources/Views/Search/SearchView.swift#L9)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookDetailView`, `Chapter`, `Extension`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DiscoveryCategoryTabView`, `DiscoveryView`, `ExtensionSelectorView`

---

### 121. SentenceRange (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:821](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L821)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 122. SettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/Main/SettingsView.swift:3](../../Sources/Views/Settings/Main/SettingsView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `DictionaryCache`, `DocumentPickerPresenter`, `NghiTTSSettingsView`, `SearchEnginesConfigView`, `TTSDictionaryEditView`, `TTSModelManagerView`, `TTSReplacementManagerView`, `TTSSettingsView`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 123. ShareSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Dictionary/DictionaryListView.swift:578](../../Sources/Views/Dictionary/DictionaryListView.swift#L578)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewControllerRepresentable`
*   **Sử dụng (Uses)**: `DictEntry`, `DictType`, `DictionaryCache`, `DocumentPickerPresenter`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 124. ShelfView (STRUCT)

*   **Định nghĩa tại**: [Views/Shelf/ShelfMain/ShelfView.swift:4](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `BookCoverView`, `BookDetailView`, `BypassWebView`, `Chapter`, `DocumentPicker`, `DownloadManager`, `DownloadTrackerView`, `ReaderView`, `TTSManager`, `TaskOptionsSheet`, `TaskType`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `MainTabView`

---

### 125. Sibling (STRUCT)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrieBuilder.swift:5](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 126. SiriTTSService (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Siri/SiriTTSService.swift:3](../../Sources/Services/TTS/Siri/SiriTTSService.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `@preconcurrency AVSpeechSynthesizerDelegate`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 127. SkeletonView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/SkeletonView.swift:2](../../Sources/Views/Common/SkeletonView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `BookDetailView`

---

### 128. SourceSearchState (ENUM)

*   **Định nghĩa tại**: [Views/Search/SearchView.swift:59](../../Sources/Views/Search/SearchView.swift#L59)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `Book`, `BookDetailView`, `Chapter`, `Extension`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`, `TranslationManager`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 129. SuggestRowView (STRUCT)

*   **Định nghĩa tại**: [Views/BookDetail/SuggestRowView.swift:2](../../Sources/Views/BookDetail/SuggestRowView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `BookCoverView`, `BookDetailView`, `CategoryResult`, `ExtensionManager`, `SearchNovelResult`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`

---

### 130. SwiftUIWebView (STRUCT)

*   **Định nghĩa tại**: [Views/Common/BypassWebView.swift:445](../../Sources/Views/Common/BypassWebView.swift#L445)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `UIViewRepresentable`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 131. TOCRule (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:2](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 132. TTSChapterInfo (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:83](../../Sources/Services/TTS/TTSModels.swift#L83)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Equatable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `TTSManager`

---

### 133. TTSDictionaryEditView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSDictionaryEditView.swift:5](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift#L5)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPicker`, `TTSManager`, `TextPreprocessor`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 134. TTSError (ENUM)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:64](../../Sources/Services/TTS/TTSModels.swift#L64)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `LocalizedError`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `EspeakPhonemizer`, `ModelsResponse`, `NghiTTSClient`, `ONNXPiperEngine`, `PiperConfig`, `PiperEngine`, `PiperTTSService`, `PrefetchResult`, `TextChunk`, `UnavailablePiperEngine`

---

### 135. TTSExtensionInfo (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:97](../../Sources/Services/TTS/TTSModels.swift#L97)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Equatable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `TTSManager`

---

### 136. TTSFloatingWidgetView (STRUCT)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSFloatingWidgetView.swift:2](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `CollapsedCircleView`, `ExpandedControlPanel`, `FloatingWidgetViewModel`, `TTSManager`, `TTSPlayStateReader`, `TTSSettingsView`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `FreeBookApp`

---

### 137. TTSManager (CLASS)

*   **Định nghĩa tại**: [Services/TTS/TTSManager.swift:10](../../Sources/Services/TTS/TTSManager.swift#L10)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `ExtTTSService`, `ImageCacheManager`, `ModelStore`, `NghiTTSClient`, `ONNXPiperEngine`, `PiperTTSService`, `SiriTTSService`, `TTSChapterInfo`, `TTSExtensionInfo`, `TTSParagraph`, `TTSReplacementManager`, `TranslateUtils`, `Voice`
*   **Được sử dụng bởi (Used by)**: `AddWordSheet`, `AppLaunchRootView`, `DictionaryMatchInfo`, `EditWordSheet`, `EditingEntry`, `FreeBookApp`, `Layout`, `LoadedChapter`, `MainTabView`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `ShelfView`, `TTSDictionaryEditView`, `TTSFloatingWidgetView`, `TTSModelManagerView`, `TTSPlayStateReader`, `TTSSettingsView`

---

### 138. TTSModelManagerView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSModelManagerView.swift:3](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPickerPresenter`, `ModelStore`, `NghiTTSClient`, `TTSManager`, `Voice`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 139. TTSParagraph (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:52](../../Sources/Services/TTS/TTSModels.swift#L52)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Hashable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `TTSManager`

---

### 140. TTSPlayStateReader (CLASS)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSPlayStateReader.swift:9](../../Sources/Views/TTSWidget/TTSPlayStateReader.swift#L9)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `TTSManager`
*   **Được sử dụng bởi (Used by)**: `Layout`, `TTSFloatingWidgetView`

---

### 141. TTSReplacementManager (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TTSReplacementManager.swift:16](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift#L16)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `TTSManager`, `TTSReplacementManagerView`

---

### 142. TTSReplacementManagerView (STRUCT)

*   **Định nghĩa tại**: [Views/Settings/TTS/TTSReplacementManagerView.swift:3](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `DocumentPickerPresenter`, `TTSReplacementManager`, `TTSReplacementRule`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `SettingsView`, `TTSSettingsView`

---

### 143. TTSReplacementRule (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TTSReplacementManager.swift:2](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`, `Equatable`
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: `TTSReplacementManagerView`

---

### 144. TTSSettingsView (STRUCT)

*   **Định nghĩa tại**: [Views/TTSWidget/TTSSettingsView.swift:4](../../Sources/Views/TTSWidget/TTSSettingsView.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Extension`, `ExtensionConfigView`, `ExtensionManager`, `ModelStore`, `NghiTTSClient`, `NghiTTSSettingsView`, `TTSDictionaryEditView`, `TTSManager`, `TTSModelManagerView`, `TTSReplacementManagerView`, `Voice`
*   **Được sử dụng bởi (Used by)**: `DictionaryCard`, `Layout`, `SettingsView`, `TTSFloatingWidgetView`

---

### 145. TaskOptionsSheet (STRUCT)

*   **Định nghĩa tại**: [Views/Download/TaskOptionsSheet.swift:3](../../Sources/Views/Download/TaskOptionsSheet.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `View`
*   **Sử dụng (Uses)**: `Book`, `BookCoverView`, `ChapterLimitOption`, `DownloadManager`, `TaskType`, `ToastManager`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DownloadTrackerView`, `ParsedBook`, `ParserChapter`, `ShelfView`

---

### 146. TaskStatus (ENUM)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:33](../../Sources/Services/Download/DownloadManager.swift#L33)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `DownloadTrackerView`

---

### 147. TaskType (ENUM)

*   **Định nghĩa tại**: [Services/Download/DownloadManager.swift:27](../../Sources/Services/Download/DownloadManager.swift#L27)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`, `Identifiable`
*   **Sử dụng (Uses)**: `AppLogger`, `Book`, `Chapter`, `DownloadTaskModel`, `Extension`, `ExtensionManager`, `ToastManager`, `TranslateUtils`
*   **Được sử dụng bởi (Used by)**: `BookDetailView`, `DownloadTrackerView`, `ParsedBook`, `ParserChapter`, `ShelfView`, `TaskOptionsSheet`

---

### 148. TextChunk (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/ONNXPiperEngine.swift:37](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift#L37)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EspeakPhonemizer`, `PiperEngine`, `TTSError`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 149. TextDictionary (CLASS)

*   **Định nghĩa tại**: [Models/Dictionaries/TextDictionary.swift:2](../../Sources/Models/Dictionaries/TextDictionary.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `TrieDictionary`
*   **Sử dụng (Uses)**: `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 150. TextPreprocessor (ACTOR)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:114](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L114)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: `AddWordSheet`, `EditWordSheet`, `EditingEntry`, `ModelsResponse`, `NghiTTSClient`, `PiperEngine`, `PiperTTSService`, `PrefetchResult`, `TTSDictionaryEditView`, `UnavailablePiperEngine`

---

### 151. ToastManager (CLASS)

*   **Định nghĩa tại**: [Common/Services/ToastManager.swift:3](../../Sources/Common/Services/ToastManager.swift#L3)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `ChapterLimitOption`, `DownloadManager`, `DownloadTask`, `FreeBookApp`, `TaskOptionsSheet`, `TaskStatus`, `TaskType`

---

### 152. TranslateUtils (CLASS)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:10](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L10)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `AllCommentsView`, `BookDetailView`, `CategoryNovelsListView`, `CategoryResult`, `ChapterLimitOption`, `ChapterResult`, `ChapterRowInfo`, `CommentSectionView`, `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryCard`, `DictionaryListView`, `DictionaryMatchInfo`, `DiscoveryCategoryTabView`, `DiscoveryView`, `DownloadManager`, `DownloadTask`, `ExtensionManager`, `ExtensionRegistryItem`, `ExtensionSelectorView`, `LoadedChapter`, `NovelDetailResult`, `PageFlipModifier`, `ParagraphTracker`, `ParsedBook`, `ParserChapter`, `ReaderChapterListView`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ReaderViewModel`, `RegistryMetadata`, `RegistryResponse`, `ScrollTarget`, `SearchNovelResult`, `SearchNovelResultWithExt`, `SearchView`, `SettingsView`, `ShareSheet`, `ShelfView`, `SourceSearchState`, `SuggestRowView`, `TTSManager`, `TaskStatus`, `TaskType`, `TranslationManager`

---

### 153. TranslationManager (CLASS)

*   **Định nghĩa tại**: [Services/Translation/Manager/TranslationManager.swift:2](../../Sources/Services/Translation/Manager/TranslationManager.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `DictionaryCache`, `DoubleArrayTrie`, `DoubleArrayTrieBuilder`, `TranslateUtils`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `AppLaunchRootView`, `DictEntry`, `DictEntrySheet`, `DictSheetMode`, `DictType`, `DictionaryCache`, `DictionaryCard`, `DictionaryHubView`, `DictionaryListView`, `DictionaryMatchInfo`, `DictionaryNavRow`, `FreeBookApp`, `LoadedChapter`, `ManageDefinitionsView`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`, `SearchNovelResultWithExt`, `SearchView`, `SentenceRange`, `SettingsView`, `ShareSheet`, `SourceSearchState`, `TOCRule`, `TranslateUtils`, `TranslationWordToken`

---

### 154. TranslationWordToken (STRUCT)

*   **Định nghĩa tại**: [Services/Translation/Utils/TranslateUtils.swift:806](../../Sources/Services/Translation/Utils/TranslateUtils.swift#L806)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: `TranslationManager`, `TrieDictionary`
*   **Được sử dụng bởi (Used by)**: `DictionaryMatchInfo`, `LoadedChapter`, `PageFlipModifier`, `ParagraphTracker`, `ReaderSettingsView`, `ReaderTheme`, `ReaderView`, `ScrollTarget`

---

### 155. TrieDictionary (PROTOCOL)

*   **Định nghĩa tại**: [Models/Dictionaries/DoubleArrayTrie.swift:2](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `SentenceRange`, `TOCRule`, `TextDictionary`, `TranslateUtils`, `TranslationManager`, `TranslationWordToken`

---

### 156. UnavailablePiperEngine (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/NghiTTS/PiperTTSService.swift:67](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift#L67)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `PiperEngine`
*   **Sử dụng (Uses)**: `ModelStore`, `ONNXPiperEngine`, `TTSError`, `TextPreprocessor`, `WAVEncoder`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 157. UnitPatternSpec (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/TextPreprocessor.swift:123](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift#L123)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: `AppLogger`, `EnglishTransliterator`, `JapaneseTransliterator`, `VietnameseNumberSpeller`, `VietnameseWordChecker`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 158. VietnameseNumberSpeller (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/VietnameseNumberSpeller.swift:2](../../Sources/Services/TTS/Preprocessing/VietnameseNumberSpeller.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 159. VietnameseWordChecker (CLASS)

*   **Định nghĩa tại**: [Services/TTS/Preprocessing/VietnameseWordChecker.swift:4](../../Sources/Services/TTS/Preprocessing/VietnameseWordChecker.swift#L4)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `DictionaryType`, `PreprocessorConfig`, `PreprocessorRegex`, `PreprocessorRuntimeConfig`, `PreprocessorSettingKey`, `TextPreprocessor`, `UnitPatternSpec`, `WordToken`

---

### 160. Voice (STRUCT)

*   **Định nghĩa tại**: [Services/TTS/TTSModels.swift:2](../../Sources/Services/TTS/TTSModels.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `Codable`, `Identifiable`, `Hashable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `ModelsResponse`, `NghiTTSClient`, `PrefetchResult`, `TTSManager`, `TTSModelManagerView`, `TTSSettingsView`
*   **Các Extension của kiểu này**:
    *   Tại [Services/TTS/TTSModels.swift:45](../../Sources/Services/TTS/TTSModels.swift#L45)

---

### 161. WAVEncoder (ENUM)

*   **Định nghĩa tại**: [Services/TTS/WAVEncoder.swift:2](../../Sources/Services/TTS/WAVEncoder.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: Không kế thừa hoặc tuân thủ protocol nào
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `AudioConfig`, `CachedSession`, `ONNXPiperEngine`, `PiperConfig`, `PiperEngine`, `PiperTTSService`, `TextChunk`, `UnavailablePiperEngine`

---

### 162. WebViewLoader (CLASS)

*   **Định nghĩa tại**: [Services/Extensions/Engine/JSExecutor.swift:722](../../Sources/Services/Extensions/Engine/JSExecutor.swift#L722)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `NSObject`, `WKNavigationDelegate`
*   **Sử dụng (Uses)**: `AppLogger`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 163. WebViewStore (CLASS)

*   **Định nghĩa tại**: [Views/Common/BypassWebView.swift:573](../../Sources/Views/Common/BypassWebView.swift#L573)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `ObservableObject`
*   **Sử dụng (Uses)**: `Extension`, `JSExecutor`
*   **Được sử dụng bởi (Used by)**: Không được kiểu dữ liệu nội bộ khác tham chiếu trực tiếp

---

### 164. WidgetMode (ENUM)

*   **Định nghĩa tại**: [Views/TTSWidget/WidgetState.swift:2](../../Sources/Views/TTSWidget/WidgetState.swift#L2)
*   **Kế thừa / Tuân thủ (Inherits / Conforms)**: `String`, `Codable`
*   **Sử dụng (Uses)**: Không phụ thuộc vào kiểu dữ liệu nội bộ khác
*   **Được sử dụng bởi (Used by)**: `FloatingWidgetViewModel`

---

### 165. WordToken (STRUCT)

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

<!-- GENERATED END -->