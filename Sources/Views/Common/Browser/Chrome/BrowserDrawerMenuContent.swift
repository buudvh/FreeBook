import SwiftUI

/// Nội dung ngăn kéo "…" của trình duyệt người dùng (mockup 2026-10-30, màn "Mới 2"), gắn bằng
/// `.sideDrawerMenu(isPresented:title: "Trình duyệt")` ở thân `BypassWebView`. Không vạch ngăn; hai nhóm:
/// - "Trang này": Import truyện (chữ phụ "N nguồn", mờ khi không tiện ích nào khớp URL hoặc màn không nhận import),
///   Sao chép link, Chia sẻ (mờ ở Home);
/// - "Trình duyệt": Tab mới (mờ khi đủ tab), Về trang chủ, Lịch sử, Cài đặt trình duyệt.
///
/// Ngăn kéo nằm ở cửa sổ riêng và không dùng environment của màn ⇒ chỉ nhận giá trị thuần + closure.
struct BrowserDrawerMenuContent: View {
    let importSourceCount: Int
    let canImport: Bool
    let hasWebPage: Bool
    let canOpenMoreTabs: Bool
    let onImport: () -> Void
    let onCopyLink: () -> Void
    let onShare: () -> Void
    let onNewTab: () -> Void
    let onGoHome: () -> Void
    let onOpenHistory: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        SideDrawerSectionHeader("Trang này")
        SideDrawerActionRow(
            "Import truyện",
            systemImage: "plus.circle",
            detail: canImport ? "\(importSourceCount) nguồn" : nil,
            action: onImport
        )
        .disabled(!canImport)
        SideDrawerActionRow("Sao chép link", glyph: .copy, action: onCopyLink)
            .disabled(!hasWebPage)
        SideDrawerActionRow("Chia sẻ", systemImage: "square.and.arrow.up", action: onShare)
            .disabled(!hasWebPage)

        SideDrawerSectionHeader("Trình duyệt")
        SideDrawerActionRow("Tab mới", systemImage: "plus.square", action: onNewTab)
            .disabled(!canOpenMoreTabs)
        SideDrawerActionRow("Về trang chủ", systemImage: "house", action: onGoHome)
        SideDrawerActionRow("Lịch sử", systemImage: "clock", action: onOpenHistory)
        SideDrawerActionRow("Cài đặt trình duyệt", systemImage: "gearshape", action: onOpenSettings)
    }
}
