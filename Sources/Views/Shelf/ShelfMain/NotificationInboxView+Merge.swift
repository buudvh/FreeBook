import SwiftUI

/// Khối **"Gộp vào Từ Điển Chung"** của `NotificationInboxView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là extension **cùng file type** nên vẫn
/// dùng được `@ObservedObject mergeTask` và hai `@State` khai ở file chính (Swift không cho khai `@State`
/// trong extension). `timeLabel(_:)` ở file chính cũng đã bỏ `private` vì lý do tương tự.
///
/// Bố cục (user chốt 2026-09-30, thay bản cũ nhiều dòng chữ): tiêu đề + **giờ ở góc phải** như các dòng
/// khác, một dòng trạng thái, **3 chip số liệu** `gốc / sửa / xoá`, rồi nút **Nhập vào VietPhrase**
/// full-width nổi bật (việc chính cần người dùng quyết), hàng dưới là **Xuất file** / **Bỏ qua**, và chú
/// thích dài gộp còn **một dòng mờ**.
///
/// Mục này **ghim**: nó không thuộc `NotificationInboxManager` lẫn `NewChapterInboxManager` nên hai hành
/// động của toolbar ("Đánh dấu đã đọc hết" / "Xoá thông báo đã đọc") **không** đụng tới nó. Nó chỉ biến
/// mất khi người dùng chọn **Nhập vào VietPhrase** hoặc **Bỏ qua**.
extension NotificationInboxView {

    @ViewBuilder
    func mergeTaskRow() -> some View {
        HStack(alignment: .top, spacing: 12) {
            mergeTaskIcon
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Gộp từ điển VietPhrase")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(timeLabel(mergeTask.displayDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(mergeTask.statusText)
                    .font(.footnote)
                    .foregroundStyle(mergeTask.isFailed ? Color.red : Color.secondary)

                if let progress = mergeTask.runningProgress {
                    ProgressView(value: progress)
                    Text("Đọc từ điển gốc · chưa ghi gì lên đĩa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if mergeTask.hasResult {
                    mergeTaskCounts
                    mergeTaskActions
                } else if mergeTask.isFailed {
                    mergeTaskFailureActions
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Icon nhấp nháy khi đang gộp. Dùng `symbolEffect(.pulse, options: .repeating)` (iOS 17) thay vì tự
    /// chạy timer + `opacity`: hiệu ứng do hệ thống lo nên không tốn vòng lặp vẽ nào.
    @ViewBuilder
    private var mergeTaskIcon: some View {
        if mergeTask.isRunning {
            Image(systemName: "arrow.triangle.merge")
                .foregroundStyle(Color.teal)
                .font(.title3)
                .symbolEffect(.pulse, options: .repeating)
        } else if mergeTask.hasResult {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(Color.teal)
                .font(.title3)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .font(.title3)
        }
    }

    /// Chip `gốc / sửa / xoá`. Khi không có số liệu chi tiết (file còn từ phiên trước mà `UserDefaults`
    /// chưa kịp ghi) thì lùi về **một** dòng tổng số từ, không hiện chip rỗng.
    @ViewBuilder
    private var mergeTaskCounts: some View {
        if let counts = mergeTask.summaryCounts {
            HStack(spacing: 8) {
                mergeCountChip("gốc", counts.base)
                mergeCountChip("sửa", counts.custom)
                mergeCountChip("xoá", counts.deleted)
            }
        } else {
            Text("\(mergeTask.resultRecordCount) từ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mergeCountChip(_ label: String, _ value: Int) -> some View {
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

    @ViewBuilder
    private var mergeTaskActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                applyMergeResult()
            } label: {
                Group {
                    if isApplyingMerge {
                        ProgressView()
                    } else {
                        Text("Nhập vào VietPhrase")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isApplyingMerge)

            HStack(spacing: 8) {
                ShareLink(item: mergeTask.mergedFileURL) {
                    Text("Xuất file").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    mergeTask.discardResult()
                } label: {
                    Text("Bỏ qua").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !mergeErrorMessage.isEmpty {
                Text(mergeErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            Text("VietPhraseMerged.txt · có sao lưu .dat cũ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mergeTaskFailureActions: some View {
        HStack(spacing: 8) {
            Button("Thử lại") { mergeTask.startMerge() }
                .buttonStyle(.bordered)
            Button("Bỏ qua", role: .destructive) { mergeTask.discardResult() }
                .buttonStyle(.bordered)
        }
        .font(.footnote)
    }

    /// Nhập file gộp vào từ điển gốc. Lỗi hiện ngay trong dòng này (không dùng toast: `ToastManager` ghi
    /// vào chính hộp thư đang mở).
    func applyMergeResult() {
        guard !isApplyingMerge else { return }
        isApplyingMerge = true
        mergeErrorMessage = ""
        Task {
            do {
                try await mergeTask.applyToVietPhrase()
            } catch {
                mergeErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Nhập thất bại: \(error.localizedDescription)"
            }
            isApplyingMerge = false
        }
    }
}
