import SwiftUI
import SwiftData

struct ChapterRowInfo: Identifiable {
    var id: Int { index }
    let title: String
    let displayTitle: String
    let url: String
    let index: Int
    let isCached: Bool
}

struct ReaderChapterListView: View {
    let bookId: String
    let extensionPackageId: String
    let bookDetailUrl: String?
    let currentChapterIndex: Int
    let isTranslationEnabled: Bool
    let theme: ReaderTheme
    @Binding var onlineChapters: [ChapterResult]
    let isVisible: Bool
    let onSelectChapter: (Int) -> Void
    let onClose: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    @Query private var allExtensions: [Extension]
    
    @State private var searchQuery = ""
    @State private var isAscending = true
    @State private var chaptersList: [ChapterRowInfo] = []
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
    
    var filteredChapters: [ChapterRowInfo] {
        let baseList = isAscending ? chaptersList : Array(chaptersList.reversed())
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseList
        }
        return baseList.filter { chap in
            chap.displayTitle.localizedCaseInsensitiveContains(searchQuery) ||
            chap.title.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Custom Navigation Bar / Header
                HStack {
                    // Nút Tải lại bên trái
                    if isUpdating {
                        ProgressView()
                            .tint(theme.textColor)
                            .frame(width: 44, height: 44)
                    } else {
                        Button(action: refreshChapters) {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .foregroundColor(theme.textColor)
                                .frame(width: 44, height: 44)
                        }
                    }
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAscending.toggle()
                        }
                    }) {
                        Image(systemName: isAscending ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.title3)
                            .foregroundColor(theme.textColor)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                    
                    // Tiêu đề ở giữa
                    Text("Danh sách chương (\(chaptersList.count))")
                        .font(.headline)
                        .foregroundColor(theme.textColor)
                    
                    Spacer()
                    
                    // Nút Đóng bên phải
                    Button(action: onClose) {
                        Text("Đóng")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(theme.textColor)
                            .frame(width: 60, height: 44)
                    }
                }
                .padding(.horizontal)
                .frame(height: 50)
                .background(theme.backgroundColor)
                
                Divider()
                    .background(theme.textColor.opacity(0.1))
                
                // Hiển thị lỗi nếu có
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Divider()
                        .background(theme.textColor.opacity(0.1))
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
                        ForEach(filteredChapters) { chap in
                            let isCurrent = chap.index == currentChapterIndex
                            let titleText = chap.displayTitle
                            
                            Button(action: {
                                onSelectChapter(chap.index)
                                onClose()
                            }) {
                                HStack {
                                    Text(titleText)
                                        .font(.body)
                                        .foregroundColor(isCurrent ? Color.blue : theme.textColor)
                                        .fontWeight(isCurrent ? .semibold : .regular)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if chap.isCached {
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
                    .onChange(of: isVisible) { _, newValue in
                        if newValue {
                            // Tự động cuộn đến chương hiện tại khi danh sách được mở ra
                            if searchQuery.isEmpty {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    withAnimation {
                                        proxy.scrollTo("chap-\(currentChapterIndex)", anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(theme.backgroundColor.ignoresSafeArea())
            .onAppear {
                loadChapters()
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
                let displayTitle = (isTranslationEnabled && TranslateUtils.containsChinese(chap.title))
                    ? TranslateUtils.translateChapterTitle(chap.title, bookId: bookId)
                    : chap.title
                
                return ChapterRowInfo(
                    title: chap.title,
                    displayTitle: displayTitle,
                    url: chap.url,
                    index: chap.index,
                    isCached: chap.isCached
                )
            }
        } else {
            self.chaptersList = onlineChapters.enumerated().map { (index, chap) in
                let displayTitle = (isTranslationEnabled && TranslateUtils.containsChinese(chap.name))
                    ? TranslateUtils.translateChapterTitle(chap.name, bookId: bookId)
                    : chap.name
                
                return ChapterRowInfo(
                    title: chap.name,
                    displayTitle: displayTitle,
                    url: chap.url,
                    index: index,
                    isCached: false
                )
            }
        }
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
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                    for pageUrl in pages {
                        let pageChaps = try await ExtensionManager.shared.toc(
                            localPath: ext.localPath,
                            downloadUrl: ext.downloadUrl,
                            url: pageUrl,
                            host: localBook?.host,
                            configJson: ext.configJson
                        )
                        allChapters.append(contentsOf: pageChaps)
                    }
                } else {
                    let tocResult = try await ExtensionManager.shared.toc(
                        localPath: ext.localPath,
                        downloadUrl: ext.downloadUrl,
                        url: url,
                        host: localBook?.host,
                        configJson: ext.configJson
                    )
                    allChapters = tocResult
                }
                
                await MainActor.run {
                    if let book = localBook {
                        // Cập nhật host của truyện nếu trống
                        if (book.host == nil || book.host!.isEmpty), let firstHost = allChapters.first?.host, !firstHost.isEmpty {
                            book.host = firstHost
                        }
                        
                        let existingChaps = book.chapters
                        let existingUrls = Set(existingChaps.map { $0.url })
                        
                        // Lọc ra các chương chưa có trong DB
                        let newChaptersFromTOC = allChapters.filter { !existingUrls.contains($0.url) }
                        
                        if !newChaptersFromTOC.isEmpty {
                            var addedChapters: [Chapter] = []
                            for item in newChaptersFromTOC {
                                let originalIndex = allChapters.firstIndex(where: { $0.url == item.url }) ?? existingChaps.count
                                
                                let chapId = "\(bookId)_\(item.url)"
                                let newChap = Chapter(
                                    id: chapId,
                                    title: item.name,
                                    url: item.url,
                                    index: originalIndex,
                                    host: item.host
                                )
                                newChap.book = book
                                modelContext.insert(newChap)
                                addedChapters.append(newChap)
                            }
                            
                            book.chapters.append(contentsOf: addedChapters)
                            try? modelContext.save()
                            
                            loadChapters()
                            showToast("Đã cập nhật thêm \(newChaptersFromTOC.count) chương mới!", isError: false)
                        } else {
                            showToast("Mục lục đã là mới nhất, không có chương mới!", isError: false)
                        }
                    } else {
                        // Đối với truyện online, chỉ đè onlineChapters
                        let oldOnlineCount = self.onlineChapters.count
                        self.onlineChapters = allChapters
                        loadChapters()
                        
                        let newAdded = allChapters.count - oldOnlineCount
                        if newAdded > 0 {
                            showToast("Đã cập nhật thêm \(newAdded) chương mới!", isError: false)
                        } else {
                            showToast("Mục lục đã là mới nhất, không có chương mới!", isError: false)
                        }
                    }
                    
                    isUpdating = false
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
