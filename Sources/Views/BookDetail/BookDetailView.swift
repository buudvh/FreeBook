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
    @State private var chapterSnapshots: [StoredChapterSnapshot] = []
    @State private var filteredOnlineChapters: [(offset: Int, element: ChapterResult)] = []
    @State private var host = ""
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    // Cấu hình tab và FAB
    @State private var selectedTab = 0
    @State private var isMenuExpanded = false
    @State private var loadingTask: Task<Void, Never>? = nil

    // Màn hình chuẩn bị mở sách mới
    @State private var bookOpenTask: Task<Void, Never>? = nil
    @State private var isPreparingBookProgress = false
    @State private var prepareProgressText = ""
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
            mainContentView

            hiddenNavigationLinksView

            if isLoadingRemainingPages || isPreparingBookProgress {
                loadingOverlay
            }

            floatingActionButton
        }
        .bookDetailActionSheets(
            selectedBookForTask: $selectedBookForTask,
            selectedTaskType: selectedTaskType,
            showingBypassBrowser: $showingBypassBrowser,
            initialDetailUrl: initialDetailUrl,
            resolvedHost: resolvedHost,
            onImport: { detailUrl, packageId, sourceName in
                showingBypassBrowser = false
                let targetBookId = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)

                if targetBookId == actualBookId || detailUrl == actualBookId {
                    loadBookData()
                    loadLocalChapterSnapshots()
                } else {
                    importedBookId = targetBookId
                    importedExtensionPackageId = packageId
                    importedDetailUrl = detailUrl
                    importedSourceName = sourceName
                    if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                        importedHost = "\(scheme)://\(host)"
                    } else {
                        importedHost = ""
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigateToImportedBook = true
                    }
                }
                ToastManager.shared.show(message: "Đã hoàn tất tải các chương!", type: .success)
            }
        )
    }

    @ViewBuilder
    private var mainContentView: some View {
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
        .onChange(of: ChapterStoreConfiguration.enableSwiftDataTOCWrite ? localBook?.chapters.count : chapterSnapshots.count) { _, _ in
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
    }

    @ViewBuilder
    private var hiddenNavigationLinksView: some View {
        Group {
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
                    BookDetailHeaderView(
                        actualBookId: actualBookId,
                        coverUrl: coverUrl,
                        title: title,
                        author: author,
                        sourceName: sourceName,
                        iconUrl: ext?.iconUrl,
                        detail: detail,
                        cleanedDetailText: cleanedDetailText,
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
                                    Text(translateMetaIfNeeded(suggest.title))
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
                                    sourceName: sourceName,
                                    isTranslationEnabled: isTranslationEnabled
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
                                Text(translateMetaIfNeeded(comment.title))
                                    .font(.headline)
                                    .padding(.horizontal)

                                CommentSectionView(
                                    category: comment,
                                    localPath: ext?.localPath ?? "",
                                    downloadUrl: ext?.downloadUrl ?? "",
                                    configJson: ext?.configJson ?? "{}",
                                    extensionPackageId: extensionPackageId,
                                    sourceName: sourceName,
                                    isTranslationEnabled: isTranslationEnabled
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

    private func refreshLocalTOCSnapshots() {
        loadLocalChapterSnapshots()
    }

    private func loadLocalChapterSnapshots() {
        let bId = actualBookId
        Task {
            if let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bId), !storeChaps.isEmpty {
                await MainActor.run {
                    self.chapterSnapshots = storeChaps
                }
            }
        }
    }

    @ViewBuilder
    private var tocTab: some View {
        VStack(spacing: 0) {
            if renderedTab == 1 {
                let totalChaps = chapterSnapshots.count > 0 ? chapterSnapshots.count : onlineChapters.count

                BookDetailTOCView(
                    chapterSearchQuery: $chapterSearchQuery,
                    totalChaps: totalChaps,
                    isTocAscending: $isTocAscending,
                    tocErrorMessage: tocErrorMessage,
                    isLoadingTOC: isLoadingTOC,
                    localBook: localBook,
                    filteredLocalChapters: filteredLocalChapters,
                    chapterSnapshots: chapterSnapshots,
                    filteredOnlineChapters: filteredOnlineChapters,
                    tocPages: tocPages,
                    remainingPagesLoaded: remainingPagesLoaded,
                    isTranslationEnabled: isTranslationEnabled,
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
        .onAppear {
            loadLocalChapterSnapshots()
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
                Text(isPreparingBookProgress ? prepareProgressText : "Đang tải danh sách chương...")
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button(action: {
                    loadingTask?.cancel()
                    loadingTask = nil
                    bookOpenTask?.cancel()
                    bookOpenTask = nil
                    isLoadingRemainingPages = false
                    isPreparingBookProgress = false
                    if modelContext.hasChanges {
                        modelContext.rollback()
                    }
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
        let totalChaps = chapterSnapshots.count > 0 ? chapterSnapshots.count : (ChapterStoreConfiguration.enableSwiftDataTOCWrite ? (localBook?.chapters.count ?? onlineChapters.count) : onlineChapters.count)
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
        if let ext = ext, !ext.localPath.isEmpty {
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
        } else if let book = localBook {
            self.title = book.title
            self.author = book.author
            self.coverUrl = book.coverUrl
            self.desc = book.desc
            self.detail = book.desc
            self.host = book.host ?? ""
            self.isLoadingDetail = false
        } else if let ext = ext {
            self.detailErrorMessage = "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!"
            self.isLoadingDetail = false
        } else {
            self.detailErrorMessage = "Không tìm thấy tiện ích bóc tách của truyện này!"
            self.isLoadingDetail = false
        }
    }

    private func loadTOCDataOnly() {
        if let ext = ext, !ext.localPath.isEmpty {
            // Tiếp tục luồng nạp online
        } else if localBook != nil {
            self.loadLocalChapterSnapshots()
            self.syncChaptersList()
            self.updateFilteredLocalChapters()
            self.isLoadingTOC = false
            return
        } else if let ext = ext {
            self.tocErrorMessage = "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!"
            self.isLoadingTOC = false
            return
        } else {
            self.tocErrorMessage = "Không tìm thấy tiện ích bóc tách của truyện này!"
            self.isLoadingTOC = false
            return
        }

        guard let ext = ext, !ext.localPath.isEmpty else {
            tocErrorMessage = "Không tìm thấy tiện ích bóc tách!"
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

                let shouldPersistTOC = await MainActor.run {
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages
                    self.isLoadingTOC = false
                    return self.localBook != nil
                }

                if shouldPersistTOC {
                    let targetBookId = await MainActor.run { self.actualBookId }
                    let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
                    let snapshots = await MainActor.run { self.tocMetadata(from: firstPageChapters) }
                    _ = try await ChapterContentRepository.shared.saveChapterList(
                        bookId: targetBookId,
                        createSnapshot: nil,
                        chapters: snapshots,
                        mode: pages.count > 1 ? .upsertPage : .replaceFullTOC,
                        protectedTTSChapter: ttsProtection
                    )
                    await MainActor.run {
                        self.refreshLocalTOCSnapshots()
                        if let savedBook = self.refetchBook(bookId: targetBookId) {
                            self.chaptersList = savedBook.chapters
                        } else {
                            self.syncChaptersList()
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

    private var activeTTSProtectedChapter: ProtectedTTSChapter? {
        let playingBookId = TTSManager.shared.playingBookId
        guard !playingBookId.isEmpty else {
            return nil
        }
        return ProtectedTTSChapter(
            bookId: playingBookId,
            index: TTSManager.shared.playingChapterIndex,
            url: TTSManager.shared.playingChapterUrl
        )
    }

    private func addToShelf() {
        let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
        Task { @MainActor in
            let targetBook: Book?
            if let book = localBook {
                book.isOnShelf = true
                try? modelContext.save()
                targetBook = book
            } else {
                targetBook = await createBookOnShelf(savedDesc: savedDesc)
            }
            if tocPages.count > 1 && !remainingPagesLoaded {
                startBackgroundRemainingPagesLoading(for: targetBook)
            }
        }
    }

    @discardableResult
    private func createBookOnShelf(savedDesc: String) async -> Book? {
        let snapshot = makeTOCCreateSnapshot(
            savedDesc: savedDesc,
            sourceUrl: ext?.sourceUrl ?? "",
            initialChapterIndex: 0,
            initialChapterTitle: onlineChapters.first?.name ?? "",
            isOnShelf: true,
            isHistory: false
        )
        let chapters = tocMetadata(from: onlineChapters)
        let targetBookId = resolvedBookId
        let ttsProtection = activeTTSProtectedChapter
        do {
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: targetBookId,
                createSnapshot: snapshot,
                chapters: chapters,
                mode: .replaceFullTOC,
                protectedTTSChapter: ttsProtection
            )
            let savedBook = refetchBook(bookId: targetBookId)
            if let savedBook {
                self.chaptersList = savedBook.chapters
            } else {
                self.syncChaptersList()
            }
            return savedBook ?? localBook
        } catch {
            self.tocErrorMessage = "Không thể tạo sách: \(error.localizedDescription)"
            return nil
        }
    }

    private func loadAllRemainingPages() async throws -> [ChapterResult] {
        guard let ext = ext else { return [] }
        var allChapters: [ChapterResult] = []
        let remainingPages = Array(tocPages.dropFirst())
        for pageUrl in remainingPages {
            try Task.checkCancellation()
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
        guard isTranslationEnabled else { return }
        let targetBookId = actualBookId

        if !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            Task {
                guard let storeChaps = try? await ChapterStore.shared.fetchOrderedTOC(bookId: targetBookId), !storeChaps.isEmpty else { return }
                let toTranslate = storeChaps.filter { ($0.titleTrans == nil || $0.titleTrans?.isEmpty == true) && TranslateUtils.containsChinese($0.title) }
                guard !toTranslate.isEmpty else { return }

                struct Item: Sendable {
                    let index: Int
                    let url: String
                    let title: String
                }
                let items = toTranslate.map { Item(index: $0.index, url: $0.url, title: $0.title) }

                let updates: [(index: Int, url: String, titleTrans: String)] = await Task.detached(priority: .utility) {
                    var list: [(index: Int, url: String, titleTrans: String)] = []
                    for item in items {
                        if Task.isCancelled { break }
                        let trans = TranslateUtils.translateChapterTitle(item.title, bookId: targetBookId)
                        list.append((index: item.index, url: item.url, titleTrans: trans))
                    }
                    return list
                }.value

                if !updates.isEmpty {
                    try? await ChapterStore.shared.updateTitleTranslations(bookId: targetBookId, updates: updates)
                    if let refreshed = try? await ChapterStore.shared.fetchOrderedTOC(bookId: targetBookId), !refreshed.isEmpty {
                        await MainActor.run {
                            self.chapterSnapshots = refreshed
                        }
                    }
                }
            }
            return
        }

        guard let book = targetBook ?? localBook else { return }
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
                    await MainActor.run { self.isLoadingRemainingPages = false }
                    return
                }
                let remainingPages = Array(tocPages.dropFirst())
                let targetBookId = await MainActor.run { self.actualBookId }

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

                    let transEnabled = await MainActor.run { self.isTranslationEnabled }
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

                    let startIndex = await MainActor.run { self.onlineChapters.count }
                    let shouldPersistPage = await MainActor.run { bookRef != nil || self.localBook != nil }
                    let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
                    if shouldPersistPage {
                        let snapshots = pageChaps.enumerated().map { offset, item in
                            ChapterMetadataSnapshot(
                                title: item.name,
                                url: item.url,
                                index: startIndex + offset,
                                host: item.host,
                                titleTrans: translatedTitlesMap[offset]
                            )
                        }
                        _ = try await ChapterContentRepository.shared.saveChapterList(
                            bookId: targetBookId,
                            createSnapshot: nil,
                            chapters: snapshots,
                            mode: .upsertPage,
                            protectedTTSChapter: ttsProtection
                        )
                    }

                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: pageChaps)
                        if let savedBook = refetchBook(bookId: targetBookId) {
                            self.chaptersList = savedBook.chapters
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


    private func startReading(at chapterIndex: Int) {
        let hasLocalChapters = !chapterSnapshots.isEmpty || (ChapterStoreConfiguration.enableSwiftDataTOCWrite && localBook?.chapters.isEmpty == false)
        if let book = localBook, hasLocalChapters {
            book.currentChapterIndex = chapterIndex
            try? modelContext.save()
            scheduleBackgroundTitleTranslationIfNeeded(for: book)
            self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
            return
        }

        bookOpenTask?.cancel()
        isPreparingBookProgress = true
        prepareProgressText = "Đang lấy mục lục..."

        bookOpenTask = Task { @MainActor in
            do {
                if let book = localBook {
                    let count = (try? await ChapterStore.shared.fetchCountAndChecksum(bookId: resolvedBookId))?.count ?? 0
                    if count > 0 {
                        book.currentChapterIndex = chapterIndex
                        try? modelContext.save()
                        scheduleBackgroundTitleTranslationIfNeeded(for: book)
                        self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
                        isPreparingBookProgress = false
                        bookOpenTask = nil
                        return
                    }
                }

                guard let ext = ext, !ext.localPath.isEmpty else {
                    throw NSError(domain: "BookError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tiện ích bóc tách!"])
                }
                let path = ext.localPath
                var allChapters: [ChapterResult] = onlineChapters
                var pages: [String] = tocPages

                if allChapters.isEmpty {
                    if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                        pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        let firstUrl = pages.first ?? initialDetailUrl
                        let firstChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: firstUrl, host: resolvedHost, configJson: ext.configJson)
                        allChapters.append(contentsOf: firstChaps)
                    } else {
                        let firstChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, host: resolvedHost, configJson: ext.configJson)
                        allChapters.append(contentsOf: firstChaps)
                    }
                    try Task.checkCancellation()
                    self.onlineChapters = allChapters
                    self.tocPages = pages
                }

                if pages.count > 1 && !remainingPagesLoaded {
                    let remainingPages = Array(pages.dropFirst())
                    let totalPages = pages.count
                    for (idx, pageUrl) in remainingPages.enumerated() {
                        try Task.checkCancellation()
                        let currentPageNum = idx + 2
                        self.prepareProgressText = "Đang lấy mục lục... Trang \(currentPageNum)/\(totalPages) (Đã lấy \(allChapters.count) chương)"
                        let pageChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, host: resolvedHost, configJson: ext.configJson)
                        allChapters.append(contentsOf: pageChaps)
                        await Task.yield()
                    }
                    try Task.checkCancellation()
                    self.onlineChapters = allChapters
                    self.remainingPagesLoaded = true
                }

                let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                let createSnapshot: TOCBookCreateSnapshot?
                if let existing = localBook {
                    existing.currentChapterIndex = chapterIndex
                    try? modelContext.save()
                    createSnapshot = nil
                } else {
                    createSnapshot = makeTOCCreateSnapshot(
                        savedDesc: savedDesc,
                        sourceUrl: ext.sourceUrl,
                        initialChapterIndex: chapterIndex,
                        initialChapterTitle: allChapters.first?.name ?? ""
                    )
                }

                let ttsProtection = activeTTSProtectedChapter
                self.prepareProgressText = "Đang lưu database... \(allChapters.count) chương"
                _ = try await ChapterContentRepository.shared.saveChapterList(
                    bookId: resolvedBookId,
                    createSnapshot: createSnapshot,
                    chapters: tocMetadata(from: allChapters),
                    mode: .replaceFullTOC,
                    protectedTTSChapter: ttsProtection
                )

                let savedBook = refetchBook(bookId: resolvedBookId)
                if let savedBook {
                    chaptersList = savedBook.chapters
                } else {
                    syncChaptersList()
                }
                try Task.checkCancellation()

                bookOpenTask = nil
                isPreparingBookProgress = false
                self.readerRoute = ReaderRoute(chapterIndex: chapterIndex)
                scheduleBackgroundTitleTranslationIfNeeded(for: savedBook ?? localBook)
            } catch {
                if modelContext.hasChanges {
                    modelContext.rollback()
                }
                bookOpenTask = nil
                isPreparingBookProgress = false
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

                    let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
                    let saveRequest = await MainActor.run {
                        let targetBookId = self.resolvedBookId
                        if self.localBook != nil {
                            return (
                                bookId: targetBookId,
                                snapshot: Optional<TOCBookCreateSnapshot>.none,
                                chapters: self.tocMetadata(from: remainingChaps, startIndex: self.onlineChapters.count),
                                mode: TOCReconciliationMode.upsertPage
                            )
                        }
                        let savedDesc = self.detail.isEmpty ? self.desc : "\(self.desc)\n\n---\n\(self.cleanDetailText(self.detail))"
                        let allChapters = self.onlineChapters + remainingChaps
                        return (
                            bookId: targetBookId,
                            snapshot: Optional(
                                self.makeTOCCreateSnapshot(
                                    savedDesc: savedDesc,
                                    sourceUrl: self.ext?.sourceUrl ?? "",
                                    initialChapterIndex: 0,
                                    initialChapterTitle: allChapters.first?.name ?? "",
                                    isOnShelf: true,
                                    isHistory: false
                                )
                            ),
                            chapters: self.tocMetadata(from: allChapters),
                            mode: TOCReconciliationMode.replaceFullTOC
                        )
                    }

                    _ = try await ChapterContentRepository.shared.saveChapterList(
                        bookId: saveRequest.bookId,
                        createSnapshot: saveRequest.snapshot,
                        chapters: saveRequest.chapters,
                        mode: saveRequest.mode,
                        protectedTTSChapter: ttsProtection
                    )

                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: remainingChaps)
                        if let savedBook = refetchBook(bookId: saveRequest.bookId) {
                            self.chaptersList = savedBook.chapters
                        } else {
                            self.syncChaptersList()
                        }

                        self.remainingPagesLoaded = true
                        self.isLoadingRemainingPages = false

                        if let book = refetchBook(bookId: saveRequest.bookId) ?? localBook {
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
            Task { @MainActor in
                let targetBook: Book?
                if let book = localBook {
                    targetBook = book
                } else {
                    let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
                    targetBook = await createBookOnShelf(savedDesc: savedDesc)
                }
                if let book = targetBook {
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
                try await BookStorageManager.shared.deleteBookAsync(bookId: bookId, container: container)
            } catch {
                AppLogger.shared.log("❌ Lỗi khi xóa khỏi kệ sách tại BookDetailView: \(error.localizedDescription)")
            }
        }
    }

    private func tocMetadata(from results: [ChapterResult], startIndex: Int = 0) -> [ChapterMetadataSnapshot] {
        results.enumerated().map { offset, item in
            ChapterMetadataSnapshot(
                title: item.name,
                url: item.url,
                index: startIndex + offset,
                host: item.host
            )
        }
    }

    private func makeTOCCreateSnapshot(
        savedDesc: String,
        sourceUrl: String,
        initialChapterIndex: Int,
        initialChapterTitle: String,
        isOnShelf: Bool = false,
        isHistory: Bool = false
    ) -> TOCBookCreateSnapshot {
        TOCBookCreateSnapshot(
            bookId: resolvedBookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: initialDetailUrl,
            sourceName: sourceName,
            sourceUrl: sourceUrl,
            extensionPackageId: extensionPackageId,
            currentChapterIndex: initialChapterIndex,
            currentChapterPage: 0,
            currentChapterTitle: initialChapterTitle,
            isOnShelf: isOnShelf,
            isHistory: isHistory,
            host: host.isEmpty ? nil : host
        )
    }

    private func refetchBook(bookId: String) -> Book? {
        let targetBookId = bookId
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.bookId == targetBookId }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func syncChaptersList() {
        refreshLocalTOCSnapshots()
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
            if chapterSearchQuery.isEmpty { return true }
            if isTranslationEnabled {
                return chap.name.localizedCaseInsensitiveContains(chapterSearchQuery) ||
                    TranslateUtils.translateChapterTitle(chap.name, bookId: actualBookId).localizedCaseInsensitiveContains(chapterSearchQuery)
            } else {
                return chap.name.localizedCaseInsensitiveContains(chapterSearchQuery)
            }
        }
    }

    private func reloadBookData() async {
        guard let ext = ext else { return }
        guard !ext.localPath.isEmpty else { return }

        await MainActor.run {
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

            let targetBookId = await MainActor.run { self.actualBookId }
            let shouldPersist = await MainActor.run { self.localBook != nil }
            let ttsProtection = await MainActor.run { self.activeTTSProtectedChapter }
            let snapshots = await MainActor.run { self.tocMetadata(from: allChapters) }

            if shouldPersist {
                _ = try await ChapterContentRepository.shared.saveChapterList(
                    bookId: targetBookId,
                    createSnapshot: nil,
                    chapters: snapshots,
                    mode: .replaceFullTOC,
                    protectedTTSChapter: ttsProtection
                )
            }

            await MainActor.run {
                self.onlineChapters = allChapters
                if let savedBook = refetchBook(bookId: targetBookId) {
                    self.chaptersList = savedBook.chapters
                } else {
                    self.syncChaptersList()
                }
            }
        } catch {
            await MainActor.run {
                self.tocErrorMessage = "Lỗi tải mục lục: \(error.localizedDescription)"
            }
        }
    }
}
