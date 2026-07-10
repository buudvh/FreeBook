import SwiftUI
import SwiftData

struct DownloadTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    @State private var showingOptionsSheet = false
    @State private var selectedBookForTask: Book? = nil
    @State private var selectedTaskType: TaskType = .download
    @State private var defaultOnlyExportCached = false
    
    var body: some View {
        VStack(spacing: 0) {
            if downloadManager.tasks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "icloud.and.arrow.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.secondary)
                    
                    Text("Không có tác vụ nào")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Các tác vụ tải truyện đọc offline và xuất ebook file TXT chạy nền sẽ hiển thị ở đây.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(downloadManager.tasks) { task in
                        taskRow(task)
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            if !downloadManager.tasks.isEmpty {
                Button("Dọn dẹp") {
                    downloadManager.clearFinishedTasks()
                }
                .foregroundColor(.blue)
            }
        }
        .sheet(isPresented: $showingOptionsSheet) {
            if let book = selectedBookForTask {
                TaskOptionsSheet(book: book, taskType: selectedTaskType, defaultOnlyExportCached: defaultOnlyExportCached)
            }
        }
    }
    
    @ViewBuilder
    private func taskRow(_ task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            BookCoverView(bookId: task.bookId, coverUrl: task.bookCoverUrl, width: 44, height: 60)
                .cornerRadius(4)
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.bookTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(task.taskType.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(task.taskType == .download ? Color.green : Color.orange)
                        .cornerRadius(4)
                    
                    statusBadge(task.status)
                }
                
                if task.status == .running || task.status == .pending {
                    VStack(alignment: .leading, spacing: 2) {
                        ProgressView(value: Double(task.progressCount), total: Double(max(1, task.totalCount)))
                            .tint(.blue)
                            .scaleEffect(x: 1, y: 0.8, anchor: .center)
                        
                        Text("Tiến độ: \(task.progressCount)/\(task.totalCount) chương")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                } else if task.status == .completed {
                    Text("Đã xử lý \(task.progressCount) chương thành công")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if task.status == .failed, let error = task.errorMessage {
                    Text("Lỗi: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if task.status == .running || task.status == .pending {
                Button(action: {
                    downloadManager.cancelTask(taskId: task.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if task.status == .completed && task.taskType == .download {
                Button {
                    exportFromCached(task)
                } label: {
                    Label("Xuất ebook từ truyện đã tải", systemImage: "square.and.arrow.up")
                }
            }
            
            Button(role: .destructive) {
                if let idx = downloadManager.tasks.firstIndex(where: { $0.id == task.id }) {
                    downloadManager.tasks.remove(at: idx)
                }
            } label: {
                Label("Xóa khỏi danh sách", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        let color: Color
        switch status {
        case .pending: color = .gray
        case .running: color = .blue
        case .completed: color = .green
        case .failed: color = .red
        case .cancelled: color = .orange
        }
        
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
    
    private func exportFromCached(_ task: DownloadTask) {
        let allBooks = (try? modelContext.fetch(FetchDescriptor<Book>())) ?? []
        if let book = allBooks.first(where: { $0.bookId == task.bookId }) {
            self.selectedBookForTask = book
            self.selectedTaskType = .exportTxt
            self.defaultOnlyExportCached = true
            self.showingOptionsSheet = true
        }
    }
}
