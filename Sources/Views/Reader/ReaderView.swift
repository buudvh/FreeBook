import SwiftUI
import SwiftData
import AVFoundation

enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper = "Sáng"
    case sepia = "Trầm ấm"
    case dark = "Tối"
    
    var id: String { self.rawValue }
    
    var backgroundColor: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.95, blue: 0.90)
        case .sepia: return Color(red: 0.90, green: 0.83, blue: 0.72)
        case .dark: return Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }
    
    var textColor: Color {
        switch self {
        case .paper: return Color(red: 0.15, green: 0.15, blue: 0.15)
        case .sepia: return Color(red: 0.25, green: 0.18, blue: 0.10)
        case .dark: return Color(red: 0.75, green: 0.75, blue: 0.75)
        }
    }
}

struct ReaderView: View {
    // static variables: Dùng làm biến toàn cục của class để lưu trạng thái chương/sách đang phát TTS
    public static var activeBookId: String? = nil
    public static var activeChapterIndex: Int = -1

    // @Environment: Lấy các biến môi trường của hệ thống
    @Environment(\.modelContext) private var modelContext // Context quản lý dữ liệu SwiftData
    @Environment(\.dismiss) private var dismiss // Hàm dùng để đóng màn hình hiện tại và quay về màn hình trước
    @Environment(\.scenePhase) private var scenePhase
    
    // @Query: Tự động tải dữ liệu từ database SwiftData
    @Query private var allBooks: [Book] // Tất cả sách trong máy
    @Query private var allExtensions: [Extension] // Tất cả các tiện ích (extensions) đã cài đặt
    
    let bookId: String // ID cuốn sách đang đọc
    let extensionPackageId: String // ID extension phụ trách bóc tách nội dung cuốn sách này
    
    // @State: Biến trạng thái nội bộ của View, khi thay đổi sẽ tự động cập nhật giao diện
    @State var chapterIndex: Int // Chỉ mục chương hiện tại đang đọc
    let onlineChapters: [ChapterResult] // Danh sách chương nếu đang đọc trực tuyến (online)
    
    // Các thông tin sách truyền vào khi đọc trực tuyến để tự động tạo sách trong Database khi cần thiết
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDesc: String?
    let bookDetailUrl: String?
    let bookSourceName: String?
    
    @State private var isLoading = true // Trạng thái đang tải nội dung
    @State private var errorMessage = "" // Thông báo lỗi nếu tải chương thất bại
    @State private var chapterTitle = "" // Tiêu đề chương hiển thị
    @State private var chapterContent = "" // Nội dung chương hiển thị
    @State private var showChapterTitle = true // Ẩn/Hiện tiêu đề chương trên đầu màn hình đọc
    
    @State private var originalTitle = "" // Tiêu đề chương gốc (thường là tiếng Trung)
    @State private var originalContent = "" // Nội dung chương gốc
    
    // Các biến trạng thái hỗ trợ bôi đen từ/câu để tra cứu từ điển
    @State private var selectedTextForDefinition = "" // Từ/Câu đang được bôi đen chọn tra từ
    @State private var showingDefinitionSheet = false // Hiện hộp thoại tra nghĩa từ điển
    @State private var customMeaning = "" // Nghĩa tự định nghĩa của người dùng lưu lại
    @AppStorage("saveToBookSpecific") private var saveToBookSpecific = true
    @AppStorage("saveAsNameType") private var saveAsNameType = false
    
    // Các cấu hình tra từ nâng cao và hiển thị
    @State private var originalSentence = ""
    @State private var selectedWordOffset = 0
    @State private var selectedWordLength = 0
    @State private var searchEngines: [SearchEngine] = []
    @State private var translationMode: String = "VP" // Dịch dạng: "VP" (Vietphrase) hoặc "HV" (Hán Việt)
    @State private var translationTokens: [TranslationWordToken] = []
    @State private var dictionaryMatches: [DictionaryMatchInfo] = []
    @State private var showingManageDefinitionsSheet = false
    
    // Cấu hình giao diện đọc (lưu trữ lâu dài qua UserDefaults nhờ @AppStorage)
    @AppStorage("readerFontSize") private var fontSize: Double = 20.0 // Cỡ chữ của văn bản đọc
    @AppStorage("readerLineSpacing") private var lineSpacing: Double = 10.0 // Khoảng cách giữa các dòng
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch thuật
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark // Theme giao diện đọc (Sáng, Trầm ấm, Tối)
    @AppStorage("hasOpenedReader") private var hasOpenedReader = false
    @State private var showingSettings = false // Hiện bảng cài đặt font chữ, màu nền
    
    // Trạng thái bypass Cloudflare và import sách
    @State private var showingBypassBrowser = false
    @State private var showingLookupBrowser = false
    @State private var lookupUrlString = ""
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToBookDetail = false
    @State private var isGoingNext = true
    @State private var isTransitioning = false
    
    // TTS (Giọng đọc): Sử dụng @StateObject để giữ vòng đời của đối tượng TTSManager.shared không bị hủy khi đổi chương
    @StateObject private var ttsManager = TTSManager.shared
    @State private var ttsShouldAutoPlayNextChapter = false // Tự động phát tiếp khi chuyển chương
    @State private var ttsResumeParagraphIndex: Int? = nil
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State private var prefetchTask: Task<Void, Never>? = nil
    @State private var editingParagraphIndex: Int? = nil
    @State private var editingChapterIndex: Int? = nil
    @State private var scrollTarget: ScrollTarget? = nil
    @State private var isAutoScrollDisabled = false
    @State private var viewModel: ReaderViewModel? = nil
    @State private var updateProgressWorkItem: DispatchWorkItem? = nil
    @State private var updateTTSPositionWorkItem: DispatchWorkItem? = nil
    @State private var prepareTTSTask: DispatchWorkItem? = nil
    
    @State private var loadedChapters: [LoadedChapter] = []
    @State private var hasScrolledToTop = false
    @State private var paragraphTracker = ParagraphTracker()
    
    // State variables for overlay HUD controls
    @State private var showControls = false
    @State private var showingChapterList = false
    @State private var showingBookDictionary = false
    @State private var sliderValue: Double = 0.0
    @State private var currentOnlineChapters: [ChapterResult] = []
    
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
    }
    
    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }
    
    private var currentChapterHost: String? {
        if chapterIndex < currentOnlineChapters.count {
            return currentOnlineChapters[chapterIndex].host
        } else if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            if chapterIndex < sorted.count {
                return sorted[chapterIndex].host
            }
        }
        return localBook?.host ?? ext?.sourceUrl
    }
    
    private var isCurrentlyPlayingThisChapter: Bool {
        ttsManager.isPlaying &&
        ttsManager.playingBookId == bookId &&
        ttsManager.playingChapterIndex == chapterIndex
    }
    
    private var ttsChaptersQueue: [TTSChapterInfo] {
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            return sorted.map { chap in
                let titleToUse: String
                if isTranslationEnabled && TranslateUtils.containsChinese(chap.title) {
                    titleToUse = TranslateUtils.translateChapterTitle(chap.title, bookId: bookId)
                } else {
                    titleToUse = chap.title
                }
                return TTSChapterInfo(
                    title: titleToUse,
                    url: chap.url,
                    index: chap.index,
                    cachedContent: chap.isCached ? chap.content : nil
                )
            }
        } else {
            return currentOnlineChapters.enumerated().map { (index, chap) in
                let titleToUse: String
                if isTranslationEnabled && TranslateUtils.containsChinese(chap.name) {
                    titleToUse = TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                } else {
                    titleToUse = chap.name
                }
                return TTSChapterInfo(
                    title: titleToUse,
                    url: chap.url,
                    index: index,
                    cachedContent: index == chapterIndex ? chapterContent : nil
                )
            }
        }
    }
    
    private var ttsExtensionInfo: TTSExtensionInfo? {
        guard let ext = ext else { return nil }
        return TTSExtensionInfo(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
    }
    
    // Tổng số chương hiện có
    private var totalChaptersCount: Int {
        if let book = localBook {
            return book.chapters.count
        }
        return currentOnlineChapters.count
    }
    
    // Lấy thông tin chương hiện tại (Title, URL)
    private var currentChapterInfo: (title: String, url: String)? {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return nil }
        
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            let chap = sorted[chapterIndex]
            return (chap.title, chap.url)
        } else {
            let chap = currentOnlineChapters[chapterIndex]
            return (chap.name, chap.url)
        }
    }
    
    private func getChapterTitle(at index: Int) -> String {
        guard index >= 0 && index < totalChaptersCount else { return "Chương \(index + 1)" }
        
        let title: String
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            if index < sorted.count {
                title = sorted[index].title
            } else {
                title = "Chương \(index + 1)"
            }
        } else {
            if index < currentOnlineChapters.count {
                title = currentOnlineChapters[index].name
            } else {
                title = "Chương \(index + 1)"
            }
        }
        
        return isTranslationEnabled && TranslateUtils.containsChinese(title)
            ? TranslateUtils.translateChapterTitle(title, bookId: bookId)
            : title
    }
    
    private var isChapterLoadingOrFailed: Bool {
        if let vm = viewModel {
            if let cached = vm.cache.get(chapterIndex) {
                switch cached.state {
                case .loading, .prefetching, .failed:
                    return true
                default:
                    return false
                }
            }
            return true
        } else {
            if loadedChapters.isEmpty {
                return true
            }
            if let currentLoaded = loadedChapters.first(where: { $0.index == chapterIndex }) {
                return currentLoaded.isLoading || !currentLoaded.errorMessage.isEmpty
            }
            return isLoading || !errorMessage.isEmpty
        }
    }
    
    var body: some View {
        ZStack {
            // Nền theo theme
            selectedTheme.backgroundColor
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                }
            
            VStack(spacing: 0) {
                readerContentView
                    .id(chapterIndex)
            }
            // Top/Bottom overlay controls
            if showControls {
                VStack(spacing: 0) {
                    topOverlayBar
                    Spacer()
                    bottomOverlayBar
                }
                .ignoresSafeArea(edges: .bottom)
            }
            
            // Chapter List Overlay (luôn nằm trong hierarchy nhưng ẩn đi bằng offset/opacity)
            ReaderChapterListView(
                bookId: bookId,
                extensionPackageId: extensionPackageId,
                bookDetailUrl: bookDetailUrl,
                currentChapterIndex: chapterIndex,
                isTranslationEnabled: isTranslationEnabled,
                theme: selectedTheme,
                onlineChapters: $currentOnlineChapters,
                isVisible: showingChapterList,
                onSelectChapter: { selectedIdx in
                    selectChapter(at: selectedIdx)
                },
                onClose: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingChapterList = false
                    }
                }
            )
            .offset(x: showingChapterList ? 0 : -UIScreen.main.bounds.width)
            .opacity(showingChapterList ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: showingChapterList)
            .zIndex(10)
        }
        .toolbar(.hidden, for: .navigationBar) // Ẩn navigation bar gốc
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(fontSize: $fontSize, lineSpacing: $lineSpacing, selectedTheme: $selectedTheme, isTranslationEnabled: $isTranslationEnabled)
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showingBookDictionary) {
            NavigationStack {
                BookDictionaryView(bookId: bookId, bookName: bookTitle ?? "")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Đóng") {
                                showingBookDictionary = false
                            }
                        }
                    }
            }
        }
        .onChange(of: ttsManager.showingSettingsSheet) { _, newValue in
            if newValue {
                // Tự động đóng các sheet khác của ReaderView để tránh tranh chấp presentation
                showingSettings = false
                showingBookDictionary = false
            }
        }
        .onChange(of: isTranslationEnabled) { _, _ in
            applyTranslation()
        }
        .sheet(isPresented: $showingDefinitionSheet) {
            definitionSheetContent
        }
        .fullScreenCover(isPresented: $showingBypassBrowser) {
            BypassWebView(
                urlString: currentChapterInfo?.url ?? bookDetailUrl ?? "",
                host: currentChapterHost,
                onImport: { detailUrl, packageId, sourceName in
                    importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                    importedExtensionPackageId = packageId
                    importedDetailUrl = detailUrl
                    importedSourceName = sourceName
                    
                    if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                        importedHost = "\(scheme)://\(host)"
                    } else {
                        importedHost = ""
                    }
                    
                    navigateToBookDetail = true
                }
            )
        }
        .background(
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
                isActive: $navigateToBookDetail
            ) {
                EmptyView()
            }
        )
        .onChange(of: localBook?.chapters.count) { _, newCount in
            if let vm = viewModel, let count = newCount {
                if vm.totalChaptersCount != count {
                    vm.totalChaptersCount = count
                    vm.updateVisibleChaptersWindow()
                }
            }
        }
        .onChange(of: currentOnlineChapters.count) { _, newCount in
            if let vm = viewModel, newCount > 0 {
                if vm.totalChaptersCount != newCount {
                    vm.totalChaptersCount = newCount
                    vm.updateVisibleChaptersWindow()
                }
            }
        }

        .onAppear {
            let key = "showChapterTitle_\(bookId)"
            if UserDefaults.standard.object(forKey: key) != nil {
                showChapterTitle = UserDefaults.standard.bool(forKey: key)
            } else {
                showChapterTitle = true
            }
            
            let autoScrollKey = "disableAutoScroll_\(bookId)"
            self.isAutoScrollDisabled = UserDefaults.standard.bool(forKey: autoScrollKey)
            
            ReaderView.activeBookId = bookId
            ReaderView.activeChapterIndex = chapterIndex
            
            if currentOnlineChapters.isEmpty {
                currentOnlineChapters = onlineChapters
            }
            
            if viewModel == nil {
                let savedPIdx = getSavedParagraphIndex(for: chapterIndex)
                
                // Tính toán số lượng chương khởi tạo an toàn bằng cách dùng trực tiếp tham số onlineChapters
                let initialTotalCount: Int
                if let book = localBook {
                    initialTotalCount = book.chapters.count
                } else {
                    initialTotalCount = onlineChapters.count
                }
                
                viewModel = ReaderViewModel(
                    bookId: bookId,
                    extensionPackageId: extensionPackageId,
                    initialChapterIndex: chapterIndex,
                    initialParagraphIndex: savedPIdx,
                    totalChaptersCount: initialTotalCount,
                    modelContext: modelContext,
                    onlineChapters: onlineChapters,
                    isTranslationEnabled: isTranslationEnabled,
                    bookTitle: bookTitle,
                    bookAuthor: bookAuthor,
                    bookCoverUrl: bookCoverUrl,
                    bookDesc: bookDesc,
                    bookDetailUrl: bookDetailUrl,
                    bookSourceName: bookSourceName
                )
            }
            
            ttsManager.onChapterFinished = {
                let nextIdx = chapterIndex + 1
                if nextIdx < totalChaptersCount {
                    selectChapter(at: nextIdx)
                }
            }
            ttsManager.onChapterNext = {
                let nextIdx = chapterIndex + 1
                if nextIdx < totalChaptersCount {
                    selectChapter(at: nextIdx)
                }
            }
            ttsManager.onChapterPrev = {
                let prevIdx = chapterIndex - 1
                if prevIdx >= 0 {
                    selectChapter(at: prevIdx)
                }
            }
            
            // Tự động hiển thị thanh công cụ HUD trong lần đầu mở trình đọc
            if !hasOpenedReader {
                showControls = true
                hasOpenedReader = true
            }
        }
        .onDisappear {
            if ReaderView.activeBookId == bookId && ReaderView.activeChapterIndex == chapterIndex {
                ReaderView.activeBookId = nil
                ReaderView.activeChapterIndex = -1
            }
            prefetchTask?.cancel()
            viewModel?.saveProgressImmediately()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel?.saveProgressImmediately()
            }
        }
        .onChange(of: chapterIndex) { _, newValue in
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.visibleParagraphs.removeAll()
            
            if ReaderView.activeBookId == bookId {
                ReaderView.activeChapterIndex = newValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidAdvanceToNextChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  let nextIdx = userInfo["chapterIndex"] as? Int else { return }
            
            if bid == bookId && nextIdx != chapterIndex {
                self.ttsShouldAutoPlayNextChapter = true
                selectChapter(at: nextIdx, scroll: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleReaderControls"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls.toggle()
            }
        }
        .onChange(of: ttsManager.currentParentParagraphIndex) { _, newValue in
            guard ttsManager.isPlaying &&
                  ttsManager.playingBookId == bookId &&
                  ttsManager.playingChapterIndex == chapterIndex &&
                  newValue >= 0 else { return }
            
            // Lưu vị trí TTS đang phát vào database
            saveReadProgress(index: chapterIndex, paragraphIndex: newValue)
            
            guard !isAutoScrollDisabled else { return }
            
            withAnimation {
                scrollTarget = ScrollTarget(chapterIndex: ttsManager.playingChapterIndex, paragraphIndex: newValue)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
    
    
    
    private func translateMetaIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
    
    private func translateChapterTitleIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }

    private func applyTranslation() {
        if let vm = viewModel {
            vm.toggleTranslation(enabled: isTranslationEnabled)
        } else {
            for chapter in loadedChapters {
                applyTranslationForChapter(index: chapter.index, originalTitle: chapter.originalTitle, originalContent: chapter.originalContent)
            }
        }
    }
    
    private func saveDefinition() {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = customMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !word.isEmpty && !meaning.isEmpty else { return }
        
        let bid = saveToBookSpecific ? bookId : nil
        
        Task {
            do {
                try await TranslationManager.shared.saveCustomEntry(word: word, meaning: meaning, isName: saveAsNameType, bookId: bid)
                await MainActor.run {
                    showingDefinitionSheet = false
                    applyTranslation()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi lưu định nghĩa từ: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Advanced Translation Editor Helpers
    
    private func getHanViet(for word: String) -> String {
        let phienAm = TranslationManager.shared.phienAmMap
        var list: [String] = []
        for char in word {
            list.append(phienAm[String(char)] ?? String(char))
        }
        return list.joined(separator: " ").capitalized
    }
    
    private func formatMeaning(_ input: String, style: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }
        
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return input }
        
        var formattedWords: [String] = []
        
        switch style {
        case "aa": // viết thường hoàn toàn
            formattedWords = words.map { $0.lowercased() }
            
        case "Aa¹": // viết hoa từ đầu tiên
            for (index, word) in words.enumerated() {
                if index == 0 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }
            
        case "Aa²": // viết hoa 2 từ đầu tiên
            for (index, word) in words.enumerated() {
                if index < 2 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }
            
        case "Aa": // viết hoa tất cả các từ trừ từ cuối cùng
            for (index, word) in words.enumerated() {
                if index < words.count - 1 {
                    formattedWords.append(word.prefix(1).uppercased() + word.dropFirst().lowercased())
                } else {
                    formattedWords.append(word.lowercased())
                }
            }
            
        case "AA": // viết kiểu title
            formattedWords = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            
        default:
            return input
        }
        
        return formattedWords.joined(separator: " ")
    }
    
    private var suggestionChips: [String] {
        var chips: [String] = []
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        
        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)
        
        func addTranslation(_ translation: String) {
            let clean = translation.replacingOccurrences(of: "¦", with: "/")
            let parts = clean.components(separatedBy: "/")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isDuplicate = chips.contains { existing in
                        existing.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                    }
                    if !isDuplicate {
                        chips.append(trimmed)
                    }
                }
            }
        }
        
        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }
        
        // 1.1 Custom Names (custom.dat)
        var hasCustomName = false
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
            hasCustomName = true
        }
        
        // 2. Global Names (chỉ hiện nếu không có trong Custom Names)
        if !hasCustomName,
           let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }
        
        // 3. Pronouns
        if let pronouns = manager.pronounsDict,
           let match = pronouns.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }
        
        // 4. LuatNhan
        if let luatNhan = manager.luatNhanDict,
           let match = luatNhan.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }
        
        // 5. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
        }
        
        // 5.1 Custom VietPhrase (custom.dat)
        var hasCustomVP = false
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value)
            hasCustomVP = true
        }
        
        // 6. Global VietPhrase (Chung - chỉ hiện nếu không có trong Custom VietPhrase)
        if !hasCustomVP,
           let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            if match.value.count < 100 {
                addTranslation(match.value)
            }
        }
        
        // 7. Phiên âm Hán Việt (chỉ 1 bản viết thường duy nhất)
        let hv = getHanViet(for: word).lowercased()
        if !hv.isEmpty {
            let isDuplicate = chips.contains { existing in
                existing.localizedCaseInsensitiveCompare(hv) == .orderedSame
            }
            if !isDuplicate {
                chips.append(hv)
            }
        }
        
        return chips
    }
    
    private var sentenceSegments: (prefix: String, selected: String, suffix: String) {
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else {
            return ("", originalSentence, "")
        }
        let prefix = ns.substring(with: NSRange(location: 0, length: selectedWordOffset))
        let selected = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        let suffix = ns.substring(with: NSRange(location: selectedWordOffset + selectedWordLength, length: ns.length - (selectedWordOffset + selectedWordLength)))
        return (prefix, selected, suffix)
    }
    
    private var translatedSentenceSegments: (prefix: String, selected: String, suffix: String) {
        let translatedSentence = TranslateUtils.translateContent(originalSentence, bookId: bookId)
        let translatedWord = TranslateUtils.translateMeta(selectedTextForDefinition, bookId: bookId)
        
        guard !translatedWord.isEmpty,
              let range = translatedSentence.range(of: translatedWord) else {
            return ("", translatedSentence, "")
        }
        
        let prefix = String(translatedSentence[..<range.lowerBound])
        let selected = String(translatedSentence[range])
        let suffix = String(translatedSentence[range.upperBound...])
        return (prefix, selected, suffix)
    }
    
    private var selectedTokens: [TranslationWordToken] {
        translationTokens.filter { token in
            token.originalOffset < selectedWordOffset + selectedWordLength &&
            token.originalOffset + token.originalLength > selectedWordOffset
        }
    }
    
    private func expandSelectionLeft() {
        if selectedWordOffset > 0 {
            selectedWordOffset -= 1
            selectedWordLength += 1
            updateEditorFromSelection()
        }
    }
    
    private func shrinkSelectionLeft() {
        if selectedWordLength > 1 {
            selectedWordOffset += 1
            selectedWordLength -= 1
            updateEditorFromSelection()
        }
    }
    
    private func shrinkSelectionRight() {
        if selectedWordLength > 1 {
            selectedWordLength -= 1
            updateEditorFromSelection()
        }
    }
    
    private func expandSelectionRight() {
        let ns = originalSentence as NSString
        if selectedWordOffset + selectedWordLength < ns.length {
            selectedWordLength += 1
            updateEditorFromSelection()
        }
    }
    
    private func updateEditorFromSelection() {
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else { return }
        let word = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        self.selectedTextForDefinition = word
        
        if translationMode == "VP" {
            self.customMeaning = TranslateUtils.translateMeta(word, bookId: bookId)
        } else {
            self.customMeaning = getHanViet(for: word)
        }
        
        // Cập nhật các tokens phân tách và tra cứu từ điển đa tầng
        self.translationTokens = TranslateUtils.getTranslationTokens(for: originalSentence, bookId: bookId)
        self.dictionaryMatches = getDictionaryMatches(for: word)
    }
    
    private func getDictionaryMatches(for word: String) -> [DictionaryMatchInfo] {
        var matches: [DictionaryMatchInfo] = []
        guard !word.isEmpty else { return matches }
        
        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)
        
        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Names (Riêng)", translation: match.value))
        }
        
        // 2. Global Names
        var namesTranslation: String? = nil
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            namesTranslation = match.value
        } else if !manager.deletedNames.contains(word),
                  let names = manager.namesDict,
                  let match = names.findLongestMatch(text: word, startIndex: 0),
                  match.length == word.count {
            namesTranslation = match.value
        }
        if let trans = namesTranslation {
            matches.append(DictionaryMatchInfo(source: "Names (Chung)", translation: trans))
        }
        
        // 3. Pronouns
        if let pronouns = manager.pronounsDict,
           let match = pronouns.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Xưng hô (Pronouns)", translation: match.value))
        }
        
        // 4. LuatNhan
        if let luatNhan = manager.luatNhanDict,
           let match = luatNhan.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Luật nhân (LuatNhan)", translation: match.value))
        }
        
        // 5. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Riêng)", translation: match.value))
        }
        
        // 6. Global VietPhrase
        var vpTranslation: String? = nil
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            vpTranslation = match.value
        } else if !manager.deletedVietPhrase.contains(word),
                  let vp = manager.vietPhraseDict,
                  let match = vp.findLongestMatch(text: word, startIndex: 0),
                  match.length == word.count {
            vpTranslation = match.value
        }
        if let trans = vpTranslation {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Chung)", translation: trans))
        }
        
        // 7. PhienAm
        let phienAm = getHanViet(for: word)
        if !phienAm.isEmpty {
            matches.append(DictionaryMatchInfo(source: "Phiên âm", translation: phienAm))
        }
        
        return matches
    }
    
    private func performQuickLookup(using engine: SearchEngine) {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        
        let rawUrl = engine.urlTemplate.replacingOccurrences(of: "%s", with: word)
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        self.lookupUrlString = encoded
        self.showingLookupBrowser = true
    }

    private func isEditableSource(_ source: String) -> Bool {
        return source == "Names (Riêng)" || source == "Names (Chung)" ||
               source == "VietPhrase (Riêng)" || source == "VietPhrase (Chung)"
    }
    
    private func deleteMatch(_ match: DictionaryMatchInfo) {
        let isName = match.source.contains("Names")
        let bid = match.source.contains("Riêng") ? bookId : nil
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                try await TranslationManager.shared.deleteCustomEntry(word: word, isName: isName, bookId: bid)
                await MainActor.run {
                    self.dictionaryMatches = getDictionaryMatches(for: word)
                    if self.translationMode == "VP" {
                        self.customMeaning = TranslateUtils.translateMeta(word, bookId: bookId)
                    } else {
                        self.customMeaning = getHanViet(for: word)
                    }
                    applyTranslation()
                }
            } catch {
                // AppLogger.shared.log("❌ Lỗi xóa định nghĩa từ: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Flashcard Song ngữ & Tách Đoạn văn Helpers
    
    @ViewBuilder
    private func chapterContentView(for chapter: LoadedChapter) -> some View {
        let isTrans = isTranslationEnabled
        let size = fontSize
        let spacing = lineSpacing
        let theme = selectedTheme
        
        LazyVStack(alignment: .leading, spacing: size * 0.8) {
            ForEach(chapter.paragraphItems) { item in
                let textLen = (isTrans ? item.translated : item.original).count
                let relativeHighlightRange: NSRange? = {
                    if ttsManager.isPlaying &&
                       ttsManager.playingBookId == bookId &&
                       ttsManager.playingChapterIndex == chapter.index &&
                       item.id == ttsManager.currentParentParagraphIndex {
                        return NSRange(location: 0, length: textLen)
                    }
                    return nil
                }()
                
                ParagraphCardView(
                    item: item,
                    isTranslationEnabled: isTrans,
                    fontSize: size,
                    lineSpacing: spacing,
                    theme: theme,
                    highlightRange: relativeHighlightRange,
                    triggerGetVisibleIndex: $triggerGetVisibleIndex,
                    onGetVisibleIndex: { visibleOffset in
                        guard !ttsManager.isPlaying else { return }
                        startTTS(at: chapter.index, paragraphIndex: item.id)
                    },
                    onSelectionChange: { selectedText, sentence, offset, absoluteOffset in
                        self.onSelectionChangeInParagraph(
                            selectedText: selectedText,
                            sentence: sentence,
                            offset: offset,
                            absoluteOffset: absoluteOffset,
                            item: item,
                            chapterIndex: chapter.index
                        )
                    },
                    onSpeakFromHere: { _ in
                        startTTS(at: chapter.index, paragraphIndex: item.id)
                    }
                )
                .id("paragraph-\(chapter.index)-\(item.id)")
                .onAppear {
                    paragraphTracker.visibleParagraphs.insert(item.id)
                }
                .onDisappear {
                    paragraphTracker.visibleParagraphs.remove(item.id)
                    updateScrollReadingProgress()
                }
            }
        }
    }
    
    @ViewBuilder
    private func chapterContentView(for chapter: CachedChapter) -> some View {
        let isTrans = isTranslationEnabled
        let size = fontSize
        let spacing = lineSpacing
        let theme = selectedTheme
        
        ForEach(chapter.paragraphItems) { item in
            let textLen = (isTrans ? item.translated : item.original).count
            let relativeHighlightRange: NSRange? = {
                if ttsManager.isPlaying &&
                   ttsManager.playingBookId == bookId &&
                   ttsManager.playingChapterIndex == chapter.index &&
                   item.id == ttsManager.currentParentParagraphIndex {
                    return NSRange(location: 0, length: textLen)
                }
                return nil
            }()
            
            ParagraphCardView(
                item: item,
                isTranslationEnabled: isTrans,
                fontSize: size,
                lineSpacing: spacing,
                theme: theme,
                highlightRange: relativeHighlightRange,
                triggerGetVisibleIndex: $triggerGetVisibleIndex,
                onGetVisibleIndex: { visibleOffset in
                    guard !ttsManager.isPlaying else { return }
                    startTTS(at: chapter.index, paragraphIndex: item.id)
                },
                onSelectionChange: { selectedText, sentence, offset, absoluteOffset in
                    self.onSelectionChangeInParagraph(
                        selectedText: selectedText,
                        sentence: sentence,
                        offset: offset,
                        absoluteOffset: absoluteOffset,
                        item: item,
                        chapterIndex: chapter.index
                    )
                },
                onSpeakFromHere: { _ in
                    startTTS(at: chapter.index, paragraphIndex: item.id)
                }
            )
            .equatable()
            .id("paragraph-\(chapter.index)-\(item.id)")
            .onAppear {
                paragraphTracker.visibleParagraphs.insert(item.id)
            }
            .onDisappear {
                paragraphTracker.visibleParagraphs.remove(item.id)
                updateScrollReadingProgress()
            }
        }
    }
    
    private func onSelectionChangeInParagraph(
        selectedText: String,
        sentence: String,
        offset: Int,
        absoluteOffset: Int,
        item: ParagraphItem,
        chapterIndex: Int
    ) {
        self.editingParagraphIndex = item.id
        self.editingChapterIndex = chapterIndex
        if isTranslationEnabled {
            // Khi bật dịch, bôi đen là tiếng Việt. Cần tìm câu gốc tiếng Trung tương ứng trong thẻ/div này
            let vietSentenceRanges = TranslateUtils.getSentenceRanges(in: item.translated)
            let chiSentenceRanges = TranslateUtils.getSentenceRanges(in: item.original)
            
            if !vietSentenceRanges.isEmpty && !chiSentenceRanges.isEmpty {
                var sentenceIdx = vietSentenceRanges.firstIndex(where: { 
                    $0.range.location <= absoluteOffset && absoluteOffset < $0.range.location + $0.range.length 
                })
                
                let targetChiSentenceIdx: Int
                let vietSentenceRange: SentenceRange
                
                if let sIdx = sentenceIdx, sIdx < chiSentenceRanges.count {
                    targetChiSentenceIdx = sIdx
                    vietSentenceRange = vietSentenceRanges[sIdx]
                } else {
                    // Fallback: Tìm bằng tỷ lệ tương đối trong phạm vi thẻ
                    let vietLength = Double(item.translated.count)
                    let relativePos = vietLength > 0 ? Double(absoluteOffset) / vietLength : 0.0
                    
                    let chiLength = Double(item.original.count)
                    var bestIdx = 0
                    var minDiff = Double.infinity
                    
                    for (idx, chiRange) in chiSentenceRanges.enumerated() {
                        let chiCenter = Double(chiRange.range.location) + Double(chiRange.range.length) / 2.0
                        let chiRelativePos = chiLength > 0 ? chiCenter / chiLength : 0.0
                        let diff = abs(chiRelativePos - relativePos)
                        if diff < minDiff {
                            minDiff = diff
                            bestIdx = idx
                        }
                    }
                    targetChiSentenceIdx = bestIdx
                    let targetVietIdx = min(bestIdx, vietSentenceRanges.count - 1)
                    vietSentenceRange = vietSentenceRanges[targetVietIdx]
                    sentenceIdx = targetVietIdx
                }
                
                let offsetInVietSentence = max(0, absoluteOffset - vietSentenceRange.range.location)
                let chiSentenceRange = chiSentenceRanges[targetChiSentenceIdx]
                let chiSentence = chiSentenceRange.text
                let tokens = TranslateUtils.getTranslationTokens(for: chiSentence, bookId: bookId)
                
                let vietSentenceNS = vietSentenceRange.text as NSString
                var vietNonSpaceMap: [Int] = []
                var nonSpaceCount = 0
                let whitespaceSet = CharacterSet.whitespacesAndNewlines
                
                for i in 0..<vietSentenceNS.length {
                    let charCode = vietSentenceNS.character(at: i)
                    if let unicodeScalar = UnicodeScalar(charCode), whitespaceSet.contains(unicodeScalar) {
                        vietNonSpaceMap.append(-1)
                    } else {
                        vietNonSpaceMap.append(nonSpaceCount)
                        nonSpaceCount += 1
                    }
                }
                
                var userStartNonSpace = -1
                var userEndNonSpace = -1
                for i in 0..<selectedText.count {
                    let charIdxInSentence = offsetInVietSentence + i
                    if charIdxInSentence < vietNonSpaceMap.count {
                        let nsIdx = vietNonSpaceMap[charIdxInSentence]
                        if nsIdx != -1 {
                            if userStartNonSpace == -1 {
                                userStartNonSpace = nsIdx
                            }
                            userEndNonSpace = nsIdx + 1
                        }
                    }
                }
                
                var tokenNonSpaceRanges: [NSRange] = []
                var reconstructedNonSpaceCount = 0
                for token in tokens {
                    var tokenNonSpaceLen = 0
                    let tokenNS = token.translatedText as NSString
                    for i in 0..<tokenNS.length {
                        let charCode = tokenNS.character(at: i)
                        if let unicodeScalar = UnicodeScalar(charCode), whitespaceSet.contains(unicodeScalar) {
                            // Bỏ qua
                        } else {
                            tokenNonSpaceLen += 1
                        }
                    }
                    tokenNonSpaceRanges.append(NSRange(location: reconstructedNonSpaceCount, length: tokenNonSpaceLen))
                    reconstructedNonSpaceCount += tokenNonSpaceLen
                }
                
                var overlappingIndices: [Int] = []
                if userStartNonSpace != -1 && userEndNonSpace != -1 {
                    let userRange = NSRange(location: userStartNonSpace, length: userEndNonSpace - userStartNonSpace)
                    for (idx, tokenRange) in tokenNonSpaceRanges.enumerated() {
                        let maxStart = max(tokenRange.location, userRange.location)
                        let minEnd = min(tokenRange.location + tokenRange.length, userRange.location + userRange.length)
                        if maxStart < minEnd {
                            overlappingIndices.append(idx)
                        }
                    }
                }
                
                var finalChiOffset = 0
                var finalChiLength = 1
                
                if !overlappingIndices.isEmpty {
                    let firstIdx = overlappingIndices.first!
                    let lastIdx = overlappingIndices.last!
                    finalChiOffset = tokens[firstIdx].originalOffset
                    finalChiLength = (tokens[lastIdx].originalOffset + tokens[lastIdx].originalLength) - finalChiOffset
                } else {
                    let vietLen = Double(vietSentenceRange.text.count)
                    let ratio = vietLen > 0 ? Double(offsetInVietSentence) / vietLen : 0.0
                    let chiLen = Double(chiSentence.count)
                    finalChiOffset = min(Int(round(ratio * chiLen)), max(0, chiSentence.count - 1))
                    finalChiLength = 1
                }
                
                let snapped = TranslateUtils.snapToToken(
                    sentence: chiSentence,
                    selectionOffset: finalChiOffset,
                    selectionLength: finalChiLength,
                    bookId: bookId
                )
                
                self.originalSentence = chiSentence
                self.selectedWordOffset = snapped.offset
                self.selectedWordLength = snapped.length
                self.updateEditorFromSelection()
                self.showingDefinitionSheet = true
                return
            }
        }
        
        // Không bật dịch (hoặc lỗi): Tra cứu trực tiếp
        let snapped = TranslateUtils.snapToToken(
            sentence: sentence,
            selectionOffset: offset,
            selectionLength: selectedText.count,
            bookId: bookId
        )
        self.originalSentence = sentence
        self.selectedWordOffset = snapped.offset
        self.selectedWordLength = snapped.length
        self.updateEditorFromSelection()
        self.showingDefinitionSheet = true
    }


    private func cleanBlankLines(in text: String) -> String {
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // loadChapterContent: Hàm tải nội dung chương truyện (hỗ trợ đọc offline từ DB hoặc tải trực tuyến thông qua extension JS)
    private func loadChapterContent(index: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let info: (title: String, url: String)
        if let book = localBook {
            // Sách local: Lấy chương tương ứng trong cơ sở dữ liệu
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            guard index < sorted.count else { return }
            let chap = sorted[index]
            info = (chap.title, chap.url)
        } else {
            // Sách đọc online: Lấy chương từ danh sách onlineChapters
            guard index < currentOnlineChapters.count else { return }
            let chap = currentOnlineChapters[index]
            info = (chap.name, chap.url)
        }
        
        // Cập nhật trạng thái loading của chương truyện trong danh sách đang hiển thị
        if let idx = loadedChapters.firstIndex(where: { $0.index == index }) {
            loadedChapters[idx].isLoading = true
            loadedChapters[idx].errorMessage = ""
        } else {
            let newChapter = LoadedChapter(
                index: index,
                title: info.title,
                originalTitle: info.title,
                originalContent: "",
                chapterContent: "",
                paragraphItems: [],
                isLoading: true
            )
            if loadedChapters.isEmpty {
                loadedChapters.append(newChapter)
            } else if index < loadedChapters.first!.index {
                loadedChapters.insert(newChapter, at: 0)
            } else {
                loadedChapters.append(newChapter)
            }
        }
        
        // Nếu sách đã được lưu local, kiểm tra xem nội dung chương đã được tải về (isCached) chưa
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            if index < sorted.count {
                let chap = sorted[index]
                if chap.isCached, let content = chap.content, !content.isEmpty {
                    // Nếu đã tải offline, làm sạch mã HTML dư thừa và tiến hành áp dụng dịch tự động (Hán Việt/Vietphrase)
                    let cleanedContent = cleanBlankLines(in: content.cleanHTML())
                    applyTranslationForChapter(index: index, originalTitle: info.title, originalContent: cleanedContent)
                    return
                }
            }
        }
        
        // Nếu chưa tải offline, kiểm tra xem có extension để cào web không
        guard let ext = ext else {
            updateChapterError(index: index, message: "Không tìm thấy tiện ích bóc tách!")
            return
        }
        
        // Task: Chạy tiến trình nền không đồng bộ để tải nội dung từ internet bằng extension JS mà không gây đơ ứng dụng
        Task {
            var chapHost: String? = nil
            if index < currentOnlineChapters.count {
                chapHost = currentOnlineChapters[index].host
            } else if let book = localBook {
                let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                if index < sorted.count {
                    chapHost = sorted[index].host
                }
            }
            
            do {
                // Gọi extension JS bóc tách nội dung chương từ nguồn web
                let content = try await ExtensionManager.shared.chap(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    url: info.url,
                    host: chapHost,
                    configJson: ext.configJson
                )
                let cleanedContent = cleanBlankLines(in: content.cleanHTML())
                
                // Trở về Main Thread để cập nhật dữ liệu và UI một cách an toàn
                await MainActor.run {
                    if let book = localBook {
                        // Lưu lại nội dung chương vừa tải vào Database để lần sau đọc offline
                        let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                        if index < sorted.count {
                            let chap = sorted[index]
                            chap.content = cleanedContent
                            chap.isCached = true
                            try? modelContext.save()
                        }
                    } else {
                        // Tải online lần đầu, tự động lưu thông tin sách vào database nếu người dùng muốn lưu
                        saveOnlineBookIfNeeded(currentIndex: index, cleanedContent: cleanedContent, info: info)
                    }
                    
                    // Thực hiện dịch thuật tự động hiển thị lên màn hình
                    applyTranslationForChapter(index: index, originalTitle: info.title, originalContent: cleanedContent)
                }
            } catch {
                await MainActor.run {
                    // Cập nhật thông báo lỗi nếu quá trình tải thất bại (hết mạng, lỗi script...)
                    updateChapterError(index: index, message: error.localizedDescription)
                }
            }
        }
    }
    
    private func saveOnlineBookIfNeeded(currentIndex: Int, cleanedContent: String, info: (title: String, url: String)) {
        guard allBooks.first(where: { $0.bookId == bookId }) == nil else {
            if let book = localBook {
                let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                if currentIndex < sorted.count {
                    let chap = sorted[currentIndex]
                    if !chap.isCached {
                        chap.content = cleanedContent
                        chap.isCached = true
                        try? modelContext.save()
                    }
                }
            }
            return
        }
        
        guard let ext = ext else { return }
        
        let newBook = Book(
            bookId: bookId,
            title: bookTitle ?? "Không rõ",
            author: bookAuthor ?? "Không rõ",
            coverUrl: bookCoverUrl ?? "",
            desc: bookDesc ?? "",
            detailUrl: bookDetailUrl ?? "",
            sourceName: bookSourceName ?? "",
            sourceUrl: ext.sourceUrl,
            extensionPackageId: extensionPackageId,
            currentChapterIndex: currentIndex,
            currentChapterTitle: info.title,
            isOnShelf: false,
            isHistory: true,
            host: currentOnlineChapters.first?.host
        )
        modelContext.insert(newBook)
        
        for (idx, item) in currentOnlineChapters.enumerated() {
            let chapId = "\(newBook.bookId)_\(item.url)"
            let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: idx, host: item.host)
            newChap.book = newBook
            if idx == currentIndex {
                newChap.content = cleanedContent
                newChap.isCached = true
            }
            modelContext.insert(newChap)
        }
        try? modelContext.save()
    }
    
    private func applyTranslationForChapter(index: Int, originalTitle: String, originalContent: String) {
        let titleToUse = originalTitle
        let bookId = self.bookId
        
        if isTranslationEnabled {
            Task.detached(priority: .userInitiated) {
                var translatedTitle = titleToUse
                if TranslateUtils.containsChinese(titleToUse) {
                    translatedTitle = TranslateUtils.translateChapterTitle(titleToUse, bookId: bookId)
                }
                
                var translatedContent = originalContent
                if TranslateUtils.containsChinese(originalContent) {
                    translatedContent = TranslateUtils.translateContent(originalContent, bookId: bookId)
                }
                
                await MainActor.run {
                    updateChapterData(index: index, originalTitle: originalTitle, originalContent: originalContent, translatedTitle: translatedTitle, translatedContent: translatedContent)
                }
            }
        } else {
            updateChapterData(index: index, originalTitle: originalTitle, originalContent: originalContent, translatedTitle: originalTitle, translatedContent: originalContent)
        }
    }
    
    private func updateChapterData(index: Int, originalTitle: String, originalContent: String, translatedTitle: String, translatedContent: String) {
        if self.isTransitioning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.updateChapterData(index: index, originalTitle: originalTitle, originalContent: originalContent, translatedTitle: translatedTitle, translatedContent: translatedContent)
            }
            return
        }
        
        guard let idx = loadedChapters.firstIndex(where: { $0.index == index }) else { return }
        
        let items = generateParagraphItems(chapterIndex: index, originalTitle: originalTitle, originalContent: originalContent, translatedTitle: translatedTitle, translatedContent: translatedContent)
        loadedChapters[idx].paragraphItems = items
        
        loadedChapters[idx].originalTitle = originalTitle
        loadedChapters[idx].originalContent = originalContent
        loadedChapters[idx].title = translatedTitle
        loadedChapters[idx].chapterContent = translatedContent
        loadedChapters[idx].isLoading = false
        loadedChapters[idx].errorMessage = ""
        
        saveReadProgress(index: index, paragraphIndex: getSavedParagraphIndex(for: index))
        
        if self.ttsShouldAutoPlayNextChapter && index == chapterIndex {
            self.ttsShouldAutoPlayNextChapter = false
            startTTS(at: index, paragraphIndex: -1)
        }
        
        prefetchAdjacentChapters()
        scrollToTTSHighlightIfNeeded()
    }
    
    private func updateChapterError(index: Int, message: String) {
        guard let idx = loadedChapters.firstIndex(where: { $0.index == index }) else { return }
        loadedChapters[idx].isLoading = false
        loadedChapters[idx].errorMessage = message
    }
    
    private func generateParagraphItems(chapterIndex: Int, originalTitle: String, originalContent: String, translatedTitle: String, translatedContent: String) -> [ParagraphItem] {
        let originalLines = originalContent.components(separatedBy: "\n")
        let translatedLines = translatedContent.components(separatedBy: "\n")
        var items: [ParagraphItem] = []
        
        let key = "showChapterTitle_\(bookId)"
        let showTitle = UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.bool(forKey: key) : true
        
        if showTitle {
            items.append(ParagraphItem(id: -1, original: originalTitle, translated: translatedTitle, isTitle: true))
        }
        
        let maxLines = max(originalLines.count, translatedLines.count)
        for i in 0..<maxLines {
            let orig = i < originalLines.count ? originalLines[i] : ""
            let trans = i < translatedLines.count ? translatedLines[i] : ""
            items.append(ParagraphItem(id: i, original: orig, translated: trans, isTitle: false))
        }
        return items
    }
    
    private func reloadChapterContent() {
        let index = chapterIndex
        guard index >= 0 && index < totalChaptersCount else { return }
        
        if let vm = viewModel {
            Task {
                try? await vm.loadChapterContentFromExtension(index)
            }
            return
        }
        
        guard let info = currentChapterInfo else { return }
        guard let ext = ext else { return }
        
        if let idx = loadedChapters.firstIndex(where: { $0.index == index }) {
            loadedChapters[idx].isLoading = true
            loadedChapters[idx].errorMessage = ""
        }
        
        Task {
            var chapHost: String? = nil
            if index < currentOnlineChapters.count {
                chapHost = currentOnlineChapters[index].host
            } else if let book = localBook {
                let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                if index < sorted.count {
                    chapHost = sorted[index].host
                }
            }
            
            do {
                let content = try await ExtensionManager.shared.chap(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    url: info.url,
                    host: chapHost,
                    configJson: ext.configJson
                )
                let cleanedContent = cleanBlankLines(in: content.cleanHTML())
                
                await MainActor.run {
                    if let book = localBook {
                        let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                        if index < sorted.count {
                            let chap = sorted[index]
                            chap.content = cleanedContent
                            chap.isCached = true
                            try? modelContext.save()
                        }
                    }
                    applyTranslationForChapter(index: index, originalTitle: info.title, originalContent: cleanedContent)
                }
            } catch {
                await MainActor.run {
                    updateChapterError(index: index, message: "Không thể tải lại chương: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func nextChapter() {
        if chapterIndex < totalChaptersCount - 1 {
            selectChapter(at: chapterIndex + 1)
        }
    }
    
    private func prevChapter() {
        if chapterIndex > 0 {
            selectChapter(at: chapterIndex - 1)
        }
    }
    
    private func selectChapter(at index: Int, scroll: Bool = true) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        self.isGoingNext = index >= self.chapterIndex
        self.isTransitioning = true
        
        self.paragraphTracker.visibleParagraphs.removeAll()
        
        if let vm = viewModel {
            vm.onTabSelectionChanged(newIndex: index)
            self.chapterIndex = index
            self.isTransitioning = false
            return
        }
        
        let currentChapter = LoadedChapter(
            index: index,
            title: "Chương \(index + 1)",
            originalTitle: "Chương \(index + 1)",
            originalContent: "",
            chapterContent: "",
            paragraphItems: [],
            isLoading: true
        )
        
        self.chapterIndex = index
        self.loadedChapters = [currentChapter]
        self.hasScrolledToTop = false
        self.isTransitioning = false
        
        loadChapterContent(index: index)
    }
    

    
    private func startTTS(at index: Int, paragraphIndex: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let chapterContentToUse: String
        if let vm = viewModel {
            chapterContentToUse = vm.cache.get(index)?.content ?? ""
        } else if let loaded = loadedChapters.first(where: { $0.index == index }) {
            chapterContentToUse = isTranslationEnabled ? loaded.chapterContent : loaded.originalContent
        } else {
            chapterContentToUse = ""
        }
        
        ttsManager.startSpeaking(
            bookId: bookId,
            chapters: ttsChaptersQueue,
            currentIndex: index,
            chapterContent: chapterContentToUse,
            startParagraphIndex: paragraphIndex,
            bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
            coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
            extensionInfo: ttsExtensionInfo
        )
    }
    
    private func getSavedParagraphIndex(for idx: Int) -> Int {
        if let book = localBook {
            if idx == book.currentChapterIndex {
                return book.currentChapterPage
            }
        } else {
            let lastChapIdx = UserDefaults.standard.integer(forKey: "lastChapterIndex_\(bookId)")
            if idx == lastChapIdx {
                return UserDefaults.standard.integer(forKey: "lastParagraphIndex_\(bookId)")
            }
        }
        
        if let vm = viewModel, let cached = vm.cache.get(idx) {
            if cached.scrollParagraphIndex >= 0 {
                return cached.scrollParagraphIndex
            }
        }
        
        return -1
    }
    
    private func prepareTTSForCurrentState() {
        guard !ttsManager.isPlaying else { return }
        
        let index = chapterIndex
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let chapterContentToUse: String
        if let vm = viewModel {
            chapterContentToUse = vm.cache.get(index)?.content ?? ""
        } else if let loaded = loadedChapters.first(where: { $0.index == index }) {
            chapterContentToUse = isTranslationEnabled ? loaded.chapterContent : loaded.originalContent
        } else {
            chapterContentToUse = ""
        }
        
        guard !chapterContentToUse.isEmpty else { return }
        
        let savedPIdx = getSavedParagraphIndex(for: index)
        
        ttsManager.prepareSpeaking(
            bookId: bookId,
            chapters: ttsChaptersQueue,
            currentIndex: index,
            chapterContent: chapterContentToUse,
            startParagraphIndex: savedPIdx,
            bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
            coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
            extensionInfo: ttsExtensionInfo
        )
    }
    
    private func schedulePrepareTTS() {
        guard !ttsManager.isPlaying else { return }
        prepareTTSTask?.cancel()
        
        let workItem = DispatchWorkItem {
            self.prepareTTSForCurrentState()
        }
        self.prepareTTSTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
    
    private func updateScrollReadingProgress() {
        guard !ttsManager.isPlaying else { return }
        
        // 1. Debounce 200ms cho việc cập nhật tiến trình lưu trữ
        updateProgressWorkItem?.cancel()
        let progressWork = DispatchWorkItem { [weak viewModel] in
            guard let topIndex = self.paragraphTracker.visibleParagraphs.min() else { return }
            
            if let vm = viewModel {
                vm.updateProgress(chapterIndex: self.chapterIndex, paragraphIndex: topIndex)
            } else {
                self.saveReadProgress(index: self.chapterIndex, paragraphIndex: topIndex)
            }
        }
        self.updateProgressWorkItem = progressWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: progressWork)
        
        // 2. Debounce 1.5 giây cho việc đồng bộ con trỏ TTS (tránh re-render ttsManager khi cuộn nhanh)
        updateTTSPositionWorkItem?.cancel()
        let ttsWork = DispatchWorkItem {
            guard let topIndex = self.paragraphTracker.visibleParagraphs.min() else { return }
            self.ttsManager.updateParagraphPositionWithoutPlaying(paragraphIndex: topIndex)
        }
        self.updateTTSPositionWorkItem = ttsWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: ttsWork)
    }
    
    private func saveReadProgress(index: Int, paragraphIndex: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let title: String
        if let vm = viewModel {
            let sorted = vm.getSortedChapters()
            guard index < sorted.count else { return }
            title = sorted[index].title
        } else if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            guard index < sorted.count else { return }
            title = sorted[index].title
        } else {
            guard index < currentOnlineChapters.count else { return }
            let chap = currentOnlineChapters[index]
            title = chap.name
        }
        
        if let book = localBook {
            book.currentChapterIndex = index
            book.currentChapterPage = paragraphIndex
            book.currentChapterTitle = title
            book.isHistory = true
            book.lastReadDate = Date()
            Task {
                try? modelContext.save()
            }
        } else if let book = allBooks.first(where: { $0.bookId == bookId }) {
            book.currentChapterIndex = index
            book.currentChapterPage = paragraphIndex
            book.currentChapterTitle = title
            book.isHistory = true
            book.lastReadDate = Date()
            Task {
                try? modelContext.save()
            }
        }
        
        UserDefaults.standard.set(index, forKey: "lastChapterIndex_\(bookId)")
        UserDefaults.standard.set(paragraphIndex, forKey: "lastParagraphIndex_\(bookId)")
    }

    
    private func prefetchAdjacentChapters() {
        prefetchTask?.cancel()
        
        prefetchTask = Task {
            // Chờ 1.5 giây sau khi lật trang rồi mới tải trước để tránh chiếm dụng băng thông và CPU khi đang lướt nhanh
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            
            // 1. Tải trước chương tiếp theo (Next Chapter)
            let nextIdx = chapterIndex + 1
            if nextIdx < totalChaptersCount {
                await prefetchChapter(at: nextIdx)
            }
            
            guard !Task.isCancelled else { return }
            
            // 2. Tải trước chương trước đó (Previous Chapter)
            let prevIdx = chapterIndex - 1
            if prevIdx >= 0 {
                await prefetchChapter(at: prevIdx)
            }
        }
    }
    
    private func prefetchChapter(at index: Int) async {
        let sortedChapters: [Chapter]
        let targetUrl: String
        let targetTitle: String
        let targetHost: String?
        
        if let book = localBook {
            sortedChapters = book.chapters.sorted(by: { $0.index < $1.index })
            guard index < sortedChapters.count else { return }
            let chap = sortedChapters[index]
            if chap.isCached && chap.content?.isEmpty == false {
                return
            }
            targetUrl = chap.url
            targetTitle = chap.title
            targetHost = chap.host
        } else {
            guard index < currentOnlineChapters.count else { return }
            let chap = currentOnlineChapters[index]
            targetUrl = chap.url
            targetTitle = chap.name
            targetHost = chap.host
        }
        
        guard let ext = ext else { return }
        
        do {
            AppLogger.shared.log("Tải trước chương \(index): \(targetTitle)")
            let content = try await ExtensionManager.shared.chap(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                url: targetUrl,
                host: targetHost,
                configJson: ext.configJson
            )
            let cleanedContent = content.cleanHTML()
            
            if let book = localBook {
                let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                if index < sorted.count {
                    let chap = sorted[index]
                    chap.content = cleanedContent
                    chap.isCached = true
                    try? modelContext.save()
                    AppLogger.shared.log("Tải trước thành công và cache chương \(index)")
                }
            }
        } catch {
            AppLogger.shared.log("Lỗi tải trước chương \(index): \(error.localizedDescription)")
        }
    }
}

// MARK: - ReaderSettingsView Sheet
struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var selectedTheme: ReaderTheme
    @Binding var isTranslationEnabled: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Cài đặt trình đọc")
                .font(.headline)
                .padding(.top)
            
            // Chỉnh cỡ chữ & giãn dòng song song
            HStack(spacing: 40) {
                // Size chữ
                VStack(spacing: 4) {
                    Text("Cỡ chữ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Button(action: { if fontSize > 12 { fontSize -= 1 } }) {
                            Image(systemName: "minus.circle")
                                .padding(6)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                        }
                        
                        Text("\(Int(fontSize))")
                            .font(.body)
                            .frame(width: 30)
                        
                        Button(action: { if fontSize < 36 { fontSize += 1 } }) {
                            Image(systemName: "plus.circle")
                                .padding(6)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
                
                // Khoảng cách dòng
                VStack(spacing: 4) {
                    Text("Giãn dòng")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Button(action: { if lineSpacing > 2 { lineSpacing -= 1 } }) {
                            Image(systemName: "minus.circle")
                                .padding(6)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                        }
                        
                        Text("\(Int(lineSpacing))")
                            .font(.body)
                            .frame(width: 30)
                        
                        Button(action: { if lineSpacing < 20 { lineSpacing += 1 } }) {
                            Image(systemName: "plus.circle")
                                .padding(6)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Chọn theme
            Picker("Theme", selection: $selectedTheme) {
                ForEach(ReaderTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            
            // Toggle dịch
            Toggle("Bật dịch Quick Translate", isOn: $isTranslationEnabled)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}

struct DictionaryMatchInfo: Identifiable {
    var id = UUID()
    let source: String
    let translation: String
}

// MARK: - View Helpers Extension
extension ReaderView {
    
    private func scrollToTTSHighlightIfNeeded() {
        guard !isAutoScrollDisabled else { return }
        if ttsManager.isPlaying && ttsManager.playingBookId == bookId && ttsManager.currentParentParagraphIndex >= 0 {
            let targetIdx = ttsManager.currentParentParagraphIndex
            let chapIdx = ttsManager.playingChapterIndex
            if chapIdx == chapterIndex {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.scrollTarget = ScrollTarget(chapterIndex: chapIdx, paragraphIndex: targetIdx)
                }
            }
        }
    }
    
    @ViewBuilder
    private var readerContentView: some View {
        if let vm = viewModel {
            if vm.totalChaptersCount > 0 && !vm.visibleIndexes.isEmpty {
                textReaderView
            } else {
                chapterLoadingView
            }
        } else if loadedChapters.isEmpty {
            chapterLoadingView
        } else {
            textReaderView
        }
    }
    
    private var chapterLoadingView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Tiêu đề chương nếu có
            if let info = currentChapterInfo {
                let displayTitle = isTranslationEnabled && TranslateUtils.containsChinese(info.title)
                    ? TranslateUtils.translateChapterTitle(info.title, bookId: bookId)
                    : info.title
                Text(displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(selectedTheme.textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)
            }
            
            if !errorMessage.isEmpty {
                // Trạng thái LỖI
                VStack(spacing: 20) {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    VStack(spacing: 12) {
                        // Nút Tải lại (ở trên)
                        Button(action: {
                            loadChapterContent(index: chapterIndex)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Tải lại")
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 160)
                            .padding(.vertical, 12)
                            .background(selectedTheme.textColor.opacity(0.1))
                            .cornerRadius(24)
                        }
                        
                        // Nút Xem nguồn (ở giữa)
                        Button(action: {
                            showingBypassBrowser = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "safari")
                                Text("Xem nguồn")
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 160)
                            .padding(.vertical, 12)
                            .background(selectedTheme.textColor.opacity(0.1))
                            .cornerRadius(24)
                        }
                        
                        // Nút Quay lại (ở dưới cùng)
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left")
                                Text("Quay lại")
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTheme.textColor)
                            .frame(width: 160)
                            .padding(.vertical, 12)
                            .background(selectedTheme.textColor.opacity(0.08))
                            .cornerRadius(24)
                        }
                    }
                }
            } else {
                // Trạng thái ĐANG TẢI (Loading)
                VStack(spacing: 24) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(selectedTheme.textColor.opacity(0.8))
                    
                    Text("Đang tải nội dung chương...")
                        .font(.subheadline)
                        .foregroundColor(selectedTheme.textColor.opacity(0.6))
                    
                    VStack(spacing: 12) {
                        // Nút Tải lại thủ công (ở trên)
                        Button(action: {
                            loadChapterContent(index: chapterIndex)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Tải lại")
                            }
                            .font(.footnote)
                            .foregroundColor(selectedTheme.textColor.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTheme.textColor.opacity(0.08))
                            .cornerRadius(16)
                        }
                        
                        // Nút Quay lại (ở dưới)
                        Button(action: {
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left")
                                Text("Quay lại")
                            }
                            .fontWeight(.medium)
                            .foregroundColor(selectedTheme.textColor)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(selectedTheme.textColor.opacity(0.1))
                            .cornerRadius(20)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    

    
    @ViewBuilder
    private var textReaderView: some View {
        Group {
            if let vm = viewModel {
                TabView(selection: Binding(
                    get: { vm.tabSelection },
                    set: { newIndex in
                        vm.onTabSelectionChanged(newIndex: newIndex)
                        self.chapterIndex = newIndex
                    }
                )) {
                    ForEach(vm.visibleIndexes, id: \.self) { idx in
                        if let cached = vm.cache.get(idx) {
                            ScrollViewReader { proxy in
                                Group {
                                    if cached.state == .loading || cached.state == .prefetching {
                                        VStack(spacing: 24) {
                                            Spacer()
                                            
                                            Text(getChapterTitle(at: idx))
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(selectedTheme.textColor)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(3)
                                                .padding(.horizontal, 40)
                                                .padding(.top, 16)
                                            
                                            ProgressView()
                                                .scaleEffect(1.5)
                                                .tint(selectedTheme.textColor.opacity(0.8))
                                            
                                            Text("Đang tải nội dung chương...")
                                                .font(.subheadline)
                                                .foregroundColor(selectedTheme.textColor.opacity(0.6))
                                            
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                showControls.toggle()
                                            }
                                        }
                                    } else if case .failed(let message) = cached.state {
                                        VStack(spacing: 24) {
                                            Spacer()
                                            
                                            Text(getChapterTitle(at: idx))
                                                .font(.title2)
                                                .fontWeight(.bold)
                                                .foregroundColor(selectedTheme.textColor)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(3)
                                                .padding(.horizontal, 40)
                                                .padding(.top, 16)
                                            
                                            VStack(spacing: 16) {
                                                Text(message)
                                                    .font(.subheadline)
                                                    .foregroundColor(.red)
                                                    .multilineTextAlignment(.center)
                                                    .padding(.horizontal, 40)
                                                
                                                Button(action: {
                                                    Task {
                                                        try? await vm.loadChapterContentFromExtension(idx)
                                                    }
                                                }) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "arrow.clockwise")
                                                        Text("Thử lại")
                                                    }
                                                    .fontWeight(.medium)
                                                    .foregroundColor(selectedTheme.textColor)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 10)
                                                    .background(selectedTheme.textColor.opacity(0.1))
                                                    .cornerRadius(20)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                showControls.toggle()
                                            }
                                        }
                                    } else {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: fontSize * 0.8) {
                                                chapterContentView(for: cached)
                                            }
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 24)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    showControls.toggle()
                                                }
                                            }
                                        }
                                        .id("scroll-view-\(idx)")
                                    }
                                }
                                .onChange(of: scrollTarget) { _, newValue in
                                    if let target = newValue, target.chapterIndex == idx {
                                        withAnimation {
                                            if target.paragraphIndex == -1 {
                                                proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
                                            } else {
                                                proxy.scrollTo("paragraph-\(target.chapterIndex)-\(target.paragraphIndex)", anchor: .center)
                                            }
                                        }
                                        scrollTarget = nil
                                    }
                                }
                                .onChange(of: cached.state) { _, state in
                                    if state == .loaded && idx == chapterIndex {
                                        if !cached.isPositionRestored {
                                            cached.isPositionRestored = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                let savedPIdx = getSavedParagraphIndex(for: idx)
                                                let hasValidParagraph = cached.paragraphItems.contains(where: { $0.id == savedPIdx })
                                                withAnimation(.easeOut(duration: 0.25)) {
                                                    if savedPIdx >= 0 && hasValidParagraph {
                                                        proxy.scrollTo("paragraph-\(idx)-\(savedPIdx)", anchor: .top)
                                                    } else {
                                                        if cached.paragraphItems.contains(where: { $0.id == -1 }) {
                                                            proxy.scrollTo("paragraph-\(idx)--1", anchor: .top)
                                                        }
                                                    }
                                                }
                                                if self.ttsShouldAutoPlayNextChapter {
                                                    self.ttsShouldAutoPlayNextChapter = false
                                                    startTTS(at: idx, paragraphIndex: -1)
                                                } else {
                                                    schedulePrepareTTS()
                                                }
                                            }
                                        } else {
                                            if self.ttsShouldAutoPlayNextChapter {
                                                self.ttsShouldAutoPlayNextChapter = false
                                                startTTS(at: idx, paragraphIndex: -1)
                                            } else {
                                                schedulePrepareTTS()
                                            }
                                        }
                                    }
                                }
                                .onAppear {
                                    if cached.state == .loaded && idx == chapterIndex {
                                        if !cached.isPositionRestored {
                                            cached.isPositionRestored = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                let savedPIdx = getSavedParagraphIndex(for: idx)
                                                let hasValidParagraph = cached.paragraphItems.contains(where: { $0.id == savedPIdx })
                                                withAnimation(.easeOut(duration: 0.25)) {
                                                    if savedPIdx >= 0 && hasValidParagraph {
                                                        proxy.scrollTo("paragraph-\(idx)-\(savedPIdx)", anchor: .top)
                                                    } else {
                                                        if cached.paragraphItems.contains(where: { $0.id == -1 }) {
                                                            proxy.scrollTo("paragraph-\(idx)--1", anchor: .top)
                                                        }
                                                    }
                                                }
                                                if self.ttsShouldAutoPlayNextChapter {
                                                    self.ttsShouldAutoPlayNextChapter = false
                                                    startTTS(at: idx, paragraphIndex: -1)
                                                } else {
                                                    schedulePrepareTTS()
                                                }
                                            }
                                        } else {
                                            if self.ttsShouldAutoPlayNextChapter {
                                                self.ttsShouldAutoPlayNextChapter = false
                                                startTTS(at: idx, paragraphIndex: -1)
                                            } else {
                                                schedulePrepareTTS()
                                            }
                                        }
                                    }
                                }
                                .onChange(of: chapterIndex) { _, newChapterIndex in
                                    if newChapterIndex == idx && cached.state == .loaded {
                                        if !cached.isPositionRestored {
                                            cached.isPositionRestored = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                                let savedPIdx = getSavedParagraphIndex(for: idx)
                                                let hasValidParagraph = cached.paragraphItems.contains(where: { $0.id == savedPIdx })
                                                withAnimation(.easeOut(duration: 0.25)) {
                                                    if savedPIdx >= 0 && hasValidParagraph {
                                                        proxy.scrollTo("paragraph-\(idx)-\(savedPIdx)", anchor: .top)
                                                    } else {
                                                        if cached.paragraphItems.contains(where: { $0.id == -1 }) {
                                                            proxy.scrollTo("paragraph-\(idx)--1", anchor: .top)
                                                        }
                                                    }
                                                }
                                                if self.ttsShouldAutoPlayNextChapter {
                                                    self.ttsShouldAutoPlayNextChapter = false
                                                    startTTS(at: idx, paragraphIndex: -1)
                                                } else {
                                                    schedulePrepareTTS()
                                                }
                                            }
                                        } else {
                                            if self.ttsShouldAutoPlayNextChapter {
                                                self.ttsShouldAutoPlayNextChapter = false
                                                startTTS(at: idx, paragraphIndex: -1)
                                            } else {
                                                schedulePrepareTTS()
                                            }
                                        }
                                    }
                                }
                            }
                            .tag(idx)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
            } else {
                ProgressView()
            }
        }
        .onChange(of: showChapterTitle) { _, _ in
            if let vm = viewModel {
                vm.refreshParagraphItems()
            } else {
                for idx in 0..<loadedChapters.count {
                    let chap = loadedChapters[idx]
                    let items = generateParagraphItems(
                        chapterIndex: chap.index,
                        originalTitle: chap.originalTitle,
                        originalContent: chap.originalContent,
                        translatedTitle: chap.title,
                        translatedContent: chap.chapterContent
                    )
                    loadedChapters[idx].paragraphItems = items
                }
            }
        }
    }
    
    @ViewBuilder
    private var readerToolbarContent: some View {
        // Translation Toggle Button
        Button(action: {
            isTranslationEnabled.toggle()
        }) {
            Image(systemName: isTranslationEnabled ? "character.bubble.fill" : "character.bubble")
                .foregroundColor(selectedTheme.textColor)
        }
        
        // TTS Button
        Button(action: {
            if ttsManager.isPlaying {
                ttsManager.stop()
            } else {
                triggerGetVisibleIndex = UUID()
            }
        }) {
            Image(systemName: ttsManager.isPlaying ? "stop.circle.fill" : "play.circle")
                .foregroundColor(ttsManager.isPlaying ? .red : selectedTheme.textColor)
        }
        
        // Dictionary Manager, Reload, and Settings Menu
        Menu {
            Button(action: {
                reloadChapterContent()
            }) {
                Label("Tải lại chương", systemImage: "arrow.clockwise")
            }
            
            if localBook != nil {
                NavigationLink(destination: BookDictionaryView(bookId: bookId, bookName: bookTitle ?? "")) {
                    Label("Từ điển truyện", systemImage: "character.book.closed")
                }
            }
            
            Button(action: {
                showingBypassBrowser = true
            }) {
                Label("Mở bằng trình duyệt", systemImage: "safari")
            }
            
            Button(action: {
                showingSettings.toggle()
            }) {
                Label("Cài đặt trình đọc", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(selectedTheme.textColor)
        }
    }
    
    // MARK: - Custom HUD Overlay Bars
    @ViewBuilder
    private var topOverlayBar: some View {
        VStack(spacing: 0) {
            // Hàng 1: Các nút điều khiển
            HStack(alignment: .center, spacing: 0) {
                // Nút Đóng X
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 8)
                
                Spacer()
                
                // Các phím Trailing Actions
                HStack(spacing: 12) {
                    // Tải lại
                    Button(action: {
                        reloadChapterContent()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 44)
                    }
                    
                    // Tìm kiếm
                    Button(action: {
                        // Tính năng tìm kiếm trong chương
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 44)
                    }
                    
                    // Dấu ba chấm nâng cấp thành Menu Dropdown
                    Menu {
                        Button(action: {
                            showChapterTitle.toggle()
                            let key = "showChapterTitle_\(bookId)"
                            UserDefaults.standard.set(showChapterTitle, forKey: key)
                        }) {
                            Label(
                                "Hiện tên chương trong nội dung",
                                systemImage: showChapterTitle ? "checkmark.square" : "square"
                            )
                        }
                        
                        Button(action: {
                            showingBookDictionary = true
                        }) {
                            Label("Từ điển truyện", systemImage: "book.closed")
                        }
                        
                        Button(action: {
                            showingBypassBrowser = true
                        }) {
                            Label("Mở bằng trình duyệt", systemImage: "safari")
                        }
                        
                        Button(action: {
                            showingSettings = true
                        }) {
                            Label("Cài đặt trình đọc", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 44)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(height: 44)
            
            // Hàng 2: Tiêu đề sách & Chương
            VStack(alignment: .leading, spacing: 2) {
                Text(translateMetaIfNeeded(localBook?.title ?? bookTitle ?? "FreeBook"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(translateChapterTitleIfNeeded(chapterTitle.isEmpty ? (currentChapterInfo?.title ?? "Chương \(chapterIndex + 1)") : chapterTitle))
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showingChapterList = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Subheader: Chọn nhanh dịch & Tỷ lệ chương
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 15))
                    Text(isTranslationEnabled ? "Việt (VP)" : "Trung (Gốc)")
                        .font(.system(size: 15))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
                .onTapGesture {
                    isTranslationEnabled.toggle()
                }
                
                Spacer()
                
                Text("\(chapterIndex + 1)/\(totalChaptersCount)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .padding(.top, 10)
        .background(
            Color(white: 0.08, opacity: 0.95)
                .ignoresSafeArea(edges: .top)
        )
    }
    
    @ViewBuilder
    private var bottomOverlayBar: some View {
        VStack(spacing: 12) {
            // Hàng 1: % tiến độ, Tên chương, Nút Layout
            HStack {
                let progress = totalChaptersCount > 0 ? (Double(chapterIndex + 1) / Double(totalChaptersCount)) * 100 : 0.0
                Text(String(format: "%.1f%%", progress))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Text(translateChapterTitleIfNeeded(chapterTitle.isEmpty ? (currentChapterInfo?.title ?? "") : chapterTitle))
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 180)
                
                Spacer()
                
                Button(action: {
                    let newValue = !isAutoScrollDisabled
                    isAutoScrollDisabled = newValue
                    UserDefaults.standard.set(newValue, forKey: "disableAutoScroll_\(bookId)")
                }) {
                    Image(systemName: isAutoScrollDisabled ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isAutoScrollDisabled ? .yellow : .white)
                }
            }
            .padding(.horizontal, 16)
            
            // Hàng 2: Trước - Slider - Tiếp
            HStack(spacing: 16) {
                Button(action: prevChapter) {
                    Text("Trước")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(chapterIndex > 0 ? .white : .white.opacity(0.4))
                }
                .disabled(chapterIndex <= 0)
                
                Slider(
                    value: $sliderValue,
                    in: 0...Double(max(0, totalChaptersCount - 1)),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing {
                            selectChapter(at: Int(sliderValue))
                        }
                    }
                )
                .tint(.blue)
                
                Button(action: nextChapter) {
                    Text("Tiếp")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(chapterIndex < totalChaptersCount - 1 ? .white : .white.opacity(0.4))
                }
                .disabled(chapterIndex >= totalChaptersCount - 1)
            }
            .padding(.horizontal, 16)
            
            // Hàng 3: Các nút chức năng dưới cùng (Chỉ giữ lại Mục lục và Nghe truyện)
            HStack(spacing: 0) {
                // Xem danh sách chương (Mục lục)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingChapterList = true
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 20))
                        Text("Mục lục")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                }
                
                // Nghe truyện TTS
                Button(action: {
                    if ttsManager.isPlaying {
                        ttsManager.stop()
                    } else {
                        triggerGetVisibleIndex = UUID()
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: ttsManager.isPlaying ? "stop.circle.fill" : "headphones")
                            .font(.system(size: 20))
                            .foregroundColor(ttsManager.isPlaying ? .red : .white)
                        Text("Nghe truyện")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .padding(.vertical, 8)
        .background(
            Color(white: 0.08, opacity: 0.95)
                .ignoresSafeArea(edges: .bottom)
        )
    }
    
    @ViewBuilder
    private var definitionSheetContent: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Dịch")
                    .font(.headline)
                Spacer()
                Button(action: { showingDefinitionSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            
            // Hàng 1: Đoạn dịch gốc và nút điều chỉnh 2 bên (Token-based)
            HStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button(action: expandSelectionLeft) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Button(action: shrinkSelectionLeft) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .foregroundColor(.blue)
                
                Spacer()
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            let nsSentence = originalSentence as NSString
                            ForEach(0..<nsSentence.length, id: \.self) { index in
                                let char = nsSentence.substring(with: NSRange(location: index, length: 1))
                                let isSelected = (index >= selectedWordOffset && index < selectedWordOffset + selectedWordLength)
                                Text(char)
                                    .font(.title3)
                                    .bold(isSelected)
                                    .underline(isSelected)
                                    .foregroundColor(isSelected ? .blue : .primary)
                                    .id("orig-\(index)")
                                    .onTapGesture {
                                        selectedWordOffset = index
                                        selectedWordLength = 1
                                        updateEditorFromSelection()
                                    }
                            }
                        }
                    }
                    .onChange(of: selectedWordOffset) { _, _ in
                        withAnimation {
                            proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("orig-\(selectedWordOffset)", anchor: .center)
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: shrinkSelectionRight) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    Button(action: expandSelectionRight) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .foregroundColor(.blue)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            
            // Hàng 2: Đoạn dịch (bold/underline các thẻ chứa từ đã chọn)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(translationTokens) { token in
                            let isSelected = (token.originalOffset < selectedWordOffset + selectedWordLength && 
                                              token.originalOffset + token.originalLength > selectedWordOffset)
                            Text(token.translatedText)
                                .font(.subheadline)
                                .bold(isSelected)
                                .underline()
                                .foregroundColor(isSelected ? .blue : .primary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                                .id("trans-\(token.id)")
                                .onTapGesture {
                                    selectedWordOffset = token.originalOffset
                                    selectedWordLength = token.originalLength
                                    updateEditorFromSelection()
                                }
                        }
                    }
                }
                .onChange(of: selectedWordOffset) { _, _ in
                    if let selectedToken = translationTokens.first(where: {
                        $0.originalOffset < selectedWordOffset + selectedWordLength && 
                        $0.originalOffset + $0.originalLength > selectedWordOffset
                    }) {
                        withAnimation {
                            proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                        }
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let selectedToken = translationTokens.first(where: {
                            $0.originalOffset < selectedWordOffset + selectedWordLength && 
                            $0.originalOffset + $0.originalLength > selectedWordOffset
                        }) {
                            withAnimation {
                                proxy.scrollTo("trans-\(selectedToken.id)", anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            
            // Hàng 3: Ô nhập nghĩa dịch
            HStack {
                TextField("Nhập nghĩa dịch...", text: $customMeaning)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !customMeaning.isEmpty {
                    Button(action: { customMeaning = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Hàng 4: Icon Quản lý tròn và gợi ý chip ngang
            HStack(spacing: 8) {
                Button(action: { showingManageDefinitionsSheet = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestionChips, id: \.self) { chip in
                            Button(action: { customMeaning = chip }) {
                                Text(chip)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(15)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Hàng 5: Nhóm nút định dạng chữ aa, Aa¹, Aa², Aa, AA
            HStack(spacing: 8) {
                ForEach(["aa", "Aa¹", "Aa²", "Aa", "AA"], id: \.self) { format in
                    Button(action: {
                        customMeaning = formatMeaning(customMeaning, style: format)
                    }) {
                        Text(format)
                            .font(.body)
                            .fontWeight(.bold)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }
            
            // Hàng 6: Hai Segment chọn Loại (Names/VP) và Phạm vi (Riêng/Chung)
            HStack(spacing: 12) {
                Picker("Loại", selection: $saveAsNameType) {
                    Text("Names").tag(true)
                    Text("VP").tag(false)
                }
                .pickerStyle(.segmented)
                
                Picker("Phạm vi", selection: $saveToBookSpecific) {
                    Text("Riêng").tag(true)
                    Text("Chung").tag(false)
                }
                .pickerStyle(.segmented)
            }
            
            // Hàng 7: Phím Cập nhật
            Button(action: saveDefinition) {
                HStack {
                    Spacer()
                    Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            
            Divider()
            
            // Quick Lookup Links
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(searchEngines) { engine in
                        Button(action: {
                            performQuickLookup(using: engine)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text(engine.name)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground).onTapGesture { hideKeyboard() })
        .presentationDetents([.height(530), .large])
        .onAppear {
            self.searchEngines = SearchEngine.loadEngines()
        }
        .sheet(isPresented: $showingManageDefinitionsSheet) {
            ManageDefinitionsView(
                word: selectedTextForDefinition,
                bookId: bookId,
                matches: $dictionaryMatches,
                onChanged: {
                    self.dictionaryMatches = getDictionaryMatches(for: selectedTextForDefinition)
                    if self.translationMode == "VP" {
                        self.customMeaning = TranslateUtils.translateMeta(selectedTextForDefinition, bookId: bookId)
                    } else {
                        self.customMeaning = getHanViet(for: selectedTextForDefinition)
                    }
                    applyTranslation()
                }
            )
        }
        .fullScreenCover(isPresented: $showingLookupBrowser) {
            BypassWebView(
                urlString: lookupUrlString
            )
        }
    }
}

// MARK: - Models for Infinite Scroll Reader

struct LoadedChapter: Identifiable, Equatable {
    let index: Int
    var title: String
    var originalTitle: String
    var originalContent: String
    var chapterContent: String
    var paragraphItems: [ParagraphItem]
    var imageUrls: [String] = []
    var isLoading: Bool = false
    var errorMessage: String = ""
    
    var id: Int { index }
}

struct ScrollTarget: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
}

// MARK: - 3D Page Flip Transition
struct PageFlipModifier: ViewModifier {
    var amount: Double
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(amount),
                axis: (x: 0.0, y: 1.0, z: 0.0),
                anchor: .leading,
                perspective: 0.5
            )
            .shadow(color: Color.black.opacity(abs(amount) > 0 ? 0.2 : 0), radius: 5, x: -5, y: 0)
    }
}

extension AnyTransition {
    static var pageFlipNext: AnyTransition {
        .modifier(
            active: PageFlipModifier(amount: -90),
            identity: PageFlipModifier(amount: 0)
        )
    }
    
    static var pageFlipPrev: AnyTransition {
        .modifier(
            active: PageFlipModifier(amount: 90),
            identity: PageFlipModifier(amount: 0)
        )
    }
}

class ParagraphTracker {
    var visibleParagraphs: Set<Int> = []
}
