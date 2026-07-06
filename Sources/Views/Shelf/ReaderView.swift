import SwiftUI
import SwiftData
import AVFoundation

enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper = "Mặc định"
    case sepia = "Trầm ấm"
    case dark = "Chế độ tối"
    
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
    @Environment(\.modelContext) private var modelContext
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
    @AppStorage("readerFontSize") private var fontSize: Double = 18.0
    @AppStorage("readerLineSpacing") private var lineSpacing: Double = 6.0
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark
    @State private var showingSettings = false
    
    // TTS Configurations & State
    @StateObject private var ttsManager = TTSManager.shared
    @State private var showingTTSPanel = false
    @State private var showingTTSSettings = false
    @State private var ttsResumeCharIndex: Int? = nil
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State private var prefetchTask: Task<Void, Never>? = nil
    
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
                TTSChapterInfo(
                    title: chap.title,
                    url: chap.url,
                    index: chap.index,
                    cachedContent: chap.isCached ? chap.content : nil
                )
            }
        } else {
            return onlineChapters.enumerated().map { (index, chap) in
                TTSChapterInfo(
                    title: chap.name,
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
        return onlineChapters.count
    }
    
    // Lấy thông tin chương hiện tại (Title, URL)
    private var currentChapterInfo: (title: String, url: String)? {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return nil }
        
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            let chap = sorted[chapterIndex]
            return (chap.title, chap.url)
        } else {
            let chap = onlineChapters[chapterIndex]
            return (chap.name, chap.url)
        }
    }
    
    var body: some View {
        ZStack {
            // Nền theo theme
            selectedTheme.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Nội dung chính
                if isLoading {
                    ProgressView()
                        .tint(selectedTheme.textColor)
                        .scaleEffect(1.2)
                        .frame(maxHeight: .infinity)
                } else if !errorMessage.isEmpty {
                    VStack(spacing: 16) {
                        Text("Không tải được chương")
                            .font(.headline)
                            .foregroundColor(selectedTheme.textColor)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Thử lại") {
                            loadChapterContent()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                } else {
                    if ext?.type == "comic" {
                        // HIỂN THỊ TRUYỆN TRANH (Webtoon style)
                        let imageUrls = chapterContent.components(separatedBy: "\n").filter { !$0.isEmpty }
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(imageUrls, id: \.self) { urlString in
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
                                
                                navigationButtons
                                    .padding(.vertical, 24)
                            }
                        }
                    } else {
                        // HIỂN THỊ TRUYỆN CHỮ
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Text(chapterTitle)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(selectedTheme.textColor)
                                    .padding(.top, 16)
                                
                                ReaderTextView(
                                    text: chapterContent,
                                    fontSize: fontSize,
                                    lineSpacing: lineSpacing,
                                    theme: selectedTheme,
                                    highlightRange: isCurrentlyPlayingThisChapter ? ttsManager.highlightRange : nil,
                                    triggerGetVisibleIndex: $triggerGetVisibleIndex,
                                    onGetVisibleIndex: { charIndex in
                                        ttsManager.startSpeaking(
                                            bookId: bookId,
                                            chapters: ttsChaptersQueue,
                                            currentIndex: chapterIndex,
                                            startCharIndex: charIndex,
                                            bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                                            extensionInfo: ttsExtensionInfo
                                        )
                                    },
                                    onSelectionChange: { selectedText, sentence, offset, absoluteOffset in
                                        if isTranslationEnabled {
                                            let vietSentenceRanges = TranslateUtils.getSentenceRanges(in: chapterContent)
                                            if let sentenceIdx = vietSentenceRanges.firstIndex(where: { 
                                                $0.range.location <= absoluteOffset && absoluteOffset < $0.range.location + $0.range.length 
                                            }) {
                                                let vietSentenceRange = vietSentenceRanges[sentenceIdx]
                                                let offsetInVietSentence = absoluteOffset - vietSentenceRange.range.location
                                                
                                                let chiSentenceRanges = TranslateUtils.getSentenceRanges(in: originalContent)
                                                if sentenceIdx < chiSentenceRanges.count {
                                                    let chiSentenceRange = chiSentenceRanges[sentenceIdx]
                                                    let chiSentence = chiSentenceRange.text
                                                    let tokens = TranslateUtils.getTranslationTokens(for: chiSentence, bookId: bookId)
                                                     
                                                     // Dựng bản đồ ký tự không khoảng trắng cho câu tiếng Việt hiển thị
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
                                                     
                                                     // Tìm phạm vi non-space của vùng bôi đen
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
                                                     
                                                     // Dựng phạm vi non-space cho từng token
                                                     var tokenNonSpaceRanges: [NSRange] = []
                                                     var reconstructedNonSpaceCount = 0
                                                     for token in tokens {
                                                         var tokenNonSpaceLen = 0
                                                         let tokenNS = token.translatedText as NSString
                                                         for i in 0..<tokenNS.length {
                                                             let charCode = tokenNS.character(at: i)
                                                             if let unicodeScalar = UnicodeScalar(charCode), whitespaceSet.contains(unicodeScalar) {
                                                                 // Bỏ qua khoảng trắng
                                                             } else {
                                                                 tokenNonSpaceLen += 1
                                                             }
                                                         }
                                                         tokenNonSpaceRanges.append(NSRange(location: reconstructedNonSpaceCount, length: tokenNonSpaceLen))
                                                         reconstructedNonSpaceCount += tokenNonSpaceLen
                                                     }
                                                     
                                                     // So khớp overlap
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
                                                    
                                                    if !overlappingIndices.isEmpty {
                                                        let firstIdx = overlappingIndices.first!
                                                        let lastIdx = overlappingIndices.last!
                                                        let chiOffset = tokens[firstIdx].originalOffset
                                                        let chiLength = (tokens[lastIdx].originalOffset + tokens[lastIdx].originalLength) - chiOffset
                                                        
                                                        let snapped = TranslateUtils.snapToToken(
                                                            sentence: chiSentence,
                                                            selectionOffset: chiOffset,
                                                            selectionLength: chiLength,
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
                                            }
                                        }
                                        
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
                                    },
                                    onSpeakFromHere: { absoluteOffset in
                                        ttsManager.startSpeaking(
                                            bookId: bookId,
                                            chapters: ttsChaptersQueue,
                                            currentIndex: chapterIndex,
                                            startCharIndex: absoluteOffset,
                                            bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                                            extensionInfo: ttsExtensionInfo
                                        )
                                        showingTTSPanel = true
                                    }
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Divider()
                                    .background(selectedTheme.textColor.opacity(0.2))
                                
                                navigationButtons
                                    .padding(.vertical, 16)
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                }
            }
             if showingTTSPanel {
                 TTSControlPanelView(
                     showingTTSPanel: $showingTTSPanel,
                     showingTTSSettings: $showingTTSSettings,
                     ttsResumeCharIndex: $ttsResumeCharIndex
                 )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .navigationTitle(currentChapterInfo?.title ?? "Trình đọc")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(selectedTheme == .dark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                            showingTTSPanel = false
                        } else {
                            triggerGetVisibleIndex = UUID()
                            showingTTSPanel = true
                        }
                    }) {
                        Image(systemName: ttsManager.isPlaying ? "stop.circle.fill" : "play.circle")
                            .foregroundColor(ttsManager.isPlaying ? .red : selectedTheme.textColor)
                    }
                    
                    // Dictionary Manager Link
                    // Dictionary Manager, Reload, and Settings collapsed in a Menu
                    Menu {
                        Button(action: {
                            reloadChapterContent()
                        }) {
                            Label("Tải lại chương", systemImage: "arrow.clockwise")
                        }
                        
                        if localBook != nil {
                            NavigationLink(destination: BookDictionaryView(bookId: bookId)) {
                                Label("Từ điển truyện", systemImage: "character.book.closed")
                            }
                        }
                        
                        Button(action: {
                            showingSettings.toggle()
                        }) {
                            Label("Cấu hình đọc (AA)", systemImage: "textformat.size")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(selectedTheme.textColor)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(fontSize: $fontSize, lineSpacing: $lineSpacing, selectedTheme: $selectedTheme, isTranslationEnabled: $isTranslationEnabled)
                .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showingTTSSettings, onDismiss: {
            if let resumeIdx = ttsResumeCharIndex {
                ttsManager.startSpeaking(
                    bookId: bookId,
                    chapters: ttsChaptersQueue,
                    currentIndex: chapterIndex,
                    startCharIndex: resumeIdx,
                    bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                    extensionInfo: ttsExtensionInfo
                )
                ttsResumeCharIndex = nil
            }
        }) {
            TTSSettingsSheet()
        }
        .onChange(of: isTranslationEnabled) { _, _ in
            applyTranslation()
        }
        .sheet(isPresented: $showingDefinitionSheet) {
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
                    HStack(spacing: 4) {
                        Button(action: expandSelectionLeft) {
                            Image(systemName: "chevron.left")
                        }
                        Button(action: shrinkSelectionLeft) {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundColor(.blue)
                    .font(.subheadline)
                    
                    Spacer()
                    
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(translationTokens) { token in
                                    let isSelected = (token.originalOffset < selectedWordOffset + selectedWordLength && 
                                                      token.originalOffset + token.originalLength > selectedWordOffset)
                                    Text(token.originalText)
                                        .font(.title3)
                                        .bold(isSelected)
                                        .underline()
                                        .foregroundColor(isSelected ? .blue : .primary)
                                        .id("orig-\(token.id)")
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
                                    proxy.scrollTo("orig-\(selectedToken.id)", anchor: .center)
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
                                        proxy.scrollTo("orig-\(selectedToken.id)", anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Button(action: shrinkSelectionRight) {
                            Image(systemName: "chevron.left")
                        }
                        Button(action: expandSelectionRight) {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .foregroundColor(.blue)
                    .font(.subheadline)
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
                
                // Hàng 4: Icon Quản lý tròn và Danh sách gợi ý chip ngang
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
                
                // Hàng 5: Nhóm nút định dạng chữ aa, Aa1, Aa2, AA dàn đều cả hàng
                HStack(spacing: 8) {
                    ForEach(["aa", "Aa¹", "Aa²", "AA"], id: \.self) { format in
                        Button(action: {
                            switch format {
                            case "aa":
                                customMeaning = customMeaning.lowercased()
                            case "Aa¹":
                                if !customMeaning.isEmpty {
                                    customMeaning = customMeaning.prefix(1).uppercased() + customMeaning.dropFirst().lowercased()
                                }
                            case "Aa²":
                                customMeaning = customMeaning.capitalized
                            case "AA":
                                customMeaning = customMeaning.uppercased()
                            default:
                                break
                            }
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
                
                // Hàng 6: Hai Segment chọn Loại (Names/VP) và Phạm vi (Riêng/Chung) trên cùng 1 hàng
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
                
                // Hàng 7: Phím Cập nhật đứng riêng 1 hàng dưới cùng
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
        }
        .sheet(isPresented: $showingManageDefinitionsSheet) {
            ManageDefinitionsView(
                word: selectedTextForDefinition,
                bookId: bookId,
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
        .onAppear {
            // Tải theme mặc định từ AppStorage nếu thích hợp, ở đây dùng sepia/paper làm mặc định
            loadChapterContent()
            
            ttsManager.onChapterFinished = {
                nextChapter()
            }
            ttsManager.onChapterNext = {
                nextChapter()
            }
            ttsManager.onChapterPrev = {
                prevChapter()
            }
        }
        .onDisappear {
            prefetchTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidAdvanceToNextChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  let nextIdx = userInfo["chapterIndex"] as? Int else { return }
            
            if bid == bookId && nextIdx != chapterIndex {
                chapterIndex = nextIdx
                loadChapterContent()
            }
        }
    }
    
    // Nút chuyển chương
    private var navigationButtons: some View {
        HStack {
            Button(action: prevChapter) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Chương trước")
                }
                .fontWeight(.semibold)
                .foregroundColor(selectedTheme.textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selectedTheme.textColor.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(chapterIndex <= 0)
            .opacity(chapterIndex <= 0 ? 0.3 : 1.0)
            
            Spacer()
            
            Button(action: nextChapter) {
                HStack {
                    Text("Chương sau")
                    Image(systemName: "chevron.right")
                }
                .fontWeight(.semibold)
                .foregroundColor(selectedTheme.textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selectedTheme.textColor.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(chapterIndex >= totalChaptersCount - 1)
            .opacity(chapterIndex >= totalChaptersCount - 1 ? 0.3 : 1.0)
        }
    }
    
    private func applyTranslation() {
        let titleToUse = currentChapterInfo?.title ?? "Trình đọc"
        self.originalTitle = titleToUse
        
        if isTranslationEnabled {
            self.isLoading = true
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
                    self.chapterTitle = translatedTitle
                    self.chapterContent = translatedContent
                    self.isLoading = false
                    prefetchNextChapter()
                }
            }
        } else {
            self.chapterTitle = originalTitle
            self.chapterContent = originalContent
            self.isLoading = false
            prefetchNextChapter()
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
        
        // 2. Global Names
        if let names = manager.namesDict,
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
        
        // 6. Global VietPhrase (Chung)
        if let vp = manager.vietPhraseDict,
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
        let tokens = translationTokens
        guard !tokens.isEmpty else { return }
        let selected = selectedTokens
        guard let firstSelected = selected.first else { return }
        
        if let idx = tokens.firstIndex(where: { $0.originalOffset == firstSelected.originalOffset }), idx > 0 {
            let prevToken = tokens[idx - 1]
            selectedWordLength = (selectedWordOffset + selectedWordLength) - prevToken.originalOffset
            selectedWordOffset = prevToken.originalOffset
            updateEditorFromSelection()
        }
    }
    
    private func shrinkSelectionLeft() {
        let tokens = translationTokens
        let selected = selectedTokens
        guard selected.count > 1, let firstSelected = selected.first else { return }
        
        if let idx = tokens.firstIndex(where: { $0.originalOffset == firstSelected.originalOffset }), idx < tokens.count - 1 {
            let nextToken = tokens[idx + 1]
            selectedWordLength = (selectedWordOffset + selectedWordLength) - nextToken.originalOffset
            selectedWordOffset = nextToken.originalOffset
            updateEditorFromSelection()
        }
    }
    
    private func shrinkSelectionRight() {
        let tokens = translationTokens
        let selected = selectedTokens
        guard selected.count > 1, let lastSelected = selected.last else { return }
        
        if let idx = tokens.firstIndex(where: { $0.originalOffset == lastSelected.originalOffset }), idx > 0 {
            let prevToken = tokens[idx - 1]
            selectedWordLength = (prevToken.originalOffset + prevToken.originalLength) - selectedWordOffset
            updateEditorFromSelection()
        }
    }
    
    private func expandSelectionRight() {
        let tokens = translationTokens
        guard !tokens.isEmpty else { return }
        let selected = selectedTokens
        guard let lastSelected = selected.last else { return }
        
        if let idx = tokens.firstIndex(where: { $0.originalOffset == lastSelected.originalOffset }), idx < tokens.count - 1 {
            let nextToken = tokens[idx + 1]
            selectedWordLength = (nextToken.originalOffset + nextToken.originalLength) - selectedWordOffset
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
        if let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "Names (Chung)", translation: match.value))
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
        if let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            matches.append(DictionaryMatchInfo(source: "VietPhrase (Chung)", translation: match.value))
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
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else { return }
        
        UIApplication.shared.open(url)
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

    private func loadChapterContent() {
        guard let info = currentChapterInfo else { return }
        
        isLoading = true
        errorMessage = ""
        
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            let chap = sorted[chapterIndex]
            
            // Cập nhật tiến độ đọc và lịch sử
            book.currentChapterIndex = chapterIndex
            book.currentChapterTitle = chap.title
            book.isHistory = true
            book.lastReadDate = Date()
            try? modelContext.save()
            
            if chap.isCached, let content = chap.content, !content.isEmpty {
                self.originalContent = content.cleanHTML()
                self.applyTranslation()
                return
            }
        }
        
        guard let ext = ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách!"
            isLoading = false
            return
        }
        
        Task {
            do {
                let content = try await ExtensionManager.shared.chap(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: info.url, configJson: ext.configJson)
                let cleanedContent = content.cleanHTML()
                
                await MainActor.run {
                    self.originalContent = cleanedContent
                    self.applyTranslation()
                    
                    // Nếu là sách local, tự động lưu vào cache offline luôn (lưu bản gốc chưa dịch!)
                    if let book = localBook {
                        let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                        let chap = sorted[chapterIndex]
                        chap.content = cleanedContent
                        chap.isCached = true
                        book.currentChapterIndex = chapterIndex
                        book.currentChapterTitle = chap.title
                        book.isHistory = true
                        book.lastReadDate = Date()
                        try? modelContext.save()
                    } else {
                        // Nếu sách chưa có trong DB (đang đọc online), tự tạo bản ghi lịch sử đọc!
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
                            currentChapterIndex: chapterIndex,
                            currentChapterTitle: info.title,
                            isOnShelf: false,
                            isHistory: true
                        )
                        modelContext.insert(newBook)
                        
                        // Thêm toàn bộ danh sách chương vào database
                        for (index, item) in onlineChapters.enumerated() {
                            let chapId = "\(newBook.bookId)_\(item.url)"
                            let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: index)
                            newChap.book = newBook
                            if index == chapterIndex {
                                newChap.content = cleanedContent
                                newChap.isCached = true
                            }
                            modelContext.insert(newChap)
                        }
                        try? modelContext.save()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func reloadChapterContent() {
        guard let info = currentChapterInfo else { return }
        guard let ext = ext else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let content = try await ExtensionManager.shared.chap(localPath: ext.localPath, downloadUrl: ext.downloadUrl, url: info.url, configJson: ext.configJson)
                let cleanedContent = content.cleanHTML()
                
                await MainActor.run {
                    self.originalContent = cleanedContent
                    self.applyTranslation()
                    
                    // Cập nhật nội dung cache mới nhất vào database
                    if let book = localBook {
                        let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                        if chapterIndex < sorted.count {
                            let chap = sorted[chapterIndex]
                            chap.content = cleanedContent
                            chap.isCached = true
                            try? modelContext.save()
                        }
                    }
                    
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Không thể tải lại chương: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func nextChapter() {
        if chapterIndex < totalChaptersCount - 1 {
            chapterIndex += 1
            loadChapterContent()
        }
    }
    
    private func prevChapter() {
        if chapterIndex > 0 {
            chapterIndex -= 1
            loadChapterContent()
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
                guard nextIdx < onlineChapters.count else { return }
                let nextChap = onlineChapters[nextIdx]
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
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
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

// MARK: - TTS Control Panel View

struct TTSControlPanelView: View {
    @Binding var showingTTSPanel: Bool
    @Binding var showingTTSSettings: Bool
    @Binding var ttsResumeCharIndex: Int?
    @ObservedObject var ttsManager = TTSManager.shared
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 12) {
                if ttsManager.isPlaying, ttsManager.paragraphs.count > 0 {
                    Text("Đang đọc đoạn \(ttsManager.currentParagraphIndex + 1)/\(ttsManager.paragraphs.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 30) {
                    Button(action: {
                        ttsManager.skipBackward()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .disabled(!ttsManager.isPlaying || ttsManager.currentParagraphIndex <= 0)
                    
                    Button(action: {
                        if ttsManager.isPlaying {
                            ttsManager.pause()
                        } else {
                            ttsManager.resume()
                        }
                    }) {
                        Image(systemName: ttsManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        ttsManager.skipForward()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .disabled(!ttsManager.isPlaying)
                    
                    Button(action: {
                        ttsManager.stop()
                        showingTTSPanel = false
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        if ttsManager.isPlaying {
                            let idx = ttsManager.currentParagraphIndex
                            if idx >= 0 && idx < ttsManager.paragraphs.count {
                                ttsResumeCharIndex = ttsManager.paragraphs[idx].range.location
                            } else {
                                ttsResumeCharIndex = 0
                            }
                            ttsManager.stop()
                        } else {
                            ttsResumeCharIndex = nil
                        }
                        showingTTSSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            .padding(.bottom, 20)
            .padding(.horizontal)
        }
    }
}

// MARK: - TTS Settings Sheet View

struct TTSSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var ttsManager = TTSManager.shared
    @State private var availableVoices: [Voice] = []
    @State private var systemVoices: [AVSpeechSynthesisVoice] = []
    
    private var hasNoDictionary: Bool {
        let path = (try? ModelStore())?.rootURL.appendingPathComponent("non-vietnamese-words.plist").path ?? ""
        return !FileManager.default.fileExists(atPath: path)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Công cụ đọc") {
                    Picker("Trình đọc", selection: $ttsManager.tool) {
                        Text("Siri (Hệ thống Apple)").tag("system")
                        Text("NghiTTS (Piper Offline)").tag("nghitts")
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
                    } else {
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
                                
                                NavigationLink(destination: TTSModelManagerView()) {
                                    Text("Tải model và thư viện")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
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
                                HStack {
                                    Text("Quản lý model & thư viện")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
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
                    
                    Picker("Độ dài phân đoạn", selection: $ttsManager.chunkLength) {
                        Text("250 ký tự").tag(250)
                        Text("500 ký tự").tag(500)
                        Text("1000 ký tự (Mặc định)").tag(1000)
                    }
                }
            }
            .navigationTitle("Cài đặt TTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
            .onAppear {
                self.systemVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }
                
                if ttsManager.tool == "system" && ttsManager.selectedVoice.isEmpty {
                    ttsManager.selectedVoice = systemVoices.first?.identifier ?? ""
                }
                
                Task {
                    self.availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false)) ?? NghiTTSClient.fallbackVietnameseVoices
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
