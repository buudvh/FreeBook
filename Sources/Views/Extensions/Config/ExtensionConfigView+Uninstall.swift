import SwiftUI

/// **Gỡ tiện ích** từ màn cấu hình — nút nằm ở hàng nút của thẻ đầu (`ExtensionConfigHeaderCard`), cạnh Trình duyệt
/// và Ghim; không còn section gỡ ở cuối form.
///
/// Cùng đường với nút gỡ ở kho (`RepositoryManagerView.uninstallExtension`):
/// `ExtensionTransactionCoordinator.uninstallExtension(packageId:)` xoá thư mục, bản ghi (cấu hình, ghim, lần
/// dùng) và `localStorage`. Kho, Khám phá và màn TTS tự cập nhật vì `ExtensionLibraryRepository` là `@Observable`.
///
/// Lỗi hiện bằng `uninstallAlertMessage` **riêng** — không dùng `errorMessage`, biến đó thay cả form bằng màn
/// "Lỗi đọc cấu hình". Hộp xác nhận + alert gắn ở gốc màn (`uninstallDialogs(on:)`), không gắn vào dòng của `Form`.
extension ExtensionConfigView {
    static let uninstallConfirmMessage = "Xoá thư mục, cấu hình, ghim và dữ liệu đăng nhập (localStorage) của tiện ích. Sách đã thêm vẫn nằm trên kệ, nhưng không tải được chương mới cho tới khi cài lại."

    static let uninstallBlockedByTTSMessage = "Tiện ích đang dùng làm giọng đọc. Hãy chọn giọng đọc khác trước khi gỡ."

    /// Hành động của nút Gỡ trên thẻ đầu; `nil` (tiện ích chưa cài — `localPath` rỗng) ⇒ thẻ ẩn nút.
    internal var uninstallAction: (() -> Void)? {
        guard !current.localPath.isEmpty else { return nil }
        return { requestUninstall() }
    }

    /// Gắn hộp xác nhận gỡ + alert lỗi/chặn gỡ vào nội dung gốc của màn.
    internal func uninstallDialogs<Content: View>(on content: Content) -> some View {
        content
            .confirmationDialog(
                "Gỡ «\(current.name)»?",
                isPresented: $showingUninstallConfirm,
                titleVisibility: .visible
            ) {
                Button("Gỡ tiện ích", role: .destructive) {
                    performUninstall()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text(Self.uninstallConfirmMessage)
            }
            .alert("Không thể gỡ tiện ích", isPresented: uninstallAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uninstallAlertMessage)
            }
    }

    private var uninstallAlertBinding: Binding<Bool> {
        Binding(
            get: { !uninstallAlertMessage.isEmpty },
            set: { isPresented in
                if !isPresented { uninstallAlertMessage = "" }
            }
        )
    }

    /// Chặn khi tiện ích đang là engine TTS. Chỉ **đọc** `TTSManager.shared.tool` lúc bấm — View không observe
    /// `TTSManager` (luật projection reader).
    @MainActor
    internal func requestUninstall() {
        if TTSManager.shared.tool == ext.packageId {
            AppLogger.shared.log("⚠️ [ExtConfig] Chặn gỡ \(current.name): đang là giọng đọc TTS")
            uninstallAlertMessage = Self.uninstallBlockedByTTSMessage
            return
        }
        showingUninstallConfirm = true
    }

    @MainActor
    internal func performUninstall() {
        let name = current.name
        switch ExtensionTransactionCoordinator.shared.uninstallExtension(packageId: ext.packageId) {
        case .success:
            AppLogger.shared.log("🧹 [ExtConfig] Đã gỡ tiện ích: \(name)")
            ToastManager.shared.show(message: "Đã gỡ «\(name)»", type: .success)
            dismiss()
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi gỡ tiện ích \(name): \(err.localizedDescription)")
            uninstallAlertMessage = "Lỗi gỡ tiện ích \(name): \(err.localizedDescription)"
        }
    }
}
