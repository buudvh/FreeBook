import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var allBooks: [Book]
    
    @State private var selectedTab = 0 // 0: Kệ Sách, 1: Lịch Sử
    @State private var showingClearHistoryAlert = false
    
    private var shelfBooks: [Book] {
        allBooks.filter { $0.isOnShelf }
    }
    
    private var historyBooks: [Book] {
        allBooks.filter { $0.isHistory }
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
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(shelfBooks) { book in
                                        NavigationLink(destination: ReaderView(
                                            bookId: book.bookId,
                                            extensionPackageId: book.extensionPackageId,
                                            chapterIndex: book.currentChapterIndex,
                                            onlineChapters: [],
                                            bookTitle: nil,
                                            bookAuthor: nil,
                                            bookCoverUrl: nil,
                                            bookDesc: nil,
                                            bookDetailUrl: nil,
                                            bookSourceName: nil
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
                                }
                                .padding(16)
                            }
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
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(historyBooks) { book in
                                        NavigationLink(destination: ReaderView(
                                            bookId: book.bookId,
                                            extensionPackageId: book.extensionPackageId,
                                            chapterIndex: book.currentChapterIndex,
                                            onlineChapters: [],
                                            bookTitle: nil,
                                            bookAuthor: nil,
                                            bookCoverUrl: nil,
                                            bookDesc: nil,
                                            bookDetailUrl: nil,
                                            bookSourceName: nil
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
                                }
                                .padding(16)
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "Kệ Sách" : "Lịch Sử Đọc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == 1 && !historyBooks.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
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
        }
    }
    
    @ViewBuilder
    private func bookItemView(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Ảnh bìa truyện
            AsyncImage(url: URL(string: book.coverUrl)) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
                    .overlay(
                        Image(systemName: "book.closed")
                            .foregroundColor(.gray)
                    )
            }
            .frame(height: 150)
            .cornerRadius(8)
            .shadow(radius: 2)
            
            // Tên truyện
            Text(book.title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Tiến độ đọc
            if book.chapters.isEmpty {
                Text("Chưa tải chương")
                    .font(.caption2)
                    .foregroundColor(.gray)
            } else {
                let currentChapIndex = min(book.currentChapterIndex, book.chapters.count - 1)
                let chapterTitle = currentChapIndex >= 0 ? book.chapters[currentChapIndex].title : "Chưa đọc"
                Text("Đang đọc: \(chapterTitle)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
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
            removeFromHistory(book)
        }
    }
}

#Preview {
    ShelfView()
}
