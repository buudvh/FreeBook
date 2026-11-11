import Foundation

/// Danh sách ngôn ngữ / model / kiểu dịch của một tiện ích dịch (`language.js`, `model.js`, `style.js`), nhớ trong
/// RAM theo tiện ích + dấu vân tay (cập nhật tiện ích hay sửa config là đọc lại). Mỗi lần đọc một executor mới.
///
/// Script không khai trong `plugin.json` ⇒ danh sách rỗng (giao diện ẩn ô chọn tương ứng). Lỗi đọc ném ra cho giao
/// diện hiện, không nhớ lỗi.
actor TranslationExtensionCatalog {
    static let shared = TranslationExtensionCatalog()

    struct Options: Sendable {
        /// Ngôn ngữ làm nguồn được (đã gồm "Tự nhận" ở đầu khi tiện ích khai `support_auto_detect`).
        let sourceLanguages: [TranslationLanguageOption]
        /// Ngôn ngữ làm đích được.
        let targetLanguages: [TranslationLanguageOption]
        let models: [TranslationPickerOption]
        let styles: [TranslationPickerOption]

        /// Cặp mặc định khi mới chọn tiện ích: Trung → Việt nếu có, không thì mục đầu (bỏ qua "Tự nhận").
        var defaultLanguages: (from: String, to: String) {
            let sources = sourceLanguages.filter { !$0.id.isEmpty }
            let from = sources.first(where: { Self.matches($0.id, "zh") })?.id ?? sources.first?.id ?? ""
            let to = targetLanguages.first(where: { Self.matches($0.id, "vi") })?.id ?? targetLanguages.first?.id ?? "vi"
            return (from, to)
        }

        private static func matches(_ id: String, _ code: String) -> Bool {
            let lowered = id.lowercased()
            return lowered == code || lowered.hasPrefix(code + "-") || lowered.hasPrefix(code + "_")
        }
    }

    private var cache: [String: Options] = [:]

    func options(packageId: String) async throws -> Options {
        let context = try TranslationExtensionContext.load(packageId: packageId)
        let key = packageId + "|" + context.fingerprint
        if let cached = cache[key] { return cached }

        let languages = try await list(scriptKey: "language", context: context)
        let parsedLanguages = languages.compactMap(Self.language(from:))
        let models = try await list(scriptKey: "model", context: context).compactMap(Self.picker(from:))
        let styles = try await list(scriptKey: "style", context: context).compactMap(Self.picker(from:))

        var sources = parsedLanguages.filter(\.canBeSource)
        if context.supportsAutoDetect { sources.insert(.autoDetect, at: 0) }
        let options = Options(
            sourceLanguages: sources,
            targetLanguages: parsedLanguages.filter(\.canBeTarget),
            models: models,
            styles: styles
        )
        cache[key] = options
        return options
    }

    func invalidate(packageId: String? = nil) {
        guard let packageId else {
            cache.removeAll()
            return
        }
        cache = cache.filter { !$0.key.hasPrefix(packageId + "|") }
    }

    // MARK: - Nội bộ

    private func list(scriptKey: String, context: TranslationExtensionContext) async throws -> [[String: Any]] {
        guard context.declaredScripts.contains(scriptKey) else { return [] }
        let executor = try context.makeExecutor(scriptKey: scriptKey)
        let value = try await executor.callAsync(functionName: "execute", arguments: [])
        return try TranslationExtensionResultParser.objectList(from: value)
    }

    private static func language(from object: [String: Any]) -> TranslationLanguageOption? {
        guard let id = stringValue(object["id"]), !id.isEmpty else { return nil }
        let direction: TranslationLanguageOption.Direction
        switch stringValue(object["type"])?.lowercased() {
        case "from": direction = .from
        case "to": direction = .to
        default: direction = .both
        }
        return TranslationLanguageOption(id: id, name: stringValue(object["name"]), direction: direction)
    }

    private static func picker(from object: [String: Any]) -> TranslationPickerOption? {
        guard let id = stringValue(object["id"]), !id.isEmpty else { return nil }
        return TranslationPickerOption(id: id, name: stringValue(object["name"]), description: stringValue(object["description"]))
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}
