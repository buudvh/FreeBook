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
    
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var chapterTitle = ""
    @State private var chapterContent = ""
    
    // Tùy chọn giao diện đọc (Novel)
    @AppStorage("readerFontSize") private var fontSize: Double = 18.0
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
            return (chap.title, chap.url)
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
                                
                                Text(chapterContent)
                                    .font(.system(size: fontSize))
                                    .lineSpacing(8)
                                    .foregroundColor(selectedTheme.textColor)
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
            ReaderSettingsView(fontSize: $fontSize, selectedTheme: $selectedTheme)
                .presentationDetents([.height(180)])
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
    
    private func loadChapterContent() {
        guard let info = currentChapterInfo else {
            errorMessage = "Lỗi xác định mục lục chương"
            return
        }
        
        isLoading = true
        errorMessage = ""
        chapterTitle = info.title
        
        // 1. Kiểm tra cache nếu là sách lưu local
        if let book = localBook {
            let sorted = book.chapters.sorted(by: { $0.index < $1.index })
            let chap = sorted[chapterIndex]
            
            // Cập nhật tiến độ đọc
            book.currentChapterIndex = chapterIndex
            book.lastReadDate = Date()
            try? modelContext.save()
            
            if chap.isCached, let content = chap.content, !content.isEmpty {
                self.chapterContent = content
                self.isLoading = false
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
                
                await MainActor.run {
                    self.chapterContent = content
                    
                    // Nếu là sách local, tự động lưu vào cache offline luôn
                    if let book = localBook {
                        let sorted = book.chapters.sorted(by: { $0.index < $1.index })
                        let chap = sorted[chapterIndex]
                        chap.content = content
                        chap.isCached = true
                        try? modelContext.save()
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
            
            Spacer()
        }
        .padding()
    }
}
