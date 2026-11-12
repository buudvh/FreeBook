import Foundation

/// Lời bài hát đã đọc xong của một nguồn (`AudioLyricParser`).
///
/// Lời có mốc giờ (LRC, VTT, SRT): mọi dòng đều có `time`, đã sắp tăng dần ⇒ `lineIndex(at:)` tìm dòng đang hát. Lời chữ
/// thường: mọi dòng `time == nil`, `lineIndex(at:)` luôn `nil` (không tô dòng).
public struct AudioLyrics: Sendable, Equatable {
    public let lines: [AudioLyricLine]

    public init(lines: [AudioLyricLine]) {
        self.lines = lines
    }

    /// Có mốc giờ ⇒ trình nghe tô dòng đang hát theo thời gian phát.
    public var isSynced: Bool {
        lines.contains { $0.time != nil }
    }

    /// Có ít nhất một dòng đã dịch ⇒ màn nghe cho chọn kiểu hiện lời (Gốc / Bản dịch / Song ngữ).
    public var hasTranslation: Bool {
        lines.contains { $0.translation != nil }
    }

    /// Có dòng mang chữ đã chuyển phồn → giản hoặc bản dịch ⇒ dịch lại phải bỏ cả hai trước.
    public var hasCaptionOverrides: Bool {
        lines.contains { $0.converted != nil || $0.translation != nil }
    }

    /// Bản sao gán chữ đã chuyển + bản dịch theo offset trong `lines` (hai mảng phải cùng số dòng với `lines`, lệch thì giữ
    /// nguyên). Truyền toàn `nil` để bỏ hết.
    public func withCaptions(converted: [String?], translations: [String?]) -> AudioLyrics {
        guard converted.count == lines.count, translations.count == lines.count else { return self }
        var updated = lines
        for offset in updated.indices {
            updated[offset].converted = converted[offset]
            updated[offset].translation = translations[offset]
        }
        return AudioLyrics(lines: updated)
    }

    /// Bản sao bỏ hết chữ đã chuyển và bản dịch (về nguyên văn).
    public func clearingCaptions() -> AudioLyrics {
        let empty = [String?](repeating: nil, count: lines.count)
        return withCaptions(converted: empty, translations: empty)
    }

    /// Dòng cuối cùng có `time <= seconds` (tìm nhị phân trên các dòng đã sắp); `nil` khi chưa tới dòng đầu hoặc lời không
    /// có mốc giờ. Chỉ số là offset trong `lines`.
    public func lineIndex(at seconds: Double) -> Int? {
        guard isSynced, seconds.isFinite else { return nil }
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            let time = lines[middle].time ?? 0
            if time <= seconds {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }
}
