import SwiftUI
import SwiftData

/// Màn xem phim cho tiện ích loại `video`. `BookContentDestination` mở màn này bên trong
/// `NavigationStack` của `fullScreenCover` khi `ExtensionContentKind` là `.video`.
///
/// Layout: thanh trên (Quay lại + tên phim) → player 16:9 → tên phim/tập, chip server, phụ đề,
/// lưới tập. Mọi logic nằm ở `VideoPlayerController`; View chỉ đọc state và gọi hàm.
struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var controller: VideoPlayerController

    init(launch: BookContentLaunch) {
        // `init` của controller không có side effect: SwiftUI có thể dựng lại struct này nhiều lần
        // nhưng chỉ giữ instance đầu tiên trong `@State`.
        _controller = State(initialValue: VideoPlayerController(launch: launch))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            VideoPlayerSurface(controller: controller)
            ScrollViewReader { proxy in
                ScrollView {
                    details
                        .padding(.vertical, 16)
                }
                .onChange(of: controller.currentEpisodeIndex) { _, newIndex in
                    scrollToEpisode(newIndex, proxy: proxy)
                }
                .onChange(of: controller.episodes.count) { _, _ in
                    scrollToEpisode(controller.currentEpisodeIndex, proxy: proxy)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await controller.start(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            controller.handleScenePhase(newPhase)
        }
        .onDisappear {
            controller.handleDisappear()
        }
    }

    // MARK: - Thanh trên

    private var headerBar: some View {
        HStack(spacing: 6) {
            Button {
                close()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            Text(controller.bookTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    // MARK: - Phần dưới player

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(controller.bookTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let episode = controller.currentEpisode {
                    Text(episode.title.isEmpty ? "Tập \(episode.index + 1)" : episode.title)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
                if controller.phase == .embed {
                    Text("Đang phát nhúng trang nguồn — bấm play trong khung phim.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 16)

            if !controller.servers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Server")
                    VideoServerChipBar(
                        servers: controller.servers,
                        selectedIndex: controller.selectedServerIndex,
                        onSelect: { controller.selectServer(at: $0) }
                    )
                }
            }

            if controller.hasSubtitles {
                subtitleToggle
                    .padding(.horizontal, 16)
            }

            if !controller.episodes.isEmpty {
                VideoEpisodeGridView(
                    episodes: controller.episodes,
                    currentIndex: controller.currentEpisodeIndex,
                    onSelect: { controller.selectEpisode($0) }
                )
            }
        }
    }

    private var subtitleToggle: some View {
        Button {
            controller.toggleSubtitles()
        } label: {
            Label(
                controller.subtitlesEnabled ? "Phụ đề: Bật" : "Phụ đề: Tắt",
                systemImage: controller.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(controller.subtitlesEnabled ? 0.22 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
    }

    // MARK: - Hành động

    private func close() {
        controller.teardown()
        dismiss()
    }

    private func scrollToEpisode(_ index: Int, proxy: ScrollViewProxy) {
        guard controller.episodes.contains(where: { $0.index == index }) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
