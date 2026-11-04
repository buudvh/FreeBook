import SwiftUI

/// Ngăn kéo chọn nguồn của Khám phá (trượt từ mép **trái**, nội dung `ExtensionSelectorView`) cùng hai sheet mở từ nó:
/// Cấu hình tiện ích và Chi tiết nguồn Legado. Sheet gắn ở màn Khám phá vì ngăn kéo nằm ở cửa sổ nổi riêng và đã trượt
/// đi khi sheet hiện.
///
/// - Chọn nguồn ⇒ ghi `selectedExtensionId` + đánh dấu "vừa dùng".
/// - Đóng sheet Cấu hình / Chi tiết nguồn ⇒ `onConfigClosed` (Khám phá tải lại nếu config của nguồn đang xem vừa đổi).
/// - "Import truyện" trong trình duyệt mở từ Cấu hình: đóng sheet trước, ~0,35 s sau mới chuyển `onImport` — đẩy màn
///   Chi tiết vào stack khi sheet còn đang trượt xuống thì lượt đẩy có thể bị bỏ.
struct DiscoverySourcePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selectedExtensionId: String
    let extensions: [Extension]
    let onImport: (_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void
    let onConfigClosed: () -> Void

    @State private var configExtension: Extension? = nil
    /// Nguồn Legado đang mở màn Chi tiết nguồn (thay cho nút cấu hình của tiện ích JS).
    @State private var legadoDetailExtension: Extension? = nil

    func body(content: Content) -> some View {
        let selectionBinding = $selectedExtensionId
        return content
            .sideDrawerMenu(
                isPresented: $isPresented,
                title: "Chọn nguồn",
                edge: .leading,
                titleAccessory: { AnyView(ExtensionNsfwToggle()) },
                // Ô tìm đứng yên ở đầu, chỉ danh sách nguồn cuộn (`ExtensionSelectorView` tự cuộn).
                contentScrolls: false
            ) {
                ExtensionSelectorView(
                    activeExtensions: extensions,
                    selectedExtensionId: selectedExtensionId,
                    onSelect: { ext in
                        selectionBinding.wrappedValue = ext.packageId
                        // Chọn nguồn = duyệt chủ động ⇒ lên đầu nhóm "vừa dùng" (ghi file gom ~3 s).
                        ExtensionTransactionCoordinator.shared.markUsed(packageId: ext.packageId)
                    },
                    onOpenConfig: { configExtension = $0 },
                    onOpenLegadoDetail: { legadoDetailExtension = $0 }
                )
            }
            // Hai sheet có thể chứa màn kiểm tra nguồn: đóng khi lượt còn chạy ⇒ thu nhỏ vào hub (1.3.702).
            .sheet(item: $configExtension, onDismiss: { closeSheet(.script) }) { ext in
                ExtensionConfigView(ext: ext, onImport: { detailUrl, packageId, sourceName in
                    configExtension = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onImport(detailUrl, packageId, sourceName)
                    }
                })
            }
            .sheet(item: $legadoDetailExtension, onDismiss: { closeSheet(.legado) }) { ext in
                LegadoSourceDetailView(packageId: ext.packageId)
            }
    }

    private func closeSheet(_ checkKind: MinimizedSourceCheck.Kind) {
        MinimizedSourceCheckCoordinator.shared.screenDidClose(checkKind, screenId: nil)
        onConfigClosed()
    }
}

extension View {
    /// Gắn ngăn kéo chọn nguồn của Khám phá — xem `DiscoverySourcePickerModifier`.
    func discoverySourcePicker(
        isPresented: Binding<Bool>,
        selectedExtensionId: Binding<String>,
        extensions: [Extension],
        onImport: @escaping (_ detailUrl: String, _ extensionPackageId: String, _ sourceName: String) -> Void,
        onConfigClosed: @escaping () -> Void
    ) -> some View {
        modifier(DiscoverySourcePickerModifier(
            isPresented: isPresented,
            selectedExtensionId: selectedExtensionId,
            extensions: extensions,
            onImport: onImport,
            onConfigClosed: onConfigClosed
        ))
    }
}
