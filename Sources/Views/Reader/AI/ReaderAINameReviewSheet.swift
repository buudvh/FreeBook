import SwiftUI

/// Bottom sheet hiển thị danh sách tên riêng trích xuất từ tin nhắn AI với hiệu ứng Skeleton bất đồng bộ.
///
/// Từ 1.3.469 nút Lưu nằm trên **thanh điều hướng** (`.confirmationAction`) dưới dạng `Menu` 2 mục —
/// đúng khuôn `AddWordSheet` — thay cho hai nút `Lưu Name riêng` / `Lưu VP riêng` ở đáy card.
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

    @Environment(\.dismiss) private var dismiss

    public let content: String
    public let bookId: String
    public let onSave: ([AIExtractedName], Bool, Bool) -> Void
    /// Luồng AI: bấm thùng rác / ↶ của một name ⇒ nhận **khoá** (vế trái đã trim) + `true` gạch / `false` bỏ gạch, để nơi
    /// gọi ghi vào tin nguồn (`AIChatMessage.struckNameKeys`). Dòng trong tin **không** bị xoá (anh Bửu 2026-11-27).
    public let onStrikeName: (String, Bool) -> Void
    /// Bấm "Cập nhật" ở màn Sửa từ của một name (1.3.780, `+Edit`): nhận phép sửa để nơi gọi ghi vào tin nguồn.
    public let onEditName: (AINameEdit) -> Void
    /// Danh sách có sẵn (luồng "Lọc name local", `LocalNameFilterSheet`): bỏ bước tách dòng `từ=nghĩa` khỏi tin AI.
    /// `nil` = luồng AI.
    let prefilledNames: [AIExtractedName]?
    /// Kiểu sắp lúc mở card: luồng AI "Đã chọn trước", luồng lọc local "Nhiều lần nhất".
    let initialSortMode: ReaderAINameReviewCardView.SortMode
    /// Thùng rác › "Không phải name" — chỉ luồng lọc local truyền; luồng AI gạch hàng (`onStrikeName`).
    public let onBlockName: ((AIExtractedName) -> Void)?
    /// Luồng lọc local: danh sách đang duyệt mỗi lần đổi (chọn / bỏ chọn, sửa, bỏ mục, cờ NE / VP tra lại) — nơi gọi giữ
    /// bản mới nhất để thành gói tạm khi đóng màn mà chưa Lưu (`LocalNameFilterSession+Drafts`). Luồng AI: `nil`.
    let onNamesChange: (([AIExtractedName]) -> Void)?

    @State private var isLoading: Bool = true
    // `internal` (không `private`): `ReaderAINameReviewSheet+Edit.swift` dùng chung.
    @State var names: [AIExtractedName] = []
    @State var editingName: AIExtractedName? = nil
    @State private var pendingIsName: Bool = true
    @State private var showingModeDialog: Bool = false
    /// Khoá đang gạch (luồng AI) — khởi tạo từ tin nguồn, mỗi lần gạch / bỏ gạch ghi ngay qua `onStrikeName`.
    // `internal` (không `private`): `+Edit` bỏ gạch khoá đích khi người dùng sửa một name thành khoá đang gạch.
    @State var struckKeys: Set<String>

    public init(
        content: String,
        bookId: String,
        struckKeys: Set<String> = [],
        onSave: @escaping ([AIExtractedName], Bool, Bool) -> Void,
        onStrikeName: @escaping (String, Bool) -> Void = { _, _ in },
        onEditName: @escaping (AINameEdit) -> Void = { _ in }
    ) {
        self.content = content
        self.bookId = bookId
        self.onSave = onSave
        self.onStrikeName = onStrikeName
        self.onEditName = onEditName
        self.prefilledNames = nil
        self.initialSortMode = .selectedFirst
        self.onBlockName = nil
        self.onNamesChange = nil
        self._struckKeys = State(initialValue: struckKeys)
    }

    /// Luồng "Lọc name local": nhận sẵn danh sách (đã gắn cờ NE / VP, name đã có bỏ chọn sẵn; `occurrenceCount` = số lần
    /// thấy; mở lại gói tạm ⇒ đúng trạng thái đã giữ), sắp "Nhiều lần nhất", chip lọc theo loại + badge loại có màu
    /// (`ReaderAINameReviewCardView.showsCategoryFilter`), ✕ có "Không phải name" (`onBlockName`). Sửa một name chỉ đổi
    /// danh sách đang duyệt (không có tin nguồn).
    public init(
        names: [AIExtractedName],
        bookId: String,
        onSave: @escaping ([AIExtractedName], Bool, Bool) -> Void,
        onBlockName: @escaping (AIExtractedName) -> Void,
        onNamesChange: (([AIExtractedName]) -> Void)? = nil
    ) {
        self.content = ""
        self.bookId = bookId
        self.onSave = onSave
        self.onStrikeName = { _, _ in }
        self.onEditName = { _ in }
        self.prefilledNames = names
        self.initialSortMode = .mostFrequent
        self.onBlockName = onBlockName
        self.onNamesChange = onNamesChange
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

    private func isStruck(_ item: AIExtractedName) -> Bool {
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
                }
            }
            .pageTitle("Duyệt tên riêng & VP")
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Lưu") {
                        Button("Lưu vào Name riêng") { requestSave(isName: true) }
                        Button("Lưu vào VP riêng") { requestSave(isName: false) }
                    }
                    .headerTextButton()
                    .disabled(selectedCount == 0)
                }
            }
            .confirmationDialog(
                "Lựa chọn chế độ lưu vào \(pendingIsName ? "Name riêng" : "VietPhrase riêng")",
                isPresented: $showingModeDialog,
                titleVisibility: .visible
            ) {
                Button("Gộp (trùng từ thì thay mới)") {
                    executeSave(isName: pendingIsName, isMerge: true)
                }
                Button("Thay thế hoàn toàn", role: .destructive) {
                    executeSave(isName: pendingIsName, isMerge: false)
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text(pendingIsName
                     ? "Chế độ Gộp sẽ thêm các tên mới vào Names.txt và giữ nguyên các tên cũ. Chế độ Thay thế sẽ làm mới hoàn toàn Names.txt của truyện."
                     : "Chế độ Gộp sẽ thêm các từ mới vào VietPhrase.txt và giữ nguyên các từ cũ. Chế độ Thay thế sẽ làm mới hoàn toàn VietPhrase.txt của truyện."
                )
            }
            .sheet(item: $editingName) { item in
                Group {
                    editSheet(for: item)
                }
                .appGlassSheet()
            }
            .onChange(of: names) { _, newNames in
                onNamesChange?(newNames)
            }
            .task {
                if prefilledNames != nil {
                    // Danh sách có sẵn: chỉ tra cờ NE/VP (cho hộp Gộp / Thay thế lúc lưu), giữ nguyên trạng thái chọn.
                    refreshDictionaryFlags()
                } else {
                    await loadAndDecorateNames()
                }
            }
        }
    }

    /// Bước 1: chọn đích — mở dialog Gộp / Thay thế hoàn toàn.
    ///
    /// Không từ nào đang chọn có sẵn trong **từ điển đích** (cờ `hasInBookNames` / `hasInBookVP` dựng lúc mở sheet)
    /// ⇒ gộp luôn, không hỏi: không có gì để ghi đè. Chỉ xét đích — lưu vào Name riêng thì từ đang có ở VP riêng
    /// vẫn là từ mới với `Names.txt`.
    private func requestSave(isName: Bool) {
        let hasExisting = names.contains {
            $0.isSelected && !isStruck($0) && (isName ? $0.hasInBookNames : $0.hasInBookVP)
        }
        guard hasExisting else {
            executeSave(isName: isName, isMerge: true)
            return
        }
        pendingIsName = isName
        showingModeDialog = true
    }

    /// Bước 2: chốt chế độ ghi. Sheet đóng ngay sau khi giao việc cho `onSave` — màn gọi sẽ thay nội
    /// dung tin nhắn bằng bản tóm tắt nên danh sách ở đây thành dữ liệu cũ.
    private func executeSave(isName: Bool, isMerge: Bool) {
        // Hàng gạch không bao giờ được lưu (ô chọn đã khoá; lọc thêm cho chắc).
        let chosen = names.filter { $0.isSelected && !isStruck($0) }
        guard !chosen.isEmpty else { return }
        onSave(chosen, isName, isMerge)
        dismiss()
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
