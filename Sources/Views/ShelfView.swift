import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.lastReadDate, order: .reverse) private var books: [Book]
    
    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
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
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(books) { book in
                                NavigationLink(destination: BookDetailView(bookId: book.bookId, extensionPackageId: book.extensionPackageId, initialDetailUrl: book.detailUrl, sourceName: book.sourceName)) {
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
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteBook(book)
                                    } label: {
                                        Label("Xóa khỏi kệ sách", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Kệ Sách")
        }
    }
    
    private func deleteBook(_ book: Book) {
        modelContext.delete(book)
        try? modelContext.save()
    }
}

#Preview {
    ShelfView()
}
