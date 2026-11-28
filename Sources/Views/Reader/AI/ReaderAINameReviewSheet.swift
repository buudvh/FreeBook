import SwiftUI
import SwiftData

/// Bottom sheet hiển thị danh sách tên riêng trích xuất từ tin nhắn AI với hiệu ứng Skeleton bất đồng bộ.
///
/// Góc phải header là nút **▼** (tam giác đặc; mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M1, mục C8
/// — thay chữ "Lưu" có từ 1.3.469) mở `Menu` ba mục:
/// - "Lưu vào Name riêng" / "Lưu vào VP riêng": có name đã có trong file đích của truyện thì hỏi cách lưu bằng popup ba
///   chế độ như nhập file (`+Save`, plan 2026-11-27-phan-loai-name L16), toàn name mới thì lưu thẳng;
/// - ngăn cách, "Xuất file" (dòng phụ: số mục sẽ xuất): ghi đúng tập mục Lưu sẽ ghi ra `Name_<tên truyện>_<ngày giờ>.txt`
///   rồi mở bảng chia sẻ (`+Export`).
/// Chưa tích mục nào ⇒ hai mục Lưu mờ; không có dòng nào để xuất ⇒ "Xuất file" mờ. Menu luôn mở được.
public struct ReaderAINameReviewSheet: View {
    public struct Target: Identifiable, Sendable {
        public let id = UUID()
        public let content: String
        /// Tin nguồn — nút thùng rác gạch / bỏ gạch name trong chính tin này (`ReaderAIFullScreenView.setNameStruck`).
        public let messageId: UUID
        /// Khoá đã gạch của tin lúc mở sheet (`AIChatMessage.struckNameKeys`).
        public let struckKeys: [String]

        public init(content: String, messageId: UUID, struckKeys: [String] = []) {
            self.content = content
            self.messageId = messageId
            self.struckKeys = struckKeys
        }
    }

    // `internal` (không `private`): `+Save` đóng sheet sau khi giao việc lưu.
    @Environment(\.dismiss) var dismiss

    public let content: String
    public let bookId: String
    /// Bấm Lưu: mục đang chọn (không gạch), `true` = Name riêng / `false` = VP riêng, cách lưu (`DataImportMode`, `+Save`).
    public let onSave: ([AIExtractedName], Bool, DataImportMode) -> Void
    /// Luồng AI: bấm thùng rác / ↶ của một name ⇒ nhận **khoá** (vế trái đã trim) + `true` gạch / `false` bỏ gạch, để nơi
    /// gọi ghi vào tin nguồn (`AIChatMessage.struckNameKeys`). Dòng trong tin **không** bị xoá (anh Bửu 2026-11-27).
    public let onStrikeName: (String, Bool) -> Void
    /// Bấm "Cập nhật" ở màn Sửa từ của một name (1.3.780, `+Edit`): nhận phép sửa để nơi gọi ghi vào tin nguồn.
    public let onEditName: (AINameEdit) -> Void
    /// Danh sách có sẵn (luồng "Lọc name local", `LocalNameFilterSheet`): bỏ bước tách dòng `từ=nghĩa` khỏi tin AI.
    /// `nil` = luồng AI.
    let prefilledNames: [AIExtractedName]?
    /// Kiểu sắp lúc mở card: luồng AI "Đã chọn trước", luồng lọc local "Chưa có trước" (name chưa có trong Name / VP lên
    /// đầu, rồi số lần — `ReaderAINameReviewCardView.SortMode.notInDictionaryFirst`).
    let initialSortMode: ReaderAINameReviewCardView.SortMode
    /// Thùng rác › "Không phải name" — chỉ luồng lọc local truyền; luồng AI gạch hàng (`onStrikeName`).
    public let onBlockName: ((AIExtractedName) -> Void)?
    /// Luồng lọc local: danh sách đang duyệt mỗi lần đổi (chọn / bỏ chọn, sửa, bỏ mục, cờ NE / VP tra lại) — nơi gọi giữ
    /// bản mới nhất để thành gói tạm khi đóng màn mà chưa Lưu (`LocalNameFilterSession+Drafts`). Luồng AI: `nil`.
    let onNamesChange: (([AIExtractedName]) -> Void)?
    /// Nút ‹ ở header (plan 2026-11-27-nghia-ten-tay-huyen mục 5, chỉ luồng lọc local): có ⇒ header là `HeaderBackButton`
    /// + tiêu đề ngay cạnh (`PageTitleModifier` kiểu `.centered` đọc `\.sheetPageBack`); bấm ⇒ nơi gọi giữ gói tạm rồi về
    /// trang đầu "Lọc name local", sheet không đóng. Luồng AI: `nil` ⇒ header như cũ.
    let onBack: (() -> Void)?
    /// Luồng lọc local: hàng "Tiền tố" + "Hậu tố" ở màn Sửa từ của mọi name trừ họ tộc + ghép lại nghĩa ngay sau khi thêm /
    /// sửa một mục (plan 2026-11-27-nghia-ten-tay-huyen mục 7, 2026-11-27-phan-loai-name L10 / L11, `+Edit`). Luồng AI: `nil`.
    let localSuffixContext: LocalNameFilterReviewSuffixContext?
    /// Tên truyện cho tên file "Xuất file" (`+Export`) — luồng AI truyền tên đang hiện ở màn AI (màn đó có thể mở bằng UIKit,
    /// môi trường không có `ModelContainer`). `nil` (luồng lọc local) ⇒ tra `Book` theo `bookId` trong `modelContext`.
    let exportBookTitle: String?
    /// `\.sheetPageBack` của nơi trình bày — trả lại cho sheet Sửa từ để nút ‹ của màn duyệt không lan vào đó.
    @Environment(\.sheetPageBack) private var inheritedSheetPageBack
    // `internal` (không `private`): `+Export` tra tên truyện; chỉ đọc khi `exportBookTitle == nil`.
    @Environment(\.modelContext) var modelContext

    @State private var isLoading: Bool = true
    // `internal` (không `private`): `ReaderAINameReviewSheet+Edit.swift` dùng chung.
    @State var names: [AIExtractedName] = []
    @State var editingName: AIExtractedName? = nil
    // Popup chọn cách lưu (`+Save`): đích, số name mới / đã có trong file đích, đang đọc file đích.
    @State var pendingIsName: Bool = true
    @State var pendingNewCount: Int = 0
    @State var pendingExistingCount: Int = 0
    @State var showingSavePopup: Bool = false
    @State var isCheckingSaveTarget: Bool = false
    /// File "Xuất file" đang đưa cho bảng chia sẻ (`+Export`).
    @State var exportedFile: ExportedFile? = nil
    /// Khoá đang gạch (luồng AI) — khởi tạo từ tin nguồn, mỗi lần gạch / bỏ gạch ghi ngay qua `onStrikeName`.
    // `internal` (không `private`): `+Edit` bỏ gạch khoá đích khi người dùng sửa một name thành khoá đang gạch.
    @State var struckKeys: Set<String>

    public init(
        content: String,
        bookId: String,
        struckKeys: Set<String> = [],
        onSave: @escaping ([AIExtractedName], Bool, DataImportMode) -> Void,
        onStrikeName: @escaping (String, Bool) -> Void = { _, _ in },
        onEditName: @escaping (AINameEdit) -> Void = { _ in },
        exportBookTitle: String? = nil
    ) {
        self.content = content
        self.bookId = bookId
        self.onSave = onSave
        self.onStrikeName = onStrikeName
        self.onEditName = onEditName
        self.exportBookTitle = exportBookTitle
        self.prefilledNames = nil
        self.initialSortMode = .selectedFirst
        self.onBlockName = nil
        self.onNamesChange = nil
        self.onBack = nil
        self.localSuffixContext = nil
        self._struckKeys = State(initialValue: struckKeys)
    }

    /// Luồng "Lọc name local": nhận sẵn danh sách (đã gắn cờ NE / VP, name đã có bỏ chọn sẵn; `occurrenceCount` = số lần
    /// thấy; mở lại gói tạm ⇒ đúng trạng thái đã giữ), sắp "Chưa có trước", chip lọc theo loại + badge loại có màu
    /// (`ReaderAINameReviewCardView.showsCategoryFilter`), ✕ có "Không phải name" (`onBlockName`), nút ‹ về trang đầu
    /// (`onBack`). Sửa một name chỉ đổi danh sách đang duyệt (không có tin nguồn).
    public init(
        names: [AIExtractedName],
        bookId: String,
        onSave: @escaping ([AIExtractedName], Bool, DataImportMode) -> Void,
        onBlockName: @escaping (AIExtractedName) -> Void,
        onNamesChange: (([AIExtractedName]) -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        suffixContext: LocalNameFilterReviewSuffixContext? = nil
    ) {
        self.content = ""
        self.bookId = bookId
        self.onSave = onSave
        self.onStrikeName = { _, _ in }
        self.onEditName = { _ in }
        self.exportBookTitle = nil
        self.prefilledNames = names
        self.initialSortMode = .notInDictionaryFirst
        self.onBlockName = onBlockName
        self.onNamesChange = onNamesChange
        self.onBack = onBack
        self.localSuffixContext = suffixContext
        self._names = State(initialValue: names)
        self._isLoading = State(initialValue: false)
        self._struckKeys = State(initialValue: [])
    }

    /// Thùng rác / ↶ của card (luồng AI) ⇒ đảo trạng thái gạch của mục, bỏ chọn khi gạch, báo nơi gọi lưu vào tin.
    private var strikeHandler: ((UUID) -> Void)? {
        guard prefilledNames == nil else { return nil }
        return { itemId in
            guard let index = names.firstIndex(where: { $0.id == itemId }) else { return }
            let key = AIRuntimeCoordinator.nameKey(names[index].original)
            guard !key.isEmpty else { return }
            let willStrike = !struckKeys.contains(key)
            if willStrike {
                struckKeys.insert(key)
                names[index].isSelected = false
            } else {
                struckKeys.remove(key)
            }
            onStrikeName(key, willStrike)
        }
    }

    func isStruck(_ item: AIExtractedName) -> Bool {
        prefilledNames == nil && struckKeys.contains(AIRuntimeCoordinator.nameKey(item.original))
    }

    /// ✕ › "Không phải name" của card ⇒ `onBlockName` với mục đầy đủ. Card gọi trước khi tự bỏ mục ⇒ còn tra được theo id.
    private var blockHandler: ((UUID) -> Void)? {
        guard let onBlockName else { return nil }
        return { blockedId in
            if let item = names.first(where: { $0.id == blockedId }) {
                onBlockName(item)
            }
        }
    }

    /// Số mục sẽ lưu — cả mục đang bị ô tìm / chip loại của card ẩn (card chỉ ẩn hàng, không bỏ chọn).
    private var selectedCount: Int {
        names.filter { $0.isSelected && !isStruck($0) }.count
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ReaderAISkeletonView()
                } else if names.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(prefilledNames == nil
                             ? "Không tìm thấy tên riêng hợp lệ dạng 'Từ=Nghĩa' trong tin nhắn."
                             : "Không còn name nào trong danh sách.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Thẻ là con **trực tiếp** của `ScrollView`: khối đầu thẻ (ô tìm + chip) ghim trên cùng khi cuộn (L14).
                    ScrollView {
                        ReaderAINameReviewCardView(
                            names: $names,
                            onDelete: { deletedId in
                                // Chỉ luồng lọc local còn xoá thật ("Bỏ khỏi lần này"); luồng AI đi `onToggleStrike`.
                                names.removeAll(where: { $0.id == deletedId })
                            },
                            onEdit: { editedId in
                                editingName = names.first(where: { $0.id == editedId })
                            },
                            initialSortMode: initialSortMode,
                            onBlock: blockHandler,
                            struckKeys: struckKeys,
                            onToggleStrike: strikeHandler,
                            showsCategoryFilter: prefilledNames != nil
                        )
                        .padding(.vertical, 8)
                    }
                    // Kéo danh sách là hạ bàn phím của ô tìm; vùng cuộn tự co theo bàn phím nên không che danh sách.
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .pageTitle("Duyệt tên riêng & VP", style: onBack == nil ? .leading : .centered)
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { saveMenu }
            }
            // Có name đã có trong file đích ⇒ popup ba cách lưu như nhập file (`+Save`); "Gộp" chọn sẵn.
            .dataImportModePopup(
                isPresented: $showingSavePopup,
                title: savePopupTitle,
                message: savePopupMessage,
                messageSystemImage: pendingIsName ? "person.fill" : "character.book.closed",
                explanations: Self.saveModeExplanations(isName: pendingIsName),
                confirmTitle: "Lưu"
            ) { mode in
                executeSave(isName: pendingIsName, mode: mode)
            }
            .sheet(item: $editingName) { item in
                Group {
                    editSheet(for: item)
                }
                .appGlassSheet()
                .environment(\.sheetPageBack, inheritedSheetPageBack)
            }
            // Bảng chia sẻ hệ thống — không gắn `.appGlassSheet()`.
            .sheet(item: $exportedFile) { file in exportShareSheet(for: file) }
            .onChange(of: names) { _, newNames in
                onNamesChange?(newNames)
            }
            .task {
                if prefilledNames != nil {
                    // Danh sách có sẵn: chỉ tra cờ NE/VP (badge + kiểu sắp "Chưa có trước"), giữ nguyên trạng thái chọn.
                    refreshDictionaryFlags()
                } else {
                    await loadAndDecorateNames()
                }
            }
        }
        // Đặt **ngoài** `NavigationStack` (khuôn `SheetPageBackEnvironment`); luồng AI giữ nguyên giá trị kế thừa.
        .environment(\.sheetPageBack, onBack ?? inheritedSheetPageBack)
    }

    /// Nút ▼ góc phải header (khung M1): icon chuẩn header 17pt nửa đậm, mép phải chạm lề.
    private var saveMenu: some View {
        Menu {
            Button { requestSave(isName: true) } label: { Label("Lưu vào Name riêng", systemImage: "person.fill") }
                .disabled(selectedCount == 0)
            Button { requestSave(isName: false) } label: { Label("Lưu vào VP riêng", systemImage: "character.book.closed") }
                .disabled(selectedCount == 0)
            Divider()
            let exportCount = recordsToSave.count
            Button { exportSelectedNames() } label: {
                Label("Xuất file", systemImage: "square.and.arrow.up")
                Text("\(exportCount) mục đang tích")
            }
            .disabled(exportCount == 0)
        } label: {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Lưu hoặc xuất name")
    }

    private func loadAndDecorateNames() async {
        let text = content
        let bid = bookId

        let decorated = await Task.detached(priority: .userInitiated) {
            let parsed = Self.parseEntriesFromText(text)
            guard !parsed.isEmpty else { return [AIExtractedName]() }

            let rawNames = parsed.map { item in
                AIExtractedName(
                    original: item.key,
                    suggestedMeaning: item.value,
                    category: "Tên riêng",
                    occurrenceCount: 1,
                    isSelected: true
                )
            }
            return AIBookDataInspector.shared.decorateExtractedNames(names: rawNames, bookId: bid)
        }.value

        // Hiển thị khung Skeleton tối thiểu 250ms để chuyển cảnh mượt mà
        try? await Task.sleep(nanoseconds: 250_000_000)

        await MainActor.run {
            // Hàng đã gạch ở lần trước: bỏ chọn sẵn (ô chọn khoá, không lưu được).
            self.names = decorated.map { item in
                var copy = item
                if self.struckKeys.contains(AIRuntimeCoordinator.nameKey(item.original)) { copy.isSelected = false }
                return copy
            }
            self.isLoading = false
        }
    }

    /// Gọi trong `.contextMenu` của **mọi** tin mỗi lần màn AI vẽ lại (mỗi nhịp stream 50 ms): duyệt từng dòng
    /// và dừng ở dòng `từ=nghĩa` đầu tiên thay vì tách cả tin thành mảng dòng. Cùng luật bỏ dòng với
    /// `parseEntriesFromText` (nghĩa lẫn chữ Hán không tính).
    public static func hasDictionaryEntries(in text: String) -> Bool {
        var found = false
        text.enumerateLines { line, stop in
            guard let eqIdx = line.firstIndex(of: "=") else { return }
            let k = line[..<eqIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let v = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty && !v.isEmpty && !TranslateUtils.containsChinese(v) {
                found = true
                stop = true
            }
        }
        return found
    }

    /// Tách các dòng `từ=nghĩa`. Bỏ dòng có nghĩa (vế phải) lẫn chữ Hán (1.3.602): AI đôi khi trả nghĩa chưa dịch
    /// hết kiểu `林动=Lâm 动`, lưu vào từ điển là hỏng bản dịch.
    private static func parseEntriesFromText(_ text: String) -> [(key: String, value: String)] {
        var seenKeys = Set<String>()
        var result: [(key: String, value: String)] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let v = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty, !v.isEmpty, !TranslateUtils.containsChinese(v) else { continue }
            if seenKeys.contains(k) {
                if let existingIdx = result.firstIndex(where: { $0.key == k }) {
                    result[existingIdx] = (key: k, value: v)
                }
            } else {
                seenKeys.insert(k)
                result.append((key: k, value: v))
            }
        }
        return result
    }
}
