import SwiftUI
import UIKit

/// Thanh kính nổi dưới của trình duyệt người dùng (mockup 2026-10-30): lùi, tiến (mờ khi không đi được), ô URL dạng
/// viên (`BrowserAddressPill`), nút dịch trang (kiểu chip "on" khi `tab.isTranslating`; mờ ở Home / trang không phải
/// web). Không còn nút Home, Import, số tab — các lối đó ở dải tab, viên Import nổi và ngăn kéo "…".
///
/// Đang nhập địa chỉ ⇒ ô URL giãn hết thanh, ẩn lùi/tiến/dịch, thêm nút "Huỷ" để thoát (trên Home không có web view
/// nào lấy mất focus nên phải có lối thoát rõ ràng).
///
/// Cao 54, bo 27; nền `BrowserGlassCapsuleBackground` (đọc cài đặt kính của nút nổi). Ép bảng màu tối cho riêng thanh
/// để chữ/caret của ô nhập luôn trắng trên kính tối.
struct BrowserBottomBar: View {
    static let height: CGFloat = 54

    @ObservedObject var store: BypassBrowserTabStore
    @ObservedObject var tab: BypassBrowserTab
    let isHome: Bool
    @Binding var inputUrl: String
    @Binding var isEditingUrl: Bool
    let onBeginEditing: () -> Void
    let onSubmitUrl: () -> Void
    let onReload: () -> Void
    let onOpenSettings: () -> Void

    private static let dimmedColor = Color.white.opacity(0.32)

    /// Nút dịch chỉ có tác dụng với trang web http(s) (`toggleTranslation` bỏ qua Home / `about:blank` / trang khác).
    private var canTranslate: Bool {
        guard !isHome, let url = URL(string: tab.urlString) else { return false }
        return BypassBrowserTabStore.isWebURL(url)
    }

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
                translateButton
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background { BrowserGlassCapsuleBackground(outlineOpacity: 0.16, usesBarGlass: true) }
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

    private var translateButton: some View {
        Button {
            store.toggleTranslation(for: tab)
        } label: {
            AppGlyph.translate.image(size: 19)
                .foregroundColor(canTranslate ? Color.white : Self.dimmedColor)
                .frame(width: 38, height: 38)
                .background {
                    if tab.isTranslating {
                        Circle().fill(Color.white.opacity(0.18))
                        Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canTranslate)
        .accessibilityLabel(tab.isTranslating ? "Tắt dịch trang" : "Dịch trang")
        .accessibilityAddTraits(tab.isTranslating ? .isSelected : [])
    }

    /// Thoát ô nhập: bỏ focus (ô tự hạ `isEditingUrl` ở `textFieldDidEndEditing`) và hạ luôn cờ phòng khi ô chưa từng
    /// nhận focus.
    private func endEditing() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        isEditingUrl = false
    }
}
