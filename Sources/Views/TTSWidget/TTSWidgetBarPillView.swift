import SwiftUI

/// Viên thu gọn của kiểu **Thanh nghe nhạc** (1.3.796): nép sát mép phải (bo tròn bên trái, phẳng bên phải), đĩa bìa xoay
/// + ⏯. Chạm đĩa ⇒ bung lại thanh. Đứng cố định ngang tâm thanh (không kéo được, 1.3.799). Nền đặc tối như thanh
/// (`MiniPlayerBarChrome.solidBackground`), không theo độ trong suốt.
struct TTSWidgetBarPillView: View {
    static let height: CGFloat = 52
    static let width: CGFloat = 98

    let model: TTSWidgetBarViewModel
    let coverImage: UIImage?
    let rotationState: CoverRotationState
    let isCoverRotating: Bool
    let isPlaying: Bool

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.height / 2,
            bottomLeadingRadius: Self.height / 2,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: { model.expandByUser() }) {
                TTSCoverView(
                    image: coverImage,
                    size: 40,
                    rotationState: rotationState,
                    isRotating: isCoverRotating
                )
                .padding(6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở thanh nghe truyện")

            MiniPlayerControlButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? "Tạm dừng" : "Phát tiếp",
                action: { model.togglePlayback() }
            )
        }
        .padding(.trailing, 6)
        .frame(width: Self.width, height: Self.height, alignment: .leading)
        .background(MiniPlayerBarChrome.solidBackground(shape))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }
}
