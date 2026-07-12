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
    public static var activeBookId: String? = nil
    public static var activeChapterIndex: Int = -1

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allBooks: [Book]
    @Query private var allExtensions: [Extension]
    
    let bookId: String
    let extensionPackageId: String
    
    @State var chapterIndex: Int
    let onlineChapters: [ChapterResult] // Truyền vào nếu đang đọc online
    
    // Thông tin sách để tự tạo trong DB nếu chưa có (khi đọc online)
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDesc: String?
    let bookDetailUrl: String?
    let bookSourceName: String?
    
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var chapterTitle = ""
    @State private var chapterContent = ""
    @State private var showChapterTitle = true
    
    @State private var originalTitle = ""
    @State private var originalContent = ""
    
    // Highlight & Define
    @State private var selectedTextForDefinition = ""
    @State private var showingDefinitionSheet = false
    @State private var customMeaning = ""
    @AppStorage("saveToBookSpecific") private var saveToBookSpecific = true
    @AppStorage("saveAsNameType") private var saveAsNameType = false
    
    // Advanced Highlight Translation Editor
    @State private var originalSentence = ""
    @State private var selectedWordOffset = 0
    @State private var selectedWordLength = 0
    @State private var searchEngines: [SearchEngine] = []
    @State private var translationMode: String = "VP" // "VP" or "HV"
    @State private var translationTokens: [TranslationWordToken] = []
    @State private var dictionaryMatches: [DictionaryMatchInfo] = []
    @State private var showingManageDefinitionsSheet = false
    
    // Tùy chọn giao diện đọc (Novel)
    @AppStorage("readerFontSize") private var fontSize: Double = 20.0
    @AppStorage("readerLineSpacing") private var lineSpacing: Double = 10.0
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark
    @AppStorage("hasOpenedReader") private var hasOpenedReader = false
    @State private var showingSettings = false
    
    // Trình duyệt bypass Cloudflare & Import
    @State private var showingBypassBrowser = false
    @State private var showingLookupBrowser = false
    @State private var lookupUrlString = ""
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var navigateToBookDetail = false
    @State private var isGoingNext = true
    
    // TTS Configurations & State
    @StateObject private var ttsManager = TTSManager.shared
    @State private var ttsShouldAutoPlayNextChapter = false
    @State private var showingTTSSettings = false
    @State private var ttsResumeParagraphIndex: Int? = nil
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State private var prefetchTask: Task<Void, Never>? = nil
    @State private var editingParagraphIndex: Int? = nil
    @State private var editingChapterIndex: Int? = nil
    @State private var scrollTarget: ScrollTarget? = nil
    @State private var isAutoScrollDisabled = false
    
    @State private var loadedChapters: [LoadedChapter] = []
    @State private var hasScrolledToTop = false
    
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
                    .transition(isGoingNext ? .pageFlipNext : .pageFlipPrev)
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
        .sheet(isPresented: $showingTTSSettings, onDismiss: {
            if let resumeParagraphIdx = ttsResumeParagraphIndex {
                ttsManager.startSpeaking(
                    bookId: bookId,
                    chapters: ttsChaptersQueue,
                    currentIndex: chapterIndex,
                    chapterContent: isTranslationEnabled ? chapterContent : originalContent,
                    startParagraphIndex: resumeParagraphIdx,
                    bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                    coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
                    extensionInfo: ttsExtensionInfo
                )
                ttsResumeParagraphIndex = nil
            }
        }) {
            TTSSettingsSheet()
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
                localPath: ext?.localPath,
                onImport: { detailUrl, packageId, sourceName in
                    importedBookId = "\(sourceName.lowercased())_\(detailUrl)"
                    importedExtensionPackageId = packageId
                    importedDetailUrl = detailUrl
                    importedSourceName = sourceName
                    navigateToBookDetail = true
                }
            )
        }
        .background(
            NavigationLink(
                destination: BookDetailView(
                    bookId: importedBookId,
                    extensionPackageId: importedExtensionPackageId,
                    initialDetailUrl: importedDetailUrl,
                    sourceName: importedSourceName
                ),
                isActive: $navigateToBookDetail
            ) {
                EmptyView()
            }
        )

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
            
            // Khởi tạo chương hiện tại
            let currentChapter = LoadedChapter(
                index: chapterIndex,
                title: "Chương \(chapterIndex + 1)",
                originalTitle: "Chương \(chapterIndex + 1)",
                originalContent: "",
                chapterContent: "",
                paragraphItems: [],
                isLoading: true
            )
            self.loadedChapters = [currentChapter]
            self.hasScrolledToTop = false
            
            // Kích hoạt tải nội dung chương hiện tại
            loadChapterContent(index: chapterIndex)
            
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
        }
        .onChange(of: chapterIndex) { _, newValue in
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
            guard !isAutoScrollDisabled else { return }
            guard ttsManager.isPlaying &&
                  ttsManager.playingBookId == bookId &&
                  ttsManager.playingChapterIndex == chapterIndex &&
                  newValue >= 0 else { return }
            
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
        for chapter in loadedChapters {
            applyTranslationForChapter(index: chapter.index, originalTitle: chapter.originalTitle, originalContent: chapter.originalContent)
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
        LazyVStack(alignment: .leading, spacing: fontSize * 0.8) {
            ForEach(chapter.paragraphItems) { item in
                let textLen = (isTranslationEnabled ? item.translated : item.original).count
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
                    isTranslationEnabled: isTranslationEnabled,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    theme: selectedTheme,
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

    private func loadChapterContent(index: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let info: (title: String, url: String)
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            guard index < sorted.count else { return }
            let chap = sorted[index]
            info = (chap.title, chap.url)
        } else {
            guard index < currentOnlineChapters.count else { return }
            let chap = currentOnlineChapters[index]
            info = (chap.name, chap.url)
        }
        
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
        
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            if index < sorted.count {
                let chap = sorted[index]
                if chap.isCached, let content = chap.content, !content.isEmpty {
                    let cleanedContent = cleanBlankLines(in: content.cleanHTML())
                    applyTranslationForChapter(index: index, originalTitle: info.title, originalContent: cleanedContent)
                    return
                }
            }
        }
        
        guard let ext = ext else {
            updateChapterError(index: index, message: "Không tìm thấy tiện ích bóc tách!")
            return
        }
        
        Task {
            do {
                let content = try await ExtensionManager.shared.chap(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: info.url, configJson: ext.configJson)
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
                    } else {
                        saveOnlineBookIfNeeded(currentIndex: index, cleanedContent: cleanedContent, info: info)
                    }
                    
                    applyTranslationForChapter(index: index, originalTitle: info.title, originalContent: cleanedContent)
                }
            } catch {
                await MainActor.run {
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
            isHistory: true
        )
        modelContext.insert(newBook)
        
        for (idx, item) in currentOnlineChapters.enumerated() {
            let chapId = "\(newBook.bookId)_\(item.url)"
            let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: idx)
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
        
        if isTranslationEnabled {
            Task {
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
        guard let idx = loadedChapters.firstIndex(where: { $0.index == index }) else { return }
        
        if ext?.type == "comic" {
            let urls = translatedContent.components(separatedBy: "\n").filter { !$0.isEmpty }
            loadedChapters[idx].imageUrls = urls
        } else {
            let items = generateParagraphItems(chapterIndex: index, originalTitle: originalTitle, originalContent: originalContent, translatedTitle: translatedTitle, translatedContent: translatedContent)
            loadedChapters[idx].paragraphItems = items
        }
        
        loadedChapters[idx].originalTitle = originalTitle
        loadedChapters[idx].originalContent = originalContent
        loadedChapters[idx].title = translatedTitle
        loadedChapters[idx].chapterContent = translatedContent
        loadedChapters[idx].isLoading = false
        loadedChapters[idx].errorMessage = ""
        
        saveReadProgress(index: index)
        
        if self.ttsShouldAutoPlayNextChapter && index == chapterIndex {
            self.ttsShouldAutoPlayNextChapter = false
            startTTS(at: index, paragraphIndex: -1)
        }
        
        prefetchNextChapter()
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
        guard let info = currentChapterInfo else { return }
        guard let ext = ext else { return }
        
        if let idx = loadedChapters.firstIndex(where: { $0.index == index }) {
            loadedChapters[idx].isLoading = true
            loadedChapters[idx].errorMessage = ""
        }
        
        Task {
            do {
                let content = try await ExtensionManager.shared.chap(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: info.url, configJson: ext.configJson)
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
        
        let currentChapter = LoadedChapter(
            index: index,
            title: "Chương \(index + 1)",
            originalTitle: "Chương \(index + 1)",
            originalContent: "",
            chapterContent: "",
            paragraphItems: [],
            isLoading: true
        )
        
        withAnimation(.easeInOut(duration: 0.45)) {
            self.chapterIndex = index
            self.loadedChapters = [currentChapter]
            self.hasScrolledToTop = false
        }
        
        loadChapterContent(index: index)
    }
    

    
    private func startTTS(at index: Int, paragraphIndex: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let chapterContentToUse: String
        if let loaded = loadedChapters.first(where: { $0.index == index }) {
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
    
    private func saveReadProgress(index: Int) {
        guard index >= 0 && index < totalChaptersCount else { return }
        
        let title: String
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            guard index < sorted.count else { return }
            let chap = sorted[index]
            title = chap.title
            
            book.currentChapterIndex = index
            book.currentChapterTitle = title
            book.isHistory = true
            book.lastReadDate = Date()
            try? modelContext.save()
        } else {
            guard index < currentOnlineChapters.count else { return }
            let chap = currentOnlineChapters[index]
            title = chap.name
            
            if let book = allBooks.first(where: { $0.bookId == bookId }) {
                book.currentChapterIndex = index
                book.currentChapterTitle = title
                book.isHistory = true
                book.lastReadDate = Date()
                try? modelContext.save()
            }
        }
    }

    
    private func prefetchNextChapter() {
        prefetchTask?.cancel()
        
        let nextIdx = chapterIndex + 1
        guard nextIdx < totalChaptersCount else { return }
        
        prefetchTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            
            let sortedChapters: [Chapter]
            let targetUrl: String
            let targetTitle: String
            
            if let book = localBook {
                sortedChapters = book.chapters.sorted(by: { $0.index < $1.index })
                guard nextIdx < sortedChapters.count else { return }
                let nextChap = sortedChapters[nextIdx]
                if nextChap.isCached && nextChap.content?.isEmpty == false {
                    return
                }
                targetUrl = nextChap.url
                targetTitle = nextChap.title
            } else {
                guard nextIdx < currentOnlineChapters.count else { return }
                let nextChap = currentOnlineChapters[nextIdx]
                targetUrl = nextChap.url
                targetTitle = nextChap.name
            }
            
            guard let ext = ext else { return }
            
            do {
                AppLogger.shared.log("Tải trước chương \(nextIdx): \(targetTitle)")
                let content = try await ExtensionManager.shared.chap(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    url: targetUrl,
                    configJson: ext.configJson
                )
                let cleanedContent = content.cleanHTML()
                
                if let book = localBook {
                    let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                    let chap = sorted[nextIdx]
                    chap.content = cleanedContent
                    chap.isCached = true
                    try? modelContext.save()
                    AppLogger.shared.log("Tải trước thành công và cache chương \(nextIdx)")
                }
            } catch {
                AppLogger.shared.log("Lỗi tải trước chương \(nextIdx): \(error.localizedDescription)")
            }
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

// MARK: - TTS Settings Sheet View

struct TTSSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var ttsManager = TTSManager.shared
    @State private var availableVoices: [Voice] = []
    @State private var systemVoices: [AVSpeechSynthesisVoice] = []
    
    @Query private var allExtensions: [Extension]
    
    private var ttsExtensions: [Extension] {
        allExtensions.filter { $0.type == "tts" && !$0.localPath.isEmpty && $0.isEnabled }
    }
    
    @State private var extensionVoices: [[String: String]] = []
    @State private var isLoadingVoices = false
    
    private var hasNoDictionary: Bool {
        let path = (try? ModelStore())?.rootURL.appendingPathComponent("non-vietnamese-words.plist").path ?? ""
        return !FileManager.default.fileExists(atPath: path)
    }
    
    private func loadExtensionVoices(packageId: String) {
        guard let ext = allExtensions.first(where: { $0.packageId == packageId }) else { return }
        isLoadingVoices = true
        Task {
            do {
                let voices = try await ExtensionManager.shared.ttsVoices(
                    localPath: ext.localPath,
                    downloadUrl: ext.downloadUrl,
                    configJson: ext.configJson
                )
                await MainActor.run {
                    self.extensionVoices = voices
                    self.isLoadingVoices = false
                    
                    let voiceIds = voices.compactMap { $0["id"] }
                    if !voiceIds.contains(ttsManager.selectedVoice) {
                        if let firstVoice = voiceIds.first {
                            ttsManager.selectedVoice = firstVoice
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.extensionVoices = []
                    self.isLoadingVoices = false
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Công cụ đọc") {
                    Picker("Trình đọc", selection: $ttsManager.tool) {
                        Text("Siri (Hệ thống Apple)").tag("system")
                        Text("NghiTTS (Piper Offline)").tag("nghitts")
                        ForEach(ttsExtensions) { ext in
                            Text(ext.name).tag(ext.packageId)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Giọng đọc") {
                    if ttsManager.tool == "system" {
                        Picker("Giọng đọc Siri", selection: $ttsManager.selectedVoice) {
                            ForEach(systemVoices, id: \.identifier) { voice in
                                Text("\(voice.name) (\(voice.quality == .premium ? "Premium" : "Default"))")
                                    .tag(voice.identifier)
                            }
                        }
                        .pickerStyle(.menu)
                    } else if ttsManager.tool == "nghitts" {
                        let downloadedVoices = availableVoices.filter { isModelDownloaded($0) }
                        let hasNoModels = downloadedVoices.isEmpty
                        let missingDict = hasNoDictionary
                        
                        if hasNoModels || missingDict {
                            VStack(alignment: .leading, spacing: 10) {
                                if hasNoModels {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Chưa tải giọng đọc NghiTTS nào")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if missingDict {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Chưa tải thư viện phiên âm")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                if hasNoModels {
                                    NavigationLink(destination: TTSModelManagerView()) {
                                        Text("Tải model")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                                if missingDict {
                                    NavigationLink(destination: TTSDictionaryEditView()) {
                                        Text("Tải thư viện phiên âm")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Picker("Giọng đọc NghiTTS", selection: $ttsManager.selectedVoice) {
                                ForEach(downloadedVoices, id: \.name) { voice in
                                    Text(voice.name)
                                        .tag(voice.name)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            NavigationLink(destination: TTSModelManagerView()) {
                                Label("Quản lý Model", systemImage: "waveform.and.mic")
                            }

                            NavigationLink(destination: TTSDictionaryEditView()) {
                                Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
                            }
                        }
                    } else {
                        // Trình đọc từ Extension
                        if isLoadingVoices {
                            ProgressView("Đang tải giọng đọc...")
                        } else if extensionVoices.isEmpty {
                            Text("Không có giọng đọc nào")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Giọng đọc Extension", selection: $ttsManager.selectedVoice) {
                                ForEach(0..<extensionVoices.count, id: \.self) { idx in
                                    let voice = extensionVoices[idx]
                                    let id = voice["id"] ?? ""
                                    let name = voice["name"] ?? id
                                    let lang = voice["language"] ?? ""
                                    Text("\(name) (\(lang))").tag(id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                if ttsManager.tool != "system" && ttsManager.tool != "nghitts" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }),
                       ExtensionManager.shared.hasConfig(localPath: ext.localPath) {
                        Section("Cấu hình") {
                            NavigationLink(destination: ExtensionConfigView(ext: ext)) {
                                Label("Cấu hình \(ext.name)", systemImage: "gearshape")
                            }
                        }
                    }
                }
                
                if ttsManager.tool == "nghitts" {
                    Section("NghiTTS (Piper Offline)") {
                        NavigationLink(destination: NghiTTSSettingsView()) {
                            Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
                        }
                    }
                }
                
                Section("Cấu hình giọng nói") {
                    VStack(alignment: .leading) {
                         HStack {
                             Text("Tốc độ:")
                             Spacer()
                             Text(String(format: "%.1fx", ttsManager.speed))
                                 .font(.system(.body, design: .monospaced))
                         }
                         Slider(value: $ttsManager.speed, in: 0.5...5.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading) {
                         HStack {
                             Text("Cao độ (Pitch):")
                             Spacer()
                             Text(String(format: "%.1fx", ttsManager.pitch))
                                 .font(.system(.body, design: .monospaced))
                         }
                         Slider(value: $ttsManager.pitch, in: 0.5...2.0, step: 0.1)
                             .disabled(ttsManager.tool == "nghitts")
                         if ttsManager.tool == "nghitts" {
                             Text("(*) NghiTTS không hỗ trợ chỉnh cao độ thời gian thực")
                                 .font(.caption2)
                                 .foregroundColor(.secondary)
                         }
                    }
                    
                    HStack {
                        Text("Độ dài phân đoạn (ký tự)")
                        Spacer()
                        TextField("200", value: $ttsManager.chunkLength, formatter: NumberFormatter())
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .navigationTitle("Cài đặt TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                            ttsManager.extensionConfigJson = ext.configJson
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                self.systemVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }
                
                if ttsManager.tool == "system" && ttsManager.selectedVoice.isEmpty {
                    ttsManager.selectedVoice = systemVoices.first?.identifier ?? ""
                }
                
                if ttsManager.tool != "system" && ttsManager.tool != "nghitts" {
                    if let ext = allExtensions.first(where: { $0.packageId == ttsManager.tool }) {
                        ttsManager.extensionLocalPath = ext.localPath
                        ttsManager.extensionConfigJson = ext.configJson
                    }
                    loadExtensionVoices(packageId: ttsManager.tool)
                }
                
                Task {
                    self.availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
                }
            }
            .onChange(of: ttsManager.tool) { _, newVal in
                if newVal != "system" && newVal != "nghitts" {
                    if let ext = allExtensions.first(where: { $0.packageId == newVal }) {
                        ttsManager.extensionLocalPath = ext.localPath
                        ttsManager.extensionConfigJson = ext.configJson
                    }
                    loadExtensionVoices(packageId: newVal)
                } else {
                    ttsManager.extensionLocalPath = ""
                    ttsManager.extensionConfigJson = "{}"
                }
            }
        }
    }
    
    private func isModelDownloaded(_ voice: Voice) -> Bool {
        return (try? ModelStore().modelExists(for: voice.id)) ?? false
    }
    
    private func deleteModel(_ voice: Voice) {
        try? ModelStore().deleteModel(for: voice.id)
        if ttsManager.selectedVoice == voice.name {
            ttsManager.selectedVoice = ""
        }
        Task {
            self.availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
        }
    }
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
        if loadedChapters.isEmpty {
            chapterLoadingView
        } else if ext?.type == "comic" {
            comicReaderView
        } else {
            textReaderView
        }
    }
    
    @ViewBuilder
    private var chapterLoadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(selectedTheme.textColor.opacity(0.8))
            
            VStack(spacing: 8) {
                if let info = currentChapterInfo {
                    let displayTitle = isTranslationEnabled && TranslateUtils.containsChinese(info.title)
                        ? TranslateUtils.translateChapterTitle(info.title, bookId: bookId)
                        : info.title
                    Text(displayTitle)
                        .font(.headline)
                        .foregroundColor(selectedTheme.textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                }
                
                Text("Đang tải nội dung chương...")
                    .font(.subheadline)
                    .foregroundColor(selectedTheme.textColor.opacity(0.6))
            }
            
            if !errorMessage.isEmpty {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Thử lại") {
                        loadChapterContent(index: chapterIndex)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTheme.textColor)
                }
            }
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                    Text("Thoát")
                        .fontWeight(.medium)
                }
                .foregroundColor(selectedTheme.textColor.opacity(0.7))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(selectedTheme.textColor.opacity(0.1))
                .cornerRadius(25)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var comicReaderView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(loadedChapters) { chapter in
                        VStack(spacing: 0) {
                            if chapter.isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(selectedTheme.textColor)
                                    Spacer()
                                }
                                .padding(.vertical, 40)
                            } else if !chapter.errorMessage.isEmpty {
                                VStack(spacing: 12) {
                                    Text(chapter.errorMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                    Button("Thử lại") {
                                        loadChapterContent(index: chapter.index)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.vertical, 40)
                            } else {
                                ForEach(chapter.imageUrls, id: \.self) { urlString in
                                    AsyncImage(url: URL(string: urlString)) { image in
                                        image.resizable()
                                            .aspectRatio(contentMode: .fit)
                                    } placeholder: {
                                        HStack {
                                            Spacer()
                                            ProgressView()
                                                .padding(.vertical, 40)
                                            Spacer()
                                        }
                                        .background(Color.gray.opacity(0.1))
                                    }
                                }
                            }
                        }
                        .id("chapter-\(chapter.index)")
                    }
                    
                    // Dòng hướng dẫn chuyển chương bằng vuốt ngang ở cuối trang hình ảnh
                    VStack(spacing: 8) {
                        Divider()
                            .background(selectedTheme.textColor.opacity(0.15))
                            .padding(.vertical, 16)
                        
                        Text("Hết chương \(chapterIndex + 1)")
                            .font(.subheadline)
                            .foregroundColor(selectedTheme.textColor.opacity(0.6))
                        
                        Text("← Vuốt phải để xem chương trước | Vuốt trái để sang chương sau →")
                            .font(.caption)
                            .foregroundColor(selectedTheme.textColor.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                }
            }
            .coordinateSpace(name: "scroll")
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontalDistance = value.translation.width
                        let verticalDistance = value.translation.height
                        
                        if abs(horizontalDistance) > 80 && abs(verticalDistance) < 80 {
                            if horizontalDistance < 0 {
                                nextChapter()
                            } else {
                                prevChapter()
                            }
                        }
                    }
            )
            .onChange(of: loadedChapters) { oldVal, newVal in
                if !hasScrolledToTop {
                    if let currentChap = newVal.first(where: { $0.index == chapterIndex }),
                       !currentChap.isLoading {
                        DispatchQueue.main.async {
                            proxy.scrollTo("chapter-\(chapterIndex)", anchor: .top)
                            hasScrolledToTop = true
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var textReaderView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(loadedChapters) { chapter in
                        VStack(alignment: .leading, spacing: 20) {
                            if chapter.isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(selectedTheme.textColor)
                                    Spacer()
                                }
                                .padding()
                            } else if !chapter.errorMessage.isEmpty {
                                VStack(spacing: 12) {
                                    Text(chapter.errorMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                    Button("Thử lại") {
                                        loadChapterContent(index: chapter.index)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            } else {
                                chapterContentView(for: chapter)
                            }
                        }
                        .id("chapter-\(chapter.index)")
                    }
                    
                    // Dòng hướng dẫn chuyển chương bằng vuốt ngang ở cuối trang
                    VStack(spacing: 8) {
                        Divider()
                            .background(selectedTheme.textColor.opacity(0.15))
                            .padding(.vertical, 16)
                        
                        Text("Hết chương \(chapterIndex + 1)")
                            .font(.subheadline)
                            .foregroundColor(selectedTheme.textColor.opacity(0.6))
                        
                        Text("← Vuốt phải để xem chương trước | Vuốt trái để sang chương sau →")
                            .font(.caption)
                            .foregroundColor(selectedTheme.textColor.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 60)
                    .frame(maxWidth: .infinity)
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
            .coordinateSpace(name: "scroll")
            .simultaneousGesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onEnded { value in
                        let horizontalDistance = value.translation.width
                        let verticalDistance = value.translation.height
                        
                        if abs(horizontalDistance) > 80 && abs(verticalDistance) < 80 {
                            if horizontalDistance < 0 {
                                nextChapter()
                            } else {
                                prevChapter()
                            }
                        }
                    }
            )
            .onChange(of: scrollTarget) { _, newValue in
                if let target = newValue {
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
            .onChange(of: loadedChapters) { oldVal, newVal in
                if !hasScrolledToTop {
                    if let currentChap = newVal.first(where: { $0.index == chapterIndex }),
                       !currentChap.isLoading {
                        DispatchQueue.main.async {
                            proxy.scrollTo("chapter-\(chapterIndex)", anchor: .top)
                            hasScrolledToTop = true
                        }
                    }
                }
            }
            .onChange(of: showChapterTitle) { _, _ in
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
        if ext?.type != "comic" {
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
                    Label("Mở bằng trình duyệt (Bypass)", systemImage: "safari")
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
                            Label("Mở bằng trình duyệt (Bypass)", systemImage: "safari")
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
                urlString: lookupUrlString,
                localPath: nil
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
