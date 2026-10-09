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
        
        // Tự động xóa log cũ nếu file quá lớn (> 5MB) để tránh đầy bộ nhớ
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileUrl.path),
           let fileSize = attributes[.size] as? UInt64,
           fileSize > 5 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: logFileUrl)
        }
    }
    
    // `@autoclosure`: chuỗi log chỉ được dựng sau khi kiểm tra cờ bật log.
    public func log(_ message: @autoclosure () -> String) {
        guard isLoggingEnabled else { return }
        let text = message()

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

    /// Chỉ gọi khi đang giữ `fileLock`.
    private func appendLocked(_ data: Data) {
        if fileHandle == nil {
            guard FileManager.default.fileExists(atPath: logFileUrl.path) else {
                // File chưa có: tạo mới như trước, lần ghi sau sẽ mở handle.
                try? data.write(to: logFileUrl, options: .atomic)
                return
            }
            fileHandle = try? FileHandle(forWritingTo: logFileUrl)
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

    public func clear() {
        fileLock.lock()
        defer { fileLock.unlock() }
        closeFileHandleLocked()
        try? FileManager.default.removeItem(at: logFileUrl)
    }

    public func getLogFileUrl() -> URL {
        return logFileUrl
    }

    public var logFileSize: UInt64 {
        fileLock.lock()
        defer { fileLock.unlock() }
        closeFileHandleLocked()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileUrl.path),
           let fileSize = attributes[.size] as? UInt64 {
            return fileSize
        }
        return 0
    }
    
    public func readLogContents() -> String {
        fileLock.lock()
        defer { fileLock.unlock() }
        closeFileHandleLocked()
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
