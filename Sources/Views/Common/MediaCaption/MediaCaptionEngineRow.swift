import SwiftUI

/// Một cấp **bộ dịch** của sheet "Dịch phụ đề" / "Dịch lời" (`MediaCaptionTranslationSheet`): BỘ DỊCH
/// (`TranslationEnginePickerSection`) + NGÔN NGỮ (`TranslationLanguagePickerRow`), như popup dịch truyện
/// (`TranslationScopePopupView`). Sheet đặt hai hàng, đúng hai cấp mà công tắc dịch của sheet ghi: phim / album này
/// (`.book`, "Theo cấp trên" = theo nguồn) và nguồn (`.source`, "Theo cấp trên" = toàn cục).
///
/// Khác popup: không có "Lưu lại" — như mọi lựa chọn khác của sheet, chọn là ghi ngay vào `TranslationEngineStore` (chỉ khi
/// khác giá trị đang lưu của cấp đó). Tiện ích vừa chọn chưa có cặp ngôn ngữ (danh sách đang đọc / đọc lỗi) thì chưa ghi,
/// chờ danh sách đọc xong rồi ghi cùng ngôn ngữ mặc định của tiện ích. Ghi xong ⇒ `onChanged` (sheet đóng thì dịch lại
/// phụ đề / lời). Phần đọc danh sách ngôn ngữ chép theo popup — các hàm ở đó `private`, gắn với state của popup.
struct MediaCaptionEngineRow: View {
    typealias Scope = TranslationEngineDraft.Scope

    let scope: Scope
    let label: String
    let bookId: String
    let packageId: String
    let onChanged: () -> Void

    @State private var draft: TranslationEngineDraft
    /// Giá trị đang lưu của cấp này (`nil` = theo cấp trên) — so để khỏi ghi lại khi không đổi (mỗi lần ghi là một lượt
    /// `TranslateUtils.invalidateCache`).
    @State private var stored: TranslationEngineSelection?
    @State private var appliesDefaultLanguages = false
    @State private var catalogOptions: [String: TranslationExtensionCatalog.Options] = [:]
    @State private var catalogErrors: [String: String] = [:]
    @State private var catalogReloadToken = 0

    /// Đọc lựa chọn đã lưu ngay trong `init` (như sheet): giá trị khởi tạo của `@State` chỉ dùng ở lần dựng đầu.
    init(scope: Scope, label: String, bookId: String, packageId: String, onChanged: @escaping () -> Void) {
        self.scope = scope
        self.label = label
        self.bookId = bookId
        self.packageId = packageId
        self.onChanged = onChanged
        let loaded = TranslationEngineDraft.load(scope: scope, bookId: bookId, packageId: packageId)
        _draft = State(initialValue: loaded)
        _stored = State(initialValue: loaded.saved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TranslationEnginePickerSection(
                choice: draft.choice,
                inheritedEngineName: inheritedEngineName,
                engines: translateEngines,
                onSelect: { select($0) }
            )
            // "Theo cấp trên" ⇒ ẩn: ngôn ngữ do cấp trên quyết định.
            if draft.choice != .inherit {
                TranslationLanguagePickerRow(
                    content: languageContent,
                    from: $draft.from,
                    to: $draft.to,
                    packageId: draft.choice.packageId,
                    onRetryLoading: { reloadCatalog() }
                )
            }
        }
        .padding(.vertical, 4)
        .task(id: catalogTaskId) {
            guard let id = draft.choice.packageId else { return }
            await loadCatalog(packageId: id)
        }
        .onChange(of: draft.from) { _, _ in persistIfReady() }
        .onChange(of: draft.to) { _, _ in persistIfReady() }
    }

    // MARK: - Bộ dịch

    /// Tiện ích loại `translate` đã cài, xếp theo tên.
    private var translateEngines: [Extension] {
        ExtensionLibraryRepository.shared.installed
            .filter(TranslationEngineStore.isTranslateExtension)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Bộ dịch cấp trên đang hiệu lực (phim / album ⇒ nguồn rồi toàn cục; nguồn ⇒ toàn cục). Đọc
    /// `TranslationDisplayRevision` để hàng phim / album vẽ lại khi hàng nguồn vừa ghi.
    private var inheritedEngineName: String? {
        _ = TranslationDisplayRevision.shared.value
        let resolved: ResolvedTranslationEngine
        switch scope {
        case .book:
            resolved = TranslationEngineStore.shared.resolve(bookId: nil, packageId: packageId.isEmpty ? nil : packageId)
        case .source:
            resolved = TranslationEngineStore.shared.resolve(bookId: nil, packageId: nil)
        case .global:
            return nil
        }
        if let missing = resolved.unavailablePackageId {
            return "\(missing) (đã gỡ — đang dùng QT)"
        }
        return resolved.displayName
    }

    private func select(_ choice: TranslationEngineDraft.Choice) {
        appliesDefaultLanguages = draft.select(choice)
        // Danh sách đã có trong RAM ⇒ `task(id:)` vẫn chạy lại (id đổi) và áp mặc định ở `loadCatalog`.
        persistIfReady()
    }

    // MARK: - Ngôn ngữ

    private var languageContent: TranslationLanguagePickerRow.Content {
        guard let id = draft.choice.packageId else { return .quickTranslator }
        if let options = catalogOptions[id] { return .loaded(options) }
        if let message = catalogErrors[id] { return .failed(message) }
        return .loading
    }

    /// Tiện ích đang chọn chưa có cặp ngôn ngữ thật ⇒ `from`/`to` còn là của bộ dịch trước ⇒ chưa ghi.
    private var isLanguagePairPending: Bool {
        guard let id = draft.choice.packageId else { return false }
        return appliesDefaultLanguages || !draft.hasLanguagePair(for: id)
    }

    private var catalogTaskId: String? {
        draft.choice.packageId.map { "\($0)#\(catalogReloadToken)" }
    }

    private func reloadCatalog() {
        guard let id = draft.choice.packageId else { return }
        catalogErrors[id] = nil
        catalogReloadToken += 1
    }

    private func loadCatalog(packageId id: String) async {
        if let options = catalogOptions[id] {
            applyPendingDefaults(options, packageId: id)
            return
        }
        catalogErrors[id] = nil
        do {
            let options = try await TranslationExtensionCatalog.shared.options(packageId: id)
            catalogOptions[id] = options
            applyPendingDefaults(options, packageId: id)
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            // Giữ `appliesDefaultLanguages`: "Thử lại" đọc được thì vẫn đặt ngôn ngữ mặc định.
            catalogErrors[id] = TranslationExtensionResultParser.shortMessage(for: error)
        }
    }

    private func applyPendingDefaults(_ options: TranslationExtensionCatalog.Options, packageId id: String) {
        guard appliesDefaultLanguages, draft.choice.packageId == id else { return }
        appliesDefaultLanguages = false
        draft.applyDefaultLanguages(of: options)
        // Mặc định trùng `from`/`to` đang có thì `onChange` không chạy ⇒ ghi tại đây.
        persistIfReady()
    }

    // MARK: - Ghi

    /// Ghi lựa chọn của cấp này nếu đã đủ cặp ngôn ngữ và khác giá trị đang lưu.
    private func persistIfReady() {
        guard !isLanguagePairPending else { return }
        let value = scope == .global ? (draft.selection ?? .quickTranslator) : draft.selection
        guard !Self.isSame(value, stored) else { return }
        let store = TranslationEngineStore.shared
        switch scope {
        case .book:
            guard !bookId.isEmpty else { return }
            store.setBookSelection(value, bookId: bookId)
        case .source:
            guard !packageId.isEmpty else { return }
            store.setSourceSelection(value, packageId: packageId)
        case .global:
            store.setGlobalSelection(value ?? .quickTranslator)
        }
        stored = value
        let name = value.map { $0.packageId ?? "QT" } ?? "theo cấp trên"
        AppLogger.shared.log("🌐 [MediaCaption] Bộ dịch «\(scope.rawValue)» ⇒ \(name)")
        onChanged()
    }

    /// Hai lựa chọn QT luôn bằng nhau (QT bỏ qua `from`/`to`); còn lại so đủ tiện ích + ngôn ngữ (như `TranslationEngineDraft`).
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
