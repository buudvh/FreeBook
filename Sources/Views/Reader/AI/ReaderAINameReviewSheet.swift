import SwiftUI

/// Bottom sheet hiển thị danh sách tên riêng trích xuất từ tin nhắn AI với hiệu ứng Skeleton bất đồng bộ.
///
/// Từ 1.3.469 nút Lưu nằm trên **thanh điều hướng** (`.confirmationAction`) dưới dạng `Menu` 2 mục —
/// đúng khuôn `AddWordSheet` — thay cho hai nút `Lưu Name riêng` / `Lưu VP riêng` ở đáy card.
public struct ReaderAINameReviewSheet: View {
    public struct Target: Identifiable, Sendable {
        public let id = UUID()
        public let content: String
        /// Tin nguồn — nút ✕ xoá dòng `từ=nghĩa` khỏi chính tin này (`ReaderAIFullScreenView.removeNameLine`).
        public let messageId: UUID

        public init(content: String, messageId: UUID) {
            self.content = content
            self.messageId = messageId
        }
    }

    @Environment(\.dismiss) private var dismiss

    public let content: String
    public let bookId: String
    public let onSave: ([AIExtractedName], Bool, Bool) -> Void
    /// Bấm ✕ một name: nhận **khoá** (`original`) để nơi gọi xoá hẳn dòng đó khỏi tin nguồn.
    public let onDeleteName: (String) -> Void

    @State private var isLoading: Bool = true
    @State private var names: [AIExtractedName] = []
    @State private var pendingIsName: Bool = true
    @State private var showingModeDialog: Bool = false

    public init(
        content: String,
        bookId: String,
        onSave: @escaping ([AIExtractedName], Bool, Bool) -> Void,
        onDeleteName: @escaping (String) -> Void = { _ in }
    ) {
        self.content = content
        self.bookId = bookId
        self.onSave = onSave
        self.onDeleteName = onDeleteName
    }

    private var selectedCount: Int {
        names.filter { $0.isSelected }.count
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
                        Text("Không tìm thấy tên riêng hợp lệ dạng 'Từ=Nghĩa' trong tin nhắn.")
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
                                // Card gọi trước khi tự xoá khỏi danh sách ⇒ còn tra được khoá theo id.
                                if let key = names.first(where: { $0.id == deletedId })?.original {
                                    onDeleteName(key)
                                }
                                names.removeAll(where: { $0.id == deletedId })
                            }
                        )
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Duyệt tên riêng & VP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Lưu") {
                        Button("Lưu vào Name riêng") { requestSave(isName: true) }
                        Button("Lưu vào VP riêng") { requestSave(isName: false) }
                    }
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
            .task {
                await loadAndDecorateNames()
            }
        }
    }

    /// Bước 1: chọn đích — mở dialog Gộp / Thay thế hoàn toàn.
    ///
    /// Không từ nào đang chọn có sẵn trong **từ điển đích** (cờ `hasInBookNames` / `hasInBookVP` dựng lúc mở sheet)
    /// ⇒ gộp luôn, không hỏi: không có gì để ghi đè. Chỉ xét đích — lưu vào Name riêng thì từ đang có ở VP riêng
    /// vẫn là từ mới với `Names.txt`.
    private func requestSave(isName: Bool) {
        let hasExisting = names.contains { $0.isSelected && (isName ? $0.hasInBookNames : $0.hasInBookVP) }
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
        let chosen = names.filter { $0.isSelected }
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
            self.names = decorated
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
