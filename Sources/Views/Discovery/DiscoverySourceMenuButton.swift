import SwiftUI

/// Nút menu tròn trên header Khám phá, gộp ba việc của nguồn đang chọn: Mở trình duyệt · Kiểu hiển thị · Dịch văn bản.
/// Chỉ hiện khi đã chọn nguồn. Mở trình duyệt / Kiểu hiển thị do `DiscoveryView` trình bày qua hai callback; dòng
/// Dịch văn bản mở bảng dịch dùng chung (`TranslationScopePopupView`) dạng popover neo vào chính nút này.
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

    var body: some View {
        Menu {
            if canOpenBrowser {
                Button(action: onOpenBrowser) {
                    Label("Mở trình duyệt", systemImage: "safari")
                }
            }

            Button(action: onShowLayout) {
                Label("Kiểu hiển thị", systemImage: layoutSymbol)
            }

            Button {
                // Action chạy khi menu hệ thống còn đang đóng; bật popover ở lượt runloop kế để nó trình bày được.
                DispatchQueue.main.async {
                    showingTranslationPopup = true
                }
            } label: {
                Label {
                    Text("Dịch văn bản")
                    Text(isTranslationEnabled ? "Đang bật" : "Đang tắt")
                } icon: {
                    Image(AppGlyph.translate.assetName)
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Tuỳ chọn nguồn")
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
