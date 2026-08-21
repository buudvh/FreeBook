---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-08-21T10:30:00+07:00
git_commit: UNKNOWN
source_files: 218
document_version: 6
---

# Phân tích các Phân hệ Cốt lõi (Subsystems)

Tài liệu này phân tích chi tiết 14 phân hệ chính cấu thành nên ứng dụng FreeBook, mô tả mục tiêu, API công khai, dependency, quan hệ sở hữu đối tượng, điểm vào/ra, vòng đời và các rủi ro tương ứng cho từng phân hệ.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Extension type vocabulary (1.3.226)

* Extension subsystem dùng `ExtensionType` làm nguồn duy nhất cho bốn giá trị type chuẩn khi parse metadata, upsert, lọc repository và chọn UI theo type.
* Discovery/Search chỉ nhận diện nguồn đọc qua `novel`/`chineseNovel` và loại `tts` khỏi search-all; TTS Settings nhận diện extension giọng đọc qua `tts`; comic tiếp tục bị repository policy ẩn. Unknown type vẫn đi qua nhánh mặc định.

## TTS replacement manager public API (1.3.221)

* `TTSReplacementManager` sở hữu danh sách có thứ tự `[TTSReplacementRule]` và persistence `character_replacements.json`. `addRule(_:) -> AddRuleResult` bảo đảm thao tác thêm không để lại pattern trùng: xóa mọi match chính xác rồi append rule mới để giữ đúng ưu tiên áp dụng tuần tự.
* `AddRuleResult` gồm `.added` và `.replaced`; `@discardableResult` giữ tương thích với caller không cần phản hồi. `updateRule(_:)`, `deleteRule(id:)`, reorder và import/export giữ hợp đồng hiện có.

## Thành Phần & Phân Hệ Kiến Trúc (Subsystems v4.1/v5.0)

1. **Phân Hệ Quản Lý Giao Dịch Dữ Liệu (Transaction System)**:
   - `BookTransactionCoordinator`: Sở hữu mọi thao tác thêm, cập nhật metadata, thiết lập chương hiện tại, xóa sách.
   - `ExtensionTransactionCoordinator`: Sở hữu mọi thao tác thêm repo, upsert extension, lưu config, touch lastUpdated.

2. **Phân Hệ Trình Đọc & Tải Nền (Reader Subsystem)**:
   - `ReaderView`, `ReaderViewModel`, `ReaderScrollCoordinator`, `ReaderSelectionCoordinator`, `ReaderProgressScheduler`, `BackgroundPagingWorker`, `BackgroundSearchWorker`, `ReaderChapterListPageFetcher`.

3. **Phân Hệ TTS & Audio Engine (TTS Subsystem)**:
   - `TTSManager`, `TTSAudioEngineController`, `TTSPresentationEventCenter`, `DisplayTextFormatter`, `ONNXPiperEngine`.

4. **Phân Hệ Quản Lý Tiện Ích & Bóc Tách (Extension Subsystem)**:
   - `ExtensionManager`, `JSExecutor`, `JSExecutor+Async`, `BookDetailLoader`, `RepositoryFilterPolicy`.
<!-- GENERATED END -->
