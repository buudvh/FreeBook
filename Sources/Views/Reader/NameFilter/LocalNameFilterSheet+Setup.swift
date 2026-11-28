import SwiftUI

/// Bước chọn của sheet "Lọc name local" (mockup khung 2; bản LAC khung 1 / 5; nghĩa tên tây huyễn khung 1; phân loại name
/// khung 5): Gói tạm chưa lưu (`+Drafts`, chỉ khi có), Phạm vi lọc, Loại cần tìm (`+Categories`), Tuỳ chọn ("Ít nhất N
/// lần", "Độ dài name", "Ưu tiên tên Latin" theo truyện), Danh sách (Hậu tố, Tiền tố, Họ, Không phải name).
///
/// Phạm vi chép cách của `ReaderAIBatchPromptSheet` (chương đang đọc / chương đầu tiên / "Chọn chương…" qua
/// `ReaderAINameScanChapterPickerView`, "Số lượng chương" `ChapterLimitPicker` mặc định Tất cả), bỏ "Tiếp nối", và
/// **không** đọc / ghi `AINameScanScopeStore`: mặc định là chương đang đọc, không còn chương đã tải nào từ đó trở đi thì
/// chương đầu tiên. Ô chương chỉ ghi tên chương (không "ch.N"); tên rỗng mới ghi "Chương N".
extension LocalNameFilterSheet {
    // MARK: - Phạm vi (tính trên RAM từ danh sách chương nạp một lần)

    /// Giới hạn thật: mốc "Tuỳ chọn" quy đổi thành số chương đang kéo.
    var limitValue: Int? {
        let effective = limitOption == ChapterLimitOption.custom
            ? ChapterLimitOption(rawValue: ChapterLimitOption.clampCustom(customLimit))
            : limitOption
        return effective.limitValue
    }

    /// Vị trí (trong `chapters`) của chương đã tải đầu tiên có chỉ số ≥ `index`.
    private func firstPosition(atOrAfter index: Int) -> Int? {
        chapters?.firstIndex { $0.index >= index }
    }

    /// Vị trí chương bắt đầu của từng kiểu; `nil` = kiểu đó không còn chương nào.
    private func startPosition(for start: ScanStart) -> Int? {
        switch start {
        case .current:
            return firstPosition(atOrAfter: chapterIndex)
        case .first:
            return (chapters?.isEmpty ?? true) ? nil : 0
        case .custom:
            guard let custom = customChapterIndex else { return nil }
            return chapters?.firstIndex { $0.index == custom }
        }
    }

    private var defaultStart: ScanStart {
        startPosition(for: .current) != nil ? .current : .first
    }

    private var activeStart: ScanStart { pickedStart ?? defaultStart }

    /// Số chương sẽ lọc: từ chương bắt đầu tới hết, kẹp theo "Số lượng chương". `nil` = đang nạp.
    private var effectiveCount: Int? {
        guard let chapters else { return nil }
        guard let start = startPosition(for: activeStart) else { return 0 }
        let available = chapters.count - start
        guard let limit = limitValue else { return available }
        return min(limit, available)
    }

    var canStart: Bool {
        (effectiveCount ?? 0) > 0
    }

    /// Chỉ số chương bắt đầu đưa cho `fetchDownloadedChapters`; "Chương đầu tiên" ⇒ `nil` (từ chương đã tải đầu tiên).
    var fromChapterIndexForRun: Int? {
        guard activeStart != .first, let chapters, let start = startPosition(for: activeStart) else { return nil }
        return chapters[start].index
    }

    private var scopeSummaryText: String {
        guard let chapters, let count = effectiveCount else { return "Đang tính…" }
        guard count > 0 else {
            return chapters.isEmpty ? "Chưa có chương nào đã tải" : "Không có chương nào để lọc"
        }
        return "Sẽ lọc \(count) chương đã tải"
    }

    /// Tên chương ở ô chọn: chỉ tên, rỗng mới "Chương N" (không tiền tố số thứ tự).
    private func chapterName(_ chapter: AINameScanChapter) -> String {
        chapter.title.isEmpty ? "Chương \(chapter.number)" : chapter.title
    }

    // MARK: - Form

    var setupForm: some View {
        Form { Group {
            if let notice = session.notice {
                Section {
                    noticeRow(notice)
                }
            }

            draftsSection

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
            } header: {
                SectionHelpHeader("Phạm vi lọc", paragraphs: ["Chỉ lọc các chương đã tải, bắt đầu từ chương chọn ở dưới. \"Số lượng chương\" giới hạn số chương đọc, tính từ chương bắt đầu."])
            } footer: {
                Text(scopeSummaryText)
                    .foregroundColor(effectiveCount == 0 ? .red : .secondary)
            }

            categoriesSection

            Section {
                HStack(spacing: 12) {
                    Text("Ít nhất")
                    Spacer(minLength: 8)
                    Picker("Ít nhất", selection: $minCount) {
                        ForEach(Self.minCountChoices, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 190)
                    Text("lần")
                        .foregroundColor(.secondary)
                }

                lengthRow

                HelpLabeledToggle(
                    title: "Ưu tiên tên Latin",
                    help: [
                        "Bật cho truyện **tây huyễn**: tên phiên âm lấy nghĩa chữ Latin trong từ điển (班森 Ban Sâm/Benson ⇒ Benson); tên chưa có trong từ điển thì máy đoán (伽罗斯 ⇒ Garos) và gắn nhãn **đoán** ở màn duyệt để kiểm lại.",
                        "Nhớ riêng cho từng truyện. Đừng bật cho truyện Trung: 史莱克 sẽ thành Shrek.",
                        "Lần đầu bật cần tải mô hình đoán tên (~150 KB); tải lỗi thì vẫn lọc, chỉ không chọn nghĩa Latin."
                    ],
                    isOn: Binding(
                        get: { prefersLatinNames },
                        set: { value in
                            prefersLatinNames = value
                            LocalNameFilterLatinPreferenceStore.shared.setPrefersLatin(value, bookId: bookId)
                        }
                    )
                )

                looseLatinRow
            } header: {
                SectionHelpHeader("Tuỳ chọn", paragraphs: [
                    "**Ít nhất N lần**: chỉ giữ name xuất hiện từ chừng ấy lần trở lên trong các chương đã chọn. Lọc ít chương thì nên hạ xuống 2.",
                    "**Độ dài name**: chỉ giữ name dài trong khoảng đã kéo, đếm theo chữ Hán (không tính dấu ·), áp cho mọi name kể cả name đã có. Đầu phải ở 10+ là không giới hạn; mặc định 2 – 10+ giữ mọi name như trước. Lựa chọn được nhớ cho lần lọc sau."
                ])
            }

            Section {
                listRow("Hậu tố", count: suffixCount, bookCount: suffixBookCount) {
                    LocalNameFilterSuffixListView(flavor: .suffix, bookId: bookId)
                }
                listRow("Tiền tố", count: prefixCount, bookCount: prefixBookCount) {
                    LocalNameFilterSuffixListView(flavor: .prefix, bookId: bookId)
                }
                listRow("Họ", count: surnameCount) {
                    LocalNameFilterSurnameListView()
                }
                listRow("Không phải name", count: blockedCount, bookCount: blockedBookCount) {
                    LocalNameFilterBlocklistView(bookId: bookId)
                }
            } header: {
                SectionHelpHeader("Danh sách", paragraphs: [
                    "Dùng chung cho mọi truyện. Số bên phải là số mục trong từng danh sách; Hậu tố / Tiền tố / Không phải name còn có danh sách **riêng của truyện này** (\"· N riêng\", chip Riêng truyện trong màn danh sách) — hậu tố / tiền tố cùng chữ thì bản riêng thắng, Không phải name chặn theo cả hai.",
                    "**Hậu tố**: ghép nghĩa name theo loại — địa danh, tổ chức, thuật ngữ (落霞镇 ⇒ Lạc Hà trấn) và danh xưng sau tên người, loại Nhân danh (陈长老 ⇒ Trần trưởng lão). **Tiền tố**: 老 / 小… đứng trước tên Latin (老尼尔 ⇒ lão Neil). Hai danh sách này chỉ dùng để dịch nghĩa; việc dò name dùng bộ hậu tố cố định trong app.",
                    "**Họ**: họ bộ lọc dùng để nhận ra tên người và đọc âm họ, riêng với Danh sách họ của rule dịch nhanh.",
                    "**Không phải name**: cụm đã loại, lần lọc sau không hiện nữa — ở riêng truyện này hoặc ở mọi truyện."
                ])
            }
        }.glassSheetRows() }
        // `onAppear` của gốc chạy lại mỗi lần quay về từ màn quản lý ⇒ số + công tắc Latin luôn mới.
        .onAppear { refreshListCounts() }
        .task { await loadChapters() }
        .task { await loadDrafts() }
    }

    /// Hàng **"Nới đoán tên Latin"** (2026-11-28, mockup https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung N5) ngay dưới
    /// "Ưu tiên tên Latin": tên + `?` + dòng phụ, công tắc chỉ bật được khi "Ưu tiên tên Latin" bật (tắt ⇒ mờ, hiện tắt; giá
    /// trị đã lưu giữ nguyên để bật lại Latin là có lại). Nhớ theo truyện (`LocalNameFilterLatinPreferenceStore.loose`).
    private var looseLatinRow: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text("Nới đoán tên Latin")
                    SectionHelpButton(accessibilityLabel: "Giải thích Nới đoán tên Latin", paragraphs: [
                        "Tên kiểu Latin có tiền tố / hậu tố (古赫密斯语, 霍伊河): phần lõi còn lại không có trong từ điển thì máy chỉ đoán khi **mọi** chữ của lõi là chữ phiên âm. Bật ⇒ chỉ cần **một nửa** số chữ.",
                        "Đo thử: bật làm 3 name đổi nghĩa, cả 3 xấu đi (小罗子 ⇒ tiểu Roko, 姜博海 ⇒ Djanbo hải) — nên để tắt, chỉ bật khi truyện có nhiều tên Latin lạ. Muốn nới cho riêng một name thì bật ở màn Sửa từ của name đó.",
                        "Chỉ bật được khi **Ưu tiên tên Latin** đang bật. Nhớ riêng cho từng truyện."
                    ])
                }
                Text("Lõi chỉ cần ½ số chữ là chữ phiên âm")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Nới đoán tên Latin", isOn: Binding(
                get: { prefersLatinNames && loosensLatinGuess },
                set: { value in
                    loosensLatinGuess = value
                    LocalNameFilterLatinPreferenceStore.loose.setOn(value, bookId: bookId)
                }
            ))
            .labelsHidden()
            .disabled(!prefersLatinNames)
        }
        .opacity(prefersLatinNames ? 1 : 0.45)
    }

    /// Hàng "Độ dài name" (L15, mockup khung 5): tiêu đề + khoảng đang chọn bên phải ("2 – 10+ chữ"), thanh kéo hai đầu.
    private var lengthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Độ dài name")
                Spacer(minLength: 8)
                Text(verbatim: LocalNameFilterLengthRangeSlider.rangeText(lower: minLengthSetting, upper: maxLengthSetting))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            LocalNameFilterLengthRangeSlider(lower: $minLengthSetting, upper: $maxLengthSetting)
        }
        .padding(.vertical, 4)
    }

    /// Một hàng của mục "Danh sách": tên + số mục (kiểu Việt, "1.299"; có mục riêng của truyện ⇒ "1.299 · 3 riêng") + mũi
    /// tên, đẩy màn quản lý vào `NavigationStack` của sheet.
    private func listRow<Destination: View>(
        _ title: String,
        count: Int,
        bookCount: Int = 0,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        let total = LocalNameFilterAffixKindFilterBar.formattedCount(count)
        let value = bookCount > 0 ? "\(total) · \(LocalNameFilterAffixKindFilterBar.formattedCount(bookCount)) riêng" : total
        return NavigationLink {
            destination()
        } label: {
            LabeledContent(title, value: value)
        }
    }

    private func noticeRow(_ notice: LocalNameFilterSession.Notice) -> some View {
        let isError: Bool
        let message: String
        switch notice {
        case .info(let text):
            isError = false
            message = text
        case .error(let text):
            isError = true
            message = text
        }
        return Label {
            Text(message)
                .foregroundColor(isError ? .red : .primary)
        } icon: {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundColor(isError ? .red : .secondary)
        }
    }

    /// Ba dòng chọn chương bắt đầu — không ghi gì xuống bộ nhớ.
    @ViewBuilder
    private func scopeRows(_ chapters: [AINameScanChapter]) -> some View {
        radioRow(
            title: "Chương đang đọc",
            subtitle: startPosition(for: .current).map { chapterName(chapters[$0]) }
                ?? "Không có chương đã tải từ chương đang đọc trở đi",
            isSelected: activeStart == .current
        ) {
            pickedStart = .current
        }

        radioRow(
            title: "Chương đầu tiên",
            subtitle: chapters.first.map { chapterName($0) } ?? "Chưa có chương nào đã tải",
            isSelected: activeStart == .first
        ) {
            pickedStart = .first
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
                subtitle: startPosition(for: .custom).map { chapterName(chapters[$0]) },
                isSelected: activeStart == .custom
            )
        }
        .disabled(chapters.isEmpty)
        .opacity(chapters.isEmpty ? 0.45 : 1)
    }

    private func radioRow(
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
                if let subtitle {
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

    // MARK: - Nạp dữ liệu

    private func refreshListCounts() {
        suffixCount = LocalNameFilterSuffixStore.shared.count
        prefixCount = LocalNameFilterPrefixStore.shared.count
        suffixBookCount = LocalNameFilterSuffixStore.shared.bookStore.count(bookId: bookId)
        prefixBookCount = LocalNameFilterPrefixStore.shared.bookStore.count(bookId: bookId)
        surnameCount = QuickTranslationSurnameStore.nameFilter.summary().total
        blockedCount = LocalNameFilterBlocklistStore.shared.count
        blockedBookCount = LocalNameFilterBookBlocklistStore.shared.count(bookId: bookId)
        prefersLatinNames = LocalNameFilterLatinPreferenceStore.shared.prefersLatin(bookId: bookId)
        loosensLatinGuess = LocalNameFilterLatinPreferenceStore.loose.isOn(bookId: bookId)
    }

    /// Nạp danh sách chương đã tải **một lần**; `.task` của gốc chạy lại khi quay về từ trang con ⇒ đã nạp thì thôi.
    private func loadChapters() async {
        guard chapters == nil else { return }
        let loaded = await AIBookDataInspector.shared.nameScanChapters(
            bookId: bookId,
            translatesTitles: translatesChapterTitles,
            convertsTraditionalToSimplified: convertsTraditionalToSimplified
        )
        // Bị huỷ giữa chừng (đẩy màn quản lý danh sách trước khi nạp xong) ⇒ tên chương chưa dịch hết; để `.task` nạp
        // lại khi quay về thay vì giữ bản dở.
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.chapters = loaded
        }
    }
}
