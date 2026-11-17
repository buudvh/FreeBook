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
                    // Chữ + tiến độ dùng chung với mục "Đang chạy" của sheet hub (`DownloadTask+ActivityText`).
                    Text(task.activityTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(task.activityDetail)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)

                    ProgressView(value: task.activityFraction)

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
