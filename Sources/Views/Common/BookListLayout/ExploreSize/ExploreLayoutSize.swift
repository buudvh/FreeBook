import SwiftUI

/// Mức "Cỡ" 7 nấc của một bố cục trang Khám phá (`ExploreLayoutSizeKind`). Nấc 4 là mặc định và hiển thị **y hệt**
/// trước khi có tuỳ chọn: mọi hàm ở đây trả nguyên giá trị gốc (theo `shape`, xem `ExploreSection+Layout`) ở nấc 4.
///
/// - Lưới: nấc to = thẻ to = ít cột (`gridColumnCount(base:)`).
/// - Hàng ngang, ảnh nhỏ của Danh sách/Xếp hạng: bề rộng nhân `widthFactor`.
/// - Chữ của Danh sách/Xếp hạng: phóng theo `BookListRowSize` cùng nấc (cùng thang 1…7, mặc định 4).
/// - Banner: đổi tỉ lệ rộng : cao, nấc to = banner cao hơn.
struct ExploreLayoutSize: Equatable {
    static let range = 1...7
    static let defaultLevel = 4

    static let `default` = ExploreLayoutSize(level: defaultLevel)

    /// Số cột của lưới luôn nằm trong khoảng này dù nấc và cột gốc của `shape` là bao nhiêu.
    static let gridColumnRange = 1...6

    private static let widthFactors: [CGFloat] = [0.7, 0.8, 0.9, 1.0, 1.15, 1.3, 1.5]
    private static let bannerAspectRatios: [CGFloat] = [2.4, 2.2, 2.0, 16.0 / 9.0, 1.6, 1.45, 1.3]

    let level: Int

    init(level: Int) {
        self.level = min(max(level, Self.range.lowerBound), Self.range.upperBound)
    }

    var isDefault: Bool { level == Self.defaultLevel }

    /// Hệ số bề rộng thẻ (hàng ngang) / ảnh nhỏ (danh sách) so với nấc mặc định.
    var widthFactor: CGFloat { Self.widthFactors[level - 1] }

    /// Tỉ lệ rộng : cao của banner; nấc mặc định đúng 16:9.
    var bannerAspectRatio: CGFloat { Self.bannerAspectRatios[level - 1] }

    /// Số cột lưới từ số cột gốc của `shape`: mỗi nấc trên mặc định bớt một cột, mỗi nấc dưới thêm một cột.
    func gridColumnCount(base: Int) -> Int {
        guard !isDefault else { return base }
        let value = base - (level - Self.defaultLevel)
        return min(max(value, Self.gridColumnRange.lowerBound), Self.gridColumnRange.upperBound)
    }

    /// Bề rộng gốc nhân `widthFactor`, làm tròn điểm; nấc mặc định trả nguyên giá trị gốc.
    func scaledWidth(_ base: CGFloat) -> CGFloat {
        guard !isDefault else { return base }
        return (base * widthFactor).rounded()
    }

    /// Font một dòng chữ của Danh sách/Xếp hạng: nấc mặc định trả `defaultFont` nguyên văn (giữ Dynamic Type),
    /// nấc khác phóng như "Cỡ dòng" của kiểu Danh sách (`BookListRowSize.font`).
    func font(_ defaultFont: Font, base: CGFloat, weight: Font.Weight = .regular) -> Font {
        BookListRowSize(level: level).font(defaultFont, base: base, weight: weight)
    }
}
