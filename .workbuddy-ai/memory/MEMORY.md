# FreeBook — ghi chú dài hạn (mục lục, nén 2026-10-05)

> **Chi tiết đầy đủ ở `REFERENCE.md`** cùng thư mục — TTS, từ điển/gộp từ điển, quét tên riêng, pipeline dịch, backup, hiệu năng Reader, plan đang mở, Tài liệu & CHANGELOG. Đọc file đó khi cần chi tiết; file này chỉ giữ luật cứng + bẫy nhanh.

## Luật cứng với người dùng
- Mọi yêu cầu **thêm / sửa / xoá chức năng PHẢI lập plan trước, chờ user "duyệt" rồi mới sửa code** (`grill-me` → `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`). **Ngoại lệ duy nhất**: yêu cầu **"điều tra"** thuần (chỉ đọc/phân tích, không đổi hành vi) làm ngay.
- Trả lời **tiếng Việt**, thuật ngữ kỹ thuật tiếng Anh inline. Không đoán UI: đọc code view thật; mọi khẳng định cấu trúc phải dẫn `file:line`.
- Plan → `Docs/Plans/`; báo cáo → `Docs/Reports/`; **không** ghi vào `Docs/CodeGraph/`.
- `grill-me` có **3 bản** (`.claude/`, `.workbuddy/`, `~/.workbuddy-ai/`) — sửa 1 phải copy 2 bản kia.

## Sau khi sửa code (bắt buộc, push-ci-monitor)
`validate_links.py --explain` → sửa **chỉ trong** `<!-- GENERATED START/END -->` → `--accept <doc>` (1 doc/lần, phải loop) hoặc `--no-change-needed <doc>` → `CHANGELOG.md` `[1.3.NNN] - YYYY-MM-DD` (tiêu đề **trùng subject commit**) → validator read-only **PASS 100%** → kết thúc response bằng `"CodeGraph updated."` hoặc `"No CodeGraph update required."`

## Bẫy nhanh
- **Không build trên Windows** ⇒ không bao giờ nói "đã kiểm chứng biên dịch" (CI xác nhận).
- `Scripts/check_architecture.py` **đỏ sẵn** (baseline 30 violation): chỉ chịu violation **MỚI**; `[PASS]` của script **không phải bằng chứng** (regex ăn nhầm code thật khi có string interpolation).
- File Swift ≤ **400 dòng**, **1 type chính** top level; `Sources/Services/**` không `import SwiftUI`/`ToastManager`; `Sources/Views/**` không `modelContext.insert/delete/save`.
- **Ratchet-down**: `TextPreprocessor.swift` **đúng 1121** dòng; `QuickTranslationRuleEngine.swift` 399/400; `TTSManager.swift` 4024/3470 (code mới → `TTSManager+*.swift`).
- Grep chỉ trong `Sources/` (`Tools/` >4000 file → timeout). **Bẫy doc**: cú pháp chứa `](` (vd `[Float](repeating:)`) bị hiểu là markdown link ⇒ viết lại bằng chữ.
- Thêm file Swift mới ⇒ `00_index`/`02_file_graph`/`09_dependency_rules`/`14_complexity_report`/`11_subsystems` cùng stale.
