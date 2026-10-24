import Foundation

/// `manifest.json` của một tập phim đã tải trọn vẹn (`videos/<sha256(bookId)>/<episodeIndex>/`, `VideoOfflineStore`).
/// Ghi **sau cùng** ⇒ có manifest ⇔ tập phát offline được.
struct VideoEpisodeManifest: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        /// Playlist HLS trên máy (`entryFile` = `index.m3u8`), phát qua `VideoOfflineHTTPServer`.
        case hls
        /// Một file media (mp4/mov/m4v), phát bằng `file://`.
        case file
    }

    struct Subtitle: Codable, Sendable, Equatable {
        let file: String
        let label: String?
        let language: String?
    }

    struct TimeSkip: Codable, Sendable, Equatable {
        let fromMs: Int
        let toMs: Int
    }

    static let currentVersion = 1

    let version: Int
    /// `url` thô của tập trong mục lục lúc tải — mục lục đổi đường dẫn tập thì coi như chưa tải.
    let episodeUrl: String
    let episodeTitle: String
    let serverTitle: String
    let kind: Kind
    /// Tên file mở đầu (chỉ tên file, không có thư mục).
    let entryFile: String
    /// Mức đã tải ("720p", "1.2 Mbps"); rỗng khi nguồn chỉ có một mức không khai độ phân giải.
    let qualityLabel: String
    let totalBytes: Int64
    /// Số đoạn media đã tải (HLS); file đơn = 1.
    let segmentCount: Int
    let subtitles: [Subtitle]
    let timeSkips: [TimeSkip]
    let completedAt: Date
}
