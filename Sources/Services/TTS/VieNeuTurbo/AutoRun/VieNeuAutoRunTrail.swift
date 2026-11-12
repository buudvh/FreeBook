import Foundation

/// **Nhật ký từng bước** của "Đo tự động" (1.3.906) — sống sót khi app bị giết.
///
/// Lượt đo đầu trên máy (1.3.890) làm app sập mà không còn dấu vết: báo cáo chỉ ghi sau khi chuẩn bị xong, log thường
/// tắt mặc định, iOS giết app vì hết RAM thì không có dòng `❌` nào. File này ghi **trước** mỗi bước nặng (biên dịch từng
/// graph, nạp session, tự kiểm, mỗi lượt / mỗi phút) kèm RAM + nhiệt, mỗi dòng `synchronize` xuống đĩa. Lần mở màn thử
/// sau thấy dòng cuối không phải dấu kết thúc ⇒ "lần đo trước dừng đột ngột ở bước …" + chia sẻ được file.
///
/// Gọi được từ mọi luồng (bước chuẩn bị chạy ở `Task.detached`).
enum VieNeuAutoRunTrail {
    static let fileName = "do-tu-dong-nhat-ky.txt"
    static let endMarker = "⏹ kết thúc lượt đo"
    private static let lock = NSLock()

    static func url(in package: VieNeuCoreMLPackage) -> URL {
        package.resultsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Bắt đầu lượt mới: ghi đè file.
    static func reset(_ url: URL, header: String) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((header + "\n").utf8).write(to: url, options: .atomic)
    }

    /// Thêm một dòng "giờ · bước · RAM · nhiệt" rồi ép xuống đĩa.
    static func append(_ url: URL, _ step: String) {
        let memory = ProcessMemoryProbe.snapshot().summary
        let thermal = VieNeuTurboSoakStats.thermalName(ProcessInfo.processInfo.thermalState)
        let line = "\(timeFormatter.string(from: Date())) · \(step) · \(memory) · \(thermal)\n"
        lock.lock(); defer { lock.unlock() }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? Data(line.utf8).write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.synchronize()
    }

    /// Lượt trước dừng đột ngột (file có mà dòng cuối không phải dấu kết thúc) ⇒ vài dòng cuối; không thì `nil`.
    static func abruptEnding(_ url: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let last = lines.last, !last.contains(endMarker) else { return nil }
        return lines.suffix(3).joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
