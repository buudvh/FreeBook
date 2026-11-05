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
    let isPresentedAsSheet: Bool // gốc sheet `java.searchBook` của Legado ⇒ hiện tiêu đề trái; còn lại là trang đẩy vào
    
    @Environment(\.modelContext) var modelContext

    @State private var changeSourceTargetResult: ExtensionItemResult? = nil
    @State private var changeSourceTargetExtension: Extension? = nil
    @State private var showingChangeSourceAlert = false
    @State var isChangingSource = false
    /// Bước đang chạy của lượt đổi nguồn ("Đang chép chương đã tải 350/2134…"); rỗng = câu mặc định.
    @State var sourceChangeStatus = ""
    
    @State private var searchQuery = ""
    @State var isSearching = false
    @State var searchTask: Task<Void, Never>? // lượt tìm đang chạy; tìm lại thì huỷ lượt cũ
    /// Tải thêm trang khi tìm trong một nguồn (`SearchView+Paging`).
    @State var searchPaging = SearchPagingState()
    @State var searchAllSources = false
    @AppStorage("searchKindFilter") var searchKindFilter = "" // chip loại nội dung — `SearchView+KindFilter`
    @State var searchResults: [ExtensionItemResultWithExt] = []
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State var searchStatusMessage = ""
    /// Lỗi tìm/đổi nguồn kèm link "Mở link lỗi" (`SearchView+ErrorLink`) và trình duyệt đang mở cho nó.
    @State var statusErrorLink: StatusErrorLink?
    @State private var openingErrorLink: SourceErrorLink?
    /// Scope đang mở sheet "Kiểu hiển thị" (chỉ có khi tìm trong một nguồn).
    @State private var layoutSheetScope: BookListLayoutScope?
    /// Sheet "Bộ lọc" của nguồn đang tìm (chỉ khi tìm trong một nguồn); áp dụng ⇒ tìm lại từ trang 1.
    @State private var showingFilterSheet = false
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

    /// `includeNsfw` quan sát được: tắt NSFW lúc đang xem kết quả "tìm mọi nguồn" thì nhóm của nguồn NSFW biến mất ngay.
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    private var searchableExtensions: [Extension] {
        SearchExtensionScopePolicy.searchableExtensions(
            activeExtensions,
            kindFilter: searchKindFilter,
            changeSourcePackageId: sameKindScopePackageId,
            includeNsfw: includeNsfw
        )
    }

    init(activeExtensions: [Extension], selectedExtension: Extension?, initialSearchQuery: String = "", changeSourceTargetBook: Book? = nil, kindScopePackageId: String? = nil, onSourceChanged: (() -> Void)? = nil, isPresentedAsSheet: Bool = false) {
        self.activeExtensions = activeExtensions
        self.selectedExtension = selectedExtension
        self.initialSearchQuery = initialSearchQuery
        self.changeSourceTargetBook = changeSourceTargetBook
        self.kindScopePackageId = kindScopePackageId
        self.onSourceChanged = onSourceChanged
        self.isPresentedAsSheet = isPresentedAsSheet
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
                    singleSourceLoadingView
                } else if searchAllSources && !sourceStates.isEmpty {
                    searchAllSourcesResultsView
                } else if !searchAllSources && !searchResults.isEmpty {
                    singleSourceResultsView
                } else {
                    searchHistoryView
                }
            }
            .pageTitle("Tìm Kiếm", style: isPresentedAsSheet ? .leading : .centered)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let scope = singleSourceLayoutScope {
                        Button {
                            layoutSheetScope = scope
                        } label: {
                            Image(systemName: BookListLayoutPreferences.shared.layout(for: scope).mode.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("Kiểu hiển thị")
                    }
                }
            }
            .sheet(item: $layoutSheetScope) { scope in
                BookListLayoutSheet(scope: scope)
            }
            .sheet(isPresented: $showingFilterSheet) {
                if let packageId = selectedExtension?.packageId {
                    ExtensionFilterSheet(packageId: packageId, scope: .pluginScript("search")) { _ in performSearch() }
                }
            }
            .errorLinkBrowser(link: $openingErrorLink, packageId: statusErrorLink?.packageId) { retryStatusError() }
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
            .onChange(of: includeNsfw) { _, isOn in
                if !isOn { dropHiddenNsfwSources() }
            }
            // Tìm trong **một** nguồn NSFW (không phải đổi nguồn) ⇒ đóng khi tắt NSFW; tìm mọi nguồn thì gỡ nhóm.
            .closesWhenNsfwHidden(
                packageId: selectedExtension?.packageId,
                isEnabled: !searchAllSources && changeSourceTargetBook == nil && kindScopePackageId == nil
            )

            if isChangingSource {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text(sourceChangeStatus.isEmpty ? "Đang thực hiện chuyển nguồn..." : sourceChangeStatus)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
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
    
    /// Ô tìm viên thuốc kiểu mục lục — bấm Tìm trên bàn phím để tìm (không còn nút "Tìm"; thanh trên bàn phím nhận ra
    /// ô tìm qua `returnKeyType == .search` để ẩn nhóm `aa…AA`). Tìm trong một nguồn có bộ lọc ⇒ icon lọc bên phải.
    @ViewBuilder
    private var searchBarView: some View {
        HStack(spacing: 2) {
            ChapterTOCSearchField(
                text: $searchQuery,
                placeholder: "Tìm truyện hoặc tác giả",
                palette: .system,
                onSubmit: performSearch,
                onClear: clearSearch
            )
            if !searchAllSources, let ext = selectedExtension {
                // Chỉ các mục `config` mà `search` (cùng các file nó `load`) dùng tới.
                ExtensionFilterButton(
                    ext: ExtensionLibraryRepository.shared.installedExtension(packageId: ext.packageId),
                    scope: .pluginScript("search"),
                    style: .inline
                ) { showingFilterSheet = true }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func clearSearch() {
        resetSearchPaging()
        searchResults.removeAll()
        sourceStates.removeAll()
        searchStatusMessage = ""
    }
    
    @ViewBuilder
    private var searchStatusView: some View {
        if !searchStatusMessage.isEmpty {
            // Câu lỗi có link ⇒ dải gọn: thêm dòng URL xám + la bàn "Mở link lỗi" bên phải.
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(searchStatusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ErrorLinkCaption(link: currentStatusErrorLink)
                }
                Spacer(minLength: 0)
                ErrorLinkButton(link: currentStatusErrorLink, presenting: $openingErrorLink, style: .icon)
            }
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
                                                                    Self.searchResultCover(result, ext: ext, width: 90, height: 125)
                                                                    
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
                                                            // Nguồn video ⇒ nút mở màn xem phim; còn lại ⇒ link Chi tiết như cũ.
                                                            ContentDetailLink(
                                                                item: result,
                                                                packageId: ext.packageId,
                                                                sourceName: ext.name,
                                                                detailBookId: "\(ext.name.lowercased())_\(result.link)"
                                                            ) {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    Self.searchResultCover(result, ext: ext, width: 90, height: 125)
                                                                    
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
    
    /// Kiểu hiển thị khi tìm trong **một** nguồn: theo loại của nguồn đang tìm, cùng phạm vi với Khám phá của nguồn đó.
    /// `nil` khi tìm mọi nguồn hoặc chưa chọn nguồn (không có nút Kiểu hiển thị).
    private var singleSourceLayoutScope: BookListLayoutScope? {
        guard !searchAllSources, let ext = selectedExtension else { return nil }
        return BookListLayoutScope(kind: SearchExtensionScopePolicy.kind(of: ext))
    }

    /// Đang tìm trong một nguồn: kiểu lưới hiện khung chờ dạng lưới (như màn Thể loại), kiểu danh sách giữ vòng xoay.
    @ViewBuilder
    private var singleSourceLoadingView: some View {
        let scope = singleSourceLayoutScope ?? .text
        let layout = BookListLayoutPreferences.shared.layout(for: scope)
        if layout.mode.isGrid {
            DiscoverySkeletonGridView(
                columns: layout.columns,
                aspectRatio: scope.coverAspectRatio,
                showsText: layout.mode == .grid
            )
            .frame(maxHeight: .infinity)
        } else {
            ProgressView("Đang tìm trên nguồn hiện tại...")
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var singleSourceResultsView: some View {
        let displayResults = changeSourceTargetBook != nil ? searchResults.filter { !isSameBookSource(result: $0.result, ext: $0.ext) } : searchResults
        let scope = singleSourceLayoutScope ?? .text
        // Đọc trong `body` ⇒ sheet "Kiểu hiển thị" hay màn Cài đặt ghi là kết quả vẽ lại theo kiểu mới.
        SearchSingleSourceResultsView(
            items: displayResults,
            layout: BookListLayoutPreferences.shared.layout(for: scope),
            aspectRatio: scope.coverAspectRatio,
            isTranslationEnabled: isTranslationEnabled,
            isChangingSource: changeSourceTargetBook != nil,
            onChangeSource: { item in
                changeSourceTargetResult = item.result
                changeSourceTargetExtension = item.ext
                showingChangeSourceAlert = true
            },
            footer: singleSourceFooterPhase(shownCount: displayResults.count, noun: scope.itemNoun),
            onLoadMore: { loadMoreSearchResults() }, onRetry: { retryLoadMoreSearchResults() }
        )
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
                            .foregroundColor(.red)
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

    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }

    private var foundCountMessage: String {
        let foundCount = sourceStates.values.reduce(0) { count, state in
            if case .found(let results) = state {
                return count + results.count
            }
            return count
        }
        return "Tìm thấy \(foundCount) truyện trên các nguồn."
    }

    /// Tắt NSFW lúc đang ở kết quả "tìm mọi nguồn": gỡ nguồn NSFW khỏi `sourceStates` (số đếm, trạng thái rỗng, vòng
    /// xoay "đang tìm" đều tính lại); kết quả của chúng về muộn bị bỏ qua.
    private func dropHiddenNsfwSources() {
        guard searchAllSources, !sourceStates.isEmpty else { return }
        let kept = Set(searchableExtensions.map(\.packageId))
        sourceStates = sourceStates.filter { kept.contains($0.key) }
        if !isSearching { searchStatusMessage = foundCountMessage }
    }

    private func saveQueryToHistory(_ query: String) {
        searchHistory = SearchHistoryStore.addQuery(query, to: searchHistory)
    }

    func performSearch() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        searchTask?.cancel()
        resetSearchPaging() // lượt mới: huỷ tải thêm trang của lượt cũ
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
            
            // Tiện ích JS song song (TTS đang phát thì chừa thread cho TTS); nguồn Legado qua cửa sổ trượt (`LegadoSearchScheduler`).
            let targets = extensionsToSearch.map { LegadoSearchScheduler.Target($0) }
            // Tắt NSFW giữa lượt ⇒ nguồn Legado NSFW còn xếp hàng không được chạy (trừ ngoại lệ đổi nguồn).
            let changeSourcePackageId = sameKindScopePackageId
            let shouldStart: @Sendable (String) -> Bool = { packageId in
                SearchExtensionScopePolicy.keepsNsfw(changeSourcePackageId: changeSourcePackageId)
                    || !RepositoryFilterPolicy.isNsfwSource(packageId: packageId)
            }
            searchTask = Task {
                await LegadoSearchScheduler.searchAll(targets, query: trimmedQuery, shouldStart: shouldStart) { packageId, results in
                    await MainActor.run {
                        guard !Task.isCancelled else { return } // lượt cũ không ghi đè trạng thái lượt mới
                        // Khoá đã bị gỡ (vừa tắt NSFW — `dropHiddenNsfwSources`) ⇒ bỏ kết quả về muộn.
                        guard self.sourceStates[packageId] != nil else { return }
                        let cleanResults = results.map { filterAndDeduplicate($0) } ?? []
                        let state: SourceSearchState = cleanResults.isEmpty ? .noResults : .found(results: cleanResults)
                        self.sourceStates[packageId] = state
                    }
                }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isSearching = false
                    self.searchStatusMessage = foundCountMessage
                }
            }
        } else {
            // Bản ghi mới nhất: vừa áp dụng bộ lọc thì `selectedExtension` (bản chụp lúc mở màn) còn config cũ.
            guard let ext = selectedExtension.map({ ExtensionLibraryRepository.shared.installedExtension(packageId: $0.packageId) ?? $0 }) else {
                isSearching = false
                searchStatusMessage = "Vui lòng chọn một nguồn trước."
                return
            }
            
            startSingleSourceSearch(ext: ext, query: trimmedQuery) // trang 1 + tải thêm trang: `SearchView+Paging`
        }
    }
}

