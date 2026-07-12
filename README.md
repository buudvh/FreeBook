# FreeBook (Tàng Công Các)

FreeBook (Tàng Công Các) là một ứng dụng đọc sách và đọc truyện chữ miễn phí trên nền tảng iOS, được thiết kế tinh gọn nhưng sở hữu nhiều tính năng mạnh mẽ nhằm mang lại trải nghiệm đọc sách tối ưu cho người dùng.

## 🚀 Các Tính Năng Nổi Bật

1. **VBook Extensions Integration**:
   - Tích hợp công cụ JavaScript Core Runtime cho phép cài đặt và chạy các extension (plugin) để cào dữ liệu truyện từ nhiều nguồn trang web khác nhau.
   - Quản lý kho extension linh hoạt, hỗ trợ đồng bộ hóa kho lưu trữ trực tuyến (repository sync).

2. **Dịch Thuật Tự Động (VietPhrase)**:
   - Tích hợp bộ dịch thuật tự động sử dụng kho dữ liệu từ điển VietPhrase phục vụ cho việc đọc truyện convert, dịch thô từ tiếng Trung sang tiếng Việt một cách mượt mà và dễ hiểu.
   - Hỗ trợ tra từ điển trực tiếp ngay trên trang đọc truyện để xem nghĩa Hán Việt, VietPhrase và nghĩa chi tiết.

3. **Đọc Thành Tiếng Offline (NghiTTS / Piper)**:
   - Hỗ trợ công cụ đọc văn bản thành giọng nói (TTS) chất lượng cao hoàn toàn offline trên thiết bị.
   - Sử dụng lõi công nghệ **Piper** chạy mô hình định dạng **ONNX Runtime** giúp phát âm tiếng Việt tự nhiên với các giọng đọc truyền cảm (như giọng Ngọc Huyền, v.v.).
   - Bộ tiền xử lý văn bản (`Preprocessing`) thông minh giúp xử lý chuyển đổi chữ số, từ viết tắt và chuẩn hóa phát âm trước khi tổng hợp âm thanh.

4. **Trình Đọc Tiện Lợi**:
   - Tùy chỉnh giao diện đọc truyện (cỡ chữ, giãn dòng, màu nền, font chữ).
   - Widget nổi điều khiển TTS (`TTSFloatingWidgetView`) giúp quản lý luồng phát (play, pause, chuyển câu) trực tiếp trên trang đọc mà không che khuất nội dung.

---

## 📂 Cơ Cấu Thư Mục Dự Án

Mã nguồn được tổ chức sạch sẽ và mô-đun hóa cao dưới thư mục `Sources/`:

* **`Sources/Common/`**: Chứa các thành phần dùng chung hệ thống.
  - `Extensions/`: Các phần mở rộng hữu ích (`String+HTML.swift`, `View+Keyboard.swift`, `String+Crypto.swift`).
  - `Services/`: Các dịch vụ cốt lõi toàn cục (`ImageCacheManager.swift`, `ToastManager.swift`).
* **`Sources/Models/`**: Các thực thể dữ liệu của ứng dụng.
  - `Database/`: Các thực thể SwiftData được lưu trữ (`Book`, `Chapter`, `Extension`, `Repository`).
  - `Dictionaries/`: Các cấu trúc dữ liệu tra từ điển hiệu năng cao (`DoubleArrayTrie`, `TextDictionary`, `SearchEngine`).
* **`Sources/Views/`**: Giao diện người dùng SwiftUI được chia theo các màn hình và module độc lập.
  - `Shelf/ShelfMain/`: Màn hình kệ sách chính (`ShelfView.swift`).
  - `BookDetail/`: Màn hình chi tiết truyện và danh sách chương.
  - `Reader/`: Trình đọc truyện chính và hiển thị trang chữ.
  - `TTSWidget/`: Widget nổi điều khiển phát TTS.
  - `Dictionary/`: Giao diện tra cứu và quản lý từ điển.
  - `Download/`: Màn hình theo dõi tiến trình tải truyện ngoại tuyến.
  - `Discovery/`: Giao diện tab khám phá để tìm truyện từ các nguồn extension.
  - `Extensions/`: Giao diện quản lý, cấu hình và cửa hàng extension.
  - `Settings/`: Giao diện cấu hình chung, quản lý từ điển phát âm và tải mô hình TTS.
  - `Common/`: Các view dùng chung (`BypassWebView.swift` để vượt tường lửa Cloudflare, `DocumentPicker.swift`...).
* **`Sources/Services/`**: Các dịch vụ thực thi logic nghiệp vụ.
  - `TTS/`: Quản lý TTS chung và 3 engine con: `NghiTTS/` (Piper offline), `Siri/` (Native iOS), `Ext/` (JS Extension).
  - `Extensions/`: Trình biên dịch và quản lý JS Extension.
  - `Translation/`: Quản lý dịch thuật tự động VietPhrase.
  - `Download/`: Quản lý tác vụ tải chương truyện chạy ngầm.
  - `Logging/`: Nhật ký hệ thống ghi ra file (`AppLogger.swift`).

---

## 🛠️ Thiết Lập & Build Dự Án

Dự án này sử dụng công cụ **XcodeGen** để cấu hình và quản lý file dự án Xcode (`.xcodeproj`).

### Yêu cầu hệ thống
- Máy Mac cài đặt **macOS** (để build ứng dụng) hoặc môi trường **GitHub Actions CI**.
- **Xcode 15.0** trở lên.
- **XcodeGen** (cài đặt qua Homebrew: `brew install xcodegen`).

### Các bước thiết lập
1. Mở Terminal tại thư mục gốc của dự án.
2. Chạy lệnh sau để tự động quét thư mục `Sources/` và tạo dự án Xcode từ file cấu hình `project.yml`:
   ```bash
   xcodegen generate
   ```
3. Sau khi lệnh chạy thành công, một file `FreeBook.xcodeproj` sẽ xuất hiện ở thư mục gốc.
4. Mở file `FreeBook.xcodeproj` bằng Xcode, chọn Target `FreeBook`, và tiến hành Build hoặc Run trên Simulator/Thiết bị thật.

*Lưu ý:* Các thư viện phụ thuộc (SwiftSoup, ZIPFoundation, ONNX Runtime, libespeak-ng-spm) được cấu hình dưới dạng Swift Package Manager trực tiếp trong `project.yml` và sẽ tự động được Xcode tải về khi nạp dự án.

---

## 📝 Quy Định Lập Trình & Đóng Góp

Mọi thay đổi trên codebase cần tuân thủ nghiêm ngặt các quy tắc lập trình, tổ chức file và các ràng buộc về runtime được quy định chi tiết tại:
👉 [Quy tắc lập trình của dự án (.agents/AGENTS.md)](.agents/AGENTS.md)
