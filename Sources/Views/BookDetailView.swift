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
    
    // Tìm sách local trong database
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
    }
    
    // Tìm extension cục bộ để chạy script
    private var ext: Extension? {
        allExtensions.first(where: { $0.packageId == extensionPackageId })
    }
    
    private func cleanDetailText(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<p>", with: "")
            .replacingOccurrences(of: "</p>", with: "\n")
        
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) {
            let range = NSRange(location: 0, length: text.utf16.count)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var cleanedDetailText: String {
        cleanDetailText(detail)
    }
    
    var body: some View {
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
                            AsyncImage(url: URL(string: coverUrl)) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                                    .overlay(Image(systemName: "book"))
                            }
                            .frame(width: 100, height: 140)
                            .cornerRadius(8)
                            .shadow(radius: 2)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(title)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(3)
                                
                                Text("Tác giả: \(author)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("Nguồn: \(sourceName)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(6)
                                
                                if !detail.isEmpty {
                                    Text(cleanedDetailText)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(4)
                                }
                                
                                Spacer()
                                
                                // Nút Thêm Kệ Sách / Bắt đầu đọc
                                HStack {
                                    if let book = localBook {
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
                                        NavigationLink(destination: ReaderView(
                                            bookId: bookId,
                                            extensionPackageId: extensionPackageId,
                                            chapterIndex: activeChapterIndex,
                                            onlineChapters: localBook == nil ? onlineChapters : []
                                        )) {
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
                                            NavigationLink(destination: ReaderView(
                                                bookId: bookId,
                                                extensionPackageId: extensionPackageId,
                                                chapterIndex: chap.index,
                                                onlineChapters: []
                                            )) {
                                                HStack {
                                                    Text(chap.title)
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
                                            NavigationLink(destination: ReaderView(
                                                bookId: bookId,
                                                extensionPackageId: extensionPackageId,
                                                chapterIndex: index,
                                                onlineChapters: onlineChapters
                                            )) {
                                                VStack(alignment: .leading) {
                                                    Text(chap.name)
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
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Chi Tiết Truyện")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBookData()
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
                self.isLoading = false
                return
            }
        }
        
        guard let ext = ext else {
            errorMessage = "Không tìm thấy tiện ích bóc tách của truyện này!"
            isLoading = false
            return
        }
        
        guard !ext.localPath.isEmpty else {
            errorMessage = "Vui lòng cài đặt tiện ích '\(ext.name)' trong phần Tiện Ích trước khi bóc tách nguồn này!"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let path = ext.localPath
                // Chạy chi tiết truyện
                let detailResult = try await ExtensionManager.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                // Chạy mục lục chương
                let tocResult = try await ExtensionManager.shared.toc(localPath: path, downloadUrl: ext.downloadUrl, url: initialDetailUrl, configJson: ext.configJson)
                
                await MainActor.run {
                    self.title = detailResult.name
                    self.author = detailResult.author
                    self.coverUrl = detailResult.cover
                    self.desc = detailResult.description
                    self.detail = detailResult.detail
                    self.onlineChapters = tocResult
                    
                    // Nếu sách đã ở local nhưng rỗng chương (hoặc cần update), cập nhật lại
                    if let book = localBook {
                        book.title = detailResult.name
                        book.author = detailResult.author
                        book.coverUrl = detailResult.cover
                        let savedDesc = detailResult.detail.isEmpty ? detailResult.description : "\(detailResult.description)\n\n---\n\(self.cleanDetailText(detailResult.detail))"
                        book.desc = savedDesc
                        
                        // Cập nhật chương
                        updateLocalChapters(for: book, with: tocResult)
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
        let newBook = Book(
            bookId: bookId,
            title: title,
            author: author,
            coverUrl: coverUrl,
            desc: savedDesc,
            detailUrl: initialDetailUrl,
            sourceName: sourceName,
            sourceUrl: ext?.sourceUrl ?? "",
            extensionPackageId: extensionPackageId
        )
        
        modelContext.insert(newBook)
        updateLocalChapters(for: newBook, with: onlineChapters)
        try? modelContext.save()
    }
    
    private func removeFromShelf(_ book: Book) {
        modelContext.delete(book)
        try? modelContext.save()
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
}
