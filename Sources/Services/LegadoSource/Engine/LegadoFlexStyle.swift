import Foundation

/// Khoá bố cục `style` (`layout_*`) dùng chung cho mục khám phá và ô form đăng nhập (spec §11.7, §10.3).
struct LegadoFlexStyle: Sendable, Equatable {
    /// `layout_flexBasisPercent` (chấp nhận tên viết sai `layout_flexBasisPersent`); chỉ `0 < p ≤ 1` có nghĩa, còn lại `nil`.
    var flexBasisPercent: Double?
    var flexGrow: Double?
    var flexShrink: Double?
    var alignSelf: String?
    /// `layout_wrapBefore`: xuống hàng trước ô này.
    var wrapBefore: Bool

    init(flexBasisPercent: Double? = nil, flexGrow: Double? = nil, flexShrink: Double? = nil, alignSelf: String? = nil,
         wrapBefore: Bool = false) {
        self.flexBasisPercent = flexBasisPercent
        self.flexGrow = flexGrow
        self.flexShrink = flexShrink
        self.alignSelf = alignSelf
        self.wrapBefore = wrapBefore
    }

    /// Đọc từ object `style` (JSON lenient); thiếu/không phải object ⇒ mặc định.
    static func parse(_ style: LegadoEngineJSON?) -> LegadoFlexStyle {
        guard let style, style.objectEntries != nil else { return LegadoFlexStyle() }
        let basis = (style["layout_flexBasisPercent"] ?? style["layout_flexBasisPersent"])?.doubleValue
        let alignSelf = style["layout_alignSelf"].map { $0.scalarString }
        return LegadoFlexStyle(
            flexBasisPercent: basis.flatMap { $0 > 0 && $0 <= 1 ? $0 : nil },
            flexGrow: style["layout_flexGrow"]?.doubleValue,
            flexShrink: style["layout_flexShrink"]?.doubleValue,
            alignSelf: alignSelf.flatMap { $0.isEmpty ? nil : $0 },
            wrapBefore: style["layout_wrapBefore"].map { LegadoBookContext.truthy($0) } ?? false
        )
    }
}
