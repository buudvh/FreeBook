import Foundation

/// Một lời gọi `java.startBrowser(url, title)` bị bắt lại trong `content` của nguồn/sách video (spec §9.6): không mở
/// trình duyệt mà trở thành "ứng viên phát" cho luồng video (§9.3 bước 4.2).
struct LegadoPlaybackCandidate: Sendable {
    let url: String
    let title: String
}
