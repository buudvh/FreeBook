import SwiftUI

/// Công tắc **"DNS mã hoá (DoH)"** của một nguồn (1.3.831) — dùng chung cho mục Mạng của Cấu hình tiện ích JS và mục
/// Hoạt động của Chi tiết nguồn Legado (nguồn Legado cũng là bản ghi `Extension`).
///
/// - Đọc bản ghi theo `packageId` **trong lượt vẽ** (bảng tiện ích là `@Observable` ⇒ ghi xong tự vẽ lại); ghi qua
///   `ExtensionTransactionCoordinator.setEncryptedDNSEnabled` (tắt ghi `nil`), rồi báo `EncryptedDNSRepository`
///   (`sourcesDidChange`) để bật / tắt proxy nội bộ và dò máy chủ.
/// - Công tắc chung "Bật cho cả app" đang bật ⇒ hiện bật + mờ (cả app đã dùng DNS mã hoá).
/// - `Footnote`: chân mục cho Cấu hình tiện ích (Legado không có chân mục).
struct ExtensionEncryptedDNSToggle: View {
    let packageId: String
    /// Hiện icon như các hàng `Label` của Chi tiết nguồn Legado.
    var showsIcon = false

    @AppStorage(EncryptedDNSPolicy.enabledKey) private var globalEnabled = EncryptedDNSPolicy.defaultEnabled

    var body: some View {
        let ext = ExtensionLibraryRepository.shared.installedExtension(packageId: packageId)
        let isOn = globalEnabled || ext?.encryptedDNSEnabled == true
        let id = packageId
        let name = ext?.name ?? packageId
        Toggle(isOn: Binding(
            get: { isOn },
            set: { value in
                guard value != isOn else { return }
                MainActor.assumeIsolated { Self.save(packageId: id, name: name, value) }
            }
        )) {
            if showsIcon {
                Label("DNS mã hoá (DoH)", systemImage: "lock.shield")
            } else {
                Text("DNS mã hoá (DoH)")
            }
        }
        .disabled(globalEnabled || ext == nil)
    }

    @MainActor
    private static func save(packageId: String, name: String, _ value: Bool) {
        switch ExtensionTransactionCoordinator.shared.setEncryptedDNSEnabled(packageId: packageId, value ? true : nil) {
        case .success:
            AppLogger.shared.log("[ExtConfig] \(name): \(value ? "bật" : "tắt") DNS mã hoá riêng")
            EncryptedDNSRepository.shared.sourcesDidChange()
        case .failure(let err):
            AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu công tắc DNS mã hoá của \(name): \(err.localizedDescription)")
            ToastManager.shared.show(message: "Không lưu được công tắc DNS mã hoá: \(err.localizedDescription)", type: .error)
        }
    }

    /// Chân mục: đang bật chung / đang bật riêng (kèm máy chủ); tắt ⇒ không có gì.
    struct Footnote: View {
        let packageId: String

        @AppStorage(EncryptedDNSPolicy.enabledKey) private var globalEnabled = EncryptedDNSPolicy.defaultEnabled
        @AppStorage(EncryptedDNSPolicy.resolverKey) private var resolver = EncryptedDNSPolicy.defaultResolver

        var body: some View {
            if globalEnabled {
                Text("Đang bật cho cả app ở Cài đặt › Mạng & DNS.")
            } else if ExtensionLibraryRepository.shared.installedExtension(packageId: packageId)?.encryptedDNSEnabled == true {
                Text("Tra tên miền qua \(resolver.shortTitle). Đổi máy chủ ở Cài đặt › Mạng & DNS.")
            }
        }
    }
}
