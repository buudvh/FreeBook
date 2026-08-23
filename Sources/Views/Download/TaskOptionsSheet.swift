import SwiftUI
import SwiftData

struct TaskOptionsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let book: Book
    let taskType: TaskType

    @State private var startFromCurrentChapter = true
    @State private var limitOption: ChapterLimitOption = .all
    @State private var translateContent = false
    @State private var onlyExportCached = false
    @State private var displayInShelf = true
    /// Định dạng bản xuất. `taskType` chỉ quyết định đây là tác vụ tải hay xuất; định dạng do người dùng
    /// chọn ở sheet này và được ghi bền qua `BookExportFormat.taskType`.
    @State private var exportFormat: BookExportFormat = .txt
    /// Số chương đã có cache / tổng số chương — để người dùng biết trước bản xuất offline sẽ thiếu bao nhiêu.
    @State private var cachedChapterCount: Int? = nil
    @State private var totalChapterCount: Int? = nil
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    init(book: Book, taskType: TaskType, defaultOnlyExportCached: Bool = false) {
        self.book = book
        self.taskType = taskType
        self._onlyExportCached = State(initialValue: defaultOnlyExportCached)
        self._exportFormat = State(initialValue: taskType.exportFormat ?? .txt)
    }

    /// Tác vụ này có tạo file hay chỉ tải cache.
    private var isExport: Bool { taskType.isExport }

    /// Loại tác vụ thật sự được đưa vào hàng đợi — với tác vụ xuất, nó theo định dạng đang chọn.
    private var effectiveTaskType: TaskType {
        return isExport ? exportFormat.taskType : taskType
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        BookCoverView(bookId: book.bookId, coverUrl: book.coverUrl, width: 60, height: 84)
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayedBookTitle)
                                .font(.headline)
                                .lineLimit(2)
                            
                            if !displayedAuthor.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                    Text(displayedAuthor)
                                        .lineLimit(1)
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            }

                            Text("\(book.sourceName)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Thông tin truyện")
                }
                
                if isExport {
                    Section {
                        Picker("Định dạng", selection: $exportFormat) {
                            ForEach(BookExportFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("Định dạng bản xuất")
                    } footer: {
                        Text(exportFormat.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Toggle("Tải từ chương đang đọc", isOn: $startFromCurrentChapter)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                    Picker("Số lượng chương", selection: $limitOption) {
                        ForEach(ChapterLimitOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    if isExport {
                        Toggle("Chỉ xuất chương đã tải", isOn: $onlyExportCached)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                        Toggle("Dịch nội dung", isOn: $translateContent)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                        if let cachedPreview {
                            Text(cachedPreview)
                                .font(.caption)
                                .foregroundColor(onlyExportCached && (totalChapterCount ?? 0) > (cachedChapterCount ?? 0) ? .orange : .secondary)
                        }
                    }

                    Toggle("Hiển thị trong Kệ sách", isOn: $displayInShelf)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                } header: {
                    Text("Tùy chọn tác vụ")
                } footer: {
                    if isExport {
                        Text("Nếu bật 'Dịch nội dung', các chương sẽ được dịch tự động bằng Quick Translator trước khi ghi vào file.\nNếu bật 'Chỉ xuất chương đã tải', quá trình xuất sẽ chạy offline và chỉ lấy các chương đã có cache — bản xuất sẽ thiếu những chương chưa tải.\nTắt 'Hiển thị trong Kệ sách' để truyện nằm trong Lịch sử đọc.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Tải truyện offline sẽ chỉ tải nội dung gốc chưa dịch để lưu trữ và tối ưu tốc độ đọc.\nTắt 'Hiển thị trong Kệ sách' để truyện nằm trong Lịch sử đọc.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(effectiveTaskType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard isExport else { return }
                await loadCacheStats()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bắt đầu") {
                        startTask()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private var displayedBookTitle: String {
        let title = isTranslationEnabled && TranslateUtils.containsChinese(book.title)
            ? TranslateUtils.translateMeta(book.title, bookId: book.bookId)
            : book.title
        return DisplayTextFormatter.titleCase(title)
    }

    private var displayedAuthor: String {
        let author = isTranslationEnabled ? TranslateUtils.translateAuthorHanViet(book.author) : book.author
        return DisplayTextFormatter.titleCase(author)
    }

    /// Dòng xem trước "đã tải X/Y chương", `nil` khi chưa đọc được mục lục.
    private var cachedPreview: String? {
        guard let cached = cachedChapterCount, let total = totalChapterCount, total > 0 else { return nil }
        if cached >= total {
            return "Đã tải đủ \(total) chương — bản xuất sẽ không thiếu chương nào."
        }
        return "Đã tải \(cached)/\(total) chương — thiếu \(total - cached) chương."
    }

    /// Đếm chương đã cache từ `ChapterStore` (mục lục thật, không phải bảng SwiftData `Chapter`).
    private func loadCacheStats() async {
        guard let chapters = try? await ChapterStore.shared.fetchOrderedTOC(bookId: book.bookId) else { return }
        let cached = chapters.filter { $0.isCached && $0.length > 0 }.count
        await MainActor.run {
            self.totalChapterCount = chapters.count
            self.cachedChapterCount = cached
        }
    }

    private func startTask() {
        let placementResult = displayInShelf
            ? BookTransactionCoordinator.shared.setOnShelf(bookId: book.bookId, isOnShelf: true, in: modelContext)
            : BookTransactionCoordinator.shared.removeFromShelf(bookId: book.bookId, in: modelContext)
        if case .failure(let err) = placementResult {
            AppLogger.shared.log("❌ [TaskOptionsSheet] Lỗi cập nhật vị trí hiển thị truyện: \(err.localizedDescription)")
        }

        DownloadManager.shared.enqueueTask(
            book: book,
            taskType: effectiveTaskType,
            startFromCurrent: startFromCurrentChapter,
            limit: limitOption,
            translate: translateContent,
            onlyExportCached: onlyExportCached,
            container: modelContext.container
        )

        ToastManager.shared.show(message: "Đã thêm tác vụ '\(effectiveTaskType.rawValue)' vào hàng đợi.")
    }
}
