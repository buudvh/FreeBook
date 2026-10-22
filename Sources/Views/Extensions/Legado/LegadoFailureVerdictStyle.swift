import SwiftUI

/// Màu + icon của kết luận "lỗi do ai" (tầng View — enum ở Services không giữ `Color`). Màu cố định, **không** dùng màu
/// nhấn (app đặt `.tint(.white)` toàn cục ⇒ màu nhấn là trắng).
extension LegadoFailureVerdict {
    var tint: Color {
        switch self {
        case .web: return .orange
        case .sourceOutdated: return Color(.systemGray)
        case .needsUser: return .blue
        case .app: return .red
        case .unknown: return Color(.systemGray2)
        }
    }

    var systemImage: String {
        switch self {
        case .web: return "wifi.exclamationmark"
        case .sourceOutdated: return "clock.arrow.circlepath"
        case .needsUser: return "lock.shield"
        case .app: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}
