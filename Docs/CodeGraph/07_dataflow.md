---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 218
document_version: 7
---

# Dòng chảy Dữ liệu & Cơ chế Cache (Data Flow & Caching)

Tài liệu này theo dõi chi tiết đường đi của dữ liệu qua các tầng kiến trúc (Input -> View -> ViewModel -> Manager -> Repository -> Database) và làm rõ toàn bộ các cơ chế bộ nhớ đệm (Cache) đang vận hành trong dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## All-source novel-search data flow (1.3.225)

* Caller-provided `[Extension]` → `SearchView.searchableExtensions` removes `type == "tts"` → parallel extension search → per-source UI state/results. The filtered collection is reused by the `Xem thêm` destination; no TTS extension reaches `ExtensionManager.search` through the all-source path.

## Local TXT title translation and search data flow (1.3.224)

* `ParsedBook.chapters` → detached `TranslateUtils.translateChapterTitle` + metadata map → `ChapterMetadataSnapshot.title/titleTrans` → `ChapterStore.replaceFullTOC` → SQLite `chapter_metadata.title/title_trans`. Cache offset/length updates reuse the same snapshot and do not discard `titleTrans`.
* Local chapter query → one `%query%` pattern bound to both stored title columns → `StoredChapterSnapshot` results → presentation chooses the row title according to `isTranslationEnabled`. No import-time or startup backfill is performed for older local books.

## Sơ Đồ Luồng Dữ Liệu (Data Flow v4.1/v5.0)

1. **Luồng Dữ Liệu Giao Dịch Lưu Trữ**:
   `SwiftUI View` -> (Tạo `Command DTO`) -> `Transaction Coordinator` -> `SwiftData ModelContext` -> `Persistent Store`
   - Dataflow hoàn toàn một chiều và bất biến ở ranh giới View.

2. **Luồng Thực Thi Tiện Ích Bóc Tách Cách Lý**:
   `BookDetailView` / `ReaderView` -> `ExtensionExecutionSnapshot` -> `JSExecutor.runAsync` -> `VBook JS Engine` -> `DTO Results`

3. **Luồng Tải Trang & Tìm Kiếm Chương Nền**:
   `ReaderViewModel` -> `BackgroundPagingWorker` / `BackgroundSearchWorker` -> `ChapterStore` -> `ChapterRowItem` / `SearchChapterDTO` -> `@Published` UI State

4. **Luồng dữ liệu NghiTTS an toàn khi chuyển chương (1.3.147)**:
   `paragraph.text` -> replacements -> `TextPreprocessor` -> kiểm tra speakable
   - Speakable -> Piper ONNX -> PCM/WAV -> `preloadedData[index]`.
   - Unspeakable -> silence samples -> WAV hoặc một terminal streaming payload -> cache/playback như audio bình thường.
   - Failure metadata chỉ lưu khóa định danh session/chapter/paragraph, số attempt và cờ block; không lưu nội dung văn bản người dùng trong log.
<!-- GENERATED END -->
