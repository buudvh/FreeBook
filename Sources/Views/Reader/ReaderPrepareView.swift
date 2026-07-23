import SwiftUI
import SwiftData

/// Màn hình chuẩn bị trước khi vào Reader
/// Hiển thị "Đang chuẩn bị..." khi load danh sách chương từ database
struct ReaderPrepareView: View {
    @Environment(\.chapterRepository) private var chapterRepository
    @Environment(\.modelContext) private var modelContext
    @Query private var allBooks: [Book]
    
    let bookId: String
    let extensionPackageId: String
    let initialChapterIndex: Int
    let bookDetailUrl: String?
    let bookSourceName: String?
    var initialParagraphIndex: Int? = nil
    
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var localChaptersCount = 0
    @State private var currentChapterTitle = ""
    
    @AppStorage("readerSelectedTheme") private var readerTheme: ReaderTheme = .dark
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    
    private var localBook: Book? {
        allBooks.first(where: { $0.bookId == bookId })
    }
    
    private var displayBookTitle: String {
        let title = localBook?.title ?? "FreeBook"
        let translated = isTranslationEnabled && TranslateUtils.containsChinese(title)
            ? TranslateUtils.translateMeta(title, bookId: bookId)
            : title
        return DisplayTextFormatter.titleCase(translated)
    }
    
    private var displayChapterTitle: String {
        guard !currentChapterTitle.isEmpty else {
            return "Chương \(initialChapterIndex + 1)"
        }
        let translated = isTranslationEnabled && TranslateUtils.containsChinese(currentChapterTitle)
            ? TranslateUtils.translateChapterTitle(currentChapterTitle, bookId: bookId)
            : currentChapterTitle
        return translated
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                preparingScreen
                    .onAppear {
                        loadChapterData()
                    }
            } else if !errorMessage.isEmpty {
                errorScreen
            } else {
                // ✅ Sau khi load xong → Navigate đến ReaderView
                NavigationLink(
                    destination: LazyView {
                        ReaderView(
                            bookId: bookId,
                            extensionPackageId: extensionPackageId,
                            chapterIndex: initialChapterIndex,
                            onlineChapters: [],
                            bookTitle: localBook?.title,
                            bookAuthor: localBook?.author,
                            bookCoverUrl: localBook?.coverUrl,
                            bookDesc: localBook?.desc,
                            bookDetailUrl: bookDetailUrl,
                            bookSourceName: bookSourceName,
                            initialParagraphIndex: initialParagraphIndex
                        )
                    },
                    isActive: .constant(true)
                ) {
                    EmptyView()
                }
            }
        }
        .navigationBarBackButtonHidden(isLoading)
        .toolbar(isLoading ? .hidden : .visible, for: .navigationBar)
    }
    
    @ViewBuilder
    private var preparingScreen: some View {
        ZStack(alignment: .topLeading) {
            readerTheme.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                ProgressView()
                    .tint(readerTheme.textColor)
                    .scaleEffect(1.4)
                
                VStack(spacing: 8) {
                    Text(displayBookTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(readerTheme.textColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    if !displayChapterTitle.isEmpty {
                        Text(displayChapterTitle)
                            .font(.headline)
                            .foregroundColor(readerTheme.textColor.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 24)
                
                Text("Đang chuẩn bị danh sách chương...")
                    .font(.subheadline)
                    .foregroundColor(readerTheme.textColor.opacity(0.6))
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Top-left back button
            Button(action: {
                // Navigation will handle back automatically
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(readerTheme.textColor)
                    .padding(12)
                    .background(Circle().fill(readerTheme.textColor.opacity(0.12)))
            }
            .padding(.leading, 16)
            .padding(.top, 16)
            .accessibilityLabel("Quay lại")
            .opacity(0) // ẩn nút back khi đang loading
        }
        .transition(.opacity)
    }
    
    @ViewBuilder
    private var errorScreen: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.red)
            
            Text("Có lỗi xảy ra")
                .font(.headline)
            
            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Thử lại") {
                isLoading = true
                errorMessage = ""
                loadChapterData()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(readerTheme.backgroundColor)
    }
    
    private func loadChapterData() {
        Task {
            do {
                // ✅ Load chapter count và current chapter title
                let count = try await chapterRepository.getTotalChaptersCount(bookId: bookId)
                
                await MainActor.run {
                    self.localChaptersCount = count
                }
                
                // ✅ Load chapter title nếu có
                if let chapter = try? await chapterRepository.getChapter(bookId: bookId, index: initialChapterIndex) {
                    await MainActor.run {
                        self.currentChapterTitle = chapter.title
                    }
                } else {
                    await MainActor.run {
                        self.currentChapterTitle = "Chương \(initialChapterIndex + 1)"
                    }
                }
                
                // ✅ Delay nhỏ để animation mượt hơn
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                await MainActor.run {
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Không thể tải thông tin chương: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
