import Foundation

/// Một mức chất lượng chọn được của item HLS đang phát, đọc từ `AVAsset.variants` (`VideoPlaybackSession+Quality`).
///
/// Chọn một mức = đặt **trần** cho AVPlayer (`preferredPeakBitRate` + `preferredMaximumResolution`): không vượt mức
/// này, nhưng mạng yếu thì vẫn có thể xuống thấp hơn — AVPlayer không có API ép đúng một biến thể.
struct VideoQualityOption: Hashable, Identifiable, Sendable {
    /// Kích thước khung hình (px); `0` = playlist không khai độ phân giải ⇒ nhãn và so sánh theo bitrate.
    let width: Int
    let height: Int
    let peakBitRate: Double

    var id: String { "\(height)-\(Int(peakBitRate))" }

    var title: String {
        height > 0 ? "\(height)p" : String(format: "%.1f Mbps", peakBitRate / 1_000_000)
    }

    /// Không vượt `other`: so chiều cao khi cả hai cùng có, không thì so bitrate.
    func isAtMost(_ other: VideoQualityOption) -> Bool {
        if height > 0, other.height > 0 { return height <= other.height }
        return peakBitRate <= other.peakBitRate
    }
}
