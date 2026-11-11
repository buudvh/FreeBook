import SwiftUI

/// Bảng cấu hình dịch dùng chung: công tắc "Dịch văn bản" + PHẠM VI ÁP DỤNG (Truyện này / Nguồn này / Tất cả) + BỘ DỊCH
/// (QT hay tiện ích loại `translate`, `TranslationEnginePickerSection`) + NGÔN NGỮ nguồn → đích
/// (`TranslationLanguagePickerRow`) + hàng báo "QT thay thế" của chương đang hiện + "Lưu lại".
/// Tách khỏi `ReaderTranslationScopeMenuView` để menu header Khám phá (`DiscoverySourceMenuButton`) mở lại đúng bảng này.
/// Caller tự lo nút neo và `.popover` (`.presentationCompactAdaptation(.popover)` + `.preferredColorScheme(.dark)`);
/// bảng ghi `TranslationConfigStore` (bật/tắt) + `TranslationEngineStore` (bộ dịch, chỉ khi đổi) rồi gọi `onDone` để
/// caller đóng popover.
///
/// Bộ dịch + ngôn ngữ lưu **theo phạm vi đang chọn**; đổi phạm vi ⇒ nạp lựa chọn đã lưu của phạm vi đó
/// (`TranslationEngineDraft`). Model / kiểu dịch là cài đặt riêng của tiện ích (màn Cấu hình tiện ích), ở đây chỉ hiện.
/// Màn không dùng bộ dịch (truyện tranh) truyền `showsEngineSection: false` ⇒ không có BỘ DỊCH / NGÔN NGỮ.
/// Hàng Phồn → giản (1.3.845) lưu theo phạm vi đang chọn + tự dịch lại tên chương — `TranslationTraditionalDraft`.
///
/// Công tắc hiện trạng thái **hiệu lực của truyện**, nên "Lưu lại" chỉ ghi nó vào phạm vi đang chọn khi người dùng
/// thật sự gạt nó trong lần mở này — đổi sang "Nguồn này" chỉ để chọn bộ dịch không được tắt dịch cả nguồn.
struct TranslationScopePopupView: View {
    private typealias TranslationPopupScope = ReaderTranslationScopeMenuView.TranslationPopupScope

    let bookId: String
    let packageId: String
    let sourceName: String
    let isChineseSourceHint: Bool?
    /// Chương đang hiện (Reader) — để hiện hàng báo "QT thay thế"; `nil` (Khám phá, Chi tiết) ⇒ không có hàng báo.
    let chapterIndex: Int?
    /// `false` ⇒ ẩn BỘ DỊCH / NGÔN NGỮ (màn truyện tranh: bộ dịch tiện ích không có tác dụng ở đó).
    let showsEngineSection: Bool
    let onDone: () -> Void

    @State private var tempIsEnabled: Bool
    /// Người dùng đã gạt công tắc trong lần mở này ⇒ "Lưu lại" mới ghi bật/tắt dịch.
    @State private var didToggleEnabled = false
    @State private var selectedScope: TranslationPopupScope
    @State private var engineDraft: TranslationEngineDraft
    /// Người dùng vừa chọn tiện ích khác lựa chọn đã lưu ⇒ đặt ngôn ngữ mặc định của nó khi đọc xong danh sách.
    @State private var appliesDefaultLanguages = false
    @State private var catalogOptions: [String: TranslationExtensionCatalog.Options] = [:]
    @State private var catalogErrors: [String: String] = [:]
    /// Tăng khi bấm "Thử lại" ở hàng ngôn ngữ ⇒ `task(id:)` đọc lại danh sách của tiện ích đang chọn.
    @State private var catalogReloadToken = 0
    @State private var traditionalDraft: TranslationTraditionalDraft
    @Environment(\.modelContext) private var modelContext

    init(
        bookId: String,
        packageId: String,
        sourceName: String,
        isChineseSourceHint: Bool?,
        chapterIndex: Int? = nil,
        showsEngineSection: Bool = true,
        onDone: @escaping () -> Void
    ) {
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.isChineseSourceHint = isChineseSourceHint
        self.chapterIndex = chapterIndex
        self.showsEngineSection = showsEngineSection
        self.onDone = onDone
        // Nội dung popover bị huỷ khi đóng nên mỗi lần mở đều khởi tạo lại tại đây: công tắc lấy trạng thái đang
        // hiệu lực (như `preparePopupState()` cũ của nút dịch).
        _tempIsEnabled = State(initialValue: TranslationConfigStore.shared.resolveStatus(
            bookId: bookId,
            packageId: packageId,
            isChineseSourceHint: isChineseSourceHint
        ).isEnabled)
        // Khởi tạo ngay theo phạm vi **có thật** của màn gọi: Khám phá truyền `bookId: ""` nên không bao giờ
        // được bắt đầu ở "Truyện này" (mục đó còn không có trong `Menu`). Trước đây mặc định cứng `.book` và chỉ
        // sửa trong `preparePopupState()` lúc bấm nút, nên popover vẽ lần đầu vẫn ghi "Truyện này".
        let initialScope = Self.availableScope(bookId: bookId, packageId: packageId)
        _selectedScope = State(initialValue: initialScope)
        _engineDraft = State(initialValue: TranslationEngineDraft.load(scope: initialScope, bookId: bookId, packageId: packageId))
        _traditionalDraft = State(initialValue: TranslationTraditionalDraft(bookId: bookId, packageId: packageId))
    }

    /// Phạm vi mặc định theo tham số màn gọi — chỉ chọn cấp **đang tồn tại**.
    static func availableScope(bookId: String, packageId: String) -> ReaderTranslationScopeMenuView.TranslationPopupScope {
        if !bookId.isEmpty { return .book }
        if !packageId.isEmpty { return .source }
        return .global
    }

    private var displaySourceName: String {
        if !sourceName.isEmpty {
            return sourceName
        }
        if packageId.isEmpty || packageId == "local" {
            return "Sách tự nhập (Local)"
        }
        return packageId
    }

    var body: some View {
        VStack(spacing: 12) {
            // Hàng 1: Cần gạt Bật / Tắt dịch
            HStack(spacing: 10) {
                AppGlyph.translate.image(size: 17)
                    .foregroundColor(.white)

                Text("Dịch văn bản")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Toggle("", isOn: enabledToggleBinding)
                    .labelsHidden()
                    .tint(.white)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Hàng 2: Dropdown chọn phạm vi áp dụng
            VStack(alignment: .leading, spacing: 6) {
                Text("PHẠM VI ÁP DỤNG")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Menu {
                    if !bookId.isEmpty {
                        scopeButton(.book, title: "Truyện này")
                    }
                    if !packageId.isEmpty {
                        scopeButton(.source, title: "Nguồn này (\(displaySourceName))")
                    }
                    scopeButton(.global, title: "Tất cả (Toàn cục)")
                } label: {
                    HStack {
                        Text(scopeDisplayText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            TranslationTraditionalToggleRow(isOn: Binding(get: { traditionalDraft.isOn }, set: { traditionalDraft.set($0) }))

            if showsEngineSection {
                // Hàng 3: Bộ dịch của phạm vi đang chọn (danh sách xổ tại chỗ)
                TranslationEnginePickerSection(
                    choice: engineDraft.choice,
                    inheritedEngineName: inheritedEngineName,
                    engines: translateEngines,
                    onSelect: { selectEngine($0) }
                )

                // Hàng 4: Ngôn ngữ nguồn → đích ("Theo cấp trên" ⇒ ẩn, ngôn ngữ do cấp trên quyết định)
                if engineDraft.choice != .inherit {
                    TranslationLanguagePickerRow(
                        content: languageContent,
                        from: $engineDraft.from,
                        to: $engineDraft.to,
                        packageId: engineDraft.choice.packageId,
                        onRetryLoading: { reloadCatalog() }
                    )
                }
            }

            // Hàng 5: Chương đang hiện bị tiện ích dịch lỗi
            if let fallbackStatus {
                TranslationFallbackNoticeRow(status: fallbackStatus, onRetry: { retryChapter() })
            }

            // Hàng 6: Nút Lưu lại (Tone màu trắng/tối giản)
            Button(action: saveSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Lưu lại")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLanguagePairPending)
            .opacity(isLanguagePairPending ? 0.45 : 1)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(minWidth: 260, maxWidth: 280)
        .onChange(of: selectedScope) { _, _ in
            // Mỗi phạm vi có lựa chọn đã lưu riêng: đổi phạm vi là nạp lại bản nháp của phạm vi đó.
            appliesDefaultLanguages = false
            engineDraft = TranslationEngineDraft.load(scope: effectiveScope, bookId: bookId, packageId: packageId)
        }
        .task(id: catalogTaskId) {
            guard showsEngineSection, let id = engineDraft.choice.packageId else { return }
            await loadCatalog(packageId: id)
        }
    }

    private func scopeButton(_ scope: TranslationPopupScope, title: String) -> some View {
        Button {
            selectedScope = scope
        } label: {
            HStack {
                Text(title)
                if effectiveScope == scope {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    /// Phạm vi đang chọn nhưng đã kẹp về cấp có thật: `selectedScope` có thể còn `.book` từ state khởi tạo cũ
    /// hoặc từ lần mở trước, trong khi màn hiện tại không có truyện/nguồn tương ứng.
    private var effectiveScope: TranslationPopupScope {
        switch selectedScope {
        case .book:
            return bookId.isEmpty ? Self.availableScope(bookId: bookId, packageId: packageId) : .book
        case .source:
            return packageId.isEmpty ? Self.availableScope(bookId: bookId, packageId: packageId) : .source
        case .global:
            return .global
        }
    }

    private var scopeDisplayText: String {
        switch effectiveScope {
        case .book:
            return "Truyện này"
        case .source:
            return "Nguồn này (\(displaySourceName))"
        case .global:
            return "Tất cả (Toàn cục)"
        }
    }

    // MARK: - Bộ dịch

    private var enabledToggleBinding: Binding<Bool> {
        Binding(
            get: { tempIsEnabled },
            set: { value in
                tempIsEnabled = value
                didToggleEnabled = true
            }
        )
    }

    /// Tiện ích loại `translate` đã cài, xếp theo tên.
    @MainActor
    private var translateEngines: [Extension] {
        ExtensionLibraryRepository.shared.installed
            .filter(TranslationEngineStore.isTranslateExtension)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Bộ dịch cấp trên đang hiệu lực: Truyện ⇒ nguồn rồi toàn cục; Nguồn ⇒ toàn cục; Toàn cục không có cấp trên.
    /// Cấp trên trỏ tới tiện ích đã gỡ ⇒ nói rõ thay vì chỉ ghi "QT".
    private var inheritedEngineName: String? {
        let resolved: ResolvedTranslationEngine
        switch effectiveScope {
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

    private var languageContent: TranslationLanguagePickerRow.Content {
        guard let id = engineDraft.choice.packageId else { return .quickTranslator }
        if let options = catalogOptions[id] { return .loaded(options) }
        if let message = catalogErrors[id] { return .failed(message) }
        return .loading
    }

    /// Tiện ích đang chọn chưa có cặp ngôn ngữ thật (danh sách đang đọc hoặc đọc lỗi) ⇒ `from`/`to` còn là của bộ dịch
    /// trước ⇒ khoá "Lưu lại" (hàng Ngôn ngữ đang hiện vòng xoay / lỗi kèm "Thử lại").
    private var isLanguagePairPending: Bool {
        guard showsEngineSection, let id = engineDraft.choice.packageId else { return false }
        return appliesDefaultLanguages || !engineDraft.hasLanguagePair(for: id)
    }

    private var catalogTaskId: String? {
        engineDraft.choice.packageId.map { "\($0)#\(catalogReloadToken)" }
    }

    private func reloadCatalog() {
        guard let id = engineDraft.choice.packageId else { return }
        catalogErrors[id] = nil
        catalogReloadToken += 1
    }

    private func selectEngine(_ choice: TranslationEngineDraft.Choice) {
        appliesDefaultLanguages = engineDraft.select(choice)
        // Danh sách đã có trong RAM ⇒ `task(id:)` vẫn chạy lại (id đổi) và áp mặc định ở `loadCatalog`.
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
        guard appliesDefaultLanguages, engineDraft.choice.packageId == id else { return }
        appliesDefaultLanguages = false
        engineDraft.applyDefaultLanguages(of: options)
    }

    // MARK: - Báo QT thay thế

    @MainActor
    private var fallbackStatus: TranslationFallbackStatus? {
        guard let chapterIndex, !bookId.isEmpty else { return nil }
        return TranslationFallbackStatusStore.shared.status(bookId: bookId, chapterIndex: chapterIndex)
    }

    /// "Thử lại" không lưu thay đổi đang dở của bảng — chỉ xin Reader dựng lại chương rồi đóng.
    @MainActor
    private func retryChapter() {
        guard let chapterIndex, !bookId.isEmpty else { return }
        TranslationFallbackStatusStore.shared.requestRetry(bookId: bookId, chapterIndex: chapterIndex)
        onDone()
    }

    // MARK: - Lưu

    @MainActor
    private func saveSettings() {
        let engineBefore = resolvedEngineOfBook()
        if didToggleEnabled {
            // Dùng scope đã kẹp: `bookId` rỗng mà lưu `.book` sẽ ghi override rác với khoá "" vào `UserDefaults`.
            switch effectiveScope {
            case .book:
                TranslationConfigStore.shared.setBookOverride(bookId: bookId, mode: tempIsEnabled ? .enabled : .disabled)
            case .source:
                TranslationConfigStore.shared.setSourceOverride(packageId: packageId, mode: tempIsEnabled ? .enabled : .disabled)
            case .global:
                TranslationConfigStore.shared.globalEnabled = tempIsEnabled
            }
        }
        if showsEngineSection, !isLanguagePairPending {
            // Chỉ ghi khi bộ dịch đổi: mỗi lần ghi là một lượt dựng lại chương ở Reader/TTS.
            engineDraft.save(scope: effectiveScope, bookId: bookId, packageId: packageId)
        }
        traditionalDraft.commit(scope: effectiveScope, bookId: bookId, packageId: packageId, context: modelContext)
        clearFallbackStatusIfStale(engineBefore: engineBefore)
        onDone()
    }

    private func resolvedEngineOfBook() -> TranslationEngineSelection? {
        guard !bookId.isEmpty else { return nil }
        return TranslationEngineStore.shared.resolve(bookId: bookId, packageId: packageId.isEmpty ? nil : packageId).selection
    }

    /// Truyện đổi bộ dịch đang hiệu lực / tắt dịch ⇒ báo "QT thay thế" của các chương đã dựng không còn đúng.
    @MainActor
    private func clearFallbackStatusIfStale(engineBefore: TranslationEngineSelection?) {
        guard !bookId.isEmpty else { return }
        let isEnabled = TranslationConfigStore.shared.resolveStatus(
            bookId: bookId,
            packageId: packageId,
            isChineseSourceHint: isChineseSourceHint
        ).isEnabled
        guard !isEnabled || resolvedEngineOfBook() != engineBefore else { return }
        TranslationFallbackStatusStore.shared.clear(bookId: bookId)
    }
}
