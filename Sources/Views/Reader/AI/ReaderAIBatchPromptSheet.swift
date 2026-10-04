import SwiftUI

/// Sheet chọn nguồn prompt cho chức năng "Quét tên riêng toàn bộ chương đã tải".
/// Prompt tự nhập chỉ dùng cho MỘT lần quét, không ghi vào Cài đặt.
public struct ReaderAIBatchPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let settingsPrompt: String
    public let bookId: String
    public let chapterIndex: Int
    public let onStart: (String, Bool) -> Void

    @State private var useCustomPrompt: Bool = false
    @State private var customPrompt: String = ""

    /// Bật = chỉ quét các chương đã tải từ `chapterIndex` trở đi; tắt = quét toàn bộ chương đã tải.
    @State private var fromCurrentChapter: Bool
    @State private var scopedCount: Int? = nil
    @State private var scopedFirstTitle: String? = nil
    @State private var totalCount: Int? = nil

    public init(
        settingsPrompt: String,
        bookId: String,
        chapterIndex: Int,
        onStart: @escaping (String, Bool) -> Void
    ) {
        self.settingsPrompt = settingsPrompt
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.onStart = onStart
        self._customPrompt = State(initialValue: settingsPrompt)
        self._fromCurrentChapter = State(initialValue: AINameScanScopeStore.shared.prefersFromCurrentChapter(bookId: bookId))
    }

    private var trimmedCustomPrompt: String {
        customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phạm vi hiện tại không có chương nào để quét.
    private var scopeIsEmpty: Bool {
        fromCurrentChapter ? (scopedCount == 0) : (totalCount == 0)
    }

    private var scopeSummaryText: String {
        if fromCurrentChapter {
            guard let count = scopedCount else { return "Đang tính…" }
            guard count > 0 else { return "Không có chương đã tải từ ch.\(chapterIndex) trở đi" }
            if let title = scopedFirstTitle, !title.isEmpty {
                return "\(count) chương — từ ch.\(chapterIndex): \(title)"
            }
            return "\(count) chương — từ ch.\(chapterIndex)"
        }
        guard let total = totalCount else { return "Đang tính…" }
        return total > 0 ? "Toàn bộ \(total) chương đã tải" : "Chưa có chương nào đã tải"
    }

    private var canStart: Bool {
        (!useCustomPrompt || !trimmedCustomPrompt.isEmpty) && !scopeIsEmpty
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $fromCurrentChapter) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Từ chương đang đọc")
                            Text(scopeSummaryText)
                                .font(.caption)
                                .foregroundColor(scopeIsEmpty ? .red : .secondary)
                        }
                    }
                    .onChange(of: fromCurrentChapter) { _, newValue in
                        AINameScanScopeStore.shared.setPrefersFromCurrentChapter(newValue, bookId: bookId)
                    }
                } header: {
                    Text("Phạm vi quét")
                } footer: {
                    Text("Bật: chỉ quét các chương đã tải từ chương đang đọc trở đi. Tắt: quét toàn bộ chương đã tải.")
                }

                Section {
                    sourceRow(
                        title: "Dùng prompt trong Cài đặt",
                        subtitle: "Prompt trích xuất hiện hành",
                        isSelected: !useCustomPrompt
                    ) {
                        useCustomPrompt = false
                    }

                    sourceRow(
                        title: "Tự nhập prompt",
                        subtitle: nil,
                        isSelected: useCustomPrompt
                    ) {
                        useCustomPrompt = true
                    }
                } header: {
                    Text("Nguồn prompt")
                } footer: {
                    Text("Prompt tự nhập chỉ dùng cho lần quét này, không lưu vào Cài đặt.")
                }

                Section {
                    TextEditor(text: useCustomPrompt ? $customPrompt : Binding.constant(settingsPrompt))
                        .frame(minHeight: 180)
                        .font(.footnote)
                        .disabled(!useCustomPrompt)

                    if useCustomPrompt && trimmedCustomPrompt.isEmpty {
                        Text("Nhập prompt trích xuất tên riêng…")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Prompt cho lần này")
                }
            }
            .navigationTitle("Quét tên riêng toàn bộ chương đã tải")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let prompt = useCustomPrompt ? trimmedCustomPrompt : settingsPrompt
                    dismiss()
                    onStart(prompt, fromCurrentChapter)
                } label: {
                    Text("Bắt đầu quét")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(!canStart)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .task {
                await loadScopeSummary()
            }
        }
    }

    /// Đếm số chương cho cả hai phạm vi ngay khi mở sheet để dòng phụ đổi theo toggle không cần chờ lại.
    private func loadScopeSummary() async {
        async let scoped = AIBookDataInspector.shared.nameScanScopeSummary(bookId: bookId, fromChapterIndex: chapterIndex)
        async let total = AIBookDataInspector.shared.nameScanScopeSummary(bookId: bookId)
        let (scopedResult, totalResult) = await (scoped, total)
        await MainActor.run {
            self.scopedCount = scopedResult.count
            self.scopedFirstTitle = scopedResult.firstTitle
            self.totalCount = totalResult.count
        }
    }

    @ViewBuilder
    private func sourceRow(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
