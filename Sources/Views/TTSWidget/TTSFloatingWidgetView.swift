import SwiftUI
import UIKit

/// View nội dung hiển thị bên trong bounded container của widget TTS.
struct TTSWidgetContentView: View {
    @ObservedObject var viewModel: FloatingWidgetViewModel
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()

    var body: some View {
        Group {
            if viewModel.mode == .peeking {
                TTSWidgetPeekCircleView(coverImage: coverLoader.image)
            } else {
                TTSWidgetCapsuleView(
                    coverImage: coverLoader.image,
                    viewModel: viewModel,
                    ttsState: ttsState
                )
            }
        }
        .onAppear {
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
    @ObservedObject var viewModel: FloatingWidgetViewModel
    @ObservedObject var ttsState: TTSWidgetStateReader
    private let ttsManager = TTSManager.shared

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
                        size: 40
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mở chương đang đọc")

                Button(action: openTimerMenu) {
                    Image(systemName: ttsState.snapshot.timerMode != .off ? "timer" : "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ttsState.snapshot.timerMode != .off ? Color.orange : Color.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(ttsState.snapshot.timerMode != .off ? Color.orange.opacity(0.18) : Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cài đặt và Hẹn giờ TTS")

                Button(action: togglePlayback) {
                    Image(systemName: ttsState.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ttsState.snapshot.isPlaying ? "Tạm dừng đọc" : "Tiếp tục đọc")

                Button(action: skipForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đọc đoạn tiếp theo")

                Button(action: stopTTS) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng TTS")
            }
            .padding(.horizontal, 8)
            .frame(width: 212, height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 6)
        }
    }

    private func openCurrentChapter() {
        NotificationCenter.default.post(
            name: NSNotification.Name("openCurrentlyPlayingReader"),
            object: nil
        )
        viewModel.hide()
    }

    private func openTimerMenu() {
        viewModel.cancelTasks()
        viewModel.disableAutoHide = true

        TTSFloatingWidgetActionPresenter.presentTimerMenu(
            viewModel: viewModel,
            currentTimerMode: ttsState.snapshot.timerMode,
            onSelectTimer: { minutes in
                ttsManager.startSleepTimer(minutes: minutes)
            },
            onStopAtEndOfChapter: {
                ttsManager.setStopAtEndOfChapter()
            },
            onCustomMinutes: {
                TTSFloatingWidgetActionPresenter.presentCustomMinutesAlert(
                    viewModel: viewModel,
                    onConfirm: { minutes in
                        ttsManager.startSleepTimer(minutes: minutes)
                    }
                )
            },
            onCancelTimer: {
                ttsManager.cancelSleepTimer()
            },
            onOpenSettings: {
                ttsManager.showingSettingsSheet = true
            }
        )
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

    var body: some View {
        TTSCoverView(
            image: coverImage,
            size: 40
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

/// View hiển thị ảnh bìa dạng tròn.
struct TTSCoverView: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        coverImage
            .frame(width: size, height: size)
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

    private struct Key: Equatable {
        let bookId: String
        let coverURL: String
    }

    private var key: Key?
    private var generation: UInt = 0

    func load(bookId: String, coverURL: String) {
        let newKey = Key(bookId: bookId, coverURL: coverURL)
        guard newKey != key else { return }

        key = newKey
        generation &+= 1
        let expectedGeneration = generation

        if !bookId.isEmpty, let localImage = ImageCacheManager.shared.loadLocalCover(for: bookId) {
            image = localImage
            return
        }

        image = nil
        guard !bookId.isEmpty, !coverURL.isEmpty else { return }

        ImageCacheManager.shared.downloadAndSaveCover(urlStr: coverURL, bookId: bookId) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == expectedGeneration,
                      self.key == newKey else { return }
                self.image = image
            }
        }
    }
}

/// Điều phối hiển thị menu hẹn giờ và hộp thoại alert nhập số phút trên key window của ứng dụng.
@MainActor
enum TTSFloatingWidgetActionPresenter {
    static func findTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first(where: { !($0 is FloatingWidgetUIWindow) }),
              let rootVC = keyWindow.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    static func presentTimerMenu(
        viewModel: FloatingWidgetViewModel,
        currentTimerMode: TTSManager.SleepTimerMode,
        onSelectTimer: @escaping (Int) -> Void,
        onStopAtEndOfChapter: @escaping () -> Void,
        onCustomMinutes: @escaping () -> Void,
        onCancelTimer: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        guard let topVC = findTopViewController() else {
            finalizeDismissal(viewModel: viewModel)
            return
        }

        // Tạm ẩn floating window để Action Sheet trên main key window không bị che bên dưới
        TTSFloatingWidgetWindowManager.shared.temporarilySuppressWindow()

        let alert = UIAlertController(
            title: "⏱️ Hẹn giờ & Cài đặt TTS",
            message: nil,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "⏱️ 15 phút", style: .default) { _ in
            onSelectTimer(15)
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "⏱️ 30 phút", style: .default) { _ in
            onSelectTimer(30)
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "⏱️ 45 phút", style: .default) { _ in
            onSelectTimer(45)
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "⏱️ 60 phút", style: .default) { _ in
            onSelectTimer(60)
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "📖 Hết chương hiện tại", style: .default) { _ in
            onStopAtEndOfChapter()
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "✏️ Tùy chỉnh số phút...", style: .default) { _ in
            onCustomMinutes()
        })

        if currentTimerMode != .off {
            alert.addAction(UIAlertAction(title: "❌ Tắt hẹn giờ", style: .destructive) { _ in
                onCancelTimer()
                finalizeDismissal(viewModel: viewModel)
            })
        }

        alert.addAction(UIAlertAction(title: "⚙️ Bảng cài đặt giọng đọc", style: .default) { _ in
            onOpenSettings()
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in
            finalizeDismissal(viewModel: viewModel)
        })

        if let popover = alert.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topVC.present(alert, animated: true)
    }

    static func presentCustomMinutesAlert(
        viewModel: FloatingWidgetViewModel,
        onConfirm: @escaping (Int) -> Void
    ) {
        guard let topVC = findTopViewController() else {
            finalizeDismissal(viewModel: viewModel)
            return
        }

        // Tạm ẩn floating window để Alert + Keyboard trên main key window không bị che bên dưới
        TTSFloatingWidgetWindowManager.shared.temporarilySuppressWindow()

        let alert = UIAlertController(
            title: "✏️ Nhập số phút hẹn giờ",
            message: "Nhập số phút tự động tạm dừng nghe truyện (ví dụ: 90).",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.placeholder = "Số phút (ví dụ: 90)"
            textField.text = "90"
        }

        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel) { _ in
            finalizeDismissal(viewModel: viewModel)
        })
        alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { [weak alert] _ in
            if let text = alert?.textFields?.first?.text, let mins = Int(text), mins > 0 {
                onConfirm(mins)
            }
            finalizeDismissal(viewModel: viewModel)
        })

        topVC.present(alert, animated: true)
    }

    private static func finalizeDismissal(viewModel: FloatingWidgetViewModel) {
        viewModel.disableAutoHide = false
        TTSFloatingWidgetWindowManager.shared.restoreWindowIfNeeded()
        // Chỉ khởi động lại auto-hide timer nếu widget vẫn đang đủ điều kiện hiển thị và ở trạng thái .revealed
        if TTSManager.shared.showFloatingWidget && viewModel.mode == .revealed {
            viewModel.startAutoHideTimer()
        }
    }
}

/// Facade tương thích ngược nếu view được nhúng trực tiếp ở nơi khác.
struct TTSFloatingWidgetView: View {
    @StateObject private var viewModel = FloatingWidgetViewModel()

    var body: some View {
        TTSWidgetContentView(viewModel: viewModel)
    }
}
