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
    
    private var logFileUrl: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("app_logs.txt")
    }
    
    private init() {
        // Tự động xóa log cũ nếu file quá lớn (> 5MB) để tránh đầy bộ nhớ
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileUrl.path),
           let fileSize = attributes[.size] as? UInt64,
           fileSize > 5 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: logFileUrl)
        }
    }
    
    public func log(_ message: String) {
        guard isLoggingEnabled else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        // In ra Xcode console
        print(logLine, terminator: "")
        
        // Ghi vào file trên thiết bị
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileUrl.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileUrl) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileUrl, options: .atomic)
            }
        }
    }
    
    public func clear() {
        try? FileManager.default.removeItem(at: logFileUrl)
    }
    
    public func getLogFileUrl() -> URL {
        return logFileUrl
    }
    
    public var logFileSize: UInt64 {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileUrl.path),
           let fileSize = attributes[.size] as? UInt64 {
            return fileSize
        }
        return 0
    }
    
    public func readLogContents() -> String {
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
