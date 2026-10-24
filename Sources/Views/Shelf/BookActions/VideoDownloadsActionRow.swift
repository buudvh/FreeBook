import SwiftUI

/// Hàng đỏ "Xoá bản tải (5 tập · 2,3 GB)" trong sheet nhấn giữ phim (`BookActionSheet`). Tự xử lý tại chỗ (xác nhận +
/// `VideoOfflineLibrary.deleteAll`) thay vì phát `BookSheetAction` — phim vẫn ở trên kệ, không cần màn gọi làm gì.
/// Chỉ hiện khi phim còn file tải; `BookActionSheet` làm mới tóm tắt lúc mở.
struct VideoDownloadsActionRow: View {
    let bookId: String

    @State private var isConfirming = false

    var body: some View {
        let summary = VideoOfflineLibrary.shared.summary(bookId: bookId)
        if summary.hasFiles {
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                Label("Xoá bản tải (\(VideoDownloadsDeletePill.detailText(for: summary)))", systemImage: "trash")
            }
            .confirmationDialog("Xoá bản tải của phim này?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Xoá bản tải", role: .destructive) {
                    deleteAll()
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Phim vẫn ở trên kệ; xem lại cần mạng hoặc tải lại.")
            }
        }
    }

    private func deleteAll() {
        Task {
            do {
                try await VideoOfflineLibrary.shared.deleteAll(bookId: bookId)
                ToastManager.shared.show(message: "Đã xoá bản tải của phim", type: .success)
            } catch {
                AppLogger.shared.log("❌ [VideoOffline] Xoá bản tải của phim lỗi: \(error.localizedDescription)")
                ToastManager.shared.show(message: "Không xoá được bản tải: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
