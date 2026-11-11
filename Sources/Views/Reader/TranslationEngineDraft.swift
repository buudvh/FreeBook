import Foundation

/// Bản nháp **bộ dịch** của popup dịch (`TranslationScopePopupView`) cho **một** phạm vi (Truyện / Nguồn / Toàn cục):
/// bộ dịch đang chọn + ngôn ngữ nguồn → đích, kèm lựa chọn đã lưu của phạm vi lúc nạp làm mốc so sánh.
///
/// Mốc so sánh để "Lưu lại" **không** ghi lại khi bộ dịch không đổi: mỗi lần `set*Selection` của
/// `TranslationEngineStore` là một lượt `TranslateUtils.invalidateCache` ⇒ Reader/TTS dựng lại chương (và có thể gọi
/// lại tiện ích). Bấm "Lưu lại" chỉ để bật/tắt dịch thì không được kéo theo lượt dựng lại đó.
///
/// Cặp ngôn ngữ nhớ **theo từng tiện ích** trong lần mở popup (`rememberedPairs`): chỉnh B sang en → vi, chọn QT rồi
/// chọn lại B thì vẫn là en → vi, không bị mặc định đè.
struct TranslationEngineDraft {
    typealias Scope = ReaderTranslationScopeMenuView.TranslationPopupScope

    enum Choice: Hashable {
        /// Không có lựa chọn riêng ở phạm vi này (chỉ Truyện / Nguồn) ⇒ lưu `nil`.
        case inherit
        case quickTranslator
        case extensionEngine(String)

        var packageId: String? {
            if case .extensionEngine(let id) = self { return id }
            return nil
        }
    }

    private struct LanguagePair {
        let from: String
        let to: String
    }

    private(set) var choice: Choice
    var from: String {
        didSet { rememberPair() }
    }
    var to: String {
        didSet { rememberPair() }
    }
    /// Lựa chọn đã lưu của phạm vi lúc nạp; `nil` = đang theo cấp trên.
    let saved: TranslationEngineSelection?
    /// Cặp ngôn ngữ đã đặt cho từng tiện ích trong bản nháp này (người dùng chọn / mặc định của tiện ích).
    private var rememberedPairs: [String: LanguagePair] = [:]

    private init(choice: Choice, from: String, to: String, saved: TranslationEngineSelection?) {
        self.choice = choice
        self.from = from
        self.to = to
        self.saved = saved
    }

    /// Nạp lựa chọn đã lưu của `scope`. Đọc `TranslationEngineStore` (có lock, không cô lập actor) ⇒ gọi được trong
    /// `init` của view.
    static func load(scope: Scope, bookId: String, packageId: String) -> TranslationEngineDraft {
        let store = TranslationEngineStore.shared
        let saved: TranslationEngineSelection?
        switch scope {
        case .book: saved = store.bookSelection(bookId: bookId)
        case .source: saved = store.sourceSelection(packageId: packageId)
        case .global: saved = store.globalSelection
        }
        guard let saved else {
            let fallback = TranslationEngineSelection.quickTranslator
            return TranslationEngineDraft(choice: .inherit, from: fallback.from, to: fallback.to, saved: nil)
        }
        let choice: Choice = saved.packageId.map { .extensionEngine($0) } ?? .quickTranslator
        return TranslationEngineDraft(choice: choice, from: saved.from, to: saved.to, saved: saved)
    }

    /// Đổi bộ dịch. Trả `true` khi cần đặt ngôn ngữ mặc định của tiện ích (chưa có cặp nào cho nó); chọn lại tiện ích
    /// đã chỉnh trong bản nháp / đã lưu thì trả lại đúng cặp đó.
    mutating func select(_ newChoice: Choice) -> Bool {
        guard newChoice != choice else { return false }
        choice = newChoice
        guard let id = newChoice.packageId else { return false }
        if let pair = rememberedPairs[id] {
            from = pair.from
            to = pair.to
            return false
        }
        if let saved, saved.packageId == id {
            from = saved.from
            to = saved.to
            return false
        }
        return true
    }

    /// Đã có cặp ngôn ngữ thật của tiện ích (đã lưu, người dùng chọn hoặc mặc định của nó). Chưa có ⇒ `from`/`to`
    /// còn là của bộ dịch trước, chưa được lưu.
    func hasLanguagePair(for packageId: String) -> Bool {
        rememberedPairs[packageId] != nil || saved?.packageId == packageId
    }

    mutating func applyDefaultLanguages(of options: TranslationExtensionCatalog.Options) {
        let defaults = options.defaultLanguages
        from = defaults.from
        to = defaults.to
    }

    /// Gọi từ `didSet` của `from`/`to`: gán cặp cho tiện ích đang chọn (QT / theo cấp trên không nhớ gì).
    private mutating func rememberPair() {
        guard let id = choice.packageId else { return }
        rememberedPairs[id] = LanguagePair(from: from, to: to)
    }

    /// Lựa chọn sẽ ghi; `nil` = theo cấp trên. QT luôn dịch Trung → Việt nên không mang ngôn ngữ của tiện ích cũ.
    var selection: TranslationEngineSelection? {
        switch choice {
        case .inherit: return nil
        case .quickTranslator: return .quickTranslator
        case .extensionEngine(let id): return TranslationEngineSelection(packageId: id, from: from, to: to)
        }
    }

    /// Ghi bộ dịch vào phạm vi `scope` nếu khác lựa chọn đã lưu. Trả `true` khi đã ghi.
    @discardableResult
    func save(scope: Scope, bookId: String, packageId: String) -> Bool {
        let store = TranslationEngineStore.shared
        switch scope {
        case .book:
            guard !bookId.isEmpty, !Self.isSame(selection, saved) else { return false }
            store.setBookSelection(selection, bookId: bookId)
        case .source:
            guard !packageId.isEmpty, !Self.isSame(selection, saved) else { return false }
            store.setSourceSelection(selection, packageId: packageId)
        case .global:
            // Toàn cục không có "Theo cấp trên": `.inherit` (không thể chọn ở đây) coi như QT.
            let value = selection ?? .quickTranslator
            guard !Self.isSame(value, saved) else { return false }
            store.setGlobalSelection(value)
        }
        return true
    }

    /// Hai lựa chọn QT luôn bằng nhau (QT bỏ qua `from`/`to`); còn lại so đủ tiện ích + ngôn ngữ.
    private static func isSame(_ lhs: TranslationEngineSelection?, _ rhs: TranslationEngineSelection?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            if left.isQuickTranslator && right.isQuickTranslator { return true }
            return left == right
        default:
            return false
        }
    }
}
