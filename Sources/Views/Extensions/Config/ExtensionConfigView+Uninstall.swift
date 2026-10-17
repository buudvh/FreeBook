import SwiftUI

/// Nút **Gỡ tiện ích** ở cuối form cấu hình (plan comic/video, Phần F).
///
/// Cùng đường với nút gỡ ở kho (`RepositoryManagerView.uninstallExtension`):
/// `ExtensionTransactionCoordinator.uninstallExtension(packageId:)` xoá thư mục, bản ghi (cấu hình, ghim, lần
/// dùng) và `localStorage`. Kho, Khám phá và màn TTS tự cập nhật vì `ExtensionLibraryRepository` là `@Observable`.
///
/// Lỗi hiện bằng `uninstallAlertMessage` **riêng** — không dùng `errorMessage`, biến đó thay cả form bằng màn
/// "Lỗi đọc cấu hình". Dialog/alert gắn vào chính nút để file gốc chỉ thêm 2 `@State` và 1 dòng gọi section.
extension ExtensionConfigView {
    static let uninstallConfirmMessage = "Xoá thư mục, cấu hình, ghim và dữ liệu đăng nhập (localStorage) của tiện ích. Sách đã thêm vẫn nằm trên kệ, nhưng không tải được chương mới cho tới khi cài lại."

    static let uninstallBlockedByTTSMessage = "Tiện ích đang dùng làm giọng đọc. Hãy chọn giọng đọc khác trước khi gỡ."

    /// Section cuối `Form`; chỉ hiện khi tiện ích đã cài (`localPath` khác rỗng).
    @ViewBuilder
    internal var uninstallSection: some View {
        if !current.localPath.isEmpty {
            Section {
                Button(role: .destructive) {
                    requestUninstall()
                } label: {
                    Label("Gỡ tiện ích", systemImage: "trash")
                }
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
