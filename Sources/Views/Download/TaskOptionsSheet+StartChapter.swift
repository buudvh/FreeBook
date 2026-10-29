import SwiftUI

/// Mục "Bắt đầu từ" của `TaskOptionsSheet` (1.3.624): thay công tắc "Tải từ chương đang đọc" bằng ba dòng chọn, cùng
/// kiểu sheet quét tên riêng (`ReaderAIBatchPromptSheet`).
///
/// - "Chương đang đọc" (mặc định, như công tắc cũ) và "Chương đầu tiên" đi qua `startFromCurrent`.
/// - "Chọn chương…" mở `ReaderAINameScanChapterPickerView` với **toàn bộ** mục lục. Chương chọn được ghi sidecar theo
///   tác vụ (`DownloadStartChapterStore`; video thì `VideoDownloadRequestStore`).
/// - Mục lục và tên dịch nạp ngầm qua `DownloadStartChapterCatalog` (ngoài main thread). Trong lúc đó dòng "Chọn
///   chương…" báo đang nạp và tạm khoá; hai dòng còn lại hiện số chương, đủ tên khi dịch xong.
extension TaskOptionsSheet {
    enum StartChoice {
        case current
        case first
        case custom
    }

    var startChapterSection: some View {
        Section {
            startRow(
                title: isVideo ? "Tập đang xem" : "Chương đang đọc",
                subtitle: chapterLabel(index: book.currentChapterIndex),
                choice: .current
            )

            startRow(
                title: isVideo ? "Tập đầu tiên" : "Chương đầu tiên",
                subtitle: pickerChapters?.first.map { chapterLabel(for: $0) } ?? numberLabel(position: 0),
                choice: .first
            )

            NavigationLink {
                ReaderAINameScanChapterPickerView(
                    chapters: pickerChapters ?? [],
                    noun: unitNoun,
                    selectedIndex: customStartIndex ?? book.currentChapterIndex
                ) { index in
                    customStartIndex = index
                    startChoice = .custom
                }
            } label: {
                radioLabel(
                    title: "Chọn \(unitNoun)…",
                    subtitle: customSubtitle,
                    isSelected: startChoice == .custom
                )
            }
            .disabled(pickerChapters?.isEmpty ?? true)
        } header: {
            helpHeader("Bắt đầu từ", paragraphs: startHelpParagraphs)
        }
    }

    /// Nạp mục lục **một lần** cho cả dòng "Đã tải X/Y chương" lẫn màn chọn chương, rồi dịch tên ngầm.
    ///
    /// Đẩy màn "Chọn chương…" làm `.task` của màn gốc bị huỷ và chạy lại khi quay về, nên mỗi bước tự bỏ qua khi đã có
    /// kết quả. Bị huỷ giữa lúc dịch thì lần chạy sau dịch lại. Gắn `@MainActor` để mọi lần ghi `@State` ở main;
    /// phần nặng (đọc sqlite, dịch tên) chạy ngoài main trong `DownloadStartChapterCatalog`.
    @MainActor
    func loadChapterCatalog() async {
        if tocChapters == nil {
            var toc = await DownloadStartChapterCatalog.fetchTOC(bookId: book.bookId)
            if toc.isEmpty {
                toc = legacyTOC()
            }
            tocChapters = toc
            if isComicExport {
                // Truyện tranh: "đã tải" = chương có manifest ảnh offline (đọc đĩa ngoài main), bỏ dòng tiêu đề nhóm.
                let readable = toc.filter { !$0.isSection }
                let bookId = book.bookId
                let downloaded = await Task.detached { ComicOfflineStore.downloadedChapterIndexes(bookId: bookId) }.value
                totalChapterCount = readable.count
                cachedChapterCount = readable.filter { downloaded.contains($0.index) }.count
            } else {
                totalChapterCount = toc.count
                cachedChapterCount = toc.filter { $0.isCached && $0.length > 0 }.count
            }
        }

        guard pickerChapters == nil, let toc = tocChapters else { return }
        let chapters = await DownloadStartChapterCatalog.pickerChapters(
            from: toc,
            bookId: book.bookId,
            packageId: book.extensionPackageId,
            contentKind: contentKind
        )
        guard !Task.isCancelled else { return }
        pickerChapters = chapters
    }

    // MARK: - Nhãn

    private var customSubtitle: String {
        if let index = customStartIndex {
            return chapterLabel(index: index)
        }
        if tocChapters == nil {
            return "Đang tải mục lục…"
        }
        guard let chapters = pickerChapters else {
            return "Đang dịch danh sách \(unitNoun)…"
        }
        return chapters.isEmpty ? "Chưa có mục lục" : "Chọn trong mục lục"
    }

    /// "ch.12: tên đã dịch" khi danh sách đã sẵn, không thì chỉ "ch.12".
    private func chapterLabel(index: Int) -> String {
        if let chapter = pickerChapters?.first(where: { $0.index == index }) {
            return chapterLabel(for: chapter)
        }
        return numberLabel(position: index)
    }

    private func chapterLabel(for chapter: AINameScanChapter) -> String {
        let number = numberLabel(position: chapter.index)
        return chapter.title.isEmpty ? number : "\(number): \(chapter.title)"
    }

    private func numberLabel(position: Int) -> String {
        isVideo ? "Tập \(position + 1)" : "ch.\(position + 1)"
    }

    // MARK: - Dòng chọn

    private func startRow(title: String, subtitle: String, choice: StartChoice) -> some View {
        Button {
            startChoice = choice
        } label: {
            radioLabel(title: title, subtitle: subtitle, isSelected: startChoice == choice)
        }
        .buttonStyle(.plain)
    }

    private func radioLabel(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    /// Truyện cũ chưa có mục lục ở `ChapterStore`: đọc bảng SwiftData `Chapter`, cùng fallback với
    /// `DownloadManager.executeTask`.
    private func legacyTOC() -> [StoredChapterSnapshot] {
        book.chapters.sorted(by: { $0.index < $1.index }).map { chapter in
            StoredChapterSnapshot(
                id: chapter.id,
                bookId: chapter.bookId,
                title: chapter.title,
                url: chapter.url,
                index: chapter.index,
                host: chapter.host,
                titleTrans: chapter.titleTrans,
                isCached: chapter.isCached,
                offset: chapter.offset,
                length: chapter.length
            )
        }
    }
}
