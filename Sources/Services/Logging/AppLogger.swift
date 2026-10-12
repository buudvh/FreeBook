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

    private var logFileUrl: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("app_logs.txt")
    }

    // Một formatter dùng chung thay vì tạo DateFormatter mỗi dòng; chỉ dùng khi giữ `fileLock`.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    // Khoá tuần tự hoá mọi thao tác trên file log để hai luồng không ghi đè byte của nhau.
    private let fileLock = NSLock()
    // Handle mở lười một lần rồi giữ lại; clear/đọc/đo kích thước đóng và nil nó để lần ghi sau mở/tạo lại.
    private var fileHandle: FileHandle?

    private init() {
        // Tự động tắt ghi log hệ thống khi khởi chạy lại ứng dụng
        UserDefaults.standard.set(false, forKey: "isLoggingEnabled")
        
        // File quá lớn (> 5MB) thì chỉ giữ 1MB cuối thay vì xoá hẳn: lần mở lại app ngay sau sự cố (vd cạn
        // file descriptor — chỉ tắt hẳn app mới hết) không được xoá mất đoạn log của chính sự cố đó.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileUrl.path),
           let fileSize = attributes[.size] as? UInt64,
           fileSize > 5 * 1024 * 1024 {
            let keepBytes: UInt64 = 1024 * 1024
            if let handle = try? FileHandle(forReadingFrom: logFileUrl),
               (try? handle.seek(toOffset: fileSize - keepBytes)) != nil,
               let tail = try? handle.readToEnd() {
                try? handle.close()
                try? tail.write(to: logFileUrl, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: logFileUrl)
            }
        }
    }
    
    // Công tắc log tắt thì vẫn ghi **dòng lỗi** (chứa "❌") để lỗi xảy ra lúc chưa bật log còn dấu vết;
    // muốn một dòng luôn được ghi thì đánh dấu ❌. Vì vậy chuỗi luôn được dựng ra mới biết có phải dòng lỗi.
    public func log(_ message: @autoclosure () -> String) {
        let text = message()
        guard isLoggingEnabled || text.contains("❌") else { return }

        fileLock.lock()
        defer { fileLock.unlock() }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(text)\n"

        // In ra Xcode console
        print(logLine, terminator: "")

        // Ghi vào file trên thiết bị (vẫn đồng bộ: crash vẫn giữ được dòng cuối)
        if let data = logLine.data(using: .utf8) {
            appendLocked(data)
        }
    }

    /// Ghi một dòng **bất kể công tắc log** — chỉ dành cho `FileDescriptorCensus` (~1 dòng mỗi chương).
    /// Lần ghi đầu ở lúc khởi động mở handle rồi giữ suốt phiên, nên khi tiến trình đã cạn file descriptor
    /// vẫn ghi được; bật log sau khi đã cạn thì không mở nổi file nữa.
    public func logAlways(_ message: String) {
        fileLock.lock()
        defer { fileLock.unlock() }

        let logLine = "[\(Self.timestampFormatter.string(from: Date()))] \(message)\n"
        print(logLine, terminator: "")
        if let data = logLine.data(using: .utf8) {
            appendLocked(data)
        }
    }

    /// Chỉ gọi khi đang giữ `fileLock`.
    private func appendLocked(_ data: Data) {
        if fileHandle == nil {
            if !FileManager.default.fileExists(atPath: logFileUrl.path) {
                // File chưa có: tạo rỗng rồi mở handle luôn, để ngay dòng đầu đã giữ được handle.
                FileManager.default.createFile(atPath: logFileUrl.path, contents: nil)
            }
            // `forUpdating` (đọc + ghi) để `readLogContents` đọc qua chính handle này, không cần fd mới.
            fileHandle = try? FileHandle(forUpdating: logFileUrl)
        }
        guard let handle = fileHandle else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Handle hỏng: bỏ đi để lần ghi sau mở lại.
            closeFileHandleLocked()
        }
    }

    /// Chỉ gọi khi đang giữ `fileLock`.
    private func closeFileHandleLocked() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    public func logTTSVerbose(_ message: @autoclosure () -> String) {
        guard isLoggingEnabled && isTTSVerboseLoggingEnabled else { return }
        log(message())
    }

    // clear / đo kích thước / đọc **không đóng** handle đang giữ: mở lại cần fd mới, mà lúc tiến trình đã cạn
    // fd thì mở lại hỏng âm thầm và mọi dòng log sau đó mất. Ghi qua handle là `write(2)` không đệm, nên
    // `stat` và đọc lại luôn thấy đủ dữ liệu.
    public func clear() {
        fileLock.lock()
        defer { fileLock.unlock() }
        if let handle = fileHandle, (try? handle.truncate(atOffset: 0)) != nil { return }
        closeFileHandleLocked()
        try? FileManager.default.removeItem(at: logFileUrl)
    }

    public func getLogFileUrl() -> URL {
        return logFileUrl
    }

    public var logFileSize: UInt64 {
        fileLock.lock()
        defer { fileLock.unlock() }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileUrl.path),
           let fileSize = attributes[.size] as? UInt64 {
            return fileSize
        }
        return 0
    }

    public func readLogContents() -> String {
        fileLock.lock()
        defer { fileLock.unlock() }
        if let handle = fileHandle,
           (try? handle.seek(toOffset: 0)) != nil,
           let data = try? handle.readToEnd() {
            return String(decoding: data, as: UTF8.self)
        }
        guard let contents = try? String(contentsOf: logFileUrl, encoding: .utf8) else {
            return ""
        }
        return contents
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
