import SwiftUI

/// Bottom sheet hiển thị danh sách tên riêng trích xuất từ tin nhắn AI với hiệu ứng Skeleton bất đồng bộ.
public struct ReaderAINameReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let content: String
    public let bookId: String
    public let onSave: ([AIExtractedName], Bool, Bool) -> Void

    @State private var isLoading: Bool = true
    @State private var names: [AIExtractedName] = []

    public init(
        content: String,
        bookId: String,
        onSave: @escaping ([AIExtractedName], Bool, Bool) -> Void
    ) {
        self.content = content
        self.bookId = bookId
        self.onSave = onSave
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
                            onSave: { itemsToSave, isName, isMerge in
                                onSave(itemsToSave, isName, isMerge)
                                dismiss()
                            },
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
            }
            .task {
                await loadAndDecorateNames()
            }
        }
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
