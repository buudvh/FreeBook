import Foundation

/// Lưu **bộ dịch** (QT hay tiện ích loại `translate`, kèm ngôn ngữ nguồn → đích) theo ba cấp Truyện > Nguồn > Toàn cục,
/// giống `TranslationConfigStore`. Trục này **độc lập** với công tắc bật/tắt dịch: công tắc quyết định có dịch hay
/// không, bộ dịch quyết định ai dịch khi đang bật.
///
/// - Lưu ở `UserDefaults` (JSON), không đụng `@Model Book`. Truyện / nguồn không có lựa chọn riêng ⇒ theo cấp trên;
///   toàn cục chưa đặt ⇒ QT.
/// - Đổi lựa chọn ⇒ `TranslateUtils.invalidateCache` (generation dịch đổi ⇒ Reader/TTS coi bản đã dựng là cũ) rồi
///   phát `didChangeNotification` trên main.
/// - Tiện ích được chọn mà đã gỡ / không còn là loại `translate` ⇒ `resolve` lùi về QT (`unavailablePackageId`).
public final class TranslationEngineStore: @unchecked Sendable {
    public static let shared = TranslationEngineStore()

    public static let didChangeNotification = Notification.Name("TranslationEngineStoreDidChangeNotification")
    public static let quickTranslatorName = "QT (VietPhrase, có sẵn)"

    private let globalKey = "FreeBook_TranslationEngine_Global_V1"
    private let bookKey = "FreeBook_TranslationEngine_Books_V1"
    private let sourceKey = "FreeBook_TranslationEngine_Sources_V1"

    private let lock = NSLock()
    private var cachedGlobal: TranslationEngineSelection?
    private var cachedBooks: [String: TranslationEngineSelection]?
    private var cachedSources: [String: TranslationEngineSelection]?

    private init() {}

    // MARK: - Đọc theo cấp

    public var globalSelection: TranslationEngineSelection {
        lock.lock()
        defer { lock.unlock() }
        return loadGlobal()
    }

    /// Lựa chọn riêng của truyện; `nil` = theo cấp trên.
    public func bookSelection(bookId: String) -> TranslationEngineSelection? {
        guard !bookId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return loadBooks()[bookId]
    }

    /// Lựa chọn riêng của nguồn; `nil` = theo toàn cục.
    public func sourceSelection(packageId: String) -> TranslationEngineSelection? {
        guard !packageId.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return loadSources()[Self.sourceKey(packageId)]
    }

    // MARK: - Ghi theo cấp

    public func setGlobalSelection(_ selection: TranslationEngineSelection) {
        lock.lock()
        cachedGlobal = selection
        UserDefaults.standard.set(try? JSONEncoder().encode(selection), forKey: globalKey)
        lock.unlock()
        didChange(bookId: nil)
    }

    /// `nil` = bỏ lựa chọn riêng (theo cấp trên).
    public func setBookSelection(_ selection: TranslationEngineSelection?, bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        var books = loadBooks()
        books[bookId] = selection
        cachedBooks = books
        UserDefaults.standard.set(try? JSONEncoder().encode(books), forKey: bookKey)
        lock.unlock()
        didChange(bookId: bookId)
    }

    /// `nil` = bỏ lựa chọn riêng (theo toàn cục).
    public func setSourceSelection(_ selection: TranslationEngineSelection?, packageId: String) {
        guard !packageId.isEmpty else { return }
        lock.lock()
        var sources = loadSources()
        sources[Self.sourceKey(packageId)] = selection
        cachedSources = sources
        UserDefaults.standard.set(try? JSONEncoder().encode(sources), forKey: sourceKey)
        lock.unlock()
        didChange(bookId: nil)
    }

    // MARK: - Tra

    /// Bộ dịch đang hiệu lực của truyện: truyện ⇒ nguồn ⇒ toàn cục. Gọi được từ thread bất kỳ (đọc bảng chụp có lock
    /// của `ExtensionLibraryRepository`).
    public func resolve(bookId: String?, packageId: String?) -> ResolvedTranslationEngine {
        let picked: (TranslationEngineSelection, ResolvedTranslationEngine.Origin)
        if let bookId, let selection = bookSelection(bookId: bookId) {
            picked = (selection, .book)
        } else if let packageId, let selection = sourceSelection(packageId: packageId) {
            picked = (selection, .source)
        } else {
            picked = (globalSelection, .global)
        }
        let (selection, origin) = picked
        guard let enginePackageId = selection.packageId else {
            return ResolvedTranslationEngine(selection: selection, origin: origin, extensionName: nil, unavailablePackageId: nil)
        }
        guard let ext = ExtensionLibraryRepository.snapshot(packageId: enginePackageId), Self.isTranslateExtension(ext) else {
            return ResolvedTranslationEngine(
                selection: .quickTranslator, origin: origin, extensionName: nil, unavailablePackageId: enginePackageId
            )
        }
        return ResolvedTranslationEngine(selection: selection, origin: origin, extensionName: ext.name, unavailablePackageId: nil)
    }

    /// Tiện ích loại `translate` (`ExtensionFilterGroups` gom cả biến thể chữ).
    public static func isTranslateExtension(_ ext: Extension) -> Bool {
        ExtensionFilterGroups.typeGroup(for: ext.type) == translateTypeGroup
    }

    static let translateTypeGroup = "translate"

    // MARK: - Nội bộ (gọi trong lock)

    private func loadGlobal() -> TranslationEngineSelection {
        if let cachedGlobal { return cachedGlobal }
        let value = UserDefaults.standard.data(forKey: globalKey)
            .flatMap { try? JSONDecoder().decode(TranslationEngineSelection.self, from: $0) } ?? .quickTranslator
        cachedGlobal = value
        return value
    }

    private func loadBooks() -> [String: TranslationEngineSelection] {
        if let cachedBooks { return cachedBooks }
        let value = decodeMap(forKey: bookKey)
        cachedBooks = value
        return value
    }

    private func loadSources() -> [String: TranslationEngineSelection] {
        if let cachedSources { return cachedSources }
        let value = decodeMap(forKey: sourceKey)
        cachedSources = value
        return value
    }

    private func decodeMap(forKey key: String) -> [String: TranslationEngineSelection] {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: TranslationEngineSelection].self, from: $0) } ?? [:]
    }

    /// Sách tự nhập dùng mã `"local"` như `TranslationConfigStore`.
    private static func sourceKey(_ packageId: String) -> String {
        packageId.isEmpty ? "local" : packageId
    }

    private func didChange(bookId: String?) {
        // Cache bản dịch theo dòng không cần xoá: khoá đã gồm tiện ích + ngôn ngữ, đổi qua đổi lại vẫn dùng lại được.
        TranslateUtils.invalidateCache(bookId: bookId)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: TranslationEngineStore.didChangeNotification, object: nil)
        }
    }
}
