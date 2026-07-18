---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 2
---

# Đồ thị File & Quan hệ Import (File & Import Graph)

Tài liệu này chi tiết hóa toàn bộ các mối quan hệ phụ thuộc giữa 87 file mã nguồn Swift trong dự án FreeBook, tách biệt rõ ràng giữa Import Graph và Dependency Graph cho từng tệp.

## Ghi chú thủ công (Human Notes)
*Đây là khu vực con người tự viết ghi chú, AI không được phép ghi đè.*

<!-- GENERATED START -->
## Reader files added in 1.3.14

* [`ReaderParagraphBuilder.swift`](../../Sources/Views/Reader/ReaderParagraphBuilder.swift) depends on `TranslateUtils` and `ParagraphItem`; it is called by both `ReaderViewModel` and the legacy `ReaderView` loading path.
* [`ReaderSelectionMapper.swift`](../../Sources/Views/Reader/ReaderSelectionMapper.swift) depends on `ParagraphItem`, `TranslationSpan`, and `TranslateUtils`; it is called by `ReaderView` after a custom text-selection action.

## Đánh giá mức độ tin cậy (Confidence Level)

*   **Mức độ tin cậy**: **High**
*   **Lý do**: Được trích xuất hoàn toàn tự động thông qua việc phân tích từ khóa kiểu dữ liệu khớp chính xác trên cây thư mục nguồn.

---

## Chi tiết Quan hệ cho từng File (Tổng cộng 86 Files)

### 1. [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)

*   **Đường dẫn**: `App/FreeBookApp.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ToastManager.swift](../../Sources/Common/Services/ToastManager.swift)
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [DownloadTaskModel.swift](../../Sources/Models/Database/DownloadTaskModel.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [Repository.swift](../../Sources/Models/Database/Repository.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [AppLoadingView.swift](../../Sources/Views/AppLoadingView.swift)
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 1. [String+Crypto.swift](../../Sources/Common/Extensions/String+Crypto.swift)

*   **Đường dẫn**: `Common/Extensions/String+Crypto.swift`
*   **Imports (Import Graph)**: `CryptoKit`, `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 2. [String+HTML.swift](../../Sources/Common/Extensions/String+HTML.swift)

*   **Đường dẫn**: `Common/Extensions/String+HTML.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 3. [View+Keyboard.swift](../../Sources/Common/Extensions/View+Keyboard.swift)

*   **Đường dẫn**: `Common/Extensions/View+Keyboard.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 4. [ImageCacheManager.swift](../../Sources/Common/Services/ImageCacheManager.swift)

*   **Đường dẫn**: `Common/Services/ImageCacheManager.swift`
*   **Imports (Import Graph)**: `Foundation`, `UIKit`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)

---

### 5. [ToastManager.swift](../../Sources/Common/Services/ToastManager.swift)

*   **Đường dẫn**: `Common/Services/ToastManager.swift`
*   **Imports (Import Graph)**: `Combine`, `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)

---

### 6. [Book.swift](../../Sources/Models/Database/Book.swift)

*   **Đường dẫn**: `Models/Database/Book.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`
*   **Sử dụng (Uses)**:
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DownloadTrackerView.swift](../../Sources/Views/Download/DownloadTrackerView.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)
    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [ReadingProgressStore.swift](../../Sources/Services/ReadingProgress/ReadingProgressStore.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 7. [Chapter.swift](../../Sources/Models/Database/Chapter.swift)

*   **Đường dẫn**: `Models/Database/Chapter.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 8. [DownloadTaskModel.swift](../../Sources/Models/Database/DownloadTaskModel.swift)

*   **Đường dẫn**: `Models/Database/DownloadTaskModel.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)

---

### 9. [Extension.swift](../../Sources/Models/Database/Extension.swift)

*   **Đường dẫn**: `Models/Database/Extension.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`
*   **Sử dụng (Uses)**:
    *   [Repository.swift](../../Sources/Models/Database/Repository.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [Repository.swift](../../Sources/Models/Database/Repository.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [ExtensionConfigView.swift](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift)
    *   [RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift)
    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 10. [Repository.swift](../../Sources/Models/Database/Repository.swift)

*   **Đường dẫn**: `Models/Database/Repository.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`
*   **Sử dụng (Uses)**:
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift)

---

### 11. [DoubleArrayTrie.swift](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift)

*   **Đường dẫn**: `Models/Dictionaries/DoubleArrayTrie.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TextDictionary.swift](../../Sources/Models/Dictionaries/TextDictionary.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)

---

### 12. [DoubleArrayTrieBuilder.swift](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift)

*   **Đường dẫn**: `Models/Dictionaries/DoubleArrayTrieBuilder.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)

---

### 13. [SearchEngine.swift](../../Sources/Models/Dictionaries/SearchEngine.swift)

*   **Đường dẫn**: `Models/Dictionaries/SearchEngine.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [SearchEnginesConfigView.swift](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift)

---

### 14. [TextDictionary.swift](../../Sources/Models/Dictionaries/TextDictionary.swift)

*   **Đường dẫn**: `Models/Dictionaries/TextDictionary.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [DoubleArrayTrie.swift](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift)
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 15. [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)

*   **Đường dẫn**: `Services/Download/DownloadManager.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`, `UIKit`
*   **Sử dụng (Uses)**:
    *   [ToastManager.swift](../../Sources/Common/Services/ToastManager.swift)
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [DownloadTaskModel.swift](../../Sources/Models/Database/DownloadTaskModel.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DownloadTrackerView.swift](../../Sources/Views/Download/DownloadTrackerView.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 16. [JSCrypto.swift](../../Sources/Services/Extensions/Engine/JSCrypto.swift)

*   **Đường dẫn**: `Services/Extensions/Engine/JSCrypto.swift`
*   **Imports (Import Graph)**: `CryptoKit`, `Foundation`, `JavaScriptCore`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 17. [JSDom.swift](../../Sources/Services/Extensions/Engine/JSDom.swift)

*   **Đường dẫn**: `Services/Extensions/Engine/JSDom.swift`
*   **Imports (Import Graph)**: `Foundation`, `JavaScriptCore`, `SwiftSoup`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**: Không được tham chiếu trực tiếp từ file khác

---

### 18. [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift)

*   **Đường dẫn**: `Services/Extensions/Engine/JSExecutor.swift`
*   **Imports (Import Graph)**: `Foundation`, `JavaScriptCore`, `WebKit`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)

---

### 19. [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)

*   **Đường dẫn**: `Services/Extensions/Manager/ExtensionManager.swift`
*   **Imports (Import Graph)**: `Combine`, `Foundation`, `JavaScriptCore`, `ZIPFoundation`
*   **Sử dụng (Uses)**:
    *   [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [ExtTTSService.swift](../../Sources/Services/TTS/Ext/ExtTTSService.swift)
    *   [AllCommentsView.swift](../../Sources/Views/BookDetail/AllCommentsView.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [CommentSectionView.swift](../../Sources/Views/BookDetail/CommentSectionView.swift)
    *   [SuggestRowView.swift](../../Sources/Views/BookDetail/SuggestRowView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift)    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 20. [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)

*   **Đường dẫn**: `Services/Logging/AppLogger.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [ImageCacheManager.swift](../../Sources/Common/Services/ImageCacheManager.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [BackgroundTaskSession.swift](../../Sources/Services/TTS/BackgroundTaskSession.swift)
    *   [EspeakPhonemizer.swift](../../Sources/Services/TTS/EspeakPhonemizer.swift)
    *   [ExtTTSService.swift](../../Sources/Services/TTS/Ext/ExtTTSService.swift)
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)
    *   [TTSReplacementManager.swift](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift)
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [AllCommentsView.swift](../../Sources/Views/BookDetail/AllCommentsView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [ChapterCache.swift](../../Sources/Views/Reader/ChapterCache.swift)
    *   [PrefetchManager.swift](../../Sources/Views/Reader/PrefetchManager.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [ReadingProgressStore.swift](../../Sources/Services/ReadingProgress/ReadingProgressStore.swift)
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 21. [BackgroundTaskSession.swift](../../Sources/Services/TTS/BackgroundTaskSession.swift)

*   **Đường dẫn**: `Services/TTS/BackgroundTaskSession.swift`
*   **Imports (Import Graph)**: `Foundation`, `UIKit`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)

---

### 22. [EspeakPhonemizer.swift](../../Sources/Services/TTS/EspeakPhonemizer.swift)

*   **Đường dẫn**: `Services/TTS/EspeakPhonemizer.swift`
*   **Imports (Import Graph)**: `Foundation`, `libespeak_ng`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)

---

### 23. [ExtTTSService.swift](../../Sources/Services/TTS/Ext/ExtTTSService.swift)

*   **Đường dẫn**: `Services/TTS/Ext/ExtTTSService.swift`
*   **Imports (Import Graph)**: `AVFoundation`, `Foundation`
*   **Sử dụng (Uses)**:
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)

---

### 24. [ModelStore.swift](../../Sources/Services/TTS/NghiTTS/ModelStore.swift)

*   **Đường dẫn**: `Services/TTS/NghiTTS/ModelStore.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 25. [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)

*   **Đường dẫn**: `Services/TTS/NghiTTS/NghiTTSClient.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [BackgroundTaskSession.swift](../../Sources/Services/TTS/BackgroundTaskSession.swift)
    *   [ModelStore.swift](../../Sources/Services/TTS/NghiTTS/ModelStore.swift)
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 26. [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)

*   **Đường dẫn**: `Services/TTS/NghiTTS/ONNXPiperEngine.swift`
*   **Imports (Import Graph)**: `Foundation`, `OnnxRuntimeBindings`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [EspeakPhonemizer.swift](../../Sources/Services/TTS/EspeakPhonemizer.swift)
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
    *   [WAVEncoder.swift](../../Sources/Services/TTS/WAVEncoder.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)

---

### 27. [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)

*   **Đường dẫn**: `Services/TTS/NghiTTS/PiperTTSService.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [ModelStore.swift](../../Sources/Services/TTS/NghiTTS/ModelStore.swift)
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
    *   [WAVEncoder.swift](../../Sources/Services/TTS/WAVEncoder.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)

---

### 28. [EnglishTransliterator.swift](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/EnglishTransliterator.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [RegexRule.swift](../../Sources/Services/TTS/Preprocessing/RegexRule.swift)
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)

---

### 29. [JapaneseTransliterator.swift](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/JapaneseTransliterator.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)

---

### 30. [RegexRule.swift](../../Sources/Services/TTS/Preprocessing/RegexRule.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/RegexRule.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [EnglishTransliterator.swift](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift)

---

### 31. [TTSReplacementManager.swift](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/TTSReplacementManager.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift)

---

### 32. [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/TextPreprocessor.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [EnglishTransliterator.swift](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift)
    *   [JapaneseTransliterator.swift](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift)
    *   [VietnameseNumberSpeller.swift](../../Sources/Services/TTS/Preprocessing/VietnameseNumberSpeller.swift)
    *   [VietnameseWordChecker.swift](../../Sources/Services/TTS/Preprocessing/VietnameseWordChecker.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)
    *   [EnglishTransliterator.swift](../../Sources/Services/TTS/Preprocessing/EnglishTransliterator.swift)
    *   [JapaneseTransliterator.swift](../../Sources/Services/TTS/Preprocessing/JapaneseTransliterator.swift)
    *   [NghiTTSSettingsView.swift](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift)
    *   [TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift)

---

### 33. [VietnameseNumberSpeller.swift](../../Sources/Services/TTS/Preprocessing/VietnameseNumberSpeller.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/VietnameseNumberSpeller.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)

---

### 34. [VietnameseWordChecker.swift](../../Sources/Services/TTS/Preprocessing/VietnameseWordChecker.swift)

*   **Đường dẫn**: `Services/TTS/Preprocessing/VietnameseWordChecker.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)

---

### 35. [SiriTTSService.swift](../../Sources/Services/TTS/Siri/SiriTTSService.swift)

*   **Đường dẫn**: `Services/TTS/Siri/SiriTTSService.swift`
*   **Imports (Import Graph)**: `AVFoundation`, `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)

---

### 36. [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)

*   **Đường dẫn**: `Services/TTS/TTSManager.swift`
*   **Imports (Import Graph)**: `AVFoundation`, `Combine`, `Foundation`, `MediaPlayer`, `QuartzCore`, `SwiftData`, `UIKit`
*   **Sử dụng (Uses)**:
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [ImageCacheManager.swift](../../Sources/Common/Services/ImageCacheManager.swift)
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [ExtTTSService.swift](../../Sources/Services/TTS/Ext/ExtTTSService.swift)
    *   [ModelStore.swift](../../Sources/Services/TTS/NghiTTS/ModelStore.swift)
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)
    *   [TTSReplacementManager.swift](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift)
    *   [SiriTTSService.swift](../../Sources/Services/TTS/Siri/SiriTTSService.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)
    *   [TTSPlayStateReader.swift](../../Sources/Views/TTSWidget/TTSPlayStateReader.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 37. [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)

*   **Đường dẫn**: `Services/TTS/TTSModels.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [EspeakPhonemizer.swift](../../Sources/Services/TTS/EspeakPhonemizer.swift)
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 38. [WAVEncoder.swift](../../Sources/Services/TTS/WAVEncoder.swift)

*   **Đường dẫn**: `Services/TTS/WAVEncoder.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [ONNXPiperEngine.swift](../../Sources/Services/TTS/NghiTTS/ONNXPiperEngine.swift)
    *   [PiperTTSService.swift](../../Sources/Services/TTS/NghiTTS/PiperTTSService.swift)

---

### 39. [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)

*   **Đường dẫn**: `Services/Translation/Manager/TranslationManager.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [DoubleArrayTrie.swift](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift)
    *   [DoubleArrayTrieBuilder.swift](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [DictionaryHubView.swift](../../Sources/Views/Dictionary/DictionaryHubView.swift)
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)
    *   [ManageDefinitionsView.swift](../../Sources/Views/Dictionary/ManageDefinitionsView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)

---

### 40. [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)

*   **Đường dẫn**: `Services/Translation/Utils/DictionaryCache.swift`
*   **Imports (Import Graph)**: `Combine`, `Foundation`
*   **Sử dụng (Uses)**:
    *   [DoubleArrayTrie.swift](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift)
    *   [DoubleArrayTrieBuilder.swift](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryHubView.swift](../../Sources/Views/Dictionary/DictionaryHubView.swift)
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)

---

### 41. [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)

*   **Đường dẫn**: `Services/Translation/Utils/TranslateUtils.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [DoubleArrayTrie.swift](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [AllCommentsView.swift](../../Sources/Views/BookDetail/AllCommentsView.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [CommentSectionView.swift](../../Sources/Views/BookDetail/CommentSectionView.swift)
    *   [SuggestRowView.swift](../../Sources/Views/BookDetail/SuggestRowView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 42. [AppLoadingView.swift](../../Sources/Views/AppLoadingView.swift)

*   **Đường dẫn**: `Views/AppLoadingView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)

---

### 43. [AllCommentsView.swift](../../Sources/Views/BookDetail/AllCommentsView.swift)

*   **Đường dẫn**: `Views/BookDetail/AllCommentsView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [CommentSectionView.swift](../../Sources/Views/BookDetail/CommentSectionView.swift)

---

### 44. [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)

*   **Đường dẫn**: `Views/BookDetail/BookDetailView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [CommentSectionView.swift](../../Sources/Views/BookDetail/CommentSectionView.swift)
    *   [SuggestRowView.swift](../../Sources/Views/BookDetail/SuggestRowView.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [ExtensionIconView.swift](../../Sources/Views/Common/ExtensionIconView.swift)
    *   [SkeletonView.swift](../../Sources/Views/Common/SkeletonView.swift)
    *   [BookDictionaryView.swift](../../Sources/Views/Dictionary/BookDictionaryView.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SuggestRowView.swift](../../Sources/Views/BookDetail/SuggestRowView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 45. [CommentSectionView.swift](../../Sources/Views/BookDetail/CommentSectionView.swift)

*   **Đường dẫn**: `Views/BookDetail/CommentSectionView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [AllCommentsView.swift](../../Sources/Views/BookDetail/AllCommentsView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)

---

### 46. [SuggestRowView.swift](../../Sources/Views/BookDetail/SuggestRowView.swift)

*   **Đường dẫn**: `Views/BookDetail/SuggestRowView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)

---

### 47. [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)

*   **Đường dẫn**: `Views/Common/BookCoverView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ImageCacheManager.swift](../../Sources/Common/Services/ImageCacheManager.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [SuggestRowView.swift](../../Sources/Views/BookDetail/SuggestRowView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [DownloadTrackerView.swift](../../Sources/Views/Download/DownloadTrackerView.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 48. [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)

*   **Đường dẫn**: `Views/Common/BypassWebView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`, `WebKit`
*   **Sử dụng (Uses)**:
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [JSExecutor.swift](../../Sources/Services/Extensions/Engine/JSExecutor.swift)
    *   [ReaderTextView.swift](../../Sources/Views/Reader/ReaderTextView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 49. [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)

*   **Đường dẫn**: `Views/Common/CategoryNovelsListView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)

---

### 50. [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)

*   **Đường dẫn**: `Views/Common/DocumentPicker.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UIKit`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [ReaderTextView.swift](../../Sources/Views/Reader/ReaderTextView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 51. [ExtensionIconView.swift](../../Sources/Views/Common/ExtensionIconView.swift)

*   **Đường dẫn**: `Views/Common/ExtensionIconView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)

---

### 52. [SkeletonView.swift](../../Sources/Views/Common/SkeletonView.swift)

*   **Đường dẫn**: `Views/Common/SkeletonView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)

---

### 53. [BookDictionaryView.swift](../../Sources/Views/Dictionary/BookDictionaryView.swift)

*   **Đường dẫn**: `Views/Dictionary/BookDictionaryView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [DictionaryHubView.swift](../../Sources/Views/Dictionary/DictionaryHubView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)

---

### 54. [DictionaryHubView.swift](../../Sources/Views/Dictionary/DictionaryHubView.swift)

*   **Đường dẫn**: `Views/Dictionary/DictionaryHubView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDictionaryView.swift](../../Sources/Views/Dictionary/BookDictionaryView.swift)

---

### 55. [DictionaryListView.swift](../../Sources/Views/Dictionary/DictionaryListView.swift)

*   **Đường dẫn**: `Views/Dictionary/DictionaryListView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [DoubleArrayTrie.swift](../../Sources/Models/Dictionaries/DoubleArrayTrie.swift)
    *   [DoubleArrayTrieBuilder.swift](../../Sources/Models/Dictionaries/DoubleArrayTrieBuilder.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [DictionaryHubView.swift](../../Sources/Views/Dictionary/DictionaryHubView.swift)

---

### 56. [ManageDefinitionsView.swift](../../Sources/Views/Dictionary/ManageDefinitionsView.swift)

*   **Đường dẫn**: `Views/Dictionary/ManageDefinitionsView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)

---

### 57. [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)

*   **Đường dẫn**: `Views/Discovery/DiscoveryView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)
    *   [CategoryNovelsListView.swift](../../Sources/Views/Common/CategoryNovelsListView.swift)
    *   [ExtensionIconView.swift](../../Sources/Views/Common/ExtensionIconView.swift)
    *   [ExtensionConfigView.swift](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift)
    *   [SearchView.swift](../../Sources/Views/Search/SearchView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)

---

### 58. [DownloadTrackerView.swift](../../Sources/Views/Download/DownloadTrackerView.swift)

*   **Đường dẫn**: `Views/Download/DownloadTrackerView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 59. [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)

*   **Đường dẫn**: `Views/Download/TaskOptionsSheet.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ToastManager.swift](../../Sources/Common/Services/ToastManager.swift)
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DownloadTrackerView.swift](../../Sources/Views/Download/DownloadTrackerView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 60. [ExtensionConfigView.swift](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift)

*   **Đường dẫn**: `Views/Extensions/Config/ExtensionConfigView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 61. [RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift)

*   **Đường dẫn**: `Views/Extensions/Manager/RepositoryManagerView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [Repository.swift](../../Sources/Models/Database/Repository.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [ExtensionConfigView.swift](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift)*   **Được sử dụng bởi (Used by)**:
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)

---

### 62. [MainTabView.swift](../../Sources/Views/MainTabView.swift)

*   **Đường dẫn**: `Views/MainTabView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)
    *   [RepositoryManagerView.swift](../../Sources/Views/Extensions/Manager/RepositoryManagerView.swift)
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)

---

### 63. [ChapterCache.swift](../../Sources/Views/Reader/ChapterCache.swift)

*   **Đường dẫn**: `Views/Reader/ChapterCache.swift`
*   **Imports (Import Graph)**: `Observation`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [ParagraphCardView.swift](../../Sources/Views/Reader/ParagraphCardView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
    *   [ReadingProgressStore.swift](../../Sources/Services/ReadingProgress/ReadingProgressStore.swift)

---

### 64. [CollapsedCircleView.swift](../../Sources/Views/Reader/CollapsedCircleView.swift)

*   **Đường dẫn**: `Views/Reader/CollapsedCircleView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)

---

### 65. [ExpandedControlPanel.swift](../../Sources/Views/Reader/ExpandedControlPanel.swift)

*   **Đường dẫn**: `Views/Reader/ExpandedControlPanel.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)

---

### 66. [ParagraphCardView.swift](../../Sources/Views/Reader/ParagraphCardView.swift)

*   **Đường dẫn**: `Views/Reader/ParagraphCardView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [ReaderTextView.swift](../../Sources/Views/Reader/ReaderTextView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ChapterCache.swift](../../Sources/Views/Reader/ChapterCache.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)

---

### 67. [PrefetchManager.swift](../../Sources/Views/Reader/PrefetchManager.swift)

*   **Đường dẫn**: `Views/Reader/PrefetchManager.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)

---

### 68. [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)

*   **Đường dẫn**: `Views/Reader/ReaderChapterListView.swift`
*   **Imports (Import Graph)**: `Observation`, `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)

---

### 69. [ReaderTextView.swift](../../Sources/Views/Reader/ReaderTextView.swift)

*   **Đường dẫn**: `Views/Reader/ReaderTextView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UIKit`
*   **Sử dụng (Uses)**:
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
    *   [ParagraphCardView.swift](../../Sources/Views/Reader/ParagraphCardView.swift)

---

### 70. [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)

*   **Đường dẫn**: `Views/Reader/ReaderView.swift`
*   **Imports (Import Graph)**: `AVFoundation`, `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [SearchEngine.swift](../../Sources/Models/Dictionaries/SearchEngine.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)
    *   [BookDictionaryView.swift](../../Sources/Views/Dictionary/BookDictionaryView.swift)
    *   [ManageDefinitionsView.swift](../../Sources/Views/Dictionary/ManageDefinitionsView.swift)
    *   [ChapterCache.swift](../../Sources/Views/Reader/ChapterCache.swift)
    *   [ParagraphCardView.swift](../../Sources/Views/Reader/ParagraphCardView.swift)
    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [ManageDefinitionsView.swift](../../Sources/Views/Dictionary/ManageDefinitionsView.swift)
    *   [ParagraphCardView.swift](../../Sources/Views/Reader/ParagraphCardView.swift)
    *   [ReaderChapterListView.swift](../../Sources/Views/Reader/ReaderChapterListView.swift)
    *   [ReaderTextView.swift](../../Sources/Views/Reader/ReaderTextView.swift)
    *   [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

---

### 71. [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)

*   **Đường dẫn**: `Views/Reader/ReaderViewModel.swift`
*   **Imports (Import Graph)**: `Combine`, `Observation`, `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [ChapterCache.swift](../../Sources/Views/Reader/ChapterCache.swift)
    *   [ParagraphCardView.swift](../../Sources/Views/Reader/ParagraphCardView.swift)
    *   [PrefetchManager.swift](../../Sources/Views/Reader/PrefetchManager.swift)
    *   [ReadingProgressStore.swift](../../Sources/Services/ReadingProgress/ReadingProgressStore.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)

---

### 72. [ReadingProgressStore.swift](../../Sources/Services/ReadingProgress/ReadingProgressStore.swift)

*   **Đường dẫn**: `Services/ReadingProgress/ReadingProgressStore.swift`
*   **Imports (Import Graph)**: `Foundation`, `SwiftData`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [ChapterCache.swift](../../Sources/Views/Reader/ChapterCache.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [ReaderViewModel.swift](../../Sources/Views/Reader/ReaderViewModel.swift)

---

### 73. [SearchView.swift](../../Sources/Views/Search/SearchView.swift)

*   **Đường dẫn**: `Views/Search/SearchView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [DiscoveryView.swift](../../Sources/Views/Discovery/DiscoveryView.swift)

---

### 74. [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)

*   **Đường dẫn**: `Views/Settings/Main/SettingsView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TranslationManager.swift](../../Sources/Services/Translation/Manager/TranslationManager.swift)
    *   [DictionaryCache.swift](../../Sources/Services/Translation/Utils/DictionaryCache.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
    *   [SearchEnginesConfigView.swift](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift)
    *   [NghiTTSSettingsView.swift](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift)
    *   [TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)

---

### 75. [SearchEnginesConfigView.swift](../../Sources/Views/Settings/Search/SearchEnginesConfigView.swift)

*   **Đường dẫn**: `Views/Settings/Search/SearchEnginesConfigView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [SearchEngine.swift](../../Sources/Models/Dictionaries/SearchEngine.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)

---

### 76. [NghiTTSSettingsView.swift](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift)

*   **Đường dẫn**: `Views/Settings/TTS/NghiTTSSettingsView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 77. [TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift)

*   **Đường dẫn**: `Views/Settings/TTS/TTSDictionaryEditView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [TextPreprocessor.swift](../../Sources/Services/TTS/Preprocessing/TextPreprocessor.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 78. [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)

*   **Đường dẫn**: `Views/Settings/TTS/TTSModelManagerView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [ModelStore.swift](../../Sources/Services/TTS/NghiTTS/ModelStore.swift)
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 79. [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift)

*   **Đường dẫn**: `Views/Settings/TTS/TTSReplacementManagerView.swift`
*   **Imports (Import Graph)**: `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [TTSReplacementManager.swift](../../Sources/Services/TTS/Preprocessing/TTSReplacementManager.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

---

### 80. [ShelfView.swift](../../Sources/Views/Shelf/ShelfMain/ShelfView.swift)

*   **Đường dẫn**: `Views/Shelf/ShelfMain/ShelfView.swift`
*   **Imports (Import Graph)**: `SwiftData`, `SwiftUI`, `UniformTypeIdentifiers`
*   **Sử dụng (Uses)**:
    *   [Book.swift](../../Sources/Models/Database/Book.swift)
    *   [Chapter.swift](../../Sources/Models/Database/Chapter.swift)
    *   [DownloadManager.swift](../../Sources/Services/Download/DownloadManager.swift)
    *   [AppLogger.swift](../../Sources/Services/Logging/AppLogger.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TranslateUtils.swift](../../Sources/Services/Translation/Utils/TranslateUtils.swift)
    *   [BookDetailView.swift](../../Sources/Views/BookDetail/BookDetailView.swift)
    *   [BookCoverView.swift](../../Sources/Views/Common/BookCoverView.swift)
    *   [BypassWebView.swift](../../Sources/Views/Common/BypassWebView.swift)
    *   [DocumentPicker.swift](../../Sources/Views/Common/DocumentPicker.swift)
    *   [DownloadTrackerView.swift](../../Sources/Views/Download/DownloadTrackerView.swift)
    *   [TaskOptionsSheet.swift](../../Sources/Views/Download/TaskOptionsSheet.swift)
    *   [ReaderView.swift](../../Sources/Views/Reader/ReaderView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [MainTabView.swift](../../Sources/Views/MainTabView.swift)

---

### 81. [FloatingWidgetViewModel.swift](../../Sources/Views/TTSWidget/FloatingWidgetViewModel.swift)

*   **Đường dẫn**: `Views/TTSWidget/FloatingWidgetViewModel.swift`
*   **Imports (Import Graph)**: `Combine`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [WidgetState.swift](../../Sources/Views/TTSWidget/WidgetState.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)

---

### 82. [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)

*   **Đường dẫn**: `Views/TTSWidget/TTSFloatingWidgetView.swift`
*   **Imports (Import Graph)**: `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [CollapsedCircleView.swift](../../Sources/Views/Reader/CollapsedCircleView.swift)
    *   [ExpandedControlPanel.swift](../../Sources/Views/Reader/ExpandedControlPanel.swift)
    *   [FloatingWidgetViewModel.swift](../../Sources/Views/TTSWidget/FloatingWidgetViewModel.swift)
    *   [TTSPlayStateReader.swift](../../Sources/Views/TTSWidget/TTSPlayStateReader.swift)
    *   [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [FreeBookApp.swift](../../Sources/App/FreeBookApp.swift)

---

### 83. [TTSPlayStateReader.swift](../../Sources/Views/TTSWidget/TTSPlayStateReader.swift)

*   **Đường dẫn**: `Views/TTSWidget/TTSPlayStateReader.swift`
*   **Imports (Import Graph)**: `Combine`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)

---

### 84. [TTSSettingsView.swift](../../Sources/Views/TTSWidget/TTSSettingsView.swift)

*   **Đường dẫn**: `Views/TTSWidget/TTSSettingsView.swift`
*   **Imports (Import Graph)**: `AVFoundation`, `SwiftData`, `SwiftUI`
*   **Sử dụng (Uses)**:
    *   [Extension.swift](../../Sources/Models/Database/Extension.swift)
    *   [ExtensionManager.swift](../../Sources/Services/Extensions/Manager/ExtensionManager.swift)
    *   [ModelStore.swift](../../Sources/Services/TTS/NghiTTS/ModelStore.swift)
    *   [NghiTTSClient.swift](../../Sources/Services/TTS/NghiTTS/NghiTTSClient.swift)
    *   [TTSManager.swift](../../Sources/Services/TTS/TTSManager.swift)
    *   [TTSModels.swift](../../Sources/Services/TTS/TTSModels.swift)
    *   [ExtensionConfigView.swift](../../Sources/Views/Extensions/Config/ExtensionConfigView.swift)
    *   [NghiTTSSettingsView.swift](../../Sources/Views/Settings/TTS/NghiTTSSettingsView.swift)
    *   [TTSDictionaryEditView.swift](../../Sources/Views/Settings/TTS/TTSDictionaryEditView.swift)
    *   [TTSModelManagerView.swift](../../Sources/Views/Settings/TTS/TTSModelManagerView.swift)
    *   [TTSReplacementManagerView.swift](../../Sources/Views/Settings/TTS/TTSReplacementManagerView.swift)
*   **Được sử dụng bởi (Used by)**:
    *   [SettingsView.swift](../../Sources/Views/Settings/Main/SettingsView.swift)
    *   [TTSFloatingWidgetView.swift](../../Sources/Views/TTSWidget/TTSFloatingWidgetView.swift)

---

### 85. [WidgetState.swift](../../Sources/Views/TTSWidget/WidgetState.swift)

*   **Đường dẫn**: `Views/TTSWidget/WidgetState.swift`
*   **Imports (Import Graph)**: `Foundation`
*   **Sử dụng (Uses)**: Không phụ thuộc trực tiếp vào file nội bộ nào khác
*   **Được sử dụng bởi (Used by)**:
    *   [FloatingWidgetViewModel.swift](../../Sources/Views/TTSWidget/FloatingWidgetViewModel.swift)

---


#### Reader/TTS unified pipeline (2026-07)

- `ChapterTextNormalizer` is the single source for LF newlines, trimmed non-empty lines, compact paragraph IDs, and UTF-16 ranges. `ChapterContentRepository` produces one normalized `ChapterDocument` for both Reader and TTS.
- Reader uses `ReaderLoadState` with bootstrap retry/clamping, typed failures, generation checks, cache-first rendering, and a short opacity crossfade only for newly fetched content. `ReaderRoute.chapterIndex` preserves the selected TOC index through navigation.
- `TTSParagraphBuilder` chunks normalized lines without renumbering parent paragraph IDs; replacement output is checked before synthesis. TTS asynchronous work is guarded by session identity and TTS owns progress while playing.
- `ReadingProgressStore` coalesces RAM snapshots in an actor and flushes from background contexts on checkpoints, dismissal, and app backgrounding. Legacy window/tab Reader, duplicate progress repository, and `TTSSession` mirror are removed.
- Compile recovery splits `DictionaryMatchInfo`, `ReaderSettingsView`, and `ReaderViewModelObserver` into standalone source files so Dictionary and Reader consumers share visible module-level declarations after legacy Reader removal.

<!-- GENERATED END -->
