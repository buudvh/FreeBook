import Foundation
import Observation

/// Mốc "cấu hình dịch / phồn → giản vừa đổi" cho các danh sách tự tra `ChineseTextPipeline.Options` (1.3.846): Kệ,
/// Lịch sử, Khám phá, Tìm kiếm… đọc `value` trong `body` (hoặc trong khoá `.task(id:)`) thì vẽ lại khi popup dịch lưu ở
/// **bất kỳ** cấp nào. Trước đây các danh sách đó chỉ vẽ lại theo `@AppStorage("isTranslationEnabled")` (cấp Tất cả).
///
/// Tăng khi: `TranslationConfigStore.didChangeNotification` (mọi chỗ ghi qua store), công tắc dịch Tất cả đổi (Cài đặt
/// ghi thẳng `UserDefaults` qua `@AppStorage`, không qua store), từ điển / rule đổi (`translationDictionariesDidUpdate`,
/// `quickTranslationRulesDidUpdate`), bộ dịch đổi (`TranslationEngineStore.didChangeNotification`, 1.3.852 — màn dịch
/// bằng tiện ích dựng lại `ChineseTextExtensionTranslator.Request`).
@MainActor
@Observable
final class TranslationDisplayRevision {
    static let shared = TranslationDisplayRevision()

    private(set) var value = 0

    @ObservationIgnored private var lastGlobalEnabled: Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        lastGlobalEnabled = TranslationConfigStore.shared.globalEnabled
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: TranslationConfigStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bump() }
        })
        let names: [Notification.Name] = [
            .translationDictionariesDidUpdate, .quickTranslationRulesDidUpdate,
            TranslationEngineStore.didChangeNotification
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.bump() }
            })
        }
        // `UserDefaults.didChangeNotification` bắn cho **mọi** khoá ⇒ chỉ tăng khi công tắc dịch Tất cả thật sự đổi.
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkGlobalToggle() }
        })
    }

    private func bump() {
        lastGlobalEnabled = TranslationConfigStore.shared.globalEnabled
        value &+= 1
    }

    private func checkGlobalToggle() {
        let current = TranslationConfigStore.shared.globalEnabled
        guard current != lastGlobalEnabled else { return }
        bump()
    }
}
