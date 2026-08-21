---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 216
document_version: 2
---

# Kiến trúc Tổng thể & Quy tắc Thiết kế

Tài liệu này phác thảo kiến trúc tổng thể, sơ đồ thư mục, các tính năng cốt lõi và các quy tắc kiến trúc đang được áp dụng trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Architecture & Refactor Summary (v4.1/v4.2/v5.0)

Dự án FreeBook đã hoàn tất tái cấu trúc kiến trúc v4.1/v5.0 với các điểm chính:
1. **Phân tách Monolith & Trích xuất File**:
   - `TTSManager.swift` được tách thành các file mở rộng chuyên biệt trong `Sources/Services/TTS/Extensions/` (`TTSManager+Playback`, `+NowPlaying`, `+Interruption`, `+PrefetchCache`, `+NghiEnergy`, `+Telemetry`) cùng với `TTSAudioEngineController` và `DisplayTextFormatter`.
   - Trình đọc `ReaderView.swift` & `ReaderViewModel.swift` trích xuất `ReaderScrollCoordinator`, `ReaderSelectionCoordinator`, `ReaderProgressScheduler`, và các extension theo nhóm chức năng.
   - Quản lý kho `RepositoryManagerView.swift` trích xuất `RepositoryFilterPolicy`, `RepositoryManagerView+Actions`, `RepositoryManagerView+RepoOps`.
   - Tiền xử lý chi tiết sách `BookDetailView.swift` trích xuất `BookDetailLoader`, `BookDetailView+TOCPreparation`, `BookDetailView+Extensions`.
   - Xử lý văn bản & dịch thuật `TranslateUtils.swift` trích xuất `TranslateUtils+Tokenization` và `VietPhraseTokenizer`.
2. **Loại bỏ SwiftData Mutations trong View Layer**:
   - SwiftUI Views không được thực hiện các thao tác ghi trực tiếp (`modelContext.insert`, `delete`, `save` hoặc gán thuộc tính `@Model`).
   - Mọi thao tác ghi được chuyển giao cho `BookTransactionCoordinator` và `ExtensionTransactionCoordinator` thông qua các Command DTO bất biến (`AddBookToShelfCommand`, `UpsertExtensionCommand`, `ExtensionConfigCommand`, `UpdateExtensionFolderCommand`).
3. **Luồng Sự Kiện Presentation (Presentation Event Center)**:
   - Các Service tầng dưới (`TTSManager`, `DownloadManager`) phát sự kiện giao diện thông qua `AsyncStream` Event Centers (`TTSPresentationEventCenter`, `DownloadPresentationEventCenter`).
   - `AppLaunchRootView` (`FreeBookApp.swift`) là điểm duy nhất trong ứng dụng đăng ký lắng nghe và hiển thị Toast trên UI.
4. **Hệ Thống Kiểm Tra Kiến Trúc Fail-Closed**:
   - `Scripts/check_architecture.py` (v2 fail-closed schema validation) kiểm tra giới hạn dòng (<= 400 dòng cho file mới), 1 loại chính/file, cấm ghi `@Model` trong View, và cấm Service phụ thuộc direct ToastManager/SwiftUI.
<!-- GENERATED END -->
