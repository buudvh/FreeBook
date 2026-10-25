import Foundation

/// Kết quả một lượt áp rule: text sau rewrite + bản đồ đoạn để dựng `TranslationSpan` về **nguồn**.
///
/// Cần bản đồ này vì rule làm output đổi độ dài và đảo thứ tự, nên không thể suy vị trí nguồn bằng
/// tỉ lệ. Đoạn nào không chứng minh được mapping thì bên tiêu thụ bỏ span **của riêng đoạn đó**.
public struct QuickTranslationRewriteResult: Sendable {
    public struct Segment: Sendable {
        /// Range UTF-16 trong chuỗi **nguồn** (trước rewrite).
        public let sourceRange: NSRange
        /// Range UTF-16 trong chuỗi **sau rewrite**.
        public let outputRange: NSRange
        /// Dòng rule đã sinh đoạn này; `nil` = đoạn đi qua nguyên vẹn.
        public let sourceLine: Int?

        public init(sourceRange: NSRange, outputRange: NSRange, sourceLine: Int?) {
            self.sourceRange = sourceRange
            self.outputRange = outputRange
            self.sourceLine = sourceLine
        }
    }

    public let text: String
    public let segments: [Segment]
    /// Số rule đã khớp — cũng là điều kiện để bên gọi biết có cần dùng bản đồ hay không.
    public let appliedRuleCount: Int

    public var didRewrite: Bool { appliedRuleCount > 0 }

    public init(text: String, segments: [Segment], appliedRuleCount: Int) {
        self.text = text
        self.segments = segments
        self.appliedRuleCount = appliedRuleCount
    }

    /// Ánh xạ một range trên chuỗi sau rewrite về range nguồn.
    ///
    /// Đoạn đi qua nguyên vẹn map theo offset tuyệt đối; đoạn do rule sinh map về **toàn bộ** match
    /// nguồn (không đoán mapping hẹp hơn). Range phủ nhiều đoạn thì lấy hợp của các range nguồn.
    public func sourceRange(forOutputRange range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        var lower = Int.max
        var upper = Int.min

        for segment in segments {
            let intersection = NSIntersectionRange(segment.outputRange, range)
            guard intersection.length > 0 else { continue }

            if segment.sourceLine == nil {
                let offset = intersection.location - segment.outputRange.location
                lower = min(lower, segment.sourceRange.location + offset)
                upper = max(upper, segment.sourceRange.location + offset + intersection.length)
            } else {
                lower = min(lower, segment.sourceRange.location)
                upper = max(upper, NSMaxRange(segment.sourceRange))
            }
        }

        guard lower != Int.max, upper > lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }
}
