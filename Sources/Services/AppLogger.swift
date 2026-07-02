import Foundation

public final class AppLogger {
    public static let shared = AppLogger()
    
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
}
