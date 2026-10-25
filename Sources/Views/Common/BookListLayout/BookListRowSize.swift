import SwiftUI

/// Cỡ dòng của kiểu Danh sách (`BookListLayoutMode.list`), 7 nấc. Lưu theo `BookListLayoutScope` cùng
/// `BookListLayoutPreferences` (khoá `bookListLayout.rowSize.<scope>`).
///
/// Nấc 4 là cỡ trước khi có tuỳ chọn (bìa 50×70, tên 14.5pt) và là mặc định: ở nấc này `font(_:base:weight:)` trả
/// nguyên font cũ của từng dòng (giữ cả Dynamic Type của text style), nên ai không chỉnh thì không thấy gì đổi.
/// Nấc khác phóng chữ theo `scale` (tỉ lệ cỡ tên so với 14.5pt).
///
/// Nấc 1–2 là dòng gọn (`isCompact`): tên 1 dòng, dòng phụ gộp thành một hàng.
struct BookListRowSize: Equatable {
    static let range = 1...7
    static let defaultLevel = 4

    static let `default` = BookListRowSize(level: defaultLevel)

    /// Rộng × cao của bìa theo nấc 1…7 (giữ tỉ lệ ~5:7 như bìa 50×70 cũ).
    private static let coverSizes: [CGSize] = [
        CGSize(width: 32, height: 45),
        CGSize(width: 38, height: 53),
        CGSize(width: 44, height: 62),
        CGSize(width: 50, height: 70),
        CGSize(width: 58, height: 81),
        CGSize(width: 68, height: 95),
        CGSize(width: 80, height: 112)
    ]
    private static let titleSizes: [CGFloat] = [12.5, 13, 13.5, 14.5, 15.5, 16.5, 17.5]
    /// Chữ phụ không nhỏ hơn mức này dù nấc nhỏ.
    private static let minimumFontSize: CGFloat = 10

    let level: Int

    init(level: Int) {
        self.level = min(max(level, Self.range.lowerBound), Self.range.upperBound)
    }

    var isDefault: Bool { level == Self.defaultLevel }
    var isCompact: Bool { level <= 2 }

    var coverWidth: CGFloat { Self.coverSizes[level - 1].width }
    var coverHeight: CGFloat { Self.coverSizes[level - 1].height }

    /// Hệ số phóng chữ so với nấc mặc định.
    var scale: CGFloat { Self.titleSizes[level - 1] / Self.titleSizes[Self.defaultLevel - 1] }

    var titleLineLimit: Int { isCompact ? 1 : 2 }

    /// Font của một dòng chữ: nấc mặc định trả `defaultFont` nguyên văn; nấc khác là `.system` cỡ `base × scale`
    /// (`base` = cỡ pt của `defaultFont` ở nấc mặc định).
    func font(_ defaultFont: Font, base: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard !isDefault else { return defaultFont }
        let size = max((base * scale * 2).rounded() / 2, Self.minimumFontSize)
        return .system(size: size, weight: weight)
    }
}
