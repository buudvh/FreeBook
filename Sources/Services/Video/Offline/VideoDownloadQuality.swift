import Foundation

/// Chất lượng khi **tải** phim (khác mục Chất lượng khi phát của `VideoPlaybackSession+Quality`). Một lựa chọn chung,
/// nhớ trong UserDefaults (sheet tải ghi, tác vụ đọc lúc chạy) — không lưu theo tác vụ để khỏi đổi `DownloadTaskModel`.
///
/// Áp khi playlist gốc có nhiều mức: lấy mức cao nhất không vượt trần; không mức nào dưới trần ⇒ mức thấp nhất.
/// Playlist không khai `RESOLUTION` ⇒ so `BANDWIDTH` với trần bitrate xấp xỉ.
enum VideoDownloadQuality: String, CaseIterable, Identifiable, Sendable {
    case highest
    case max1080
    case max720
    case max480

    static let defaultsKey = "videoDownloadQuality"
    static let defaultValue: VideoDownloadQuality = .max720

    var id: String { rawValue }

    static var current: VideoDownloadQuality {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = VideoDownloadQuality(rawValue: raw) else { return defaultValue }
        return value
    }

    var title: String {
        switch self {
        case .highest: return "Cao nhất"
        case .max1080: return "Tối đa 1080p"
        case .max720: return "Tối đa 720p"
        case .max480: return "Tối đa 480p"
        }
    }

    private var maxHeight: Int? {
        switch self {
        case .highest: return nil
        case .max1080: return 1080
        case .max720: return 720
        case .max480: return 480
        }
    }

    /// Trần bitrate khi playlist không khai độ phân giải (xấp xỉ mức phổ biến của từng độ phân giải).
    private var maxBandwidth: Int? {
        switch self {
        case .highest: return nil
        case .max1080: return 6_000_000
        case .max720: return 3_500_000
        case .max480: return 1_500_000
        }
    }

    /// Biến thể cần tải; `nil` khi danh sách rỗng.
    func pick(_ variants: [VideoHLSOfflinePlanner.Variant]) -> VideoHLSOfflinePlanner.Variant? {
        guard !variants.isEmpty else { return nil }
        let withHeight = variants.filter { $0.height > 0 }
        if !withHeight.isEmpty {
            let ordered = withHeight.sorted { ($0.height, $0.bandwidth) < ($1.height, $1.bandwidth) }
            guard let maxHeight else { return ordered.last }
            return ordered.last { $0.height <= maxHeight } ?? ordered.first
        }
        let ordered = variants.sorted { $0.bandwidth < $1.bandwidth }
        guard let maxBandwidth else { return ordered.last }
        return ordered.last { $0.bandwidth <= maxBandwidth } ?? ordered.first
    }
}
