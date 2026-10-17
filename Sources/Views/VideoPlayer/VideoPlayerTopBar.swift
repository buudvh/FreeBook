import SwiftUI

/// Thanh trên của trình phát — **chỉ biểu tượng**, chữ duy nhất là tên phim + tập.
///
/// Trái: thu nhỏ, đóng. Phải: tốc độ (`gauge…`, bung menu 0.5–2×, chỉ hiện số nhỏ khi khác 1×), Vừa/Lấp đầy/Phóng
/// (`aspectratio`), khoá xoay (khi ngang, hoặc khi đang khoá — khoá ở ngang rồi bấm Xoay dọc thì vẫn còn nút để mở
/// khoá), phụ đề, PiP, server, `⋯`. Màn dọc hẹp nên khung hình và server dồn vào
/// menu `⋯` (server còn có hàng chip dưới khung phim).
struct VideoPlayerTopBar: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController
    let isLandscape: Bool
    let onMinimize: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            VideoPlayerIconButton(systemName: "chevron.down", label: "Thu nhỏ trình phát", action: onMinimize)
            VideoPlayerIconButton(systemName: "xmark", label: "Đóng trình phát", action: onClose)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.bookTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !session.currentEpisodeLabel.isEmpty {
                    Text(session.currentEpisodeLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if session.embedContent == nil {
                speedMenu
                if isLandscape {
                    gravityMenu
                }
            }
            if isLandscape || controller.isOrientationLocked {
                VideoPlayerIconButton(
                    systemName: controller.isOrientationLocked ? "lock.rotation" : "lock.rotation.open",
                    label: controller.isOrientationLocked ? "Mở khoá xoay" : "Khoá xoay",
                    isActive: controller.isOrientationLocked
                ) {
                    controller.toggleOrientationLock()
                }
            }
            if session.hasSubtitles {
                VideoPlayerIconButton(
                    systemName: session.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble",
                    label: session.subtitlesEnabled ? "Tắt phụ đề" : "Bật phụ đề"
                ) {
                    session.toggleSubtitles()
                    controller.showControls()
                }
            }
            if session.isPictureInPicturePossible || session.isPictureInPictureActive {
                VideoPlayerIconButton(
                    systemName: session.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                    label: "Hình trong hình"
                ) {
                    session.togglePictureInPicture()
                }
            }
            if isLandscape, session.servers.count > 1 {
                Menu {
                    serverPicker
                } label: {
                    VideoPlayerIconLabel(systemName: "server.rack")
                }
                .accessibilityLabel("Chọn server")
            }
            moreMenu
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    // MARK: - Menu

    private var speedMenu: some View {
        Menu {
            ForEach(VideoPlaybackSession.playbackRates, id: \.self) { rate in
                checkmarkButton(Self.rateLabel(rate), isSelected: rate == session.playbackRate) {
                    session.setPlaybackRate(rate)
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                VideoPlayerIconLabel(systemName: "gauge.with.dots.needle.67percent")
                if session.playbackRate != 1 {
                    Text(Self.rateLabel(session.playbackRate))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.white))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .accessibilityLabel("Tốc độ phát")
    }

    private var gravityMenu: some View {
        Menu {
            gravityPicker
        } label: {
            VideoPlayerIconLabel(systemName: "aspectratio")
        }
        .accessibilityLabel("Khung hình")
    }

    private var gravityPicker: some View {
        ForEach(VideoPlayerController.Gravity.allCases) { gravity in
            checkmarkButton(gravity.title, isSelected: gravity == controller.gravity) {
                controller.setGravity(gravity)
            }
        }
    }

    private var serverPicker: some View {
        ForEach(Array(session.servers.enumerated()), id: \.offset) { index, server in
            checkmarkButton(
                server.title.isEmpty ? "Server \(index + 1)" : server.title,
                isSelected: index == session.selectedServerIndex
            ) {
                session.selectServer(at: index)
            }
        }
    }

    /// Mục menu có dấu tích ở lựa chọn hiện tại (thay `Picker` để hành động đi thẳng qua `Button`).
    @ViewBuilder
    private func checkmarkButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if !isLandscape, session.embedContent == nil {
                Menu("Khung hình") {
                    gravityPicker
                }
            }
            if !isLandscape, session.servers.count > 1 {
                Menu("Server") {
                    serverPicker
                }
            }
            Button {
                session.retry()
            } label: {
                Label("Tải lại", systemImage: "arrow.clockwise")
            }
            if session.canTryAnotherServer {
                Button {
                    session.tryAnotherServer()
                } label: {
                    Label("Thử server khác", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Divider()
            Button(role: .destructive, action: onClose) {
                Label("Đóng trình phát", systemImage: "xmark")
            }
        } label: {
            VideoPlayerIconLabel(systemName: "ellipsis")
        }
        .accessibilityLabel("Thêm")
    }

    static func rateLabel(_ rate: Float) -> String {
        let text = rate == rate.rounded() ? String(Int(rate)) : String(format: "%g", Double(rate))
        return "\(text)×"
    }
}
