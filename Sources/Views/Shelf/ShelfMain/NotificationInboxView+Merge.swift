import SwiftUI

/// Khối **"Gộp vào Từ Điển Chung"** của `NotificationInboxView`.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo. Đây là extension **cùng file type** nên vẫn
/// dùng được `@ObservedObject mergeTask` và hai `@State` khai ở file chính (Swift không cho khai `@State`
/// trong extension).
///
/// Mục này **ghim**: nó không thuộc `NotificationInboxManager` lẫn `NewChapterInboxManager` nên hai hành
/// động của toolbar ("Đánh dấu đã đọc hết" / "Xoá thông báo đã đọc") **không** đụng tới nó. Nó chỉ biến mất
/// khi người dùng chọn **Nhập vào VietPhrase** hoặc **Bỏ qua**.
extension NotificationInboxView {

    @ViewBuilder
    func mergeTaskRow() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                mergeTaskIcon
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gộp vào Từ Điển Chung")
                        .font(.subheadline.weight(.semibold))
                    Text(mergeTask.statusText)
                        .font(.footnote)
                        .foregroundStyle(mergeTask.isFailed ? Color.red : Color.secondary)
                    if mergeTask.hasResult {
                        Text("File kết quả: `VietPhraseMerged.txt` (trong thư mục `translate/`)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let progress = mergeTask.runningProgress {
                ProgressView(value: progress)
            }

            if mergeTask.hasResult {
                mergeTaskActions
            } else if mergeTask.isFailed {
                HStack(spacing: 16) {
                    Button("Thử lại") { mergeTask.startMerge() }
                    Button("Bỏ qua", role: .destructive) { mergeTask.discardResult() }
                }
                .buttonStyle(.borderless)
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }

    /// Icon nhấp nháy khi đang gộp. Dùng `symbolEffect(.pulse, options: .repeating)` (iOS 17) thay vì tự
    /// chạy timer + `opacity`: hiệu ứng do hệ thống lo nên không tốn một vòng lặp vẽ nào.
    @ViewBuilder
    var mergeTaskIcon: some View {
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

    @ViewBuilder
    var mergeTaskActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Button {
                    applyMergeResult()
                } label: {
                    if isApplyingMerge {
                        ProgressView()
                    } else {
                        Label("Nhập vào VietPhrase", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(isApplyingMerge)

                ShareLink(item: mergeTask.mergedFileURL) {
                    Label("Xuất file", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderless)
            .font(.footnote)

            Button("Bỏ qua", role: .destructive) { mergeTask.discardResult() }
                .buttonStyle(.borderless)
                .font(.footnote)

            if !mergeErrorMessage.isEmpty {
                Text(mergeErrorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            Text("Nhập sẽ **thay** VietPhrase gốc bằng file này rồi **xoá** từ chỉnh sửa + từ đã xoá. Bản `.dat` cũ được sao lưu thành `VietPhrase.dat.bak-merge` trước khi thay.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
