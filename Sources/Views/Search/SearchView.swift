import SwiftUI
import SwiftData

struct ExtensionItemResultWithExt: Identifiable {
    let id = UUID()
    let result: ExtensionItemResult
    let ext: Extension
}

struct SearchView: View {
    let activeExtensions: [Extension]
    let selectedExtension: Extension?
    let initialSearchQuery: String
    
    let changeSourceTargetBook: Book?
    /// "Thay đổi nguồn" ở Chi tiết truyện **chưa lưu** (không có `changeSourceTargetBook`): chỉ tìm nguồn cùng loại
    /// với tiện ích này — xem `sameKindScopePackageId` (`SearchView+KindFilter`).
    let kindScopePackageId: String?
    let onSourceChanged: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var changeSourceTargetResult: ExtensionItemResult? = nil
    @State private var changeSourceTargetExtension: Extension? = nil
    @State private var showingChangeSourceAlert = false
    @State private var isChangingSource = false
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? // lượt tìm đang chạy; tìm lại thì huỷ lượt cũ
    @State var searchAllSources = false
    @AppStorage("searchKindFilter") var searchKindFilter = "" // chip loại nội dung — `SearchView+KindFilter`
    @State private var searchResults: [ExtensionItemResultWithExt] = []
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State private var searchStatusMessage = ""
    @AppStorage("search_history") private var searchHistoryJSON = "[]"
    /// Bản đã decode của `searchHistoryJSON`, **chỉ** cho hiển thị (`matchingHistory`) — xem `ShelfSearchView`.
    @State private var displayedHistory: [String] = []

    /// Đường **ghi** đọc thẳng JSON, không qua cache: `onAppear` gọi `performSearch` → `saveQueryToHistory`
    /// có thể chạy trước `onChange(initial:)`; đọc cache rỗng lúc đó là ghi đè mất cả lịch sử.
    private var searchHistory: [String] {
        get { SearchHistoryStore.decode(searchHistoryJSON) }
        nonmutating set {
            displayedHistory = newValue
            searchHistoryJSON = SearchHistoryStore.encode(newValue)
        }
    }

    // Lịch sử hiển thị: lọc theo từ đang nhập khi có query, ngược lại hiện toàn bộ.
    private var matchingHistory: [String] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return displayedHistory }
        return displayedHistory.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var searchableExtensions: [Extension] {
        SearchExtensionScopePolicy.searchableExtensions(activeExtensions, kindFilter: searchKindFilter, changeSourcePackageId: sameKindScopePackageId)
    }

    init(activeExtensions: [Extension], selectedExtension: Extension?, initialSearchQuery: String = "", changeSourceTargetBook: Book? = nil, kindScopePackageId: String? = nil, onSourceChanged: (() -> Void)? = nil) {
        self.activeExtensions = activeExtensions
        self.selectedExtension = selectedExtension
        self.initialSearchQuery = initialSearchQuery
        self.changeSourceTargetBook = changeSourceTargetBook
        self.kindScopePackageId = kindScopePackageId
        self.onSourceChanged = onSourceChanged
        
        // Mặc định tìm tất cả nguồn nếu chưa chọn nguồn cụ thể hoặc khi đang đổi nguồn
        _searchAllSources = State(initialValue: selectedExtension == nil || changeSourceTargetBook != nil)
    }
    
    enum SourceSearchState {
        case searching
        case found(results: [ExtensionItemResult])
        case noResults
    }
    
    @State var sourceStates: [String: SourceSearchState] = [:]
    
    private var hasAnyResults: Bool {
        sourceStates.values.contains { state in
            if case .found(let results) = state, !results.isEmpty {
                return true
            }
            return false
        }
    }
    
    private var isAnySourceSearching: Bool {
        sourceStates.values.contains { state in
            if case .searching = state {
                return true
            }
            return false
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Thanh Tìm Kiếm
                searchBarView
                
                searchOptionsView
                
                Divider()
                
                searchStatusView
                
                if !searchAllSources && isSearching {
                    ProgressView("Đang tìm trên nguồn hiện tại...")
                        .frame(maxHeight: .infinity)
                } else if searchAllSources && !sourceStates.isEmpty {
                    searchAllSourcesResultsView
                } else if !searchAllSources && !searchResults.isEmpty {
                    singleSourceResultsView
                } else {
                    searchHistoryView
                }
            }
            .navigationTitle("Tìm Kiếm")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !initialSearchQuery.isEmpty && searchQuery.isEmpty {
                    searchQuery = initialSearchQuery
                    if selectedExtension != nil {
                        searchAllSources = false
                    }
                    performSearch()
                }
            }
            .onChange(of: searchHistoryJSON, initial: true) { _, json in
                displayedHistory = SearchHistoryStore.decode(json)
            }

            if isChangingSource {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("Đang thực hiện chuyển nguồn...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(20)
                .background(Color.black.opacity(0.75))
                .cornerRadius(12)
            }
        }
        .alert("Xác nhận thay đổi nguồn", isPresented: $showingChangeSourceAlert, presenting: changeSourceTargetResult) { result in
            Button("Đồng ý", role: .none) {
                if let ext = changeSourceTargetExtension {
                    isChangingSource = true
                    Task {
                        await executeSourceChange(to: result, ext: ext)
                        await MainActor.run {
                            isChangingSource = false
                        }
                    }
                }
            }
            Button("Hủy", role: .cancel) {}
        } message: { result in
            let extName = changeSourceTargetExtension?.name ?? "Nguồn mới"
            let oldBookId = changeSourceTargetBook?.bookId ?? ""
            let isPlayingTTS = (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget) && TTSManager.shared.playingBookId == oldBookId
            if isPlayingTTS {
                Text("Bạn đang nghe phát âm thanh cho truyện này. Nguồn mới '\(extName)' sẽ được thêm vào kệ sách mà không xóa nguồn cũ để quá trình nghe không bị gián đoạn.")
            } else {
                Text("Bạn có chắc chắn muốn thay đổi nguồn cho truyện sang '\(extName)' không?\nSách cũ trên kệ sẽ bị xóa và các cài đặt dịch riêng, từ điển riêng cũng như tiến độ đọc chương sẽ được chuyển qua sách mới.")
            }
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm truyện hoặc tác giả...", text: $searchQuery, onCommit: performSearch)
                    .textInputAutocapitalization(.none)
                    // Thanh trên bàn phím nhận ra ô tìm kiếm qua `returnKeyType == .search` để ẩn nhóm `aa…AA`.
                    .submitLabel(.search)
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        searchResults.removeAll()
                        sourceStates.removeAll()
                        searchStatusMessage = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            
            Button(action: performSearch) {
                Text("Tìm")
                    .bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var searchStatusView: some View {
        if !searchStatusMessage.isEmpty {
            Text(searchStatusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
        }
    }
    
    @ViewBuilder
    private var searchAllSourcesResultsView: some View {
        if !hasAnyResults && !isAnySourceSearching {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Không tìm thấy truyện nào trên các nguồn")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxHeight: .infinity)
        } else {
            let sortedSources = searchableExtensions.sorted(by: { $0.name < $1.name })
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sortedSources, id: \.packageId) { ext in
                        if let state = sourceStates[ext.packageId] {
                            Group {
                                switch state {
                                case .searching:
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(ext.name)
                                                .font(.headline)
                                                .fontWeight(.bold)
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                        .padding(.horizontal)
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 16) {
                                                ForEach(0..<3, id: \.self) { _ in
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Color.gray.opacity(0.1)
                                                            .frame(width: 90, height: 125)
                                                            .cornerRadius(6)
                                                        
                                                        Color.gray.opacity(0.1)
                                                            .frame(width: 90, height: 12)
                                                            .cornerRadius(3)
                                                        
                                                        Color.gray.opacity(0.1)
                                                            .frame(width: 60, height: 10)
                                                            .cornerRadius(3)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                        }
                                        .redacted(reason: .placeholder)
                                    }
                                    
                                case .found(let results):
                                    let displayResults = changeSourceTargetBook != nil ? results.filter { !isSameBookSource(result: $0, ext: ext) } : results
                                    if !displayResults.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(ext.name)
                                                    .font(.headline)
                                                    .fontWeight(.bold)
                                                
                                                Spacer()
                                                
                                                NavigationLink(destination: SearchView(
                                                    activeExtensions: sortedSources,
                                                    selectedExtension: ext,
                                                    initialSearchQuery: searchQuery
                                                )) {
                                                    HStack(spacing: 4) {
                                                        Text("Xem thêm")
                                                            .foregroundColor(.white)
                                                        Image(systemName: "chevron.right")
                                                            .foregroundColor(.white)
                                                    }
                                                    .font(.subheadline)
                                                }
                                            }
                                            .padding(.horizontal)
                                            
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 16) {
                                                    ForEach(displayResults, id: \.link) { result in
                                                        if changeSourceTargetBook != nil {
                                                            Button(action: {
                                                                changeSourceTargetResult = result
                                                                changeSourceTargetExtension = ext
                                                                showingChangeSourceAlert = true
                                                            }) {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    searchResultCover(result, ext: ext, width: 90, height: 125)
                                                                    
                                                                    Text(DisplayTextFormatter.titleCase(translateIfNeeded(result.name)))
                                                                        .font(.caption)
                                                                        .fontWeight(.semibold)
                                                                        .foregroundColor(.primary)
                                                                        .lineLimit(2)
                                                                        .multilineTextAlignment(.leading)
                                                                        .frame(width: 90, alignment: .leading)
                                                                    
                                                                    // let authorText = !result.author.isEmpty ? result.author : "Không rõ tác giả"
                                                                    // Text(translateIfNeeded(authorText))
                                                                    //     .font(.system(size: 10))
                                                                    //     .foregroundColor(.secondary)
                                                                    //     .lineLimit(1)
                                                                    //     .frame(width: 90, alignment: .leading)
                                                                }
                                                            }
                                                            .buttonStyle(.plain)
                                                        } else {
                                                            NavigationLink(destination: BookDetailView(
                                                                bookId: "\(ext.name.lowercased())_\(result.link)",
                                                                extensionPackageId: ext.packageId,
                                                                initialDetailUrl: result.link,
                                                                sourceName: ext.name,
                                                                initialHost: result.host
                                                            )) {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    searchResultCover(result, ext: ext, width: 90, height: 125)
                                                                    
                                                                    Text(DisplayTextFormatter.titleCase(translateIfNeeded(result.name)))
                                                                        .font(.caption)
                                                                        .fontWeight(.semibold)
                                                                        .foregroundColor(.primary)
                                                                        .lineLimit(2)
                                                                        .multilineTextAlignment(.leading)
                                                                        .frame(width: 90, alignment: .leading)
                                                                    
                                                                    // let authorText = !result.author.isEmpty ? result.author : "Không rõ tác giả"
                                                                    // Text(translateIfNeeded(authorText))
                                                                    //     .font(.system(size: 10))
                                                                    //     .foregroundColor(.secondary)
                                                                    //     .lineLimit(1)
                                                                    //     .frame(width: 90, alignment: .leading)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal)
                                            }
                                        }
                                    }
                                    
                                case .noResults:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
        }
    }
    
    @ViewBuilder
    private var singleSourceResultsView: some View {
        let displayResults = changeSourceTargetBook != nil ? searchResults.filter { !isSameBookSource(result: $0.result, ext: $0.ext) } : searchResults
        List(displayResults) { item in
            if changeSourceTargetBook != nil {
                Button(action: {
                    changeSourceTargetResult = item.result
                    changeSourceTargetExtension = item.ext
                    showingChangeSourceAlert = true
                }) {
                    HStack(spacing: 12) {
                        searchResultCover(item.result, ext: item.ext, width: 50, height: 70)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.result.name)))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            let descText = !item.result.description.isEmpty ? item.result.description : (!item.result.content.isEmpty ? item.result.content : item.result.author)
                            Text(translateIfNeeded(descText))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Text(item.ext.name)
                                .font(.system(size: 9))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(destination: BookDetailView(
                    bookId: "\(item.ext.name.lowercased())_\(item.result.link)",
                    extensionPackageId: item.ext.packageId,
                    initialDetailUrl: item.result.link,
                    sourceName: item.ext.name,
                    initialHost: item.result.host
                )) {
                    HStack(spacing: 12) {
                        searchResultCover(item.result, ext: item.ext, width: 50, height: 70)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DisplayTextFormatter.titleCase(translateIfNeeded(item.result.name)))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .lineLimit(2)
                            
                            let descText = !item.result.description.isEmpty ? item.result.description : (!item.result.content.isEmpty ? item.result.content : item.result.author)
                            Text(translateIfNeeded(descText))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            Text(item.ext.name)
                                .font(.system(size: 9))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
    }
    
    @ViewBuilder
    private var searchHistoryView: some View {
        if !matchingHistory.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Lịch sử tìm kiếm")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: {
                        searchHistory = []
                    }) {
                        Text("Xóa tất cả")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(matchingHistory, id: \.self) { item in
                            HStack(spacing: 12) {
                                Button(action: {
                                    searchQuery = item
                                    performSearch()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "clock")
                                            .foregroundColor(.secondary)
                                        
                                        Text(item)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    var currentHistory = searchHistory
                                    currentHistory.removeAll { $0 == item }
                                    searchHistory = currentHistory
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.secondary)
                                        .padding(8)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(.top)
        } else {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("Nhập từ khóa để tìm kiếm truyện")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxHeight: .infinity)
        }
    }
    
    private func isSameBookSource(result: ExtensionItemResult, ext: Extension) -> Bool {
        guard let target = changeSourceTargetBook else { return false }
        
        let resultBookId = BookIdUtils.make(extensionPackageId: ext.packageId, detailUrl: result.link)
        if resultBookId == target.bookId {
            return true
        }
        
        if !target.extensionPackageId.isEmpty && target.extensionPackageId == ext.packageId {
            if target.detailUrl == result.link || normalizeUrlForSearch(target.detailUrl) == normalizeUrlForSearch(result.link) {
                return true
            }
        }
        
        return false
    }

    private func normalizeUrlForSearch(_ url: String) -> String {
        guard !url.isEmpty else { return "" }
        var str = url.lowercased()
        if str.hasPrefix("http://") {
            str = String(str.dropFirst(7))
        } else if str.hasPrefix("https://") {
            str = String(str.dropFirst(8))
        }
        if str.hasSuffix("/") {
            str = String(str.dropLast())
        }
        return str
    }

    private func executeSourceChange(to result: ExtensionItemResult, ext: Extension) async {
        guard let oldBook = changeSourceTargetBook else { return }
        
        let oldBookId = oldBook.bookId
        let newBookId = UUID().uuidString
        let oldChapterIndex = oldBook.currentChapterIndex
        let isPlayingTTS = (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget) && TTSManager.shared.playingBookId == oldBookId
        
        do {
            try BookSourceMigrator.ensureSameContentKind(oldPackageId: oldBook.extensionPackageId, newPackageId: ext.packageId)
            let path = ext.localPath
            // Ngữ cảnh theo `newBookId`: nguồn Legado ghi trạng thái theo đúng id của sách sắp tạo.
            let context = SourceRuntimeContext(bookId: newBookId, bookUrl: result.link, bookName: result.name, bookAuthor: result.author, isInteractive: true)
            let detailResult = try await SourceRuntime.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: result.link, host: ExtensionHostResolver.nonEmpty(result.host) ?? ext.sourceUrl, configJson: ext.configJson, context: context)
            // Host sách: host detail → host item tìm kiếm → source (detail thường không trả host).
            let bookHost = ExtensionHostResolver.nonEmpty(detailResult.host) ?? ExtensionHostResolver.nonEmpty(result.host) ?? ext.sourceUrl
            // Cùng quy tắc với BookDetail (trang đầu = `pages.first`). Mục lục rỗng/trang rỗng ⇒ ném lỗi trước khi tạo sách
            // mới, nên sách cũ và chương đã tải không bị xoá.
            let snapshot = ExtensionExecutionSnapshot(packageId: ext.packageId, name: ext.name, localPath: path, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
            let tocChapters = try await BookDetailLoader.shared.fetchFullTOC(snapshot: snapshot, url: result.link, host: bookHost, context: context).chapters

            let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(detailResult.detail.cleanHTML())"
            let initialChapterIndex = min(oldChapterIndex, max(0, tocChapters.count - 1))
            let initialChapterTitle = tocChapters.isEmpty ? "" : tocChapters[initialChapterIndex].name

            let createSnapshot = TOCBookCreateSnapshot(
                bookId: newBookId,
                title: detailResult.name,
                author: detailResult.author,
                coverUrl: detailResult.cover,
                desc: savedDesc,
                detailUrl: result.link,
                sourceName: ext.name,
                sourceUrl: ext.sourceUrl,
                extensionPackageId: ext.packageId,
                currentChapterIndex: initialChapterIndex,
                currentChapterPage: 0,
                currentChapterTitle: initialChapterTitle,
                isOnShelf: oldBook.isOnShelf,
                isHistory: oldBook.isHistory,
                host: bookHost
            )

            let chapterSnapshots = tocChapters.enumerated().map { index, item in
                ChapterMetadataSnapshot(title: item.name, url: item.url, index: index, host: item.host, isSection: item.isSection)
            }

            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: newBookId,
                createSnapshot: createSnapshot,
                chapters: chapterSnapshots,
                mode: .replaceFullTOC
            )

            // Giữ lại nội dung các chương đã tải từ nguồn cũ
            await BookSourceMigrator.shared.migrateCachedChapters(
                oldBookId: oldBookId,
                newBookId: newBookId,
                newChapters: chapterSnapshots
            )

            // Di chuyển từ điển riêng, rule riêng, session AI và cấu hình dịch
            await BookSourceMigrator.shared.migrateTranslationFiles(
                oldBookId: oldBookId,
                newBookId: newBookId,
                isPlayingTTS: isPlayingTTS
            )
            await BookSourceMigrator.shared.migrateMetadataAndSettings(
                oldBookId: oldBookId,
                newBookId: newBookId,
                isPlayingTTS: isPlayingTTS
            )

            await MainActor.run {
                if !isPlayingTTS {
                    let delRes = BookTransactionCoordinator.shared.deleteBook(bookId: oldBookId, in: modelContext)
                    if case .failure(let err) = delRes {
                        searchStatusMessage = "Lỗi xóa sách cũ: \(err.localizedDescription)"
                    }

                    TranslateUtils.clearCache()
                    TranslationManager.shared.clearBookDictCache(for: oldBookId)
                }

                TranslationManager.shared.clearBookDictCache(for: newBookId)

                if isPlayingTTS {
                    ToastManager.shared.show(message: "Đã thêm nguồn mới '\(ext.name)' vào kệ sách!", type: .success)
                }

                // Gửi `ShelfTab.rawValue` chứ không phải số trần — xem `ShelfTab`.
                let targetShelfTab = (createSnapshot.isOnShelf ? ShelfTab.shelf : ShelfTab.history).rawValue
                NotificationCenter.default.post(
                    name: NSNotification.Name("sourceChangedNavigateToShelf"),
                    object: nil,
                    userInfo: ["shelfTab": targetShelfTab]
                )

                onSourceChanged?()
            }

            if !isPlayingTTS {
                await BookSourceMigrator.shared.cleanupOldBookStorage(oldBookId: oldBookId)
            }
        } catch {
            AppLogger.shared.log("❌ Lỗi đổi nguồn truyện: \(error.localizedDescription)")
            await MainActor.run { searchStatusMessage = "Lỗi đổi nguồn: \(error.localizedDescription)" }
        }
    }
    
    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }

    private func saveQueryToHistory(_ query: String) {
        searchHistory = SearchHistoryStore.addQuery(query, to: searchHistory)
    }

    func performSearch() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        searchTask?.cancel()
        saveQueryToHistory(trimmedQuery)
        
        isSearching = true
        searchResults.removeAll()
        sourceStates.removeAll()
        
        if searchAllSources {
            let extensionsToSearch = searchableExtensions
            guard !extensionsToSearch.isEmpty else {
                isSearching = false
                searchStatusMessage = "Không có nguồn nào hoạt động."
                return
            }
            
            searchStatusMessage = "Đang tìm kiếm trên \(extensionsToSearch.count) nguồn..."
            
            // Khởi tạo trạng thái đang tìm kiếm cho tất cả các nguồn
            var initialStates: [String: SourceSearchState] = [:]
            for ext in extensionsToSearch {
                initialStates[ext.packageId] = .searching
            }
            sourceStates = initialStates
            
            // Tiện ích JS song song không giới hạn như cũ; nguồn Legado qua cửa sổ trượt (`LegadoSearchScheduler`).
            let targets = extensionsToSearch.map { LegadoSearchScheduler.Target($0) }
            searchTask = Task {
                await LegadoSearchScheduler.searchAll(targets, query: trimmedQuery) { packageId, results in
                    await MainActor.run {
                        guard !Task.isCancelled else { return } // lượt cũ không ghi đè trạng thái lượt mới
                        let cleanResults = results.map { filterAndDeduplicate($0) } ?? []
                        let state: SourceSearchState = cleanResults.isEmpty ? .noResults : .found(results: cleanResults)
                        self.sourceStates[packageId] = state
                    }
                }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isSearching = false
                    let foundCount = sourceStates.values.reduce(0) { count, state in
                        if case .found(let results) = state {
                            return count + results.count
                        }
                        return count
                    }
                    self.searchStatusMessage = "Tìm thấy \(foundCount) truyện trên các nguồn."
                }
            }
        } else {
            guard let ext = selectedExtension else {
                isSearching = false
                searchStatusMessage = "Vui lòng chọn một nguồn trước."
                return
            }
            
            searchStatusMessage = "Đang tìm trên nguồn \(ext.name)..."
            ExtensionTransactionCoordinator.shared.markUsed(packageId: ext.packageId) // chỉ tìm MỘT nguồn mới tính "đã dùng"

            searchTask = Task {
                do {
                    let results = try await SourceRuntime.shared.search(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        query: trimmedQuery,
                        page: 1,
                        configJson: ext.configJson
                    )
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        let cleanResults = filterAndDeduplicate(results)
                        self.searchResults = cleanResults.map { ExtensionItemResultWithExt(result: $0, ext: ext) }
                        self.isSearching = false
                        self.searchStatusMessage = "Tìm thấy \(cleanResults.count) truyện trên nguồn \(ext.name)."
                    }
                } catch {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.isSearching = false
                        self.searchStatusMessage = "Lỗi khi tìm kiếm: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

