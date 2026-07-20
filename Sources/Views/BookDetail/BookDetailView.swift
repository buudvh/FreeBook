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
    
    // Tìm sách local trong database
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
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
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
    
    private func translateTitleIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }
    
    private func translateChapterTitleIfNeeded(_ chap: Chapter) -> String {
        if isTranslationEnabled && TranslateUtils.containsChinese(chap.title) {
            return TranslateUtils.translateChapterTitle(chap.title, bookId: bookId)
        }
        return chap.title
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !detailErrorMessage.isEmpty && title.isEmpty {
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
                } else {
                    // Custom Tab Bar cố định ở đầu trang
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
                    
                    Divider()
                    
                    TabView(selection: $selectedTab) {
                        // TAB CHI TIẾT
                        ScrollView {
                            if renderedTab == 0 {
                            VStack(alignment: .leading, spacing: 16) {
                                if isLoadingDetail && title.isEmpty {
                                    // SƯỜN DETAIL LOADING (SKELETON PLACEHOLDER)
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
                                        BookCoverView(bookId: bookId, coverUrl: coverUrl, width: 100, height: 140)
                                            .cornerRadius(8)
                                            .shadow(radius: 2)
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(translateMetaIfNeeded(title))
                                                .font(.title3)
                                                .fontWeight(.bold)
                                                .lineLimit(3)
                                            
                                            Text("Tác giả: \(TranslateUtils.translateAuthorHanViet(author))")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            
                                            // Hiển thị nguồn cải tiến (icon + tên nguồn, bỏ chữ "Nguồn:")
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
                                            
                                            // Genres chip list
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
                                    
                                    // Phần mô tả giới thiệu
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
                                
                                // 2. PHẦN TRUYỆN GỢI Ý (SUGGESTS)
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
                                
                                // 3. PHẦN BÌNH LUẬN (COMMENTS)
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
                        .tag(0)
                        
                        // TAB MỤC LỤC
                        VStack(spacing: 0) {
                            if renderedTab == 1 {
                            let totalChaps = localBook?.chapters.count ?? onlineChapters.count
                            
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
                                        Text("Danh sách chương (\(totalChaps))")
                                            .font(.headline)
                                        
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
                                            if let book = localBook {
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
                                            
                                            // Nút tải thêm chương phân trang
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
                        bookId: bookId,
                        extensionPackageId: extensionPackageId,
                        chapterIndex: route.chapterIndex,
                        // Keep the online TOC as a bootstrap fallback while
                        // SwiftData @Query catches up. Reader still prefers
                        // its direct local Book snapshot when one exists.
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
                destination: BookDictionaryView(bookId: bookId, bookName: title),
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
            
            // Loading remaining pages overlay
            if isLoadingRemainingPages {
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
                    
                    // Nút Back/Quay lại hủy tác vụ đang chạy bất đồng bộ
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
            
            // 5. NÚT HÀNH ĐỘNG NỔI (FAB) DROPDOWN NGƯỢC LÊN (chỉ hiển thị khi đã tải xong chương và totalChaps > 0)
            let totalChaps = localBook?.chapters.count ?? onlineChapters.count
            if totalChaps > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if isMenuExpanded {
                                // Nút 1: Đọc tiếp / Đọc ngay
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
                                
                                // Nút 2: Thêm kệ / Xóa kệ
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
                                
                                // Nút 3: Tải truyện
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
                                
                                // Nút 4: Xuất TXT
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
                            
                            // Nút tròn chính (Toggle)
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
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $selectedBookForTask) { book in
            TaskOptionsSheet(book: book, taskType: selectedTaskType)
        }
        .fullScreenCover(isPresented: $showingBypassBrowser) {
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
                        
                        // Trì hoãn push để tránh xung đột với dismiss animation của fullScreenCover
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            navigateToImportedBook = true
                        }
                    }
                }
            )
        }
    }
    
    private func loadBookData() {
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
        
        if let book = localBook {
            book.isOnShelf = true
            try? modelContext.save()
            
            // Tải toàn bộ chương nếu chưa được nạp đầy đủ
            if tocPages.count > 1 && !remainingPagesLoaded {
                isLoadingRemainingPages = true
                loadingTask = Task {
                    do {
                        let remainingChaps = try await loadAllRemainingPages()
                        try Task.checkCancellation()
                        await MainActor.run {
                            self.onlineChapters.append(contentsOf: remainingChaps)
                            let startIdx = book.chapters.count
                            for (index, item) in remainingChaps.enumerated() {
                                let chapId = "\(bookId)_\(item.url)"
                                let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx + index)
                                newChap.book = book
                                modelContext.insert(newChap)
                            }
                            try? modelContext.save()
                            self.syncChaptersList()
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
        } else {
            if tocPages.count > 1 && !remainingPagesLoaded {
                isLoadingRemainingPages = true
                loadingTask = Task {
                    do {
                        let remainingChaps = try await loadAllRemainingPages()
                        try Task.checkCancellation()
                        await MainActor.run {
                            self.onlineChapters.append(contentsOf: remainingChaps)
                            createBookOnShelf(savedDesc: savedDesc)
                            self.remainingPagesLoaded = true
                            self.isLoadingRemainingPages = false
                            self.loadingTask = nil
                        }
                    } catch {
                        if !Task.isCancelled {
                            await MainActor.run {
                                self.tocErrorMessage = "Lỗi tải thêm chương khi lưu kệ: \(error.localizedDescription)"
                                self.isLoadingRemainingPages = false
                                createBookOnShelf(savedDesc: savedDesc)
                                self.loadingTask = nil
                            }
                        }
                    }
                }
            } else {
                createBookOnShelf(savedDesc: savedDesc)
            }
        }
    }
    
    private func createBookOnShelf(savedDesc: String) {
        let newBook = Book(
            bookId: bookId,
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
    
    private func loadMoreChapters() {
        guard !isLoadingRemainingPages else { return }
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
                            let chapId = "\(bookId)_\(item.url)"
                            let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx + index)
                            newChap.book = book
                            modelContext.insert(newChap)
                        }
                        try? modelContext.save()
                        self.syncChaptersList()
                    }
                    
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
    
    private func startReading(at chapterIndex: Int) {
        let route = ReaderRoute(chapterIndex: chapterIndex)
        if tocPages.count > 1 && !remainingPagesLoaded {
            // Điều hướng người dùng sang màn hình đọc ngay lập tức không bắt chờ
            self.readerRoute = route
            
            // Nếu đã có tác vụ đang chạy thì không chạy trùng lặp
            guard loadingTask == nil else { return }
            
            isLoadingRemainingPages = true
            tocErrorMessage = ""
            
            loadingTask = Task {
                do {
                    let remainingChaps = try await loadAllRemainingPages()
                    try Task.checkCancellation()
                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: remainingChaps)
                        
                        if let book = localBook {
                            let existingUrls = Set(book.chapters.map { $0.url })
                            var startIdx = book.chapters.count
                            for item in remainingChaps {
                                if !existingUrls.contains(item.url) {
                                    let chapId = "\(bookId)_\(item.url)"
                                    let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx)
                                    newChap.book = book
                                    modelContext.insert(newChap)
                                    startIdx += 1
                                }
                            }
                            try? modelContext.save()
                            self.syncChaptersList()
                        }
                        
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
        } else {
            self.readerRoute = route
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
                                let chapId = "\(bookId)_\(item.url)"
                                let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx + index)
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
        if book.isHistory {
            book.isOnShelf = false
            try? modelContext.save()
        } else {
            UserDefaults.standard.removeObject(forKey: "lastChapterIndex_\(book.bookId)")
            UserDefaults.standard.removeObject(forKey: "lastParagraphIndex_\(book.bookId)")
            if TTSManager.shared.playingBookId == book.bookId {
                TTSManager.shared.stop()
            }
            modelContext.delete(book)
            try? modelContext.save()
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
                if chapter.content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    chapter.isCached = true
                }
            } else {
                let newChapter = Chapter(
                    id: "\(book.bookId)_\(item.url.isEmpty ? "index-\(index)" : item.url)",
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
            TranslateUtils.translateChapterTitle(chap.name, bookId: bookId).localizedCaseInsensitiveContains(chapterSearchQuery)
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
