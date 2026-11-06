import Foundation

/// Kết quả một lần quét `covers/` (`ImageCacheManager.scanCoverFolder`) — bản chụp bất biến, đếm trước khi dọn để hộp
/// xác nhận của màn Dung lượng hiện số thật. Lúc dọn, owner kiểm lại chủ + tuổi từng file chứ không tin bản chụp này.
struct CoverFolderScan: Sendable, Equatable {
    /// Bìa của một truyện còn trong thư viện mà cạnh dài vượt `CoverImageEncoder.maxPixelSize`.
    struct OversizedCover: Sendable, Equatable {
        let fileName: String
        let bookId: String
    }

    /// File không thuộc `Book` nào (đã qua tuổi tối thiểu) — thường là bìa của trang Chi tiết truyện chưa lưu.
    let orphanFileNames: [String]
    let orphanBytes: Int64
    /// Chỉ có khi quét với `includeOversized`.
    let oversized: [OversizedCover]
    let oversizedBytes: Int64

    var orphanCount: Int { orphanFileNames.count }
    var oversizedCount: Int { oversized.count }
    var isEmpty: Bool { orphanFileNames.isEmpty && oversized.isEmpty }
}
