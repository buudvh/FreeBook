import Foundation

/// Quản lý cấu hình dịch thuật phân cấp 3 mức: Truyện (Book) > Nguồn (Source) > Toàn cục (Global).
public final class TranslationConfigStore: @unchecked Sendable {
    public static let shared = TranslationConfigStore()

    public static let didChangeNotification = Notification.Name("TranslationConfigStoreDidChangeNotification")

    public typealias OverrideMode = ScopeOverride

    public enum ScopeOverride: Int, Codable, CaseIterable, Sendable {
        case inherited = 0 // Theo cấp cha (Truyện theo Nguồn, Nguồn theo Toàn cục)
        case enabled = 1   // Luôn Bật dịch
        case disabled = 2  // Luôn Tắt dịch

        public var title: String {
            switch self {
            case .inherited: return "Mặc định (Kế thừa)"
            case .enabled: return "Luôn Bật"
            case .disabled: return "Luôn Tắt"
            }
        }
    }

    public enum ResolvedOrigin: String, Sendable {
        case book = "Truyện này"
        case source = "Nguồn này"
        case global = "Toàn cục"
    }

    public struct ResolvedStatus: Sendable {
        public let isEnabled: Bool
        public let origin: ResolvedOrigin
        public let bookOverride: ScopeOverride
        public let sourceOverride: ScopeOverride
        public let globalEnabled: Bool
    }

    private let lock = NSLock()
    private let bookOverridesKey = "FreeBook_Translation_Book_Overrides_V1"
    private let sourceOverridesKey = "FreeBook_Translation_Source_Overrides_V1"
    private let globalKey = "isTranslationEnabled"
    private var sourceIsChineseMap: [String: Bool] = [:]

    private init() {}

    public func registerSource(packageId: String, isChinese: Bool) {
        guard !packageId.isEmpty, packageId != "local" else { return }
        lock.lock()
        sourceIsChineseMap[packageId.lowercased()] = isChinese
        lock.unlock()
    }

    // MARK: - Global Scope
    public var globalEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: globalKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: globalKey)
            notifyChange()
        }
    }

    // MARK: - Book Scope
    public func getBookOverride(bookId: String) -> ScopeOverride {
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: bookOverridesKey) as? [String: Int] ?? [:]
        guard let raw = dict[bookId], let mode = ScopeOverride(rawValue: raw) else {
            return .inherited
        }
        return mode
    }

    public func setBookOverride(bookId: String, mode: ScopeOverride) {
        lock.lock()
        var dict = UserDefaults.standard.dictionary(forKey: bookOverridesKey) as? [String: Int] ?? [:]
        if mode == .inherited {
            dict.removeValue(forKey: bookId)
        } else {
            dict[bookId] = mode.rawValue
        }
        UserDefaults.standard.set(dict, forKey: bookOverridesKey)
        lock.unlock()
        notifyChange()
    }

    // MARK: - Source Scope
    public func getSourceOverride(packageId: String) -> ScopeOverride {
        lock.lock()
        defer { lock.unlock() }
        let normalized = packageId.isEmpty ? "local" : packageId
        let dict = UserDefaults.standard.dictionary(forKey: sourceOverridesKey) as? [String: Int] ?? [:]
        guard let raw = dict[normalized], let mode = ScopeOverride(rawValue: raw) else {
            return .inherited
        }
        return mode
    }

    public func setSourceOverride(packageId: String, mode: ScopeOverride) {
        lock.lock()
        let normalized = packageId.isEmpty ? "local" : packageId
        var dict = UserDefaults.standard.dictionary(forKey: sourceOverridesKey) as? [String: Int] ?? [:]
        if mode == .inherited {
            dict.removeValue(forKey: normalized)
        } else {
            dict[normalized] = mode.rawValue
        }
        UserDefaults.standard.set(dict, forKey: sourceOverridesKey)
        lock.unlock()
        notifyChange()
    }

    // MARK: - Resolution
    public func isTranslationEnabled(bookId: String?, packageId: String? = nil, isChineseSourceHint: Bool? = nil) -> Bool {
        resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint).isEnabled
    }

    public func isChineseSource(packageId: String) -> Bool {
        guard !packageId.isEmpty, packageId != "local" else { return false }
        lock.lock()
        if let cached = sourceIsChineseMap[packageId.lowercased()] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupport = paths.first else { return false }
        let extDir = appSupport.appendingPathComponent("extensions", isDirectory: true)
            .appendingPathComponent(packageId, isDirectory: true)

        var pluginJsonUrl = extDir.appendingPathComponent("plugin.json")
        if !FileManager.default.fileExists(atPath: pluginJsonUrl.path) {
            if let contents = try? FileManager.default.contentsOfDirectory(at: extDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for item in contents {
                    let sub = item.appendingPathComponent("plugin.json")
                    if FileManager.default.fileExists(atPath: sub.path) {
                        pluginJsonUrl = sub
                        break
                    }
                }
            }
        }

        guard let data = try? Data(contentsOf: pluginJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let meta = json["metadata"] as? [String: Any] ?? json
        let type = ((meta["type"] as? String) ?? (json["type"] as? String) ?? "").lowercased()
        let locale = ((meta["locale"] as? String) ?? (meta["language"] as? String) ?? (json["locale"] as? String) ?? "").lowercased()
        let isChinese = type == "chinese_novel" || locale.contains("zh") || locale.contains("cn")

        lock.lock()
        sourceIsChineseMap[packageId.lowercased()] = isChinese
        lock.unlock()
        return isChinese
    }

    public func resolveStatus(bookId: String?, packageId: String? = nil, isChineseSourceHint: Bool? = nil) -> ResolvedStatus {
        let global = globalEnabled
        let bOverride = bookId.flatMap { getBookOverride(bookId: $0) } ?? .inherited
        let sOverride = packageId.flatMap { getSourceOverride(packageId: $0) } ?? .inherited

        if bOverride == .enabled {
            return ResolvedStatus(isEnabled: true, origin: .book, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
        } else if bOverride == .disabled {
            return ResolvedStatus(isEnabled: false, origin: .book, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
        }

        if sOverride == .enabled {
            return ResolvedStatus(isEnabled: true, origin: .source, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
        } else if sOverride == .disabled {
            return ResolvedStatus(isEnabled: false, origin: .source, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
        }

        if let hint = isChineseSourceHint, let pkgId = packageId, !pkgId.isEmpty {
            registerSource(packageId: pkgId, isChinese: hint)
            return ResolvedStatus(isEnabled: hint, origin: .source, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
        }

        if let pkgId = packageId, !pkgId.isEmpty, pkgId != "local" {
            let isChinese = isChineseSource(packageId: pkgId)
            return ResolvedStatus(isEnabled: isChinese, origin: .source, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
        }

        return ResolvedStatus(isEnabled: global, origin: .global, bookOverride: bOverride, sourceOverride: sOverride, globalEnabled: global)
    }

    // MARK: - Management Listing
    public var allBookOverrides: [String: ScopeOverride] {
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: bookOverridesKey) as? [String: Int] ?? [:]
        var result: [String: ScopeOverride] = [:]
        for (k, v) in dict {
            if let mode = ScopeOverride(rawValue: v) {
                result[k] = mode
            }
        }
        return result
    }

    public var allSourceOverrides: [String: ScopeOverride] {
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: sourceOverridesKey) as? [String: Int] ?? [:]
        var result: [String: ScopeOverride] = [:]
        for (k, v) in dict {
            if let mode = ScopeOverride(rawValue: v) {
                result[k] = mode
            }
        }
        return result
    }

    public func resetAllOverrides() {
        lock.lock()
        UserDefaults.standard.removeObject(forKey: bookOverridesKey)
        UserDefaults.standard.removeObject(forKey: sourceOverridesKey)
        lock.unlock()
        notifyChange()
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: TranslationConfigStore.didChangeNotification, object: nil)
        }
    }
}
