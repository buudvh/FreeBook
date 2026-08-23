import Foundation

/// File tạm `.part` dùng chung cho mọi renderer: mở sẵn một `FileHandle`, ghi thẳng xuống đĩa, và chỉ
/// đổi tên sang đường dẫn đích khi `commit()` — nên tác vụ bị huỷ/lỗi không bao giờ để lại file hoàn
/// chỉnh giả trong `Documents/Exports/`.
///
/// Kế thừa nguyên tắc của bộ ghi TXT cũ (1.3.243) nhưng dùng lại được cho TXT, FB2, MOBI và cả bộ ghi
/// ZIP của EPUB.
final class ExportStagingFile {
    let targetURL: URL
    private let partURL: URL
    private let handle: FileHandle
    private var isClosed = false
    /// Số byte đã ghi — bộ ghi ZIP cần con số này làm offset của local file header.
    private(set) var bytesWritten: Int = 0
    /// Đã ghi được ký tự có nghĩa nào chưa (dùng cho `ExportRenderer.hasContent`).
    private(set) var didWriteNonWhitespace = false

    init(targetURL: URL) throws {
        self.targetURL = targetURL
        self.partURL = ExportFileNaming.stagingURL(for: targetURL)

        let fileManager = FileManager.default
        // File `.part` sót lại từ một lần xuất bị kill giữa đường không được cộng vào bản mới.
        if fileManager.fileExists(atPath: partURL.path) {
            try fileManager.removeItem(at: partURL)
        }
        guard fileManager.createFile(atPath: partURL.path, contents: nil) else {
            throw ExportRenderError.cannotCreateFile(partURL.path)
        }
        handle = try FileHandle(forWritingTo: partURL)
    }

    deinit {
        // Không đổi tên và cũng không xoá: `commit()`/`discard()` là nơi quyết định, đây chỉ nhả
        // file descriptor.
        try? handle.close()
    }

    func write(_ text: String) throws {
        try write(Data(text.utf8))
        if !didWriteNonWhitespace, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            didWriteNonWhitespace = true
        }
    }

    func write(_ data: Data) throws {
        guard !isClosed, !data.isEmpty else { return }
        try handle.write(contentsOf: data)
        bytesWritten += data.count
    }

    /// Đóng file tạm rồi đổi tên thành file đích.
    func commit() throws -> URL {
        closeIfNeeded()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.moveItem(at: partURL, to: targetURL)
        return targetURL
    }

    func discard() {
        closeIfNeeded()
        try? FileManager.default.removeItem(at: partURL)
    }

    private func closeIfNeeded() {
        guard !isClosed else { return }
        isClosed = true
        try? handle.close()
    }
}
