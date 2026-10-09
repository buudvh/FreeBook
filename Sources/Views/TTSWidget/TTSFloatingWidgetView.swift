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

    static let rotationSpeed: Double = 24.0 // 24 độ/giây = 15 giây / 1 vòng quay 360°
    // Không @Published: góc được Core Animation nội suy (TTSRotatingCoverView), view chỉ đọc lúc gắn animation.
    private var data: RotationData = RotationData()
    /// Tăng mỗi lần `resetAngle` (đổi sách) để TTSRotatingCoverView chạy lại animation từ góc 0.
    @Published public private(set) var resetGeneration: Int = 0

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

    /// Góc hiện tại (độ) theo trạng thái phát mà model đang giữ (`playStartDate` chỉ khác nil khi đang phát).
    public func currentAngle(at date: Date = Date()) -> Double {
        guard let start = data.playStartDate else {
            return data.accumulatedAngle
        }
        let elapsed = max(0, date.timeIntervalSince(start))
        return (data.accumulatedAngle + elapsed * Self.rotationSpeed).truncatingRemainder(dividingBy: 360.0)
    }

    public func resetAngle(isPlaying: Bool, at date: Date = Date()) {
        data = RotationData(accumulatedAngle: 0.0, playStartDate: isPlaying ? date : nil)
        resetGeneration &+= 1
    }
}

/// View nội dung hiển thị bên trong bounded container của widget TTS.
struct TTSWidgetContentView: View {
    @ObservedObject var viewModel: FloatingWidgetViewModel
    @ObservedObject var rotationState: CoverRotationState
    @ObservedObject private var windowManager = TTSFloatingWidgetWindowManager.shared
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var ttsPresentation = TTSRootPresentationReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()

    var body: some View {
        // Xoay ảnh bìa do Core Animation chạy (TTSRotatingCoverView); body chỉ đánh giá lại khi cờ này đổi.
        let shouldAnimateCover = ttsState.snapshot.isPlaying && windowManager.isWidgetActuallyVisible

        Group {
            if viewModel.mode == .peeking {
                TTSWidgetPeekCircleView(
                    coverImage: coverLoader.image,
                    rotationState: rotationState,
                    isCoverRotating: shouldAnimateCover
                )
            } else {
                TTSWidgetCapsuleView(
                    coverImage: coverLoader.image,
                    rotationState: rotationState,
                    isCoverRotating: shouldAnimateCover,
                    viewModel: viewModel,
                    ttsState: ttsState
                )
            }
        }
        // `ttsPresentation` chỉ làm mới view khi cờ sheet đổi (không observe cả TTSManager); get đọc thẳng manager
        // để sau khi vuốt đóng (set false) không còn đọc giá trị cũ của snapshot.
        .sheet(isPresented: Binding(
            get: { TTSManager.shared.showingSettingsSheet },
            set: { TTSManager.shared.showingSettingsSheet = $0 }
        )) {
            if let container = TTSFloatingWidgetWindowManager.shared.modelContainer {
                TTSSettingsSheet()
                    .modelContainer(container)
            } else {
                TTSSettingsSheet()
            }
        }
        .onAppear {
            rotationState.syncPlaybackState(isPlaying: ttsState.snapshot.isPlaying, at: Date())
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
    let rotationState: CoverRotationState
    let isCoverRotating: Bool
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
                .background(Capsule().fill(Color(white: 0.22)))
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                Button(action: openCurrentChapter) {
                    TTSCoverView(
                        image: coverImage,
                        size: 40,
                        rotationState: rotationState,
                        isRotating: isCoverRotating
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
                        .foregroundStyle(ttsState.snapshot.timerMode != .off ? Color.white : Color.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ttsState.snapshot.timerMode != .off ? Color.white.opacity(0.18) : Color.primary.opacity(0.09)))
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
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tua tới đoạn tiếp theo")

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
            // Shadow gắn vào nền tĩnh, không phủ lên ảnh bìa đang xoay.
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.28), radius: 11, x: 0, y: 5)
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
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
    let rotationState: CoverRotationState
    let isCoverRotating: Bool

    var body: some View {
        TTSCoverView(
            image: coverImage,
            size: 40,
            rotationState: rotationState,
            isRotating: isCoverRotating
        )
        .padding(6)
        .frame(width: 52, height: 52)
        // Shadow gắn vào nền tĩnh, không phủ lên ảnh bìa đang xoay.
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.28), radius: 11, x: 0, y: 5)
        )
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mở điều khiển TTS")
        .accessibilityAddTraits(.isButton)
    }
}

/// View hiển thị ảnh bìa dạng tròn có hiệu ứng xoay đĩa than (Core Animation, xem TTSRotatingCoverView).
struct TTSCoverView: View {
    let image: UIImage?
    let size: CGFloat
    let rotationState: CoverRotationState
    let isRotating: Bool

    var body: some View {
        TTSRotatingCoverView(
            image: image,
            size: size,
            rotationState: rotationState,
            isRotating: isRotating
        )
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        .contentShape(Rectangle())
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
