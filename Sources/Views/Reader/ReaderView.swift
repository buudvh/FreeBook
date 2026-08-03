import SwiftUI
import SwiftData
import AVFoundation

public enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper = "Sáng"
    case sepia = "Trầm ấm"
    case dark = "Tối"

    public var id: String { self.rawValue }

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

    var highlightUIColor: UIColor {
        switch self {
        case .paper:
            return UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 0.45)
        case .sepia:
            return UIColor(red: 0.92, green: 0.72, blue: 0.45, alpha: 0.45)
        case .dark:
            return UIColor(white: 1.0, alpha: 0.16)
        }
    }

    var highlightTextUIColor: UIColor? {
        switch self {
        case .paper:
            return UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.0)
        case .sepia:
            return UIColor(red: 0.13, green: 0.07, blue: 0.02, alpha: 1.0)
        case .dark:
            return UIColor.white
        }
    }
}

public enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable {
    case system = "Hệ thống (San Francisco)"
    case georgia = "Georgia (Kindle Classic)"
    case palatino = "Palatino (Văn Học)"
    case charter = "Charter (Tiếng Việt Rõ Nét)"
    case avenir = "Avenir Next (Hiện Đại)"
    case songti = "Tống Thể - 宋体 (Hán Tự Cổ Điển)"
    case kaiti = "Khải Thể - 楷体 (Hán Tự Thư Pháp)"
    case pingfang = "Bình Phương - 苹方 (Hán Tự Hiện Đại)"

    public var id: String { self.rawValue }

    public var fontName: String? {
        switch self {
        case .system: return nil
        case .georgia: return "Georgia"
        case .palatino: return "Palatino-Roman"
        case .charter: return "Charter-Roman"
        case .avenir: return "AvenirNext-Regular"
        case .songti: return "SongtiSC-Regular"
        case .kaiti: return "KaitiSC-Regular"
        case .pingfang: return "PingFangSC-Regular"
        }
    }
}

private struct ReaderLookupRoute: Identifiable, Equatable {
    let id = UUID()
    let urlString: String
}

struct ReaderView: View {
    // static variables: Dùng làm biến toàn cục của class để lưu trạng thái chương/sách đang phát TTS
    public static var activeBookId: String? = nil

    // @Environment: Lấy các biến môi trường của hệ thống
    @Environment(\.modelContext) private var modelContext // Context quản lý dữ liệu SwiftData
    @Environment(\.dismiss) private var dismiss // Hàm dùng để đóng màn hình hiện tại và quay về màn hình trước
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    var initialParagraphIndex: Int? = nil

    @State private var showChapterTitle = true // Ẩn/Hiện tiêu đề chương trên đầu màn hình đọc


    // Các biến trạng thái hỗ trợ bôi đen từ/câu để tra cứu từ điển
    @State private var selectedTextForDefinition = "" // Từ/Câu đang được bôi đen chọn tra từ
    @State private var showingDefinitionSheet = false // Hiện hộp thoại tra nghĩa từ điển
    @State private var customMeaning = "" // Nghĩa tự định nghĩa của người dùng lưu lại
    @AppStorage("pinnedSaveToBookSpecific") private var pinnedSaveToBookSpecific = true
    @AppStorage("pinnedSaveAsNameType") private var pinnedSaveAsNameType = false
    @State private var saveToBookSpecific = true
    @State private var saveAsNameType = false

    // Các cấu hình tra từ nâng cao và hiển thị
    @State private var originalSentence = ""
    @State private var selectedWordOffset = 0
    @State private var selectedWordLength = 0
    @State private var selectedDisplayedOffset = 0
    @State private var searchEngines: [SearchEngine] = []
    @State private var showingSearchEnginesConfigSheet = false
    @State private var translationMode: String = "VP" // Dịch dạng: "VP" (Vietphrase) hoặc "HV" (Hán Việt)
    @State private var translationTokens: [TranslationWordToken] = []
    @State private var dictionaryMatches: [DictionaryMatchInfo] = []
    @State private var showingManageDefinitionsSheet = false
    @State private var showingFloatingMenu = false
    @State private var selectionMinY: CGFloat? = nil
    @State private var selectionMaxY: CGFloat? = nil
    @State private var showingAddNghiTTSPhonemeSheet = false
    @State private var selectedDisplayedText = ""
    @State private var clearSelectionTrigger: UUID? = nil
    @State private var wordSynthesizer: AVSpeechSynthesizer? = nil

    // Cấu hình giao diện đọc (lưu trữ lâu dài qua UserDefaults nhờ @AppStorage)
    @AppStorage("readerFontSize") private var fontSize: Double = 20.0 // Cỡ chữ của văn bản đọc
    @AppStorage("readerLineSpacing") private var lineSpacing: Double = 10.0 // Khoảng cách giữa các dòng
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false // Trạng thái bật/tắt tự động dịch thuật
    @AppStorage("isTranslationPronounsEnabled") private var isTranslationPronounsEnabled = false // Bật dịch đại từ
    @AppStorage("isTranslationLuatNhanEnabled") private var isTranslationLuatNhanEnabled = false // Bật dịch luật nhân
    @AppStorage("readerSelectedTheme") private var selectedTheme: ReaderTheme = .dark // Theme giao diện đọc (Sáng, Trầm ấm, Tối)
    @AppStorage("readerFontFamily") private var fontFamily: ReaderFontFamily = .georgia // Phông chữ đọc sách
    @AppStorage("hasOpenedReader") private var hasOpenedReader = false
    @State private var showingSettings = false // Hiện bảng cài đặt font chữ, màu nền
    @State private var showingTOCRules = false
    @State private var showingJunkDeleteSheet = false
    @State private var junkPatternInput = ""
    @State private var showingJunkFilterManagerSheet = false

    // Trạng thái bypass Cloudflare và import sách
    @State private var showingBypassBrowser = false
    @State private var lookupRoute: ReaderLookupRoute?
    @State private var importedBookId = ""
    @State private var importedExtensionPackageId = ""
    @State private var importedDetailUrl = ""
    @State private var importedSourceName = ""
    @State private var importedHost = ""
    @State private var navigateToBookDetail = false

    // TTS (Giọng đọc): Sử dụng @StateObject để giữ vòng đời của đối tượng TTSManager.shared không bị hủy khi đổi chương
    @StateObject private var ttsManager = TTSManager.shared
    @State private var triggerGetVisibleIndex: UUID? = nil
    @State private var editingParagraphIndex: Int? = nil
    @State private var scrollTarget: ScrollTarget? = nil
    @State private var readerViewportHeight: CGFloat = 360
    @State private var isRestoringReaderPosition = true
    @State private var isAutoScrollDisabled = false
    @State private var viewModel: ReaderViewModel? = nil
    @State private var updateProgressWorkItem: DispatchWorkItem? = nil
    @State private var updateTTSPositionWorkItem: DispatchWorkItem? = nil
    @State private var prepareTTSTask: DispatchWorkItem? = nil

    @State private var localChaptersCount: Int = 0
    @State private var currentChapterTitle: String = ""
    @State private var currentChapterUrl: String = ""
    @State private var didResolveLocalChapterCount = false

    @State private var paragraphTracker = ParagraphTracker()
    @State private var translationRefreshToken = UUID()

    @State private var showingChapterList = false
    @State private var showingBookDictionary = false
    @State private var currentOnlineChapters: [ChapterResult] = []
    @State private var chapterListStore: ReaderChapterListStore? = nil
    // SwiftData's @Query can deliver after the Reader has already appeared.
    // Keep a one-time local snapshot so the first render has Book/TOC metadata
    // even when this screen was opened from history or the shelf.
    @State private var localBookSnapshot: Book? = nil

    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId }) ?? localBookSnapshot
    }

    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }

    private var isLocalTXTBook: Bool {
        return extensionPackageId.lowercased() == "local"
            || (bookDetailUrl ?? "").lowercased().hasPrefix("local://")
            || bookId.lowercased().hasPrefix("local://")
            || (bookSourceName ?? "").lowercased() == "local"
            || localBook?.isLocalBook == true
    }

    @State private var currentChapterHost: String? = nil
    @State private var metadataTask: Task<Void, Never>? = nil
    @State private var metadataGeneration: Int = 0

    private var isCurrentlyPlayingThisChapter: Bool {
        ttsManager.isPlaying &&
        ttsManager.playingBookId == bookId &&
        ttsManager.playingChapterIndex == chapterIndex
    }

    private var isTTSPlayingThisBook: Bool {
        ttsManager.isPlaying && ttsManager.playingBookId == bookId
    }

    private var ttsExtensionInfo: TTSExtensionInfo? {
        guard let ext = ext else { return nil }
        return TTSExtensionInfo(
            packageId: ext.packageId,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
    }

    // Tổng số chương hiện có
    private var totalChaptersCount: Int {
        if let vm = viewModel {
            return vm.totalChaptersCount
        }
        return max(localChaptersCount, currentOnlineChapters.count)
    }

    // Lấy thông tin chương hiện tại (Title, URL)
    private var currentChapterInfo: (title: String, url: String)? {
        guard chapterIndex >= 0 && chapterIndex < totalChaptersCount else { return nil }
        return (currentChapterTitle, currentChapterUrl)
    }

    private func getChapterTitle(at index: Int) -> String {
        guard index >= 0 && index < totalChaptersCount else { return "Chương \(index + 1)" }

        let title: String
        if index == (viewModel?.displayedChapterIndex ?? chapterIndex) {
            title = currentChapterTitle
        } else if localBook != nil {
            if let cached = viewModel?.cache.cache[index], !cached.title.isEmpty {
                title = cached.title
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

    private var displayedBookTitle: String {
        let rawTitle = bookTitle ?? localBook?.title ?? localBookSnapshot?.title ?? ""
        guard !rawTitle.isEmpty else { return "" }
        return isTranslationEnabled && TranslateUtils.containsChinese(rawTitle)
            ? TranslateUtils.translateChapterTitle(rawTitle, bookId: bookId)
            : rawTitle
    }


    var body: some View {
        readerLifecycleView
    }

    private var readerPresentationView: some View {
        GeometryReader { geometry in
            ZStack {
                selectedTheme.backgroundColor
                    .ignoresSafeArea()
                readerMainContent(geometry: geometry)

                // Panel dịch dạng overlay ở đáy (Full-width Bottom Sheet)
                if showingDefinitionSheet {
                    VStack(spacing: 0) {
                        // Vùng trống phía trên bắt tap để đóng panel dịch
                        Color.clear
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    withAnimation {
                                        showingDefinitionSheet = false
                                    }
                                }
                            )

                        ReaderDefinitionOverlayView(
                            isPresented: $showingDefinitionSheet,
                            selectedTheme: selectedTheme,
                            originalSentence: originalSentence,
                            selectedWordOffset: $selectedWordOffset,
                            selectedWordLength: $selectedWordLength,
                            translationTokens: translationTokens,
                            customMeaning: $customMeaning,
                            saveAsNameType: $saveAsNameType,
                            saveToBookSpecific: $saveToBookSpecific,
                            pinnedSaveAsNameType: pinnedSaveAsNameType,
                            pinnedSaveToBookSpecific: pinnedSaveToBookSpecific,
                            onPinNameType: { isName in
                                pinnedSaveAsNameType = isName
                                saveAsNameType = isName
                                ToastManager.shared.show(message: "Đã ghim mặc định Loại: \(isName ? "Names" : "VP")", type: .success)
                            },
                            onPinScope: { isBook in
                                pinnedSaveToBookSpecific = isBook
                                saveToBookSpecific = isBook
                                ToastManager.shared.show(message: "Đã ghim mặc định Phạm vi: \(isBook ? "Riêng" : "Chung")", type: .success)
                            },
                            suggestionChips: suggestionChips,
                            searchEngines: searchEngines,
                            selectedTextForDefinition: selectedTextForDefinition,
                            bookId: bookId,
                            dictionaryMatches: $dictionaryMatches,
                            translationMode: $translationMode,
                            showingManageDefinitionsSheet: $showingManageDefinitionsSheet,
                            onExpandSelectionLeft: expandSelectionLeft,
                            onShrinkSelectionLeft: shrinkSelectionLeft,
                            onShrinkSelectionRight: shrinkSelectionRight,
                            onExpandSelectionRight: expandSelectionRight,
                            onUpdateEditorFromSelection: updateEditorFromSelection,
                            onFormatMeaning: formatMeaning,
                            onSaveDefinition: saveDefinition,
                            onPerformQuickLookup: performQuickLookup,
                            onOpenSearchEngineConfig: {
                                showingSearchEnginesConfigSheet = true
                            },
                            onGetDictionaryMatches: getDictionaryMatches,
                            onGetHanViet: { getHanViet(for: $0) },
                            onApplyTranslation: applyTranslation
                        )
                        .padding([.horizontal, .bottom])
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                                .fill(selectedTheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -4)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    if value.translation.height > 50 {
                                        withAnimation {
                                            showingDefinitionSheet = false
                                        }
                                    }
                                }
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .zIndex(5)
                }

                ReaderFloatingMenuOverlayView(
                    isShowing: $showingFloatingMenu,
                    clearSelectionTrigger: $clearSelectionTrigger,
                    selectionMinY: selectionMinY ?? 200,
                    selectionMaxY: selectionMaxY ?? 240,
                    geometryOriginY: geometry.frame(in: .global).minY,
                    screenWidth: geometry.size.width,
                    onTranslate: {
                        updateEditorFromSelection()
                        showingDefinitionSheet = true
                    },
                    onSpeak: {
                        if let pIndex = editingParagraphIndex {
                            startTTS(at: chapterIndex, paragraphIndex: pIndex, startTextOffset: selectedDisplayedOffset)
                        }
                    },
                    onPhoneme: {
                        updateEditorFromSelection()
                        showingAddNghiTTSPhonemeSheet = true
                    },
                    onCopy: {
                        updateEditorFromSelection()
                        UIPasteboard.general.string = selectedDisplayedText
                        ToastManager.shared.show(message: "Đã sao chép: \"\(selectedDisplayedText)\"")
                    },
                    onReadSelected: {
                        readSelectedText()
                    },
                    onDeleteJunk: {
                        updateEditorFromSelection()
                        junkPatternInput = selectedTextForDefinition.isEmpty ? selectedDisplayedText : selectedTextForDefinition
                        showingJunkDeleteSheet = true
                    }
                )

                if showingJunkDeleteSheet {
                    VStack {
                        Spacer()
                        ReaderJunkDeleteOverlayView(
                            isPresented: $showingJunkDeleteSheet,
                            selectedTheme: selectedTheme,
                            originalSentence: originalSentence,
                            selectedWordOffset: $selectedWordOffset,
                            selectedWordLength: $selectedWordLength,
                            translationTokens: translationTokens,
                            junkPatternInput: $junkPatternInput,
                            onExpandSelectionLeft: expandSelectionLeft,
                            onShrinkSelectionLeft: shrinkSelectionLeft,
                            onShrinkSelectionRight: shrinkSelectionRight,
                            onExpandSelectionRight: expandSelectionRight,
                            onUpdateEditorFromSelection: updateEditorFromSelection,
                            onConfirmDelete: { pattern in
                                confirmDeleteJunk(pattern)
                            },
                            onCancel: {
                                showingJunkDeleteSheet = false
                            }
                        )
                        .padding([.horizontal, .bottom])
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                                .fill(selectedTheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: -4)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 0 : 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(6)
                }

                readerChapterListOverlay(in: geometry)
            }
        }
        .toolbar(.hidden, for: .navigationBar) // Ẩn navigation bar gốc
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                fontFamily: $fontFamily,
                selectedTheme: $selectedTheme,
                isTranslationEnabled: $isTranslationEnabled,
                isPronounsEnabled: $isTranslationPronounsEnabled,
                isLuatNhanEnabled: $isTranslationLuatNhanEnabled,
                onOpenJunkFilter: {
                    showingSettings = false
                    showingJunkFilterManagerSheet = true
                }
            )
            .presentationDetents([.height(450)])
        }
        .sheet(isPresented: $showingJunkFilterManagerSheet) {
            NavigationStack {
                JunkFilterManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Xong") {
                                showingJunkFilterManagerSheet = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingTOCRules) {
            NavigationStack {
                TOCRulesConfigView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Xong") {
                                showingTOCRules = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingBookDictionary) {
            NavigationStack {
                BookDictionaryView(bookId: bookId, bookName: bookTitle ?? "")
                    .navigationBarItems(trailing: Button("Đóng") {
                        showingBookDictionary = false
                    })
            }
        }
        .sheet(isPresented: $showingSearchEnginesConfigSheet, onDismiss: {
            searchEngines = SearchEngine.loadEngines()
        }) {
            NavigationStack {
                SearchEnginesConfigView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Xong") {
                                showingSearchEnginesConfigSheet = false
                            }
                        }
                    }
            }
        }
        .onChange(of: showingDefinitionSheet) { _, newValue in
            if newValue {
                searchEngines = SearchEngine.loadEngines()
            }
        }
        .onChange(of: isTranslationEnabled) { _, newValue in
            applyTranslation()
            chapterListStore?.updateTranslation(isTranslationEnabled: newValue)
        }
        .onChange(of: isTranslationPronounsEnabled) { _, _ in
            TranslateUtils.clearCache()
            applyTranslation()
        }
        .onChange(of: isTranslationLuatNhanEnabled) { _, _ in
            TranslateUtils.clearCache()
            applyTranslation()
        }
        .sheet(isPresented: $showingAddNghiTTSPhonemeSheet) {
            AddWordSheet(initialKey: selectedDisplayedText) { key, val in
                _ = Task {
                    try? await TextPreprocessor.shared.updateWord(key: key, value: val)
                    await TextPreprocessor.shared.loadResources()
                    ToastManager.shared.show(message: "Đã thêm phiên âm: \(key)")
                }
            }
        }
        .fullScreenCover(isPresented: $showingBypassBrowser) {
            let browserUrl: String = {
                if let chapUrl = currentChapterInfo?.url, !chapUrl.isEmpty, chapUrl.hasPrefix("http") {
                    return chapUrl
                }
                if let sourceUrl = localBook?.sourceUrl, !sourceUrl.isEmpty, sourceUrl.hasPrefix("http") {
                    return sourceUrl
                }
                if let detailUrl = bookDetailUrl, !detailUrl.isEmpty, detailUrl.hasPrefix("http") {
                    return detailUrl
                }
                return "home"
            }()
            BypassWebView(
                urlString: browserUrl,
                host: currentChapterHost,
                onImport: { detailUrl, packageId, sourceName in
                    importedBookId = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)
                    importedExtensionPackageId = packageId
                    importedDetailUrl = detailUrl
                    importedSourceName = sourceName

                    if let url = URL(string: detailUrl), let scheme = url.scheme, let host = url.host {
                        importedHost = "\(scheme)://\(host)"
                    } else {
                        importedHost = ""
                    }

                    showingBypassBrowser = false
                    ToastManager.shared.show(message: "Đã hoàn tất tải các chương!", type: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigateToBookDetail = true
                    }
                }
            )
        }
        .fullScreenCover(item: $lookupRoute) { route in
            BypassWebView(
                urlString: route.urlString
            )
        }
        .background(
            Group {
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
            }
        )
    }

    @State private var selectionAudioPlayer: AVAudioPlayer? = nil

    private func readSelectedText() {
        let text = selectedDisplayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        clearSelectionTrigger = UUID()
        showingFloatingMenu = false

        if wordSynthesizer?.isSpeaking == true {
            wordSynthesizer?.stopSpeaking(at: .immediate)
        }
        if selectionAudioPlayer?.isPlaying == true {
            selectionAudioPlayer?.stop()
            selectionAudioPlayer = nil
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        let googleService = GoogleTTSService.shared
        if googleService.hasApiKey {
            let voice = UserDefaults.standard.string(forKey: "googleVoice") ?? "via"
            Task {
                do {
                    let mp3Data = try await googleService.synthesize(text: text, voice: voice, speed: 1.0, pitch: 1.0)
                    await MainActor.run {
                        do {
                            let player = try AVAudioPlayer(data: mp3Data)
                            player.play()
                            self.selectionAudioPlayer = player
                        } catch {
                            self.fallbackSiriReadSelectedText(text)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.fallbackSiriReadSelectedText(text)
                    }
                }
            }
        } else {
            fallbackSiriReadSelectedText(text)
        }
    }

    private func fallbackSiriReadSelectedText(_ text: String) {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(language: "vi-VN") {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
        self.wordSynthesizer = synthesizer
    }

    private func confirmDeleteJunk(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        clearSelectionTrigger = UUID()
        showingFloatingMenu = false

        JunkFilterManager.shared.addRule(pattern: trimmed)
        TranslateUtils.clearCache()

        let currentChapterIndex = chapterIndex
        let currentBookId = bookId

        Task {
            await ChapterContentRepository.shared.remove(bookId: currentBookId, chapterIndex: currentChapterIndex)
            if let vm = viewModel {
                await MainActor.run {
                    vm.reloadDisplayedChapter()
                }
            }
        }

        ToastManager.shared.show(message: "Đã thêm vào lọc rác: \"\(trimmed)\"", type: .success)
    }

    private var readerDataObservationView: some View {
        readerPresentationView

        .onChange(of: ttsManager.isPlaying) { _, _ in
            let ttsOwnsBook = ttsManager.isPlaying && ttsManager.playingBookId == bookId
            viewModel?.setSpeculativePrefetchEnabled(!ttsOwnsBook)
        }
        .onChange(of: viewModel?.displayedChapterIndex) { _, _ in
            updateCurrentChapterMetadata()
        }
        .onChange(of: currentOnlineChapters) { _, _ in
            updateCurrentChapterMetadata()
        }
        .onChange(of: currentOnlineChapters.count) { _, newCount in
            if let vm = viewModel, newCount > 0 {
                vm.updateChapterSnapshot(
                    totalCount: newCount,
                    onlineChapters: currentOnlineChapters
                )
                if let store = chapterListStore {
                    store.updateChapters(totalCount: newCount, onlineChapters: currentOnlineChapters)
                }
            }
        }
        .onChange(of: onlineChapters.count) { _, newCount in
            guard newCount > 0, newCount != currentOnlineChapters.count else { return }
            currentOnlineChapters = onlineChapters
            if let vm = viewModel {
                vm.updateChapterSnapshot(
                    totalCount: newCount,
                    onlineChapters: onlineChapters
                )
                if let store = chapterListStore {
                    store.updateChapters(totalCount: newCount, onlineChapters: onlineChapters)
                }
            }
        }
    }

    private var readerLifecycleView: some View {
        readerDataObservationView
        .task(id: readerBootstrapKey) {
            await initializeReaderIfNeeded()
        }
        .onDisappear {
            metadataTask?.cancel()
            if ReaderView.activeBookId == bookId {
                ReaderView.activeBookId = nil
            }
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.removeAll()
            if let vm = viewModel {
                let ttsOwnsProgress = ttsManager.isPlaying && ttsManager.playingBookId == bookId
                Task {
                    await vm.shutdown(saveProgress: !ttsOwnsProgress)
                    await ChapterContentRepository.shared.flush(bookId: bookId)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && !(ttsManager.isPlaying && ttsManager.playingBookId == bookId) {
                viewModel?.saveProgressImmediately()
            }
        }
        .onChange(of: chapterIndex) { _, _ in
            updateProgressWorkItem?.cancel()
            updateTTSPositionWorkItem?.cancel()
            prepareTTSTask?.cancel()
            paragraphTracker.removeAll()

        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ttsDidAdvanceToNextChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  let nextIdx = userInfo["chapterIndex"] as? Int else { return }

            if bid == bookId && nextIdx != chapterIndex {
                if chapterIndex == nextIdx - 1 {
                    requestChapter(
                        at: nextIdx,
                        paragraphIndex: 0,
                        source: .ttsSync,
                        persistProgress: false
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .translationDictionariesDidUpdate)) { _ in
            TranslateUtils.clearCache()
            viewModel?.updateCachedTranslatedContent(bookId: bookId)
            TTSManager.shared.clearPrefetchCache()
            translationRefreshToken = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateReaderToPlayingChapter"))) { notification in
            guard let userInfo = notification.userInfo,
                  let bid = userInfo["bookId"] as? String,
                  bid == bookId,
                  let targetIndex = userInfo["chapterIndex"] as? Int else { return }

            let paragraphIndex = (userInfo["paragraphIndex"] as? Int).flatMap { $0 >= 0 ? $0 : nil } ?? 0
            if targetIndex != chapterIndex {
                requestChapter(
                    at: targetIndex,
                    paragraphIndex: paragraphIndex,
                    source: .ttsSync,
                    persistProgress: false
                )
            } else if paragraphIndex >= 0 {
                scrollTarget = ScrollTarget(chapterIndex: targetIndex, paragraphIndex: paragraphIndex)
            }
        }
        .onChange(of: ttsManager.currentParentParagraphIndex) { _, newValue in
            guard ttsManager.isPlaying &&
                  ttsManager.playingBookId == bookId &&
                  ttsManager.playingChapterIndex >= 0 &&
                  ttsManager.playingChapterIndex < totalChaptersCount &&
                  newValue >= 0 else { return }

            let playingChapterIndex = ttsManager.playingChapterIndex
            guard !isAutoScrollDisabled else { return }

            guard chapterIndex == playingChapterIndex else { return }

            scrollTarget = ScrollTarget(chapterIndex: playingChapterIndex, paragraphIndex: newValue)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func readerMainContent(geometry: GeometryProxy) -> some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer().frame(height: 100)

                ZStack(alignment: .bottomTrailing) {
                    readerContentView
                    readerTTSControl(geometry: geometry)
                }

                Spacer().frame(height: 52)
            }

            ReaderHeaderFooterOverlayView(
                selectedTheme: selectedTheme,
                isTranslationEnabled: $isTranslationEnabled,
                showChapterTitle: $showChapterTitle,
                showingBookDictionary: $showingBookDictionary,
                showingBypassBrowser: $showingBypassBrowser,
                showingSettings: $showingSettings,
                showingChapterList: $showingChapterList,
                showingTOCRules: $showingTOCRules,
                showingJunkFilter: $showingJunkFilterManagerSheet,
                readerBookDisplayTitle: readerBookDisplayTitle,
                readerChapterDisplayTitle: readerChapterDisplayTitle,
                hasLocalBook: localBook != nil,
                isLocalTXTBook: isLocalTXTBook,
                chapterIndex: chapterIndex,
                pendingNavigationIndex: viewModel?.pendingNavigationIndex,
                navigationFailureMessage: viewModel?.navigationFailure?.sourceMessage,
                totalChaptersCount: totalChaptersCount,
                readerPresentedChapterIndex: readerPresentedChapterIndex,
                readerProgressPercent: readerProgressPercent,
                onDismiss: { dismiss() },
                onReloadChapter: reloadCurrentChapterFromMenu,
                onToggleChapterTitle: toggleChapterTitleVisibility,
                onOpenChapterList: {
                    _ = getOrInitChapterListStore()
                    showingChapterList = true
                },
                onPrevChapter: prevChapter,
                onNextChapter: nextChapter
            )
        }
    }

    private var readerBootstrapKey: String {
        "\(bookId)|\(onlineChapters.count)"
    }

    private func ensureViewModel(totalCount: Int) {
        if let vm = viewModel {
            if totalCount > 0 {
                vm.updateChapterSnapshot(
                    totalCount: totalCount,
                    onlineChapters: currentOnlineChapters
                )
            }
        } else {
            let savedPIdx = initialParagraphIndex ?? getSavedParagraphIndex(for: chapterIndex)
            let newViewModel = ReaderViewModel(
                bookId: bookId,
                extensionPackageId: extensionPackageId,
                initialChapterIndex: chapterIndex,
                initialParagraphIndex: savedPIdx,
                totalChaptersCount: totalCount,
                modelContext: modelContext,
                onlineChapters: currentOnlineChapters,
                isTranslationEnabled: isTranslationEnabled,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                bookCoverUrl: bookCoverUrl,
                bookDesc: bookDesc,
                bookDetailUrl: bookDetailUrl,
                bookSourceName: bookSourceName
            )
            newViewModel.onChapterCached = { index in
                chapterListStore?.markCached(index: index)
            }
            newViewModel.setSpeculativePrefetchEnabled(
                !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
            )
            viewModel = newViewModel

            if !hasOpenedReader {
                hasOpenedReader = true
            }
        }
        if totalCount > 0 {
            chapterListStore?.updateChapters(totalCount: totalCount, onlineChapters: currentOnlineChapters)
        }
        updateCurrentChapterMetadata()
    }

    @MainActor
    private func initializeReaderIfNeeded() async {
        let key = "showChapterTitle_\(bookId)"
        if UserDefaults.standard.object(forKey: key) != nil {
            showChapterTitle = UserDefaults.standard.bool(forKey: key)
        } else {
            showChapterTitle = true
        }

        isAutoScrollDisabled = UserDefaults.standard.bool(forKey: "disableAutoScroll_\(bookId)")
        searchEngines = SearchEngine.loadEngines()
        ReaderView.activeBookId = bookId

        if localBookSnapshot == nil {
            var descriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { book in
                    book.bookId == bookId
                }
            )
            descriptor.fetchLimit = 1
            localBookSnapshot = (try? modelContext.fetch(descriptor))?.first(where: { $0.bookId == bookId })
        }

        if currentOnlineChapters.isEmpty, !onlineChapters.isEmpty {
            currentOnlineChapters = onlineChapters
        }

        let bookHash = String(Chapter.hashUrl(bookId).prefix(8))

        if localBookSnapshot != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            do {
                let count = try await ChapterStore.shared.fetchCountAndChecksum(bookId: bookId).count
                guard !Task.isCancelled, ReaderView.activeBookId == bookId else { return }
                if count > 0 {
                    self.localChaptersCount = count
                    self.didResolveLocalChapterCount = true
                    AppLogger.shared.log("ℹ️ [ReaderBootstrap] bookIdHash=\(bookHash) totalChapters=\(count) source=ChapterStore status=success")
                    ensureViewModel(totalCount: count)
                } else {
                    AppLogger.shared.log("❌ [ReaderBootstrap] bookIdHash=\(bookHash) status=count_zero")
                    ensureViewModel(totalCount: 0)
                    viewModel?.failBootstrap(message: "Mục lục sách cục bộ rỗng")
                }
            } catch {
                guard !Task.isCancelled, ReaderView.activeBookId == bookId else { return }
                AppLogger.shared.log("❌ [ReaderBootstrap] bookIdHash=\(bookHash) status=fetch_failed_error")
                ensureViewModel(totalCount: 0)
                viewModel?.failBootstrap(message: "Lỗi đọc mục lục sách cục bộ")
            }
        } else if localBookSnapshot != nil && ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            let localBId = bookId
            let descriptor = FetchDescriptor<Chapter>(
                predicate: #Predicate<Chapter> { $0.bookId == localBId }
            )
            let count = (try? modelContext.fetchCount(descriptor)) ?? 0
            self.localChaptersCount = count
            self.didResolveLocalChapterCount = true
            ensureViewModel(totalCount: count)
        } else {
            ensureViewModel(totalCount: currentOnlineChapters.count)
        }
    }

    private func updateCurrentChapterMetadata() {
        guard viewModel != nil || localBookSnapshot == nil else { return }
        metadataTask?.cancel()
        metadataGeneration += 1
        let currentGen = metadataGeneration
        let targetIndex = viewModel?.displayedChapterIndex ?? chapterIndex

        self.currentChapterTitle = "Đang tải..."
        self.currentChapterUrl = ""
        self.currentChapterHost = nil

        metadataTask = Task {
            struct ResolvedMeta {
                let title: String
                let url: String
                let host: String?
            }
            var resolved: ResolvedMeta? = nil

            if localBookSnapshot != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                if let snapshot = await viewModel?.fetchChapterSnapshot(at: targetIndex) {
                    let trimmedUrl = snapshot.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedUrl.isEmpty {
                        resolved = ResolvedMeta(
                            title: snapshot.title,
                            url: trimmedUrl,
                            host: snapshot.host ?? localBook?.host ?? ext?.sourceUrl
                        )
                    }
                }
            } else if localBookSnapshot != nil && ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                let localBookId = bookId
                var descriptor = FetchDescriptor<Chapter>(
                    predicate: #Predicate<Chapter> { $0.bookId == localBookId && $0.index == targetIndex }
                )
                descriptor.fetchLimit = 1
                if let chap = (try? modelContext.fetch(descriptor))?.first {
                    let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedUrl.isEmpty {
                        resolved = ResolvedMeta(
                            title: chap.title,
                            url: trimmedUrl,
                            host: chap.host
                        )
                    }
                }
            } else if targetIndex >= 0 && targetIndex < currentOnlineChapters.count {
                let chap = currentOnlineChapters[targetIndex]
                let trimmedUrl = chap.url.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedUrl.isEmpty {
                    resolved = ResolvedMeta(
                        title: chap.name,
                        url: trimmedUrl,
                        host: chap.host
                    )
                }
            }

            guard !Task.isCancelled,
                  currentGen == self.metadataGeneration,
                  targetIndex == (self.viewModel?.displayedChapterIndex ?? self.chapterIndex),
                  ReaderView.activeBookId == self.bookId else { return }

            if let res = resolved {
                self.currentChapterTitle = res.title
                self.currentChapterUrl = res.url
                self.currentChapterHost = res.host
            } else if localBookSnapshot != nil && !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
                let bookHash = String(Chapter.hashUrl(self.bookId).prefix(8))
                AppLogger.shared.log("❌ [ReaderMetadata] bookIdHash=\(bookHash) index=\(targetIndex) status=missing_or_empty_url")
            }
        }
    }

    private func getOrInitChapterListStore() -> ReaderChapterListStore? {
        if let store = chapterListStore {
            store.updateTranslation(isTranslationEnabled: isTranslationEnabled)
            return store
        }
        guard let vm = viewModel else { return nil }
        let store = ReaderChapterListStore(
            bookId: bookId,
            modelContext: localBook != nil ? modelContext : nil,
            onlineChapters: currentOnlineChapters.isEmpty ? onlineChapters : currentOnlineChapters,
            totalCount: vm.totalChaptersCount,
            isAscending: true,
            isTranslationEnabled: isTranslationEnabled
        )
        self.chapterListStore = store
        return store
    }

    @ViewBuilder
    private func readerChapterListOverlay(in geometry: GeometryProxy) -> some View {
        if let chapterListStore {
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeChapterList()
                    }
                    .opacity(showingChapterList ? 1 : 0)
                    .allowsHitTesting(showingChapterList)

                ReaderChapterListView(
                    bookId: bookId,
                    bookTitle: bookTitle,
                    bookAuthor: bookAuthor,
                    bookCoverUrl: bookCoverUrl,
                    bookDetailUrl: bookDetailUrl,
                    localBook: localBook,
                    ext: ext,
                    currentChapterIndex: viewModel?.displayedChapterIndex ?? chapterIndex,
                    isPresented: showingChapterList,
                    isTranslationEnabled: isTranslationEnabled,
                    theme: selectedTheme,
                    store: chapterListStore,
                    onlineChapters: $currentOnlineChapters,
                    isLocalTXTBook: isLocalTXTBook,
                    onSelectChapter: { selectedIdx in
                        selectChapter(at: selectedIdx)
                    },
                    onClose: {
                        closeChapterList()
                    },
                    onLocalTOCRefreshed: { newTotal in
                        Task { @MainActor in
                            self.localChaptersCount = newTotal
                            self.viewModel?.updateChapterSnapshot(totalCount: newTotal, onlineChapters: [])
                            if ttsManager.playingBookId == bookId {
                                ttsManager.refreshChaptersQueueInBackground(bookId: bookId, onlineChapters: nil)
                            }
                        }
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height - 60)
                .offset(
                    y: reduceMotion
                        ? 60
                        : (showingChapterList ? 60 : geometry.size.height + geometry.safeAreaInsets.bottom)
                )
                .opacity(showingChapterList ? 1 : 0)
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: showingChapterList)
                .allowsHitTesting(showingChapterList)
                .accessibilityHidden(!showingChapterList)
            }
            .zIndex(10)
        }
    }

    private func closeChapterList() {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25)) {
            showingChapterList = false
        }
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
        viewModel?.toggleTranslation(enabled: isTranslationEnabled)
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

    private var suggestionChips: [SuggestionChip] {
        var chips: [SuggestionChip] = []
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }

        let manager = TranslationManager.shared
        let bookDicts = manager.getBookDictionaries(for: bookId)

        func addTranslation(_ translation: String, category: SuggestionChipCategory) {
            let clean = translation.replacingOccurrences(of: "¦", with: "/")
            let parts = clean.components(separatedBy: "/")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isDuplicate = chips.contains { existing in
                        existing.text == trimmed
                    }
                    if !isDuplicate {
                        chips.append(SuggestionChip(text: trimmed, category: category))
                    }
                }
            }
        }

        // 1. Book Names
        if let bookNames = bookDicts.names,
           let match = bookNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
        }

        // 1.1 Custom Names (custom.dat)
        var hasCustomName = false
        if let customNames = manager.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
            hasCustomName = true
        }

        // 2. Global Names (Names.dat)
        if !hasCustomName,
           !manager.deletedNames.contains(word),
           let names = manager.namesDict,
           let match = names.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .name)
        }

        // 3. Book VietPhrase
        if let bookVP = bookDicts.vietPhrase,
           let match = bookVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .vietPhrase)
        }

        // 3.1 Custom VietPhrase (custom.dat)
        var hasCustomVP = false
        if let customVP = manager.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            addTranslation(match.value, category: .vietPhrase)
            hasCustomVP = true
        }

        // 4. Global VietPhrase (VietPhrase.dat)
        if !hasCustomVP,
           !manager.deletedVietPhrase.contains(word),
           let vp = manager.vietPhraseDict,
           let match = vp.findLongestMatch(text: word, startIndex: 0),
           match.length == word.count {
            if match.value.count < 100 {
                addTranslation(match.value, category: .vietPhrase)
            }
        }

        // 5. Phiên âm Hán Việt
        let hv = getHanViet(for: word).lowercased()
        if !hv.isEmpty {
            let isDuplicate = chips.contains { existing in
                existing.text == hv
            }
            if !isDuplicate {
                chips.append(SuggestionChip(text: hv, category: .hanViet))
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
        self.saveAsNameType = self.pinnedSaveAsNameType
        self.saveToBookSpecific = self.pinnedSaveToBookSpecific
        let ns = originalSentence as NSString
        guard selectedWordOffset >= 0 && selectedWordOffset + selectedWordLength <= ns.length else { return }
        let word = ns.substring(with: NSRange(location: selectedWordOffset, length: selectedWordLength))
        self.selectedTextForDefinition = word
        self.junkPatternInput = word

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
        guard let encoded = rawUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }

        // Present one immutable URL snapshot. A fresh identity also guarantees
        // the browser cannot reuse the previous lookup request.
        self.lookupRoute = ReaderLookupRoute(urlString: url.absoluteString)
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
    private func chapterContentView(for chapter: CachedChapter) -> some View {
        let isTrans = isTranslationEnabled
        let size = fontSize
        let spacing = lineSpacing
        let theme = selectedTheme

        ForEach(chapter.paragraphItems) { item in
            let relativeHighlightRange: NSRange? = {
                guard ttsManager.isPlaying,
                      ttsManager.playingBookId == bookId,
                      ttsManager.playingChapterIndex == chapter.index,
                      item.id == ttsManager.currentParentParagraphIndex,
                      let chunkRange = ttsManager.highlightRange else { return nil }

                AppLogger.shared.log("🔊 [ReaderView] Applied relativeHighlightRange for ItemID=\(item.id): chunkRange=\(chunkRange)")
                return chunkRange
            }()

            ParagraphCardView(
                item: item,
                isTranslationEnabled: isTrans,
                bookId: bookId,
                translationRefreshToken: translationRefreshToken,
                fontSize: size,
                lineSpacing: spacing,
                fontFamily: fontFamily,
                theme: theme,
                highlightRange: relativeHighlightRange,
                triggerGetVisibleIndex: $triggerGetVisibleIndex,
                clearSelectionTrigger: $clearSelectionTrigger,
                onGetVisibleIndex: { visibleOffset in
                    guard !ttsManager.isPlaying else { return }
                    startTTS(at: chapter.index, paragraphIndex: item.id)
                },
                onSelectionChange: { paragraphID, selectionRange, minY, maxY in
                    self.onSelectionChangeInParagraph(
                        selectionRange: selectionRange,
                        minY: minY,
                        maxY: maxY,
                        paragraphID: paragraphID,
                        chapterIndex: chapter.index,
                        paragraphItems: chapter.paragraphItems
                    )
                },
                onSpeakFromHere: { _ in
                    startTTS(at: chapter.index, paragraphIndex: item.id)
                }
            )
            .equatable()
            .id("paragraph-\(chapter.index)-\(item.id)")
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let frame = geo.frame(in: .global)
                            paragraphTracker.updateFrame(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id, minY: frame.minY, maxY: frame.maxY)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            paragraphTracker.updateFrame(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id, minY: newFrame.minY, maxY: newFrame.maxY)
                        }
                }
            )
            .onAppear {
                paragraphTracker.insert(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id)
                updateScrollReadingProgress()
            }
            .onDisappear {
                paragraphTracker.remove(bookId: bookId, chapterIndex: chapter.index, paragraphIndex: item.id)
                updateScrollReadingProgress()
            }
        }
    }

    private func onSelectionChangeInParagraph(
        selectionRange: NSRange,
        minY: CGFloat?,
        maxY: CGFloat?,
        paragraphID: Int,
        chapterIndex: Int,
        paragraphItems: [ParagraphItem]
    ) {
        if selectionRange.length == 0 || selectionRange.location == NSNotFound {
            self.showingFloatingMenu = false
            self.selectionMinY = nil
            self.selectionMaxY = nil
            self.selectedDisplayedText = ""
            return
        }

        guard let item = paragraphItems.first(where: { $0.id == paragraphID }) else { return }

        let displayedText = isTranslationEnabled ? item.translated : item.original
        let nsDisplayed = displayedText as NSString
        if selectionRange.location != NSNotFound && NSMaxRange(selectionRange) <= nsDisplayed.length {
            self.selectedDisplayedText = nsDisplayed.substring(with: selectionRange)
        } else {
            self.selectedDisplayedText = ""
        }

        guard let originalRange = ReaderSelectionMapper.mapSelection(
                selectionRange,
                in: item,
                isTranslationEnabled: isTranslationEnabled,
                bookId: bookId
              ) else { return }

        self.editingParagraphIndex = paragraphID
        self.originalSentence = item.original
        self.selectedWordOffset = originalRange.location
        self.selectedWordLength = originalRange.length
        self.selectedDisplayedOffset = selectionRange.location

        self.selectionMinY = minY
        self.selectionMaxY = maxY
        self.showingFloatingMenu = true
    }

    private func ttsChapterInfo(at index: Int) async -> TTSChapterInfo? {
        if let snapshot = await viewModel?.fetchChapterSnapshot(at: index) {
            let rawTitle = snapshot.titleTrans ?? snapshot.title
            let title = isTranslationEnabled && TranslateUtils.containsChinese(rawTitle)
                ? TranslateUtils.translateChapterTitle(rawTitle, bookId: bookId)
                : rawTitle
            return TTSChapterInfo(title: title, url: snapshot.url, index: snapshot.index, host: snapshot.host)
        }

        guard currentOnlineChapters.indices.contains(index) else { return nil }
        let chapter = currentOnlineChapters[index]
        let title = isTranslationEnabled && TranslateUtils.containsChinese(chapter.name)
            ? TranslateUtils.translateChapterTitle(chapter.name, bookId: bookId)
            : chapter.name
        return TTSChapterInfo(title: title, url: chapter.url, index: index, host: chapter.host)
    }

    private func nextChapter() {
        let persistProgress = !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        let targetIndex = (viewModel?.pendingNavigationIndex ?? chapterIndex) + 1
        if targetIndex >= 0 && targetIndex < totalChaptersCount {
            viewModel?.stepChapter(by: 1, source: .nextButton, persistProgress: persistProgress)
        }
    }

    private func prevChapter() {
        let persistProgress = !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        let targetIndex = (viewModel?.pendingNavigationIndex ?? chapterIndex) - 1
        if targetIndex >= 0 && targetIndex < totalChaptersCount {
            viewModel?.stepChapter(by: -1, source: .previousButton, persistProgress: persistProgress)
        }
    }

    private func selectChapter(at index: Int, scroll: Bool = true) {
        let persistProgress = !(ttsManager.isPlaying && ttsManager.playingBookId == bookId)
        requestChapter(
            at: index,
            paragraphIndex: scroll ? -1 : getSavedParagraphIndex(for: index),
            source: .chapterList,
            persistProgress: persistProgress
        )
    }

    private func requestChapter(
        at index: Int,
        paragraphIndex: Int,
        source: ReaderNavigationSource,
        persistProgress: Bool
    ) {
        guard index >= 0 && index < totalChaptersCount else { return }
        isRestoringReaderPosition = true
        paragraphTracker.removeAll()
        viewModel?.requestChapter(
            index: index,
            paragraphIndex: paragraphIndex,
            source: source,
            persistProgress: persistProgress
        )
    }

    private func startTTS(at index: Int, paragraphIndex: Int, startTextOffset: Int? = nil) {
        guard index >= 0 && index < totalChaptersCount else { return }
        Task {
            guard let currentChapter = await ttsChapterInfo(at: index) else { return }
            var initialQueue = [currentChapter]
            let preloadUpperBound = min(totalChaptersCount, index + 4)
            if index + 1 < preloadUpperBound {
                for nextIndex in (index + 1)..<preloadUpperBound {
                    if let nextChapter = await ttsChapterInfo(at: nextIndex) {
                        initialQueue.append(nextChapter)
                    }
                }
            }

            let chapterContentToUse = getTTSChapterContent(for: index)

            ttsManager.startSpeaking(
                bookId: bookId,
                chapters: initialQueue,
                currentIndex: index,
                chapterContent: chapterContentToUse,
                startParagraphIndex: paragraphIndex,
                startTextOffset: startTextOffset,
                bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
                bookDetailUrl: localBook?.detailUrl ?? bookDetailUrl ?? "",
                bookSourceName: localBook?.sourceName ?? bookSourceName ?? "",
                extensionInfo: ttsExtensionInfo
            )
            ttsManager.refreshChaptersQueueInBackground(
                bookId: bookId,
                onlineChapters: localBook == nil ? currentOnlineChapters.enumerated().map {
                    TTSChapterInfo(title: $0.element.name, url: $0.element.url, index: $0.offset, host: $0.element.host)
                } : nil
            )
        }
    }

    private func getTTSChapterContent(for index: Int) -> String {
        guard let cached = viewModel?.cache.get(index) else { return "" }
        let rawContent = cached.originalContent.isEmpty ? cached.content : cached.originalContent
        if isTranslationEnabled && TranslateUtils.containsChinese(rawContent) {
            return TranslateUtils.translateContent(rawContent, bookId: bookId)
        }
        return rawContent
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

        let chapterContentToUse = getTTSChapterContent(for: index)
        guard !chapterContentToUse.isEmpty else { return }

        Task {
            guard let currentChapter = await ttsChapterInfo(at: index) else { return }

            let savedPIdx = getSavedParagraphIndex(for: index)

            ttsManager.prepareSpeaking(
                bookId: bookId,
                chapters: [currentChapter],
                currentIndex: index,
                chapterContent: chapterContentToUse,
                startParagraphIndex: savedPIdx,
                bookTitle: localBook?.title ?? bookTitle ?? "FreeBook",
                coverUrl: localBook?.coverUrl ?? bookCoverUrl ?? "",
                bookDetailUrl: localBook?.detailUrl ?? bookDetailUrl ?? "",
                bookSourceName: localBook?.sourceName ?? bookSourceName ?? "",
                extensionInfo: ttsExtensionInfo
            )
        }
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
        guard !isRestoringReaderPosition else { return }

        // 1. Debounce 200ms cho việc cập nhật tiến trình lưu trữ
        updateProgressWorkItem?.cancel()
        let progressWork = DispatchWorkItem { [weak viewModel] in
            guard let top = self.paragraphTracker.getTopVisible(viewportTopY: 80, currentBookId: self.bookId, currentChapterIndex: self.chapterIndex) ?? self.paragraphTracker.topVisible else { return }
            let ttsOwnsProgress = ttsManager.isPlaying && ttsManager.playingBookId == self.bookId

            guard let vm = viewModel, top.chapterIndex == vm.displayedChapterIndex else { return }
            if !ttsOwnsProgress {
                vm.updateProgress(
                    chapterIndex: top.chapterIndex,
                    paragraphIndex: top.paragraphIndex
                )
            }
        }
        self.updateProgressWorkItem = progressWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: progressWork)

        // 2. Debounce 1.5 giây cho việc đồng bộ con trỏ TTS (tránh re-render ttsManager khi cuộn nhanh)
        guard ttsManager.isPlaying || ttsManager.showFloatingWidget else { return }
        guard ttsManager.playingBookId == bookId else { return }

        updateTTSPositionWorkItem?.cancel()
        let ttsWork = DispatchWorkItem {
            guard let top = self.paragraphTracker.getTopVisible(viewportTopY: 80, currentBookId: self.bookId, currentChapterIndex: self.chapterIndex) ?? self.paragraphTracker.topVisible else { return }
            guard self.ttsManager.playingChapterIndex == top.chapterIndex else { return }
            self.ttsManager.updateParagraphPositionWithoutPlaying(paragraphIndex: top.paragraphIndex)
        }
        self.updateTTSPositionWorkItem = ttsWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: ttsWork)
    }


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
            ReaderViewModelObserver(viewModel: vm) { observedViewModel in
                singleChapterReaderView(viewModel: observedViewModel)
            }
        } else {
            chapterInlineLoadingView(index: chapterIndex)
        }
    }

    private func chapterInlineLoadingView(index: Int) -> some View {
        VStack(spacing: 24) {
            Text(getChapterTitle(at: index))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)

            chapterSkeletonLines
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang tải \(getChapterTitle(at: index))")
    }

    private func chapterBootstrapErrorView(message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
            Button("Quay lại") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chapterSkeletonLines: some View {
        let widthFactors: [CGFloat] = [1, 0.94, 0.82, 1, 0.9, 0.76, 1, 0.86]
        return GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 36)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(widthFactors.indices, id: \.self) { index in
                    SkeletonView(width: availableWidth * widthFactors[index], height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .frame(height: 226)
    }

    private func attemptScroll(to target: ScrollTarget, proxy: ScrollViewProxy, vm: ReaderViewModel) -> Bool {
        guard vm.cache.get(target.chapterIndex)?.state == .loaded else { return false }

        if target.paragraphIndex >= 0 {
            guard let cached = vm.cache.get(target.chapterIndex), cached.state == .loaded else { return false }
            let hasParagraph = cached.paragraphItems.contains(where: { $0.id == target.paragraphIndex })
            if hasParagraph {
                proxy.scrollTo("paragraph-\(target.chapterIndex)-\(target.paragraphIndex)", anchor: .center)
            } else {
                proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
            }
            completeReaderPositionRestore(after: 0.25)
            return true
        }

        proxy.scrollTo("chapter-\(target.chapterIndex)", anchor: .top)
        completeReaderPositionRestore(after: 0.25)
        return true
    }

    @ViewBuilder
    private func singleChapterReaderView(viewModel vm: ReaderViewModel) -> some View {
        GeometryReader { geometry in
            let presentationIndex = vm.pendingNavigationIndex ?? vm.displayedChapterIndex
            ZStack {
                if let failure = vm.navigationFailure {
                    chapterNavigationErrorView(failure: failure, viewModel: vm)
                } else if case .failed(_, let message) = vm.loadState {
                    chapterBootstrapErrorView(message: message)
                } else if let chapter = vm.cache.get(presentationIndex),
                          chapter.state == .loaded {
                    singleChapterScrollView(chapter: chapter, viewModel: vm)
                        .id("single-chapter-\(chapter.index)")
                        .transition(.opacity)
                } else {
                    chapterInlineLoadingView(index: presentationIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                readerViewportHeight = max(geometry.size.height, 360)
            }
            .onChange(of: geometry.size.height) { _, height in
                readerViewportHeight = max(height, 360)
            }
            .onChange(of: vm.navigationCommit) { _, commit in
                guard let commit else { return }
                applyNavigationCommit(commit)
            }
            .animation(
                reduceMotion || vm.navigationCommit?.animateContent != true
                    ? nil
                    : .easeOut(duration: 0.12),
                value: vm.displayedChapterIndex
            )
        }
    }

    private func singleChapterScrollView(
        chapter: CachedChapter,
        viewModel vm: ReaderViewModel
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * 0.8) {
                    chapterContentView(for: chapter)
                }
                .id("chapter-\(chapter.index)")
                .frame(
                    maxWidth: .infinity,
                    minHeight: max(readerViewportHeight, 360),
                    alignment: .topLeading
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
            .onAppear {
                restoreSingleChapterPosition(proxy: proxy, chapter: chapter, viewModel: vm)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target, target.chapterIndex == chapter.index else { return }
                if attemptScroll(to: target, proxy: proxy, vm: vm) {
                    scrollTarget = nil
                }
            }
        }
    }

    private func restoreSingleChapterPosition(
        proxy: ScrollViewProxy,
        chapter: CachedChapter,
        viewModel vm: ReaderViewModel
    ) {
        if let target = scrollTarget, target.chapterIndex == chapter.index,
           attemptScroll(to: target, proxy: proxy, vm: vm) {
            scrollTarget = nil
            schedulePrepareTTS()
        } else {
            restoreReaderPositionIfNeeded(proxy: proxy, chapter: chapter)
        }
    }

    private func applyNavigationCommit(
        _ commit: ReaderNavigationCommit
    ) {
        isRestoringReaderPosition = true
        paragraphTracker.removeAll()
        let apply = {
            chapterIndex = commit.chapterIndex
            scrollTarget = ScrollTarget(
                chapterIndex: commit.chapterIndex,
                paragraphIndex: commit.paragraphIndex
            )
        }
        if reduceMotion || !commit.animateContent || commit.source == .ttsSync {
            apply()
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                apply()
            }
        }
        // Reader navigation is intentionally independent from the active TTS chapter.
    }

    private func chapterNavigationErrorView(
        failure: ReaderChapterLoadFailure,
        viewModel vm: ReaderViewModel
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)

            Text(translateChapterTitleIfNeeded(failure.chapterTitle))
                .font(.title3.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(failure.sourceMessage)
                .font(.subheadline)
                .foregroundColor(selectedTheme.textColor.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { vm.retryPendingNavigation() }) {
                HStack(spacing: 8) {
                    if vm.isRetryingNavigation {
                        ProgressView().tint(selectedTheme.textColor)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Tải lại")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(selectedTheme.textColor)
                .frame(minWidth: 132, minHeight: 44)
                .background(selectedTheme.textColor.opacity(0.1))
                .cornerRadius(8)
            }
            .disabled(vm.isRetryingNavigation)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completeReaderPositionRestore(after delay: TimeInterval = 0) {
        guard isRestoringReaderPosition else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            paragraphTracker.removeAll()
            isRestoringReaderPosition = false
        }
    }

    private func restoreReaderPositionIfNeeded(proxy: ScrollViewProxy, chapter: CachedChapter) {
        guard !chapter.isPositionRestored else {
            schedulePrepareTTS()
            return
        }
        chapter.isPositionRestored = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let savedPIdx = getSavedParagraphIndex(for: chapter.index)
            let hasValidParagraph = chapter.paragraphItems.contains(where: { $0.id == savedPIdx })
            if savedPIdx >= 0 && hasValidParagraph {
                proxy.scrollTo("paragraph-\(chapter.index)-\(savedPIdx)", anchor: .top)
            } else {
                proxy.scrollTo("chapter-\(chapter.index)", anchor: .top)
            }
            completeReaderPositionRestore()
            schedulePrepareTTS()
        }
    }

    private var readerBookDisplayTitle: String {
        DisplayTextFormatter.titleCase(translateMetaIfNeeded(localBook?.title ?? bookTitle ?? "FreeBook"))
    }

    private var readerPresentedChapterIndex: Int {
        viewModel?.pendingNavigationIndex ?? viewModel?.displayedChapterIndex ?? chapterIndex
    }

    private var readerChapterDisplayTitle: String {
        getChapterTitle(at: readerPresentedChapterIndex)
    }

    private var readerProgressPercent: Double {
        guard totalChaptersCount > 0 else { return 0 }
        return (Double(readerPresentedChapterIndex + 1) / Double(totalChaptersCount)) * 100
    }

    private var readerChromeBackground: Color {
        selectedTheme == .dark ? Color.black.opacity(0.78) : Color.white.opacity(0.72)
    }



    private func toggleChapterTitleVisibility() {
        showChapterTitle.toggle()
        UserDefaults.standard.set(showChapterTitle, forKey: "showChapterTitle_\(bookId)")
        viewModel?.refreshParagraphItems()
    }

    private func reloadCurrentChapterFromMenu() {
        paragraphTracker.removeAll()
        isRestoringReaderPosition = true
        viewModel?.reloadDisplayedChapter()
    }

    @ViewBuilder
    private func readerTTSControl(geometry: GeometryProxy) -> some View {
        readerEdgeButton(
            // Keep this as the Reader listen action. It must not become a
            // global stop control when another book owns the TTS session.
            icon: "headphones",
            tint: selectedTheme.textColor.opacity(0.9),
            action: {
                if ttsManager.isPlaying || ttsManager.showFloatingWidget {
                    ttsManager.stop()
                }
                let viewportTopY = geometry.frame(in: .global).minY + geometry.safeAreaInsets.top + 20
                if let top = paragraphTracker.getTopVisible(viewportTopY: viewportTopY, currentBookId: bookId, currentChapterIndex: chapterIndex) {
                    startTTS(at: top.chapterIndex, paragraphIndex: top.paragraphIndex)
                } else if let top = paragraphTracker.topVisible {
                    startTTS(at: top.chapterIndex, paragraphIndex: top.paragraphIndex)
                } else {
                    let savedPIdx = getSavedParagraphIndex(for: chapterIndex)
                    let targetPIdx: Int
                    if savedPIdx >= 0 {
                        targetPIdx = savedPIdx
                    } else if let vm = viewModel, vm.readingContext.chapterIndex == chapterIndex, vm.readingContext.paragraphIndex >= 0 {
                        targetPIdx = vm.readingContext.paragraphIndex
                    } else {
                        targetPIdx = -1
                    }
                    startTTS(at: chapterIndex, paragraphIndex: targetPIdx)
                }
            }
        )
        .accessibilityLabel(isTTSPlayingThisBook ? "Dừng đọc thành tiếng" : "Đọc thành tiếng")
        .padding(8)
        .background(.ultraThinMaterial, in: Circle())
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
        .padding(.trailing, 8)
        .padding(.bottom, 12)
    }

    private func readerEdgeButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(selectedTheme == .dark ? 0.34 : 0.12))
                .clipShape(Circle())
        }
    }
}

struct ScrollTarget: Equatable {
    let chapterIndex: Int
    let paragraphIndex: Int
}

struct ParagraphFrame: Equatable {
    let bookId: String
    let chapterIndex: Int
    let paragraphIndex: Int
    let minY: CGFloat
    let maxY: CGFloat
}

class ParagraphTracker {
    private var visibleParagraphs: Set<ReadingContext> = []
    private var frames: [ReadingContext: ParagraphFrame] = [:]

    func insert(bookId: String, chapterIndex: Int, paragraphIndex: Int) {
        visibleParagraphs.insert(ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex))
    }

    func updateFrame(bookId: String, chapterIndex: Int, paragraphIndex: Int, minY: CGFloat, maxY: CGFloat) {
        let ctx = ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        visibleParagraphs.insert(ctx)
        frames[ctx] = ParagraphFrame(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex, minY: minY, maxY: maxY)
    }

    func remove(bookId: String, chapterIndex: Int, paragraphIndex: Int) {
        let ctx = ReadingContext(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
        visibleParagraphs.remove(ctx)
        frames.removeValue(forKey: ctx)
    }

    func removeAll() {
        visibleParagraphs.removeAll()
        frames.removeAll()
    }

    func getTopVisible(viewportTopY: CGFloat, currentBookId: String, currentChapterIndex: Int) -> ReadingContext? {
        let candidates = frames.values.filter {
            $0.bookId == currentBookId &&
            $0.chapterIndex == currentChapterIndex &&
            $0.maxY > viewportTopY + 5
        }

        if !candidates.isEmpty {
            let sorted = candidates.sorted {
                if abs($0.minY - $1.minY) < 1.0 {
                    return $0.paragraphIndex < $1.paragraphIndex
                }
                return $0.minY < $1.minY
            }
            if let best = sorted.first {
                return ReadingContext(bookId: best.bookId, chapterIndex: best.chapterIndex, paragraphIndex: best.paragraphIndex)
            }
        }

        return topVisible
    }

    var topVisible: ReadingContext? {
        visibleParagraphs.sorted {
            if $0.chapterIndex == $1.chapterIndex {
                return $0.paragraphIndex < $1.paragraphIndex
            }
            return $0.chapterIndex < $1.chapterIndex
        }.first
    }
}

// MARK: - Floating Selection Menu

struct FloatingSelectionMenu: View {
    let selectionMinY: CGFloat   // Tọa độ Y trên cùng của selection (window coordinates từ UIKit)
    let selectionMaxY: CGFloat   // Tọa độ Y dưới cùng của selection (window coordinates từ UIKit)
    let geometryOriginY: CGFloat // Tọa độ Y toàn cục của GeometryReader (để chuyển đổi sang local)
    let screenWidth: CGFloat
    let onTranslate: () -> Void
    let onSpeak: () -> Void
    let onPhoneme: () -> Void
    let onCopy: () -> Void
    let onReadSelected: () -> Void
    let onDeleteJunk: () -> Void

    // Chiều rộng tổng của menu (6 nút × 60 + padding)
    private let menuWidth: CGFloat = 370
    // Khoảng cách giữa menu và cạnh trên/dưới vùng bôi đen
    private let gap: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTranslate) {
                VStack(spacing: 3) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Dịch")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onSpeak) {
                VStack(spacing: 3) {
                    Image(systemName: "headphones")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Nghe")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onPhoneme) {
                VStack(spacing: 3) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Phiên âm")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onCopy) {
                VStack(spacing: 3) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Copy")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onReadSelected) {
                VStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Đọc")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onDeleteJunk) {
                VStack(spacing: 3) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Xoá")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.red)
                .frame(width: 60, height: 48)
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.92))
                .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
        .position(
            // X: căn giữa màn hình, giới hạn trong lề an toàn
            x: min(max(screenWidth / 2, menuWidth / 2 + 16), screenWidth - menuWidth / 2 - 16),
            // Y: chuyển đổi từ window coords sang local coords của GeometryReader
            // Nếu có đủ không gian phía trên (>80pt tính từ đỉnh GeometryReader) → đặt TRÊN selection
            // Ngược lại → đặt DƯỚI selection
            y: {
                let localMinY = selectionMinY - geometryOriginY
                let localMaxY = selectionMaxY - geometryOriginY
                return localMinY > 80 ? localMinY - gap : localMaxY + gap
            }()
        )
    }
}
