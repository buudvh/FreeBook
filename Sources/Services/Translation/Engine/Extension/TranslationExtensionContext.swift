import Foundation

/// Mọi thứ cần để chạy một tiện ích dịch, đọc **một lần mỗi lượt** (mỗi chương / mỗi lần lấy danh sách): bản ghi đã cài,
/// config đã trộn (khoá API nằm ở đây), ba khoá thô của `config` trong `plugin.json`, model / kiểu đã chọn, dấu vân tay
/// dùng làm khoá cache.
///
/// Khoá thô theo hợp đồng chỉ đọc khi là giá trị JSON trần (`"max_line": 50`); chuỗi `"50"` hay object
/// `{ title, default }` bị bỏ qua.
struct TranslationExtensionContext: Sendable {
    let packageId: String
    let name: String
    let localPath: String
    let downloadUrl: String
    /// Config đã trộn (mặc định của `plugin.json` + giá trị người dùng) dạng JSON, nạp vào executor bằng `injectGlobals`.
    let configurationData: Data
    let supportsAutoDetect: Bool
    /// Số dòng tối đa mỗi lần gọi; `nil` = không giới hạn.
    let maxLines: Int?
    /// Số ký tự tối đa mỗi lần gọi; `nil` = không giới hạn. Khai `≤ 0` ⇒ không chia lô gì cả (bỏ cả `max_line`).
    let maxLength: Int?
    let disablesSplitting: Bool
    let declaredScripts: Set<String>
    let model: String
    let style: String
    /// Phiên bản + config ⇒ sửa khoá API hay cập nhật tiện ích là khoá cache đổi.
    let fingerprint: String

    enum LoadError: LocalizedError {
        case notInstalled(String)
        case notTranslateExtension(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Tiện ích dịch đã bị gỡ"
            case .notTranslateExtension(let name): return "\(name) không phải tiện ích dịch"
            }
        }
    }

    static func load(packageId: String) throws -> TranslationExtensionContext {
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: packageId) else {
            throw LoadError.notInstalled(packageId)
        }
        guard TranslationEngineStore.isTranslateExtension(ext) else {
            throw LoadError.notTranslateExtension(ext.name)
        }
        let localPath = ext.localPath
        let manifest = ExtensionPackageReader.manifest(localPath: localPath) ?? [:]
        let rawConfig = manifest["config"] as? [String: Any] ?? [:]
        let scripts = (manifest["script"] as? [String: Any]).map { Set($0.keys) } ?? []
        let configs = ExtensionManager.shared.getCombinedConfigs(localPath: localPath, configJson: ext.configJson)
        let configurationData = (try? JSONSerialization.data(withJSONObject: configs, options: [.sortedKeys])) ?? Data("{}".utf8)
        let maxLength = Self.bareInt(rawConfig["max_length"])
        let settings = TranslationExtensionSettingsStore.shared
        return TranslationExtensionContext(
            packageId: packageId,
            name: ext.name,
            localPath: localPath,
            downloadUrl: ext.downloadUrl,
            configurationData: configurationData,
            supportsAutoDetect: Self.bareBool(rawConfig["support_auto_detect"]) ?? false,
            maxLines: Self.bareInt(rawConfig["max_line"]).flatMap { $0 > 0 ? $0 : nil },
            maxLength: maxLength.flatMap { $0 > 0 ? $0 : nil },
            disablesSplitting: (maxLength ?? 1) <= 0,
            declaredScripts: scripts,
            model: settings.model(packageId: packageId),
            style: settings.style(packageId: packageId),
            fingerprint: "\(ext.version)|\(ext.updatedAt?.timeIntervalSince1970 ?? 0)|\(ext.configJson.md5())"
        )
    }

    /// Executor mới đã nạp config + script của `scriptKey`. Mỗi lượt một executor, xong là bỏ (không giữ lâu dài).
    func makeExecutor(scriptKey: String) throws -> JSExecutor {
        let script = try ExtensionManager.shared.entryScript(localPath: localPath, scriptKey: scriptKey)
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        if let globals = (try? JSONSerialization.jsonObject(with: configurationData)) as? [String: Any] {
            executor.injectGlobals(globals)
        }
        try executor.prepareScript(try script.text())
        return executor
    }

    // MARK: - Khoá thô của config

    /// Chỉ nhận số JSON (không nhận `Bool`, chuỗi hay object).
    private static func bareInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        return number.intValue
    }

    private static func bareBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBool(number) else { return nil }
        return number.boolValue
    }

    private static func isBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
