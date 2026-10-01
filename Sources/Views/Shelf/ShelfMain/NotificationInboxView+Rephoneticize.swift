import SwiftUI

/// Khối **"Phiên âm lại từ điển"** của `NotificationInboxView` — hai card, mỗi từ điển một card.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là extension **cùng file type** nên vẫn
/// dùng được `@ObservedObject rephoneticizeNghi` / `rephoneticizeVieNeu` khai ở file chính, và `timeLabel(_:)`
/// (đã bỏ `private` chính vì lý do này).
///
/// ## Không chạm đĩa trong `body`
/// Mọi con số ở đây đến từ `@Published` **đã nằm trong RAM** của `RephoneticizeTask` (`phase`, `meta`,
/// `lastOutcome`, `runningProgress`, `statusText`, `displayDate`). Không parse plist, không đếm lại từ file —
/// đó là điều kiện để mở màn Thông báo sau khi khởi động lại không bị đơ (bài học 1.3.448 với
/// `VietPhraseMerged.txt`).
///
/// ## Bố cục
/// Giống khối gộp VietPhrase: icon (nhấp nháy khi chạy) + tiêu đề + giờ, một dòng trạng thái, thanh tiến độ
/// khi đang chạy, chip số liệu khi có kết quả, rồi nút chính full-width **Nhập vào từ điển**, hàng dưới
/// **Xuất file** / **Bỏ qua**.
extension NotificationInboxView {

    /// Chỉ vẽ card của từ điển **thật sự** đang chạy / có kết quả / vừa lỗi (`isVisible`). Từ điển chưa
    /// phiên âm lại thì không có gì để báo ⇒ **không** hiện card, tránh một dòng "Chưa phiên âm lại" vô
    /// nghĩa chiếm chỗ ở màn Thông báo.
    @ViewBuilder
    func rephoneticizeRow() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if rephoneticizeNghi.isVisible {
                RephoneticizeCard(task: rephoneticizeNghi, timeText: timeLabel(rephoneticizeNghi.displayDate))
            }
            if rephoneticizeVieNeu.isVisible {
                RephoneticizeCard(task: rephoneticizeVieNeu, timeText: timeLabel(rephoneticizeVieNeu.displayDate))
            }
        }
        .padding(.vertical, 4)
    }

    /// Card theo dõi **một** lượt "Phiên âm lại" cho **một** từ điển.
    ///
    /// Là `View` khai **lồng** trong extension (không phải type top-level thứ hai của file) vì mỗi card cần
    /// `@State` riêng: Swift **không** cho khai `@State` trong extension, và nhét thêm 4 `@State` vào
    /// `NotificationInboxView` sẽ đẩy file đó vượt trần 400 dòng.
    @MainActor
    struct RephoneticizeCard: View {
        @ObservedObject var task: RephoneticizeTask
        /// Giờ đã định dạng sẵn — `timeLabel` là hàm của `NotificationInboxView` nên truyền vào thay vì
        /// chép lại `DateFormatter` ở đây.
        let timeText: String

        /// Khai `init` tường minh: `@ObservedObject` phải bọc tay và `init` này được gọi từ file chính.
        init(task: RephoneticizeTask, timeText: String) {
            self._task = ObservedObject(wrappedValue: task)
            self.timeText = timeText
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                icon.frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(task.statusText)
                        .font(.footnote)
                        .foregroundStyle(task.isFailed ? Color.red : Color.secondary)

                    if let progress = task.runningProgress {
                        ProgressView(value: progress)
                        Text("Chạy ngầm · chưa ghi gì lên đĩa")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if task.hasResult {
                        counts
                        actions
                    } else if task.isFailed {
                        failureActions
                    }
                }
            }
        }

        /// Icon nhấp nháy khi đang chạy — `symbolEffect(.pulse)` (iOS 17) để hệ thống lo hiệu ứng, không tốn
        /// vòng lặp vẽ nào.
        @ViewBuilder
        private var icon: some View {
            if task.isRunning {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.teal)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating)
            } else if task.hasResult {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(Color.teal)
                    .font(.title3)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.title3)
            }
        }

        /// Chip số liệu, chia hai hàng vì bốn nhãn không vừa một hàng trên máy hẹp.
        @ViewBuilder
        private var counts: some View {
            if let summary = task.summaryCounts {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        countChip("tổng", summary.total)
                        countChip("đổi", summary.changed)
                    }
                    HStack(spacing: 8) {
                        countChip("giữ nguyên", summary.kept)
                        countChip("gộp khoá", summary.merged)
                    }
                }
            } else if task.isMetaMissing {
                // Có file kết quả nhưng thiếu meta (bị xoá tay, hoặc từ bản app khác). **Không** đọc lại plist
                // để đếm — chính là thứ từng làm đơ app.
                Text("Số liệu chưa có — chạy lại để cập nhật.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(task.resultRecordCount) mục")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private func countChip(_ label: String, _ value: Int) -> some View {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                Capsule().stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
            )
        }

        private var actions: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Cùng nút với banner màn từ điển ⇒ cùng một định nghĩa *Trộn* / *Thay thế toàn bộ*.
                RephoneticizeApplyButton(task: task) {}

                HStack(spacing: 8) {
                    if let url = task.resultFileURL {
                        ShareLink(item: url) {
                            Text("Xuất file").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        task.discardResult()
                    } label: {
                        Text("Bỏ qua").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }

        private var failureActions: some View {
            HStack(spacing: 8) {
                Button("Thử lại") { task.start() }
                    .buttonStyle(.bordered)
                Button("Bỏ qua", role: .destructive) { task.discardResult() }
                    .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
    }
}
