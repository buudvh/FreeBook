import SwiftUI
import SwiftData

struct ReaderRoute: Identifiable, Hashable {
    let chapterIndex: Int
    var id: Int { chapterIndex }
}

struct BookDetailView: View {
    @Environment(\.modelContext) internal var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]

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
    @State internal var detailErrorMessage = ""
    @State internal var tocErrorMessage = ""
    // Link "Mở link lỗi" của hai chữ lỗi trên — chỉ gán qua `setDetailError`/`setTOCError` (`BookDetailView+ErrorLink`).
    @State internal var detailErrorLink: SourceErrorLink?
    @State internal var tocErrorLink: SourceErrorLink?
    @State private var openingDetailErrorLink: SourceErrorLink?
    @State private var openingTOCErrorLink: SourceErrorLink?
    /// Bị trình duyệt "Mở link lỗi" che lúc biến mất ⇒ `onAppear` kế tiếp không `loadBookData()` trước khi chép cookie
    /// (lượt thử lại của `.errorLinkBrowser` lo tải và cũng hạ cờ) — xem `ErrorLinkBrowserModifier`.
    @State private var skipsReappearLoad = false

    @State internal var genres: [CategoryResult] = []
    @State internal var suggests: [CategoryResult] = []
    @State internal var comments: [CategoryResult] = []

    // Dữ liệu tạm thời khi xem online (chưa thêm vào kệ)
    @State internal var title = ""
    @State internal var author = ""
    @State internal var coverUrl = ""
    @State internal var desc = ""
    @State private var isDescExpanded = false
    @State internal var isTocAscending = true
    @State private var renderedTab = 0
    @State internal var detail = ""
    @State internal var onlineChapters: [ChapterResult] = []
    @State internal var chaptersList: [Chapter] = []
    @State internal var filteredLocalChapters: [Chapter] = []
    @State internal var chapterSnapshots: [StoredChapterSnapshot] = []
    @State internal var filteredOnlineChapters: [(offset: Int, element: ChapterResult)] = []
    @State internal var host = ""
    @State internal var isTranslationEnabled = false

    var totalChaptersCount: Int {
        if chapterSnapshots.count > 0 { return chapterSnapshots.count }
        if ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            return localBook?.chapters.count ?? onlineChapters.count
        }
        return onlineChapters.count
    }

    // Cấu hình tab và FAB
    @State internal var selectedTab = 0
    @State private var isMenuExpanded = false
    @State internal var loadingTask: Task<Void, Never>? = nil
    /// Truyện vừa được đưa lên kệ, đang chờ người dùng chọn bộ sưu tập (chọn hay không đều được).
    @State internal var collectionPickerBook: Book? = nil

    // Màn hình chuẩn bị mở sách mới
    @State internal var bookOpenTask: Task<Void, Never>? = nil
    @State internal var isPreparingBookProgress = false
    @State internal var prepareProgressText = ""
    @AppStorage("readerSelectedTheme") private var readerTheme: ReaderTheme = .dark

    // Phân trang danh sách chương
    @State internal var tocPages: [String] = []
    @State internal var remainingPagesLoaded = false
    @State internal var isLoadingRemainingPages = false
    /// Số trang **sau trang 1** đã nối vào `onlineChapters`: lượt "Tải thêm chương" lỗi/huỷ thì lần sau tải tiếp từ đây.
    @State internal var loadedRemainingPageCount = 0
    @State internal var readerRoute: ReaderRoute?
    @State internal var navigateToDictionary = false
    @State internal var navigateToChangeSource = false
    @State internal var showingEllipsisMenu = false // Ngăn kéo "…" (`BookDetailView+Extensions`)

    // Trình duyệt bypass Cloudflare & Import
    @State internal var showingBypassBrowser = false
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToImportedBook = false
    @State internal var chapterSearchQuery = ""
    @State internal var appliedChapterSearchQuery = "" // query đã debounce, bộ lọc chỉ đọc giá trị này
    @State internal var onlineTitleIndex = BookDetailOnlineTOCIndex()

    // Quản lý tác vụ tải/xuất
    @State internal var selectedTaskType: TaskType = .download
    @State internal var selectedBookForTask: Book? = nil

    @State internal var resolvedBookId: String = ""

    internal var actualBookId: String {
        resolvedBookId.isEmpty ? bookId : resolvedBookId
    }

    // Tìm sách local trong database
    internal var localBook: Book? {
        allBooks.first(where: {
            $0.detailUrl == initialDetailUrl && $0.extensionPackageId == extensionPackageId
        })
    }

    // Tìm extension để chạy script. Tra cả mục catalog **chưa cài** (folder rỗng) để còn báo "Vui lòng cài đặt
    // tiện ích …" theo tên; `localPath` rỗng ⇒ không chạy script.
    internal var ext: Extension? {
        ExtensionLibraryRepository.shared.catalogExtension(packageId: extensionPackageId)
    }

    // Host đã phân giải (ưu tiên localBook.host -> self.host -> ext.sourceUrl)
    internal var resolvedHost: String? {
        if let localHost = localBook?.host, !localHost.isEmpty {
            return localHost
        }
        if !self.host.isEmpty {
            return self.host
        }
        return ext?.sourceUrl
    }

    internal func cleanDetailText(_ html: String) -> String {
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

    internal func translateChapterTitleIfNeeded(_ chap: Chapter) -> String {
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
        // Tiêu đề không hiện (`backPageTitle`: mục `.principal` rỗng) nhưng vẫn giữ: màn con lấy nó làm nhãn nút quay lại.
        // Cả khi là gốc sheet (mục lục Reader/Comic): header là bìa lớn, không có tiêu đề trái.
        .backPageTitle("Chi Tiết Truyện")
        // Nút quay lại của màn này chỉ còn icon, không kèm tên màn trước.
        .toolbarRole(.editor)
        .closesWhenNsfwHidden(packageId: extensionPackageId) // tắt NSFW ⇒ đóng, kể cả truyện trên Kệ
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 6) {
                    ReaderTranslationScopeMenuView(
                        bookId: actualBookId,
                        packageId: extensionPackageId,
                        sourceName: sourceName,
                        showBackground: false,
                        isChineseSourceHint: ext?.isChineseSource,
                        iconSize: 17,
                        frameWidth: 36,
                        frameHeight: 36
                    )
                    ellipsisMenu
                }
            }
        }
        .sideDrawerMenu(isPresented: $showingEllipsisMenu, title: ellipsisMenuTitle) { ellipsisMenuItems }
        .onAppear {
            renderedTab = selectedTab
            isTranslationEnabled = TranslationConfigStore.shared.isTranslationEnabled(
                bookId: actualBookId,
                packageId: extensionPackageId,
                isChineseSourceHint: ext?.isChineseSource
            )
            if skipsReappearLoad {
                skipsReappearLoad = false
            } else {
                loadBookData()
            }
            markSourceUsed()
            if contentKind == .video, let videoBookId = localBook?.bookId { VideoOfflineLibrary.shared.refresh(bookId: videoBookId) }
            syncChaptersList()
            updateFilteredLocalChapters()
            updateFilteredOnlineChapters()
        }
        .onDisappear {
            if openingDetailErrorLink != nil || openingTOCErrorLink != nil { skipsReappearLoad = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationConfigStore.didChangeNotification)) { _ in
            let newState = TranslationConfigStore.shared.isTranslationEnabled(
                bookId: actualBookId,
                packageId: extensionPackageId,
                isChineseSourceHint: ext?.isChineseSource
            )
            if isTranslationEnabled != newState {
                isTranslationEnabled = newState
            }
        }
        .task(id: actualBookId) {
            // Transaction thuộc `BookTransactionCoordinator` — View không tự `modelContext.save()`.
            // Lấy `bookId` từ chính `localBook`: `localBook` dò theo `detailUrl` nên không chắc trùng
            // `actualBookId` khi `resolvedBookId` chưa được phân giải.
            guard let targetBookId = localBook?.bookId else { return }
            if case .failure(let error) = BookTransactionCoordinator.shared.refreshTitleTranslations(bookId: targetBookId, in: modelContext) {
                AppLogger.shared.log("⚠️ [BookDetailView] Không cập nhật được tên dịch: \(error.localizedDescription)")
            }
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
        .task(id: chapterSearchQuery) {
            await applyChapterSearchQueryDebounced()
        }
        .onChange(of: isTranslationEnabled) { _, _ in
            updateFilteredLocalChapters()
            updateFilteredOnlineChapters()
        }
        // Reader đóng: màn này **không** chạy lại `onAppear` (cover phủ lên, không pop navigation), nên phải tự
        // đọc lại danh sách cục bộ. Sách vừa được `startReading` tạo ⇒ `localBook` đã khác nil nhưng
        // `chapterSnapshots`/`chaptersList` còn rỗng; không đồng bộ ở đây thì tab mục lục trắng (chỉ đọc DB,
        // không gọi mạng — mục lục vừa được `startReading` ghi đủ).
        .fullScreenCover(item: $readerRoute, onDismiss: {
            syncChaptersList()
            updateFilteredLocalChapters()
            updateFilteredOnlineChapters()
        }) { route in
            NavigationStack {
                LazyView {
                    BookContentDestination(
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
        .sheet(item: $collectionPickerBook) { book in
            CollectionPickerSheet(bookId: book.bookId)
        }
        // Lỗi chi tiết thường kéo theo lỗi mục lục (cùng trang chặn) ⇒ thử lại cả mục lục nếu nó cũng đang lỗi.
        .errorLinkBrowser(link: $openingDetailErrorLink, packageId: extensionPackageId) {
            skipsReappearLoad = false
            loadBookDetailOnly()
            if !tocErrorMessage.isEmpty { loadTOCDataOnly() }
        }
        .errorLinkBrowser(link: $openingTOCErrorLink, packageId: extensionPackageId) {
            skipsReappearLoad = false
            loadTOCDataOnly()
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
                    activeExtensions: ExtensionLibraryRepository.shared.installed,
                    selectedExtension: nil,
                    initialSearchQuery: title,
                    changeSourceTargetBook: localBook,
                    // Truyện chưa lưu (`localBook == nil`) vẫn chỉ tìm nguồn cùng loại với tiện ích đang xem.
                    kindScopePackageId: extensionPackageId,
                    onSourceChanged: {
                        navigateToChangeSource = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
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
            ErrorLinkCaption(link: detailErrorLink)
            HStack(spacing: 10) {
                Button("Thử lại") {
                    loadBookDetailOnly()
                }
                .buttonStyle(.bordered)
                ErrorLinkButton(link: detailErrorLink, presenting: $openingDetailErrorLink, style: .bordered)
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
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
                        sourceHost: resolvedHost,
                        iconUrl: ext?.iconUrl,
                        detail: detail,
                        cleanedDetailText: cleanedDetailText,
                        genres: genres,
                        desc: desc,
                        isDescExpanded: $isDescExpanded,
                        isLoadingDetail: isLoadingDetail,
                        detailErrorMessage: detailErrorMessage,
                        detailErrorLink: detailErrorLink,
                        openingErrorLink: $openingDetailErrorLink,
                        extensionPackageId: extensionPackageId,
                        localPath: ext?.localPath ?? "",
                        downloadUrl: ext?.downloadUrl ?? "",
                        configJson: ext?.configJson ?? "{}",
                        isTranslationEnabled: isTranslationEnabled,
                        prefersLandscapeCover: contentKind == .video,
                        onTranslateMetaIfNeeded: translateMetaIfNeeded,
                        onLoadBookDetailOnly: loadBookDetailOnly
                    )

                    if isLoadingDetail && title.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonView(width: 120, height: 18)
                            let columns = [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ]
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(0..<4) { _ in
                                    HStack(alignment: .top, spacing: 10) {
                                        SkeletonView(width: 48, height: 68)
                                        VStack(alignment: .leading, spacing: 6) {
                                            SkeletonView(width: 100, height: 12)
                                            SkeletonView(width: 60, height: 12)
                                        }
                                        Spacer(minLength: 0)
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
                                        .foregroundColor(.white)
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
                                    isTranslationEnabled: isTranslationEnabled,
                                    host: resolvedHost
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
                                    isTranslationEnabled: isTranslationEnabled,
                                    host: resolvedHost
                                )
                            }
                        }
                    }
                }
                // Không đệm trên: khối bìa đầu tab (`BookDetailHeroView`) nằm sát thanh tab.
                .padding(.bottom)
            } else {
                Spacer()
            }
        }
        .refreshable {
            await reloadBookData()
        }
    }

    internal func refreshLocalTOCSnapshots() {
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
                    appliedSearchQuery: appliedChapterSearchQuery,
                    totalChaps: totalChaps,
                    isTocAscending: $isTocAscending,
                    tocErrorMessage: tocErrorMessage,
                    tocErrorLink: tocErrorLink,
                    openingErrorLink: $openingTOCErrorLink,
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
                    onLoadMoreChapters: loadMoreChapters,
                    episodeNoun: episodeNoun,
                    isVideo: contentKind == .video
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
                                    Text(readActionTitle(isResuming: localBook != nil))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: localBook == nil ? "play.fill" : "book.fill")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(white: 0.22))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.35), lineWidth: 1))
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
                                .background(localBook?.isOnShelf == true ? Color(red: 0.15, green: 0.45, blue: 0.25) : Color(white: 0.22))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.35), lineWidth: 1))
                                .shadow(radius: 3)
                            }
                            .transition(.scale.combined(with: .opacity))

                            if let downloadTitle = downloadActionTitle {
                                Button(action: {
                                    isMenuExpanded = false
                                    prepareForTask(taskType: .download)
                                }) {
                                    HStack {
                                        Text(downloadTitle)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                        Image(systemName: "arrow.down.circle.fill")
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(white: 0.22))
                                    .foregroundColor(.white)
                                    .cornerRadius(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.35), lineWidth: 1))
                                    .shadow(radius: 3)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }

                            if showsExport {
                                Button(action: {
                                    isMenuExpanded = false
                                    prepareForTask(taskType: .exportTxt)
                                }) {
                                    HStack {
                                        Text(exportActionTitle)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                        Image(systemName: "square.and.arrow.up.fill")
                                            .resizable()
                                            .frame(width: 16, height: 16)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(white: 0.22))
                                    .foregroundColor(.white)
                                    .cornerRadius(20)
                                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.35), lineWidth: 1))
                                    .shadow(radius: 3)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }

                            if showsVideoDownloadsPill, let videoBookId = localBook?.bookId {
                                VideoDownloadsDeletePill(bookId: videoBookId) { isMenuExpanded = false }
                                    .transition(.scale.combined(with: .opacity))
                            }
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
                                .background(Color(white: 0.22))
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
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
        
        // Kiểm tra cache trước khi tải
        if let cachedEntry = BookDetailCacheManager.shared.getCache(for: actualBookId) {
            self.title = cachedEntry.title
            self.author = cachedEntry.author
            self.coverUrl = cachedEntry.coverUrl
            self.desc = cachedEntry.desc
            self.detail = cachedEntry.detail
            self.genres = cachedEntry.genres
            self.suggests = cachedEntry.suggests
            self.comments = cachedEntry.comments
            if !cachedEntry.host.isEmpty { self.host = cachedEntry.host }
            self.isLoadingDetail = false
            // Vẫn cần tải TOC
            loadTOCDataOnly()
            return
        }

        isLoadingDetail = true
        isLoadingTOC = true
        setDetailError("")
        setTOCError("")

        loadBookDetailOnly()
        loadTOCDataOnly()
    }

    private func loadBookDetailOnly() {
        if let ext = ext, !ext.localPath.isEmpty {
            isLoadingDetail = true
            setDetailError("")

            let snapshot = ExtensionExecutionSnapshot(
                packageId: ext.packageId,
                name: ext.name,
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                configJson: ext.configJson
            )
            let context = sourceRuntimeContext
            Task {
                do {
                    let detailResult = try await BookDetailLoader.shared.fetchDetail(snapshot: snapshot, url: initialDetailUrl, host: resolvedHost, context: context)

                    await MainActor.run {
                        self.title = detailResult.name
                        self.author = detailResult.author
                        self.coverUrl = detailResult.cover
                        self.desc = detailResult.description.cleanHTML()
                        self.detail = detailResult.detail
                        self.genres = detailResult.genres
                        self.suggests = detailResult.suggests
                        self.comments = detailResult.comments
                        if !detailResult.host.isEmpty { self.host = detailResult.host }

                        if let book = localBook {
                            let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                            let res = BookTransactionCoordinator.shared.updateBookMetadata(bookId: book.bookId, title: detailResult.name, author: detailResult.author, coverUrl: detailResult.cover, desc: savedDesc, host: detailResult.host, in: modelContext)
                            if case .failure(let err) = res {
                                self.setDetailError(err.localizedDescription)
                            }
                        }
                        self.isLoadingDetail = false
                        
                        // Lưu vào cache
                        let cacheEntry = BookDetailCacheManager.BookDetailCacheEntry(
                            title: detailResult.name,
                            author: detailResult.author,
                            coverUrl: detailResult.cover,
                            desc: detailResult.description.cleanHTML(),
                            detail: detailResult.detail,
                            genres: detailResult.genres,
                            suggests: detailResult.suggests,
                            comments: detailResult.comments,
                            host: detailResult.host,
                            timestamp: Date()
                        )
                        BookDetailCacheManager.shared.setCache(for: self.actualBookId, entry: cacheEntry)
                    }
                } catch {
                    await MainActor.run { self.setDetailError(error.localizedDescription, sourceError: error); self.isLoadingDetail = false }
                }
            }
        } else if let book = localBook {
            self.title = book.title; self.author = book.author; self.coverUrl = book.coverUrl
            self.desc = book.desc; self.detail = book.desc; self.host = book.host ?? ""; self.isLoadingDetail = false
        } else if let ext = ext {
            self.setDetailError("Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!")
            self.isLoadingDetail = false
        } else {
            self.setDetailError("Không tìm thấy tiện ích bóc tách của truyện này!")
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
            self.setTOCError("Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!")
            self.isLoadingTOC = false
            return
        } else {
            self.setTOCError("Không tìm thấy tiện ích bóc tách của truyện này!")
            self.isLoadingTOC = false
            return
        }

        guard let ext = ext, !ext.localPath.isEmpty else {
            setTOCError("Không tìm thấy tiện ích bóc tách!")
            self.isLoadingTOC = false
            return
        }

        isLoadingTOC = true
        setTOCError("")

        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let context = sourceRuntimeContext
        Task {
            do {
                let (firstPageChapters, pages) = try await BookDetailLoader.shared.fetchFirstPageTOC(snapshot: snapshot, url: initialDetailUrl, host: resolvedHost, context: context)

                let shouldPersistTOC = await MainActor.run {
                    self.isLoadingTOC = false
                    // "Tải thêm chương" đang/đã nối các trang sau vào `onlineChapters` (và tự ghi mục lục đầy đủ):
                    // gán lại bằng trang 1 sẽ làm danh sách đó mất các trang giữa. Nhưng `onlineChapters` rỗng thì
                    // bỏ qua = mục lục trắng, nên điều kiện phải có dữ liệu đang giữ.
                    if !self.onlineChapters.isEmpty, pages.count > 1,
                       self.isLoadingRemainingPages || self.remainingPagesLoaded {
                        if self.tocPages.isEmpty { self.tocPages = pages }
                        return false
                    }
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages
                    self.loadedRemainingPageCount = 0
                    // Chỉ có trang 1 ⇒ chưa đủ mục lục: mở lại nút "Tải thêm chương" thay vì giữ cờ đã đủ trang.
                    if pages.count > 1 { self.remainingPagesLoaded = false }
                    return self.localBook != nil
                }

                if shouldPersistTOC {
                    // Một hop MainActor cho cả ba giá trị, thay vì ba `await MainActor.run` rời rạc.
                    let saveContext: (bookId: String, ttsProtection: ProtectedTTSChapter?, snapshots: [ChapterMetadataSnapshot]) = await MainActor.run {
                        (self.actualBookId, self.activeTTSProtectedChapter, self.tocMetadata(from: firstPageChapters))
                    }
                    // Nguồn nhiều trang mà máy đã có mục lục: riêng trang 1 không đủ để đối chiếu (khớp theo url sẽ kéo
                    // các chương đầu trang 2 lên, hở chỉ số ở các trang chưa tải) ⇒ không ghi. Cập nhật đầy đủ do
                    // kéo làm mới, làm mới trong Reader và "Tải thêm chương" lo. Đọc số chương lỗi ⇒ coi như đã có (không ghi).
                    let storedCount = pages.count > 1 ? ((try? await ChapterStore.shared.countChapters(bookId: saveContext.bookId)) ?? 1) : 0
                    let didChangeTOC: Bool
                    if storedCount == 0 {
                        let saveResult = try await ChapterContentRepository.shared.saveChapterList(
                            bookId: saveContext.bookId,
                            createSnapshot: nil,
                            chapters: saveContext.snapshots,
                            mode: pages.count > 1 ? .upsertPage : .replaceFullTOC,
                            protectedTTSChapter: saveContext.ttsProtection
                        )
                        didChangeTOC = saveResult.inserted > 0 || saveResult.updated > 0 || saveResult.deleted > 0
                    } else {
                        didChangeTOC = false
                    }
                    await MainActor.run {
                        // Mục lục y nguyên ⇒ không đọc lại toàn bộ TOC chỉ để gán lại mảng `@State`.
                        if didChangeTOC || self.chapterSnapshots.isEmpty {
                            self.refreshLocalTOCSnapshots()
                        }
                        if let savedBook = self.refetchBook(bookId: saveContext.bookId) {
                            self.chaptersList = savedBook.chapters
                        } else {
                            self.syncChaptersList()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.setTOCError(error.localizedDescription, sourceError: error)
                    self.isLoadingTOC = false
                }
            }
        }
    }

    internal var activeTTSProtectedChapter: ProtectedTTSChapter? {
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
            await placeOnShelf(savedDesc: savedDesc)
        }
    }

    @discardableResult
    internal func createBookOnShelf(savedDesc: String) async -> Book? {
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
            self.setTOCError("Không thể tạo sách: \(error.localizedDescription)")
            return nil
        }
    }

    internal func scheduleBackgroundTitleTranslationIfNeeded(for targetBook: Book? = nil) {
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
                let res = BookTransactionCoordinator.shared.updateChapterTitleTranslations(bookId: targetBookId, translations: translatedMap, in: self.modelContext)
                switch res {
                case .success: self.syncChaptersList()
                case .failure(let err): AppLogger.shared.log("⚠️ [BookDetail] Failed to save chapter title translations: \(err.localizedDescription)")
                }
            }
        }
    }

    private func loadMoreChapters() {
        startBackgroundRemainingPagesLoading()
    }







}
