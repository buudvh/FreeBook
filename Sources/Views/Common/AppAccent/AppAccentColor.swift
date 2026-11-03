import SwiftUI
import UIKit

/// Màu nhấn của app (1.3.678) — Cài đặt › Chung › Giao diện › **Màu nhấn**. Thay `.tint(.white)` cố định trước đây;
/// không còn lựa chọn trắng. Mặc định Xanh ngọc.
///
/// Dùng màu hệ thống nên tự đổi sắc theo nền tối / sáng (vd. Xanh ngọc `systemTeal`: #40C8E0 tối, #30B0C7 sáng).
///
/// Lưu ở `UserDefaults` khoá `storageKey` (không dấu chấm — `@AppStorage` nghe qua KVO, xem `GlassChromeSettings`).
/// Mọi nơi gắn `.appAccentTint()` đọc khoá này nên chọn màu là đổi ngay; phần UIKit (menu hệ thống, hộp thoại,
/// share sheet) đổi qua `applyToWindows()` mà chính modifier đó gọi khi hiện ra và khi khoá đổi.
enum AppAccentColor: String, CaseIterable, Identifiable {
    case teal
    case blue
    case orange
    case indigo

    static let storageKey = "appAccentColor"
    static let defaultValue: AppAccentColor = .teal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teal: return "Xanh ngọc"
        case .blue: return "Xanh dương"
        case .orange: return "Cam hổ phách"
        case .indigo: return "Chàm"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .orange: return .systemOrange
        case .indigo: return .systemIndigo
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// Giá trị lưu lạ / chưa có ⇒ mặc định.
    init(storedValue: String) {
        self = AppAccentColor(rawValue: storedValue) ?? Self.defaultValue
    }

    /// Bản đọc thẳng `UserDefaults` cho nơi không có `@AppStorage` (UIKit).
    static var current: AppAccentColor {
        AppAccentColor(storedValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
    }

    /// `tintColor` của mọi cửa sổ đang mở — phần UIKit không đọc `.tint` của SwiftUI.
    @MainActor
    func applyToWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = uiColor
            }
        }
    }
}
