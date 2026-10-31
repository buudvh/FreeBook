import SwiftUI
import UIKit

/// Thanh dưới của trình duyệt người dùng, **gắn sát đáy** (mockup 2026-10-31): trang kết thúc ngay trên thanh, thanh
/// không nổi đè lên nội dung. Từ trái: lùi, tiến (mờ khi không đi được), ô URL dạng viên (`BrowserAddressPill`), nút
/// Import (`BrowserImportButton`, chỉ khi có nguồn khớp URL), nút ⋮ mở ngăn kéo "Trình duyệt". Dịch trang bằng tay nằm ở
/// ngăn kéo (công tắc "Dịch trang"); trang đang dịch thì ô URL có icon dịch nhỏ.
///
/// Đang nhập địa chỉ ⇒ ô URL giãn hết thanh, ẩn các nút khác, thêm nút "Huỷ" để thoát (trên Home không có web view
/// nào lấy mất focus nên phải có lối thoát rõ ràng).
///
/// Nền tối đặc kéo xuống hết vùng vạch Home (chỉ safe area `.container`: bàn phím hiện thì thanh nằm ngay trên bàn
/// phím). Ép bảng màu tối cho riêng thanh để chữ/caret của ô nhập luôn trắng.
struct BrowserBottomBar: View {
    static let height: CGFloat = 52

    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var tab: BypassBrowserTab
    let isHome: Bool
    /// Nguồn import khớp URL trang; rỗng ⇒ không có nút Import (View cha truyền rỗng khi màn không nhận import).
    let importMatches: [ExtensionUrlMatcher.Match]
    @Binding var isImportPickerPresented: Bool
    @Binding var inputUrl: String
    @Binding var isEditingUrl: Bool
    let onBeginEditing: () -> Void
    let onSubmitUrl: () -> Void
    let onReload: () -> Void
    let onOpenSettings: () -> Void
    let onImport: (ExtensionUrlMatcher.Match) -> Void
    let onOpenMenu: () -> Void

    private static let barColor = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private static let dimmedColor = Color.white.opacity(0.32)

    var body: some View {
        HStack(spacing: 4) {
            if !isEditingUrl {
                roundButton(systemImage: "chevron.left", isEnabled: tab.canGoBack, label: "Trang trước") {
                    tab.webView.goBack()
                }
                roundButton(systemImage: "chevron.right", isEnabled: tab.canGoForward, label: "Trang sau") {
                    tab.webView.goForward()
                }
            }

            BrowserAddressPill(
                store: store,
                tab: tab,
                isHome: isHome,
                inputUrl: $inputUrl,
                isEditing: $isEditingUrl,
                onBeginEditing: onBeginEditing,
                onSubmit: onSubmitUrl,
                onReload: onReload,
                onOpenSettings: onOpenSettings
            )

            if isEditingUrl {
                Button("Huỷ") {
                    endEditing()
                }
                .headerTextButton()
                .foregroundColor(.white)
                .frame(minWidth: 44, minHeight: 38)
                .padding(.horizontal, 4)
            } else {
                if !importMatches.isEmpty {
                    BrowserImportButton(
                        matches: importMatches,
                        isPickerPresented: $isImportPickerPresented,
                        onImport: onImport
                    )
                }
                menuButton
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            Self.barColor
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: isEditingUrl)
    }

    private func roundButton(
        systemImage: String,
        isEnabled: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isEnabled ? Color.white : Self.dimmedColor)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    /// ⋮ — SF Symbols không có ba chấm dọc nên xoay `ellipsis` 90°.
    private var menuButton: some View {
        Button(action: onOpenMenu) {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .rotationEffect(.degrees(90))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tuỳ chọn trình duyệt")
    }

    /// Thoát ô nhập: bỏ focus (ô tự hạ `isEditingUrl` ở `textFieldDidEndEditing`) và hạ luôn cờ phòng khi ô chưa từng
    /// nhận focus.
    private func endEditing() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isEditingUrl = false
    }
}
