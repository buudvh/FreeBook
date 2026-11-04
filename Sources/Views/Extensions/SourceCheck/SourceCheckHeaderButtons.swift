import SwiftUI

/// Nút header của hai màn kiểm tra nguồn (Legado, tiện ích JS): **⌄ thu nhỏ** (chỉ khi lượt đang chạy, 1.3.697) và chia
/// sẻ báo cáo. Hai nút đứng sát nhau trong **một** `ToolbarItem` theo `HeaderButtonMetrics`; còn một nút thì khung 36.
/// Glyph ⌄ cùng nút thu nhỏ của trình phát video.
struct SourceCheckHeaderButtons: View {
    let showsMinimize: Bool
    let isShareDisabled: Bool
    let onMinimize: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: HeaderButtonMetrics.pairSpacing) {
            if showsMinimize {
                Button(action: onMinimize) {
                    icon("chevron.down")
                }
                .accessibilityLabel("Thu nhỏ, lượt kiểm tra chạy tiếp ở nền")
            }
            Button(action: onShare) {
                icon("square.and.arrow.up")
            }
            .disabled(isShareDisabled)
            .accessibilityLabel("Chia sẻ báo cáo kiểm tra")
        }
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: showsMinimize ? HeaderButtonMetrics.pairIconWidth : 36, height: 36)
            .contentShape(Rectangle())
    }
}
