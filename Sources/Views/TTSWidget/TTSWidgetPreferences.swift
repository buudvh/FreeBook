import Foundation
import Combine

/// Cài đặt kiểu widget TTS (1.3.796) cho tầng chạy: window manager đổi container khi `style` đổi, thanh nghe nhạc đọc hai
/// công tắc thu gọn. Màn `TTSWidgetSettingsView` ghi bằng `@AppStorage` trên đúng các khoá này; ở đây nạp lại theo
/// `UserDefaults.didChangeNotification` (khuôn `BookListLayoutPreferences`) và **chỉ phát khi giá trị khác** — thanh tự ghi
/// vị trí / trạng thái thu gọn cũng làm thông báo này bắn, không được kéo theo dựng lại.
///
/// Khoá không có dấu chấm (`@AppStorage` + KVO). Khoá vắng ⇒ mặc định: `.disc`, thu gọn khi mở Reader **bật**, tự thu
/// gọn sau 5 giây **tắt**.
@MainActor
final class TTSWidgetPreferences: ObservableObject {
    static let shared = TTSWidgetPreferences()

    nonisolated static let styleKey = "ttsWidgetStyle"
    nonisolated static let collapsesInReaderKey = "ttsWidgetBarCollapsesInReader"
    nonisolated static let autoCollapseKey = "ttsWidgetBarAutoCollapse"
    nonisolated static let defaultStyle: TTSWidgetStyle = .disc
    nonisolated static let defaultCollapsesInReader = true
    nonisolated static let defaultAutoCollapse = false

    @Published private(set) var style: TTSWidgetStyle
    @Published private(set) var collapsesInReader: Bool
    @Published private(set) var autoCollapse: Bool

    private var defaultsObserver: NSObjectProtocol?

    private init() {
        style = Self.readStyle()
        collapsesInReader = Self.readBool(Self.collapsesInReaderKey, fallback: Self.defaultCollapsesInReader)
        autoCollapse = Self.readBool(Self.autoCollapseKey, fallback: Self.defaultAutoCollapse)
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadIfChanged()
            }
        }
    }

    private func reloadIfChanged() {
        let newStyle = Self.readStyle()
        if newStyle != style { style = newStyle }
        let newCollapsesInReader = Self.readBool(Self.collapsesInReaderKey, fallback: Self.defaultCollapsesInReader)
        if newCollapsesInReader != collapsesInReader { collapsesInReader = newCollapsesInReader }
        let newAutoCollapse = Self.readBool(Self.autoCollapseKey, fallback: Self.defaultAutoCollapse)
        if newAutoCollapse != autoCollapse { autoCollapse = newAutoCollapse }
    }

    nonisolated private static func readStyle() -> TTSWidgetStyle {
        UserDefaults.standard.string(forKey: styleKey).flatMap(TTSWidgetStyle.init(rawValue:)) ?? defaultStyle
    }

    nonisolated private static func readBool(_ key: String, fallback: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? fallback
    }
}
