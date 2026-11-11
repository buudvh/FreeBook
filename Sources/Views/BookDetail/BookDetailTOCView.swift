import SwiftUI

struct BookDetailTOCView: View {
    @Binding var chapterSearchQuery: String
    let appliedSearchQuery: String // query đã debounce (~200 ms) dùng để lọc
    let totalChaps: Int
    @Binding var isTocAscending: Bool
    let tocErrorMessage: String
    /// Link "Mở link lỗi" của `tocErrorMessage`; `BookDetailView` gắn `.errorLinkBrowser` cho `openingErrorLink`.
    let tocErrorLink: SourceErrorLink?
    @Binding var openingErrorLink: SourceErrorLink?
    let isLoadingTOC: Bool
    let localBook: Book?
    let filteredLocalChapters: [Chapter]
    let chapterSnapshots: [StoredChapterSnapshot]
    let filteredOnlineChapters: [(offset: Int, element: ChapterResult)]
    /// Số thứ tự của mục lục online, dựng từ **toàn bộ** `onlineChapters` ở `BookDetailView` (danh sách ở đây đã lọc
    /// khi tìm nên không đếm được dòng tiêu đề nhóm đứng trước).
    let onlineNumbering: ChapterOrdinalNumbering
    let tocPages: [String]
    let remainingPagesLoaded: Bool
    let isTranslationEnabled: Bool
    /// Cờ chữ của mục lục (`BookDetailView.tocTitleOptions`, đọc một lần mỗi lượt vẽ của trang — 1.3.846): tên hàng qua
    /// `BookDetailView.tocTitle(for:_:)` / `ChineseTextPipeline.chapterTitle` (phồn → giản cả khi tắt dịch); ô tìm khớp
    /// cả tên đã chuyển.
    let titleOptions: ChineseTextPipeline.Options

    let onLoadTOCDataOnly: () -> Void
    let onStartReading: (Int) -> Void
    let onLoadMoreChapters: () -> Void

    /// Danh sách chương đã đảo chiều/lọc. Giữ trong `@State` vì view này bị vẽ lại theo mọi lần vẽ của
    /// `BookDetailView` (có closure nên không bỏ qua được): lọc hàng nghìn chương ở mỗi lần vẽ là việc
    /// thừa — chỉ tính lại khi query/chiều/mục lục đổi.
    @State private var visibleSnapshots: [StoredChapterSnapshot] = []
    @State var didAutoLoadMoreChapters = false // `+AutoLoad`: tự tải trang mục lục còn lại tối đa một lần
    @State var freshlyCachedIndices: Set<Int> = [] // `+DownloadEvents`: chương vừa tải xong, `chapterSnapshots` chưa có
    /// Số thứ tự của mục lục đã lưu, dựng lại chỉ khi `chapterSnapshots` đổi (không theo từ khoá / chiều).
    @State private var snapshotNumbering = ChapterOrdinalNumbering.empty
    @AppStorage(ChapterOrdinalNumbering.showsOrdinalKey)
    private var showsChapterOrdinal = ChapterOrdinalNumbering.showsOrdinalDefault

    var body: some View {
        // Panel Mục lục dùng chung với Reader/comic: đầu panel + ô tìm đứng yên, chỉ danh sách cuộn.
        VStack(spacing: 0) {
            ChapterTOCPanelHeader(
                chapterCount: readableChapterCount,
                noun: "chương",
                searchText: totalChaps > 0 ? $chapterSearchQuery : nil,
                isAscending: isTocAscending,
                palette: .system,
                onToggleSort: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTocAscending.toggle()
                    }
                }
            ) {
                tocErrorActions
            }
            tocListView
        }
        .chapterTOCPanel(.system)
        .padding(.top, 12)
        .onChange(of: appliedSearchQuery) { recomputeVisibleSnapshots() }
        .onChange(of: isTocAscending) { recomputeVisibleSnapshots() }
        .onChange(of: chapterSnapshots, initial: true) { oldSnapshots, _ in
            snapshotNumbering = ChapterOrdinalNumbering(chapterSnapshots, index: { $0.index }, isSection: { $0.isSection })
            recomputeVisibleSnapshots()
            reconcileFreshlyCached(previousCount: oldSnapshots.count)
        }
        .task(id: localBook?.bookId) { await observeChapterDownloads() }
    }

    private func recomputeVisibleSnapshots() {
        visibleSnapshots = filteredChapterSnapshots
    }

    /// Đã có mục lục nhưng lượt tải lại lỗi: "Tải lại lỗi" + la bàn "Mở link lỗi", đứng trước nút sắp xếp ở đầu panel.
    @ViewBuilder
    private var tocErrorActions: some View {
        if totalChaps > 0 && !tocErrorMessage.isEmpty {
            Button(action: onLoadTOCDataOnly) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("Tải lại lỗi")
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            if let link = tocErrorLink {
                // Nút tròn la bàn 24pt, vùng chạm 36×36 — cùng hàng với nút sắp xếp.
                Button { openingErrorLink = link } label: {
                    Image(systemName: ErrorLinkButton.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.16)))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ErrorLinkButton.accessibilityText)
                .accessibilityHint(link.displayText)
            }
        }
    }

    private var filteredChapterSnapshots: [StoredChapterSnapshot] {
        // `fetchOrderedTOC` đã `ORDER BY chapter_index ASC` ⇒ chỉ cần đảo chiều, không sort lại mỗi lần vẽ.
        let sorted = isTocAscending
            ? chapterSnapshots
            : Self.liftSectionHeaders(Array(chapterSnapshots.reversed()), isSection: { $0.isSection })
        let query = appliedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        // Khớp tên gốc + tên đã chuyển phồn → giản (rẻ, có memo) + bản lưu (không dịch sống từng dòng trên main mỗi lần
        // gõ), bỏ qua hoa/thường và dấu như Reader.
        let converts = titleOptions.converts
        return sorted.filter { chap in
            ChapterTitleSearchMatcher.matches(
                query, anyOf: [chap.title, ChineseTextPipeline.convert(chap.title, converts: converts), chap.titleTrans]
            )
        }
    }

    private var tocListView: some View {
        ScrollView {
            if isLoadingTOC && totalChaps == 0 {
                HStack {
                    Spacer()
                    ProgressView("Đang tải danh sách chương...")
                        .padding(.vertical, 30)
                    Spacer()
                }
            } else if totalChaps == 0 {
                if !tocErrorMessage.isEmpty {
                    BookDetailTOCErrorBlock(
                        message: tocErrorMessage,
                        link: tocErrorLink,
                        openingLink: $openingErrorLink,
                        onReload: onLoadTOCDataOnly
                    )
                } else {
                    Text("Không tìm thấy chương nào hoặc lỗi tải chương")
                        .foregroundColor(.gray)
                        .padding()
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let currentIdx = localBook?.currentChapterIndex ?? -1
                    if !chapterSnapshots.isEmpty {
                        let ordinalDigits = showsChapterOrdinal ? snapshotNumbering.digits : 0
                        ForEach(visibleSnapshots, id: \.id) { chap in
                            let displayTitle = BookDetailView.tocTitle(for: chap, titleOptions)
                            if chap.isSection {
                                sectionHeader(displayTitle)
                            } else {
                                BookDetailTOCRow(
                                    title: displayTitle,
                                    ordinal: snapshotNumbering.ordinal(forIndex: chap.index),
                                    ordinalDigits: ordinalDigits,
                                    isCurrent: currentIdx == chap.index,
                                    isRead: currentIdx >= 0 && chap.index < currentIdx,
                                    isCached: chap.isCached || freshlyCachedIndices.contains(chap.index),
                                    palette: .system,
                                    onSelect: { onStartReading(chap.index) }
                                )
                            }
                        }
                    } else if let book = localBook, !filteredLocalChapters.isEmpty {
                        // `chaptersList` lấy từ `Book.chapters`, mà `enableSwiftDataTOCWrite = false` nên **luôn rỗng**:
                        // sách vừa được tạo (bấm "Đọc ngay") có `localBook != nil` mà chưa nạp kịp `chapterSnapshots`
                        // ⇒ nhánh này vẽ ra danh sách 0 dòng dù `onlineChapters` đang giữ đủ mục lục. Chỉ dùng khi có dữ liệu.
                        // Bảng SwiftData `Chapter` không có dòng tiêu đề nhóm ⇒ số = index + 1.
                        let localCount = (filteredLocalChapters.map(\.index).max() ?? -1) + 1
                        let ordinalDigits = showsChapterOrdinal ? ChapterOrdinalNumbering(chapterCount: localCount).digits : 0
                        ForEach(filteredLocalChapters) { chap in
                            BookDetailTOCRow(
                                title: BookDetailView.tocTitle(for: chap, titleOptions),
                                ordinal: chap.index + 1,
                                ordinalDigits: ordinalDigits,
                                isCurrent: book.currentChapterIndex == chap.index,
                                isRead: chap.index < book.currentChapterIndex,
                                isCached: chap.isCached || freshlyCachedIndices.contains(chap.index),
                                palette: .system,
                                onSelect: { onStartReading(chap.index) }
                            )
                        }
                    } else {
                        let ordinalDigits = showsChapterOrdinal ? onlineNumbering.digits : 0
                        ForEach(onlineRows, id: \.offset) { index, chap in
                            if chap.isSection {
                                sectionHeader(ChineseTextPipeline.chapterTitle(chap.name, titleOptions))
                            } else {
                                BookDetailTOCRow(
                                    title: ChineseTextPipeline.chapterTitle(chap.name, titleOptions),
                                    ordinal: onlineNumbering.ordinal(forIndex: index),
                                    ordinalDigits: ordinalDigits,
                                    isCurrent: currentIdx == index,
                                    isRead: currentIdx >= 0 && index < currentIdx,
                                    isCached: freshlyCachedIndices.contains(index),
                                    palette: .system,
                                    onSelect: { onStartReading(index) }
                                )
                            }
                        }
                    }

                    if tocPages.count > 1 && !remainingPagesLoaded {
                        Button(action: onLoadMoreChapters) {
                            HStack {
                                Spacer()
                                Text("Tải thêm chương (còn \(tocPages.count - 1) trang)")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(Color.white.opacity(0.16))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                            .padding(.horizontal, 8)
                            .padding(.top, 10)
                        }
                        .onAppear(perform: autoLoadMoreChaptersIfNeeded) // nằm trong `LazyVStack` ⇒ chỉ khi cuộn tới cuối
                    }
                }
                // Hàng tự đệm ngang 8 (nền chương đang đọc) ⇒ chữ thẳng lề 16 với đầu panel.
                .padding(.horizontal, 8)
                .padding(.bottom)
            }
        }
    }

    // MARK: - Nhóm tập (section)

    /// Số chương trên tiêu đề danh sách: dòng tiêu đề nhóm (`isSection`, ext nhiều server) không chạm được nên
    /// không tính. Lấy từ cùng bộ số thứ tự của danh sách ⇒ N luôn bằng số lớn nhất, kể cả khi đang tìm.
    private var readableChapterCount: Int {
        chapterSnapshots.isEmpty ? onlineNumbering.chapterCount : snapshotNumbering.chapterCount
    }

    /// `BookDetailView` đảo chiều mục lục online sẵn; giữ tiêu đề nhóm ở đầu nhóm khi xếp giảm dần.
    private var onlineRows: [(offset: Int, element: ChapterResult)] {
        guard !isTocAscending else { return filteredOnlineChapters }
        return Self.liftSectionHeaders(filteredOnlineChapters, isSection: { $0.element.isSection })
    }

    /// Nhãn nhóm tập — không vạch riêng: hàng chương ngay dưới tự vẽ vạch ở trên nó (`BookDetailTOCRow`).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundColor(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    /// Danh sách **đã đảo chiều**: tiêu đề nhóm đứng sau các tập của nó — đưa lên đầu nhóm. Tập đứng trước tiêu đề
    /// đầu tiên (không thuộc nhóm nào) giữ ở cuối, đúng thứ tự giảm dần.
    private static func liftSectionHeaders<Row>(_ reversedRows: [Row], isSection: (Row) -> Bool) -> [Row] {
        var result: [Row] = []
        result.reserveCapacity(reversedRows.count)
        var pending: [Row] = []
        for row in reversedRows {
            if isSection(row) {
                result.append(row)
                result.append(contentsOf: pending)
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(row)
            }
        }
        result.append(contentsOf: pending)
        return result
    }
}
