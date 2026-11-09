import Foundation
import Combine

/// Cài đặt kiểu widget TTS (1.3.796) cho tầng chạy: `TTSFloatingWidgetWindowManager` (kiểu Đĩa nổi) và
/// `MediaDiscWindowManager` (kiểu Đĩa góc dưới) hiện / ẩn theo `style`. Màn `TTSWidgetSettingsView` ghi bằng `@AppStorage`
/// trên đúng khoá này; ở đây nạp lại theo `UserDefaults.didChangeNotification` (khuôn `BookListLayoutPreferences`) và **chỉ
/// phát khi giá trị khác** — khoá khác đổi cũng làm thông báo này bắn.
///
/// Khoá không có dấu chấm (`@AppStorage` + KVO). Khoá vắng ⇒ `.disc`. Hai công tắc của kiểu "Thanh nghe nhạc" cũ
/// (`ttsWidgetBarCollapsesInReader`, `ttsWidgetBarAutoCollapse`) bỏ ở 1.3.808 — giá trị cũ còn trong máy, không ai đọc.
@MainActor
final class TTSWidgetPreferences: ObservableObject {
    static let shared = TTSWidgetPreferences()

    nonisolated static let styleKey = "ttsWidgetStyle"
    nonisolated static let defaultStyle: TTSWidgetStyle = .disc

    @Published private(set) var style: TTSWidgetStyle

    private var defaultsObserver: NSObjectProtocol?

    private init() {
        style = Self.readStyle()
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
    }

    nonisolated private static func readStyle() -> TTSWidgetStyle {
        UserDefaults.standard.string(forKey: styleKey).flatMap(TTSWidgetStyle.init(rawValue:)) ?? defaultStyle
    }
}
