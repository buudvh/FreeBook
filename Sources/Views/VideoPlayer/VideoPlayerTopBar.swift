import SwiftUI

/// Thanh trên của trình phát — **chỉ biểu tượng**, chữ duy nhất là tên phim + tập.
///
/// Trái: thu nhỏ, đóng. Phải: tốc độ (`gauge…`, bung menu 0.5–2×, chỉ hiện số nhỏ khi khác 1×), Vừa/Lấp đầy/Phóng
/// (`aspectratio`), khoá xoay (khi ngang, hoặc khi đang khoá — khoá ở ngang rồi bấm Xoay dọc thì vẫn còn nút để mở
/// khoá), phụ đề, PiP, server, `⋯`. Màn dọc hẹp nên khung hình và server dồn vào
/// ngăn kéo `⋯` (server còn có hàng chip dưới khung phim). Chất lượng (HLS nhiều mức) luôn nằm trong `⋯`.
struct VideoPlayerTopBar: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController
    let isLandscape: Bool
    let onMinimize: () -> Void
    let onClose: () -> Void

    @State private var showingMoreMenu = false // Ngăn kéo `⋯`

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
            if isLandscape, session.hasSourceChoices {
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
        // Ngăn kéo cao toàn màn, bám mép phải cả khi nằm ngang; tông tối riêng nên đọc rõ trên khung phim.
        .sideDrawerMenu(isPresented: $showingMoreMenu, title: "Tuỳ chọn trình phát") { moreMenuItems }
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

    /// Tập có bản tải ⇒ "Bản tải" đứng đầu (+ "Trực tuyến" khi chưa nạp server — `VideoPlaybackSession+Offline`).
    @ViewBuilder
    private var serverPicker: some View {
        if session.hasOfflineCopy {
            checkmarkButton("Bản tải", isSelected: session.isPlayingOffline) {
                session.playOffline()
            }
            if session.servers.isEmpty {
                checkmarkButton("Trực tuyến", isSelected: false) {
                    session.playOnline()
                }
            }
        }
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

    /// Nút `⋯` bật ngăn kéo `moreMenuItems` (gắn ở thân thanh này — thanh chỉ mờ đi khi tự ẩn, không rời cây view).
    private var moreMenu: some View {
        Button {
            showingMoreMenu = true
        } label: {
            VideoPlayerIconLabel(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thêm")
    }

    /// Ba menu con cũ (Khung hình / Server / Chất lượng) ⇒ ba nhóm hàng chọn: bấm là áp dụng ngay, ngăn kéo vẫn mở.
    @ViewBuilder
    private var moreMenuItems: some View {
        let showsGravity = !isLandscape && session.embedContent == nil
        let showsServers = !isLandscape && session.hasSourceChoices
        // HLS từ 2 mức trở lên (`VideoPlaybackSession+Quality`); chọn = trần chất lượng, mạng yếu vẫn có thể thấp hơn.
        // Danh sách chỉ xoá khi item mới vào ⇒ chặn thêm lúc nhúng trang / không có item để không hiện mục cũ.
        let showsQuality = session.embedContent == nil && session.hasPlayableItem && !session.qualityOptions.isEmpty
        if showsGravity {
            SideDrawerSectionHeader("Khung hình")
            ForEach(VideoPlayerController.Gravity.allCases) { gravity in
                SideDrawerOptionRow(gravity.title, isSelected: gravity == controller.gravity) { controller.setGravity(gravity) }
            }
        }
        if showsServers {
            SideDrawerSectionHeader("Server")
            serverOptionRows
        }
        if showsQuality {
            SideDrawerSectionHeader("Chất lượng · \(session.appliedQuality?.title ?? "Tự động")")
            SideDrawerOptionRow("Tự động", isSelected: session.selectedQuality == nil) { session.selectQuality(nil) }
            ForEach(session.qualityOptions) { option in
                SideDrawerOptionRow(option.title, isSelected: session.selectedQuality != nil && option == session.appliedQuality) {
                    session.selectQuality(option)
                }
            }
        }
        if showsGravity || showsServers || showsQuality {
            SideDrawerDivider()
        }
        downloadItems
        SideDrawerActionRow("Tải lại", systemImage: "arrow.clockwise") { session.retry() }
        if session.canTryAnotherServer {
            SideDrawerActionRow("Thử server khác", systemImage: "arrow.triangle.2.circlepath") { session.tryAnotherServer() }
        }
        SideDrawerDivider()
        SideDrawerActionRow("Đóng trình phát", systemImage: "xmark", role: .destructive, action: onClose)
    }

    /// Bản hàng chọn của `serverPicker` cho ngăn kéo (menu Server lúc nằm ngang vẫn dùng `serverPicker`).
    @ViewBuilder
    private var serverOptionRows: some View {
        if session.hasOfflineCopy {
            SideDrawerOptionRow("Bản tải", isSelected: session.isPlayingOffline) { session.playOffline() }
            if session.servers.isEmpty {
                SideDrawerOptionRow("Trực tuyến", isSelected: false) { session.playOnline() }
            }
        }
        ForEach(Array(session.servers.enumerated()), id: \.offset) { index, server in
            SideDrawerOptionRow(
                server.title.isEmpty ? "Server \(index + 1)" : server.title,
                isSelected: index == session.selectedServerIndex
            ) {
                session.selectServer(at: index)
            }
        }
    }

    /// "Tải tập này" (hoặc "Xoá bản tải tập này" khi đã tải) và "Tải nhiều tập…" (sheet tải của màn hình).
    @ViewBuilder
    private var downloadItems: some View {
        if let episode = session.currentEpisode {
            let actions = VideoEpisodeDownloadActions(session: session)
            if actions.isDownloaded(episode) {
                SideDrawerActionRow("Xoá bản tải tập này", systemImage: "trash", role: .destructive) {
                    actions.deleteDownload(episode)
                }
            } else {
                SideDrawerActionRow("Tải tập này", systemImage: "arrow.down.circle") { actions.download(episode) }
            }
            SideDrawerActionRow("Tải nhiều tập…", systemImage: "square.and.arrow.down.on.square") {
                controller.showsBatchDownloadSheet = true
            }
        }
    }

    static func rateLabel(_ rate: Float) -> String {
        let text = rate == rate.rounded() ? String(Int(rate)) : String(format: "%g", Double(rate))
        return "\(text)×"
    }
}
