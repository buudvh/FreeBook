import SwiftUI

/// Ba mức màu của chip rule ở màn Check rule. Màu nằm ở tầng **View** — `QuickTranslationRuleTrace`
/// ở tầng Models nên không được biết `Color`.
///
/// Quy ước do chủ dự án chốt: rule **thắng** chữ + viền xanh **đậm** kèm dấu ✓ **sau chữ**; rule
/// **tranh chấp** xanh **nhạt**; rule **bị tắt** xanh **xám**. Ba mức cùng một tông để đọc được là
/// "cùng một loại thông tin, khác mức hiệu lực".
enum ReaderRuleChipStyle {
    case winner
    case conflicting
    case disabled

    init(status: QuickTranslationRuleTrace.Status) {
        switch status {
        case .applied:
            self = .winner
        case .lostOverlap:
            self = .conflicting
        case .disabledGlobally, .disabledForBook, .tokenDisabled, .tooComplex:
            self = .disabled
        }
    }

    var textColor: Color {
        switch self {
        case .winner: return Color.white
        case .conflicting: return Color.white.opacity(0.65)
        case .disabled: return Color(red: 0.75, green: 0.75, blue: 0.75)
        }
    }

    var textWeight: Font.Weight {
        switch self {
        case .winner: return .bold
        case .conflicting: return .regular
        case .disabled: return .regular
        }
    }

    var borderColor: Color {
        switch self {
        case .winner: return Color.white.opacity(0.95)
        case .conflicting: return Color.white.opacity(0.35)
        case .disabled: return Color.gray.opacity(0.45)
        }
    }

    var borderWidth: CGFloat {
        self == .winner ? 1.5 : 1.0
    }

    /// Dấu gắn **sau** chữ của chip. Chỉ rule thắng có dấu.
    var trailingMark: String? {
        self == .winner ? "✓" : nil
    }

    /// Nhãn trạng thái ngắn hiện dưới mẫu, để không phải đoán màu.
    static func label(for status: QuickTranslationRuleTrace.Status) -> String {
        switch status {
        case .applied: return "đang áp dụng"
        case .lostOverlap(let line): return "thua dòng \(line)"
        case .disabledGlobally: return "tắt ở bộ chung"
        case .disabledForBook: return "tắt cho truyện này"
        case .tokenDisabled: return "token đang tắt"
        case .tooComplex: return "rule quá phức tạp"
        }
    }
}
