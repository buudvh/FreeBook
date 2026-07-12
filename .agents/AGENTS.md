# FreeBook - Project Rules

This document defines coding guidelines, runtime specifications, and constraints for developers and agentic models working on the **FreeBook** codebase.

## Codebase Guidelines & Swift Architecture

### 1. Persistence & SwiftData Queries
- **Constraint:** Avoid using SwiftData `#Predicate` filters on string properties (e.g., `!localPath.isEmpty`) in SwiftUI `@Query` declarations. SwiftData's SQLite query compiler has translation bugs that may fail to filter correctly.
- **Rule:** Query the complete list and filter in memory using a computed property:
  ```swift
  @Query private var allExtensions: [Extension]
  private var activeExtensions: [Extension] {
      allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
  }
  ```

### 2. Extension Registry & Installation URL
- The `Extension` model includes a `downloadUrl` property.
- When syncing repository files (`RepositoryManagerView.swift`), save the raw `path` from `plugin.json` directly into `downloadUrl` to ensure correct package downloads.
- Do not use hardcoded string replacements to generate zip URLs.

### 3. Codebase File & Folder Organization (Common, Views, Services, Models)
- **Rule:** Maintain the following directory structure for codebase integrity:
  - **Common (`Sources/Common`)**: Chứa các thành phần dùng chung cho toàn dự án.
    - `Extensions/`: Các phần mở rộng (Extensions/Helpers) dùng chung (`String+HTML.swift`, `View+Keyboard.swift`, `String+Crypto.swift`...).
    - `Services/`: Các Service/Manager dùng chung cho toàn bộ ứng dụng (`ImageCacheManager.swift`, `ToastManager.swift`...).
  - **Models (`Sources/Models`)**:
    - `Database/`: All SwiftData persistable model classes (`Book`, `Chapter`, `Extension`, `Repository`).
    - `Dictionaries/`: All translation lookup data structure classes (`DoubleArrayTrie`, `TextDictionary`, `SearchEngine`).
  - **Views (`Sources/Views`)**: Tổ chức thành các thư mục con theo module chức năng độc lập:
    - `Shelf/ShelfMain/`: Chỉ chứa kệ sách chính (`ShelfView.swift`).
    - `Discovery/`: Tab Khám phá (`DiscoveryView.swift`).
    - `BookDetail/`: Chi tiết sách (`BookDetailView.swift`).
    - `Search/`: Tìm kiếm truyện (`SearchView.swift`).
    - `Reader/`: Trình đọc truyện (`ReaderView.swift` và các view phụ trợ).
    - `TTSWidget/`: Floating widget điều khiển giọng đọc trên trình đọc.
    - `Dictionary/`: Tra cứu từ điển (`DictionaryHubView.swift`, `DictionaryListView.swift`...).
    - `Download/`: Quản lý tiến trình tải sách (`DownloadTrackerView.swift`, `TaskOptionsSheet.swift`).
    - `Extensions/`: Quản lý extension, chia làm các thư mục con `Config/`, `Store/`, `Manager/`.
    - `Settings/`: Cấu hình hệ thống, chia làm các thư mục con `Main/`, `Search/`, `TTS/`.
    - `Common/`: Các view phụ trợ dùng chung (`BypassWebView.swift`, `DocumentPicker.swift`, `BookCoverView.swift`...).
  - **Services (`Sources/Services`)**: Tổ chức thành các thư mục con theo mảng dịch vụ chức năng:
    - `TTS/`: Dịch vụ phát âm TTS.
      - Thư mục gốc `TTS/`: Các bộ điều khiển và định nghĩa dùng chung (`TTSManager.swift`, `EspeakPhonemizer.swift`, `WAVEncoder`...) và thư mục `Preprocessing/`.
      - `NghiTTS/`: Chứa client NghiTTS và lõi Piper offline (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `ModelStore.swift`).
      - `Siri/`: Chứa dịch vụ phát âm native Siri (`SiriTTSService.swift`).
      - `Ext/`: Chứa dịch vụ phát âm qua Extension JS (`ExtTTSService.swift`).
    - `Extensions/`: Engine chạy extension javascript.
      - `Engine/`: Core thực thi JS (`JSExecutor.swift`, `JSDom.swift`, `JSCrypto.swift`).
      - `Manager/`: `ExtensionManager.swift`.
    - `Translation/`: Dịch thuật tự động.
      - `Manager/`: `TranslationManager.swift`.
      - `Utils/`: `TranslateUtils.swift`, `DictionaryCache.swift`.
    - `Download/`: `DownloadManager.swift`.
    - `Logging/`: `AppLogger.swift`.

---

## JavaScript Core Runtime & VBook Extensions Integration

### 1. Script Entrypoint
- All JavaScript extensions are structured as isolated modules.
- **Rule:** The entry point function inside ALL script files (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) is named `execute(...)`. Always invoke `"execute"` via `runAsync` in `ExtensionManager.swift`.

### 2. Script File Path Resolution
- Scripts may be stored in the root folder of the extension package or inside a `src/` subdirectory.
- `ExtensionManager.swift`'s `getScriptPath` is configured to search both the root folder and the `src/` subfolder. Respect this fallback search sequence.

### 3. Injected Global JS Objects
The `JSExecutor` injects the following global namespaces/functions into the `JSContext`:
- `Html`: Dom parser bridge (`Html.parse(...)`).
- `console`: Redirects `console.log(...)` to Xcode print logs.
- `fetch`: Asynchronous Promise-based fetch API.
- `Response`: Global response helper namespace:
  - `Response.success(data)` returns the raw data directly.
  - `Response.error(message)` throws an Error.
- `Engine`: Simulates a synchronous headless browser:
  - `Engine.newBrowser()` returns a mocked `Browser` instance supporting `.launch(url, timeout)` (sync network request), `.html()`, and `.close()`.

### 4. Logging & Diagnostics
- **Environment Constraint:** The primary developer does not own a Mac. The application is built using GitHub Actions (CI) and installed on a physical iOS device inside **LiveContainer** to be run. Direct Xcode console attachment is unavailable.
- **Rule:** Write all runtime logs to a file named `app_logs.txt` inside the app's `Documents/` directory using the `AppLogger` utility. This allows logs to be read directly on the device or exported.
- Log all JS exception details including `desc`, `line`, `column`, and `stack` (JS Stacktrace) into both standard output and `app_logs.txt`.
- Keep detailed trace logs of inputs, JS outputs, and parser results in `ExtensionManager` actions to ensure traceability during debugging.
