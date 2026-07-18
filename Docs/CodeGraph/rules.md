---
generated_by: Antigravity
generator_version: 1.0
generated_at: 2026-07-17T23:26:29+07:00
git_commit: UNKNOWN
source_files: 93
document_version: 5
---

# Hướng dẫn Quy định Lập trình (Coding & Architecture Rules)

Tài liệu này tổng hợp các quy tắc lập trình, quy định bảo trì và kiến thức kỹ thuật chi tiết của dự án FreeBook.

## Ghi chú thủ công (Human Notes)
*Ghi chú thủ công của con người.*

<!-- GENERATED START -->
## Reader/TTS normalized-text invariants (1.3.15)

* `ChapterTextNormalizer` is the only component allowed to canonicalize chapter newlines, remove blank lines, assign paragraph IDs, and calculate UTF-16 ranges.
* `ChapterDocument` is created once by `ChapterContentRepository`; Reader and TTS builders must consume its normalized lines without re-splitting or re-numbering.
* TTS chunks may split a line but must retain the parent `ChapterTextLine.id`; replacement output must be non-empty before extension synthesis.
* TTS owns progress while playing. Reader snapshots are ignored during TTS ownership and all checkpoints flush through `ReadingProgressStore` off the MainActor.
* TOC navigation carries an immutable `ReaderRoute.chapterIndex`; filtering and sorting must never convert an original chapter index into a filtered-row offset.

## Reader paragraph invariants (1.3.14)

* Split original chapter content before translation. Each original line, including an empty or trailing line, must produce exactly one translated line and one `ParagraphItem` with the same stable index.
* All selection and translation offsets exchanged with UIKit must use UTF-16 `NSRange` semantics.
* The definition editor must resolve `chapterIndex + paragraph id` and use `ParagraphItem.original` as its only source text; translated text may only be used to map the selected range.
* Exact stored spans take precedence. The historical sentence/token heuristic is fallback-only when span coverage is missing or invalid.

## 1. Thứ tự Ưu tiên Thẩm quyền (Priority of Authority / Source of Truth Hierarchy)

Thứ tự ưu tiên thẩm quyền của tài liệu và mã nguồn khi xảy ra xung đột thông tin được định nghĩa theo cấp bậc sau:
1.  **`Docs/CodeGraph/rules.md`** (Normative Specification / The current approved technical specification. Unless explicitly changed by the user or project maintainers, AI must treat it as the authoritative technical standard).
2.  **`Source Code`** (Actual Implementation / Triển khai thực tế - những gì code đang thực thi).
3.  **`Docs/CodeGraph/*`** (Descriptive Documentation / Tài liệu mô tả - những gì tài liệu mô tả về mã nguồn).
4.  **Các tài liệu khác** (Other documentation).

> [!NOTE]
> **This authority order is only used to resolve conflicts between artifacts. It does not define the normal development workflow.**
> *(Thứ tự ưu tiên thẩm quyền này chỉ được sử dụng khi xảy ra xung đột giữa các tài liệu hoặc mã nguồn. Nó không định nghĩa hay thay thế quy trình phát triển thông thường).*

*   **Bản chất**: `rules.md` là tài liệu quy phạm (những gì dự án cần tuân thủ), trong khi `Docs/CodeGraph/*` là tài liệu mô tả (những gì mã nguồn đang thực thi hiện tại).
*   **Quy trình xử lý sai lệch (Deviation Handling)**: AI phải thực hiện quy trình sau khi phát hiện sự sai lệch:
    *   **Xác minh**: Kiểm tra xem sai lệch là **chủ ý thiết kế mới** (intentional change) hay là **lỗi lập trình** (stale/bug).
    *   **Lỗi / Sai lệch**: Tiến hành sửa đổi `Source Code` để tuân thủ quy chuẩn trong `rules.md`.
    *   **Quy tắc cũ / Thay đổi kiến trúc**: Cập nhật `rules.md` trước (chỉ khi bản thân quy chuẩn kỹ thuật của dự án thay đổi) để ghi nhận quy tắc mới $\rightarrow$ Đồng bộ `Source Code` (nếu cần) $\rightarrow$ Cập nhật `Docs/CodeGraph/*` tương ứng để phản ánh trạng thái thực tế mới.
    *   **Yêu cầu trực tiếp từ người dùng (User-directed change)**: Nếu người dùng hoặc maintainer yêu cầu thay đổi tính năng, kiến trúc hoặc quy tắc (chỉ áp dụng khi yêu cầu của người dùng có sửa code):
        1. Thực hiện thay đổi theo yêu cầu trên **Source Code**.
        2. Đánh giá xem thay đổi đó có làm thay đổi quy chuẩn của dự án (**`rules.md`**) hay không.
        3. Nếu có, cập nhật **`rules.md`**.
        4. Cuối cùng cập nhật **`Docs/CodeGraph/*`** để phản ánh trạng thái mới.
    *   **Trường hợp không rõ (UNKNOWN)**: Nếu AI không đủ bằng chứng để xác định liệu sai lệch là chủ ý hay lỗi, **bắt buộc phải đánh dấu UNKNOWN** và yêu cầu người dùng xác nhận thay vì tự suy đoán.
    *   **Không tự ý sửa**: Tuyệt đối không tự ý sửa `Source Code` chỉ để khớp với `rules.md` khi chưa xác minh `rules.md` vẫn là quy tắc hiện hành.

*   **Lưu ý**: Đa số các tính năng thông thường (ordinary features) không cần sửa `rules.md`.

*   **Ví dụ minh họa (Examples)**:
    *   *Code khác CodeGraph* $\rightarrow$ Cập nhật CodeGraph.
    *   *Code khác rules.md vì rules.md cũ* $\rightarrow$ 1. Cập nhật rules.md; 2. Đồng bộ Source Code (nếu cần); 3. Cập nhật Docs/CodeGraph/* để phản ánh trạng thái mới.
    *   *Code khác rules.md do bug* $\rightarrow$ Sửa Source Code để tuân thủ rules.md.
    *   *Người dùng yêu cầu thay đổi tính năng/kiến trúc* $\rightarrow$ 1. Sửa Source Code; 2. Đánh giá và cập nhật rules.md (nếu đổi quy chuẩn); 3. Cập nhật Docs/CodeGraph/*.

---

## 2. Quy tắc Bảo trì CodeGraph (Maintenance Rules)

*   **Không tạo lại toàn bộ (No Full Regeneration)**: Chỉ phân tích và chỉnh sửa các tài liệu bị ảnh hưởng trực tiếp bởi thay đổi code. Giữ nguyên các tài liệu khác.
*   **Bảo vệ ghi chú của con người (Preserve Human Edits)**:
    *   Mọi nội dung tự động sinh bởi AI nằm trong khối comment bắt đầu bằng `GENERATED_START` và kết thúc bằng `GENERATED_END` (không chứa khoảng trắng để tránh xung đột parser).
    *   AI chỉ được phép chỉnh sửa nội dung bên trong vùng này.
    *   **Tuyệt đối không** ghi đè, xóa hoặc sửa đổi bất kỳ nội dung nào nằm ngoài vùng này.
*   **Đồng bộ khi Rename / Delete / Move file**:
    *   If a Swift file is renamed, moved, or deleted, the AI must update all relative path references in `Docs/CodeGraph/` and remove orphan references.

---

## 3. Quy tắc Kích hoạt Cập nhật (Trigger Rules)

CodeGraph bắt buộc phải được đồng bộ hóa lập tức khi có bất kỳ thay đổi nào sau đây:
*   Thêm file mới, xóa file hoặc di chuyển/đổi tên file Swift.
*   Thay đổi Public API của các Manager, Service, hoặc ViewModel.
*   Thay đổi định nghĩa Protocol.
*   Thay đổi mối quan hệ phụ thuộc (Dependency) giữa các thành phần.
*   Thay đổi Máy trạng thái (State Machine) điều khiển TTS, Tải xuống, hoặc Đọc truyện.
*   Thay đổi quan hệ sở hữu đối tượng (Ownership Graph).
*   Thay đổi luồng điều hướng màn hình (Navigation).
*   Thay đổi cấu trúc mô hình SwiftData (`@Model`).
*   Thay đổi cấu hình Audio Pipeline (`AVAudioEngine`, `AVAudioSession`) hoặc TTS Pipeline.

---

## 4. Kiến thức Dự án & Cấu trúc Thư mục (Project Knowledge)

### 4.1. Cấu trúc thư mục mã nguồn
Dự án FreeBook được tổ chức theo cấu trúc phân tầng nghiêm ngặt:
*   **Common (`Sources/Common`)**: Chứa các thành phần dùng chung cho toàn dự án.
    *   `Extensions/`: Các phần mở rộng (Extensions/Helpers) dùng chung (`String+HTML.swift`, `View+Keyboard.swift`, `String+Crypto.swift`...).
    *   `Services/`: Các Service/Manager dùng chung cho toàn bộ ứng dụng (`ImageCacheManager.swift`, `ToastManager.swift`...).
*   **Models (`Sources/Models`)**:
    *   `Database/`: All SwiftData persistable model classes (`Book`, `Chapter`, `Extension`, `Repository`).
    *   `Dictionaries/`: All translation lookup data structure classes (`DoubleArrayTrie`, `TextDictionary`, `SearchEngine`).
*   **Views (`Sources/Views`)**: Tổ chức thành các thư mục con theo module chức năng độc lập:
    *   `Shelf/ShelfMain/`: Chỉ chứa kệ sách chính (`ShelfView.swift`).
    *   `Discovery/`: Tab Khám phá (`DiscoveryView.swift`).
    *   `BookDetail/`: Chi tiết sách (`BookDetailView.swift`).
    *   `Search/`: Tìm kiếm truyện (`SearchView.swift`).
    *   `Reader/`: Trình đọc truyện (`ReaderView.swift` và các view phụ trợ).
    *   `TTSWidget/`: Floating widget điều khiển giọng đọc trên trình đọc.
    *   `Dictionary/`: Tra cứu từ điển (`DictionaryHubView.swift`, `DictionaryListView.swift`...).
    *   `Download/`: Quản lý tiến trình tải sách (`DownloadTrackerView.swift`, `TaskOptionsSheet.swift`).
    *   `Extensions/`: Quản lý extension, chia làm các thư mục con `Config/`, `Store/`, `Manager/`.
    *   `Settings/`: Cấu hình hệ thống, chia làm các thư mục con `Main/`, `Search/`, `TTS/`.
    *   `Common/`: Các view phụ trợ dùng chung (`BypassWebView.swift`, `DocumentPicker.swift`, `BookCoverView.swift`...).
*   **Services (`Sources/Services`)**: Tổ chức thành các thư mục con theo mảng dịch vụ chức năng:
    *   `TTS/`: Dịch vụ phát âm TTS.
        *   Thư mục gốc `TTS/`: Các bộ điều khiển và định nghĩa dùng chung (`TTSManager.swift`, `EspeakPhonemizer.swift`, `WAVEncoder`...) và thư mục `Preprocessing/`.
        *   `NghiTTS/`: Chứa client NghiTTS và lõi Piper offline (`ONNXPiperEngine.swift`, `PiperTTSService.swift`, `ModelStore.swift`).
        *   `Siri/`: Chứa dịch vụ phát âm native Siri (`SiriTTSService.swift`).
        *   `Ext/`: Chứa dịch vụ phát âm qua Extension JS (`ExtTTSService.swift`).
    *   `Extensions/`: Engine chạy extension javascript.
        *   `Engine/`: Core thực thi JS (`JSExecutor.swift`, `JSDom.swift`, `JSCrypto.swift`).
        *   `Manager/`: `ExtensionManager.swift`.
    *   `Translation/`: Dịch thuật tự động.
        *   `Manager/`: `TranslationManager.swift`.
        *   `Utils/`: `TranslateUtils.swift`, `DictionaryCache.swift`.
    *   `Download/`: `DownloadManager.swift`.
    *   `Logging/`: `AppLogger.swift`.

### 4.2. JavaScript Core Runtime & VBook Extensions Integration
*   **Script Entrypoint**: Tên hàm bắt đầu thực thi bên trong toàn bộ các tệp JavaScript (`search.js`, `detail.js`, `toc.js`, `chap.js`, `genre.js`, `home.js`) phải là `execute(...)`, được gọi bất đồng bộ qua `runAsync` trong `ExtensionManager.swift`.
*   **Script File Path Resolution**: Các tệp JS script có thể đặt ở thư mục gốc của extension hoặc trong thư mục `src/`. `ExtensionManager` sẽ quét cả hai vị trí này.
*   **Injected Global JS Objects**: Các đối tượng global được inject vào `JSContext`:
    *   `Html`: Parser cầu nối DOM (`Html.parse(...)`).
    *   `console`: Chuyển hướng `console.log` ra console in logs.
    *   `fetch`: API tải mạng bất đồng bộ.
    *   `Response`: `Response.success(data)` và `Response.error(message)`.
    *   `Engine`: Headless browser giả lập đồng bộ (`Engine.newBrowser()`).

---

## 5. Các Quy định Lập trình chi tiết (Coding Rules)

### 5.1. SwiftData Rules
*   **Tên**: Không sử dụng bộ lọc chuỗi trên Predicate trong `@Query`
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Tránh viết các câu lệnh truy vấn lọc chuỗi trực tiếp trong Predicate của SwiftUI `@Query`. Thay vào đó, hãy query toàn bộ danh sách và thực hiện lọc trên RAM bằng computed property.
*   **Lý do**: Bộ dịch truy vấn SQLite của SwiftData trên iOS 17 gặp lỗi dịch câu lệnh chuỗi gây ra kết quả không chính xác hoặc lỗi biên dịch.
*   **Ví dụ đúng**:
    ```swift
    @Query private var allExtensions: [Extension]
    private var activeExtensions: [Extension] {
        allExtensions.filter { !$0.localPath.isEmpty && $0.isEnabled }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    @Query(filter: #Predicate<Extension> { !$0.localPath.isEmpty && $0.isEnabled })
    private var activeExtensions: [Extension]
    ```

### 5.2. Architecture Rules
*   **Tên**: Không import SwiftUI vào các lớp nghiệp vụ Manager / Service
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Tầng Manager và Service tuyệt đối không được import framework `SwiftUI` hay giữ tham chiếu đến giao diện (View).
*   **Lý do**: Đảm bảo tính độc lập của logic nghiệp vụ, phục vụ unit testing dễ dàng và ngăn chặn rò rỉ bộ nhớ.
*   **Ví dụ đúng**:
    ```swift
    // Trong Sources/Services/Translation/Manager/TranslationManager.swift
    import Foundation
    public final class TranslationManager: ObservableObject { ... }
    ```
*   **Ví dụ sai**:
    ```swift
    import SwiftUI
    public final class TranslationManager: ObservableObject {
        var statusLabelView: Text? // Vi phạm kiến trúc
    }
    ```

### 5.3. Concurrency Rules
*   **Tên**: Sử dụng ModelContext riêng biệt cho tác vụ chạy nền (Background Tasks)
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Mọi thao tác ghi hoặc cập nhật thực thể SwiftData trong các tác vụ nền phải tạo một `ModelContext` mới từ `ModelContainer` dùng chung và không dùng chung context với MainActor.
*   **Lý do**: Tránh lỗi tranh chấp dữ liệu và lỗi crash truy cập sai luồng của SwiftData.
*   **Ví dụ đúng**:
    ```swift
    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let bgContext = ModelContext(container)
        let allBooks = (try? bgContext.fetch(FetchDescriptor<Book>())) ?? []
        try? bgContext.save()
    }
    ```
*   **Ví dụ sai**:
    ```swift
    private func executeTask(_ task: DownloadTask, container: ModelContainer) async {
        let allBooks = (try? viewModel.modelContext.fetch(FetchDescriptor<Book>())) ?? []
        try? viewModel.modelContext.save()
    }
    ```

### 5.4. SwiftUI Rules
*   **Tên**: Lưu bookmark tiến độ đọc truyện khẩn cấp khi chuyển nền
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: View chính của trình đọc phải lắng nghe sự kiện thay đổi trạng thái của app (`scenePhase == .background`) để lưu bookmark vị trí đọc hiện tại ngay lập tức.
*   **Lý do**: Hệ điều hành iOS có thể chấm dứt ứng dụng chạy ngầm bất cứ lúc nào để giải phóng RAM, gây mất bookmark của người đọc nếu không lưu kịp thời.
*   **Ví dụ đúng**:
    ```swift
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .background {
            viewModel?.saveProgressImmediately()
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    .onDisappear {
        viewModel?.saveProgressImmediately()
    }
    ```

### 5.5. Audio Rules
*   **Tên**: Tránh chặn Main Thread bằng Semaphore khi tải WebView ngầm
*   **Loại quy tắc**: **Recommended Rule**
*   **Mô tả**: Không sử dụng `DispatchSemaphore` chờ đồng bộ trên Main Thread khi chạy `WKWebView` để bypass Cloudflare hoặc nạp web động.
*   **Lý do**: Gây hiện tượng Deadlock vĩnh viễn vì WKWebView yêu cầu chạy trên Main Thread nhưng Main Thread lại bị Semaphore khóa cứng.
*   **Ví dụ đúng**:
    ```swift
    func loadWebView(url: URL) async -> String {
        return await withCheckedContinuation { continuation in
            loader.load(url: url) { html in
                continuation.resume(returning: html)
            }
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
        loader.load(url: url) { html in
            semaphore.signal()
        }
    }
    _ = semaphore.wait(timeout: .now() + 5.0) // Gây Deadlock vĩnh viễn trên Main Thread
    ```

### 5.6. TTS Rules
*   **Tên**: Dọn dẹp cửa sổ trượt prefetch WAV của đoạn văn
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Chỉ giữ buffer âm thanh PCM của đoạn hiện tại đang đọc (N) và đoạn tiếp theo (N+1) trong cache `preloadedWavs`.
*   **Lý do**: Buffer âm thanh PCM thô tiêu tốn rất nhiều bộ nhớ RAM, nếu không dọn dẹp sẽ gây crash app vì cạn bộ nhớ (OOM).
*   **Ví dụ đúng**:
    ```swift
    let cacheKeepIndices = [N, N + 1]
    for idx in preloadedWavs.keys {
        if !cacheKeepIndices.contains(idx) {
            preloadedWavs.removeValue(forKey: idx)
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    preloadedWavs[index] = buffer // Không bao giờ giải phóng
    ```

### 5.7. Extension Rules
*   **Tên**: Tạo thực thể JSExecutor ngắn hạn cho mỗi tác vụ bóc tách
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Mỗi lần chạy bóc tách phải khởi tạo một thực thể `JSExecutor` mới và giải phóng nó sau khi hoàn thành.
*   **Lý do**: Giải phóng hoàn toàn `JSContext` của JavaScriptCore sau mỗi lần chạy, ngăn rò rỉ bộ nhớ dài hạn của engine JS.
*   **Ví dụ đúng**:
    ```swift
    public func chap(url: String) async throws -> String {
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        return try await executor.runAsync(...)
    }
    ```
*   **Ví dụ sai**:
    ```swift
    public final class ExtensionManager {
        private let sharedExecutor = JSExecutor() // Gây rò rỉ bộ nhớ dài hạn
    }
    ```

### 5.8. Memory Rules
*   **Tên**: Tránh giữ strong reference `self` trong callback âm thanh ngầm
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Dùng `[weak self]` ở các callback schedule buffer hoặc các block xử lý luồng âm thanh ngầm.
*   **Lý do**: Tránh tạo ra strong reference cycle giữ chặt `TTSManager` hoặc View Model trong bộ nhớ RAM, gây rò rỉ bộ nhớ.
*   **Ví dụ đúng**:
    ```swift
    player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
        DispatchQueue.main.async {
            guard let self = self, self.isPlaying else { return }
            self.nextParagraph()
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    player.scheduleBuffer(buffer, at: nil, options: []) {
        self.nextParagraph()
    }
    ```

### 5.9. Logging Rules
*   **Tên**: Ghi log ngoại lệ chi tiết của JS Engine ra tệp logs
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Toàn bộ thông tin crash, exception của JS phải được lưu vào file `app_logs.txt` trong thư mục `Documents`.
*   **Lý do**: Nhà phát triển ứng dụng cài app qua LiveContainer test trực tiếp trên iOS vật lý, không thể debug qua Xcode Console.
*   **Ví dụ đúng**:
    ```swift
    context.exceptionHandler = { context, exception in
        let desc = exception?.toString() ?? ""
        AppLogger.shared.log("❌ JSContext Exception: \(desc)")
    }
    ```
*   **Ví dụ sai**:
    ```swift
    context.exceptionHandler = { context, exception in
        print("❌ JSContext Exception: \(exception)")
    }
    ```

### 5.10. Performance Rules
*   **Tên**: Giới hạn lưu tiến độ đọc (Debounce DB Save)
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Chỉ thực hiện lưu DB tiến độ khi người dùng dịch chuyển ít nhất 3 đoạn văn trở lên và áp dụng trì hoãn lưu 3 giây (`Task.sleep`).
*   **Lý do**: Giảm tần suất ghi đĩa I/O của SwiftData liên tục khi người đọc cuộn trang nhanh, tránh làm đơ/lag UI.
*   **Ví dụ đúng**:
    ```swift
    if abs(newProgress.paragraphIndex - last.paragraphIndex) >= 3 {
        dbSaveTask?.cancel()
        dbSaveTask = Task {
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            repository.saveProgress(newProgress)
        }
    }
    ```
*   **Ví dụ sai**:
    ```swift
    repository.saveProgress(newProgress)
    ```

### 5.11. Testing Rules
*   **Tên**: Kiểm tra chéo toàn bộ liên kết tài liệu phân tích (Cross Validation)
*   **Loại quy tắc**: **Recommended Rule**
*   **Mô tả**: Đảm bảo số lượng file quét trùng khớp với thư mục, không có markdown link bị hỏng, và tất cả UNKNOWN đều ghi rõ nguyên nhân.
*   **Lý do**: Tối ưu hóa bộ tài liệu phân tích để AI assistant có thể hiểu sâu sắc mà không bị đi vào các liên kết chết.
*   **Ví dụ đúng**: Chạy script quét link kiểm tra trước khi hoàn thiện tài liệu.
*   **Ví dụ sai**: Bỏ qua bước kiểm tra liên kết sau khi viết markdown.

### 5.12. Coding Rules
*   **Tên**: Save path plugin gốc vào `downloadUrl` khi đồng bộ repo
*   **Loại quy tắc**: **Observed Rule**
*   **Mô tả**: Lưu trực tiếp thuộc tính `path` từ `plugin.json` của repo vào `downloadUrl` của model `Extension`.
*   **Lý do**: Đảm bảo link tải zip của plugin chính xác và thống nhất.
*   **Ví dụ đúng**:
    ```swift
    extension.downloadUrl = item.path
    ```
*   **Ví dụ sai**:
    ```swift
    extension.downloadUrl = "https://raw.githubusercontent.com/.../plugin.zip"
    ```

---

## 6. Quy định mở rộng về Chất lượng Code (AI Expanded Policies)

### 6.1. Quy tắc Biên dịch & An toàn Concurrency (Compile & Concurrency Rules)
- **Compile Rule**: Mọi thay đổi mã nguồn phải cố gắng giữ khả năng biên dịch thành công của dự án. Tránh tuyệt đối các lỗi về thiếu ký hiệu (missing symbols), vi phạm Actor isolation (`@MainActor`), xử lý sai luồng SwiftData (phải dùng background context riêng) và vòng lặp tham chiếu mạnh (retain cycles/strong reference).
- **UNKNOWN Rule**: Khi xây dựng các đồ thị phân tích (Call Graph, State Machine, Ownership Graph, Dependency, Event Graph), nếu phương pháp phân tích tĩnh (static analysis) không thể chứng minh hoặc xác thực một mối quan hệ/đường gọi cụ thể (ví dụ: callback, dynamic dispatch, dynamic event), bắt buộc phải đánh dấu mối quan hệ đó là `UNKNOWN` hoặc `PARTIAL` kèm theo lý do cụ thể, tuyệt đối không được tự ý suy đoán dựa trên kinh nghiệm.

### 6.2. Quy trình Validation & CodeGraph Refresh Policy
- **Validation Failure Policy**: Chạy `python Docs/CodeGraph/validate_links.py`. Nếu kịch bản phát hiện bất kỳ lỗi nào (như tệp manifest không khớp, liên kết chết, sai định dạng front matter hoặc GENERATED comment), AI bắt buộc phải sửa lỗi và chạy lại; không được báo cáo hoàn thành khi validation chưa PASS 100%.
- **Manifest Hash Policy**: Sau thay đổi source hoặc vùng GENERATED, chạy validator với `--update-hashes`, sau đó chạy lại ở chế độ chỉ đọc. `sourceHash` là SHA-256 của chuỗi đường dẫn tương đối và nội dung source đã chuẩn hóa LF; `generatedHash` là SHA-256 của nội dung giữa cặp marker GENERATED đã chuẩn hóa LF.
- **Full CodeGraph Refresh Policy**: Khi phát sinh các thay đổi mang tính cấu trúc lớn, tái cấu trúc thư mục dự án hoặc chỉnh sửa đồng loạt trên khoảng 20 file mã nguồn Swift trở lên, AI phải đề xuất hoặc thực hiện làm mới toàn bộ hệ thống CodeGraph (Full CodeGraph Refresh) để đảm bảo tính đồng bộ hoàn toàn.

### 6.3. Thiết kế Kiến trúc & Tối ưu hóa Hiệu năng (Performance & Memory Rules)
- **Architecture Decision Rule**: Ưu tiên tối đa việc tái sử dụng các lớp Manager, Service và ViewModel sẵn có trong dự án (ví dụ: `TTSManager`, `ExtensionManager`, `DownloadManager`, `TranslationManager`). Tránh tạo ra duplicate logic hoặc tự ý xây dựng lại các kiến trúc thiết kế mới song song nếu không có yêu cầu cụ thể từ người dùng.
- **Logging Rule**: Mọi log runtime trong mã nguồn Swift hoặc engine JS phải sử dụng tiện ích `AppLogger` để ghi trực tiếp vào tệp logs `app_logs.txt` trong thư mục `Documents` của thiết bị. Không sử dụng hoặc phụ thuộc vào Xcode Console (do môi trường chạy thực tế là LiveContainer trên iOS vật lý không thể đính Xcode).
- **Performance & Memory Rules**:
  * Tránh khởi tạo lại thực thể `AVAudioEngine` nhiều lần không cần thiết.
  * Tránh truy vấn (fetch) SwiftData dư thừa; ưu tiên sử dụng RAM cache (`ChapterCache`, `bookDicts`).
  * Đảm bảo hủy các `Task` chạy ngầm ngắt quãng (`Task.sleep`, prefetch tasks), gỡ bỏ `NotificationCenter` observers khi View hoặc ViewModel deinit để triệt tiêu nguy cơ rò rỉ bộ nhớ (retain cycle).

---

## 7. Checklist Tự kiểm tra trước khi Hoàn thành (AI Review Checklist)

Trước khi kết thúc lượt và thông báo hoàn thành, AI bắt buộc phải tự đánh giá mã nguồn và tài liệu theo checklist sau:
- [ ] **Compile**: Mã nguồn sửa đổi biên dịch thành công, không vi phạm Actor isolation, không lỗi threading SwiftData?
- [ ] **Architecture**: Tái sử dụng components cũ tối đa, tránh tạo logic trùng lặp, giữ vững Clean Architecture?
- [ ] **Extension**: Giữ nguyên tính tương thích ngược, không đổi API của tiện ích mở rộng nếu không được yêu cầu?
- [ ] **TTS & Audio**: Dọn dẹp preloadedWavs RAM cache đoạn văn đúng cửa sổ trượt [N, N+1], tránh retain cycle?
- [ ] **CodeGraph**: Cập nhật chính xác các tài liệu bị ảnh hưởng trực tiếp bên trong thẻ `GENERATED`?
- [ ] **Validation**: Chạy kịch bản `validate_links.py` và PASS 100%, cập nhật manifest.json và CHANGELOG.md thành công?
<!-- GENERATED END -->
