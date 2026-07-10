import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    @Query private var allExtensions: [Extension]
    
    let bookId: String
    let extensionPackageId: String
    let initialDetailUrl: String
    let sourceName: String
    
    @State private var isLoading = true
    @State private var errorMessage = ""
    
    // Dữ liệu tạm thời khi xem online (chưa thêm vào kệ)
    @State private var title = ""
    @State private var author = ""
    @State private var coverUrl = ""
    @State private var desc = ""
    @State private var detail = ""
    @State private var onlineChapters: [ChapterResult] = []
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    
    // Phân trang danh sách chương
    @State private var tocPages: [String] = []
    @State private var remainingPagesLoaded = false
    @State private var isLoadingRemainingPages = false
    @State private var navigateToReader = false
    @State private var targetChapterIndex = 0
    
    // Tìm sách local trong database
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
    }
    
    // Tìm extension cục bộ để chạy script
    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }
    
    private func cleanDetailText(_ html: String) -> String {
        return html.cleanHTML()
    }
    
    private var cleanedDetailText: String {
        cleanDetailText(detail)
    }
    
    private func translateMetaIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }
    
    private func translateTitleIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateChapterTitle(text, bookId: bookId)
    }
    
    var body: some View {
        ZStack {
            VStack {
            if isLoading {
                ProgressView("Đang tải chi tiết truyện...")
                    .frame(maxHeight: .infinity)
            } else if !errorMessage.isEmpty {
                VStack(spacing: 16) {
                    Text("Có lỗi xảy ra")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Thử lại") {
                        loadBookData()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Phần Header truyện
                        HStack(alignment: .top, spacing: 16) {
                            BookCoverView(bookId: bookId, coverUrl: coverUrl, width: 100, height: 140)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(translateMetaIfNeeded(title))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(3)
                                
                                Text("Tác giả: \(translateMetaIfNeeded(author))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("Nguồn: \(sourceName)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(6)
                                
                                if !detail.isEmpty {
                                    Text(translateMetaIfNeeded(cleanedDetailText))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(4)
                                }
                                
                                Spacer()
                                
                                // Nút Thêm Kệ Sách / Bắt đầu đọc
                                HStack {
                                    if let book = localBook, book.isOnShelf {
                                        Button(action: {
                                            removeFromShelf(book)
                                        }) {
                                            Label("Đã ở kệ", systemImage: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.green.opacity(0.1))
                                                .cornerRadius(6)
                                        }
                                    } else {
                                        Button(action: addToShelf) {
                                            Label("Thêm vào kệ", systemImage: "plus")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.accentColor)
                                                .cornerRadius(6)
                                        }
                                    }
                                    
                                    let activeChapterIndex = localBook?.currentChapterIndex ?? 0
                                    let totalChaps = localBook?.chapters.count ?? onlineChapters.count
                                    
                                    if totalChaps > 0 {
                                        Button(action: {
                                            targetChapterIndex = activeChapterIndex
                                            startReading()
                                        }) {
                                            Text(localBook == nil ? "Đọc ngay" : "Đọc tiếp")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Color.blue)
                                                .cornerRadius(6)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Phần mô tả giới thiệu
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Giới thiệu")
                                .font(.headline)
                            Text(desc)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Phần danh sách chương
                        VStack(alignment: .leading, spacing: 8) {
                            let totalChaps = localBook?.chapters.count ?? onlineChapters.count
                            Text("Danh sách chương (\(totalChaps))")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            if totalChaps == 0 {
                                Text("Không tìm thấy chương nào")
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    if let book = localBook {
                                        // Hiển thị chương từ database
                                        let sortedChaps = book.chapters.sorted(by: { $0.index < $1.index })
                                        ForEach(sortedChaps) { chap in
                                            Button(action: {
                                                targetChapterIndex = chap.index
                                                startReading()
                                            }) {
                                                HStack {
                                                    Text(translateTitleIfNeeded(chap.title))
                                                        .foregroundColor(book.currentChapterIndex == chap.index ? .accentColor : .primary)
                                                        .font(.subheadline)
                                                        .lineLimit(1)
                                                    Spacer()
                                                    if chap.isCached {
                                                        Image(systemName: "arrow.down.circle.fill")
                                                            .font(.caption)
                                                            .foregroundColor(.green)
                                                    }
                                                }
                                                .padding(.vertical, 12)
                                                .padding(.horizontal)
                                                Divider()
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } else {
                                        // Hiển thị chương online
                                        ForEach(Array(onlineChapters.enumerated()), id: \.offset) { index, chap in
                                            Button(action: {
                                                targetChapterIndex = index
                                                startReading()
                                            }) {
                                                VStack(alignment: .leading) {
                                                    Text(translateTitleIfNeeded(chap.name))
                                                        .font(.subheadline)
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                        .padding(.vertical, 12)
                                                        .padding(.horizontal)
                                                    Divider()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    
                                    // Nút tải thêm chương phân trang
                                    if tocPages.count > 1 && !remainingPagesLoaded {
                                        Button(action: loadMoreChapters) {
                                            HStack {
                                                Spacer()
                                                Text("Tải thêm chương (còn \(tocPages.count - 1) trang)")
                                                    .fontWeight(.semibold)
                                                Spacer()
                                            }
                                            .padding()
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                            .padding(.horizontal)
                                            .padding(.top, 10)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await reloadBookData()
                }
            }
        }
            .navigationTitle("Chi Tiết Truyện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        isTranslationEnabled.toggle()
                    }) {
                        Image(systemName: isTranslationEnabled ? "character.bubble.fill" : "character.bubble")
                    }
                    
                    if localBook != nil {
                        NavigationLink(destination: BookDictionaryView(bookId: bookId)) {
                            Image(systemName: "character.book.closed")
                        }
                    }
                }
            }
            .onAppear {
                loadBookData()
            }
            
            // Hidden navigation link for programmatic reader routing
            NavigationLink(
                destination: ReaderView(
                    bookId: bookId,
                    extensionPackageId: extensionPackageId,
                    chapterIndex: targetChapterIndex,
                    onlineChapters: localBook == nil ? onlineChapters : [],
                    bookTitle: title,
                    bookAuthor: author,
                    bookCoverUrl: coverUrl,
                    bookDesc: desc.isEmpty ? nil : desc,
                    bookDetailUrl: initialDetailUrl,
                    bookSourceName: sourceName
                ),
                isActive: $navigateToReader
            ) {
                EmptyView()
            }
            
            // Loading remaining pages overlay
            if isLoadingRemainingPages {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("Đang tải danh sách chương...")
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(20)
                .background(Color.black.opacity(0.75))
                .cornerRadius(12)
            }
        }
    }
    
    private func loadBookData() {
        // Nếu sách đã ở local, gán dữ liệu từ local để hiển thị ngay
        if let book = localBook {
            self.title = book.title
            self.author = book.author
            self.coverUrl = book.coverUrl
            self.desc = book.desc
            if !book.chapters.isEmpty {
                self.remainingPagesLoaded = true
                self.isLoading = false
                return
            }
        }
        
        guard let ext = ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách của truyện này!"
            self.isLoading = false
            return
        }
        
        guard !ext.localPath.isEmpty else {
            errorMessage = "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!"
            self.isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let path = ext.localPath
                // Chạy chi tiết truyện
                let detailResult = try await ExtensionManager.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                
                // Chạy mục lục chương (có hỗ trợ phân trang)
                var firstPageChapters: [ChapterResult] = []
                var pages: [String] = []
                
                if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                    pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                    if !pages.isEmpty {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pages[0], configJson: ext.configJson)
                    } else {
                        firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                    }
                } else {
                    firstPageChapters = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                }
                
                await MainActor.run {
                    self.title = detailResult.name
                    self.author = detailResult.author
                    self.coverUrl = detailResult.cover
                    self.desc = detailResult.description.cleanHTML()
                    self.detail = detailResult.detail
                    self.onlineChapters = firstPageChapters
                    self.tocPages = pages
                    
                    // Nếu sách đã ở local nhưng rỗng chương (hoặc cần update), cập nhật lại
                    if let book = localBook {
                        book.title = detailResult.name
                        book.author = detailResult.author
                        book.coverUrl = detailResult.cover
                        let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                        book.desc = savedDesc
                        
                        // Cập nhật chương
                        updateLocalChapters(for: book, with: firstPageChapters)
                    }
                    
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func addToShelf() {
        let savedDesc = detail.isEmpty ? desc : "\(desc)\n\n---\n\(cleanDetailText(detail))"
        
        if let book = localBook {
            book.isOnShelf = true
            try? modelContext.save()
            
            // Tải toàn bộ chương nếu chưa được nạp đầy đủ
            if tocPages.count > 1 && !remainingPagesLoaded {
                isLoadingRemainingPages = true
                Task {
                    do {
                        let remainingChaps = try await loadAllRemainingPages()
                        await MainActor.run {
                            self.onlineChapters.append(contentsOf: remainingChaps)
                            let startIdx = book.chapters.count
                            for (index, item) in remainingChaps.enumerated() {
                                let chapId = "\(bookId)_\(item.url)"
                                let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx + index)
                                newChap.book = book
                                modelContext.insert(newChap)
                            }
                            try? modelContext.save()
                            self.remainingPagesLoaded = true
                            self.isLoadingRemainingPages = false
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Lỗi tải thêm chương: \(error.localizedDescription)"
                            self.isLoadingRemainingPages = false
                        }
                    }
                }
            }
        } else {
            if tocPages.count > 1 && !remainingPagesLoaded {
                isLoadingRemainingPages = true
                Task {
                    do {
                        let remainingChaps = try await loadAllRemainingPages()
                        await MainActor.run {
                            self.onlineChapters.append(contentsOf: remainingChaps)
                            createBookOnShelf(savedDesc: savedDesc)
                            self.remainingPagesLoaded = true
                            self.isLoadingRemainingPages = false
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Lỗi tải thêm chương khi lưu kệ: \(error.localizedDescription)"
                            self.isLoadingRemainingPages = false
                            createBookOnShelf(savedDesc: savedDesc)
                        }
                    }
                }
            } else {
                createBookOnShelf(savedDesc: savedDesc)
            }
        }
    }
    
    private func createBookOnShelf(savedDesc: String) {
        let newBook = Book(
            bookId: bookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: initialDetailUrl,
            sourceName: sourceName,
            sourceUrl: ext?.sourceUrl ?? "",
            extensionPackageId: extensionPackageId,
            currentChapterIndex: 0,
            currentChapterTitle: onlineChapters.first?.name ?? "",
            isOnShelf: true,
            isHistory: false
        )
        modelContext.insert(newBook)
        updateLocalChapters(for: newBook, with: onlineChapters)
        try? modelContext.save()
    }
    
    private func loadAllRemainingPages() async throws -> [ChapterResult] {
        guard let ext = ext else { return [] }
        var allChapters: [ChapterResult] = []
        let remainingPages = Array(tocPages.dropFirst())
        for pageUrl in remainingPages {
            let pageChaps = try await ExtensionManager.shared.toc(
                localPath: ext.localPath,
                downloadUrl: ext.downloadUrl,
                url: pageUrl,
                configJson: ext.configJson
            )
            allChapters.append(contentsOf: pageChaps)
        }
        return allChapters
    }
    
    private func loadMoreChapters() {
        guard !isLoadingRemainingPages else { return }
        isLoadingRemainingPages = true
        errorMessage = ""
        
        Task {
            do {
                let remainingChaps = try await loadAllRemainingPages()
                await MainActor.run {
                    self.onlineChapters.append(contentsOf: remainingChaps)
                    
                    if let book = localBook {
                        let startIdx = book.chapters.count
                        for (index, item) in remainingChaps.enumerated() {
                            let chapId = "\(bookId)_\(item.url)"
                            let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx + index)
                            newChap.book = book
                            modelContext.insert(newChap)
                        }
                        try? modelContext.save()
                    }
                    
                    self.remainingPagesLoaded = true
                    self.isLoadingRemainingPages = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Lỗi tải thêm chương: \(error.localizedDescription)"
                    self.isLoadingRemainingPages = false
                }
            }
        }
    }
    
    private func startReading() {
        if tocPages.count > 1 && !remainingPagesLoaded {
            isLoadingRemainingPages = true
            errorMessage = ""
            
            Task {
                do {
                    let remainingChaps = try await loadAllRemainingPages()
                    await MainActor.run {
                        self.onlineChapters.append(contentsOf: remainingChaps)
                        
                        if let book = localBook {
                            let startIdx = book.chapters.count
                            for (index, item) in remainingChaps.enumerated() {
                                let chapId = "\(bookId)_\(item.url)"
                                let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: startIdx + index)
                                newChap.book = book
                                modelContext.insert(newChap)
                            }
                            try? modelContext.save()
                        }
                        
                        self.remainingPagesLoaded = true
                        self.isLoadingRemainingPages = false
                        self.navigateToReader = true
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Lỗi tải thêm chương: \(error.localizedDescription)"
                        self.isLoadingRemainingPages = false
                        self.navigateToReader = true
                    }
                }
            }
        } else {
            self.navigateToReader = true
        }
    }
    
    private func removeFromShelf(_ book: Book) {
        if book.isHistory {
            book.isOnShelf = false
            try? modelContext.save()
        } else {
            modelContext.delete(book)
            try? modelContext.save()
        }
    }
    
    private func updateLocalChapters(for book: Book, with results: [ChapterResult]) {
        // Xóa chương cũ
        book.chapters.removeAll()
        
        // Thêm chương mới
        for (index, item) in results.enumerated() {
            let chapId = "\(book.bookId)_\(item.url)"
            let newChap = Chapter(id: chapId, title: item.name, url: item.url, index: index)
            newChap.book = book
            modelContext.insert(newChap)
        }
    }
    
    private func reloadBookData() async {
        guard let ext = ext else { return }
        guard !ext.localPath.isEmpty else { return }
        
        do {
            let path = ext.localPath
            let detailResult = try await ExtensionManager.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
            
            var allChapters: [ChapterResult] = []
            if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
                let pages = try await ExtensionManager.shared.page(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                await MainActor.run {
                    self.tocPages = pages
                }
                
                for pageUrl in pages {
                    let pageChaps = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: pageUrl, configJson: ext.configJson)
                    allChapters.append(contentsOf: pageChaps)
                }
                await MainActor.run {
                    self.remainingPagesLoaded = true
                }
            } else {
                let tocResult = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                allChapters = tocResult
            }
            
            await MainActor.run {
                self.title = detailResult.name
                self.author = detailResult.author
                self.coverUrl = detailResult.cover
                self.desc = detailResult.description.cleanHTML()
                self.detail = detailResult.detail
                self.onlineChapters = allChapters
                
                if let book = localBook {
                    book.title = detailResult.name
                    book.author = detailResult.author
                    book.coverUrl = detailResult.cover
                    let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                    book.desc = savedDesc
                    
                    updateLocalChapters(for: book, with: allChapters)
                    try? modelContext.save()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
