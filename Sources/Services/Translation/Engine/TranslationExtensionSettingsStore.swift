import Foundation

/// Model và kiểu dịch đã chọn cho **từng tiện ích dịch** (hợp đồng: "stored per engine"), áp cho mọi truyện dùng tiện
/// ích đó. `""` = chưa chọn ⇒ truyền `""` cho `translate.js`, script tự dùng mặc định của nó.
///
/// Đổi giá trị ⇒ `TranslateUtils.invalidateCache()` (Reader/TTS dựng lại) + `TranslationEngineStore.didChangeNotification`.
public final class TranslationExtensionSettingsStore: @unchecked Sendable {
    public static let shared = TranslationExtensionSettingsStore()

    private let modelKey = "FreeBook_TranslationExtension_Model_V1"
    private let styleKey = "FreeBook_TranslationExtension_Style_V1"
    private let lock = NSLock()

    private init() {}

    public func model(packageId: String) -> String {
        read(key: modelKey, packageId: packageId)
    }

    public func style(packageId: String) -> String {
        read(key: styleKey, packageId: packageId)
    }

    public func setModel(_ model: String, packageId: String) {
        write(model, key: modelKey, packageId: packageId)
    }

    public func setStyle(_ style: String, packageId: String) {
        write(style, key: styleKey, packageId: packageId)
    }

    // MARK: - Nội bộ

    private func read(key: String, packageId: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[packageId] ?? ""
    }

    private func write(_ value: String, key: String, packageId: String) {
        guard !packageId.isEmpty else { return }
        lock.lock()
        var map = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        let changed = (map[packageId] ?? "") != value
        map[packageId] = value.isEmpty ? nil : value
        UserDefaults.standard.set(map, forKey: key)
        lock.unlock()
        guard changed else { return }
        TranslateUtils.invalidateCache()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: TranslationEngineStore.didChangeNotification, object: nil)
        }
    }
}
