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
## 1. Sơ đồ Quan hệ Phụ thuộc hợp lệ (Allowed Dependencies)

```mermaid
graph TD
    Views["Tầng View (SwiftUI Views)"] -->|1| ViewModels["Tầng ViewModel (ReaderViewModel)"]
    Views -->|2| Managers["Tầng Manager (Singletons)"]
    
    ViewModels -->|3| Managers
    ViewModels -->|4| Repositories["Tầng Repository (ReadingProgressRepository)"]
    
    Managers -->|5| Engines["Tầng Engine / Service (JSExecutor, PiperTTSService)"]
    Engines -->|6| Models["Tầng Model / Cấu trúc dữ liệu (Book, Chapter, Extension)"]
    
    %% Cho phép truy cập dữ liệu
    Views -.->|7 (Đọc dữ liệu)| Models
    ViewModels -.->|8| Models
    Managers -.->|9 (Đọc & Ghi)| Models
```

### Giải thích các mối quan hệ hợp lệ:
1.  **[1] View -> ViewModel**: View sở hữu và quan sát ViewModel qua `@StateObject` hoặc `@ObservedObject` để cập nhật giao diện.
2.  **[2] View -> Manager**: View được phép tham chiếu trực tiếp đến các Manager Singleton (ví dụ: `TTSManager.shared`, `DownloadManager.shared`) để hiển thị trạng thái phát hoặc tải lên giao diện.
3.  **[3] ViewModel -> Manager**: ViewModel gọi Manager để thực hiện các hành động nghiệp vụ.
4.  **[4] ViewModel -> Repository**: ViewModel dùng Repository để thực hiện lưu trữ/nạp tiến trình đọc.
5.  **[5] Manager -> Engine / Service**: Các Manager đóng gói và điều phối các bộ công cụ lõi.
6.  **[6] Engine -> Model**: Các Engine thao tác trên các thực thể hoặc cấu trúc dữ liệu cơ bản.
7.  **[7, 8, 9] Truy cập Models**: Các tầng View, ViewModel và Manager được phép đọc thông tin từ các thực thể SwiftData (`Book`, `Chapter`) để phục vụ hiển thị hoặc lưu trữ.

---

## 2. Các mối quan hệ cấm kỵ (Forbidden Dependencies)

Để tránh rò rỉ bộ nhớ, lỗi thread-safety và lỗi phá hỏng cấu trúc Clean Architecture, các mối quan hệ sau **tuyệt đối bị cấm**:

### 2.1. Tầng Manager / Service -> Tầng View (Ngược chiều kiến trúc)
*   **Mô tả**: Các lớp Service hoặc Manager không được phép import `SwiftUI` hoặc giữ bất kỳ tham chiếu nào đến SwiftUI Views.
*   **Lý do**: Phá hỏng tính độc lập của logic nghiệp vụ, gây khó khăn cho việc viết Unit Test và có nguy cơ rò rỉ bộ nhớ rất cao khi giữ tham chiếu đến View.
*   *Quy tắc*: Giao tiếp ngược từ Manager lên View chỉ được thực hiện thông qua cơ chế Reactive (Combine `@Published` properties hoặc Notification Center).

### 2.2. Tầng View -> Tầng Repository / Database trực tiếp (Bỏ qua ViewModel/Manager)
*   **Mô tả**: View không được tự ý gọi trực tiếp các lệnh sửa đổi database hoặc lưu trữ tiến trình qua Repository. Mọi hành động ghi đĩa phải đi qua ViewModel hoặc Manager.
*   **Lý do**: View chỉ phụ trách hiển thị. Nếu để View tự ghi đĩa, logic lưu trữ sẽ bị phân mảnh, khó bảo trì và dễ gây xung đột ghi đồng thời trên nhiều View.
*   *Trường hợp ngoại lệ*: SwiftUI `@Query` được phép truy vấn trực tiếp danh sách Book/Chapter hiển thị lên View (đọc dữ liệu), nhưng hành động ghi dữ liệu phải đi qua context do ViewModel/Manager quản lý.

### 2.3. Tầng Model -> Tầng Service / ViewModel / View
*   **Mô tả**: Các thực thể SwiftData (`Book`, `Chapter`, `Extension`) hoặc cấu trúc dữ liệu (`DoubleArrayTrie`) phải là các lớp thuần dữ liệu. Chúng không được phép gọi Service, ViewModel hoặc View.
*   **Lý do**: Thực thể dữ liệu nằm ở nhân trong cùng của kiến trúc, chúng không được biết bất kỳ thông tin nào về cách ứng dụng vận hành ở bên ngoài.

### 2.4. Tầng Utilities -> Tầng View / ViewModel
*   **Mô tả**: Các file trong `Common/Extensions` là các hàm bổ trợ thuần túy. Chúng không được import SwiftUI hoặc gọi ViewModel.
<!-- GENERATED END -->
