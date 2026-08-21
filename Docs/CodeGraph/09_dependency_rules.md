---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 216
document_version: 2
---

# Quy tắc Phụ thuộc Kiến trúc (Dependency Rules)

Tài liệu này định nghĩa các quy tắc phụ thuộc (Dependency Rules) hợp lệ và không hợp lệ giữa các tầng kiến trúc trong dự án FreeBook, nhằm bảo toàn tính toàn vẹn của mô hình Clean Architecture / MVVM và tránh lỗi coupling (ràng buộc chéo) phức tạp.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
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
