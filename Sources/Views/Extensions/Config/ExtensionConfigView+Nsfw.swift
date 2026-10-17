import SwiftUI

/// Section **Nội dung nhạy cảm** của màn Cấu hình tiện ích: nút đánh dấu / bỏ đánh dấu 18+ (`Extension.nsfwOverride`).
///
/// Lưu **ngay** qua `ExtensionTransactionCoordinator.setNsfwOverride`. Lựa chọn của người dùng thắng nhận diện tự động
/// và không mất khi cập nhật tiện ích. Đánh dấu kéo theo: ẩn khi công tắc NSFW tắt, nhãn 18+ trên icon, mặc định
/// không lưu lịch sử (nếu chưa tự chọn).
extension ExtensionConfigView {
    @ViewBuilder
    internal var nsfwSection: some View {
        if current.isInstalled {
            let isNsfw = ExtensionNsfwClassifier.isNsfw(current)
            Section {
                Button {
                    Self.saveNsfwOverride(packageId: ext.packageId, name: current.name, !isNsfw)
                } label: {
                    Label(isNsfw ? "Bỏ đánh dấu 18+" : "Đánh dấu 18+", systemImage: isNsfw ? "eye" : "eye.slash")
                }
                if current.nsfwOverride != nil {
                    Button {
                        Self.saveNsfwOverride(packageId: ext.packageId, name: current.name, nil)
                    } label: {
                        Label("Dùng nhận diện tự động", systemImage: "arrow.uturn.backward")
                    }
                }
            } header: {
                Text("Nội dung nhạy cảm")
            } footer: {
                Text(nsfwFooter(isNsfw: isNsfw))
            }
        }
    }

    private func nsfwFooter(isNsfw: Bool) -> String {
        let state: String
        switch current.nsfwOverride {
        case .some(true): state = "Bạn đã đánh dấu tiện ích này là 18+."
        case .some(false): state = "Bạn đã bỏ đánh dấu 18+ cho tiện ích này."
        case .none: state = isNsfw ? "Tự nhận là 18+ (tiện ích tự khai hoặc tên, mô tả, tên miền nhạy cảm)." : "Không nhận là 18+."
        }
        return state + " Tiện ích 18+ bị ẩn khi tắt NSFW trong Cài đặt và có nhãn 18+ trên icon."
    }

    @MainActor
    static func saveNsfwOverride(packageId: String, name: String, _ value: Bool?) {
        switch ExtensionTransactionCoordinator.shared.setNsfwOverride(packageId: packageId, value) {
        case .success:
            let note = value.map { $0 ? "đánh dấu 18+" : "bỏ đánh dấu 18+" } ?? "dùng nhận diện tự động"
            AppLogger.shared.log("🔞 [ExtConfig] \(name): \(note)")
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu đánh dấu 18+ của \(name): \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không lưu được đánh dấu 18+: \(err.localizedDescription)", type: .error)
        }
    }
}
