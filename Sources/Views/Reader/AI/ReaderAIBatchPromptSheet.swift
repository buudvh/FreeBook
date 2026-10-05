import SwiftUI

/// Sheet chọn phạm vi quét và nguồn prompt cho chức năng "Quét tên riêng theo phạm vi".
/// Prompt tự nhập chỉ dùng cho MỘT lần quét, không ghi vào Cài đặt.
public struct ReaderAIBatchPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let settingsPrompt: String
    public let bookId: String
    public let chapterIndex: Int
    /// `prompt`, `fromCurrentChapter`, `limit` (số chương cần quét, `nil` = không giới hạn).
    public let onStart: (String, Bool, Int?) -> Void

    @State private var useCustomPrompt: Bool = false
    @State private var customPrompt: String = ""

    /// Bật = chỉ quét các chương đã tải từ `chapterIndex` trở đi; tắt = quét toàn bộ chương đã tải.
    @State private var fromCurrentChapter: Bool
    /// Số chương cần quét trong phạm vi đang chọn. Cố ý **không** ghi nhớ giữa các lần mở sheet
    /// (khác `fromCurrentChapter`): mỗi lần mở lại về `.all`.
    @State private var limitOption: ChapterLimitOption = .all
    /// Số chương của mốc "Tuỳ chọn" — chỉ có nghĩa khi `limitOption == .custom`.
    @State private var customLimit: Int = 100
    @State private var scopedCount: Int? = nil
    @State private var scopedFirstTitle: String? = nil
    @State private var totalCount: Int? = nil

    public init(
        settingsPrompt: String,
        bookId: String,
        chapterIndex: Int,
        onStart: @escaping (String, Bool, Int?) -> Void
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

    /// Giới hạn thật: mốc "Tuỳ chọn" được quy đổi thành số chương đang kéo.
    private var effectiveLimit: ChapterLimitOption {
        limitOption == ChapterLimitOption.custom
            ? ChapterLimitOption(rawValue: ChapterLimitOption.clampCustom(customLimit))
            : limitOption
    }

    /// Số chương sẽ quét thật sự; `nil` = không giới hạn.
    private var limitValue: Int? { effectiveLimit.limitValue }

    /// Số chương đã tải của phạm vi đang chọn, **chưa** áp giới hạn.
    private var availableCount: Int? {
        fromCurrentChapter ? scopedCount : totalCount
    }

    /// Số chương thực quét: giới hạn được kẹp vào số chương có sẵn.
    private var effectiveCount: Int? {
        guard let available = availableCount else { return nil }
        guard let limit = limitValue else { return available }
        return min(limit, available)
    }

    /// Phạm vi hiện tại không có chương nào để quét.
    private var scopeIsEmpty: Bool {
        effectiveCount == 0
    }

    private var scopeSummaryText: String {
        guard let count = effectiveCount else { return "Đang tính…" }
        guard count > 0 else {
            return fromCurrentChapter
                ? "Không có chương đã tải từ ch.\(chapterIndex) trở đi"
                : "Chưa có chương nào đã tải"
        }
        guard fromCurrentChapter else { return "\(count) chương đã tải" }
        if let title = scopedFirstTitle, !title.isEmpty {
            return "\(count) chương — từ ch.\(chapterIndex): \(title)"
        }
        return "\(count) chương — từ ch.\(chapterIndex)"
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

                    ChapterLimitPicker.optionPicker(option: $limitOption)

                    if limitOption == ChapterLimitOption.custom {
                        ChapterLimitPicker.customRow(customLimit: $customLimit)
                    }
                } header: {
                    Text("Phạm vi quét")
                } footer: {
                    Text("Bật: chỉ quét các chương đã tải từ chương đang đọc trở đi. Tắt: quét toàn bộ chương đã tải.\n\"Số lượng chương\" giới hạn số chương thực quét, tính từ đầu phạm vi.")
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
            .navigationTitle("Quét tên riêng theo phạm vi")
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
                    onStart(prompt, fromCurrentChapter, limitValue)
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
    /// Nạp số chương **có sẵn** (không áp giới hạn) — view tự kẹp `min` khi người dùng kéo thanh kéo,
    /// nên đổi số chương không phải đọc lại mục lục.
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
