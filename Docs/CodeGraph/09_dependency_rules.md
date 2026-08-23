---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 230
document_version: 2
---

# Quy tắc Phụ thuộc Kiến trúc (Dependency Rules)

Tài liệu này định nghĩa các quy tắc phụ thuộc (Dependency Rules) hợp lệ và không hợp lệ giữa các tầng kiến trúc trong dự án FreeBook, nhằm bảo toàn tính toàn vẹn của mô hình Clean Architecture / MVVM và tránh lỗi coupling (ràng buộc chéo) phức tạp.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Vị trí tầng của 5 file mới (1.3.250)

* **3 file ở tầng Services**: `Services/ChapterText/ChapterStore/ChapterTOCDiff.swift` (55), `Services/Download/DownloadManager+TaskStore.swift` (249), `Services/Download/TxtExportFileWriter.swift` (97). Cả ba chỉ `import Foundation` (`+TaskStore` thêm `SwiftData`) — **không file nào `import SwiftUI`** ⇒ `SERVICE_SWIFTUI_IMPORT` không bị nới; **không file nào gọi `ToastManager.shared`** ⇒ `SERVICE_TOAST_COUPLING` an toàn: `+TaskStore` phát toast qua `DownloadPresentationEventCenter.shared.send(.showToast(...))` đúng như `DownloadManager.swift` trước đó.
* `ChapterTOCDiff` là `enum` với hàm `static` **thuần** trên hai mảng snapshot — không chạm sqlite, không `ModelContext`, không biết `ChapterStoreDatabase` tồn tại. Chiều phụ thuộc mới là một cạnh duy nhất: `ChapterStoreDatabase` → `ChapterTOCDiff`. Đặt logic ở file riêng thay vì nhồi vào `ChapterStoreDatabase.swift` (955, baseline 977 — chỉ còn 22 dòng dư địa) là quyết định có chủ ý.
* `DownloadManager+TaskStore.swift` là `extension DownloadManager`, **không khai type top-level** ⇒ `MULTI_PRIMARY_TYPES` không áp dụng; nó ở tầng Services nên việc tạo/giữ `ModelContext` riêng là đúng luật "tác vụ nền phải tạo `ModelContext` riêng từ `ModelContainer`, không dùng chung context của MainActor". `TxtExportFileWriter` là `final class` top-level, chỉ chạm `FileManager`/`FileHandle`.
* **2 file ở tầng Views**: `Views/Reader/Extensions/ReaderView+Suggestions.swift` (106) và `Views/Shelf/ShelfMain/Extensions/ShelfView+TXTImport.swift` (283) — đều là `extension` của struct View, không type top-level. **Không file nào `modelContext.insert/delete/save`**: khối TXT-import ghi qua `BookTransactionCoordinator` và `ChapterStore`/`BookBinManager`, `Result` trả về được xử lý ⇒ `VIEW_SWIFTDATA_MUTATION` không phát sinh vi phạm mới. Lưu ý khi đọc code: `try? modelContext.save()` ở `ShelfView.swift` nằm **ngoài** vùng tách nên vẫn ở file gốc, không bị mang sang.
* Ràng buộc ngôn ngữ, không phải kiến trúc, nhưng bắt buộc: `private` trong Swift là **file-scoped**, nên mọi member mà file `+` gọi tới đều phải `internal`. Vì vậy `ShelfView` mở `modelContext`, `selectedTab`, `isImporting`, `importIsIndeterminate`, `importProgress`, `importStatusText`, `pendingImport`, `isParsingTXT` thành `internal`, và `ReaderView` mở `suggestionChips` thành `internal`. `parseTxtBook` giữ `private` vì chỉ được gọi trong chính `+TXTImport`.
* Trần dòng: `ShelfView.swift` 1076 → **827** (baseline 942) và `DownloadManager.swift` 688 → **484** (baseline 640) ⇒ **cả hai rời khỏi danh sách vi phạm**. `ReaderView.swift` 2268 → **2186**, `ChapterStoreDatabase.swift` 955 → **954**, `ChapterPersistenceStore.swift` giữ **915** — đều đúng chiều "chỉ được giảm". **Không entry `architecture_allowlist.json` nào được thêm hay nới, không baseline nào bị nới.** `check_architecture.py`: **16 → 14 violation**, tập còn lại là tập con thật sự. Tổng file Swift 279 → **284**.

## Vị trí tầng của 2 file mới (1.3.247)

* Cả **2 file đều ở tầng Views**: `Views/Extensions/Editor/ExtensionScriptEditorView+Picker.swift` (117) và `+Toolbars.swift` (119) — đều là `extension ExtensionScriptEditorView`, **không khai type top-level** nên `MULTI_PRIMARY_TYPES` không áp dụng; không file nào `modelContext.insert/delete/save` hay gán thuộc tính `@Model` ⇒ không đụng `VIEW_SWIFTDATA_MUTATION`. Không cạnh phụ thuộc mới nào: hai file chỉ dịch chuyển khai báo trong cùng một struct.
* `+Toolbars.swift` khai `import UIKit` cạnh `import SwiftUI` — nằm ở `Views/**` nên luật `SERVICE_SWIFTUI_IMPORT` (chỉ áp cho `Sources/Services/**`) không liên quan; `dismissKeyboard()` cần `UIApplication`/`UIResponder` nên import tường minh thay vì dựa vào việc SwiftUI re-export UIKit.
* `RepositoryFilterPolicy` (Services) nhận thêm khoá sắp xếp `hasUpdate` — vẫn là hàm thuần trên `[Extension]`, không thêm import, không chạm `ModelContext`. Chiều Views → Services giữ nguyên: `RepositoryManagerView.filteredExtensions` gọi policy, policy không biết View tồn tại. Sắp xếp làm trên RAM đúng luật "không đặt predicate/sort chuỗi trong `@Query`".
* `GoogleDriveBackupListView` (Views) thêm phụ thuộc `TTSWidgetStateReader` + `modelContext.container`: đúng mẫu "View không observe trực tiếp `TTSManager`, chỉ qua projection reader", và container chỉ được **truyền xuống** `BackupCoordinator` chứ View không tự mở `ModelContext` để ghi.
* `AddBookToShelfCommand` (Models) thêm `lastReadDate: Date?` — DTO bất biến, mặc định `nil` nên mọi call site cũ không đổi; điểm đọc duy nhất là `BookTransactionCoordinator` (Services). `BackupLibraryWriter` vẫn ghi qua coordinator, không ghi thẳng `@Model`.
* Trần dòng: `ExtensionScriptEditorView.swift` 583 → **384** (baseline 474) ⇒ rời khỏi danh sách vi phạm; hai file mới ≤ 119 dòng. **Không entry `architecture_allowlist.json` nào được thêm hay nới.** `check_architecture.py`: **17 → 16 violation**, không violation mới. Tổng file Swift 277 → **279**.

## Vị trí tầng của 33 file mới (1.3.246)

* **23 file ở tầng Services** — `Services/Backup/` (17) + `Services/Backup/GoogleDrive/` (6): chỉ import `Foundation`, `SwiftData`, `Combine`, `ZIPFoundation`, `CryptoKit`, `Security`, `AuthenticationServices`, `UIKit`. **Không file nào `import SwiftUI`** ⇒ miễn trừ chỉ-dành-cho-`*WebViewLoader.swift` của `SERVICE_SWIFTUI_IMPORT` không bị nới; `UIKit` (key window cho `ASWebAuthenticationSession`) và `AuthenticationServices` không thuộc luật đó. **Không file nào gọi `ToastManager.shared`** ⇒ `SERVICE_TOAST_COUPLING` an toàn: `BackupCoordinator` chỉ publish `lastMessage`/`lastError` và `BackupHubView` mới hiển thị toast.
* **1 file Services nữa**: `Services/Extensions/Manager/ExtensionSyncCommandBuilder.swift` (chỉ `Foundation`). Nó nằm ở tầng Services chứ không cạnh `RepositoryManagerView` vì việc của nó là I/O + dựng Command, không phải presentation; View chỉ đưa vào một snapshot bất biến và nhận `[UpsertExtensionCommand]` — chiều Views → Services, đúng chiều cho phép.
* **1 file Models**: `Models/Books/EditBookInfoCommand.swift` — DTO bất biến, không phụ thuộc gì ngoài `Foundation`.
* **8 file ở tầng Views**: `Views/Settings/Backup/` (5), `Views/BookDetail/BookInfoEditView.swift`, `Views/Settings/Main/{BackupSettingsSection, TTSSettingsSection}.swift`. Không file nào `modelContext.insert/delete/save` hay gán thuộc tính `@Model`; mọi ghi đi qua coordinator và `Result` trả về **đều được xử lý** ⇒ không đụng `VIEW_SWIFTDATA_MUTATION`.
* Chiều phụ thuộc mới, không có cạnh ngược nào: `Views/Settings/Backup/**` → `BackupCoordinator` → `BackupExportWorker` / `BackupRestoreWorker` / `LocalBackupStore` / `GoogleDrive*`; `BackupRestoreWorker` → `BackupLibraryWriter` → `BookTransactionCoordinator` + `ExtensionTransactionCoordinator` (Services) → `@Model` (Models); `BackupChapterRestorer` → `ChapterStore` + `BookBinManager`; `BackupDictionaryRestorer` → `DictionaryTextFileStore` (Models) + `TranslationManager` (Services). Không worker nào biết `BackupHubView` tồn tại.
* `BackupLibraryWriter` là `@MainActor struct` chứ không phải actor: nó thao tác `ModelContext` của View và gọi coordinator — giữ nguyên luật "ghi SwiftData qua coordinator trên MainActor", còn phần nặng (zip, mạng, file) nằm trong actor worker.
* Ranh giới bí mật: `GoogleDriveConfiguration` là điểm duy nhất đọc `GOOGLE_DRIVE_CLIENT_ID` (Info.plist) và `UserDefaults("googleDriveClientId")`; `GoogleDriveTokenStore` là điểm duy nhất chạm Keychain. Không file nào khác trong `Sources/` đọc hai khoá này, và không file nào log token/payload.
* Notification: restore chỉ **phát lại** tên string đã có (`"extensionDidUpdate"`) và `notifyDictionariesDidUpdate()` sẵn có — không thêm tên notification string mới, đúng luật "signalling mới thì dùng `AsyncStream`".
* Trần dòng: file mới lớn nhất là `BackupRestoreWorker.swift` **236 dòng**; cả 33 file đều dưới trần 400 và đúng một type top-level (record Codable dùng type lồng, ví dụ `BackupPayload.BookRecord`) ⇒ **không entry `architecture_allowlist.json` nào được thêm hay nới**. Ba file legacy đi đúng chiều giảm: `SettingsView.swift` 453 → **439** (baseline 453), `RepositoryManagerView.swift` 751 → **709** (baseline 751), `BookDetailView.swift` 1213 → **1181** (baseline 1201). `check_architecture.py`: **18 → 17 violation** — không violation mới, cái mất đi là `LINE_LIMIT_EXCEEDED` của `BookDetailView.swift`. Tổng file Swift 244 → **277**.

## Vị trí tầng của 12 file mới (1.3.244)

* **11 file ở tầng Views**: `Views/Common/{BookSearchBarView, FloatingWidgetGeometry, VisibleBrowserPulseMonitor, BrowserFloatingWidgetUIWindow, BrowserFloatingWidgetContainerViewController, BrowserFloatingWidgetWindowManager}.swift`, `Views/Dictionary/{DictionaryTransferTarget, DictionaryEntryTransferAction, DictionaryEntryRow, DictionaryListView+Transfer}.swift`, `Views/Settings/Main/BrowserSettingsSection.swift`. Không file nào `modelContext.insert/delete/save` hay gán thuộc tính `@Model` ⇒ không đụng `VIEW_SWIFTDATA_MUTATION`.
* **1 file ở tầng Services**: `Services/Extensions/Engine/VisibleBrowserSettings.swift` — chỉ `import Foundation`, không `import SwiftUI` (nên miễn trừ chỉ-dành-cho-`*WebViewLoader.swift` của `SERVICE_SWIFTUI_IMPORT` không bị nới), và không gọi `ToastManager.shared` (`SERVICE_TOAST_COUPLING` an toàn). Cài đặt được đặt ở tầng Services vì consumer thật là `VisibleBrowserTabManager` (Services); tầng Views chỉ đọc **khoá** qua `@AppStorage(VisibleBrowserSettings.openMinimizedKey)` — chiều Views → Services, đúng chiều cho phép.
* Chiều phụ thuộc mới của đường copy từ điển: `Views/Dictionary/*` → `DictionaryCache` (Services) / `TranslationManager` (Services) → `DictionaryTextFileStore` (Models). Không có cạnh ngược, và **không có** tầng lưu trữ song song nào được tạo: `DictionaryEntryTransferAction` không mở file, không biết đường dẫn, không biết `.dat`.
* Toast của đường copy phát từ tầng **Views** (`ToastManager.shared` trong `DictionaryListView+Transfer.swift`), đúng nơi được phép; không service nào phát toast cho việc này nên `SERVICE_TOAST_COUPLING` không bị vi phạm mới.
* `BrowserFloatingWidget*` ở `Views/Common/` chứ không ở `Views/TTSWidget/`: chúng không phụ thuộc bất kỳ type nào của TTS. Phần dùng chung duy nhất được trích ra là `FloatingWidgetGeometry` (hàm thuần, `import UIKit`) — hai container VC phụ thuộc **vào nó**, không phụ thuộc lẫn nhau. Không có base class chung, nên không tạo cạnh mới giữa hai phân hệ widget.
* `VisibleBrowserPulseMonitor` và `BrowserFloatingWidgetWindowManager` phụ thuộc `VisibleBrowserTabManager` (Services) theo chiều Views → Services; chúng nhận tín hiệu qua `stateDidChangeNotification` **đã có sẵn**, không thêm tên notification string mới (đúng luật "signalling mới thì dùng `AsyncStream`, đừng thêm notification string").
* Trần dòng: file mới lớn nhất là `BrowserFloatingWidgetContainerViewController.swift` **197 dòng** — cả 12 file đều dưới trần 400 và đúng một type top-level, nên **không entry `architecture_allowlist.json` nào được thêm hay nới**. `SettingsView.swift` giữ đúng 453 dòng (không tăng: section mới nằm ở file riêng), `DictionaryListView.swift` 767 → 748 (tiến gần baseline 690, không xa thêm). `check_architecture.py` giữ đúng **18 violation** với tập vi phạm y hệt. Tổng file Swift 232 → 244.

## Vị trí tầng của `ReaderViewModelInvalidationRelay` (1.3.243)

* File mới `Sources/Views/Reader/Components/ReaderViewModelInvalidationRelay.swift` nằm trong tầng **Views**. Nó chỉ `import Combine`, phụ thuộc ra ngoài duy nhất là `ReaderViewModel` (cùng tầng, cùng thư mục) và giữ nó bằng `weak` chỉ để so identity — không SwiftData, không `ToastManager.shared`, không `import SwiftUI`, nên không đụng `VIEW_SWIFTDATA_MUTATION` lẫn `SERVICE_TOAST_COUPLING`.
* Chiều phụ thuộc mới là chiều **View → ViewModel** đã cho phép, đi qua một trung gian: `ReaderView` → `ReaderViewModelInvalidationRelay` → `ReaderViewModel.objectWillChange`. Không có cạnh ngược nào: relay không tham chiếu view, không biết `ReaderView` tồn tại.
* Luật đi kèm cho tầng Views: **`ObservableObject` giữ trong `@State` thì không được coi là đã quan sát.** Hoặc dùng `@StateObject`/`@ObservedObject`, hoặc phải có relay như file này; ngược lại body sẽ chỉ dựng lại nhờ nguồn invalidate vô can (đúng bug 1.3.243 sửa).
* File mới dài **40 dòng** (dưới trần 400 cho file mới), đúng một type top-level ⇒ không cần entry nào trong `architecture_allowlist.json`. Tổng file Swift 231 → 232; `check_architecture.py` giữ đúng **18 violation** cũ, không baseline nào bị nới.

## Vị trí tầng của `ReaderEnergyDiagnostics` sau khi tách file (1.3.239)

* File mới `Sources/Views/Reader/Components/ReaderEnergyDiagnostics.swift` nằm trong tầng **Views**, đúng nơi nó vốn ở (trước đây là type thứ hai trong `ReaderTextView.swift`). Nó chỉ `import UIKit`, phụ thuộc ra ngoài duy nhất là `AppLogger` — không chạm SwiftData, không `ToastManager.shared`, nên không đụng `VIEW_SWIFTDATA_MUTATION` lẫn `SERVICE_TOAST_COUPLING`.
* Chiều phụ thuộc không đổi, chỉ dịch chuyển khai báo: `ReaderView`, `ReaderTextView`, `ReaderView+LoadingView`, `ReaderScrollCoordinator`, `ParagraphTracker` → `ReaderEnergyDiagnostics` → `AppLogger`. Không có cạnh ngược từ diagnostics về bất kỳ view nào (`recordUIViewUpdate` nhận `AnyObject` và chỉ lấy `ObjectIdentifier`, không giữ tham chiếu mạnh).
* File mới dài **258 dòng** (dưới trần 400 dòng cho file mới) và đúng một type top-level, nên không cần entry miễn trừ nào trong `architecture_allowlist.json`; `ReaderTextView.swift` 647 → 450, tức càng xa baseline allowlist 651 của nó — baseline không bị nới. File này vẫn còn **3** type top-level (`ReaderTextView`, `ReaderUITextView`, `AutoSizingTextView`, giảm từ 4) nên entry miễn trừ `MULTI_PRIMARY_TYPES` của nó vẫn cần thiết. Tổng file Swift 230 → 231. `check_architecture.py` giữ đúng **18 violation** cũ.
* `AppLogger.shared.isLoggingEnabled` là getter chạm `UserDefaults`; luật mới cho tầng Views: **không đọc nó trên hot path** — chốt vào cờ cục bộ ở điểm bắt đầu session (`beginReaderSession`) rồi `guard` theo cờ đó. Đánh đổi có chủ ý: đổi cài đặt log khi Reader đang mở chỉ có hiệu lực ở lần mở kế tiếp.

## Luật một-primary-type đã được thoả mà không cần miễn trừ (1.3.236)

* Sau phép tách, **không file nào** trong `Sources/` còn vi phạm `MULTI_PRIMARY_TYPES`; 8 file trước đây vi phạm nay mỗi file đúng một type top-level. Miễn trừ `MULTI_PRIMARY_TYPES` trong `architecture_allowlist.json` không bị thêm entry nào.
* Chiều phụ thuộc không đổi — tách file chỉ dịch chuyển khai báo trong cùng module. Cặp phụ thuộc mới xuất hiện đều là nội bộ tầng: `TTSFloatingWidgetWindowManager` → `FloatingWidgetUIWindow` → `FloatingWidgetContainerViewController` (cùng `Views/TTSWidget/`), `VisibleBrowserTabManager` → `TabbedVisibleBrowserViewController` (cùng `Services/Extensions/Engine/`).
* Ranh giới `SERVICE_SWIFTUI_IMPORT` giữ nguyên: hai file mới dưới `Sources/Services/**` (`VisibleWebViewController.swift`, `TabbedVisibleBrowserViewController.swift`, `VisibleBrowserTabItem.swift`, `BookTitleTranslationBackfill.swift`, `DictionaryInvalidationScope.swift`) không import SwiftUI, nên miễn trừ chỉ-dành-cho-`*WebViewLoader.swift` không bị nới.

## Ranh giới target sau khi bỏ tầng test (1.3.235)

* `project.yml` chỉ còn **một** target biên dịch (`FreeBook`, `sources: - path: Sources`). Target `FreeBookTests` và thư mục `Tests/` đã bị xoá theo yêu cầu trực tiếp của người dùng, nên không còn phụ thuộc `Tests → FreeBook` và không còn API nào tồn tại chỉ để phục vụ test.
* Hệ quả cho luật phụ thuộc: mọi symbol `public`/`internal` không có tham chiếu trong `Sources/` nay là code chết thật sự — trước đây không thể kết luận vì `Tests/` có thể đang dùng.
* Chiều phụ thuộc của các phân hệ không đổi; việc dọn chỉ **bớt** cạnh (xoá 5 file, ~30 symbol) chứ không thêm cạnh mới nào.

## Next-chapter prefix dependency direction (1.3.234)

* `TTSNextChapterPrefixCache` nằm ở `Sources/Services/TTS/`, chỉ `import Foundation`, **không** import SwiftUI và **không** gọi `ToastManager.shared` — thoả `SERVICE_SWIFTUI_IMPORT` và `SERVICE_TOAST_COUPLING`.
* Chiều phụ thuộc: `TTSManager` (+ extension `TTSManager+NextChapterPrefix`) → `TTSNextChapterPrefixCache` → {`PiperTTSService`, `TTSAudioSynthesisWorker` → `RemoteTTSSynthesisCoordinator`, `GoogleTTSService`, `ExtTTSService`}. Bộ đệm **không** tham chiếu ngược `TTSManager`: mọi service được truyền vào theo tham số của `request(...)`, đúng mẫu `promoteAudioIfNeeded` của `TTSChapterPrefetcher`.
* Bộ đệm không phụ thuộc `TTSChapterPrefetcher` và ngược lại; việc điều phối thứ tự (chunk 0 trước prefix) do `TTSManager+NextChapterPrefix` quyết định, giữ hai owner tách biệt.
* `Sources/Views/**` không có tham chiếu nào tới bộ đệm này; Reader/widget tiếp tục chỉ đọc projection reader.

## Shared extension-type vocabulary (1.3.226)

* `ExtensionType` nằm trong tầng `Models/Extensions`; Models command, Services và Views được phép phụ thuộc vào namespace này để dùng chung vocabulary persisted.
* Namespace không chứa policy hiển thị/lọc và không import SwiftUI; các policy vẫn thuộc `RepositoryFilterPolicy` hoặc view tương ứng. `Extension.type` vẫn là `String` để giữ schema và hỗ trợ type mở rộng.

## Quy Tắc Phụ Thuộc Tầng (Dependency Rules v4.1/v5.0)

1. **Ma Trận Phụ Thuộc Phân Tầng**:
   - `Views` -> `ViewModels` / `Transaction Coordinators` -> `Services` / `Repositories` -> `Models`
   - Views **KHÔNG ĐƯỢC** thực hiện thay đổi dữ liệu SwiftData trực tiếp.
   - Services **KHÔNG ĐƯỢC** import `SwiftUI` và **KHÔNG ĐƯỢC** gọi `ToastManager.shared` trực tiếp. Check `SERVICE_SWIFTUI_IMPORT` miễn trừ đúng các file có tên kết thúc bằng `WebViewLoader.swift` (hiện là `WebViewLoader.swift` và `VisibleWebViewLoader.swift`); tính đến bản này **không file nào** trong `Sources/Services/` còn import SwiftUI, nên miễn trừ chỉ là an toàn tương lai.

2. **Giới Hạn File & Ratcheting**:
   - File mới được tạo trong refactor phải <= 400 dòng physical.
   - Các file cũ vượt 400 dòng thuộc `Scripts/architecture_allowlist.json` phải siết chặt dòng (ratchet down) và không được tăng lại.
   - Mỗi file Swift chỉ chứa **duy nhất 1 primary type** (`class`, `struct`, `enum`, `actor`).

3. **Luật Khóa Unit Tests (AGENTS.md Rule 2.1)**:
   - Nghiêm cấm tuyệt đối chỉnh sửa, tạo mới, di chuyển, hoặc xóa các file trong thư mục `Tests/`.
<!-- GENERATED END -->
