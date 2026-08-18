---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 5
---

# Phân tích các Phân hệ Cốt lõi (Subsystems)

Tài liệu này phân tích chi tiết 14 phân hệ chính cấu thành nên ứng dụng FreeBook, mô tả mục tiêu, API công khai, dependency, quan hệ sở hữu đối tượng, điểm vào/ra, vòng đời và các rủi ro tương ứng cho từng phân hệ.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Thành Phần & Phân Hệ Kiến Trúc (Subsystems v4.1/v5.0)

1. **Phân Hệ Quản Lý Giao Dịch Dữ Liệu (Transaction System)**:
   - `BookTransactionCoordinator`: Sở hữu mọi thao tác thêm, cập nhật metadata, thiết lập chương hiện tại, xóa sách.
   - `ExtensionTransactionCoordinator`: Sở hữu mọi thao tác thêm repo, upsert extension, lưu config, touch lastUpdated.

2. **Phân Hệ Trình Đọc & Tải Nền (Reader Subsystem)**:
   - `ReaderView`, `ReaderViewModel`, `ReaderScrollCoordinator`, `ReaderSelectionCoordinator`, `ReaderProgressScheduler`, `BackgroundPagingWorker`, `BackgroundSearchWorker`, `ReaderChapterListStore`.

3. **Phân Hệ TTS & Audio Engine (TTS Subsystem)**:
   - `TTSManager`, `TTSAudioEngineController`, `TTSPresentationEventCenter`, `DisplayTextFormatter`, `ONNXPiperEngine`.

4. **Phân Hệ Quản Lý Tiện Ích & Bóc Tách (Extension Subsystem)**:
   - `ExtensionManager`, `JSExecutor`, `JSExecutor+Async`, `BookDetailLoader`, `RepositoryFilterPolicy`.
<!-- GENERATED END -->
