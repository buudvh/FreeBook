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
