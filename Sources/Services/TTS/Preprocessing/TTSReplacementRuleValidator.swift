import Foundation

/// Kiểm tra một luật thay thế TTS theo luật token (1.3.920) — nguồn **duy nhất** cho mục "Kiểm tra" của sheet
/// Sửa ở Cài đặt, sheet "Thêm thay thế TTS" của Reader và huy hiệu trên hàng danh sách.
///
/// - **Lỗi** (chặn Lưu; luật đã lưu thì `TTSReplacementPlan` bỏ qua): mẫu rỗng; mẫu không phải đúng một token.
/// - **Cảnh báo** (vẫn Lưu được): trùng mẫu với luật khác cùng tầng; chuỗi thay thế giống hệt mẫu.
///
/// Token hiểu theo `TTSReplacementTokenizer` — cùng một hàm với lúc đọc, nên "ở đây xanh" là "lúc đọc có chạy".
enum TTSReplacementRuleValidator {
    enum Severity: Int, Comparable, Sendable {
        case error = 0
        case warning = 1

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Code: String, Sendable {
        case emptyPattern = "EMPTY_PATTERN"
        case notSingleToken = "NOT_SINGLE_TOKEN"
        case duplicatePattern = "DUPLICATE_PATTERN"
        case noOp = "NO_OP"

        var severity: Severity {
            switch self {
            case .emptyPattern, .notSingleToken: return .error
            case .duplicatePattern, .noOp: return .warning
            }
        }

        /// Nhãn ngắn cho huy hiệu và dòng Kiểm tra.
        var label: String {
            switch self {
            case .emptyPattern: return "MẪU RỖNG"
            case .notSingleToken: return "KHÔNG PHẢI 1 TOKEN"
            case .duplicatePattern: return "TRÙNG MẪU"
            case .noOp: return "KHÔNG ĐỔI GÌ"
            }
        }
    }

    struct Issue: Equatable, Sendable {
        let code: Code
        let message: String

        var severity: Severity { code.severity }
    }

    /// - Parameters:
    ///   - siblings: luật **cùng tầng** để xét trùng mẫu; truyền `[]` khi nơi gọi đã tự hiện luật trùng (chip R/C
    ///     của sheet Reader).
    ///   - excludingId: luật đang sửa — không tự coi là trùng với chính nó.
    static func issues(
        pattern: String,
        replacement: String,
        siblings: [TTSReplacementRule] = [],
        excludingId: UUID? = nil
    ) -> [Issue] {
        guard !pattern.isEmpty else {
            return [Issue(code: .emptyPattern, message: "Nhập từ hoặc ký hiệu cần thay.")]
        }
        var result: [Issue] = []
        if TTSReplacementTokenizer.singleToken(pattern) == nil {
            result.append(Issue(code: .notSingleToken, message: notSingleTokenReason(pattern)))
        }
        if siblings.contains(where: { $0.id != excludingId && $0.pattern == pattern }) {
            result.append(Issue(code: .duplicatePattern, message: "Tầng này đã có luật cùng mẫu — Lưu sẽ đè luật đó."))
        }
        if replacement == pattern {
            result.append(Issue(code: .noOp, message: "Chuỗi thay thế giống hệt mẫu — luật không đổi gì."))
        }
        return result
    }

    /// Lỗi + cảnh báo của một luật **đã lưu**, xét trùng mẫu trong chính tầng của nó.
    static func issues(for rule: TTSReplacementRule, in layer: [TTSReplacementRule]) -> [Issue] {
        issues(pattern: rule.pattern, replacement: rule.replacement, siblings: layer, excludingId: rule.id)
    }

    /// Câu mô tả cho mẫu hợp lệ (dòng xanh của mục Kiểm tra); `nil` khi mẫu không phải đúng một token.
    static func validDescription(for pattern: String) -> String? {
        switch TTSReplacementTokenizer.singleToken(pattern)?.kind {
        case .word:
            return "Luật chữ — thay khi cả từ trùng đúng mẫu (phân biệt hoa thường)."
        case .symbol:
            return "Luật ký hiệu — thay trong dãy ký hiệu, chạy sau luật chữ, mẫu dài hơn được ưu tiên."
        case .space, .none:
            return nil
        }
    }

    private static func notSingleTokenReason(_ pattern: String) -> String {
        let parts = TTSReplacementTokenizer.tokens(in: pattern)
        let split = parts.map { $0.kind == .space ? "␣" : $0.text }.joined(separator: " / ")
        if parts.contains(where: { $0.kind == .space }) {
            return "Mẫu có dấu cách hoặc xuống dòng (tách thành: \(split)). Mỗi luật chỉ là một từ hoặc một dãy ký hiệu."
        }
        return "Mẫu có cả chữ lẫn ký hiệu (tách thành: \(split)) — tách thành hai luật. Dấu \"-\" và \".\" chỉ thuộc từ khi kẹp giữa hai chữ."
    }
}
