import SwiftUI

/// Màn **Bộ ngoặc** của token `<[>` / `<]>` (1.3.692), kiểu danh sách 1.3.636: header chỉ có nút quay lại + `…`
/// (`.sideDrawerMenu`), nút `+` nổi, mỗi hàng `[Sửa] [Tắt/Bật] [Xoá]` (`QuickTranslationRuleBracketRow`).
///
/// Hai phạm vi:
/// - `.global` — bộ chung (`QuickTranslationRuleBracketStore`). `…` có "Khôi phục mặc định".
/// - `.book(bookId:)` — mở từ Cài đặt đọc › Token rule của truyện. Truyện chưa có bộ riêng ⇒ hiện bộ chung **chỉ xem**
///   kèm dải "Đang dùng bộ chung" và nút "Chỉnh riêng cho truyện này" (chép bộ chung làm điểm xuất phát). Đã có bộ
///   riêng ⇒ sửa được, `…` có "Dùng bộ chung" (xoá phần riêng).
///
/// Hai store đều **không** phát thay đổi (không phải `ObservableObject`), nên màn giữ bản chụp ở `@State` và đọc lại
/// sau **mọi** lần ghi và ở `onAppear`. Mỗi thao tác sửa đọc danh sách mới từ store rồi sửa trên đó — không sửa trên
/// bản chụp có thể đã cũ. Store chung tự dọn cache dịch + báo rule đổi; bộ riêng truyện thì màn này báo
/// `notifyDictionariesDidUpdate(… .config(bookId:))` như công tắc token riêng (`ReaderBookTokenSettingsView`).
struct QuickTranslationRuleBracketListView: View {
    typealias Pair = QuickTranslationRuleBracketPair
    typealias BracketStore = QuickTranslationRuleBracketStore
    typealias BookConfigStore = QuickTranslationBookEngineConfigStore

    enum Scope: Hashable {
        case global
        case book(bookId: String)
    }

    /// Đích của sheet sửa; `index == nil` = thêm cặp mới.
    struct EditorTarget: Identifiable {
        let id = UUID()
        let index: Int?
        let pair: Pair?
    }

    let scope: Scope

    @State private var pairs: [Pair]
    /// Phạm vi truyện chưa có bộ riêng ⇒ đang hiện bộ chung, chỉ xem.
    @State private var inheritsGlobal: Bool
    @State private var isGlobalCustomized: Bool
    @State private var editorTarget: EditorTarget?
    @State private var showingMenu = false
    @State private var confirmingResetGlobal = false
    @State private var confirmingUseGlobal = false

    /// Nạp ở `init` để lượt vẽ đầu đã đúng; `onAppear` đọc lại khi quay về từ màn khác.
    init(scope: Scope) {
        self.scope = scope
        let loaded = Self.load(scope)
        _pairs = State(initialValue: loaded.pairs)
        _inheritsGlobal = State(initialValue: loaded.inheritsGlobal)
        _isGlobalCustomized = State(initialValue: BracketStore.shared.isGlobalCustomized)
    }

    private static func load(_ scope: Scope) -> (pairs: [Pair], inheritsGlobal: Bool) {
        switch scope {
        case .global:
            return (BracketStore.shared.globalPairs(), false)
        case .book(let bookId):
            if let own = BookConfigStore.shared.bracketPairs(bookId: bookId) {
                return (own, false)
            }
            return (BracketStore.shared.globalPairs(), true)
        }
    }

    private var isEditable: Bool { !inheritsGlobal }

    private var countLabel: String {
        "\(pairs.filter(\.isEnabled).count)/\(pairs.count) cặp bật"
    }

    private var sectionTitle: String {
        switch scope {
        case .global: return "Bộ chung · \(countLabel)"
        case .book: return inheritsGlobal ? "Bộ chung · \(countLabel)" : "Riêng cho truyện · \(countLabel)"
        }
    }

    var body: some View {
        List { Group {
            if inheritsGlobal {
                inheritBanner
            }
            pairsSection
        }.glassSheetRows() }
        .listStyle(.plain)
        // Không dùng `.floatingAddButton`: nút chỉ có khi sửa được, mà modifier đó luôn gắn nút.
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            if isEditable {
                FloatingAddButton(accessibilityLabel: "Thêm cặp ngoặc") {
                    editorTarget = EditorTarget(index: nil, pair: nil)
                }
            }
        }
        .backPageTitle("Bộ ngoặc")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Tuỳ chọn bộ ngoặc")
            }
        }
        .sideDrawerMenu(isPresented: $showingMenu, title: "Bộ ngoặc") {
            menuItems
        }
        .sheet(item: $editorTarget) { target in
            Group {
                QuickTranslationRuleBracketEditorSheet(
                    original: target.pair,
                    existingPairs: pairs,
                    editingIndex: target.index
                ) { pair in
                    save(pair, at: target.index)
                }
            }
            .appGlassSheet()
        }
        .confirmationDialog("Khôi phục bộ ngoặc mặc định?", isPresented: $confirmingResetGlobal, titleVisibility: .visible) {
            Button("Khôi phục mặc định", role: .destructive) { resetGlobal() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bộ chung về lại \(QuickTranslationRuleBracketDefaults.pairs.count) cặp mặc định; mọi cặp đã thêm, sửa hoặc tắt sẽ mất.")
        }
        .confirmationDialog("Dùng bộ chung cho truyện này?", isPresented: $confirmingUseGlobal, titleVisibility: .visible) {
            Button("Dùng bộ chung", role: .destructive) { useGlobalForBook() }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bộ ngoặc riêng của truyện sẽ bị xoá.")
        }
        .onAppear {
            reload()
        }
    }

    // MARK: - Nội dung

    private var inheritBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Đang dùng bộ chung (\(countLabel))", systemImage: "link")
                    .font(.subheadline)
                Button("Chỉnh riêng cho truyện này") { copyGlobalToBook() }
                    .buttonStyle(.appFilled)
            }
            .padding(.vertical, 6)
        }
    }

    private var pairsSection: some View {
        Section {
            if pairs.isEmpty {
                Text(verbatim: isEditable
                     ? "Chưa có cặp ngoặc nào: <[> và <]> sẽ không khớp gì. Bấm + để thêm."
                     : "Bộ chung chưa có cặp ngoặc nào.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            // Định danh theo vị trí: dữ liệu đọc chịu lỗi nên có thể còn cặp trùng ký tự từ file sửa tay.
            ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                QuickTranslationRuleBracketRow(
                    pair: pair,
                    isEditable: isEditable,
                    onEdit: { editorTarget = EditorTarget(index: index, pair: pair) },
                    onToggle: { toggle(at: index) },
                    onDelete: { delete(at: index) }
                )
            }
        } header: {
            SectionHelpHeader(sectionTitle, texts: QuickTranslationRuleGuide.helpTexts(for: .bracketList))
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        switch scope {
        case .global:
            SideDrawerActionRow("Khôi phục mặc định", systemImage: "arrow.counterclockwise") {
                confirmingResetGlobal = true
            }
            .disabled(!isGlobalCustomized)
        case .book:
            if inheritsGlobal {
                SideDrawerActionRow("Chỉnh riêng cho truyện này", systemImage: "slider.horizontal.3") {
                    copyGlobalToBook()
                }
            } else {
                SideDrawerActionRow("Dùng bộ chung", systemImage: "arrow.uturn.backward", role: .destructive) {
                    confirmingUseGlobal = true
                }
            }
        }
    }

    // MARK: - Thao tác

    private func reload() {
        let loaded = Self.load(scope)
        pairs = loaded.pairs
        inheritsGlobal = loaded.inheritsGlobal
        isGlobalCustomized = BracketStore.shared.isGlobalCustomized
    }

    /// Lưu từ sheet: kiểm lại trên danh sách đọc mới, rồi thay (sửa) hoặc nối cuối (thêm). Trả lỗi để sheet hiện.
    private func save(_ pair: Pair, at index: Int?) -> String? {
        var current = Self.load(scope).pairs
        if let index, !current.indices.contains(index) {
            reload()
            return "Danh sách vừa đổi, cặp này không còn ở chỗ cũ. Mở lại để sửa."
        }
        if let error = BracketStore.validationError(open: pair.open, close: pair.close, in: current, excludingIndex: index) {
            return error
        }
        if let index {
            current[index] = pair
        } else {
            current.append(pair)
        }
        return persist(current, success: index == nil ? "Đã thêm cặp \(pair.open) \(pair.close)." : "Đã lưu cặp \(pair.open) \(pair.close).")
    }

    private func toggle(at index: Int) {
        var current = Self.load(scope).pairs
        guard current.indices.contains(index) else { return reload() }
        current[index].isEnabled.toggle()
        let pair = current[index]
        let verb = pair.isEnabled ? "Đã bật" : "Đã tắt"
        persist(current, success: "\(verb) cặp \(pair.open) \(pair.close).")
    }

    /// Xoá một chạm như các danh sách rule/từ điển.
    private func delete(at index: Int) {
        var current = Self.load(scope).pairs
        guard current.indices.contains(index) else { return reload() }
        let removed = current.remove(at: index)
        persist(current, success: "Đã xoá cặp \(removed.open) \(removed.close).")
    }

    /// Ghi trọn danh sách vào đúng phạm vi đang mở. `nil` = đã ghi; chuỗi = lỗi (đã báo toast).
    @discardableResult
    private func persist(_ updated: [Pair], success: String) -> String? {
        switch scope {
        case .global:
            BracketStore.shared.setGlobalPairs(updated)
            reload()
            // `setGlobalPairs` chỉ ghi log khi mã hoá hỏng — so lại để không báo "đã lưu" sai.
            guard pairs == updated else {
                let message = "Không lưu được bộ ngoặc chung."
                ToastManager.shared.show(message: message, type: .error)
                return message
            }
            ToastManager.shared.show(message: success, type: .success)
            return nil
        case .book:
            return writeBook(updated, success: success)
        }
    }

    /// `nil` = xoá bộ riêng, truyện quay về bộ chung.
    @discardableResult
    private func writeBook(_ updated: [Pair]?, success: String) -> String? {
        guard case .book(let bookId) = scope else { return nil }
        let outcome = BookConfigStore.shared.setBracketPairs(updated, bookId: bookId)
        if case .failure(let message) = outcome {
            ToastManager.shared.show(message: message, type: .error)
            reload()
            return message
        }
        // Đúng khuôn công tắc token riêng: một lời gọi, scope `.config` mang `bookId` (tự dọn cache dịch bên trong).
        TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil, scope: .config(bookId: bookId))
        reload()
        ToastManager.shared.show(message: success, type: .success)
        return nil
    }

    private func copyGlobalToBook() {
        writeBook(BracketStore.shared.globalPairs(), success: "Đã tạo bộ ngoặc riêng cho truyện này từ bộ chung.")
    }

    private func useGlobalForBook() {
        writeBook(nil, success: "Truyện này đã về dùng bộ ngoặc chung.")
    }

    private func resetGlobal() {
        BracketStore.shared.resetGlobalToDefaults()
        reload()
        ToastManager.shared.show(message: "Đã khôi phục bộ ngoặc mặc định.", type: .success)
    }
}
