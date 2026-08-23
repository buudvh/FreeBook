import Foundation

/// Hợp đồng chung của mọi bộ render bản xuất.
///
/// Renderer **ghi dần** ra đĩa: `append(_:)` được gọi ngay khi một chương có nội dung (lấy từ cache
/// hoặc vừa tải xong), nên đỉnh RAM không phụ thuộc số chương — truyện vài nghìn chương vẫn phẳng.
/// Vòng đời bắt buộc: `init` → `append` × N → đúng **một** trong `finish()` / `discard()`.
public protocol ExportRenderer: AnyObject {
    /// Đã ghi được nội dung có nghĩa nào chưa. `false` ⇒ không được tạo artifact.
    var hasContent: Bool { get }
    /// Số chương đã ghi.
    var writtenChapterCount: Int { get }
    /// Ghi một chương. Renderer tự lo định dạng của mình.
    func append(_ chapter: ExportChapterPayload) throws
    /// Đóng file tạm, ghi phần đuôi (mục lục, metadata…) và đổi tên sang đường dẫn cuối.
    func finish() throws -> ExportArtifact
    /// Huỷ bản xuất: đóng và xoá mọi file tạm, không để lại rác trong `Documents/Exports/`.
    func discard()
}
