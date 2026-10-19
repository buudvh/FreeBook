import SwiftUI

struct BookDetailTOCView: View {
    @Binding var chapterSearchQuery: String
    let appliedSearchQuery: String // query đã debounce (~200 ms) dùng để lọc
    let totalChaps: Int
    @Binding var isTocAscending: Bool
    let tocErrorMessage: String
    let isLoadingTOC: Bool
    let localBook: Book?
    let filteredLocalChapters: [Chapter]
    let chapterSnapshots: [StoredChapterSnapshot]
    let filteredOnlineChapters: [(offset: Int, element: ChapterResult)]
    let tocPages: [String]
    let remainingPagesLoaded: Bool
    let isTranslationEnabled: Bool

    let onLoadTOCDataOnly: () -> Void
    let onStartReading: (Int) -> Void
    let onTranslateChapterTitleIfNeeded: (Chapter) -> String
    let onTranslateTitleIfNeeded: (String) -> String
    let onLoadMoreChapters: () -> Void
    /// "chương" hoặc "tập" (video) — `BookDetailView.episodeNoun`.
    var episodeNoun: String = "chương"
    /// `true` = nội dung video: vẽ **lưới tập** (`BookDetailVideoTOCGrid`) thay cho danh sách hàng.
    var isVideo: Bool = false

    /// Danh sách chương đã đảo chiều/lọc. Giữ trong `@State` vì view này bị vẽ lại theo mọi lần vẽ của
    /// `BookDetailView` (có closure nên không bỏ qua được): lọc `localizedStandardContains` hàng nghìn
    /// chương ở mỗi lần vẽ là việc thừa — chỉ tính lại khi query/chiều/mục lục đổi.
    @State private var visibleSnapshots: [StoredChapterSnapshot] = []

    var body: some View {
        Group {
            if isVideo {
                videoTOC
            } else {
                VStack(spacing: 0) {
                    if totalChaps > 0 {
                        searchBarView
                    }
                    tocListView
                }
            }
        }
        .onChange(of: appliedSearchQuery, initial: true) { recomputeVisibleSnapshots() }
        .onChange(of: isTocAscending) { recomputeVisibleSnapshots() }
        .onChange(of: chapterSnapshots) { recomputeVisibleSnapshots() }
    }

    // MARK: - Video: mục lục dạng lưới

    /// Nhánh video: cùng dữ liệu với danh sách hàng, khác cách trình bày. Tìm kiếm dùng chung
    /// `chapterSearchQuery` nên không có hai nguồn từ khoá.
    private var videoTOC: some View {
        BookDetailVideoTOCGrid(
            rows: videoRows,
            currentIndex: localBook?.currentChapterIndex ?? -1,
            isAscending: isTocAscending,
            isLoading: isLoadingTOC,
            errorMessage: tocErrorMessage,
            noun: episodeNoun,
            remainingPages: tocPages.count > 1 && !remainingPagesLoaded ? tocPages.count - 1 : 0,
            searchQuery: $chapterSearchQuery,
            onToggleSort: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTocAscending.toggle()
                }
            },
            onSelect: { onStartReading($0) },
            onReload: onLoadTOCDataOnly,
            onLoadMore: onLoadMoreChapters
        )
    }

    /// Dòng mục lục cho lưới tập. Giữ **đúng thứ tự ưu tiên** của danh sách hàng
    /// (`chapterSnapshots` → `Book.chapters` → `onlineChapters`) để hai cách hiển thị không lệch nhau.
    /// Số tập hiển thị do lưới tự đánh theo từng tab, nên ở đây chỉ chuyển dữ liệu thô.
    private var videoRows: [BookDetailVideoTOCGrid.Row] {
        videoSourceRows().map { item in
            BookDetailVideoTOCGrid.Row(
                index: item.index,
                title: item.title,
                isSection: item.isSection,
                isCached: item.isCached
            )
        }
    }

    private func videoSourceRows() -> [(index: Int, title: String, isSection: Bool, isCached: Bool)] {
        if !chapterSnapshots.isEmpty {
            return visibleSnapshots.map { chap in
                (index: chap.index,
                 title: isTranslationEnabled ? onTranslateTitleIfNeeded(chap.titleTrans ?? chap.title) : chap.title,
                 isSection: chap.isSection,
                 isCached: chap.isCached)
            }
        }
        if localBook != nil, !filteredLocalChapters.isEmpty {
            // `Book.chapters` luôn rỗng khi `enableSwiftDataTOCWrite = false`; giữ nhánh cho đồng bộ với danh sách hàng.
            return filteredLocalChapters.map { chap in
                (index: chap.index,
                 title: onTranslateChapterTitleIfNeeded(chap),
                 isSection: false,
                 isCached: chap.isCached)
            }
        }
        return onlineRows.map { row in
            (index: row.offset,
             title: onTranslateTitleIfNeeded(row.element.name),
             isSection: row.element.isSection,
             isCached: false)
        }
    }

    private func recomputeVisibleSnapshots() {
        visibleSnapshots = filteredChapterSnapshots
    }

    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Tìm kiếm \(episodeNoun)...", text: $chapterSearchQuery)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.none)
            if !chapterSearchQuery.isEmpty {
                Button(action: { chapterSearchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var filteredChapterSnapshots: [StoredChapterSnapshot] {
        // `fetchOrderedTOC` đã `ORDER BY chapter_index ASC` ⇒ chỉ cần đảo chiều, không sort lại mỗi lần vẽ.
        let sorted = isTocAscending
            ? chapterSnapshots
            : Self.liftSectionHeaders(Array(chapterSnapshots.reversed()), isSection: { $0.isSection })
        let query = appliedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { chap in
            chap.title.localizedStandardContains(query)
                || chap.titleTrans?.localizedStandardContains(query) == true
        }
    }

    private var tocListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Danh sách \(episodeNoun) (\(readableChapterCount))")
                        .font(.headline)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTocAscending.toggle()
                        }
                    }) {
                        Image(systemName: isTocAscending ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 4)

                    Spacer()
                    if totalChaps > 0 && !tocErrorMessage.isEmpty {
                        Button(action: onLoadTOCDataOnly) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Tải lại lỗi")
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)

                if isLoadingTOC && totalChaps == 0 {
                    HStack {
                        Spacer()
                        ProgressView("Đang tải danh sách \(episodeNoun)...")
                            .padding(.vertical, 30)
                        Spacer()
                    }
                } else if totalChaps == 0 {
                    if !tocErrorMessage.isEmpty {
                        VStack(spacing: 12) {
                            Text(tocErrorMessage)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Tải lại mục lục") {
                                onLoadTOCDataOnly()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Không tìm thấy chương nào hoặc lỗi tải chương")
                            .foregroundColor(.gray)
                            .padding()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let currentIdx = localBook?.currentChapterIndex ?? -1
                        if !chapterSnapshots.isEmpty {
                            ForEach(visibleSnapshots, id: \.id) { chap in
                                if chap.isSection {
                                    sectionHeader(isTranslationEnabled ? onTranslateTitleIfNeeded(chap.titleTrans ?? chap.title) : chap.title)
                                } else {
                                    Button(action: {
                                        onStartReading(chap.index)
                                    }) {
                                        HStack {
                                            let displayTitle = isTranslationEnabled ? onTranslateTitleIfNeeded(chap.titleTrans ?? chap.title) : chap.title
                                            let isCurrent = currentIdx == chap.index
                                            let isRead = currentIdx >= 0 && chap.index < currentIdx
                                            Text(displayTitle)
                                                .foregroundColor(isCurrent ? .white : (isRead ? Color.primary.opacity(0.4) : .primary))
                                                .font(.subheadline)
                                                .lineLimit(2)
                                            Spacer()
                                            if chap.isCached {
                                                Image(systemName: "arrow.down.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal)
                                        Divider()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else if let book = localBook, !filteredLocalChapters.isEmpty {
                            // `chaptersList` lấy từ `Book.chapters`, mà `enableSwiftDataTOCWrite = false` nên **luôn rỗng**:
                            // sách vừa được tạo (bấm "Đọc ngay") có `localBook != nil` mà chưa nạp kịp `chapterSnapshots`
                            // ⇒ nhánh này vẽ ra danh sách 0 dòng dù `onlineChapters` đang giữ đủ mục lục. Chỉ dùng khi có dữ liệu.
                            ForEach(filteredLocalChapters) { chap in
                                Button(action: {
                                    onStartReading(chap.index)
                                }) {
                                    HStack {
                                        let isCurrent = book.currentChapterIndex == chap.index
                                        let isRead = chap.index < book.currentChapterIndex
                                        Text(onTranslateChapterTitleIfNeeded(chap))
                                            .foregroundColor(isCurrent ? .white : (isRead ? Color.primary.opacity(0.4) : .primary))
                                            .font(.subheadline)
                                            .lineLimit(2)
                                        Spacer()
                                        if chap.isCached {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal)
                                    Divider()
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            ForEach(onlineRows, id: \.offset) { index, chap in
                                if chap.isSection {
                                    sectionHeader(onTranslateTitleIfNeeded(chap.name))
                                } else {
                                    Button(action: {
                                        onStartReading(index)
                                    }) {
                                        VStack(alignment: .leading) {
                                            let isCurrent = currentIdx == index
                                            let isRead = currentIdx >= 0 && index < currentIdx
                                            Text(onTranslateTitleIfNeeded(chap.name))
                                                .font(.subheadline)
                                                .foregroundColor(isCurrent ? .white : (isRead ? Color.primary.opacity(0.4) : .primary))
                                                .lineLimit(2)
                                                .padding(.vertical, 12)
                                                .padding(.horizontal)
                                            Divider()
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if tocPages.count > 1 && !remainingPagesLoaded {
                            Button(action: onLoadMoreChapters) {
                                HStack {
                                    Spacer()
                                    Text("Tải thêm \(episodeNoun) (còn \(tocPages.count - 1) trang)")
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
                                .padding(.horizontal)
                                .padding(.top, 10)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Nhóm tập (section)

    /// Số chương trên tiêu đề danh sách: dòng tiêu đề nhóm (`isSection`, ext nhiều server) không chạm được nên
    /// không tính.
    private var readableChapterCount: Int {
        let sectionRows: Int
        if !chapterSnapshots.isEmpty {
            sectionRows = chapterSnapshots.reduce(0) { count, chapter in chapter.isSection ? count + 1 : count }
        } else {
            sectionRows = filteredOnlineChapters.reduce(0) { count, row in row.element.isSection ? count + 1 : count }
        }
        return max(0, totalChaps - sectionRows)
    }

    /// `BookDetailView` đảo chiều mục lục online sẵn; giữ tiêu đề nhóm ở đầu nhóm khi xếp giảm dần.
    private var onlineRows: [(offset: Int, element: ChapterResult)] {
        guard !isTocAscending else { return filteredOnlineChapters }
        return Self.liftSectionHeaders(filteredOnlineChapters, isSection: { $0.element.isSection })
    }

    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 6)
            Divider()
        }
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
