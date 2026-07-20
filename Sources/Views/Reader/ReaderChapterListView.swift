import SwiftUI
import SwiftData
import Observation

@MainActor
@Observable
final class ReaderChapterRowState: Identifiable {
    let id: Int
    let title: String
    let url: String
    var isCached: Bool

    init(index: Int, title: String, url: String, isCached: Bool) {
        self.id = index
        self.title = title
        self.url = url
        self.isCached = isCached
    }
}

@MainActor
@Observable
final class ReaderChapterListStore {
    private(set) var rows: [ReaderChapterRowState] = []
    private var rowsByIndex: [Int: ReaderChapterRowState] = [:]

    init(sortedChapters: [Chapter], onlineChapters: [ChapterResult]) {
        replace(sortedChapters: sortedChapters, onlineChapters: onlineChapters)
    }

    func markCached(index: Int) {
        rowsByIndex[index]?.isCached = true
    }

    func synchronize(sortedChapters: [Chapter], onlineChapters: [ChapterResult]) {
        let descriptors = Self.descriptors(sortedChapters: sortedChapters, onlineChapters: onlineChapters)
        let commonCount = min(rows.count, descriptors.count)
        let prefixIsStable = (0..<commonCount).allSatisfy { offset in
            let row = rows[offset]
            let descriptor = descriptors[offset]
            return row.id == descriptor.index && row.url == descriptor.url && row.title == descriptor.title
        }

        guard prefixIsStable else {
            replace(descriptors: descriptors)
            return
        }

        for descriptor in descriptors.prefix(commonCount) where descriptor.isCached {
            rowsByIndex[descriptor.index]?.isCached = true
        }

        if descriptors.count > rows.count {
            for descriptor in descriptors.dropFirst(rows.count) {
                let row = ReaderChapterRowState(
                    index: descriptor.index,
                    title: descriptor.title,
                    url: descriptor.url,
                    isCached: descriptor.isCached
                )
                rows.append(row)
                rowsByIndex[descriptor.index] = row
            }
        } else if descriptors.count < rows.count {
            replace(descriptors: descriptors)
        }
    }

    private func replace(sortedChapters: [Chapter], onlineChapters: [ChapterResult]) {
        replace(descriptors: Self.descriptors(sortedChapters: sortedChapters, onlineChapters: onlineChapters))
    }

    private func replace(descriptors: [(index: Int, title: String, url: String, isCached: Bool)]) {
        let newRows = descriptors.map { descriptor in
            ReaderChapterRowState(
                index: descriptor.index,
                title: descriptor.title,
                url: descriptor.url,
                isCached: descriptor.isCached
            )
        }
        rows = newRows
        rowsByIndex = Dictionary(uniqueKeysWithValues: newRows.map { ($0.id, $0) })
    }

    private static func descriptors(
        sortedChapters: [Chapter],
        onlineChapters: [ChapterResult]
    ) -> [(index: Int, title: String, url: String, isCached: Bool)] {
        if !sortedChapters.isEmpty {
            return sortedChapters.map { ($0.index, $0.title, $0.url, $0.isCached) }
        }
        return onlineChapters.enumerated().map { index, chapter in
            (index, chapter.name, chapter.url, false)
        }
    }
}

struct ReaderChapterListView: View {
    let bookId: String
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDetailUrl: String?
    let localBook: Book?
    let ext: Extension?
    let currentChapterIndex: Int
    let isTranslationEnabled: Bool
    let theme: ReaderTheme
    let store: ReaderChapterListStore
    @Binding var onlineChapters: [ChapterResult]
    let onSelectChapter: (Int) -> Void
    let onClose: () -> Void
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showingBookDetail = false
    @State private var searchQuery = ""
    @State private var isAscending = true
    @State private var isUpdating = false
    @State private var errorMessage = ""
    @State private var didPositionInitialChapter = false

    private var filteredChapters: [ReaderChapterRowState] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches: [ReaderChapterRowState]
        if query.isEmpty {
            matches = store.rows
        } else {
            matches = store.rows.filter { chapter in
                chapter.title.localizedCaseInsensitiveContains(query) ||
                    displayTitle(for: chapter).localizedCaseInsensitiveContains(query)
            }
        }
        return isAscending ? matches : Array(matches.reversed())
    }

    private var metadataTitle: String {
        let original = firstNonempty(localBook?.title, bookTitle) ?? "FreeBook"
        guard isTranslationEnabled, TranslateUtils.containsChinese(original) else {
            return original
        }
        return TranslateUtils.translateMeta(original, bookId: bookId)
    }

    private var metadataAuthor: String {
        let original = firstNonempty(localBook?.author, bookAuthor) ?? "Không rõ"
        guard isTranslationEnabled, TranslateUtils.containsChinese(original) else {
            return original
        }
        return TranslateUtils.translateAuthorHanViet(original)
    }

    private var metadataCoverUrl: String {
        firstNonempty(localBook?.coverUrl, bookCoverUrl) ?? ""
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().background(theme.textColor.opacity(0.1))

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Divider().background(theme.textColor.opacity(0.1))
                }

                searchField
                chapterList
            }
            .background(theme.backgroundColor.ignoresSafeArea())
        }
        .accessibilityAction(.escape) {
            onClose()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(theme.textColor.opacity(0.3))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 12) {
                Button(action: { showingBookDetail = true }) {
                    BookCoverView(
                        bookId: bookId,
                        coverUrl: metadataCoverUrl,
                        width: 72,
                        height: 100
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(bookDetailUrl == nil || ext == nil)
                .sheet(isPresented: $showingBookDetail) {
                    if let detailUrl = bookDetailUrl, let ext {
                        NavigationStack {
                            BookDetailView(
                                bookId: bookId,
                                extensionPackageId: ext.packageId,
                                initialDetailUrl: detailUrl,
                                sourceName: ext.name
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(metadataTitle)
                        .font(.headline)
                        .foregroundColor(theme.textColor)
                        .lineLimit(2)

                    Text(metadataAuthor)
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.72))
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        Text("\(store.rows.count) chương")
                            .font(.caption.weight(.medium))
                            .foregroundColor(theme.textColor.opacity(0.72))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 4)

                        if isUpdating {
                            ProgressView()
                                .tint(theme.textColor)
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("Đang cập nhật mục lục")
                        } else {
                            Button(action: refreshChapters) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(theme.textColor)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Cập nhật mục lục")
                        }

                        Button(action: { isAscending.toggle() }) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.body.weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(isAscending ? "Sắp xếp chương giảm dần" : "Sắp xếp chương tăng dần")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(theme.backgroundColor)
        .contentShape(Rectangle())
        .simultaneousGesture(dismissGesture)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let v = value.translation.height
                let h = abs(value.translation.width)
                guard v > 0, v >= h else { return }
                onDragChanged?(v)
            }
            .onEnded { value in
                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = value.translation.height
                guard verticalDistance >= 72,
                      verticalDistance >= horizontalDistance * 1.25 else {
                    onDragEnded?(0)
                    return
                }
                onDragEnded?(verticalDistance)
            }
    }

    private func firstNonempty(_ primary: String?, _ fallback: String?) -> String? {
        for value in [primary, fallback] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(theme.textColor.opacity(0.6))
            TextField("Tìm kiếm chương...", text: $searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundColor(theme.textColor)
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(theme.textColor.opacity(0.6))
                }
            }
        }
        .padding(10)
        .background(theme.textColor.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredChapters) { chapter in
                    ReaderChapterRowView(
                        chapter: chapter,
                        isCurrent: chapter.id == currentChapterIndex,
                        displayTitle: displayTitle(for: chapter),
                        theme: theme,
                        onSelect: {
                            onSelectChapter(chapter.id)
                            onClose()
                        }
                    )
                    .id(chapter.id)
                }
            }
            .listStyle(.plain)
            .background(theme.backgroundColor)
            .scrollContentBackground(.hidden)
            .onAppear {
                guard !didPositionInitialChapter else { return }
                didPositionInitialChapter = true
                DispatchQueue.main.async {
                    proxy.scrollTo(currentChapterIndex, anchor: .center)
                }
            }
        }
    }

    private func displayTitle(for chapter: ReaderChapterRowState) -> String {
        guard isTranslationEnabled, TranslateUtils.containsChinese(chapter.title) else {
            return chapter.title
        }
        return TranslateUtils.translateChapterTitle(chapter.title, bookId: bookId)
    }

    private func refreshChapters() {
        guard let ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách!"
            ToastManager.shared.show(message: errorMessage, type: .error)
            return
        }
        let url = localBook?.detailUrl ?? bookDetailUrl ?? ""
        guard !url.isEmpty else {
            errorMessage = "Đường dẫn truyện không hợp lệ!"
            ToastManager.shared.show(message: errorMessage, type: .error)
            return
        }

        isUpdating = true
        errorMessage = ""
        Task {
            do {
                var allChapters: [ChapterResult] = []
                if ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: "page") {
                    let pages = try await ExtensionManager.shared.page(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                    for pageURL in pages {
                        allChapters.append(contentsOf: try await ExtensionManager.shared.toc(
                            localPath: ext.localPath,
                            downloadUrl: ext.downloadUrl,
                            url: pageURL,
                            host: localBook?.host,
                            configJson: ext.configJson
                        ))
                    }
                } else {
                    allChapters = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                }

                if let book = localBook {
                    let existingURLs = Set(book.chapters.map(\.url))
                    let additions = allChapters.enumerated().filter { !existingURLs.contains($0.element.url) }
                    for (index, item) in additions {
                        let chapter = Chapter(
                            id: "\(bookId)_\(item.url)",
                            title: item.name,
                            url: item.url,
                            index: index,
                            host: item.host
                        )
                        chapter.book = book
                        modelContext.insert(chapter)
                        book.chapters.append(chapter)
                    }
                    if (book.host ?? "").isEmpty, let host = allChapters.first?.host, !host.isEmpty {
                        book.host = host
                    }
                    try? modelContext.save()
                    store.synchronize(sortedChapters: book.chapters.sorted(by: { $0.index < $1.index }), onlineChapters: onlineChapters)
                    ToastManager.shared.show(message: additions.isEmpty ? "Mục lục đã mới nhất" : "Đã thêm \(additions.count) chương mới", type: .success)
                } else {
                    let oldCount = onlineChapters.count
                    onlineChapters = allChapters
                    store.synchronize(sortedChapters: [], onlineChapters: allChapters)
                    let added = max(0, allChapters.count - oldCount)
                    ToastManager.shared.show(message: added == 0 ? "Mục lục đã mới nhất" : "Đã thêm \(added) chương mới", type: .success)
                }
                isUpdating = false
            } catch {
                errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
                isUpdating = false
                ToastManager.shared.show(message: errorMessage, type: .error)
            }
        }
    }
}

private struct ReaderChapterRowView: View {
    let chapter: ReaderChapterRowState
    let isCurrent: Bool
    let displayTitle: String
    let theme: ReaderTheme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(displayTitle)
                    .font(.body)
                    .foregroundColor(isCurrent ? .blue : theme.textColor)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Spacer()
                if chapter.isCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(isCurrent ? Color.blue.opacity(0.08) : theme.backgroundColor)
    }
}
