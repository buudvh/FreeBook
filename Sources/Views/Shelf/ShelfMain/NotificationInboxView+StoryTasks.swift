import SwiftUI

/// Phần **truyện** của khối "Đang chạy" trong `NotificationInboxView`: lượt nhập truyện từ file
/// (`BookImportProgressCenter`) và các tác vụ tải / xuất ebook (`DownloadManager.tasks`).
///
/// ## Chỉ hiện việc chưa xong — khác hàng sao lưu và tải model
/// Hai hàng kia ở lại sau khi xong, chờ nút "Bỏ qua". Hàng ở đây thì biến mất ngay khi tác vụ tới trạng
/// thái cuối, vì:
/// - `DownloadTaskModel` sống qua khởi động lại, nên giữ dòng đã xong là phải thêm bộ nhớ "đã bỏ qua" riêng;
///   không có nó thì mỗi lần mở app cả lịch sử tải cũ lại hiện về.
/// - Kết quả ("Đã xong" / "Lỗi" / "Đã hủy" / "Đã nhập thành công") đã có toast, và toast tự ghi vào nhật ký
///   của chính màn này. Chia sẻ lại file xuất hay thử lại tác vụ lỗi vẫn ở tab Tải.
///
/// Tác vụ **đang chờ** gộp thành một dòng đếm: xếp hàng tải cả loạt truyện không được kéo dài màn ra hàng
/// chục dòng.
///
/// ## Struct riêng, observe riêng
/// `DownloadManager.tasks` phát tới ~10 lần/giây khi đang tải. Tách thành `StoryActivityRows` để chỉ khối
/// này vẽ lại theo nhịp đó, không kéo hàng sao lưu / tải model (và cả `NotificationInboxView`) theo. Struct
/// lồng trong extension để không thành type chính thứ hai của file (luật `MULTI_PRIMARY_TYPES`).
extension NotificationInboxView {

    struct StoryActivityRows: View {
        @ObservedObject private var imports = BookImportProgressCenter.shared
        @ObservedObject private var storyTasks = DownloadManager.shared

        var body: some View {
            if let entry = imports.entry {
                BookImportActivityRow(entry: entry)
            }

            ForEach(storyTasks.tasks.filter { $0.status == .running }) { task in
                StoryTaskActivityRow(task: task) {
                    storyTasks.cancelTask(taskId: task.id)
                }
            }

            let pendingCount = storyTasks.tasks.filter { $0.status == .pending }.count
            if pendingCount > 0 {
                PendingStoryTasksRow(count: pendingCount)
            }
        }
    }

    /// Lượt nhập truyện đang ghi vào CSDL. Không có nút huỷ: luồng nhập không nhận cancellation.
    struct BookImportActivityRow: View {
        let entry: BookImportProgressCenter.Entry

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(Color.blue)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Nhập truyện · \(entry.message)")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)

                    ProgressView(value: entry.fraction)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Một tác vụ tải truyện hoặc xuất ebook đang chạy.
    struct StoryTaskActivityRow: View {
        let task: DownloadTask
        let onCancel: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                icon.frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    // Dịch tên giống toast kết quả của `DownloadManager`, để hai dòng nói cùng một tên.
                    Text(TranslateUtils.translateBookTitleIfNeeded(task.bookTitle, bookId: task.bookId))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)

                    ProgressView(value: fraction)

                    // Tác vụ video: tập đang tải ("Tập 4: 45% · 210 MB") và danh sách từng tập như tab Tải.
                    if let mediaDetail = task.mediaDetail {
                        Text(mediaDetail)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                    }
                    if !task.videoEpisodes.isEmpty {
                        VideoEpisodeProgressList(episodes: task.videoEpisodes)
                    }
                }

                Spacer(minLength: 0)

                Button(role: .destructive, action: onCancel) {
                    Text("Huỷ")
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
            .padding(.vertical, 2)
        }

        /// `nil` khi chưa biết tổng số chương (mục lục chưa nạp xong) ⇒ thanh chạy vô định. Video chạy mượt theo phần
        /// trăm của tập đang tải (`DownloadTask.smoothProgressCount`).
        private var fraction: Double? {
            guard task.totalCount > 0 else { return nil }
            return min(1, task.smoothProgressCount / Double(task.totalCount))
        }

        /// "Tải truyện · 12/300 chương" / "Tải video · 3/10 tập · 34%"; tác vụ xuất nối thêm giai đoạn ("Đang tạo
        /// file") khi đã có.
        private var detail: String {
            var parts = [task.displayTypeName]
            if task.totalCount > 0 {
                parts.append("\(task.progressCount)/\(task.totalCount) \(task.unitNoun)")
            }
            if let percent = task.videoProgressPercent {
                parts.append("\(percent)%")
            }
            if let stage = task.exportStage {
                parts.append(stage.displayName)
            }
            return parts.joined(separator: " · ")
        }

        /// Màu theo nhãn loại tác vụ ở tab Tải: tải xanh lá, xuất cam.
        @ViewBuilder
        private var icon: some View {
            if task.taskType.isExport {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Color.orange)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating)
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color.green)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
    }

    /// Một dòng đếm cho mọi tác vụ tải/xuất đang xếp hàng.
    struct PendingStoryTasksRow: View {
        let count: Int

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .foregroundStyle(Color.secondary)
                    .font(.title3)
                    .frame(width: 28)

                Text("\(count) tác vụ tải/xuất đang chờ")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}
