# FreeBook — ghi chú dài hạn (mục lục, nén 2026-10-05)

> **Chi tiết đầy đủ ở `REFERENCE.md`** cùng thư mục — TTS, từ điển/gộp từ điển, quét tên riêng, pipeline dịch, backup, hiệu năng Reader, plan đang mở, Tài liệu & CHANGELOG. Đọc file đó khi cần chi tiết; file này chỉ giữ luật cứng + bẫy nhanh.

## Luật cứng với người dùng
- Mọi yêu cầu **thêm / sửa / xoá chức năng PHẢI lập plan trước, chờ user "duyệt" rồi mới sửa code** (`grill-me` → `Docs/Plans/YYYY-MM-DD-plan-<slug>.md`). **Ngoại lệ duy nhất**: yêu cầu **"điều tra"** thuần (chỉ đọc/phân tích, không đổi hành vi) làm ngay.
- Trả lời **tiếng Việt**, thuật ngữ kỹ thuật tiếng Anh inline. Không đoán UI: đọc code view thật; mọi khẳng định cấu trúc phải dẫn `file:line`.
- Plan → `Docs/Plans/`; báo cáo → `Docs/Reports/`; **không** ghi vào `Docs/CodeGraph/`.
- `grill-me` có **3 bản** (`.claude/`, `.workbuddy/`, `~/.workbuddy-ai/`) — sửa 1 phải copy 2 bản kia.

## Sau khi sửa code (bắt buộc, push-ci-monitor)
Thêm entry `Docs/CodeGraph/CHANGELOG.md` `[1.3.NNN] - YYYY-MM-DD` (tăng NNN mỗi thay đổi; tiêu đề **trùng subject commit**) → kết thúc response bằng `"CodeGraph updated."` hoặc `"No CodeGraph update required."`

**Đã cũ, đừng làm lại**: `validate_links.py` + đồ thị cấu trúc CodeGraph **đã nghỉ hưu** ở `[1.3.477] - 2026-10-07`. Truy vấn cấu trúc nay dùng MCP `codegraph_explore` / CLI `codegraph explore`. `CHANGELOG.md` **nằm ở `Docs/CodeGraph/`**, KHÔNG ở root (cạnh `CHANGELOG.archive.md` — chỉ tra cứu, không ghi mới). Version hiện tại: `[1.3.477]`.

## Bẫy nhanh
- **Không build trên Windows** ⇒ không bao giờ nói "đã kiểm chứng biên dịch" (CI xác nhận).
- `Scripts/check_architecture.py` **đỏ sẵn** (baseline 30 violation): chỉ chịu violation **MỚI**; `[PASS]` của script **không phải bằng chứng** (regex ăn nhầm code thật khi có string interpolation).
- File Swift ≤ **400 dòng**, **1 type chính** top level; `Sources/Services/**` không `import SwiftUI`/`ToastManager`; `Sources/Views/**` không `modelContext.insert/delete/save`.
- **Ratchet-down**: `TextPreprocessor.swift` **đúng 1121** dòng; `QuickTranslationRuleEngine.swift` 399/400; `TTSManager.swift` 4024/3470 (code mới → `TTSManager+*.swift`).
- Grep chỉ trong `Sources/` (`Tools/` >4000 file → timeout). **Bẫy doc**: cú pháp chứa `](` (vd `[Float](repeating:)`) bị hiểu là markdown link ⇒ viết lại bằng chữ.
- Thêm file Swift mới ⇒ **không cần** cập nhật doc đồ thị nữa (9 doc đó đã bị xoá ở 1.3.477). Chỉ cần `xcodegen generate` khi thêm/xoá/đổi tên file Swift.
- TTS: `Sources/Services/TTS/` có ~90 file; entry luồng phát là `TTSManager.startSpeaking` (`:1243`) → `speakCurrent` (`:2421`) → dispatch `:2451-2459`. `TTSAudioEngineController` (EQ + TimePitch) là **dead code**, đừng tưởng nó đang chỉnh tiếng.
