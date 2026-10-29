import SwiftUI
import SwiftData

struct DownloadTrackerView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    @State private var selectedBookForTask: Book? = nil
    @State private var selectedTaskType: TaskType = .download
    @State private var defaultOnlyExportCached = false
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    /// Công tắc NSFW toàn app — tắt ⇒ ẩn tác vụ tải/xuất của truyện thuộc nguồn NSFW hoặc tự đánh dấu NSFW (tác vụ vẫn
    /// chạy).
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    private var visibleTasks: [DownloadTask] {
        RepositoryFilterPolicy.excludingNsfwBooks(
            downloadManager.tasks,
            includeNsfw: includeNsfw,
            bookId: \.bookId,
            packageId: \.extensionPackageId
        )
    }

    var body: some View {
        let tasks = visibleTasks
        VStack(spacing: 0) {
            if tasks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "icloud.and.arrow.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(.secondary)
                    
                    Text("Không có tác vụ nào")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Các tác vụ tải truyện đọc offline, xuất ebook (TXT, EPUB, FB2, MOBI), truyện tranh (CBZ, PDF) và video chạy nền sẽ hiển thị ở đây.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $selectedBookForTask) { book in
            TaskOptionsSheet(book: book, taskType: selectedTaskType, defaultOnlyExportCached: defaultOnlyExportCached)
        }
    }
    
    @ViewBuilder
    private func taskRow(_ task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            // Match the shelf/history book-row proportions so a task still looks
            // like the same book wherever it is shown.
            BookCoverView(bookId: task.bookId, coverUrl: task.bookCoverUrl, width: 50, height: 70, extensionPackageId: task.extensionPackageId)
                .cornerRadius(4)
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 4) {
                let rawTitle = isTranslationEnabled && TranslateUtils.containsChinese(task.bookTitle)
                     ? TranslateUtils.translateMeta(task.bookTitle, bookId: task.bookId)
                     : task.bookTitle
                Text(DisplayTextFormatter.titleCase(rawTitle))
                    .font(.system(size: 14.5, weight: .semibold))
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(task.displayTypeName)
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
                        ProgressView(value: progressValue(task), total: Double(max(1, task.totalCount)))
                            .tint(.white)
                            .scaleEffect(x: 1, y: 0.8, anchor: .center)

                        Text(progressText(task))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Tác vụ video: phần trăm / dung lượng của tập đang tải (một tập có thể mất vài phút).
                        if let detail = task.mediaDetail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // Giai đoạn của tác vụ xuất: chương cuối chạy xong không còn là khoảng im lặng
                        // không giải thích được nữa (renderer đang đóng file / dựng mục lục).
                        if let stage = task.exportStage {
                            Text(stage.displayName)
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.top, 2)
                } else if task.status == .completed {
                    Text(task.isVideoDownload ? "Đã tải \(task.progressCount) tập" : "Đã xử lý \(task.progressCount) \(task.unitNoun) thành công")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Bản xuất thiếu chương phải nói rõ thiếu bao nhiêu, không im lặng báo "hoàn thành".
                    if let summary = task.exportSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else if task.status == .failed, let error = task.errorMessage {
                    Text("Lỗi: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }

                // Tác vụ video: phần trăm / trạng thái từng tập (một tập có thể mất vài phút).
                if !task.videoEpisodes.isEmpty {
                    VideoEpisodeProgressList(episodes: task.videoEpisodes)
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
            } else if task.status == .completed, let path = task.exportFilePath, FileManager.default.fileExists(atPath: path) {
                Button(action: {
                    downloadManager.shareExportedFile(taskId: task.id)
                }) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            } else if task.status == .failed || task.status == .cancelled {
                Button(action: {
                    downloadManager.retryTask(taskId: task.id)
                }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .resizable()
                        .frame(width: 22, height: 22)
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if task.status == .completed, let path = task.exportFilePath, FileManager.default.fileExists(atPath: path) {
                Button {
                    downloadManager.shareExportedFile(taskId: task.id)
                } label: {
                    Label("Chia sẻ lại file đã xuất", systemImage: "square.and.arrow.up")
                }
            }

            if task.status == .failed || task.status == .cancelled {
                Button {
                    downloadManager.retryTask(taskId: task.id)
                } label: {
                    Label("Tải lại tác vụ", systemImage: "arrow.clockwise")
                }
            }
            
            // Theo loại nguồn: truyện chữ ⇒ ebook, truyện tranh ⇒ CBZ/PDF từ ảnh đã tải, video ⇒ file phim từ tập đã tải.
            if task.status == .completed && task.taskType == .download,
               let title = exportFromCachedTitle(task) {
                Button {
                    exportFromCached(task)
                } label: {
                    Label(title, systemImage: "square.and.arrow.up")
                }
            }
            
            Button(role: .destructive) {
                downloadManager.deleteTask(taskId: task.id)
            } label: {
                Label("Xóa khỏi danh sách", systemImage: "trash")
            }
        }
    }
    
    /// Giá trị thanh tiến độ: số mục xong, cộng phần đã tải của tập video đang tải (`DownloadTask.smoothProgressCount`).
    private func progressValue(_ task: DownloadTask) -> Double {
        task.smoothProgressCount
    }

    /// "Tiến độ: 3/10 tập · 34%" với video; truyện giữ "Tiến độ: 3/10 chương".
    private func progressText(_ task: DownloadTask) -> String {
        let base = "Tiến độ: \(task.progressCount)/\(task.totalCount) \(task.unitNoun)"
        guard let percent = task.videoProgressPercent else { return base }
        return "\(base) · \(percent)%"
    }

    private func statusBadge(_ status: TaskStatus) -> some View {
        let color: Color
        switch status {
        case .pending: color = .gray
        case .running: color = .white
        case .completed: color = .green
        case .failed: color = .red
        case .cancelled: color = .orange
        }
        
        return Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
    
    private func exportFromCachedTitle(_ task: DownloadTask) -> String? {
        switch ExtensionContentKind.resolve(packageId: task.extensionPackageId) {
        case .video: return "Xuất video từ tập đã tải"
        case .comic: return "Xuất CBZ/PDF từ ảnh đã tải"
        case .text, .unsupported: return "Xuất ebook từ truyện đã tải"
        }
    }

    /// Mở sheet tuỳ chọn với "Chỉ xuất chương đã tải" bật sẵn.
    ///
    /// Từ 1.3.253 đường này **không** enqueue thẳng `.exportTxt` nữa: có 4 định dạng nên người dùng phải
    /// được chọn định dạng trước, và sheet tuỳ chọn cũng cho biết trước bản xuất offline thiếu bao nhiêu chương.
    private func exportFromCached(_ task: DownloadTask) {
        let allBooks = (try? modelContext.fetch(FetchDescriptor<Book>())) ?? []
        if let book = allBooks.first(where: { $0.bookId == task.bookId }) {
            selectedTaskType = .exportTxt
            defaultOnlyExportCached = true
            selectedBookForTask = book
        }
    }
}
