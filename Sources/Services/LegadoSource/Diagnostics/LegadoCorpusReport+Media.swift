import Foundation

extension LegadoCorpusReport {
    /// Chi tiết bước media của một nguồn tranh/video (bước báo cáo vẫn là `Step.content` — không thêm case mới để client
    /// cũ và màn Kiểm tra hàng loạt không phải đổi).
    ///
    /// - Tranh: lấy danh sách ảnh chương đầu (`items` = số ảnh) rồi tải thử ảnh đầu (`firstItemBytes`).
    /// - Video: lấy server của tập đầu (`items`), giải nguồn phát (`trackKind`), với nguồn `native` thì tải thử 1 KB đầu
    ///   (`firstItemBytes`; `.m3u8` phải bắt đầu bằng `#EXTM3U`).
    public struct MediaCheck: Codable, Sendable, Equatable {
        /// `comic` / `video`.
        public let kind: String
        public let items: Int
        public let firstItemBytes: Int?
        /// `native` / `webview` / `auto` (video).
        public let trackKind: String?
        /// Ảnh đầu đi qua `imageDecode` (tranh).
        public let decoded: Bool
        /// Bước con hỏng: `list` / `item` / `track` / `probe`; `nil` khi qua.
        public let failedStage: String?

        public init(kind: String, items: Int, firstItemBytes: Int?, trackKind: String?, decoded: Bool, failedStage: String?) {
            self.kind = kind
            self.items = items
            self.firstItemBytes = firstItemBytes
            self.trackKind = trackKind
            self.decoded = decoded
            self.failedStage = failedStage
        }
    }
}
