import SwiftUI

/// Hộp "Đổi tên playlist" (ô nhập) + hộp xác nhận "Xoá playlist", dùng chung cho thẻ ở tab Playlist (nhấn giữ) và ngăn
/// kéo `…` của trang chi tiết. Mọi lượt ghi đi qua `PlaylistCoordinator`; lỗi / xong báo bằng toast.
///
/// Nơi gọi đặt `renameText` = tên hiện tại **trước** khi gán `renameTarget` (ô nhập của `alert` không nhận giá trị đổi
/// sau khi hộp đã hiện).
struct PlaylistManageAlertsModifier: ViewModifier {
    @Binding var renameTarget: Playlist?
    @Binding var renameText: String
    @Binding var deleteTarget: Playlist?
    /// Chạy sau khi xoá xong (trang chi tiết quay lại).
    let onDeleted: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Đổi tên playlist", isPresented: isPresented($renameTarget)) {
                TextField("Tên playlist", text: $renameText)
                    .textInputAutocapitalization(.sentences)
                Button("Lưu") { commitRename() }
                Button("Hủy", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog(
                "Xoá playlist \"\(deleteTarget?.name ?? "")\"?",
                isPresented: isPresented($deleteTarget),
                titleVisibility: .visible
            ) {
                Button("Xoá playlist", role: .destructive) { commitDelete() }
                Button("Hủy", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Chỉ danh sách bị xoá. Album, phim và tiến độ nghe / xem vẫn giữ nguyên.")
            }
    }

    private func isPresented(_ target: Binding<Playlist?>) -> Binding<Bool> {
        Binding(
            get: { target.wrappedValue != nil },
            set: { presented in
                if !presented { target.wrappedValue = nil }
            }
        )
    }

    private func commitRename() {
        guard let playlist = renameTarget else { return }
        renameTarget = nil
        if case .failure(let error) = PlaylistCoordinator.shared.rename(playlistId: playlist.id, to: renameText) {
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }

    private func commitDelete() {
        guard let playlist = deleteTarget else { return }
        deleteTarget = nil
        switch PlaylistCoordinator.shared.delete(playlistId: playlist.id) {
        case .success:
            ToastManager.shared.show(message: "Đã xoá playlist \(playlist.name)", type: .success)
            onDeleted()
        case .failure(let error):
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        }
    }
}

extension View {
    /// Gắn hộp đổi tên / xoá playlist — xem `PlaylistManageAlertsModifier`.
    func playlistManageAlerts(
        renameTarget: Binding<Playlist?>,
        renameText: Binding<String>,
        deleteTarget: Binding<Playlist?>,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(PlaylistManageAlertsModifier(
            renameTarget: renameTarget,
            renameText: renameText,
            deleteTarget: deleteTarget,
            onDeleted: onDeleted
        ))
    }
}
