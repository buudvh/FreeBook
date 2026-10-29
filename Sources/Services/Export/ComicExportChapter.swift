import Foundation

/// Một chương truyện tranh **đã tải ảnh offline** đưa vào bản xuất CBZ/PDF (`DownloadManager+ComicExport`).
struct ComicExportChapter: Sendable {
    /// Vị trí 1-based trong danh sách chương đã lên kế hoạch (tính cả chương chưa tải bị bỏ) — tiến độ tác vụ.
    let position: Int
    /// Thứ tự 1-based trong bản xuất — tên thư mục chương của CBZ.
    let ordinal: Int
    let title: String
    /// File ảnh trong `ComicOfflineStore`, đúng thứ tự manifest.
    let pages: [URL]
}
