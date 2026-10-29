import SwiftUI

/// Sáu nấc "Độ đục" của **nút nổi** (1.3.645) và **ngăn kéo menu** (1.3.647): mỗi nấc là một độ dày kính có sẵn của
/// iOS, luôn vẽ ở độ hiện 100%.
///
/// Vì sao không còn `.opacity(độ đục)` trên material như 1.3.640: kính của iOS (UIVisualEffectView / Material) chỉ nhoè
/// được khi chính nó và mọi lớp cha hiện đủ 100% — Apple ghi rõ alpha < 1 làm hiệu ứng "hiện sai hoặc không hiện". Nên
/// trước đây 0–95% đều **không nhoè** (chỉ phủ lớp xám), chỉ 100% mới nhoè ⇒ cú nhảy người dùng thấy giữa 95% và 100%.
/// iOS không có API công khai đặt bán kính nhoè tuỳ ý, nên chỉ chỉnh theo nấc (ngăn kéo từng thử nhoè mịn bằng ảnh chụp
/// nền ở 1.3.645, người dùng cho gỡ ở 1.3.647).
///
/// Giá trị lưu vẫn là `Double` 0…1 (`GlassChromeSettings.floatingFrostKey`); đọc thì làm tròn về nấc gần nhất (bước 0,2).
enum GlassFrostLevel: Int, CaseIterable {
    case none = 0
    case ultraThin
    case thin
    case regular
    case thick
    case ultraThick

    /// Bước của thanh kéo "Độ đục" nút nổi.
    static let step = 0.2

    init(frost: Double) {
        let index = Int((min(max(frost, 0), 1) / Self.step).rounded())
        self = GlassFrostLevel(rawValue: index) ?? .none
    }

    var title: String {
        switch self {
        case .none: return "Không nhoè"
        case .ultraThin: return "Rất mỏng"
        case .thin: return "Mỏng"
        case .regular: return "Vừa"
        case .thick: return "Dày"
        case .ultraThick: return "Rất dày"
        }
    }

    /// `nil` = không có lớp kính.
    var material: Material? {
        switch self {
        case .none: return nil
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .ultraThick: return .ultraThickMaterial
        }
    }
}
