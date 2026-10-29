import Foundation

/// Các file video đã nhận (`LocalVideoImporter.prepare`) — dữ liệu của sheet xác nhận "Nhập phim". Nhiều file gộp thành
/// **một** phim, tập xếp theo tên file tự nhiên. File vẫn nằm trong `workDirectory` cho tới khi người dùng bấm "Nhập".
struct LocalVideoImportPlan: Identifiable, Sendable {
    struct Episode: Identifiable, Sendable {
        /// Vị trí 0-based — cũng là `index` của tập trong mục lục và tên thư mục ở `VideoOfflineStore`.
        let id: Int
        /// Tên file gốc (có đuôi) — hiện trên sheet.
        let fileName: String
        /// Tên tập trong mục lục: tên file bỏ đuôi.
        let title: String
        let fileURL: URL
        let bytes: Int64
    }

    let id = UUID()
    /// Tên phim mặc định trên sheet.
    let defaultTitle: String
    /// `LocalMediaImportWorkspace` của lượt nhập — xoá cả cây khi nhập xong hoặc bỏ.
    let workDirectory: URL
    let episodes: [Episode]

    var totalBytes: Int64 {
        episodes.reduce(0) { $0 + $1.bytes }
    }
}
