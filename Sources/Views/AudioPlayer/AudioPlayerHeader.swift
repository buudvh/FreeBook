import SwiftUI

/// Header của màn nghe: trái ⌄ (thu nhỏ — đóng màn, nhạc vẫn phát), giữa tên album + "Phát từ album" (`HeaderTitleBlock`
/// căn giữa, dòng chính ở trên), phải `ellipsis.circle` (ngăn kéo tuỳ chọn). Lưới header chung (1.3.1017): lề
/// `HeaderMetrics`, ⌄ khung 38×44 canh trái và "…" khung 36×38 canh phải ⇒ icon ngoài cùng chạm lề; icon 17pt nửa đậm.
struct AudioPlayerHeader: View {
    let albumTitle: String
    let onMinimize: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            iconButton(
                systemImage: "chevron.down",
                label: "Thu nhỏ màn nghe",
                width: HeaderMetrics.backFrameWidth,
                height: HeaderMetrics.backFrameHeight,
                alignment: .leading,
                action: onMinimize
            )
            HeaderTitleBlock(
                title: albumTitle.isEmpty ? "Album" : albumTitle,
                subtitle: "Phát từ album",
                alignment: .center,
                titleColor: Color.white,
                subtitleColor: Color.white.opacity(0.65)
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            iconButton(
                systemImage: "ellipsis.circle",
                label: "Tuỳ chọn trình nghe",
                width: HeaderMetrics.iconFrameWidth,
                height: HeaderMetrics.iconFrameHeight,
                alignment: .trailing,
                action: onMenu
            )
        }
        .padding(.horizontal, HeaderMetrics.horizontalMargin)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func iconButton(
        systemImage: String,
        label: String,
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: width, height: height, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
