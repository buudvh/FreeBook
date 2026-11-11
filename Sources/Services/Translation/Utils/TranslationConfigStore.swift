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
    /// Phồn→giản theo nguồn — ba trạng thái từ 1.3.845 (`true` bật, `false` tắt, vắng = theo Tất cả).
    private let sourceTraditionalKey = "FreeBook_Translation_Source_TraditionalToSimplified_V1"
    /// Phồn→giản "Tất cả" (1.3.845) — mặc định tắt.
    private let globalTraditionalKey = "FreeBook_Translation_Global_TraditionalToSimplified_V1"
    private var sourceIsChineseMap: [String: Bool] = [:]

    private init() {}

    /// Sách nhập từ file — chữ (`"local"`) và truyện tranh/phim (`LocalMediaPackage`): không có tiện ích nguồn để dò
    /// `plugin.json` ⇒ theo công tắc dịch chung, không tra/ghi cache theo nguồn.
    static func isLocalPackage(_ packageId: String) -> Bool {
        packageId == "local" || LocalMediaPackage.isLocalMedia(packageId: packageId)
    }

    public func registerSource(packageId: String, isChinese: Bool) {
        guard !packageId.isEmpty, !Self.isLocalPackage(packageId) else { return }
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
        guard !bookId.isEmpty else { return .inherited }
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: bookOverridesKey) as? [String: Int] ?? [:]
        guard let raw = dict[bookId], let mode = ScopeOverride(rawValue: raw) else {
            return .inherited
        }
        return mode
    }

    public func setBookOverride(bookId: String, mode: ScopeOverride) {
        // `bookId` rỗng (item Khám phá / Tìm kiếm chưa lưu) không được thành khoá chung cho mọi item chưa lưu.
        guard !bookId.isEmpty else { return }
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
        guard !packageId.isEmpty, !Self.isLocalPackage(packageId) else { return false }
        lock.lock()
        if let cached = sourceIsChineseMap[packageId.lowercased()] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Gói theo bản ghi đã cài; không có bản ghi ⇒ dò trên đĩa: `js/<id>.json` → `legado/<id>.json` → thư mục cũ
        // `<id>/` (hoặc thư mục con một cấp có `plugin.json`, zip bọc mọi thứ trong một thư mục).
        let recordPath = ExtensionLibraryRepository.snapshot(packageId: packageId)?.localPath ?? ""
        guard let packagePath = recordPath.isEmpty ? ExtensionFolderLocator.packagePath(packageId: packageId) : recordPath,
              let json = ExtensionPackageReader.manifest(localPath: packagePath) else {
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
        snapshot().resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint)
    }

    /// Bản chụp mọi cấp (1.3.846) — luật phân cấp nằm ở `TranslationConfigSnapshot`. Danh sách dài chụp một lần mỗi
    /// lượt dựng thay vì gọi `resolveStatus` / `convertsTraditionalToSimplified` từng hàng.
    public func snapshot() -> TranslationConfigSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        return TranslationConfigSnapshot(
            globalEnabled: defaults.bool(forKey: globalKey),
            globalConvertsTraditional: defaults.bool(forKey: globalTraditionalKey),
            bookOverrides: defaults.dictionary(forKey: bookOverridesKey) as? [String: Int] ?? [:],
            sourceOverrides: defaults.dictionary(forKey: sourceOverridesKey) as? [String: Int] ?? [:],
            sourceTraditional: defaults.dictionary(forKey: sourceTraditionalKey) as? [String: Bool] ?? [:]
        )
    }

    // MARK: - Phồn → giản
    /// Phồn→giản là **bước riêng chạy trước khi dịch** (có bật dịch hay không — 1.3.846), ba cấp như công tắc dịch (1.3.845): truyện này (khoá
    /// `convertTraditionalToSimplified_<bookId>`, vắng = theo nguồn) ⇒ nguồn (`sourceTraditionalOverride`, vắng = theo Tất
    /// cả) ⇒ Tất cả (`globalConvertsTraditional`, mặc định tắt). **Mọi** chỗ đọc (Reader, TTS, truyện tranh, Chi tiết, xuất,
    /// phụ đề / lời) đi qua hàm này; chỗ ghi là popup dịch (`TranslationTraditionalDraft`) và sheet Dịch phụ đề / Dịch lời.
    /// Trước 1.3.845 truyện chữ / tranh chỉ có cấp truyện (`convertsTraditionalToSimplified(bookId:)`, đã bỏ).
    public func convertsTraditionalToSimplified(bookId: String, packageId: String) -> Bool {
        snapshot().convertsTraditional(bookId: bookId, packageId: packageId)
    }

    /// Màn chưa có truyện (Khám phá, Tìm kiếm, bộ lọc…): Nguồn ⇒ Tất cả (1.3.846).
    public func convertsTraditionalToSimplified(packageId: String) -> Bool {
        snapshot().convertsTraditional(bookId: nil, packageId: packageId)
    }

    /// Phồn→giản "Tất cả" — cấp cuối của `convertsTraditionalToSimplified(bookId:packageId:)`.
    public var globalConvertsTraditional: Bool {
        get { UserDefaults.standard.bool(forKey: globalTraditionalKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: globalTraditionalKey)
            notifyChange()
        }
    }

    /// Phồn→giản của nguồn: `.inherited` = theo Tất cả.
    public func sourceTraditionalOverride(packageId: String) -> ScopeOverride {
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: sourceTraditionalKey) as? [String: Bool] ?? [:]
        guard let value = dict[packageId.isEmpty ? "local" : packageId] else { return .inherited }
        return value ? .enabled : .disabled
    }

    public func setSourceTraditionalOverride(packageId: String, mode: ScopeOverride) {
        lock.lock()
        let normalized = packageId.isEmpty ? "local" : packageId
        var dict = UserDefaults.standard.dictionary(forKey: sourceTraditionalKey) as? [String: Bool] ?? [:]
        switch mode {
        case .inherited: dict.removeValue(forKey: normalized)
        case .enabled: dict[normalized] = true
        case .disabled: dict[normalized] = false
        }
        UserDefaults.standard.set(dict, forKey: sourceTraditionalKey)
        lock.unlock()
        notifyChange()
    }

    /// Phồn→giản riêng của truyện / phim / album: `.inherited` = khoá theo truyện chưa từng đặt (theo nguồn).
    public func traditionalOverride(bookId: String) -> ScopeOverride {
        guard !bookId.isEmpty else { return .inherited }
        let key = Self.bookTraditionalKey(bookId)
        guard UserDefaults.standard.object(forKey: key) != nil else { return .inherited }
        return UserDefaults.standard.bool(forKey: key) ? .enabled : .disabled
    }

    public func setTraditionalOverride(bookId: String, mode: ScopeOverride) {
        guard !bookId.isEmpty else { return }
        let key = Self.bookTraditionalKey(bookId)
        switch mode {
        case .inherited: UserDefaults.standard.removeObject(forKey: key)
        case .enabled: UserDefaults.standard.set(true, forKey: key)
        case .disabled: UserDefaults.standard.set(false, forKey: key)
        }
        notifyChange()
    }

    /// Hai trạng thái của sheet Dịch phụ đề / Dịch lời: bật = `true`; chưa đặt hoặc tắt = `false` (sheet đó coi tắt là
    /// "theo Tất cả" — `setSourceConvertsTraditional(enabled: false)` xoá khoá).
    public func sourceConvertsTraditional(packageId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let dict = UserDefaults.standard.dictionary(forKey: sourceTraditionalKey) as? [String: Bool] ?? [:]
        return dict[packageId.isEmpty ? "local" : packageId] ?? false
    }

    public func setSourceConvertsTraditional(packageId: String, enabled: Bool) {
        lock.lock()
        let normalized = packageId.isEmpty ? "local" : packageId
        var dict = UserDefaults.standard.dictionary(forKey: sourceTraditionalKey) as? [String: Bool] ?? [:]
        if enabled {
            dict[normalized] = true
        } else {
            dict.removeValue(forKey: normalized)
        }
        UserDefaults.standard.set(dict, forKey: sourceTraditionalKey)
        lock.unlock()
        notifyChange()
    }

    static func bookTraditionalKey(_ bookId: String) -> String {
        "convertTraditionalToSimplified_\(bookId)"
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
