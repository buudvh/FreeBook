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
    
    @State private var toastMessage = ""
    @State private var showingToast = false
    @State private var isToastError = false
    
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
            let displayTitle = displayTitle(for: chap.title, index: chap.index)
            return displayTitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var body: some View {
        ZStack {
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
                                let titleText = displayTitle(for: chap.title, index: chap.index)
                                
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
            
            if showingToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: isToastError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(isToastError ? .red : .green)
                        Text(toastMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.1).opacity(0.9))
                    )
                    .padding(.bottom, 30)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
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
    
    private func displayTitle(for rawTitle: String, index: Int) -> String {
        if isTranslationEnabled {
            if let book = localBook {
                let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                if index < sorted.count {
                    let dbChap = sorted[index]
                    if let trans = dbChap.titleTrans, !trans.isEmpty {
                        return trans
                    } else if TranslateUtils.containsChinese(rawTitle) {
                        let trans = TranslateUtils.translateChapterTitle(rawTitle, bookId: bookId)
                        dbChap.titleTrans = trans
                        try? modelContext.save()
                        return trans
                    }
                }
            }
            if TranslateUtils.containsChinese(rawTitle) {
                return TranslateUtils.translateChapterTitle(rawTitle, bookId: bookId)
            }
        }
        return rawTitle
    }
    
    private func showToast(_ message: String, isError: Bool) {
        toastMessage = message
        isToastError = isError
        withAnimation {
            showingToast = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showingToast = false
            }
        }
    }

    private func refreshChapters() {
        guard let ext = ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách!"
            showToast("Lỗi: Không tìm thấy tiện ích!", isError: true)
            return
        }
        let url = localBook?.detailUrl ?? bookDetailUrl ?? ""
        guard !url.isEmpty else {
            errorMessage = "Đường dẫn truyện không hợp lệ!"
            showToast("Lỗi: Đường dẫn không hợp lệ!", isError: true)
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
                                existing.titleTrans = TranslateUtils.translateChapterTitle(item.name, bookId: bookId)
                                newChapters.append(existing)
                            } else {
                                let chapId = "\(bookId)_\(item.url)"
                                let transTitle = TranslateUtils.translateChapterTitle(item.name, bookId: bookId)
                                let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: index, titleTrans: transTitle)
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
                    showToast("Cập nhật danh sách chương thành công!", isError: false)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
                    self.isUpdating = false
                    showToast("Cập nhật thất bại: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}
