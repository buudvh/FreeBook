import SwiftUI

/// Bottom sheet hiển thị danh sách tên riêng trích xuất từ tin nhắn AI với hiệu ứng Skeleton bất đồng bộ.
///
/// Từ 1.3.469 nút Lưu nằm trên **thanh điều hướng** (`.confirmationAction`) dưới dạng `Menu` 2 mục —
/// đúng khuôn `AddWordSheet` — thay cho hai nút `Lưu Name riêng` / `Lưu VP riêng` ở đáy card.
public struct ReaderAINameReviewSheet: View {
    public struct Target: Identifiable, Sendable {
        public let id = UUID()
        public let content: String

        public init(content: String) {
            self.content = content
        }
    }

    @Environment(\.dismiss) private var dismiss

    public let content: String
    public let bookId: String
    public let onSave: ([AIExtractedName], Bool, Bool) -> Void

    @State private var isLoading: Bool = true
    @State private var names: [AIExtractedName] = []
    @State private var pendingIsName: Bool = true
    @State private var showingModeDialog: Bool = false

    public init(
        content: String,
        bookId: String,
        onSave: @escaping ([AIExtractedName], Bool, Bool) -> Void
    ) {
        self.content = content
        self.bookId = bookId
        self.onSave = onSave
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
    private func requestSave(isName: Bool) {
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

    public static func hasDictionaryEntries(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let k = line[..<eqIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let v = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !k.isEmpty && !v.isEmpty {
                return true
            }
        }
        return false
    }

    private static func parseEntriesFromText(_ text: String) -> [(key: String, value: String)] {
        var seenKeys = Set<String>()
        var result: [(key: String, value: String)] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let v = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty, !v.isEmpty else { continue }
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
