import SwiftUI

/// Ngăn kéo menu trượt từ mép phải — thay cho menu thả xuống "…" (`Menu` của hệ thống) ở các màn.
///
/// Cách dùng: nút "…" trên thanh tiêu đề chỉ bật một `@State`, còn ngăn kéo gắn ở **thân chính** của màn:
/// ```swift
/// .toolbar { ToolbarItem { Button { showingMenu = true } label: { Image(systemName: "ellipsis.circle") } } }
/// .sideDrawerMenu(isPresented: $showingMenu, title: "Tuỳ chọn Kệ") {
///     SideDrawerSectionHeader("Hiển thị")
///     SideDrawerToggleRow("Dịch nghĩa", glyph: .translate, isOn: $isTranslationEnabled)
///     SideDrawerDivider()
///     SideDrawerActionRow("Nhập truyện từ file", systemImage: "square.and.arrow.down") { showingFilePicker = true }
/// }
/// ```
/// Menu theo từng hàng của danh sách dùng biến thể `sideDrawerMenu(item:title:content:)` gắn ở view gốc luôn được dựng
/// (`List`/`Form`) — một ngăn kéo cho cả danh sách. View chỉ là một `Section` (không có gốc ổn định) thì dùng
/// `SideDrawerMenuButton` ở từng hàng.
///
/// **Đừng** gắn modifier này bên trong `ToolbarItem`: nội dung toolbar bị gỡ/dựng lại thất thường ⇒ `onDisappear` gỡ
/// ngăn kéo ngoài ý muốn (trước đây là màn trắng khi pop, bug 1.3.281, xem `QuickTranslationRuleIOMenu`).
///
/// Cơ chế:
/// - Ngăn kéo nằm ở **cửa sổ nổi riêng** (`SideDrawerMenuWindowManager`), không còn `fullScreenCover`: cover chặn màn bên
///   dưới trình bày sheet mới nên phải chờ gỡ cover xong mới chạy action ⇒ sheet hiện chậm.
/// - Hàng thao tác (`SideDrawerActionRow`) chạy action **ngay** khi ngăn kéo bắt đầu trượt ra; sheet / hộp thoại /
///   bộ chọn tệp / điều hướng mà action mở ra trượt lên phía dưới trong lúc ngăn kéo trượt đi. Hàng công tắc và hàng
///   chọn (`SideDrawerToggleRow`, `SideDrawerOptionRow`) đổi giá trị ngay, ngăn kéo vẫn mở.
/// - Nội dung ngăn kéo luôn theo state của màn: trong lúc mở, `SideDrawerMenuContentRelay` (view vô hình gắn sau màn)
///   đẩy bản mới nhất sang cửa sổ mỗi lần màn vẽ lại; Binding trong hàng vẫn trỏ về state của màn.
/// - Màn rời cây view khi ngăn kéo còn mở (pop, đóng sheet chứa nó…) ⇒ gỡ cửa sổ ngay và hạ `isPresented`.
struct SideDrawerMenuModifier<MenuContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder let menuContent: () -> MenuContent

    /// Định danh chỗ gắn này với `SideDrawerMenuWindowManager` (một màn có thể gắn nhiều ngăn kéo).
    @State private var ownerID = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                if isPresented {
                    SideDrawerMenuContentRelay {
                        pushContent()
                    }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    present()
                } else {
                    // Ngăn kéo tự đóng (hàng thao tác, chạm ngoài, vuốt) đã hạ `isPresented` lúc bắt đầu trượt ra —
                    // manager bỏ qua lệnh này để hiệu ứng chạy nốt. Còn lại là nơi gọi tự tắt ⇒ gỡ ngay.
                    SideDrawerMenuWindowManager.shared.dismiss(ownerID: ownerID)
                }
            }
            .onAppear {
                if isPresented {
                    present()
                }
            }
            .onDisappear {
                SideDrawerMenuWindowManager.shared.dismiss(ownerID: ownerID)
                // Không hạ thì lần sau bấm "…" gán `true` lên `true`, `onChange` không chạy ⇒ ngăn kéo không mở.
                if isPresented {
                    isPresented = false
                }
            }
    }

    @MainActor
    private func present() {
        let binding = $isPresented
        let didPresent = SideDrawerMenuWindowManager.shared.present(
            ownerID: ownerID,
            title: title,
            content: contentProvider,
            resetPresented: {
                if binding.wrappedValue {
                    binding.wrappedValue = false
                }
            }
        )
        if !didPresent {
            isPresented = false
        }
    }

    @MainActor
    private func pushContent() {
        SideDrawerMenuWindowManager.shared.update(ownerID: ownerID, title: title, content: contentProvider)
    }

    /// Bọc nội dung thành `AnyView` cho host dùng chung; closure được gọi lại mỗi lần panel vẽ.
    private var contentProvider: () -> AnyView {
        let build = menuContent
        return { AnyView(build()) }
    }
}

extension View {
    /// Gắn ngăn kéo menu trượt từ mép phải; bật bằng `isPresented`. Xem `SideDrawerMenuModifier`.
    func sideDrawerMenu<MenuContent: View>(
        isPresented: Binding<Bool>,
        title: String,
        @ViewBuilder content: @escaping () -> MenuContent
    ) -> some View {
        modifier(SideDrawerMenuModifier(isPresented: isPresented, title: title, menuContent: content))
    }

    /// Biến thể cho menu theo **từng hàng** của danh sách: gán `item` = hàng được bấm để mở; ngăn kéo đóng thì `item`
    /// về `nil`. Tiêu đề ngăn kéo lấy từ chính hàng đó.
    ///
    /// Hàng được chụp lại ngay lúc màn vẽ: `item` về `nil` khi ngăn kéo bắt đầu trượt ra, nội dung đang trượt vẫn là
    /// của hàng cũ (không trống trơn giữa chừng).
    func sideDrawerMenu<Item: Identifiable, MenuContent: View>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        @ViewBuilder content: @escaping (Item) -> MenuContent
    ) -> some View {
        let current = item.wrappedValue
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in
                if !presented {
                    item.wrappedValue = nil
                }
            }
        )
        return modifier(
            SideDrawerMenuModifier(isPresented: isPresented, title: current.map(title) ?? "") {
                if let current {
                    content(current)
                }
            }
        )
    }
}
