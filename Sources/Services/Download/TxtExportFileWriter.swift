import Foundation

/// Ghi dần bản xuất TXT của một truyện ra `Documents/Exports/`.
///
/// Trước đây `DownloadManager.executeTask` cộng dồn toàn bộ bản xuất vào một `String` rồi mới ghi một lần ở cuối:
/// truyện vài nghìn chương ⇒ chuỗi bị realloc liên tục và đỉnh RAM bằng cả file. Writer này giữ một `FileHandle`
/// mở sẵn trên file tạm `<tên>.txt.part`, mỗi chương ghi thẳng xuống đĩa nên bộ nhớ phẳng; chỉ khi `finish()`
/// mới đổi tên thành `<tên>.txt`, nhờ đó tác vụ bị huỷ/lỗi không bao giờ để lại file `.txt` dở dang.
public final class TxtExportFileWriter {
    /// Chuỗi phân tách giữa hai chương, giữ đúng như bộ đệm chuỗi cũ.
    private static let chapterSeparator = "\n\n"

    /// Đường dẫn cuối cùng người dùng nhận được (chỉ tồn tại sau `finish()`).
    public let targetURL: URL

    private let partURL: URL
    private let handle: FileHandle
    private var isClosed = false
    /// Đã ghi được byte nào chưa — quyết định có chèn dấu phân tách trước chương kế tiếp.
    private var didWriteAnyBytes = false
    /// Đã ghi được ký tự có nghĩa nào chưa — thay cho `txtAccumulator.trimmingCharacters(...).isEmpty` cũ.
    private var didWriteNonWhitespace = false

    public init(bookTitle: String) throws {
        let fileManager = FileManager.default
        let exportDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let sanitizedTitle = bookTitle.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
        targetURL = exportDir.appendingPathComponent("\(sanitizedTitle).txt")
        partURL = exportDir.appendingPathComponent("\(sanitizedTitle).txt.part")

        // File `.part` sót lại từ một lần xuất bị kill giữa đường không được cộng vào bản mới.
        if fileManager.fileExists(atPath: partURL.path) {
            try fileManager.removeItem(at: partURL)
        }
        guard fileManager.createFile(atPath: partURL.path, contents: nil) else {
            throw NSError(
                domain: "TxtExportFileWriter",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Không tạo được tệp xuất tạm tại \(partURL.path)"]
            )
        }
        handle = try FileHandle(forWritingTo: partURL)
    }

    deinit {
        // Không đổi tên và cũng không xoá: `finish()`/`discard()` là nơi quyết định, đây chỉ nhả file descriptor.
        try? handle.close()
    }

    /// Bản xuất vẫn chưa có nội dung có nghĩa nào (dùng cho `DownloadTaskOutcomeCalculator`).
    public var hasNoContent: Bool { !didWriteNonWhitespace }

    /// Ghi một chương đã format. Dấu phân tách được chèn trước, đúng thứ tự của bộ đệm chuỗi cũ.
    public func append(_ chapterText: String) throws {
        guard !isClosed else { return }
        if didWriteAnyBytes {
            try write(Self.chapterSeparator)
        }
        try write(chapterText)
        if !chapterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            didWriteNonWhitespace = true
        }
    }

    /// Đóng file tạm và đổi tên thành file đích, ghi đè bản xuất cũ cùng tên như trước đây.
    public func finish() throws -> URL {
        closeHandleIfNeeded()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        try fileManager.moveItem(at: partURL, to: targetURL)
        return targetURL
    }

    /// Huỷ bản xuất: đóng file và xoá file tạm để không để lại rác trong `Documents/Exports/`.
    public func discard() {
        closeHandleIfNeeded()
        try? FileManager.default.removeItem(at: partURL)
    }

    private func write(_ text: String) throws {
        let data = Data(text.utf8)
        guard !data.isEmpty else { return }
        try handle.write(contentsOf: data)
        didWriteAnyBytes = true
    }

    private func closeHandleIfNeeded() {
        guard !isClosed else { return }
        isClosed = true
        try? handle.close()
    }
}
