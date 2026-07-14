import SwiftUI
import SwiftData

struct SearchNovelResultWithExt: Identifiable {
    let id = UUID()
    let result: SearchNovelResult
    let ext: Extension
}

struct SearchView: View {
    let activeExtensions: [Extension]
    let selectedExtension: Extension?
    let initialSearchQuery: String
    
    let changeSourceTargetBook: Book?
    let onSourceChanged: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var changeSourceTargetResult: SearchNovelResult? = nil
    @State private var changeSourceTargetExtension: Extension? = nil
    @State private var showingChangeSourceAlert = false
    @State private var isChangingSource = false
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var searchAllSources = false
    @State private var searchResults: [SearchNovelResultWithExt] = []
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State private var searchStatusMessage = ""
    @AppStorage("search_history") private var searchHistoryJSON = "[]"
    
    private var searchHistory: [String] {
        get {
            guard let data = searchHistoryJSON.data(using: .utf8),
                  let history = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return history
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: data, encoding: .utf8) {
                searchHistoryJSON = jsonString
            }
        }
    }
    
    init(activeExtensions: [Extension], selectedExtension: Extension?, initialSearchQuery: String = "", changeSourceTargetBook: Book? = nil, onSourceChanged: (() -> Void)? = nil) {
        self.activeExtensions = activeExtensions
        self.selectedExtension = selectedExtension
        self.initialSearchQuery = initialSearchQuery
        self.changeSourceTargetBook = changeSourceTargetBook
        self.onSourceChanged = onSourceChanged
        
        // Mặc định tìm tất cả nguồn nếu chưa chọn nguồn cụ thể hoặc khi đang đổi nguồn
        _searchAllSources = State(initialValue: selectedExtension == nil || changeSourceTargetBook != nil)
    }
    
    enum SourceSearchState {
        case searching
        case found(results: [SearchNovelResult])
        case noResults
    }
    
    @State private var sourceStates: [String: SourceSearchState] = [:]
    
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
            Text("Bạn có chắc chắn muốn thay đổi nguồn cho truyện sang '\(extName)' không?\nSách cũ trên kệ sẽ bị xóa và các cài đặt dịch riêng, từ điển riêng cũng như tiến độ đọc chương sẽ được chuyển qua sách mới.")
        }
    }
    
    @ViewBuilder
    private var searchBarView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm truyện hoặc tác giả...", text: $searchQuery, onCommit: performSearch)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.none)
                
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
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var searchOptionsView: some View {
        Toggle(isOn: $searchAllSources) {
            Text("Tìm trên tất cả nguồn đã cài")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        .padding(.horizontal)
        .padding(.vertical, 6)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(activeExtensions.sorted(by: { $0.name < $1.name }), id: \.packageId) { ext in
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
                                    if !results.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(ext.name)
                                                    .font(.headline)
                                                    .fontWeight(.bold)
                                                
                                                Spacer()
                                                
                                                NavigationLink(destination: SearchView(
                                                    activeExtensions: activeExtensions,
                                                    selectedExtension: ext,
                                                    initialSearchQuery: searchQuery
                                                )) {
                                                    HStack(spacing: 4) {
                                                        Text("Xem thêm")
                                                            .foregroundColor(.accentColor)
                                                        Image(systemName: "chevron.right")
                                                            .foregroundColor(.accentColor)
                                                    }
                                                    .font(.subheadline)
                                                }
                                            }
                                            .padding(.horizontal)
                                            
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 16) {
                                                    ForEach(results, id: \.link) { result in
                                                        if changeSourceTargetBook != nil {
                                                            Button(action: {
                                                                changeSourceTargetResult = result
                                                                changeSourceTargetExtension = ext
                                                                showingChangeSourceAlert = true
                                                            }) {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    AsyncImage(url: URL(string: result.cover)) { image in
                                                                        image.resizable()
                                                                            .aspectRatio(contentMode: .fill)
                                                                    } placeholder: {
                                                                        Color.gray.opacity(0.3)
                                                                            .overlay(Image(systemName: "book"))
                                                                    }
                                                                    .frame(width: 90, height: 125)
                                                                    .cornerRadius(6)
                                                                    .clipped()
                                                                    
                                                                    Text(translateIfNeeded(result.name))
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
                                                                sourceName: ext.name
                                                            )) {
                                                                VStack(alignment: .leading, spacing: 6) {
                                                                    AsyncImage(url: URL(string: result.cover)) { image in
                                                                        image.resizable()
                                                                            .aspectRatio(contentMode: .fill)
                                                                    } placeholder: {
                                                                        Color.gray.opacity(0.3)
                                                                            .overlay(Image(systemName: "book"))
                                                                    }
                                                                    .frame(width: 90, height: 125)
                                                                    .cornerRadius(6)
                                                                    .clipped()
                                                                    
                                                                    Text(translateIfNeeded(result.name))
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
        List(searchResults) { item in
            if changeSourceTargetBook != nil {
                Button(action: {
                    changeSourceTargetResult = item.result
                    changeSourceTargetExtension = item.ext
                    showingChangeSourceAlert = true
                }) {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: item.result.cover)) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                                .overlay(Image(systemName: "book"))
                        }
                        .frame(width: 50, height: 70)
                        .cornerRadius(6)
                        .clipped()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(translateIfNeeded(item.result.name))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            let descText = !item.result.description.isEmpty ? item.result.description : item.result.author
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
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
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
                    sourceName: item.ext.name
                )) {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: item.result.cover)) { image in
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                                .overlay(Image(systemName: "book"))
                        }
                        .frame(width: 50, height: 70)
                        .cornerRadius(6)
                        .clipped()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(translateIfNeeded(item.result.name))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .lineLimit(2)
                            
                            let descText = !item.result.description.isEmpty ? item.result.description : item.result.author
                            Text(translateIfNeeded(descText))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            Text(item.ext.name)
                                .font(.system(size: 9))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
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
        if !searchHistory.isEmpty {
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
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal)
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(searchHistory, id: \.self) { item in
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
    
    private func executeSourceChange(to result: SearchNovelResult, ext: Extension) async {
        guard let oldBook = changeSourceTargetBook else { return }
        
        let oldBookId = oldBook.bookId
        let newBookId = "\(ext.name.lowercased())_\(result.link)"
        let oldChapterIndex = oldBook.currentChapterIndex
        
        do {
            let path = ext.localPath
            let detailResult = try await ExtensionManager.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: result.link, configJson: ext.configJson)
            
            var firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: result.link, configJson: ext.configJson)
            
            if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                let pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: result.link, configJson: ext.configJson)
                if pages.count > 1 {
                    for pageUrl in pages.dropFirst() {
                        let pageChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, configJson: ext.configJson)
                        firstPageChapters.append(contentsOf: pageChaps)
                    }
                }
            }
            
            try await MainActor.run {
                let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(detailResult.detail.cleanHTML())"
                
                let newBook = Book(
                    bookId: newBookId,
                    title: detailResult.name,
                    author: detailResult.author,
                    coverUrl: detailResult.cover,
                    desc: savedDesc,
                    detailUrl: result.link,
                    sourceName: ext.name,
                    sourceUrl: ext.sourceUrl,
                    extensionPackageId: ext.packageId,
                    currentChapterIndex: min(oldChapterIndex, max(0, firstPageChapters.count - 1)),
                    currentChapterTitle: firstPageChapters.isEmpty ? "" : firstPageChapters[min(oldChapterIndex, max(0, firstPageChapters.count - 1))].name,
                    isOnShelf: true,
                    isHistory: oldBook.isHistory
                )
                
                modelContext.insert(newBook)
                
                for (index, item) in firstPageChapters.enumerated() {
                    let chapId = "\(newBookId)_\(item.url)"
                    let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: index)
                    newChap.book = newBook
                    modelContext.insert(newChap)
                }
                
                let translateDir = TranslationManager.shared.translateDirectory
                let oldDir = translateDir.appendingPathComponent("books").appendingPathComponent(oldBookId)
                let newDir = translateDir.appendingPathComponent("books").appendingPathComponent(newBookId)
                
                if FileManager.default.fileExists(atPath: oldDir.path) {
                    try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
                    let fileNames = ["VietPhrase.dat", "Names.dat", "VietPhrase.txt", "Names.txt"]
                    for name in fileNames {
                        let oldFile = oldDir.appendingPathComponent(name)
                        let newFile = newDir.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: oldFile.path) {
                            try? FileManager.default.removeItem(at: newFile)
                            try? FileManager.default.copyItem(at: oldFile, to: newFile)
                        }
                    }
                    try? FileManager.default.removeItem(at: oldDir)
                }
                
                modelContext.delete(oldBook)
                
                try? modelContext.save()
                
                TranslateUtils.clearCache()
                TranslationManager.shared.clearBookDictCache(for: oldBookId)
                TranslationManager.shared.clearBookDictCache(for: newBookId)
                
                onSourceChanged?()
            }
        } catch {
            print("❌ Lỗi đổi nguồn truyện: \(error.localizedDescription)")
        }
    }
    
    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }

    private func saveQueryToHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var currentHistory = searchHistory
        currentHistory.removeAll { $0 == trimmed }
        currentHistory.insert(trimmed, at: 0)
        if currentHistory.count > 15 {
            currentHistory = Array(currentHistory.prefix(15))
        }
        searchHistory = currentHistory
    }

    private func performSearch() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        
        saveQueryToHistory(trimmedQuery)
        
        isSearching = true
        searchResults.removeAll()
        sourceStates.removeAll()
        
        if searchAllSources {
            let extensionsToSearch = activeExtensions
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
            
            Task {
                await withTaskGroup(of: (String, [SearchNovelResult]?).self) { group in
                    for ext in extensionsToSearch {
                        let path = ext.localPath
                        let packageId = ext.packageId
                        let configJson = ext.configJson
                        let downloadUrl = ext.downloadUrl
                        
                        group.addTask {
                            do {
                                let extResults = try await ExtensionManager.shared.search(
                                    localPath: path,
                                    downloadUrl: downloadUrl,
                                    query: trimmedQuery,
                                    page: 1,
                                    configJson: configJson
                                )
                                return (packageId, extResults)
                            } catch {
                                return (packageId, nil)
                            }
                        }
                    }
                    
                    for await (packageId, results) in group {
                        await MainActor.run {
                            if let results = results, !results.isEmpty {
                                self.sourceStates[packageId] = .found(results: results)
                            } else {
                                self.sourceStates[packageId] = .noResults
                            }
                        }
                    }
                }
                
                await MainActor.run {
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
            
            Task {
                do {
                    let results = try await ExtensionManager.shared.search(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        query: trimmedQuery,
                        page: 1,
                        configJson: ext.configJson
                    )
                    await MainActor.run {
                        self.searchResults = results.map { SearchNovelResultWithExt(result: $0, ext: ext) }
                        self.isSearching = false
                        self.searchStatusMessage = "Tìm thấy \(results.count) truyện trên nguồn \(ext.name)."
                    }
                } catch {
                    await MainActor.run {
                        self.isSearching = false
                        self.searchStatusMessage = "Lỗi khi tìm kiếm: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
