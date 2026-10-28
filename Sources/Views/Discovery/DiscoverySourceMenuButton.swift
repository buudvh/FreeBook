import SwiftUI

/// Nút menu tròn trên header Khám phá, gộp ba việc của nguồn đang chọn: Mở trình duyệt · Kiểu hiển thị · Dịch văn bản.
/// Chỉ hiện khi đã chọn nguồn. Bấm ⇒ ngăn kéo trượt từ mép phải (`sideDrawerMenu`). Mở trình duyệt / Kiểu hiển thị do
/// `DiscoveryView` trình bày qua hai callback; dòng Dịch văn bản mở bảng dịch dùng chung (`TranslationScopePopupView`)
/// dạng popover neo vào chính nút này — mở ngay khi ngăn kéo bắt đầu trượt ra (ngăn kéo ở cửa sổ riêng, không chặn).
struct DiscoverySourceMenuButton: View {
    let packageId: String
    let sourceName: String
    let isChineseSourceHint: Bool?
    /// Trạng thái dịch hiện hành của nguồn (Khám phá tự cập nhật khi đổi nguồn / cấu hình dịch đổi) — cho dòng phụ.
    let isTranslationEnabled: Bool
    /// Icon của kiểu hiển thị đang dùng (`layout.mode.symbolName`).
    let layoutSymbol: String
    /// Nguồn có link trang chủ; không có thì ẩn dòng "Mở trình duyệt".
    let canOpenBrowser: Bool
    let onOpenBrowser: () -> Void
    let onShowLayout: () -> Void

    @State private var showingTranslationPopup = false
    @State private var showingDrawer = false

    var body: some View {
        Button {
            showingDrawer = true
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tuỳ chọn nguồn")
        .sideDrawerMenu(isPresented: $showingDrawer, title: "Tuỳ chọn nguồn") {
            if canOpenBrowser {
                SideDrawerActionRow("Mở trình duyệt", systemImage: "safari", action: onOpenBrowser)
            }
            SideDrawerActionRow("Kiểu hiển thị", systemImage: layoutSymbol, action: onShowLayout)
            SideDrawerActionRow(
                "Dịch văn bản",
                glyph: .translate,
                detail: isTranslationEnabled ? "Đang bật" : "Đang tắt"
            ) {
                showingTranslationPopup = true
            }
        }
        .popover(isPresented: $showingTranslationPopup, arrowEdge: .top) {
            // Khám phá không có truyện cụ thể ⇒ `bookId: ""`, bảng chỉ cho chọn Nguồn này / Tất cả.
            TranslationScopePopupView(
                bookId: "",
                packageId: packageId,
                sourceName: sourceName,
                isChineseSourceHint: isChineseSourceHint,
                onDone: { showingTranslationPopup = false }
            )
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.dark)
        }
    }
}
