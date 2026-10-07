import SwiftUI

/// Khối **"Đang chạy"** của `NotificationInboxView`: tiến độ sao lưu/khôi phục và tiến độ tải model,
/// ghim ở **đầu danh sách** (ngoài nhóm theo ngày).
///
/// ## Vì sao ghim trên cùng, không nhập vào nhóm theo ngày
/// Hai card "Gộp VietPhrase" và "Phiên âm lại" nằm trong nhóm ngày vì chúng có **file kết quả trên đĩa**
/// và sống qua khởi động lại — chúng là *lịch sử*. Tiến độ sao lưu/khôi phục và tải model thì ngược lại:
/// chỉ tồn tại trong phiên (người dùng chốt 2026-10-07), nên gán cho chúng một mốc ngày giờ là nói sai
/// bản chất. Ghim ở đầu cũng tránh phải thêm case vào enum `InboxItem` — `NotificationInboxView.swift`
/// đang **393/400** dòng, thêm case là vượt trần.
///
/// ## Không chạm đĩa trong `body`
/// Mọi con số đến từ `@Published` **đã nằm trong RAM** (`BackupCoordinator.progress`,
/// `ModelDownloadCenter.entries`). Không đọc file, không đếm lại — cùng nguyên tắc đã trả giá ở 1.3.448.
///
/// ## Vì sao là extension + struct **lồng**
/// Trần "1 type chính / file" của `check_architecture.py`: khai `ActivityRows` ở top level file này là một
/// vi phạm mới. Struct lồng trong extension không bị tính (cùng khuôn `RephoneticizeCard`).
extension NotificationInboxView {

    /// Có gì để ghim không. Dùng cho `body` của file chính: màn Thông báo đang mở mà chỉ có tiến độ
    /// (không có chương mới, không có toast) thì vẫn phải hiện **danh sách**, không được hiện màn rỗng.
    ///
    /// **Không** `private`: gọi từ `NotificationInboxView.swift` — `private` của Swift giới hạn theo file.
    var hasActivity: Bool {
        BackupCoordinator.shared.progress.isInboxVisible
            || !ModelDownloadCenter.shared.entries.isEmpty
    }

    /// Hàng tiến độ ghim ở đầu danh sách. Trả về **rỗng** khi không có việc gì đang chạy hay vừa xong.
    @ViewBuilder
    func activityRows() -> some View {
        ActivityRows()
    }

    /// Quan sát hai singleton và vẽ hàng tương ứng. Tách thành struct riêng để **chỉ khối này** vẽ lại khi
    /// tiến độ nhích, thay vì kéo cả `NotificationInboxView` (đang `@Query` toàn bộ `Book`) vẽ lại theo.
    struct ActivityRows: View {
        @ObservedObject private var backup = BackupCoordinator.shared
        @ObservedObject private var downloads = ModelDownloadCenter.shared

        var body: some View {
            if backup.progress.isInboxVisible {
                BackupActivityRow(progress: backup.progress) {
                    backup.dismissProgress()
                }
            }

            ForEach(downloads.entries) { entry in
                DownloadActivityRow(entry: entry) {
                    downloads.dismiss(entry.id)
                }
            }
        }
    }

    /// Một lượt sao lưu **hoặc** khôi phục. Hai việc dùng chung `BackupCoordinator.progress` nên chung một
    /// hàng; nhãn phân biệt bằng `progress.isRestore`.
    struct BackupActivityRow: View {
        let progress: BackupProgress
        let onDismiss: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                icon.frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.isRestore ? "Khôi phục dữ liệu" : "Sao lưu dữ liệu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(progress.message)
                        .font(.footnote)
                        .foregroundStyle(isFailed ? Color.red : Color.secondary)
                        .lineLimit(2)

                    if progress.isActive {
                        ProgressView(value: progress.fraction)
                    } else {
                        ActivityDismissButton(action: onDismiss)
                    }
                }
            }
            .padding(.vertical, 2)
        }

        private var isFailed: Bool { progress.phase == .failed }

        /// Nhấp nháy khi đang chạy để hàng "sống"; `symbolEffect(.pulse)` do hệ thống lo, không tốn vòng
        /// lặp vẽ nào (iOS 17 — đúng deployment target của app).
        @ViewBuilder
        private var icon: some View {
            if progress.isActive {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.blue)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating)
            } else if isFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.title3)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                    .font(.title3)
            }
        }
    }

    /// Một lượt tải model: NghiTTS (mỗi giọng một hàng) hoặc VieNeu (model lõi / gói graph nhân bản).
    struct DownloadActivityRow: View {
        let entry: ModelDownloadCenter.Entry
        let onDismiss: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                icon.frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(entry.message.isEmpty ? "Đang tải…" : entry.message)
                        .font(.footnote)
                        .foregroundStyle(entry.state.isFailed ? Color.red : Color.secondary)
                        .lineLimit(2)

                    if entry.state.isRunning {
                        ProgressView(value: entry.fraction)
                    } else {
                        ActivityDismissButton(action: onDismiss)
                    }
                }
            }
            .padding(.vertical, 2)
        }

        @ViewBuilder
        private var icon: some View {
            if entry.state.isRunning {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color.teal)
                    .font(.title3)
                    .symbolEffect(.pulse, options: .repeating)
            } else if entry.state.isFailed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .font(.title3)
            } else {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(Color.teal)
                    .font(.title3)
            }
        }
    }

    /// Nút "Bỏ qua" của **dòng kết quả**. Không có `swipeActions` cho hàng tiến độ: một cú vuốt không nên
    /// xoá mất dấu vết của lượt khôi phục vừa chạy — phải là hành động tường minh, cùng lý do đã ghi ở
    /// `NotificationInboxView+Rephoneticize.swift`.
    struct ActivityDismissButton: View {
        let action: () -> Void

        var body: some View {
            Button(role: .destructive, action: action) {
                Text("Bỏ qua")
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
    }
}
