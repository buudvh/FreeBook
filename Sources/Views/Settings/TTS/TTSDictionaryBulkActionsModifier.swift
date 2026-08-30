import SwiftUI

/// Hai hành động **hàng loạt** của màn Từ điển phiên âm: tải lại bộ gốc và **xoá tất cả**.
///
/// Vì sao là `ViewModifier` ở file riêng chứ không viết thẳng vào `TTSDictionaryEditView`: file đó
/// đang **vượt** baseline dòng của `check_architecture.py` (706 > 641) nên chỉ được giảm. Dời hai
/// alert ra đây vừa thêm được tính năng vừa làm file gốc ngắn lại.
///
/// Modifier tự gọi `TextPreprocessor` chứ không nhận closure xoá từ ngoài: nó là chủ duy nhất của
/// nghĩa "xoá tất cả", nên không có hai nơi hiểu khác nhau về việc đó. Chỉ `onFinished` được trả ra
/// để màn hình nạp lại danh sách.
@MainActor
struct TTSDictionaryBulkActionsModifier: ViewModifier {
    @Binding var showingDownloadConfirmation: Bool
    @Binding var showingDeleteAllConfirmation: Bool
    let onDownload: () -> Void
    let onFinished: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert("Xác nhận tải lại", isPresented: $showingDownloadConfirmation) {
                Button("Hủy", role: .cancel) {}
                Button("Tải lại", role: .destructive) { onDownload() }
            } message: {
                // Từ 1.3.290 bản tải về được **trộn** với bản dưới máy (mục dưới máy thắng), nên câu
                // cảnh báo cũ ("ghi đè tất cả từ vựng tùy chỉnh") đã sai và phải sửa theo.
                Text("Hành động này tải lại từ điển gốc từ HuggingFace và **trộn** vào bộ hiện có. Các phiên âm bạn tự thêm được giữ nguyên; mục nào trùng khoá thì bản của bạn thắng.")
            }
            .alert("Xoá tất cả phiên âm?", isPresented: $showingDeleteAllConfirmation) {
                Button("Hủy", role: .cancel) {}
                Button("Xoá tất cả", role: .destructive) { deleteAll() }
            } message: {
                Text("Xoá **toàn bộ** danh sách phiên âm khỏi máy, kể cả các mục tải từ HuggingFace và các mục bạn tự thêm. Không hoàn tác được. Sau khi xoá, mọi từ tiếng Anh/Nhật sẽ đọc theo bộ phiên âm tự động.")
            }
    }

    private func deleteAll() {
        Task {
            do {
                let removed = try await TextPreprocessor.shared.deleteAllWords()
                await onFinished()
                ToastManager.shared.show(message: "Đã xoá \(removed) phiên âm.", type: .success)
            } catch {
                ToastManager.shared.show(
                    message: "Không xoá được danh sách phiên âm: \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
}

extension View {
    func ttsDictionaryBulkActions(
        showingDownloadConfirmation: Binding<Bool>,
        showingDeleteAllConfirmation: Binding<Bool>,
        onDownload: @escaping () -> Void,
        onFinished: @escaping () async -> Void
    ) -> some View {
        modifier(TTSDictionaryBulkActionsModifier(
            showingDownloadConfirmation: showingDownloadConfirmation,
            showingDeleteAllConfirmation: showingDeleteAllConfirmation,
            onDownload: onDownload,
            onFinished: onFinished
        ))
    }
}
