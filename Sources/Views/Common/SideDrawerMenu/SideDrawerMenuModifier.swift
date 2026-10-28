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
/// **Đừng** gắn modifier này bên trong `ToolbarItem`: presenter nằm trong nội dung toolbar bị gỡ khi pop màn ⇒ màn
/// trắng (bug 1.3.281, xem `QuickTranslationRuleIOMenu`).
///
/// Cơ chế:
/// - Trình bày bằng `fullScreenCover` nền trong suốt nên phủ cả thanh điều hướng lẫn thanh tab. Hiệu ứng trượt lên mặc
///   định bị tắt (`Transaction.disablesAnimations`); `SideDrawerMenuPanel` tự trượt ngăn kéo vào từ phải.
/// - Nơi gọi chỉ bật `isPresented`; trạng thái cover nội bộ đi theo qua `onChange`.
/// - Hàng thao tác (`SideDrawerActionRow`) đóng ngăn kéo **trước**, action chạy trong `onDismiss` của cover — lúc đó
///   cover đã gỡ hẳn nên sheet / confirmationDialog / bộ chọn tệp / alert / điều hướng mà action mở ra không bị hụt.
///   Hàng công tắc và hàng chọn (`SideDrawerToggleRow`, `SideDrawerOptionRow`) đổi giá trị ngay, ngăn kéo vẫn mở.
struct SideDrawerMenuModifier<MenuContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var isCoverPresented = false
    /// Action của hàng thao tác vừa chọn — chạy khi cover đã gỡ xong.
    @State private var pendingAction: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                if presented, !isCoverPresented {
                    setCoverPresented(true)
                } else if !presented, isCoverPresented {
                    // Nơi gọi tự tắt khi ngăn kéo còn mở (hiếm) ⇒ gỡ ngay, không chờ hiệu ứng trượt ra.
                    setCoverPresented(false)
                }
            }
            .fullScreenCover(isPresented: $isCoverPresented, onDismiss: handleCoverDismiss) {
                SideDrawerMenuPanel(title: title, onClosed: finishClose, content: menuContent)
                    .presentationBackground(.clear)
            }
    }

    private func setCoverPresented(_ value: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCoverPresented = value
        }
    }

    /// Ngăn kéo đã trượt ra hết: gỡ cover (không hiệu ứng) rồi báo nơi gọi.
    private func finishClose(_ followUp: (() -> Void)?) {
        // Cover đã bị gỡ bằng đường khác (nơi gọi tự tắt) ⇒ `onDismiss` đã chạy, không giữ lại action mồ côi.
        guard isCoverPresented else { return }
        pendingAction = followUp
        setCoverPresented(false)
        if isPresented {
            isPresented = false
        }
    }

    private func handleCoverDismiss() {
        if isPresented {
            isPresented = false
        }
        guard let action = pendingAction else { return }
        pendingAction = nil
        // Nhường một nhịp runloop để UIKit dọn xong cover trước khi action trình bày cái mới.
        DispatchQueue.main.async {
            action()
        }
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
    func sideDrawerMenu<Item: Identifiable, MenuContent: View>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        @ViewBuilder content: @escaping (Item) -> MenuContent
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { presented in
                if !presented {
                    item.wrappedValue = nil
                }
            }
        )
        return modifier(
            SideDrawerMenuModifier(isPresented: isPresented, title: item.wrappedValue.map(title) ?? "") {
                if let value = item.wrappedValue {
                    content(value)
                }
            }
        )
    }
}
