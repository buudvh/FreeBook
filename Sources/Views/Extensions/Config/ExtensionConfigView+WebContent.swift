import SwiftUI

/// Nhóm **Trình duyệt** của màn Cấu hình tiện ích (plan §3.3) — chặn quảng cáo + chế độ máy tính cho mọi webview
/// của tiện ích (engine ẩn, trình duyệt hiển thị, khung nhúng video, dò media). Hiện với **mọi** tiện ích đã cài.
///
/// - Công tắc **Chặn quảng cáo** hiển thị giá trị đang có hiệu lực `adBlockOverride ?? cài đặt chung` (đúng luật
///   của `WebContentPolicy`) và ghi `true`/`false` **tường minh**; chỉ dòng **Dùng cài đặt chung** (hiện khi đã
///   chỉnh) mới ghi `nil`.
/// - Công tắc **Chế độ máy tính** = `desktopModeOverride ?? false`; tắt ghi `nil` (khớp mặc định điện thoại).
///
/// Lưu **ngay** khi bấm qua `ExtensionTransactionCoordinator` (mẫu `+History`), không đi qua `configJson` (chuỗi đó
/// bị tiêm thành biến global của JS). Có hiệu lực từ lượt nạp trang kế tiếp của webview tiện ích.
///
/// Là view con riêng (không phải thuộc tính tính toán) để giữ `@AppStorage` của công tắc chung: mở trình duyệt từ
/// thẻ đầu → menu khiên → Cài đặt trình duyệt rồi đổi công tắc chung thì nhóm này vẽ lại ngay.
extension ExtensionConfigView {
    @ViewBuilder
    internal var webContentSection: some View {
        if current.isInstalled {
            WebContentSection(packageId: ext.packageId, fallback: current)
        }
    }

    struct WebContentSection: View {
        let packageId: String
        /// Bản chụp lúc vẽ màn cha — chỉ dùng khi bảng tiện ích không còn bản ghi (vừa gỡ).
        let fallback: Extension

        /// Mặc định `true` khớp `WebContentSettings.registerDefaults()`.
        @AppStorage(WebContentSettings.adBlockEnabledKey) private var globalAdBlock = true

        var body: some View {
            // Tra lại theo `packageId` trong lượt vẽ: bảng tiện ích là `@Observable` nên ghi xong là vẽ lại.
            let ext = ExtensionLibraryRepository.shared.installedExtension(packageId: packageId) ?? fallback
            Section {
                Toggle("Chặn quảng cáo", isOn: adBlockBinding(ext))
                if ext.adBlockOverride != nil {
                    Button {
                        Self.saveAdBlockOverride(packageId: ext.packageId, name: ext.name, nil)
                    } label: {
                        Label("Dùng cài đặt chung", systemImage: "arrow.uturn.backward")
                            .foregroundColor(.primary)
                    }
                }
                Toggle("Chế độ máy tính", isOn: desktopBinding(ext))
            } header: {
                Text("Trình duyệt")
            } footer: {
                Text(footer(for: ext))
            }
        }

        // MARK: - Binding

        /// Như `savesHistoryBinding`: chụp giá trị trong lượt vẽ, ghi qua `MainActor.assumeIsolated`.
        private func adBlockBinding(_ ext: Extension) -> Binding<Bool> {
            let isOn = ext.adBlockOverride ?? globalAdBlock
            let packageId = ext.packageId
            let name = ext.name
            return Binding(
                get: { isOn },
                set: { value in
                    guard value != isOn else { return }
                    MainActor.assumeIsolated { Self.saveAdBlockOverride(packageId: packageId, name: name, value) }
                }
            )
        }

        private func desktopBinding(_ ext: Extension) -> Binding<Bool> {
            let isOn = ext.desktopModeOverride ?? false
            let packageId = ext.packageId
            let name = ext.name
            return Binding(
                get: { isOn },
                set: { value in
                    guard value != isOn else { return }
                    // Tắt ⇒ `nil`, không ghi `false`: dữ liệu khớp đúng mặc định (điện thoại).
                    let stored: Bool? = value ? true : nil
                    MainActor.assumeIsolated { Self.saveDesktopModeOverride(packageId: packageId, name: name, stored) }
                }
            )
        }

        private func footer(for ext: Extension) -> String {
            let globalText = globalAdBlock ? "Bật" : "Tắt"
            let adBlockNote: String
            if let override = ext.adBlockOverride {
                adBlockNote = "Bạn đã \(override ? "bật" : "tắt") chặn quảng cáo cho tiện ích này (cài đặt chung: \(globalText))."
            } else {
                adBlockNote = "Chặn quảng cáo theo cài đặt chung (\(globalText))."
            }
            return adBlockNote + " Chế độ máy tính đổi HTML trang trả về, dễ làm tiện ích bóc tách sai. "
                + "Chỉ bật khi trang bắt buộc. Lưu ngay khi bấm."
        }

        // MARK: - Lưu

        @MainActor
        private static func saveAdBlockOverride(packageId: String, name: String, _ value: Bool?) {
            switch ExtensionTransactionCoordinator.shared.setAdBlockOverride(packageId: packageId, value) {
            case .success:
                let note = value.map { $0 ? "bật chặn quảng cáo" : "tắt chặn quảng cáo" } ?? "chặn quảng cáo theo cài đặt chung"
                AppLogger.shared.log("🛡️ [ExtConfig] \(name): \(note)")
            case .failure(let err):
                AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu công tắc chặn quảng cáo của \(name): \(err.localizedDescription)")
                ToastManager.shared.show(message: "Không lưu được công tắc chặn quảng cáo: \(err.localizedDescription)", type: .error)
            }
        }

        @MainActor
        private static func saveDesktopModeOverride(packageId: String, name: String, _ value: Bool?) {
            switch ExtensionTransactionCoordinator.shared.setDesktopModeOverride(packageId: packageId, value) {
            case .success:
                AppLogger.shared.log("🛡️ [ExtConfig] \(name): \(value == true ? "bật" : "tắt") chế độ máy tính")
            case .failure(let err):
                AppLogger.shared.log("❌ [ExtConfig] Lỗi lưu chế độ máy tính của \(name): \(err.localizedDescription)")
                ToastManager.shared.show(message: "Không lưu được chế độ máy tính: \(err.localizedDescription)", type: .error)
            }
        }
    }
}
