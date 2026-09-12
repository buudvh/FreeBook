import Combine
import Foundation

/// Trạng thái **chế độ E-Ink** — nguồn sự thật duy nhất cho mọi quyết định "đang bật e-ink hay chưa".
///
/// Màn e-ink (Boox/Dasung/Hisense…) render dải xám rất kém và bị ghosting khi có chuyển động, nên chế
/// độ này không phải "thêm một theme màu" mà là một **chính sách render**: chỉ đen/trắng, viền thay
/// bóng, đảo ngược thay vì tô màu nhạt, và bỏ các hiệu ứng nền mờ.
///
/// **Vì sao không `@MainActor`** như `ToastManager`/`TTSManager`: object này bị đọc từ rất nhiều chỗ,
/// gồm `ViewModifier` và `ReaderViewModel` — những ngữ cảnh mà trình biên dịch không chắc đã
/// MainActor-isolated. Repo đã có tiền lệ cùng kiểu ở `TranslationManager` (singleton `ObservableObject`
/// không `@MainActor`, đọc từ mọi tầng). Mọi lượt **ghi** đều đến từ màn Cài đặt (main thread); lượt
/// đọc chỉ là `Bool` trong `UserDefaults` nên không có tranh chấp thực chất.
public final class EInkModeSettings: ObservableObject {
    public static let shared = EInkModeSettings()

    /// Màu nền giấy của chế độ E-Ink — người dùng chọn một trong ba tông, mặc định **Gray** (#D8D8D2).
    ///
    /// Enum nằm trong class (không phải type top level riêng) để file vẫn đúng **1 type top level**
    /// (`MULTI_PRIMARY_TYPES`). Chỉ mang `rawValue: Int` + nhãn tiếng Việt — **không** import SwiftUI
    /// (tầng `Services` cấm), nên việc đổi `Int` sang `Color`/`UIColor` nằm ở `EInkPalette`.
    public enum EInkPaperColor: Int, CaseIterable {
        /// Trắng ngà (#F2F1EC) — ít ngả vàng nhất.
        case white = 0
        /// Xám giấy (#D8D8D2) — dịu mắt nhất, **mặc định**.
        case gray = 1
        /// Vàng giấy (#E5DED0) — hơi ngả vàng như giấy sách.
        case warm = 2

        public var label: String {
            switch self {
            case .white: return "Trắng ngà"
            case .gray: return "Xám giấy"
            case .warm: return "Vàng giấy"
            }
        }
    }

    /// Bật/tắt toàn bộ chế độ E-Ink.
    @Published public private(set) var isEnabled: Bool
    /// Bìa sách đổi sang thang xám. Bỏ qua khi `hideCovers` bật.
    @Published public private(set) var monochromeCovers: Bool
    /// Bỏ hẳn ảnh bìa, thay bằng khung chữ — mạnh hơn `monochromeCovers`.
    @Published public private(set) var hideCovers: Bool
    /// Lật chương không animation (nhảy thẳng tới vị trí mới).
    @Published public private(set) var instantChapterTurn: Bool
    /// Hiện nút full-refresh trong trình đọc.
    @Published public private(set) var showsRefreshButton: Bool
    /// Màu nền giấy được chọn (White / Gray / Warm).
    @Published public private(set) var paperColor: EInkPaperColor

    /// Khoá `UserDefaults` — công khai để `View+EInk` bind `@AppStorage` **đúng cùng khoá**, nhờ đó màn
    /// tự cập nhật khi người dùng đổi chế độ mà không phải observe singleton ở từng chỗ.
    ///
    /// Lồng trong class để file vẫn đúng **1 type top level** (`MULTI_PRIMARY_TYPES`).
    public enum Key {
        public static let enabled = "eInkModeEnabled"
        public static let monochromeCovers = "eInkMonochromeCovers"
        public static let hideCovers = "eInkHideCovers"
        public static let instantChapterTurn = "eInkInstantChapterTurn"
        public static let showsRefreshButton = "eInkShowsRefreshButton"
        public static let paperColor = "eInkPaperColor"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Công tắc phụ mặc định bật sẵn: bật chế độ là dùng được ngay, người dùng chỉ tắt bớt nếu muốn.
        defaults.register(defaults: [
            Key.enabled: false,
            Key.monochromeCovers: true,
            Key.hideCovers: false,
            Key.instantChapterTurn: true,
            Key.showsRefreshButton: true,
            Key.paperColor: EInkPaperColor.gray.rawValue
        ])
        isEnabled = defaults.bool(forKey: Key.enabled)
        monochromeCovers = defaults.bool(forKey: Key.monochromeCovers)
        hideCovers = defaults.bool(forKey: Key.hideCovers)
        instantChapterTurn = defaults.bool(forKey: Key.instantChapterTurn)
        showsRefreshButton = defaults.bool(forKey: Key.showsRefreshButton)
        paperColor = EInkPaperColor(rawValue: defaults.integer(forKey: Key.paperColor)) ?? .gray
    }

    // MARK: - Ghi

    public func setEnabled(_ value: Bool) {
        guard value != isEnabled else { return }
        defaults.set(value, forKey: Key.enabled)
        isEnabled = value
        // Appearance proxy của UIKit **không retroactive**: `EInkAppearance` vừa cài proxy cho thanh dựng
        // sau, vừa quét window hiện có để thanh đang mở đổi ngay.
        EInkAppearance.apply()
    }

    public func setMonochromeCovers(_ value: Bool) {
        defaults.set(value, forKey: Key.monochromeCovers)
        monochromeCovers = value
    }

    public func setHideCovers(_ value: Bool) {
        defaults.set(value, forKey: Key.hideCovers)
        hideCovers = value
    }

    public func setInstantChapterTurn(_ value: Bool) {
        defaults.set(value, forKey: Key.instantChapterTurn)
        instantChapterTurn = value
    }

    public func setShowsRefreshButton(_ value: Bool) {
        defaults.set(value, forKey: Key.showsRefreshButton)
        showsRefreshButton = value
    }

    public func setPaperColor(_ value: EInkPaperColor) {
        guard value != paperColor else { return }
        defaults.set(value.rawValue, forKey: Key.paperColor)
        paperColor = value
        // Appearance proxy của UIKit không retroactive — áp lại proxy và các thanh đang mở để nhận nền
        // giấy mới ngay.
        EInkAppearance.apply()
    }
}
