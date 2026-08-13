---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 6
---

# Dòng chảy Dữ liệu & Cơ chế Cache (Data Flow & Caching)

Tài liệu này theo dõi chi tiết đường đi của dữ liệu qua các tầng kiến trúc (Input -> View -> ViewModel -> Manager -> Repository -> Database) và làm rõ toàn bộ các cơ chế bộ nhớ đệm (Cache) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Sơ Đồ Luồng Dữ Liệu (Data Flow v4.1/v5.0)

1. **Luồng Dữ Liệu Giao Dịch Lưu Trữ**:
   `SwiftUI View` -> (Tạo `Command DTO`) -> `Transaction Coordinator` -> `SwiftData ModelContext` -> `Persistent Store`
   - Dataflow hoàn toàn một chiều và bất biến ở ranh giới View.

2. **Luồng Thực Thi Tiện Ích Bóc Tách Cách Lý**:
   `BookDetailView` / `ReaderView` -> `ExtensionExecutionSnapshot` -> `JSExecutor.runAsync` -> `VBook JS Engine` -> `DTO Results`

3. **Luồng Tải Trang & Tìm Kiếm Chương Nền**:
   `ReaderViewModel` -> `BackgroundPagingWorker` / `BackgroundSearchWorker` -> `ChapterStore` -> `ChapterRowItem` / `SearchChapterDTO` -> `@Published` UI State
<!-- GENERATED END -->
