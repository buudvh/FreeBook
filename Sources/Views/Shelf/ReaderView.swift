import SwiftUI
import SwiftData

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
    @State private var saveToBookSpecific = true
    @State private var saveAsNameType = false
    
    // Advanced Highlight Translation Editor
    @State private var originalSentence = ""
    @State private var selectedWordOffset = 0
    @State private var selectedWordLength = 0
    @State private var searchEngines: [SearchEngine] = []
    @State private var translationMode: String = "VP" // "VP" or "HV"
    
    // Tùy chọn giao diện đọc (Novel)
    @AppStorage("readerFontSize") private var fontSize: Double = 18.0
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State private var selectedTheme: ReaderTheme = .paper
    @State private var showingSettings = false
    
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
    }
    
    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
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
                                    theme: selectedTheme,
                                    onSelectionChange: { selectedText, sentence, offset in
                                        self.originalSentence = sentence
                                        self.selectedWordOffset = offset
                                        self.selectedWordLength = selectedText.count
                                        self.updateEditorFromSelection()
                                        self.showingDefinitionSheet = true
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
        }
        .navigationTitle(currentChapterInfo?.title ?? "Trình đọc")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if ext?.type != "comic" {
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "textformat.size")
                            .foregroundColor(selectedTheme.textColor)
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(fontSize: $fontSize, selectedTheme: $selectedTheme, isTranslationEnabled: $isTranslationEnabled)
                .presentationDetents([.height(240)])
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
                
                // Original Hán ngữ segment with adjuster
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
                    
                    let segs = sentenceSegments
                    Text(segs.prefix)
                        .foregroundColor(.secondary)
                    + Text(segs.selected)
                        .foregroundColor(.primary)
                        .bold()
                        .underline()
                    + Text(segs.suffix)
                        .foregroundColor(.secondary)
                    
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
                .lineLimit(1)
                
                // Translated segment text
                let tSegs = translatedSentenceSegments
                HStack {
                    Text(tSegs.prefix)
                        .foregroundColor(.secondary)
                    + Text(tSegs.selected)
                        .foregroundColor(.primary)
                        .bold()
                        .underline()
                    + Text(tSegs.suffix)
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                
                // Input TextField with Clear button
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
                
                // Quick suggestions chips
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
                
                // Case formats & Dictionary toggles
                HStack(spacing: 12) {
                    // Case formats
                    HStack(spacing: 4) {
                        Button("aa") { customMeaning = customMeaning.lowercased() }
                        Button("Aa¹") {
                            if !customMeaning.isEmpty {
                                customMeaning = customMeaning.prefix(1).uppercased() + customMeaning.dropFirst().lowercased()
                            }
                        }
                        Button("Aa²") { customMeaning = customMeaning.capitalized }
                        Button("AA") { customMeaning = customMeaning.uppercased() }
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    // NE / VP
                    Picker("Loại", selection: $saveAsNameType) {
                        Text("Names (NE)").tag(true)
                        Text("VietPhrase (VP)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                
                HStack {
                    // Scope: Riêng / Chung
                    Picker("Phạm vi", selection: $saveToBookSpecific) {
                        Text("Riêng truyện").tag(true)
                        Text("Chung hệ thống").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    Spacer()
                    
                    // Update action button
                    Button(action: saveDefinition) {
                        Label("Cập nhật", systemImage: "tray.and.arrow.down.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customMeaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
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
            .presentationDetents([.height(430)])
            .onAppear {
                self.searchEngines = SearchEngine.loadEngines()
            }
        }
        .onAppear {
            // Tải theme mặc định từ AppStorage nếu thích hợp, ở đây dùng sepia/paper làm mặc định
            loadChapterContent()
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
                }
            }
        } else {
            self.chapterTitle = originalTitle
            self.chapterContent = originalContent
            self.isLoading = false
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
                AppLogger.shared.log("❌ Lỗi lưu định nghĩa từ: \(error.localizedDescription)")
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
        let word = selectedTextForDefinition
        
        let currentTranslation = TranslateUtils.translateMeta(word, bookId: bookId)
        if !currentTranslation.isEmpty && currentTranslation != word {
            let clean = currentTranslation.replacingOccurrences(of: "¦", with: "/")
            let parts = clean.components(separatedBy: "/")
            for part in parts {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !chips.contains(trimmed) {
                    chips.append(trimmed)
                }
            }
        }
        
        let hv = getHanViet(for: word)
        if !hv.isEmpty {
            if !chips.contains(hv) {
                chips.append(hv)
            }
            let hvLower = hv.lowercased()
            if !chips.contains(hvLower) {
                chips.append(hvLower)
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
    }
    
    private func performQuickLookup(using engine: SearchEngine) {
        let word = selectedTextForDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        
        guard let encodedWord = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let urlString = engine.urlTemplate.replacingOccurrences(of: "%s", with: encodedWord)
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
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
}

// MARK: - ReaderSettingsView Sheet
struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var selectedTheme: ReaderTheme
    @Binding var isTranslationEnabled: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Cài đặt trình đọc")
                .font(.headline)
                .padding(.top)
            
            // Chỉnh size chữ
            HStack(spacing: 20) {
                Button(action: { if fontSize > 12 { fontSize -= 1 } }) {
                    Image(systemName: "textformat.size.smaller")
                        .padding(10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
                }
                
                Text("\(Int(fontSize)) pt")
                    .font(.subheadline)
                    .frame(width: 60)
                
                Button(action: { if fontSize < 36 { fontSize += 1 } }) {
                    Image(systemName: "textformat.size.larger")
                        .padding(10)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(8)
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
