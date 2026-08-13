---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-14T09:15:00+07:00
git_commit: UNKNOWN
source_files: 87
document_version: 1
---

# Quy tắc Phụ thuộc Kiến trúc (Dependency Rules)

Tài liệu này định nghĩa các quy tắc phụ thuộc (Dependency Rules) hợp lệ và không hợp lệ giữa các tầng kiến trúc trong dự án FreeBook, nhằm bảo toàn tính toàn vẹn của mô hình Clean Architecture / MVVM và tránh lỗi coupling (ràng buộc chéo) phức tạp.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Quy Tắc Phụ Thuộc Tầng (Dependency Rules v4.1/v5.0)

1. **Ma Trận Phụ Thuộc Phân Tầng**:
   - `Views` -> `ViewModels` / `Transaction Coordinators` -> `Services` / `Repositories` -> `Models`
   - Views **KHÔNG ĐƯỢC** thực hiện thay đổi dữ liệu SwiftData trực tiếp.
   - Services **KHÔNG ĐƯỢC** import `SwiftUI` (trừ adapter `WebViewLoader.swift`) và **KHÔNG ĐƯỢC** gọi `ToastManager.shared` trực tiếp.

2. **Giới Hạn File & Ratcheting**:
   - File mới được tạo trong refactor phải <= 400 dòng physical.
   - Các file cũ vượt 400 dòng thuộc `Scripts/architecture_allowlist.json` phải siết chặt dòng (ratchet down) và không được tăng lại.
   - Mỗi file Swift chỉ chứa **duy nhất 1 primary type** (`class`, `struct`, `enum`, `actor`).

3. **Luật Khóa Unit Tests (AGENTS.md Rule 2.1)**:
   - Nghiêm cấm tuyệt đối chỉnh sửa, tạo mới, di chuyển, hoặc xóa các file trong thư mục `Tests/`.
<!-- GENERATED END -->
