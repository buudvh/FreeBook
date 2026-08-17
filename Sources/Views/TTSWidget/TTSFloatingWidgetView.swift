import SwiftUI
import UIKit
import SwiftData

/// Đối tượng quản lý trạng thái góc quay của ảnh bìa trên widget TTS.
/// Có vòng đời dài hạn do FloatingWidgetContainerViewController sở hữu, không bị mất góc khi view root tái tạo.
@MainActor
public final class CoverRotationState: ObservableObject {
    private struct RotationData: Sendable, Equatable {
        let accumulatedAngle: Double
        let playStartDate: Date?

        init(accumulatedAngle: Double = 0.0, playStartDate: Date? = nil) {
            self.accumulatedAngle = accumulatedAngle
            self.playStartDate = playStartDate
        }
    }

    private static let rotationSpeed: Double = 24.0 // 24 độ/giây = 15 giây / 1 vòng quay 360°
    @Published private var data: RotationData = RotationData()

    public func syncPlaybackState(isPlaying: Bool, at date: Date = Date()) {
        if isPlaying {
            if data.playStartDate == nil {
                data = RotationData(accumulatedAngle: data.accumulatedAngle, playStartDate: date)
            }
        } else {
            if let start = data.playStartDate {
                let elapsed = max(0, date.timeIntervalSince(start))
                let newAccumulated = (data.accumulatedAngle + elapsed * Self.rotationSpeed).truncatingRemainder(dividingBy: 360.0)
                data = RotationData(accumulatedAngle: newAccumulated, playStartDate: nil)
            }
        }
    }

    public func currentAngle(at date: Date, isPlaying: Bool) -> Double {
        guard isPlaying, let start = data.playStartDate else {
            return data.accumulatedAngle
        }
        let elapsed = max(0, date.timeIntervalSince(start))
        return (data.accumulatedAngle + elapsed * Self.rotationSpeed).truncatingRemainder(dividingBy: 360.0)
    }

    public func resetAngle(isPlaying: Bool, at date: Date = Date()) {
        data = RotationData(accumulatedAngle: 0.0, playStartDate: isPlaying ? date : nil)
    }
}

/// View nội dung hiển thị bên trong bounded container của widget TTS.
struct TTSWidgetContentView: View {
    @ObservedObject var viewModel: FloatingWidgetViewModel
    @ObservedObject var rotationState: CoverRotationState
    @ObservedObject private var ttsManager = TTSManager.shared
    @ObservedObject private var windowManager = TTSFloatingWidgetWindowManager.shared
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()

    var body: some View {
        let shouldAnimateCover = ttsManager.isPlaying && windowManager.isWidgetActuallyVisible

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimateCover)) { context in
            let displayAngle = rotationState.currentAngle(at: context.date, isPlaying: ttsManager.isPlaying)

            Group {
                if viewModel.mode == .peeking {
                    TTSWidgetPeekCircleView(
                        coverImage: coverLoader.image,
                        rotationAngle: displayAngle
                    )
                } else {
                    TTSWidgetCapsuleView(
                        coverImage: coverLoader.image,
                        rotationAngle: displayAngle,
                        viewModel: viewModel,
                        ttsState: ttsState
                    )
                }
            }
        }
        .sheet(isPresented: $ttsManager.showingSettingsSheet) {
            if let container = TTSFloatingWidgetWindowManager.shared.modelContainer {
                TTSSettingsSheet()
                    .modelContainer(container)
            } else {
                TTSSettingsSheet()
            }
        }
        .onAppear {
            rotationState.syncPlaybackState(isPlaying: ttsManager.isPlaying, at: Date())
            refreshCover()
        }
        .onChange(of: ttsState.snapshot.playingBookId) { _, _ in
            refreshCover()
        }
        .onChange(of: ttsState.snapshot.playingCoverUrl) { _, _ in
            refreshCover()
        }
    }

    private func refreshCover() {
        coverLoader.load(
            bookId: ttsState.snapshot.playingBookId,
            coverURL: ttsState.snapshot.playingCoverUrl
        )
    }
}

/// Giao diện dạng capsule mở rộng (revealed mode).
struct TTSWidgetCapsuleView: View {
    let coverImage: UIImage?
    let rotationAngle: Double
    @ObservedObject var viewModel: FloatingWidgetViewModel
    @ObservedObject var ttsState: TTSWidgetStateReader
    private let ttsManager = TTSManager.shared

    @State private var showingQuickTimerSheet = false

    var body: some View {
        VStack(spacing: 4) {
            if ttsState.snapshot.timerMode != .off {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .bold))
                    Text(ttsState.snapshot.sleepTimerBadgeText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange))
                .shadow(color: .orange.opacity(0.4), radius: 4, x: 0, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Button(action: openCurrentChapter) {
                    TTSCoverView(
                        image: coverImage,
                        size: 40,
                        rotationAngle: rotationAngle
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mở chương đang đọc")

                Button(action: {
                    viewModel.cancelTasks()
                    viewModel.disableAutoHide = true
                    showingQuickTimerSheet = true
                }) {
                    Image(systemName: ttsState.snapshot.timerMode != .off ? "timer" : "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ttsState.snapshot.timerMode != .off ? Color.orange : Color.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ttsState.snapshot.timerMode != .off ? Color.orange.opacity(0.18) : Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hẹn giờ và cài đặt")

                Button(action: togglePlayback) {
                    Image(systemName: ttsState.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ttsState.snapshot.isPlaying ? "Tạm dừng" : "Phát tiếp")

                Button(action: skipForward) {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tua tới 30 giây")

                Button(action: stopTTS) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dừng đọc")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 11, x: 0, y: 5)
        }
        .sheet(isPresented: $showingQuickTimerSheet, onDismiss: {
            viewModel.disableAutoHide = false
            viewModel.startAutoHideTimer()
        }) {
            TTSQuickTimerSheet()
        }
    }

    private func openCurrentChapter() {
        NotificationCenter.default.post(
            name: NSNotification.Name("openCurrentlyPlayingReader"),
            object: nil
        )
        viewModel.hide()
    }

    private func togglePlayback() {
        if ttsState.snapshot.isPlaying {
            ttsManager.pause()
        } else {
            ttsManager.resume()
        }
        viewModel.startAutoHideTimer()
    }

    private func skipForward() {
        ttsManager.skipForward()
        viewModel.startAutoHideTimer()
    }

    private func stopTTS() {
        ttsManager.stop()
    }
}

/// Giao diện dạng đĩa tròn thu nhỏ (peeking mode).
struct TTSWidgetPeekCircleView: View {
    let coverImage: UIImage?
    let rotationAngle: Double

    var body: some View {
        TTSCoverView(
            image: coverImage,
            size: 40,
            rotationAngle: rotationAngle
        )
        .padding(6)
        .frame(width: 52, height: 52)
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 11, x: 0, y: 5)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mở điều khiển TTS")
        .accessibilityAddTraits(.isButton)
    }
}

/// View hiển thị ảnh bìa dạng tròn có hiệu ứng xoay đĩa than mượt mà.
struct TTSCoverView: View {
    let image: UIImage?
    let size: CGFloat
    var rotationAngle: Double = 0.0

    var body: some View {
        coverImage
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotationAngle))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var coverImage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.7), .purple.opacity(0.6), .black.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "book.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}

/// Lớp nạp ảnh bìa cho widget TTS.
@MainActor
final class TTSCoverImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    func load(bookId: String, coverURL: String) {
        guard !bookId.isEmpty else {
            image = nil
            return
        }

        if let cached = ImageCacheManager.shared.loadLocalCover(for: bookId) {
            image = cached
            return
        }

        guard !coverURL.isEmpty else {
            image = nil
            return
        }

        ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverURL, bookId: bookId) { [weak self] downloaded in
            Task { @MainActor in
                self?.image = downloaded
            }
        }
    }
}
