import Foundation

public final class AppLogger {
    public static let shared = AppLogger()
    
    public var isLoggingEnabled: Bool {
        get {
            // Mặc định là true nếu chưa cấu hình
            if UserDefaults.standard.object(forKey: "isLoggingEnabled") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "isLoggingEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isLoggingEnabled")
        }
    }
    
    public var isCompactSuccessLogEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "isCompactSuccessLogEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isCompactSuccessLogEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isCompactSuccessLogEnabled")
        }
    }

    public var isTTSVerboseLoggingEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "isTTSVerboseLoggingEnabled") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "isTTSVerboseLoggingEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isTTSVerboseLoggingEnabled")
        }
    }

    // Một formatter dùng chung thay vì tạo DateFormatter mỗi dòng; chỉ dùng trên `queue`.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Mọi thao tác trên file log chạy tuần tự trên queue nền này: luồng gọi (kể cả main) chỉ dựng chuỗi
    /// rồi đi tiếp, không chờ ghi đĩa. Đổi lại, app crash có thể mất vài dòng cuối chưa kịp ghi.
    private let queue = DispatchQueue(label: "FreeBook.AppLogger", qos: .utility)
    // Handle của `app_logs.txt`, mở một lần rồi giữ suốt phiên (chỉ truy cập trên `queue`): mở lại cần fd mới,
    // mà lúc tiến trình đã cạn fd thì mở lại hỏng âm thầm và mọi dòng log sau đó mất.
    private var fileHandle: FileHandle?
    // Số byte của file đang ghi, để biết lúc xoay vòng (chỉ truy cập trên `queue`).
    private var currentFileSize: UInt64 = 0

    private init() {
        // Tự động tắt ghi log hệ thống khi khởi chạy lại ứng dụng
        UserDefaults.standard.set(false, forKey: "isLoggingEnabled")
    }

    // Công tắc log tắt thì vẫn ghi **dòng lỗi** (chứa "❌") để lỗi xảy ra lúc chưa bật log còn dấu vết;
    // muốn một dòng luôn được ghi thì đánh dấu ❌. Vì vậy chuỗi luôn được dựng ra mới biết có phải dòng lỗi.
    public func log(_ message: @autoclosure () -> String) {
        let text = message()
        guard isLoggingEnabled || text.contains("❌") else { return }
        enqueue(text, at: Date())
    }

    /// Ghi một dòng **bất kể công tắc log** — chỉ dành cho `FileDescriptorCensus` (~1 dòng mỗi chương).
    public func logAlways(_ message: String) {
        enqueue(message, at: Date())
    }

    /// Thời điểm lấy ở luồng gọi; định dạng, in console và ghi file làm trên `queue`.
    private func enqueue(_ text: String, at date: Date) {
        queue.async {
            let logLine = "[\(Self.timestampFormatter.string(from: date))] \(text)\n"
            print(logLine, terminator: "")
            self.appendOnQueue(Data(logLine.utf8))
        }
    }

    private func appendOnQueue(_ data: Data) {
        if fileHandle == nil {
            openCurrentFileOnQueue()
        }
        guard let handle = fileHandle else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            currentFileSize += UInt64(data.count)
        } catch {
            // Handle hỏng: bỏ đi để lần ghi sau mở lại.
            closeFileHandleOnQueue()
            return
        }
        if currentFileSize >= AppLogFiles.maxFileBytes {
            rotateOnQueue()
        }
    }

    private func openCurrentFileOnQueue() {
        let url = AppLogFiles.currentURL
        if !FileManager.default.fileExists(atPath: url.path) {
            // File chưa có: tạo rỗng rồi mở handle luôn, để ngay dòng đầu đã giữ được handle.
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        // `forUpdating` (đọc + ghi) để `readLogContents` đọc qua chính handle này, không cần fd mới.
        fileHandle = try? FileHandle(forUpdating: url)
        // Phép thử chẩn đoán rò fd: fd thiếu FD_CLOEXEC có bị nhân bản theo nhóm hay không (xem FileDescriptorCensus).
        if let descriptor = fileHandle?.fileDescriptor {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
        currentFileSize = (try? fileHandle?.seekToEnd()) ?? 0
    }

    /// File đang ghi đủ lớn ⇒ đẩy nó thành `app_logs.1.txt` rồi mở `app_logs.txt` mới. Nếu không mở nổi file
    /// mới (vd đã cạn fd) thì trả file đang ghi về lại tên `app_logs.txt` (đổi tên không cần fd) và ghi tiếp
    /// qua handle cũ: handle **luôn** trỏ file hiện hành, nên lần xoay sau hay "Xóa tất cả" không bao giờ
    /// xoá nhầm chính file đang ghi. Chỉ thử xoay lại sau thêm `maxFileBytes`.
    private func rotateOnQueue() {
        let previousHandle = fileHandle
        guard AppLogFiles.shiftForRotation() else {
            // Không đổi tên được: handle vẫn ở `app_logs.txt`, cứ ghi tiếp và thử lại sau.
            currentFileSize = 0
            return
        }
        openCurrentFileOnQueue()
        if fileHandle == nil {
            try? FileManager.default.removeItem(at: AppLogFiles.currentURL)
            try? FileManager.default.moveItem(at: AppLogFiles.archiveURL(1), to: AppLogFiles.currentURL)
            fileHandle = previousHandle
        } else {
            try? previousHandle?.close()
        }
        currentFileSize = 0
    }

    private func closeFileHandleOnQueue() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    public func logTTSVerbose(_ message: @autoclosure () -> String) {
        guard isLoggingEnabled && isTTSVerboseLoggingEnabled else { return }
        log(message())
    }

    /// Xoá **tất cả** file log. File đang ghi được cắt về 0 qua handle đang giữ (không cần fd mới).
    public func clear() {
        queue.sync {
            AppLogFiles.removeArchives()
            if let handle = fileHandle, (try? handle.truncate(atOffset: 0)) != nil {
                currentFileSize = 0
                return
            }
            closeFileHandleOnQueue()
            try? FileManager.default.removeItem(at: AppLogFiles.currentURL)
        }
    }

    /// File đang ghi (`app_logs.txt`).
    public func getLogFileUrl() -> URL {
        AppLogFiles.currentURL
    }

    /// Mọi file log đang có, mới nhất trước — dùng để xuất tất cả.
    public func logFileUrls() -> [URL] {
        AppLogFiles.existingURLs()
    }

    /// Kích thước file đang ghi. Đọc thẳng `stat` (không cần fd, không chờ queue) vì có thể bị gọi lúc dựng view.
    public var logFileSize: UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: AppLogFiles.currentURL.path)
        return (attributes?[.size] as? UInt64) ?? 0
    }

    /// Nội dung file đang ghi, đọc qua chính handle đang giữ (vẫn đọc được khi đã cạn fd).
    public func readLogContents() -> String {
        queue.sync {
            if let handle = fileHandle,
               (try? handle.seek(toOffset: 0)) != nil,
               let data = try? handle.readToEnd() {
                return String(decoding: data, as: UTF8.self)
            }
            return (try? String(contentsOf: AppLogFiles.currentURL, encoding: .utf8)) ?? ""
        }
    }
}

// MARK: - AppDiagnostics
public final class AppDiagnostics: ObservableObject {
    public static let shared = AppDiagnostics()
    
    @Published public var lastCall: CallInfo? = nil
    
    private init() {}
    
    public struct CallInfo: Identifiable {
        public let id = UUID()
        public let timestamp = Date()
        public let action: String
        public let input: String
        public let status: String
        public let details: String
    }
}
