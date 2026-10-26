import SwiftUI

/// Sheet chọn phạm vi quét và nguồn prompt cho chức năng "Quét tên riêng theo phạm vi".
/// Prompt tự nhập chỉ dùng cho MỘT lần quét, không ghi vào Cài đặt.
///
/// Phạm vi (1.3.602): chọn **chương bắt đầu** theo 4 kiểu — chương đang đọc, tiếp nối lần quét trước (điểm tiếp nối
/// của `AINameScanScopeStore`), chương đầu tiên, hoặc tự chọn một chương đã tải (`ReaderAINameScanChapterPickerView`).
/// Danh sách chương đã tải nạp **một lần** khi mở sheet; mọi con số tính trên RAM từ danh sách đó.
public struct ReaderAIBatchPromptSheet: View {
    /// Kiểu chọn chương bắt đầu quét.
    private enum ScanStart: Hashable {
        case current, resume, first, custom
    }

    @Environment(\.dismiss) private var dismiss

    public let settingsPrompt: String
    public let bookId: String
    /// Chương đang đọc (0-based theo mục lục).
    public let chapterIndex: Int
    /// Cấu hình dịch của Reader cho truyện (1.3.603): bật dịch thì tên chương hiện bản dịch như danh sách chương Reader.
    public let translatesChapterTitles: Bool
    public let convertsTraditionalToSimplified: Bool
    /// `prompt`, `fromChapterIndex` (chương bắt đầu, 0-based; `nil` = từ chương đã tải đầu tiên), `limit` (số chương
    /// cần quét, `nil` = không giới hạn).
    public let onStart: (String, Int?, Int?) -> Void

    @State private var useCustomPrompt: Bool = false
    @State private var customPrompt: String = ""

    /// Kiểu người dùng đã bấm; `nil` = theo `defaultStart` (mặc định phụ thuộc danh sách chương nên chỉ chốt được sau
    /// khi nạp xong).
    @State private var pickedStart: ScanStart? = nil
    /// Chương tự chọn ở "Chọn chương…" — cố ý **không** nhớ giữa các lần mở sheet.
    @State private var customChapterIndex: Int? = nil
    /// Số chương cần quét tính từ chương bắt đầu. Cố ý **không** ghi nhớ giữa các lần mở sheet: mỗi lần mở lại về `.all`.
    @State private var limitOption: ChapterLimitOption = .all
    /// Số chương của mốc "Tuỳ chọn" — chỉ có nghĩa khi `limitOption == .custom`.
    @State private var customLimit: Int = 100
    /// Chương đã tải theo thứ tự mục lục; `nil` = đang nạp.
    @State private var chapters: [AINameScanChapter]? = nil

    /// Lựa chọn "từ chương đang đọc / chương đầu tiên" đã nhớ theo truyện — chỉ dùng làm mặc định.
    private let prefersFromCurrentChapter: Bool
    /// Điểm tiếp nối của lần quét gần nhất (chỉ số chương cuối được coi là đã quét); `nil` = chưa có.
    private let resumeChapterIndex: Int?

    public init(
        settingsPrompt: String,
        bookId: String,
        chapterIndex: Int,
        translatesChapterTitles: Bool = false,
        convertsTraditionalToSimplified: Bool = false,
        onStart: @escaping (String, Int?, Int?) -> Void
    ) {
        self.settingsPrompt = settingsPrompt
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.translatesChapterTitles = translatesChapterTitles
        self.convertsTraditionalToSimplified = convertsTraditionalToSimplified
        self.onStart = onStart
        self._customPrompt = State(initialValue: settingsPrompt)
        self.prefersFromCurrentChapter = AINameScanScopeStore.shared.prefersFromCurrentChapter(bookId: bookId)
        self.resumeChapterIndex = AINameScanScopeStore.shared.resumeChapterIndex(bookId: bookId)
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

    /// Vị trí (trong `chapters`) của chương đã tải đầu tiên có chỉ số ≥ `index`.
    private func firstPosition(atOrAfter index: Int) -> Int? {
        chapters?.firstIndex { $0.index >= index }
    }

    /// Vị trí chương bắt đầu của từng kiểu; `nil` = kiểu đó không còn chương nào.
    private func startPosition(for start: ScanStart) -> Int? {
        switch start {
        case .current:
            return firstPosition(atOrAfter: chapterIndex)
        case .resume:
            guard let resume = resumeChapterIndex else { return nil }
            return firstPosition(atOrAfter: resume + 1)
        case .first:
            return (chapters?.isEmpty ?? true) ? nil : 0
        case .custom:
            guard let custom = customChapterIndex else { return nil }
            return chapters?.firstIndex { $0.index == custom }
        }
    }

    /// Mặc định: có điểm tiếp nối và còn chương sau nó ⇒ tiếp nối; không thì theo lựa chọn đã nhớ của truyện.
    private var defaultStart: ScanStart {
        if startPosition(for: .resume) != nil { return .resume }
        return prefersFromCurrentChapter ? .current : .first
    }

    private var activeStart: ScanStart { pickedStart ?? defaultStart }

    /// Số chương thực quét: từ chương bắt đầu tới hết, kẹp theo "Số lượng chương". `nil` = đang nạp.
    private var effectiveCount: Int? {
        guard let chapters else { return nil }
        guard let start = startPosition(for: activeStart) else { return 0 }
        let available = chapters.count - start
        guard let limit = limitValue else { return available }
        return min(limit, available)
    }

    /// Phạm vi hiện tại không có chương nào để quét.
    private var scopeIsEmpty: Bool {
        effectiveCount == 0
    }

    private var scopeSummaryText: String {
        guard let chapters, let count = effectiveCount else { return "Đang tính…" }
        guard count > 0, let start = startPosition(for: activeStart) else {
            return chapters.isEmpty ? "Chưa có chương nào đã tải" : "Không có chương nào để quét"
        }
        return "Sẽ quét \(count) chương: ch.\(chapters[start].number) → ch.\(chapters[start + count - 1].number)"
    }

    /// Chỉ số chương bắt đầu gửi cho lần quét; "Chương đầu tiên" ⇒ `nil` (toàn bộ chương đã tải).
    private var fromChapterIndexForScan: Int? {
        guard activeStart != .first, let chapters, let start = startPosition(for: activeStart) else { return nil }
        return chapters[start].index
    }

    private var canStart: Bool {
        (!useCustomPrompt || !trimmedCustomPrompt.isEmpty) && (effectiveCount ?? 0) > 0
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let chapters {
                        scopeRows(chapters)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Đang nạp danh sách chương…")
                                .foregroundColor(.secondary)
                        }
                    }

                    ChapterLimitPicker.optionPicker(option: $limitOption)

                    if limitOption == ChapterLimitOption.custom {
                        ChapterLimitPicker.customRow(customLimit: $customLimit)
                    }

                    Text(scopeSummaryText)
                        .font(.footnote)
                        .foregroundColor(scopeIsEmpty ? .red : .secondary)
                } header: {
                    Text("Phạm vi quét")
                } footer: {
                    Text("Chỉ quét các chương đã tải, bắt đầu từ chương chọn ở trên. \"Tiếp nối\" bắt đầu ngay sau chương cuối mà lần quét trước đã quét liền mạch thành công (dừng trước lượt lỗi đầu tiên).\n\"Số lượng chương\" giới hạn số chương thực quét, tính từ chương bắt đầu.")
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
                    let fromChapterIndex = fromChapterIndexForScan
                    let limit = limitValue
                    dismiss()
                    onStart(prompt, fromChapterIndex, limit)
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
                await loadChapters()
            }
        }
    }

    /// Bốn dòng chọn chương bắt đầu. Chọn "đang đọc"/"đầu tiên" thì nhớ lựa chọn đó cho truyện như trước; "Tiếp nối"
    /// và "Chọn chương" không ghi gì.
    @ViewBuilder
    private func scopeRows(_ chapters: [AINameScanChapter]) -> some View {
        sourceRow(
            title: "Chương đang đọc",
            subtitle: startPosition(for: .current).map { chapters[$0].label }
                ?? "Không có chương đã tải từ ch.\(chapterIndex + 1) trở đi",
            isSelected: activeStart == .current
        ) {
            pickedStart = .current
            AINameScanScopeStore.shared.setPrefersFromCurrentChapter(true, bookId: bookId)
        }

        if let resume = resumeChapterIndex {
            let resumePosition = startPosition(for: .resume)
            sourceRow(
                title: "Tiếp nối lần quét trước",
                subtitle: resumePosition.map { chapters[$0].label }
                    ?? "Đã quét hết chương đã tải" + (resume >= 0 ? " (tới ch.\(resume + 1))" : ""),
                isSelected: activeStart == .resume
            ) {
                pickedStart = .resume
            }
            .disabled(resumePosition == nil)
            .opacity(resumePosition == nil ? 0.45 : 1)
        }

        sourceRow(
            title: "Chương đầu tiên",
            subtitle: chapters.first?.label ?? "Chưa có chương nào đã tải",
            isSelected: activeStart == .first
        ) {
            pickedStart = .first
            AINameScanScopeStore.shared.setPrefersFromCurrentChapter(false, bookId: bookId)
        }

        NavigationLink {
            ReaderAINameScanChapterPickerView(
                chapters: chapters,
                selectedIndex: customChapterIndex ?? startPosition(for: activeStart).map { chapters[$0].index }
            ) { index in
                customChapterIndex = index
                pickedStart = .custom
            }
        } label: {
            radioLabel(
                title: "Chọn chương…",
                subtitle: startPosition(for: .custom).map { chapters[$0].label } ?? "Chọn một chương đã tải",
                isSelected: activeStart == .custom
            )
        }
        .disabled(chapters.isEmpty)
        .opacity(chapters.isEmpty ? 0.45 : 1)
    }

    /// Nạp danh sách chương đã tải **một lần** khi mở sheet — đổi kiểu bắt đầu hay số chương không đọc lại mục lục.
    /// `.task` của màn gốc chạy lại mỗi lần quay về từ "Chọn chương…" ⇒ đã nạp thì thôi.
    private func loadChapters() async {
        guard chapters == nil else { return }
        let loaded = await AIBookDataInspector.shared.nameScanChapters(
            bookId: bookId,
            translatesTitles: translatesChapterTitles,
            convertsTraditionalToSimplified: convertsTraditionalToSimplified
        )
        await MainActor.run {
            self.chapters = loaded
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
            radioLabel(title: title, subtitle: subtitle, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func radioLabel(title: String, subtitle: String?, isSelected: Bool) -> some View {
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
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}
