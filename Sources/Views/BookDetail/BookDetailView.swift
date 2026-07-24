import SwiftUI
import SwiftData

struct ReaderRoute: Identifiable, Hashable {
    let chapterIndex: Int
    var id: Int { chapterIndex }
}

struct BookDetailView: View {
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

    private var actualBookId: String {
        resolvedBookId.isEmpty ? bookId : resolvedBookId
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

    // Host đã phân giải (ưu tiên localBook.host -> self.host -> ext.sourceUrl)
    private var resolvedHost: String? {
        if let localHost = localBook?.host, !localHost.isEmpty {
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
            .onChange(of: localBook?.chapters.count) { _, _ in
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
                    changeSourceTargetBook: localBook,
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

            floatingActionButton
        }
            BookDetailActionSheetView(
                selectedBookForTask: $selectedBookForTask,
                selectedTaskType: selectedTaskType,
                showingBypassBrowser: $showingBypassBrowser,
                initialDetailUrl: initialDetailUrl,
                resolvedHost: resolvedHost,
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
                    BookDetailHeaderView(
                        actualBookId: actualBookId,
                        coverUrl: coverUrl,
                        title: title,
                        author: author,
                        sourceName: sourceName,
                        detail: detail,
                        cleanedDetailText: cleanedDetailText(detail),
                        genres: genres,
                        desc: desc,
                        isDescExpanded: $isDescExpanded,
                        isLoadingDetail: isLoadingDetail,
                        detailErrorMessage: detailErrorMessage,
                        extensionPackageId: extensionPackageId,
                        localPath: ext?.localPath ?? "",
                        downloadUrl: ext?.downloadUrl ?? "",
                        configJson: ext?.configJson ?? "{}",
                        isTranslationEnabled: isTranslationEnabled,
                        onTranslateMetaIfNeeded: translateMetaIfNeeded,
                        onLoadBookDetailOnly: loadBookDetailOnly
                    )

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
                let totalChaps = localBook?.chapters.count ?? onlineChapters.count

                BookDetailTOCView(
                    chapterSearchQuery: $chapterSearchQuery,
                    totalChaps: totalChaps,
                    isTocAscending: $isTocAscending,
                    tocErrorMessage: tocErrorMessage,
                    isLoadingTOC: isLoadingTOC,
                    localBook: localBook,
                    filteredLocalChapters: filteredLocalChapters,
                    filteredOnlineChapters: filteredOnlineChapters,
                    tocPages: tocPages,
                    remainingPagesLoaded: remainingPagesLoaded,
                    onLoadTOCDataOnly: loadTOCDataOnly,
                    onStartReading: startReading,
                    onTranslateChapterTitleIfNeeded: translateChapterTitleIfNeeded,
                    onTranslateTitleIfNeeded: translateTitleIfNeeded,
                    onLoadMoreChapters: loadMoreChapters
                )
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

            if localBook != nil {
                Button(action: {
                    navigateToDictionary = true
                }) {
                    Label("Từ điển", systemImage: "character.book.closed")
                }
            }

            Button(action: {
                navigateToChangeSource = true
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
                    isLoadingRemainingPages = false
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
    private var floatingActionButton: some View {
        let totalChaps = localBook?.chapters.count ?? onlineChapters.count
        if totalChaps > 0 {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        if isMenuExpanded {
                            let activeChapterIndex = localBook?.currentChapterIndex ?? 0
                            Button(action: {
                                isMenuExpanded = false
                                startReading(at: activeChapterIndex)
                            }) {
                                HStack {
                                    Text(localBook == nil ? "Đọc ngay" : "Đọc tiếp")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: localBook == nil ? "play.fill" : "book.fill")
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
                                if let book = localBook, book.isOnShelf {
                                    removeFromShelf(book)
                                } else {
                                    addToShelf()
                                }
                            }) {
                                HStack {
                                    Text(localBook?.isOnShelf == true ? "Đã ở kệ" : "Thêm vào kệ")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: localBook?.isOnShelf == true ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(localBook?.isOnShelf == true ? Color.green : Color.accentColor)
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


    private func resolveBookId() {
        if let book = localBook {
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
        if let book = localBook {
            self.title = book.title
            self.author = book.author
            self.coverUrl = book.coverUrl
            self.desc = book.desc
            self.syncChaptersList()
            self.updateFilteredLocalChapters()
            if !book.chapters.isEmpty {
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

                    if let book = localBook {
                        book.title = detailResult.name
                        book.author = detailResult.author
                        book.coverUrl = detailResult.cover
                        let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                        book.desc = savedDesc
                        book.host = detailResult.host
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
                    } else {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                    }
                } else {
                    firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                }

                await MainActor.run {
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages

                    if let book = localBook {
                        updateLocalChapters(for: book, with: firstPageChapters)
                        try? modelContext.save()
                    }
                    self.isLoadingTOC = false
                }
            } catch {
                await MainActor.run {
                    self.tocErrorMessage = error.localizedDescription
                    self.isLoadingTOC = false
                }
            }
        }
    }

    private func addToShelf() {
        let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
        let targetBook: Book
        if let book = localBook {
            book.isOnShelf = true
            try? modelContext.save()
            targetBook = book
        } else {
            targetBook = createBookOnShelf(savedDesc: savedDesc)
        }
        if tocPages.count > 1 && !remainingPagesLoaded {
            startBackgroundRemainingPagesLoading(for: targetBook)
        }
    }

    @discardableResult
    private func createBookOnShelf(savedDesc: String) -> Book {
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
            currentChapterIndex: 0,
            currentChapterTitle: onlineChapters.first?.name ?? "",
            isOnShelf: true,
            isHistory: false,
            host: host.isEmpty ? nil : host
        )
        modelContext.insert(newBook)
        updateLocalChapters(for: newBook, with: onlineChapters)
        try? modelContext.save()
        return newBook
    }

    private func loadAllRemainingPages() async throws -> [ChapterResult] {
        guard let ext = ext else { return [] }
        var allChapters: [ChapterResult] = []
        let remainingPages = Array(tocPages.dropFirst())
        for pageUrl in remainingPages {
            try Task.checkCancellation() // Hỗ trợ hủy nhanh khi người dùng nhấn nút Quay lại
            let pageChaps = try await ExtensionManager.shared.toc(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                url: pageUrl,
                host: resolvedHost,
                configJson: ext.configJson
            )
            allChapters.append(contentsOf: pageChaps)
        }
        return allChapters
    }

    private func scheduleBackgroundTitleTranslationIfNeeded(for targetBook: Book? = nil) {
        guard isTranslationEnabled, let book = targetBook ?? localBook else { return }
        let targetBookId = actualBookId
        let chaptersToTranslate = book.chapters.filter { chap in
            (chap.titleTrans == nil || chap.titleTrans?.isEmpty == true) && TranslateUtils.containsChinese(chap.title)
        }
        guard !chaptersToTranslate.isEmpty else { return }

        struct ChapItem: Sendable {
            let id: String
            let title: String
        }
        let items = chaptersToTranslate.map { ChapItem(id: $0.id, title: $0.title) }

        Task {
            let translatedMap: [String: String] = await Task.detached(priority: .utility) {
                var map: [String: String] = [:]
                for item in items {
                    if Task.isCancelled { break }
                    map[item.id] = TranslateUtils.translateChapterTitle(item.title, bookId: targetBookId)
                }
                return map
            }.value

            await MainActor.run {
                for chap in book.chapters {
                    if let trans = translatedMap[chap.id] {
                        chap.titleTrans = trans
                    }
                }
                try? self.modelContext.save()
                self.syncChaptersList()
            }
        }
    }

    private func startBackgroundRemainingPagesLoading(for targetBook: Book? = nil) {
        guard tocPages.count > 1, !remainingPagesLoaded, !isLoadingRemainingPages else { return }
        isLoadingRemainingPages = true
        tocErrorMessage = ""

        let bookRef = targetBook ?? localBook

        loadingTask = Task {
            do {
                guard let ext = ext else {
                    await MainActor.run {
                        self.isLoadingRemainingPages = false
                    }
                    return
                }
                let remainingPages = Array(tocPages.dropFirst())
                let targetBookId = actualBookId
                let transEnabled = isTranslationEnabled

                for pageUrl in remainingPages {
                    try Task.checkCancellation()
                    let pageChaps = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: pageUrl,
                        host: resolvedHost,
                        configJson: ext.configJson
                    )
                    try Task.checkCancellation()

                    let translatedTitlesMap: [Int: String] = await Task.detached(priority: .utility) {
                        var map: [Int: String] = [:]
                        guard transEnabled else { return map }
                        for (idx, item) in pageChaps.enumerated() {
                            if Task.isCancelled { break }
                            if !item.name.isEmpty && TranslateUtils.containsChinese(item.name) {
                                map[idx] = TranslateUtils.translateChapterTitle(item.name, bookId: targetBookId)
                            }
                        }
                        return map
                    }.value

                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: pageChaps)

                        if let book = bookRef ?? self.localBook {
                            let startIdx = book.chapters.count
                            for (index, item) in pageChaps.enumerated() {
                                let chapId = Chapter.generateId(bookId: self.resolvedBookId, url: item.url, index: startIdx + index)
                                let newChap = Chapter(id: chapId, bookId: self.resolvedBookId, title: item.name, url: item.url, index: startIdx + index)
                                if let trans = translatedTitlesMap[index] {
                                    newChap.titleTrans = trans
                                }
                                newChap.book = book
                                self.modelContext.insert(newChap)
                            }
                            try? self.modelContext.save()
                            self.syncChaptersList()
                        }
                    }
                    await Task.yield()
                }

                await MainActor.run {
                    self.remainingPagesLoaded = true
                    self.isLoadingRemainingPages = false
                    self.loadingTask = nil
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.tocErrorMessage = "Lỗi tải thêm chương: \(error.localizedDescription)"
                        self.isLoadingRemainingPages = false
                        self.loadingTask = nil
                    }
                }
            }
        }
    }

    private func loadMoreChapters() {
        startBackgroundRemainingPagesLoading()
    }

    @discardableResult
    private func ensureBookCreatedIfNeeded(initialChapterIndex: Int) -> Book? {
        if let existing = localBook {
            return existing
        }
        guard !onlineChapters.isEmpty else { return nil }
        let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
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
            currentChapterTitle: onlineChapters.first?.name ?? "",
            isOnShelf: false,
            isHistory: false,
            host: host.isEmpty ? nil : host
        )
        modelContext.insert(newBook)
        updateLocalChapters(for: newBook, with: onlineChapters)
        try? modelContext.save()
        syncChaptersList()
        return newBook
    }

    private func startReading(at chapterIndex: Int) {
        let isBookReady = (localBook != nil && !(localBook?.chapters.isEmpty ?? true)) || !onlineChapters.isEmpty

        if isBookReady {
            let targetBook = ensureBookCreatedIfNeeded(initialChapterIndex: chapterIndex)
            scheduleBackgroundTitleTranslationIfNeeded(for: targetBook)
            startBackgroundRemainingPagesLoading(for: targetBook)
            self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
            return
        }

        bookOpenTask?.cancel()
        bookOpenTask = Task { @MainActor in
            do {
                if onlineChapters.isEmpty && localBook == nil {
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
                        } else {
                            firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        }
                    } else {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                    }

                    try Task.checkCancellation()
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages
                }

                let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                let targetBook: Book
                if let existing = localBook {
                    targetBook = existing
                } else {
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
                        currentChapterIndex: chapterIndex,
                        currentChapterTitle: onlineChapters.first?.name ?? "",
                        isOnShelf: false,
                        isHistory: false,
                        host: host.isEmpty ? nil : host
                    )
                    modelContext.insert(newBook)
                    targetBook = newBook
                }

                updateLocalChapters(for: targetBook, with: onlineChapters)

                try Task.checkCancellation()

                do {
                    try modelContext.save()
                } catch {
                    if modelContext.hasChanges {
                        modelContext.rollback()
                    }
                    throw error
                }

                syncChaptersList()

                try Task.checkCancellation()

                bookOpenTask = nil
                self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)

                scheduleBackgroundTitleTranslationIfNeeded(for: targetBook)
                startBackgroundRemainingPagesLoading(for: targetBook)
            } catch {
                if modelContext.hasChanges {
                    modelContext.rollback()
                }
                bookOpenTask = nil
                readerRoute = nil
                if !Task.isCancelled {
                    self.tocErrorMessage = "Lỗi chuẩn bị sách: \(error.localizedDescription)"
                }
            }
        }
    }

    private func prepareForTask(taskType: TaskType) {
        if tocPages.count > 1 && !remainingPagesLoaded {
            isLoadingRemainingPages = true
            tocErrorMessage = ""

            loadingTask = Task {
                do {
                    let remainingChaps = try await loadAllRemainingPages()
                    try Task.checkCancellation()
                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: remainingChaps)

                        if let book = localBook {
                            let startIdx = book.chapters.count
                            for (index, item) in remainingChaps.enumerated() {
                                let chapId = Chapter.generateId(bookId: resolvedBookId, url: item.url, index: startIdx + index)
                                let newChap = Chapter(id: chapId, bookId: resolvedBookId, title: item.name, url: item.url, index: startIdx + index)
                                newChap.book = book
                                modelContext.insert(newChap)
                            }
                            try? modelContext.save()
                            self.syncChaptersList()
                        } else {
                            let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                            createBookOnShelf(savedDesc: savedDesc)
                        }

                        self.remainingPagesLoaded = true
                        self.isLoadingRemainingPages = false

                        if let book = localBook {
                            self.selectedTaskType = taskType
                            self.selectedBookForTask = book
                        }
                        self.loadingTask = nil
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.tocErrorMessage = "Lỗi tải thêm chương: \(error.localizedDescription)"
                            self.isLoadingRemainingPages = false
                            self.loadingTask = nil
                        }
                    }
                }
            }
        } else {
            if localBook == nil {
                let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                createBookOnShelf(savedDesc: savedDesc)
            }
            if let book = localBook {
                self.selectedTaskType = taskType
                self.selectedBookForTask = book
            }
        }
    }

    private func removeFromShelf(_ book: Book) {
        let bookId = book.bookId
        let container = modelContext.container
        Task { @MainActor in
            do {
                try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa khỏi kệ sách tại BookDetailView: \(error.localizedDescription)")
            }
        }
    }

    private func updateLocalChapters(for book: Book, with results: [ChapterResult]) {
        let unmatchedSet = book.chapters

        var unmatchedByUrl: [String: Chapter] = [:]
        var unmatchedByIndex: [Int: Chapter] = [:]
        for chap in unmatchedSet {
            if !chap.url.isEmpty {
                unmatchedByUrl[chap.url] = chap
            }
            unmatchedByIndex[chap.index] = chap
        }

        var remainingUnmatched = Set(unmatchedSet)

        for (index, item) in results.enumerated() {
            var matchedChapter: Chapter? = nil
            if !item.url.isEmpty {
                matchedChapter = unmatchedByUrl[item.url] ?? unmatchedByIndex[index]
            } else {
                matchedChapter = unmatchedByIndex[index]
            }

            if let chapter = matchedChapter {
                remainingUnmatched.remove(chapter)
                chapter.title = item.name
                chapter.url = item.url
                chapter.index = index
                chapter.host = item.host
                if chapter.isCached && chapter.length > 0 {
                    chapter.isCached = true
                }
            } else {
                let chapId = Chapter.generateId(bookId: book.bookId, url: item.url, index: index)
                let newChapter = Chapter(
                    id: chapId,
                    bookId: book.bookId,
                    title: item.name,
                    url: item.url,
                    index: index,
                    host: item.host
                )
                book.chapters.append(newChapter)
                modelContext.insert(newChapter)
            }
        }

        for stale in remainingUnmatched {
            let isPlayingChapter = TTSManager.shared.playingBookId == book.bookId
                && TTSManager.shared.playingChapterIndex == stale.index
                && (stale.url.isEmpty || TTSManager.shared.playingChapterUrl == stale.url)
            if !isPlayingChapter {
                book.chapters.removeAll(where: { $0 === stale })
                modelContext.delete(stale)
            }
        }

        if (book.host == nil || book.host?.isEmpty == true),
           let firstHost = results.first?.host,
           !firstHost.isEmpty {
            book.host = firstHost
        }

        self.syncChaptersList()
    }

    private func syncChaptersList() {
        if let book = localBook {
            chaptersList = book.chapters
        } else {
            chaptersList = []
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
            self.detailErrorMessage = ""
            self.tocErrorMessage = ""
        }

        // Chạy song song detail và toc
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

                if let book = localBook {
                    book.title = detailResult.name
                    book.author = detailResult.author
                    book.coverUrl = detailResult.cover
                    let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                    book.desc = savedDesc
                    book.host = detailResult.host
                }
            }
        } catch {
            await MainActor.run {
                self.detailErrorMessage = "Lỗi tải chi tiết: \(error.localizedDescription)"
            }
        }

        do {
            let path = ext.localPath
            var allChapters: [ChapterResult] = []
            if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                let pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                await MainActor.run {
                    self.tocPages = pages
                }

                for pageUrl in pages {
                    let pageChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, host: resolvedHost, configJson: ext.configJson)
                    allChapters.append(contentsOf: pageChaps)
                }
                await MainActor.run {
                    self.remainingPagesLoaded = true
                }
            } else {
                let tocResult = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: localBook?.host, configJson: ext.configJson)
                allChapters = tocResult
            }

            await MainActor.run {
                self.onlineChapters = allChapters
                if let book = localBook {
                    updateLocalChapters(for: book, with: allChapters)
                    try? modelContext.save()
                }
            }
        } catch {
            await MainActor.run {
                self.tocErrorMessage = "Lỗi tải mục lục: \(error.localizedDescription)"
            }
        }
    }
}
