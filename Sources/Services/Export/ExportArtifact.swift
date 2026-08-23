import Foundation

/// File đã hoàn chỉnh của một lần xuất truyện.
///
/// Chỉ được tạo bởi `ExportRenderer.finish()`, tức là **sau** khi file tạm đã đóng và đổi tên sang
/// đường dẫn cuối. Tác vụ chỉ được đánh dấu hoàn thành khi có artifact và file tồn tại thật.
public struct ExportArtifact: Sendable {
    public let fileURL: URL
    public let format: BookExportFormat
    /// Số chương thực sự đã ghi vào file.
    public let chapterCount: Int

    public init(fileURL: URL, format: BookExportFormat, chapterCount: Int) {
        self.fileURL = fileURL
        self.format = format
        self.chapterCount = chapterCount
    }

    /// File có tồn tại trên đĩa hay không — điều kiện bắt buộc trước khi báo hoàn thành.
    public var exists: Bool {
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
