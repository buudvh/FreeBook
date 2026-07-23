import SwiftUI
import SwiftData

extension Notification.Name {
    static let bookChaptersUpdated = Notification.Name("bookChaptersUpdatedNotification")
}

struct ReaderRoute: Identifiable, Hashable {
    let chapterIndex: Int
    var id: Int { chapterIndex }
}

struct BookDetailView: View {
    @Environment(\.chapterRepository) private var chapterRepository
    @Environment(\.bookStorageManager) private var bookStorageManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]
    @Query private var allExtensions: [Extension]

    let bookId: String
    let extensionPackageId: String
    let initialDetailUrl: String
    let sourceName: String
    let initialHost: String?

    init(bookId: String, extensionPackageId: String, initialDetailUrl: String, sourceName: String, initialHost: String? = nil) {
        self.bookId = bookId
        self.extensionPackageId = extensionPackageId
        self.initialDetailUrl = initialDetailUrl
        self.sourceName = sourceName
        self.initialHost = initialHost
        self._host = State(initialValue: initialHost ?? "")
    }

    @State private var isLoadingDetail = true
    @State private var isLoadingTOC = true
    @State private var detailErrorMessage = ""
    @State private var tocErrorMessage = ""

    @State private var genres: [CategoryResult] = []
    @State private var suggests: [CategoryResult] = []
    @State private var comments: [CategoryResult] = []

    // Dữ liệu tạm thời khi xem online (chưa thêm vào kệ)
    @State private var title = ""
    @State private var author = ""
    @State private var coverUrl = ""
    @State private var desc = ""
    @State private var isDescExpanded = false
    @State private var isTocAscending = true
    @State private var renderedTab = 0
    @State private var detail = ""
    @State private var onlineChapters: [ChapterResult] = []
    @State private var totalChaptersCount: Int = 0
    @State private var chaptersList: [Chapter] = []
    @State private var filteredLocalChapters: [Chapter] = []
    @State private var filteredOnlineChapters: [(offset: Int, element: ChapterResult)] = []
    @State private var host = ""
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    // Cấu hình tab và FAB
    @State private var selectedTab = 0
    @State private var isMenuExpanded = false
    @State private var loadingTask: Task<Void, Never>? = nil

    // Màn hình chuẩn bị mở sách mới
    @State private var isPreparingBook = false
    @State private var preparingStatusText = "Đang chuẩn bị danh sách chương..."
    @State private var preparingTargetChapterTitle = ""
    @State private var bookOpenTask: Task<Void, Never>? = nil
    @AppStorage("readerSelectedTheme") private var readerTheme: ReaderTheme = .dark

    // Phân trang danh sách chương
    @State private var tocPages: [String] = []
    @State private var remainingPagesLoaded = false
    @State private var isLoadingRemainingPages = false
    @State private var readerRoute: ReaderRoute?
    @State private var navigateToDictionary = false
    @State private var navigateToChangeSource = false

    // Trình duyệt bypass Cloudflare & Import
    @State private var showingBypassBrowser = false
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToImportedBook = false
    @State private var chapterSearchQuery = ""

    // Quản lý tác vụ tải/xuất
    @State private var selectedTaskType: TaskType = .download
    @State private var selectedBookForTask: Book? = nil

    @State private var resolvedBookId: String = ""
    @State private var createdBookInstance: Book? = nil
    @State private var progressiveTocTask: Task<Void, Never>? = nil
    @State private var progressiveLoadingPageText: String = ""
    @State private var loadedPageUrls: Set<String> = []

    private var actualBookId: String {
        resolvedBookId.isEmpty ? bookId : resolvedBookId
    }

    private var effectiveBook: Book? {
        localBook ?? createdBookInstance
    }

    // Tìm sách local trong database
    private var localBook: Book? {
        allBooks.first(where: {
            $0.detailUrl == initialDetailUrl && $0.extensionPackageId == extensionPackageId
        })
    }

    // Tìm extension cục bộ để chạy script
    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }

    // Host đã phân giải (ưu tiên effectiveBook.host -> self.host -> ext.sourceUrl)
    private var resolvedHost: String? {
        if let localHost = effectiveBook?.host, !localHost.isEmpty {
            return localHost
        }
        if !self.host.isEmpty {
            return self.host
        }
        return ext?.sourceUrl
    }

    private func cleanDetailText(_ html: String) -> String {
        return html.cleanHTML()
    }

    private var cleanedDetailText: String {
        cleanDetailText(detail)
    }

    private func translateMetaIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: actualBookId)
    }

    private func translateTitleIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: actualBookId)
    }

    private func translateChapterTitleIfNeeded(_ chap: Chapter) -> String {
        if isTranslationEnabled {
            if let trans = chap.titleTrans, !trans.isEmpty {
                return trans
            }
            if TranslateUtils.containsChinese(chap.title) {
                return TranslateUtils.translateChapterTitle(chap.title, bookId: actualBookId)
            }
        }
        return chap.title
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !detailErrorMessage.isEmpty && title.isEmpty {
                    errorView
                } else {
                    customTabBar

                    Divider()

                    TabView(selection: $selectedTab) {
                        detailTab
                            .tag(0)

                        tocTab
                            .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onChange(of: selectedTab) { oldVal, newVal in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            renderedTab = newVal
                        }
                    }
                }
            }
            .navigationTitle("Chi Tiết Truyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ellipsisMenu
                }
            }
            .onAppear {
                renderedTab = selectedTab
                loadBookData()
                syncChaptersList()
                updateFilteredLocalChapters()
                updateFilteredOnlineChapters()
            }
            .onDisappear {
                if readerRoute == nil {
                    progressiveTocTask?.cancel()
                    progressiveTocTask = nil
                }
                loadingTask?.cancel()
                loadingTask = nil
                bookOpenTask?.cancel()
                bookOpenTask = nil
                isLoadingRemainingPages = false
                progressiveLoadingPageText = ""
            }
            .onChange(of: totalChaptersCount) { _, _ in
                syncChaptersList()
            }
            .onChange(of: chaptersList) { _, _ in
                updateFilteredLocalChapters()
            }
            .onChange(of: onlineChapters) { _, _ in
                updateFilteredOnlineChapters()
            }
            .onChange(of: isTocAscending) { _, _ in
                updateFilteredLocalChapters()
                updateFilteredOnlineChapters()
            }
            .onChange(of: chapterSearchQuery) { _, _ in
                updateFilteredLocalChapters()
                updateFilteredOnlineChapters()
            }
            .onChange(of: isTranslationEnabled) { _, _ in
                updateFilteredLocalChapters()
                updateFilteredOnlineChapters()
            }
            .navigationDestination(item: $readerRoute) { route in
                LazyView {
                    ReaderView(
                        bookId: actualBookId,
                        extensionPackageId: extensionPackageId,
                        chapterIndex: route.chapterIndex,
                        onlineChapters: onlineChapters,
                        bookTitle: title,
                        bookAuthor: author,
                        bookCoverUrl: coverUrl,
                        bookDesc: desc.isEmpty ? nil : desc,
                        bookDetailUrl: initialDetailUrl,
                        bookSourceName: sourceName,
                        initialParagraphIndex: -1
                    )
                }
            }

            NavigationLink(
                destination: BookDictionaryView(bookId: actualBookId, bookName: title),
                isActive: $navigateToDictionary
            ) {
                EmptyView()
            }

            NavigationLink(
                destination: SearchView(
                    activeExtensions: Array(allExtensions),
                    selectedExtension: nil,
                    initialSearchQuery: title,
                    changeSourceTargetBook: effectiveBook,
                    onSourceChanged: {
                        dismiss()
                    }
                ),
                isActive: $navigateToChangeSource
            ) {
                EmptyView()
            }

            NavigationLink(
                destination: LazyView {
                    BookDetailView(
                        bookId: importedBookId,
                        extensionPackageId: importedExtensionPackageId,
                        initialDetailUrl: importedDetailUrl,
                        sourceName: importedSourceName,
                        initialHost: importedHost
                    )
                },
                isActive: $navigateToImportedBook
            ) {
                EmptyView()
            }

            if isLoadingRemainingPages {
                loadingOverlay
            }

            if isPreparingBook {
                preparingScreenOverlay
            }

            floatingActionButton
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(isPreparingBook ? .hidden : .visible, for: .navigationBar)
        .navigationBarBackButtonHidden(isPreparingBook)
        .sheet(item: $selectedBookForTask) { book in
            TaskOptionsSheet(book: book, taskType: selectedTaskType)
        }
        .fullScreenCover(isPresented: $showingBypassBrowser) {
            bypassBrowserContent
        }
    }

    @ViewBuilder
    private var errorView: some View {
        VStack(spacing: 16) {
            Text("Có lỗi xảy ra")
                .font(.headline)
            Text(detailErrorMessage)
                .font(.subheadline)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            Button("Thử lại") {
                loadBookDetailOnly()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var customTabBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 0
                }
            }) {
                VStack(spacing: 8) {
                    Text("Chi tiết")
                        .font(.subheadline)
                        .fontWeight(selectedTab == 0 ? .bold : .medium)
                        .foregroundColor(selectedTab == 0 ? .accentColor : .secondary)

                    Rectangle()
                        .fill(selectedTab == 0 ? Color.accentColor : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 1
                }
            }) {
                VStack(spacing: 8) {
                    Text("Mục lục")
                        .font(.subheadline)
                        .fontWeight(selectedTab == 1 ? .bold : .medium)
                        .foregroundColor(selectedTab == 1 ? .accentColor : .secondary)

                    Rectangle()
                        .fill(selectedTab == 1 ? Color.accentColor : Color.clear)
                        .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .padding(.top, 4)
    }

    @ViewBuilder
    private var detailTab: some View {
        ScrollView {
            if renderedTab == 0 {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoadingDetail && title.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 16) {
                                SkeletonView(width: 100, height: 140)

                                VStack(alignment: .leading, spacing: 10) {
                                    SkeletonView(width: 180, height: 22)
                                    SkeletonView(width: 120, height: 16)
                                    SkeletonView(width: 80, height: 16)
                                    Spacer()
                                }
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonView(width: 80, height: 18)
                                SkeletonView(width: nil, height: 14)
                                SkeletonView(width: nil, height: 14)
                                SkeletonView(width: 200, height: 14)
                            }
                        }
                        .padding(.horizontal)
                    } else if isLoadingDetail {
                        HStack {
                            Spacer()
                            ProgressView("Đang tải chi tiết truyện...")
                                .padding(.vertical, 30)
                            Spacer()
                        }
                    } else if !detailErrorMessage.isEmpty {
                        VStack(spacing: 12) {
                            Text(detailErrorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                            Button("Thử lại chi tiết") {
                                loadBookDetailOnly()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            BookCoverView(bookId: actualBookId, coverUrl: coverUrl, width: 100, height: 140)
                                .cornerRadius(8)
                                .shadow(radius: 2)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(DisplayTextFormatter.titleCase(translateMetaIfNeeded(title)))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(3)

                                let formattedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? ""
                                    : DisplayTextFormatter.titleCase(TranslateUtils.translateAuthorHanViet(author))
                                if !formattedAuthor.isEmpty {
                                    HStack(spacing: 5) {
                                        Image(systemName: "person.fill")
                                            .font(.caption)
                                        Text(formattedAuthor)
                                            .lineLimit(1)
                                    }
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                }

                                HStack(spacing: 6) {
                                    if let ext = ext {
                                        ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 16)
                                    } else {
                                        Image(systemName: "puzzlepiece.extension")
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(sourceName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }

                                if !detail.isEmpty {
                                    Text(translateMetaIfNeeded(cleanedDetailText))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(4)
                                }

                                if !genres.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(genres) { genre in
                                                NavigationLink(destination: CategoryNovelsListView(
                                                    category: genre,
                                                    extensionPackageId: extensionPackageId,
                                                    localPath: ext?.localPath ?? "",
                                                    downloadUrl: ext?.downloadUrl ?? "",
                                                    configJson: ext?.configJson ?? "{}",
                                                    sourceName: sourceName
                                                )) {
                                                    Text(TranslateUtils.translateMeta(genre.title))
                                                        .font(.caption2)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.blue.opacity(0.1))
                                                        .foregroundColor(.blue)
                                                        .cornerRadius(8)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Giới thiệu")
                                .font(.headline)
                            Text(translateMetaIfNeeded(desc))
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(isDescExpanded ? nil : 4)

                            if desc.count > 150 {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isDescExpanded.toggle()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Text(isDescExpanded ? "Thu gọn" : "Xem thêm")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Image(systemName: isDescExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.accentColor)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if isLoadingDetail && title.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonView(width: 120, height: 18)
                            HStack(spacing: 14) {
                                ForEach(0..<4) { _ in
                                    VStack(alignment: .leading, spacing: 6) {
                                        SkeletonView(width: 80, height: 110)
                                        SkeletonView(width: 80, height: 12)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else if !suggests.isEmpty {
                        Divider()
                        ForEach(suggests) { suggest in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(TranslateUtils.translateMeta(suggest.title))
                                        .font(.headline)
                                    Spacer()
                                    NavigationLink(destination: CategoryNovelsListView(
                                        category: suggest,
                                        extensionPackageId: extensionPackageId,
                                        localPath: ext?.localPath ?? "",
                                        downloadUrl: ext?.downloadUrl ?? "",
                                        configJson: ext?.configJson ?? "{}",
                                        sourceName: sourceName
                                    )) {
                                        HStack(spacing: 4) {
                                            Text("Xem thêm")
                                            Image(systemName: "chevron.right")
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal)

                                SuggestRowView(
                                    category: suggest,
                                    localPath: ext?.localPath ?? "",
                                    downloadUrl: ext?.downloadUrl ?? "",
                                    configJson: ext?.configJson ?? "{}",
                                    extensionPackageId: extensionPackageId,
                                    sourceName: sourceName
                                )
                            }
                        }
                    }

                    if isLoadingDetail && title.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonView(width: 100, height: 18)
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(0..<3) { _ in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            SkeletonView(width: 20, height: 20)
                                            SkeletonView(width: 100, height: 14)
                                        }
                                        SkeletonView(width: nil, height: 12)
                                            .padding(.leading, 28)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else if !comments.isEmpty {
                        Divider()
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(TranslateUtils.translateMeta(comment.title))
                                    .font(.headline)
                                    .padding(.horizontal)

                                CommentSectionView(
                                    category: comment,
                                    localPath: ext?.localPath ?? "",
                                    downloadUrl: ext?.downloadUrl ?? "",
                                    configJson: ext?.configJson ?? "{}",
                                    extensionPackageId: extensionPackageId,
                                    sourceName: sourceName
                                )
                            }
                        }
                    }
                }
                .padding(.vertical)
            } else {
                Spacer()
            }
        }
        .refreshable {
            await reloadBookData()
        }
    }

    @ViewBuilder
    private var tocTab: some View {
        VStack(spacing: 0) {
            if renderedTab == 1 {
                let totalChaps = max(totalChaptersCount, onlineChapters.count)

                if totalChaps > 0 {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Tìm kiếm chương...", text: $chapterSearchQuery)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if !remainingPagesLoaded && tocPages.count > 1 && !isLoadingTOC {
                                HStack(spacing: 6) {
                                    Text("Danh sách chương (\(totalChaps)...)")
                                        .font(.headline)
                                    ProgressView()
                                        .controlSize(.small)
                                    if !progressiveLoadingPageText.isEmpty {
                                        Text(progressiveLoadingPageText)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("Danh sách chương (\(totalChaps))")
                                    .font(.headline)
                            }

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isTocAscending.toggle()
                                }
                            }) {
                                Image(systemName: isTocAscending ? "arrow.down.circle" : "arrow.up.circle")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.leading, 4)

                            Spacer()
                            if totalChaps > 0 && !tocErrorMessage.isEmpty {
                                Button(action: loadTOCDataOnly) {
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
                                ProgressView("Đang tải danh sách chương...")
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
                                        loadTOCDataOnly()
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
                                if let book = effectiveBook, !filteredLocalChapters.isEmpty {
                                    ForEach(filteredLocalChapters) { chap in
                                        Button(action: {
                                            startReading(at: chap.index)
                                        }) {
                                            HStack {
                                                Text(translateChapterTitleIfNeeded(chap))
                                                    .foregroundColor(book.currentChapterIndex == chap.index ? .accentColor : .primary)
                                                    .font(.subheadline)
                                                    .lineLimit(1)
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
                                    ForEach(filteredOnlineChapters, id: \.offset) { index, chap in
                                        Button(action: {
                                            startReading(at: index)
                                        }) {
                                            VStack(alignment: .leading) {
                                                Text(translateTitleIfNeeded(chap.name))
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                    .padding(.vertical, 12)
                                                    .padding(.horizontal)
                                                Divider()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if tocPages.count > 1 && !remainingPagesLoaded {
                                    Button(action: loadMoreChapters) {
                                        HStack {
                                            Spacer()
                                            Text("Tải thêm chương (còn \(tocPages.count - 1) trang)")
                                                .fontWeight(.semibold)
                                            Spacer()
                                        }
                                        .padding()
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                        .padding(.top, 10)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            } else {
                Spacer()
            }
        }
        .refreshable {
            await reloadBookData()
        }
    }

    @ViewBuilder
    private var ellipsisMenu: some View {
        Menu {
            Button(action: {
                isTranslationEnabled.toggle()
            }) {
                Label(
                    isTranslationEnabled ? "Tắt dịch" : "Bật dịch",
                    systemImage: isTranslationEnabled ? "character.bubble.fill" : "character.bubble"
                )
            }

            if effectiveBook != nil {
                Button(action: {
                    navigateToDictionary = true
                }) {
                    Label("Từ điển", systemImage: "character.book.closed")
                }
            }

            Button(action: {
                if effectiveBook == nil {
                    bookOpenTask?.cancel()
                    bookOpenTask = Task { @MainActor in
                        isPreparingBook = true
                        preparingStatusText = "Đang lưu dữ liệu..."
                        await Task.yield()
                        if Task.isCancelled {
                            isPreparingBook = false
                            bookOpenTask = nil
                            return
                        }
                        let result = await persistBookToSQLiteAsync(isOnShelf: false)
                        isPreparingBook = false
                        bookOpenTask = nil
                        if result != nil {
                            navigateToChangeSource = true
                        } else if !Task.isCancelled {
                            tocErrorMessage = "Không thể lưu thông tin sách!"
                        }
                    }
                } else {
                    navigateToChangeSource = true
                }
            }) {
                Label("Thay đổi nguồn", systemImage: "arrow.2.squarepath")
            }

            Button(action: {
                showingBypassBrowser = true
            }) {
                Label("Mở bằng trình duyệt", systemImage: "safari")
            }

            Button(action: {
                // Chưa làm chức năng
            }) {
                Label("Chia sẻ", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                Text("Đang tải danh sách chương...")
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Button(action: {
                    loadingTask?.cancel()
                    loadingTask = nil
                    progressiveTocTask?.cancel()
                    progressiveTocTask = nil
                    isLoadingRemainingPages = false
                    progressiveLoadingPageText = ""
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text("Quay lại")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color.black.opacity(0.75))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var preparingScreenOverlay: some View {
        ZStack(alignment: .topLeading) {
            readerTheme.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ProgressView()
                    .tint(readerTheme.textColor)
                    .scaleEffect(1.4)

                VStack(spacing: 8) {
                    let displayBookTitle = isTranslationEnabled && TranslateUtils.containsChinese(title)
                        ? TranslateUtils.translateMeta(title, bookId: actualBookId)
                        : title
                    Text(DisplayTextFormatter.titleCase(displayBookTitle))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(readerTheme.textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if !preparingTargetChapterTitle.isEmpty {
                        Text(preparingTargetChapterTitle)
                            .font(.headline)
                            .foregroundColor(readerTheme.textColor.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 24)

                Text(preparingStatusText)
                    .font(.subheadline)
                    .foregroundColor(readerTheme.textColor.opacity(0.6))
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Top-left chevron back icon button (No header bar, no bottom toolbar)
            Button(action: cancelPreparingBook) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerTheme.textColor)
                    .padding(12)
                    .background(Circle().fill(readerTheme.textColor.opacity(0.12)))
            }
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("Quay lại")
        }
        .transition(.opacity)
        .zIndex(100)
    }

    private func cancelPreparingBook() {
        bookOpenTask?.cancel()
        bookOpenTask = nil
        if modelContext.hasChanges {
            modelContext.rollback()
        }
        isPreparingBook = false
        readerRoute = nil
    }

    @ViewBuilder
    private var floatingActionButton: some View {
        let totalChaps = max(totalChaptersCount, onlineChapters.count)
        if totalChaps > 0 {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        if isMenuExpanded {
                            let activeChapterIndex = effectiveBook?.currentChapterIndex ?? 0
                            Button(action: {
                                isMenuExpanded = false
                                startReading(at: activeChapterIndex)
                            }) {
                                HStack {
                                    Text(effectiveBook == nil ? "Đọc ngay" : "Đọc tiếp")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: effectiveBook == nil ? "play.fill" : "book.fill")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 3)
                            }
                            .transition(.scale.combined(with: .opacity))

                            Button(action: {
                                isMenuExpanded = false
                                if let book = effectiveBook, book.isOnShelf {
                                    removeFromShelf(book)
                                } else {
                                    addToShelf()
                                }
                            }) {
                                HStack {
                                    Text(effectiveBook?.isOnShelf == true ? "Đã ở kệ" : "Thêm vào kệ")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: effectiveBook?.isOnShelf == true ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(effectiveBook?.isOnShelf == true ? Color.green : Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 3)
                            }
                            .transition(.scale.combined(with: .opacity))

                            Button(action: {
                                isMenuExpanded = false
                                prepareForTask(taskType: .download)
                            }) {
                                HStack {
                                    Text("Tải truyện")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: "arrow.down.circle.fill")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 3)
                            }
                            .transition(.scale.combined(with: .opacity))

                            Button(action: {
                                isMenuExpanded = false
                                prepareForTask(taskType: .exportTxt)
                            }) {
                                HStack {
                                    Text("Xuất TXT")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: "square.and.arrow.up.fill")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 3)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isMenuExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "plus")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 5)
                                .rotationEffect(.degrees(isMenuExpanded ? 135 : 0))
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    @ViewBuilder
    private var bypassBrowserContent: some View {
        BypassWebView(
            urlString: initialDetailUrl,
            host: resolvedHost,
            onImport: { detailUrl, packageId, sourceName in
                let checkUrl = JSExecutor.cleanAndResolveUrl(detailUrl, host: ext?.sourceUrl)
                let currentResolved = JSExecutor.cleanAndResolveUrl(initialDetailUrl, host: ext?.sourceUrl)

                if checkUrl == currentResolved {
                    loadBookData()
                } else {
                    importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                    importedExtensionPackageId = packageId
                    importedDetailUrl = detailUrl
                    importedSourceName = sourceName

                    if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                        importedHost = "\(scheme)://\(host)"
                    } else {
                        importedHost = ""
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        navigateToImportedBook = true
                    }
                }
            }
        )
    }

    private func resolveBookId() {
        if let book = effectiveBook {
            resolvedBookId = book.bookId
        } else {
            if bookId.contains("-") && bookId.count > 30 {
                resolvedBookId = bookId
            } else {
                resolvedBookId = UUID().uuidString
            }
        }
    }

    private func loadBookData() {
        resolveBookId()
        // Nếu sách đã ở local, gán dữ liệu từ local để hiển thị ngay
        if let book = effectiveBook {
            self.title = book.title
            self.author = book.author
            self.coverUrl = book.coverUrl
            self.desc = book.desc
            self.syncChaptersList()
            self.updateFilteredLocalChapters()
            if totalChaptersCount > 0 {
                self.remainingPagesLoaded = true
                self.isLoadingDetail = false
                self.isLoadingTOC = false
                return
            }
        }

        isLoadingDetail = true
        isLoadingTOC = true
        detailErrorMessage = ""
        tocErrorMessage = ""

        loadBookDetailOnly()
        loadTOCDataOnly()
    }

    private func loadBookDetailOnly() {
        guard let ext = ext else {
            detailErrorMessage = "Không tìm thấy tiện ích bóc tách của truyện này!"
            self.isLoadingDetail = false
            return
        }

        guard !ext.localPath.isEmpty else {
            detailErrorMessage = "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!"
            self.isLoadingDetail = false
            return
        }

        isLoadingDetail = true
        detailErrorMessage = ""

        Task {
            do {
                let path = ext.localPath
                let detailResult = try await ExtensionManager.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)

                await MainActor.run {
                    self.title = detailResult.name
                    self.author = detailResult.author
                    self.coverUrl = detailResult.cover
                    self.desc = detailResult.description.cleanHTML()
                    self.detail = detailResult.detail
                    self.genres = detailResult.genres
                    self.suggests = detailResult.suggests
                    self.comments = detailResult.comments
                    self.host = detailResult.host

                    if let book = effectiveBook {
                        book.title = detailResult.name
                        book.author = detailResult.author
                        book.coverUrl = detailResult.cover
                        let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                        book.desc = savedDesc
                        book.host = detailResult.host
                        try? modelContext.save()
                    }
                    self.isLoadingDetail = false
                }
            } catch {
                await MainActor.run {
                    self.detailErrorMessage = error.localizedDescription
                    self.isLoadingDetail = false
                }
            }
        }
    }

    private func loadTOCDataOnly() {
        guard let ext = ext else {
            tocErrorMessage = "Không tìm thấy tiện ích bóc tách!"
            self.isLoadingTOC = false
            return
        }

        guard !ext.localPath.isEmpty else {
            tocErrorMessage = "Vui lòng cài đặt tiện ích '\(ext.name)'!"
            self.isLoadingTOC = false
            return
        }

        progressiveTocTask?.cancel()
        progressiveTocTask = nil
        loadedPageUrls.removeAll()
        remainingPagesLoaded = false
        isLoadingTOC = true
        tocErrorMessage = ""

        Task {
            do {
                let path = ext.localPath
                var firstPageChapters: [ChapterResult] = []
                var pages: [String] = []

                if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                    pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                    if !pages.isEmpty {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pages[0], host: resolvedHost, configJson: ext.configJson)
                        _ = await MainActor.run { self.loadedPageUrls.insert(pages[0]) }
                    } else {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        _ = await MainActor.run { self.loadedPageUrls.insert(initialDetailUrl) }
                    }
                } else {
                    firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                    _ = await MainActor.run { self.loadedPageUrls.insert(initialDetailUrl) }
                }

                await MainActor.run {
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages

                    if let targetBook = self.effectiveBook {
                        self.updateFirstPageChapters(for: targetBook, with: firstPageChapters)
                        try? self.modelContext.save()
                        self.syncChaptersList()
                        self.isLoadingTOC = false

                        if pages.count > 1 {
                            self.remainingPagesLoaded = false
                            self.startProgressiveTOCLoading(for: targetBook, pages: pages)
                        } else {
                            self.remainingPagesLoaded = true
                        }
                    } else {
                        self.isLoadingTOC = false
                        if pages.count > 1 {
                            self.remainingPagesLoaded = false
                            self.startProgressiveTOCLoading(for: nil, pages: pages)
                        } else {
                            self.remainingPagesLoaded = true
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.tocErrorMessage = error.localizedDescription
                    self.isLoadingTOC = false
                }
            }
        }
    }
    private func makeSafeChapterId(
        bookId: String,
        url: String,
        index: Int,
        seenIds: inout Set<String>
    ) -> String {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvalidUrl = trimmedUrl.isEmpty ||
                           trimmedUrl == "#" ||
                           trimmedUrl.lowercased().hasPrefix("javascript:") ||
                           trimmedUrl.lowercased().hasPrefix("about:blank")

        let candidateId: String
        if isInvalidUrl {
            candidateId = "\(bookId.count):\(bookId)|I:\(index)"
        } else {
            candidateId = Chapter.generateId(bookId: bookId, url: trimmedUrl, index: index)
        }

        if seenIds.contains(candidateId) {
            let fallbackId = "\(bookId.count):\(bookId)|I:\(index)"
            seenIds.insert(fallbackId)
            return fallbackId
        } else {
            seenIds.insert(candidateId)
            return candidateId
        }
    }

    private func cleanupPersistenceFailure(isNewBook: Bool, book: Book?) {
        if isNewBook, let book = book {
            modelContext.delete(book)
            try? modelContext.save()
            createdBookInstance = nil
        } else {
            if modelContext.hasChanges {
                modelContext.rollback()
            }
        }
    }

    @discardableResult
    private func persistBookToSQLiteAsync(isOnShelf: Bool = false, initialChapterIndex: Int = 0) async -> Book? {
        if let existing = effectiveBook {
            if isOnShelf && !existing.isOnShelf {
                existing.isOnShelf = true
                try? modelContext.save()
            }
            return existing
        }

        let isNewBook = (createdBookInstance == nil && localBook == nil)
        let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
        let initialChapterTitle: String
        if initialChapterIndex >= 0 && initialChapterIndex < onlineChapters.count {
            initialChapterTitle = onlineChapters[initialChapterIndex].name
        } else {
            initialChapterTitle = onlineChapters.first?.name ?? ""
        }

        let effectiveHost = !host.isEmpty ? host : resolvedHost
        let newBook = Book(
            bookId: resolvedBookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: initialDetailUrl,
            sourceName: sourceName,
            sourceUrl: ext?.sourceUrl ?? "",
            extensionPackageId: extensionPackageId,
            currentChapterIndex: initialChapterIndex,
            currentChapterTitle: initialChapterTitle,
            isOnShelf: isOnShelf,
            isHistory: false,
            host: effectiveHost
        )
        modelContext.insert(newBook)
        createdBookInstance = newBook

        let totalOnline = onlineChapters.count
        if totalOnline == 0 {
            do {
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .bookChaptersUpdated,
                    object: nil,
                    userInfo: ["bookId": newBook.bookId]
                )
                syncChaptersList()
                return newBook
            } catch {
                cleanupPersistenceFailure(isNewBook: isNewBook, book: newBook)
                return nil
            }
        }

        let batchSize = 500
        var startIndex = 0
        while startIndex < totalOnline {
            if Task.isCancelled {
                cleanupPersistenceFailure(isNewBook: isNewBook, book: newBook)
                return nil
            }

            let endIndex = min(startIndex + batchSize, totalOnline)
            let batchResults = Array(onlineChapters[startIndex..<endIndex])

            if startIndex == 0 {
                updateFirstPageChapters(for: newBook, with: batchResults)
            } else {
                appendOrUpsertChapters(for: newBook, newResults: batchResults, baseIndex: startIndex)
            }

            do {
                try modelContext.save()
                NotificationCenter.default.post(
                    name: .bookChaptersUpdated,
                    object: nil,
                    userInfo: ["bookId": newBook.bookId]
                )
            } catch {
                cleanupPersistenceFailure(isNewBook: isNewBook, book: newBook)
                return nil
            }

            startIndex = endIndex
            await Task.yield()
        }

        syncChaptersList()
        return newBook
    }

    @discardableResult
    private func persistBookToSQLite(isOnShelf: Bool = false, initialChapterIndex: Int = 0) -> Book? {
        if let existing = effectiveBook {
            if isOnShelf && !existing.isOnShelf {
                existing.isOnShelf = true
                try? modelContext.save()
            }
            return existing
        }

        let isNewBook = (createdBookInstance == nil && localBook == nil)
        let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
        let initialChapterTitle: String
        if initialChapterIndex >= 0 && initialChapterIndex < onlineChapters.count {
            initialChapterTitle = onlineChapters[initialChapterIndex].name
        } else {
            initialChapterTitle = onlineChapters.first?.name ?? ""
        }

        let effectiveHost = !host.isEmpty ? host : resolvedHost
        let newBook = Book(
            bookId: resolvedBookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: initialDetailUrl,
            sourceName: sourceName,
            sourceUrl: ext?.sourceUrl ?? "",
            extensionPackageId: extensionPackageId,
            currentChapterIndex: initialChapterIndex,
            currentChapterTitle: initialChapterTitle,
            isOnShelf: isOnShelf,
            isHistory: false,
            host: effectiveHost
        )
        modelContext.insert(newBook)
        createdBookInstance = newBook

        updateFirstPageChapters(for: newBook, with: onlineChapters)

        do {
            try modelContext.save()
            NotificationCenter.default.post(
                name: .bookChaptersUpdated,
                object: nil,
                userInfo: ["bookId": newBook.bookId]
            )
        } catch {
            cleanupPersistenceFailure(isNewBook: isNewBook, book: newBook)
            return nil
        }

        syncChaptersList()
        return newBook
    }

    private func isValidChapterUrl(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        return lower != "#" && !lower.hasPrefix("javascript:") && !lower.hasPrefix("about:")
    }

    private func updateFirstPageChapters(for book: Book, with firstPageResults: [ChapterResult]) {
        let defaultHost = book.host ?? resolvedHost
        let targetBookId = book.bookId

        let models = firstPageResults.enumerated().map { index, item in
            let effectiveHost = !item.host.isEmpty ? item.host : defaultHost
            return ChapterModel(
                bookId: targetBookId,
                index: index,
                title: item.name,
                url: item.url,
                host: effectiveHost
            )
        }

        Task {
            try? await chapterRepository.bulkUpsert(bookId: targetBookId, chapters: models)
            await MainActor.run { self.syncChaptersList() }
        }

        if (book.host == nil || book.host?.isEmpty == true) {
            if let firstHost = firstPageResults.first?.host, !firstHost.isEmpty {
                book.host = firstHost
            } else if let fallback = resolvedHost, !fallback.isEmpty {
                book.host = fallback
            }
        }
    }

    private func appendOrUpsertChapters(for book: Book, newResults: [ChapterResult], baseIndex: Int) {
        let defaultHost = book.host ?? resolvedHost
        let targetBookId = book.bookId

        let models = newResults.enumerated().map { offset, item in
            let targetIndex = baseIndex + offset
            let effectiveHost = !item.host.isEmpty ? item.host : defaultHost
            return ChapterModel(
                bookId: targetBookId,
                index: targetIndex,
                title: item.name,
                url: item.url,
                host: effectiveHost
            )
        }

        Task {
            try? await chapterRepository.bulkUpsert(bookId: targetBookId, chapters: models)
            await MainActor.run { self.syncChaptersList() }
        }
    }

    private func startProgressiveTOCLoading(for book: Book?, pages: [String]) {
        progressiveTocTask?.cancel()
        tocErrorMessage = ""

        guard pages.count > 1 else {
            remainingPagesLoaded = true
            progressiveLoadingPageText = ""
            return
        }
        let remainingPages = pages.filter { !loadedPageUrls.contains($0) }
        let totalPages = pages.count

        progressiveTocTask = Task {
            var encounteredError = false
            var pendingPageCount = 0
            for (pageIdx, pageUrl) in remainingPages.enumerated() {
                if Task.isCancelled { break }
                let currentPageNum = pageIdx + 2
                await MainActor.run {
                    self.progressiveLoadingPageText = "Đang nạp trang \(currentPageNum)/\(totalPages)..."
                }

                guard let ext = self.ext else {
                    encounteredError = true
                    await MainActor.run {
                        self.tocErrorMessage = "Không tìm thấy tiện ích bóc tách!"
                    }
                    break
                }

                do {
                    let pageChaps = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: pageUrl,
                        host: self.resolvedHost,
                        configJson: ext.configJson
                    )
                    try Task.checkCancellation()

                    await MainActor.run {
                        self.loadedPageUrls.insert(pageUrl)
                        let pageBaseIndex = self.onlineChapters.count
                        self.onlineChapters.append(contentsOf: pageChaps)
                        if let targetBook = book ?? self.effectiveBook {
                            self.appendOrUpsertChapters(for: targetBook, newResults: pageChaps, baseIndex: pageBaseIndex)
                        }
                    }

                    pendingPageCount += 1
                    let isLastPage = (pageIdx == remainingPages.count - 1)
                    if pendingPageCount >= 10 || isLastPage {
                        await MainActor.run {
                            if let targetBook = book ?? self.effectiveBook {
                                try? self.modelContext.save()
                                NotificationCenter.default.post(
                                    name: .bookChaptersUpdated,
                                    object: nil,
                                    userInfo: ["bookId": targetBook.bookId]
                                )
                            }
                            if self.selectedTab == 1 {
                                self.updateFilteredLocalChapters()
                                self.updateFilteredOnlineChapters()
                            }
                        }
                        pendingPageCount = 0
                    }
                    await Task.yield()
                } catch {
                    if Task.isCancelled {
                        break
                    }
                    encounteredError = true
                    let errorMsg = error.localizedDescription
                    await MainActor.run {
                        self.tocErrorMessage = "Lỗi tải trang \(currentPageNum): \(errorMsg)"
                    }
                    break
                }
            }

            await MainActor.run {
                if pendingPageCount > 0 {
                    if let targetBook = book ?? self.effectiveBook {
                        try? self.modelContext.save()
                        NotificationCenter.default.post(
                            name: .bookChaptersUpdated,
                            object: nil,
                            userInfo: ["bookId": targetBook.bookId]
                        )
                    }
                }
                self.updateFilteredLocalChapters()
                self.updateFilteredOnlineChapters()
                self.progressiveLoadingPageText = ""
                if !Task.isCancelled {
                    if !encounteredError {
                        self.remainingPagesLoaded = true
                    }
                    self.progressiveTocTask = nil
                }
            }
        }
    }

    @discardableResult
    private func ensureChaptersLoadedUpTo(targetIndex: Int, for book: Book?) async -> Bool {
        if onlineChapters.count > targetIndex || remainingPagesLoaded || tocPages.count <= 1 {
            return true
        }
        if let activeTask = progressiveTocTask {
            activeTask.cancel()
            _ = await activeTask.value
            progressiveTocTask = nil
        }

        let remainingPages = tocPages.filter { !loadedPageUrls.contains($0) }
        guard let ext = self.ext, !ext.localPath.isEmpty else { return false }

        var pendingPageCount = 0
        for pageUrl in remainingPages {
            if Task.isCancelled { break }
            if onlineChapters.count > targetIndex { break }

            do {
                let pageChaps = try await ExtensionManager.shared.toc(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    url: pageUrl,
                    host: self.resolvedHost,
                    configJson: ext.configJson
                )
                try Task.checkCancellation()

                loadedPageUrls.insert(pageUrl)
                let pageBaseIndex = onlineChapters.count
                onlineChapters.append(contentsOf: pageChaps)
                if let targetBook = book ?? self.effectiveBook {
                    appendOrUpsertChapters(for: targetBook, newResults: pageChaps, baseIndex: pageBaseIndex)
                }

                pendingPageCount += 1
                let targetReached = (onlineChapters.count > targetIndex)
                if pendingPageCount >= 10 || targetReached {
                    if let targetBook = book ?? self.effectiveBook {
                        try? modelContext.save()
                        NotificationCenter.default.post(
                            name: .bookChaptersUpdated,
                            object: nil,
                            userInfo: ["bookId": targetBook.bookId]
                        )
                    }
                    if selectedTab == 1 {
                        updateFilteredLocalChapters()
                        updateFilteredOnlineChapters()
                    }
                    pendingPageCount = 0
                }
                await Task.yield()
            } catch {
                if Task.isCancelled { break }
                return false
            }
        }

        if pendingPageCount > 0 {
            if let targetBook = book ?? self.effectiveBook {
                try? modelContext.save()
                NotificationCenter.default.post(
                    name: .bookChaptersUpdated,
                    object: nil,
                    userInfo: ["bookId": targetBook.bookId]
                )
            }
        }
        updateFilteredLocalChapters()
        updateFilteredOnlineChapters()

        if loadedPageUrls.count >= tocPages.count {
            remainingPagesLoaded = true
        }
        return onlineChapters.count > targetIndex || remainingPagesLoaded
    }

    @discardableResult
    private func ensureAllRemainingPagesLoaded(for book: Book?) async -> Bool {
        return await ensureChaptersLoadedUpTo(targetIndex: Int.max - 1, for: book)
    }

    private func addToShelf() {
        if let book = effectiveBook {
            book.isOnShelf = true
            let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
            if !savedDesc.isEmpty {
                book.desc = savedDesc
            }
            try? modelContext.save()
        } else {
            bookOpenTask?.cancel()
            bookOpenTask = Task { @MainActor in
                isPreparingBook = true
                preparingStatusText = "Đang lưu dữ liệu..."
                await Task.yield()
                if Task.isCancelled {
                    isPreparingBook = false
                    bookOpenTask = nil
                    return
                }
                let result = await persistBookToSQLiteAsync(isOnShelf: true)
                isPreparingBook = false
                bookOpenTask = nil
                if result == nil && !Task.isCancelled {
                    tocErrorMessage = "Không thể thêm sách vào kệ!"
                }
            }
        }
    }

    private func loadMoreChapters() {
        guard progressiveTocTask == nil && !isLoadingRemainingPages else { return }
        if let book = effectiveBook, tocPages.count > 1 && !remainingPagesLoaded {
            startProgressiveTOCLoading(for: book, pages: tocPages)
        }
    }

    private func startReading(at chapterIndex: Int) {
        let loadedCount = max(totalChaptersCount, onlineChapters.count)
        let isChapterAvailable = (chapterIndex >= 0 && chapterIndex < loadedCount)

        if isChapterAvailable {
            bookOpenTask?.cancel()
            bookOpenTask = Task { @MainActor in
                let targetBook: Book?
                if effectiveBook == nil {
                    isPreparingBook = true
                    preparingStatusText = "Đang lưu dữ liệu..."
                    await Task.yield()
                    if Task.isCancelled {
                        isPreparingBook = false
                        bookOpenTask = nil
                        return
                    }
                    guard let newBook = await persistBookToSQLiteAsync(isOnShelf: false, initialChapterIndex: chapterIndex) else {
                        isPreparingBook = false
                        bookOpenTask = nil
                        if !Task.isCancelled {
                            self.tocErrorMessage = "Không thể lưu thông tin sách!"
                        }
                        return
                    }
                    targetBook = newBook
                    isPreparingBook = false
                } else {
                    targetBook = effectiveBook
                    if let book = targetBook {
                        book.currentChapterIndex = chapterIndex
                        let targetBookId = book.bookId
                        Task {
                            if let chap = try? await chapterRepository.getChapter(bookId: targetBookId, index: chapterIndex) {
                                await MainActor.run {
                                    book.currentChapterTitle = chap.title
                                    try? modelContext.save()
                                }
                            }
                        }
                    }
                }
                if Task.isCancelled {
                    bookOpenTask = nil
                    return
                }
                if tocPages.count > 1 && !remainingPagesLoaded && progressiveTocTask == nil {
                    startProgressiveTOCLoading(for: targetBook, pages: tocPages)
                }
                bookOpenTask = nil
                self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
            }
            return
        }

        isPreparingBook = true
        preparingStatusText = "Đang tải danh sách chương..."

        let rawTargetTitle: String
        if chapterIndex >= 0 && chapterIndex < onlineChapters.count {
            rawTargetTitle = onlineChapters[chapterIndex].name
        } else if chapterIndex >= 0 && chapterIndex < chaptersList.count {
            rawTargetTitle = chaptersList[chapterIndex].title
        } else {
            rawTargetTitle = "Chương \(chapterIndex + 1)"
        }

        preparingTargetChapterTitle = isTranslationEnabled && TranslateUtils.containsChinese(rawTargetTitle)
            ? TranslateUtils.translateChapterTitle(rawTargetTitle, bookId: actualBookId)
            : rawTargetTitle

        bookOpenTask?.cancel()
        bookOpenTask = Task { @MainActor in
            let isNewBook = (createdBookInstance == nil && localBook == nil)
            var createdNewBook: Book? = nil
            do {
                if onlineChapters.isEmpty && effectiveBook == nil {
                    guard let ext = ext, !ext.localPath.isEmpty else {
                        throw NSError(domain: "BookError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tiện ích bóc tách!"])
                    }
                    let path = ext.localPath
                    var firstPageChapters: [ChapterResult] = []
                    var pages: [String] = []

                    if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                        pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        if !pages.isEmpty {
                            firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pages[0], host: resolvedHost, configJson: ext.configJson)
                            loadedPageUrls.insert(pages[0])
                        } else {
                            firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                            loadedPageUrls.insert(initialDetailUrl)
                        }
                    } else {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        loadedPageUrls.insert(initialDetailUrl)
                    }

                    try Task.checkCancellation()
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages
                }

                let targetBook: Book
                if let existing = effectiveBook {
                    targetBook = existing
                } else {
                    preparingStatusText = "Đang lưu dữ liệu..."
                    await Task.yield()
                    try Task.checkCancellation()
                    guard let newBook = await persistBookToSQLiteAsync(isOnShelf: false, initialChapterIndex: chapterIndex) else {
                        throw NSError(domain: "BookError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể tạo sách!"])
                    }
                    createdNewBook = newBook
                    targetBook = newBook
                }

                if tocPages.count > 1 && !remainingPagesLoaded {
                    preparingStatusText = "Đang tải các trang chương tiếp theo..."
                    let success = await ensureChaptersLoadedUpTo(targetIndex: chapterIndex, for: targetBook)
                    try Task.checkCancellation()
                    if !success {
                        throw NSError(domain: "BookError", code: 2, userInfo: [NSLocalizedDescriptionKey: tocErrorMessage.isEmpty ? "Lỗi tải các trang chương!" : tocErrorMessage])
                    }
                }

                preparingStatusText = "Đang lưu dữ liệu..."
                try Task.checkCancellation()

                do {
                    try modelContext.save()
                    NotificationCenter.default.post(
                        name: .bookChaptersUpdated,
                        object: nil,
                        userInfo: ["bookId": targetBook.bookId]
                    )
                } catch {
                    cleanupPersistenceFailure(isNewBook: isNewBook, book: targetBook)
                    throw error
                }

                syncChaptersList()
                try Task.checkCancellation()

                isPreparingBook = false
                bookOpenTask = nil
                self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
            } catch {
                cleanupPersistenceFailure(isNewBook: isNewBook, book: createdNewBook ?? effectiveBook)
                isPreparingBook = false
                bookOpenTask = nil
                readerRoute = nil
                if !Task.isCancelled {
                    self.tocErrorMessage = "Lỗi chuẩn bị sách: \(error.localizedDescription)"
                }
            }
        }
    }

    private func prepareForTask(taskType: TaskType) {
        loadingTask?.cancel()
        loadingTask = Task { @MainActor in
            isLoadingRemainingPages = true
            tocErrorMessage = ""
            await Task.yield()
            if Task.isCancelled {
                isLoadingRemainingPages = false
                loadingTask = nil
                return
            }

            let book: Book
            if let existing = self.effectiveBook {
                book = existing
            } else {
                guard let newBook = await self.persistBookToSQLiteAsync(isOnShelf: false) else {
                    self.isLoadingRemainingPages = false
                    self.loadingTask = nil
                    if !Task.isCancelled {
                        self.tocErrorMessage = "Không thể chuẩn bị thông tin sách!"
                    }
                    return
                }
                book = newBook
            }

            if Task.isCancelled {
                self.isLoadingRemainingPages = false
                self.loadingTask = nil
                return
            }

            if self.tocPages.count > 1 && !self.remainingPagesLoaded {
                let success = await self.ensureAllRemainingPagesLoaded(for: book)
                self.isLoadingRemainingPages = false
                self.loadingTask = nil
                if success && !Task.isCancelled {
                    self.selectedTaskType = taskType
                    self.selectedBookForTask = book
                }
            } else {
                self.isLoadingRemainingPages = false
                self.loadingTask = nil
                if !Task.isCancelled {
                    self.selectedTaskType = taskType
                    self.selectedBookForTask = book
                }
            }
        }
    }

    private func removeFromShelf(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        Task { @MainActor in
            do {
                try await bookStorageManager.deleteBookAsync(bookId: bookId, container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa khỏi kệ sách tại BookDetailView: \(error.localizedDescription)")
            }
        }
    }

    private func syncChaptersList() {
        if let targetBookId = effectiveBook?.bookId {
            Task {
                let items = (try? await chapterRepository.loadPageKeyset(bookId: targetBookId, startIdx: 0, limit: 100000)) ?? []
                await MainActor.run {
                    self.chaptersList = items
                    self.totalChaptersCount = items.count
                    self.updateFilteredLocalChapters()
                    self.updateFilteredOnlineChapters()
                }
            }
        } else {
            chaptersList = []
            totalChaptersCount = 0
            updateFilteredLocalChapters()
            updateFilteredOnlineChapters()
        }
    }

    private func updateFilteredLocalChapters() {
        let sorted = chaptersList.sorted(by: { isTocAscending ? ($0.index < $1.index) : ($0.index > $1.index) })
        filteredLocalChapters = sorted.filter { chap in
            chapterSearchQuery.isEmpty ||
            chap.title.localizedCaseInsensitiveContains(chapterSearchQuery) ||
            translateChapterTitleIfNeeded(chap).localizedCaseInsensitiveContains(chapterSearchQuery)
        }
    }

    private func updateFilteredOnlineChapters() {
        let enumeratedChaps = Array(onlineChapters.enumerated())
        let sortedOnline = isTocAscending ? enumeratedChaps : Array(enumeratedChaps.reversed())
        filteredOnlineChapters = sortedOnline.filter { index, chap in
            chapterSearchQuery.isEmpty ||
            chap.name.localizedCaseInsensitiveContains(chapterSearchQuery) ||
            TranslateUtils.translateChapterTitle(chap.name, bookId: actualBookId).localizedCaseInsensitiveContains(chapterSearchQuery)
        }
    }

    private func reloadBookData() async {
        guard let ext = ext else { return }
        guard !ext.localPath.isEmpty else { return }

        await MainActor.run {
            self.progressiveTocTask?.cancel()
            self.progressiveTocTask = nil
            self.loadedPageUrls.removeAll()
            self.remainingPagesLoaded = false
            self.detailErrorMessage = ""
            self.tocErrorMessage = ""
        }

        let bookHost = resolvedHost
        async let detailTask = ExtensionManager.shared.detail(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: bookHost, configJson: ext.configJson)

        do {
            let detailResult = try await detailTask
            await MainActor.run {
                self.title = detailResult.name
                self.author = detailResult.author
                self.coverUrl = detailResult.cover
                self.desc = detailResult.description.cleanHTML()
                self.detail = detailResult.detail
                self.genres = detailResult.genres
                self.suggests = detailResult.suggests
                self.comments = detailResult.comments
                self.host = detailResult.host

                if let book = effectiveBook {
                    book.title = detailResult.name
                    book.author = detailResult.author
                    book.coverUrl = detailResult.cover
                    let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                    book.desc = savedDesc
                    book.host = detailResult.host
                    try? modelContext.save()
                }
            }
        } catch {
            await MainActor.run {
                self.detailErrorMessage = "Lỗi tải chi tiết: \(error.localizedDescription)"
            }
        }

        do {
            let path = ext.localPath
            var firstPageChapters: [ChapterResult] = []
            var pages: [String] = []

            if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                if !pages.isEmpty {
                    firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pages[0], host: resolvedHost, configJson: ext.configJson)
                    _ = await MainActor.run { self.loadedPageUrls.insert(pages[0]) }
                } else {
                    firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                    _ = await MainActor.run { self.loadedPageUrls.insert(initialDetailUrl) }
                }
            } else {
                firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: effectiveBook?.host, configJson: ext.configJson)
                _ = await MainActor.run { self.loadedPageUrls.insert(initialDetailUrl) }
            }

            await MainActor.run {
                self.onlineChapters = firstPageChapters
                self.tocPages = pages
                if let book = effectiveBook {
                    updateFirstPageChapters(for: book, with: firstPageChapters)
                    try? modelContext.save()
                    NotificationCenter.default.post(
                        name: .bookChaptersUpdated,
                        object: nil,
                        userInfo: ["bookId": book.bookId]
                    )
                }
                if pages.count > 1 {
                    self.remainingPagesLoaded = false
                    self.startProgressiveTOCLoading(for: effectiveBook, pages: pages)
                } else {
                    self.remainingPagesLoaded = true
                }
            }
        } catch {
            await MainActor.run {
                self.tocErrorMessage = "Lỗi tải mục lục: \(error.localizedDescription)"
            }
        }
    }
}
