import Foundation

/// Chữ dung lượng / tiến độ tải của sheet chọn giọng VieNeu (1.3.900). MB **thập phân** như nhãn các gói khác (GGUF
/// 187.917.664 byte = "188 MB").
enum VieNeuSizeFormatter {
    /// "347 MB"; dưới 1 MB ⇒ "dưới 1 MB" (file giọng Turbo vài KB).
    static func megabytes(_ bytes: Int64) -> String {
        bytes < 1_000_000 ? "dưới 1 MB" : String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }

    /// "Đang tải 37% · 93 / 251 MB"; chưa biết tổng ⇒ "Đang tải…"; đang xếp hàng ⇒ chữ chờ.
    static func progress(_ entry: ModelDownloadCenter.Entry) -> String {
        if entry.isQueued { return "Đang chờ lượt tải khác…" }
        guard entry.totalBytes > 0 else { return "Đang tải…" }
        let percent = Int((Double(entry.completedBytes) / Double(entry.totalBytes) * 100).rounded(.down))
        return String(
            format: "Đang tải %d%% · %.0f / %.0f MB",
            min(100, max(0, percent)),
            Double(entry.completedBytes) / 1_000_000,
            Double(entry.totalBytes) / 1_000_000
        )
    }
}
