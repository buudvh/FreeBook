import SwiftUI
import SwiftData

struct ReaderChapterListView: View {
    let bookId: String
    let extensionPackageId: String
    let bookDetailUrl: String?
    let currentChapterIndex: Int
    let isTranslationEnabled: Bool
    let theme: ReaderTheme
    @Binding var onlineChapters: [ChapterResult]
    let onSelectChapter: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    @Query private var allExtensions: [Extension]
    
    @State private var searchQuery = ""
    @State private var chaptersList: [TTSChapterInfo] = []
    @State private var isUpdating = false
    @State private var errorMessage = ""
    
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
    }
    
    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }
    
    var filteredChapters: [TTSChapterInfo] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return chaptersList
        }
        return chaptersList.filter { chap in
            let displayTitle = displayTitle(for: chap.title)
            return displayTitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Hiển thị lỗi nếu có
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                
                // Thanh tìm kiếm chương
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(theme.textColor.opacity(0.6))
                    
                    TextField("Tìm kiếm chương...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundColor(theme.textColor)
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(theme.textColor.opacity(0.6))
                        }
                    }
                }
                .padding(10)
                .background(theme.textColor.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                // Danh sách chương
                ScrollViewReader { proxy in
                    List {
                        ForEach(filteredChapters, id: \.index) { chap in
                            let isCurrent = chap.index == currentChapterIndex
                            let titleText = displayTitle(for: chap.title)
                            
                            Button(action: {
                                onSelectChapter(chap.index)
                                dismiss()
                            }) {
                                HStack {
                                    Text(titleText)
                                        .font(.body)
                                        .foregroundColor(isCurrent ? Color.blue : theme.textColor)
                                        .fontWeight(isCurrent ? .semibold : .regular)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if chap.cachedContent != nil {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(isCurrent ? Color.blue.opacity(0.08) : theme.backgroundColor)
                            .id("chap-\(chap.index)")
                        }
                    }
                    .listStyle(.plain)
                    .background(theme.backgroundColor)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        // Tự động cuộn đến chương hiện tại
                        if searchQuery.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo("chap-\(currentChapterIndex)", anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .background(theme.backgroundColor)
            .navigationTitle("Danh sách chương (\(chaptersList.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isUpdating {
                        ProgressView()
                            .tint(theme.textColor)
                    } else {
                        Button(action: refreshChapters) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(theme.textColor)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .foregroundColor(theme.textColor)
                }
            }
            .toolbarColorScheme(theme == .dark ? .dark : .light, for: .navigationBar)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                loadChapters()
            }
        }
    }
    
    private func loadChapters() {
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            self.chaptersList = sorted.map { chap in
                TTSChapterInfo(
                    title: chap.title,
                    url: chap.url,
                    index: chap.index,
                    cachedContent: chap.isCached ? chap.content : nil
                )
            }
        } else {
            self.chaptersList = onlineChapters.enumerated().map { (index, chap) in
                TTSChapterInfo(
                    title: chap.name,
                    url: chap.url,
                    index: index,
                    cachedContent: nil
                )
            }
        }
    }
    
    private func displayTitle(for rawTitle: String) -> String {
        if isTranslationEnabled && TranslateUtils.containsChinese(rawTitle) {
            return TranslateUtils.translateChapterTitle(rawTitle, bookId: bookId)
        }
        return rawTitle
    }
    
    private func refreshChapters() {
        guard let ext = ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách!"
            return
        }
        let url = localBook?.detailUrl ?? bookDetailUrl ?? ""
        guard !url.isEmpty else {
            errorMessage = "Đường dẫn truyện không hợp lệ!"
            return
        }
        
        isUpdating = true
        errorMessage = ""
        
        Task {
            do {
                var allChapters: [ChapterResult] = []
                if ExtensionManager.shared.hasScript(localPath: ext.localPath, scriptKey: "page") {
                    let pages = try await ExtensionManager.shared.page(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        configJson: ext.configJson
                    )
                    for pageUrl in pages {
                        let pageChaps = try await ExtensionManager.shared.toc(
                            localPath: ext.localPath,
                            downloadUrl: ext.downloadUrl,
                            url: pageUrl,
                            configJson: ext.configJson
                        )
                        allChapters.append(contentsOf: pageChaps)
                    }
                } else {
                    let tocResult = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        configJson: ext.configJson
                    )
                    allChapters = tocResult
                }
                
                await MainActor.run {
                    if let book = localBook {
                        // Tránh mất cache của chương cũ bằng cách gộp chương thông minh
                        let existingChaps = book.chapters
                        let existingMap = Dictionary(uniqueKeysWithValues: existingChaps.map { ($0.url, $0) })
                        
                        var newChapters: [Chapter] = []
                        for (index, item) in allChapters.enumerated() {
                            if let existing = existingMap[item.url] {
                                existing.title = item.name
                                existing.index = index
                                newChapters.append(existing)
                            } else {
                                let chapId = "\(bookId)_\(item.url)"
                                let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: index)
                                newChap.book = book
                                modelContext.insert(newChap)
                                newChapters.append(newChap)
                            }
                        }
                        book.chapters = newChapters
                        try? modelContext.save()
                    } else {
                        // Cập nhật onlineChapters binding
                        self.onlineChapters = allChapters
                    }
                    
                    // Nạp lại danh sách chương
                    loadChapters()
                    isUpdating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
                    self.isUpdating = false
                }
            }
        }
    }
}
