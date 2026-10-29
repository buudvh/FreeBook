import SwiftUI

/// Nút "Xoá bản tải · 5 tập · 2,3 GB" trong cụm nút bung của trang chi tiết phim. Chỉ hiện khi phim còn file tải (kể
/// cả bản dở); bấm hỏi xác nhận rồi xoá qua `VideoOfflineLibrary` (phim vẫn ở trên kệ, tác vụ tải của phim bị huỷ).
/// Tóm tắt đọc từ `VideoOfflineLibrary` — trang chi tiết gọi `refresh` lúc hiện.
struct VideoDownloadsDeletePill: View {
    let bookId: String
    let onDone: () -> Void

    @State private var isConfirming = false

    private var summary: VideoOfflineStore.BookSummary {
        VideoOfflineLibrary.shared.summary(bookId: bookId)
    }

    var body: some View {
        if summary.hasFiles {
            Button {
                isConfirming = true
            } label: {
                HStack {
                    Text("Xoá bản tải · " + Self.detailText(for: summary))
                        .font(.caption)
                        .fontWeight(.bold)
                    Image(systemName: "trash.fill")
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                // Chữ + icon đỏ trên nền đỏ mờ ~15%, lót nền tối như các pill cạnh nó để không lẫn vào ảnh bìa.
                .background(Color.red.opacity(0.15))
                .background(Color(white: 0.22))
                .foregroundColor(.red)
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(radius: 3)
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

    /// "5 tập · 2,3 GB" — chỉ có bản dở thì chỉ ghi dung lượng. Dùng chung với `VideoDownloadsActionRow`.
    static func detailText(for summary: VideoOfflineStore.BookSummary) -> String {
        var parts: [String] = []
        if !summary.completedEpisodes.isEmpty {
            parts.append("\(summary.completedEpisodes.count) tập")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    private func deleteAll() {
        onDone()
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
