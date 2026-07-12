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
    
    init(book: Book, taskType: TaskType, defaultOnlyExportCached: Bool = false) {
        self.book = book
        self.taskType = taskType
        self._onlyExportCached = State(initialValue: defaultOnlyExportCached)
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
                            Text(book.title)
                                .font(.headline)
                                .lineLimit(2)
                            
                            Text("Tác giả: \(book.author)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Nguồn: \(book.sourceName)")
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
                
                Section {
                    Toggle("Tải từ chương đang đọc", isOn: $startFromCurrentChapter)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    
                    Picker("Số lượng chương", selection: $limitOption) {
                        ForEach(ChapterLimitOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if taskType == .exportTxt {
                        Toggle("Chỉ xuất chương đã tải", isOn: $onlyExportCached)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        
                        Toggle("Dịch nội dung", isOn: $translateContent)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    }
                } header: {
                    Text("Tùy chọn tác vụ")
                } footer: {
                    if taskType == .exportTxt {
                        Text("Nếu bật 'Dịch nội dung', các chương sẽ được dịch tự động bằng Quick Translator trước khi ghi vào file TXT.\nNếu bật 'Chỉ xuất chương đã tải', quá trình xuất sẽ chạy offline và chỉ lấy các chương đã có cache.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Tải truyện offline sẽ chỉ tải nội dung gốc chưa dịch để lưu trữ và tối ưu tốc độ đọc.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(taskType.rawValue)
            .navigationBarTitleDisplayMode(.inline)
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
    
    private func startTask() {
        DownloadManager.shared.enqueueTask(
            book: book,
            taskType: taskType,
            startFromCurrent: startFromCurrentChapter,
            limit: limitOption,
            translate: translateContent,
            onlyExportCached: onlyExportCached,
            container: modelContext.container
        )
        
        ToastManager.shared.show(message: "Đã thêm tác vụ '\(taskType.rawValue)' vào hàng đợi.")
    }
}
