---
name: code_reviewer
description: Thực hiện code review độc lập từng màn hình và chức năng của dự án, kiểm tra kỹ cả cú pháp và logic bằng cách chia nhỏ thành các subagent chuyên biệt.
---

# Hướng dẫn Code Review Chuyên Sâu (Senior Code Reviewer Skill)

Tài liệu này định nghĩa quy trình thực hiện Code Review chuyên sâu cho dự án **FreeBook**, sử dụng cơ chế chia nhỏ công việc cho nhiều subagent chuyên trách độc lập để tối đa hóa hiệu năng và chất lượng kiểm tra.

---

## 1. Phân chia Module & Màn hình Dự án

Dự án FreeBook được phân chia thành các module cốt lõi sau để gán cho từng subagent review riêng biệt:

1. **Module Shelf & BookDetail (Kệ sách & Chi tiết truyện)**
   - **Phạm vi file:** `Sources/Views/Shelf/`, `Sources/Views/BookDetail/`, `Sources/Models/Database/Book.swift`, `Sources/Models/Database/Chapter.swift`.
   - **Vai trò subagent:** `subagent_shelf_detail_review`

2. **Module Reader & TTS (Trình đọc & Giọng đọc thành tiếng)**
   - **Phạm vi file:** `Sources/Views/Reader/`, `Sources/Views/TTSWidget/`, `Sources/Services/TTS/`.
   - **Vai trò subagent:** `subagent_reader_tts_review`

3. **Module JS Extension & Engine (Extension Engine & Store)**
   - **Phạm vi file:** `Sources/Views/Extensions/`, `Sources/Services/Extensions/`, `Sources/Models/Database/Extension.swift`, `Sources/Models/Database/Repository.swift`.
   - **Vai trò subagent:** `subagent_extensions_review`

4. **Module Dictionary & Translation (Từ điển & Dịch tự động)**
   - **Phạm vi file:** `Sources/Views/Dictionary/`, `Sources/Services/Translation/`, `Sources/Models/Dictionaries/`.
   - **Vai trò subagent:** `subagent_translation_review`

5. **Module Download & Common Services (Tải truyện ngoại tuyến & Thành phần chung)**
   - **Phạm vi file:** `Sources/Views/Download/`, `Sources/Views/Common/`, `Sources/Services/Download/`, `Sources/Common/`.
   - **Vai trò subagent:** `subagent_download_common_review`

---

## 2. Quy trình Thực hiện dành cho Agent Chính (Orchestrator)

1. **Bước 1: Khởi tạo các subagent**
   Sử dụng công cụ `define_subagent` để định nghĩa các subagent dựa trên danh sách module ở trên.
   
2. **Bước 2: Phân công nhiệm vụ**
   Sử dụng công cụ `invoke_subagent` để gửi yêu cầu cụ thể cho từng subagent. Mỗi subagent sẽ nhận danh sách file tương ứng trong phạm vi của mình và các checklist chi tiết dưới đây.

3. **Bước 3: Tổng hợp báo cáo**
   Thu thập kết quả từ tất cả các subagent, giải quyết các mâu thuẫn (nếu có), loại bỏ trùng lặp và biên soạn thành một báo cáo duy nhất `review_report.md` tại thư mục artifacts.

---

## 3. Checklist Chi tiết cho từng Subagent

Mỗi subagent khi nhận nhiệm vụ review mã nguồn phải kiểm tra nghiêm ngặt 2 phần:

### A. Kiểm tra Cú pháp (Syntax)
1. **Dấu ngoặc & Ký tự phân tách:** Kiểm tra tỉ mỉ các dấu đóng mở ngoặc `{}`, `()`, `[]`, `<>` hoặc các dấu phẩy `,`, hai chấm `:`, chấm phẩy `;` xem có bị thừa hoặc thiếu hay không.
2. **Khai báo hợp lệ:** Đối chiếu các class, struct, enum, protocol, hàm và biến. Đảm bảo chúng được khai báo đúng cú pháp Swift, tuân thủ access level tương thích.
3. **Phạm vi & Vòng đời (Scope & Lifespan):**
   - Đảm bảo biến/hàm được khai báo trước khi sử dụng.
   - Tránh lỗi Shadowing gây hiểu nhầm logic.
   - Kiểm tra các tham chiếu có nguy cơ gây Strong Reference Cycles (Memory Leaks), đặc biệt trong các closure (`@escaping`), các khối Combine hoặc Swift Concurrency. Yêu cầu sử dụng `[weak self]` khi cần thiết.
   - Chú ý quy tắc của dự án: Không sử dụng `#Predicate` lọc thuộc tính chuỗi trực tiếp trong `@Query` của SwiftData (phải lấy toàn bộ rồi lọc trong bộ nhớ).
4. **Kiểu dữ liệu:** Đảm bảo kiểu tham số truyền vào và kiểu trả về khớp hoàn toàn. Kiểm tra việc ép kiểu ép buộc (`as!`) hoặc force unwrap (`!`), đề xuất thay thế bằng safe unwrap (`if let`, `guard let`, `nil coalescing ??`).

### B. Kiểm tra Logic & Luồng hoạt động (Logic & Workflows)
1. **Luồng giao diện & Trạng thái (UI/State Flow):**
   - Vẽ/Mô phỏng luồng hoạt động của màn hình từ lúc mở cho đến lúc đóng.
   - Tìm kiếm nguy cơ bị kẹt trạng thái (deadlock UI): Popup/Sheet/Alert mở ra nhưng không có nút đóng hoặc điều kiện đóng bị lỗi; Hai màn hình chờ đợi kết quả chéo lẫn nhau.
   - Lỗi cập nhật giao diện: Các biến thay đổi nhưng không dùng `@State`, `@Binding`, hoặc `@StateObject` làm giao diện không thể tự động render lại.
2. **Điều hướng (Navigation):**
   - Xác định rõ các cơ chế điều hướng (`NavigationStack`, `NavigationLink`, `.sheet`, `.fullScreenCover`).
   - Đảm bảo có thể quay lại màn hình trước đó dễ dàng, không bị mất trạng thái hoặc rò rỉ bộ nhớ khi dismiss.
3. **Xử lý Ngoại lệ & Biên (Edge Cases):**
   - Dữ liệu trả về rỗng (Empty state), dữ liệu định dạng sai (ví dụ: chuỗi JSON từ extension bị lỗi).
   - Mất kết nối mạng đột ngột khi đang thực hiện các yêu cầu tải sách/extension.
   - Người dùng bấm nút liên tiếp nhiều lần (Double tap/Concurrent actions) tạo ra các tác vụ tải trùng lặp hoặc crash ứng dụng. Đề xuất debounce hoặc disabling nút khi đang xử lý.

---

## 4. Khuôn mẫu Báo cáo Đầu ra (Output Template)

Mỗi lỗi phát hiện bởi subagent hoặc báo cáo tổng hợp cuối cùng phải được trình bày theo cấu trúc sau:

### Lỗi #[Số thứ tự]: [Tên mô tả ngắn gọn lỗi]
- **Tệp tin:** `[Tên file và dòng code chứa lỗi]` (Sử dụng liên kết markdown file://)
- **Phân loại:** `[Cú pháp / Logic]`
- **Mức độ ảnh hưởng:** `[Critical / Major / Minor]`
- **Nguyên nhân:** `[Giải thích cặn kẽ tại sao đoạn code đó sai hoặc không tối ưu]`
- **Ảnh hưởng:** `[Hành vi xấu gì sẽ xảy ra trên ứng dụng nếu không được sửa]`
- **Đề xuất cách sửa cụ thể:**
  ```diff
  - // Code cũ bị lỗi
  + // Code mới đề xuất sửa
  ```

---

## 5. Kích hoạt & Thực thi
Khi nhận lệnh chạy review, Model chính sẽ:
1. Đọc hướng dẫn này.
2. Xác định các file thuộc về từng module trong codebase.
3. Spawns các subagent bằng `invoke_subagent`.
4. Viết báo cáo cuối cùng vào artifact `review_report.md` và giới thiệu cho người dùng thông qua Walkthrough.
