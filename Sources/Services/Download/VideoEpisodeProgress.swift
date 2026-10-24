import Foundation

/// Trạng thái **từng tập** của một tác vụ tải video (`DownloadTask.videoEpisodes`) — cho mục "Chi tiết tập" ở tab Tải.
/// Chỉ là trạng thái hiển thị: không lưu CSDL (app khởi động lại thì tác vụ dở đã thành "Thất bại", thử lại sẽ dựng lại).
/// `DownloadManager+Video` cập nhật, tối đa ~1 lần/giây cho tập đang tải.
public struct VideoEpisodeProgress: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case waiting
        case downloading(fraction: Double, bytes: Int64)
        case done(bytes: Int64)
        /// Đã có bản tải cùng URL tập từ trước — bỏ qua.
        case alreadyDownloaded
        case failed(String)
        case cancelled
    }

    /// Chỉ số tập trong mục lục (`StoredChapterSnapshot.index`).
    public let index: Int
    public let title: String
    public var state: State

    public var id: Int { index }

    public var displayTitle: String {
        title.isEmpty ? "Tập \(index + 1)" : title
    }

    public var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    /// Phần đã xong của tập (0…1) — dùng cho thanh tiến độ tổng.
    public var fraction: Double {
        switch state {
        case .waiting, .cancelled: return 0
        case .downloading(let fraction, _): return min(1, max(0, fraction))
        case .done, .alreadyDownloaded, .failed: return 1
        }
    }
}

extension DownloadTask {
    /// Số mục đã xong cộng phần đã tải của tập video đang tải — thanh tiến độ chạy mượt trong một tập dài. Dùng chung
    /// cho tab Tải và màn Thông báo.
    public var smoothProgressCount: Double {
        let current = videoEpisodes.first(where: \.isDownloading)?.fraction ?? 0
        return min(Double(max(1, totalCount)), Double(progressCount) + current)
    }

    /// Phần trăm cả tác vụ tải video; `nil` với tác vụ khác hoặc khi chưa biết tổng số tập.
    public var videoProgressPercent: Int? {
        guard isVideoDownload, totalCount > 0 else { return nil }
        return Int((smoothProgressCount / Double(totalCount) * 100).rounded())
    }
}
