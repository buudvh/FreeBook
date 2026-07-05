import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    
    @State private var selectedTab = 0 // 0: Kệ Sách, 1: Lịch Sử
    @State private var showingClearHistoryAlert = false
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    
    @State private var shelfLimit = 50
    @State private var historyLimit = 50
    
    private var shelfBooks: [Book] {
        allBooks.filter { $0.isOnShelf }
    }
    
    private var historyBooks: [Book] {
        allBooks.filter { $0.isHistory }
    }
    
    private var displayedShelfBooks: [Book] {
        Array(shelfBooks.prefix(shelfLimit))
    }
    
    private var displayedHistoryBooks: [Book] {
        Array(historyBooks.prefix(historyLimit))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control to switch tabs
                Picker("Phân loại", selection: $selectedTab) {
                    Text("Kệ Sách").tag(0)
                    Text("Lịch Sử").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                Divider()
                
                Group {
                    if selectedTab == 0 {
                        // TAB KỆ SÁCH
                        if shelfBooks.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "books.vertical")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.secondary)
                                
                                Text("Kệ sách của bạn đang trống")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Đi tới phần Tìm Kiếm hoặc Khám Phá để thêm các truyện yêu thích vào kệ sách.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(displayedShelfBooks) { book in
                                    NavigationLink(destination: ReaderView(
                                        bookId: book.bookId,
                                        extensionPackageId: book.extensionPackageId,
                                        chapterIndex: book.currentChapterIndex,
                                        onlineChapters: [],
                                        bookTitle: nil,
                                        bookAuthor: nil,
                                        bookCoverUrl: nil,
                                        bookDesc: nil,
                                        bookDetailUrl: book.detailUrl,
                                        bookSourceName: book.sourceName
                                    )) {
                                        bookItemView(book)
                                    }
                                    .contextMenu {
                                        NavigationLink(destination: BookDetailView(
                                            bookId: book.bookId,
                                            extensionPackageId: book.extensionPackageId,
                                            initialDetailUrl: book.detailUrl,
                                            sourceName: book.sourceName
                                        )) {
                                            Label("Xem chi tiết", systemImage: "info.circle")
                                        }
                                        
                                        Button(role: .destructive) {
                                            removeFromShelf(book)
                                        } label: {
                                            Label("Xóa khỏi kệ sách", systemImage: "bookmark.slash")
                                        }
                                    }
                                }
                                
                                if shelfBooks.count > shelfLimit {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .onAppear {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    shelfLimit += 50
                                                }
                                            }
                                        Spacer()
                                    }
                                    .listRowSeparator(.hidden)
                                }
                            }
                            .listStyle(.plain)
                        }
                    } else {
                        // TAB LỊCH SỬ
                        if historyBooks.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.secondary)
                                
                                Text("Lịch sử đọc trống")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Text("Lịch sử sẽ tự động ghi nhớ sau khi bạn bắt đầu đọc một chương truyện.")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(displayedHistoryBooks) { book in
                                    NavigationLink(destination: ReaderView(
                                        bookId: book.bookId,
                                        extensionPackageId: book.extensionPackageId,
                                        chapterIndex: book.currentChapterIndex,
                                        onlineChapters: [],
                                        bookTitle: nil,
                                        bookAuthor: nil,
                                        bookCoverUrl: nil,
                                        bookDesc: nil,
                                        bookDetailUrl: book.detailUrl,
                                        bookSourceName: book.sourceName
                                    )) {
                                        bookItemView(book)
                                    }
                                    .contextMenu {
                                        NavigationLink(destination: BookDetailView(
                                            bookId: book.bookId,
                                            extensionPackageId: book.extensionPackageId,
                                            initialDetailUrl: book.detailUrl,
                                            sourceName: book.sourceName
                                        )) {
                                            Label("Xem chi tiết", systemImage: "info.circle")
                                        }
                                        
                                        Button(role: .destructive) {
                                            removeFromHistory(book)
                                        } label: {
                                            Label("Xóa lịch sử", systemImage: "clock.badge.xmark")
                                        }
                                    }
                                }
                                
                                if historyBooks.count > historyLimit {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .onAppear {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    historyLimit += 50
                                                }
                                            }
                                        Spacer()
                                    }
                                    .listRowSeparator(.hidden)
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "Kệ Sách" : "Lịch Sử Đọc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: {
                        isTranslationEnabled.toggle()
                    }) {
                        Image(systemName: isTranslationEnabled ? "character.bubble.fill" : "character.bubble")
                    }
                    
                    if selectedTab == 1 && !historyBooks.isEmpty {
                        Button(action: {
                            showingClearHistoryAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Xóa tất cả lịch sử", isPresented: $showingClearHistoryAlert) {
                Button("Xóa tất cả", role: .destructive) {
                    clearAllHistory()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Bạn có chắc chắn muốn xóa toàn bộ lịch sử đọc không? Sách trong kệ sách sẽ không bị ảnh hưởng.")
            }
            .onChange(of: selectedTab) { _, _ in
                shelfLimit = 50
                historyLimit = 50
            }
        }
    }
    
    @ViewBuilder
    private func bookItemView(_ book: Book) -> some View {
        HStack(spacing: 12) {
            if !book.coverUrl.isEmpty, let url = URL(string: book.coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 50, height: 70)
                .cornerRadius(4)
                .clipped()
            } else {
                Color.gray.opacity(0.2)
                    .frame(width: 50, height: 70)
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(translateIfNeeded(book.title))
                    .font(.headline)
                    .lineLimit(1)
                
                if !book.author.isEmpty {
                    Text(translateIfNeeded(book.author))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if selectedTab == 1 {
                    let chapterTitle = book.displayChapterTitle
                    if !chapterTitle.isEmpty {
                        Text("Đã đọc: \(translateIfNeeded(chapterTitle))")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
    }
    
    private func translateIfNeeded(_ text: String) -> String {
        guard isTranslationEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text)
    }
    
    private func removeFromShelf(_ book: Book) {
        if book.isHistory {
            book.isOnShelf = false
        } else {
            modelContext.delete(book)
        }
        try? modelContext.save()
    }
    
    private func removeFromHistory(_ book: Book) {
        if book.isOnShelf {
            book.isHistory = false
        } else {
            modelContext.delete(book)
        }
        try? modelContext.save()
    }
    
    private func clearAllHistory() {
        for book in historyBooks {
            if book.isOnShelf {
                book.isHistory = false
            } else {
                modelContext.delete(book)
            }
        }
        try? modelContext.save()
    }
}

#Preview {
    ShelfView()
}
