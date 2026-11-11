import SwiftUI

/// Sheet **điều khiển nhanh TTS** (1.3.806) — mở từ nửa viên đĩa nghe (`MediaDiscSheetHost`,
/// 1.3.808; nửa viên dính mép từ 1.3.858), khuôn `AudioQuickControlSheet` của nhạc: cao vừa nội dung, vuốt xuống để đóng (không nút chỉ để đóng),
/// nền kính theo cài đặt **ngăn kéo** (`DrawerGlassSheetBackground`, luôn tông tối ⇒ nội dung vẽ ở `colorScheme` tối).
///
/// Nội dung:
/// - Hàng đầu: đĩa bìa truyện xoay (`TTSCoverView`, góc chung `TTSWidgetCoverRotation` với mặt đĩa nghe) · tên
///   truyện + tên chương (`TTSWidgetBarInfoReader`, đã dịch theo phiên TTS) · ⏱ (đang hẹn ⇒ màu nhấn + thời gian còn lại;
///   chạm mở `TTSQuickTimerSheet` tab Hẹn giờ **đè lên** sheet này; đang hẹn ⇒ viên "Hủy" ngay cạnh, 1.3.816). Chạm
///   **khối bìa + tên** ⇒ mở chương đang đọc (`onOpenReader`, chỗ gọi đóng sheet rồi mới mở).
/// - Câu đang đọc + vạch tiến độ chương + "N/M" đoạn ở bên phải (1.3.817; `NowReadingBlock`, chỉ khối này vẽ lại theo từng đoạn).
/// - Chương trước · ⏪ đoạn trước · ⏯ · ⏩ đoạn kế · chương kế (`jumpToAdjacentChapter` / `skipBackward` / `pause`/`resume` /
///   `skipForward`).
/// - Hàng dưới: Mục lục (`TTSQuickTimerSheet` tab Danh sách chương) · Giọng đọc (Cài đặt TTS) · Dừng (chữ đỏ, chỗ gọi
///   dừng hẳn; 1.3.818 đổi từ "Tắt đọc").
///
/// Cài đặt TTS mở bằng state **riêng** của sheet, không qua `TTSManager.showingSettingsSheet`: cờ đó do
/// `TTSSettingsSheetHost` của `TTSQuickTimerSheet` giữ — hai host cùng nghe một cờ sẽ tranh nhau trình bày.
struct TTSQuickControlSheet: View {
    /// Chiều cao nội dung đo được — nằm ở **chỗ gọi** (nội dung sheet dựng lại mỗi lần mở).
    @Binding var height: CGFloat
    /// Chạm khối bìa + tên: mở chương đang đọc (chỗ gọi đóng sheet trước).
    let onOpenReader: () -> Void
    /// "Dừng": dừng hẳn TTS (đĩa thu lại, sheet đóng theo).
    let onStop: () -> Void

    /// App đang hoạt động ⇒ đĩa đầu sheet được xoay. Sheet trình bày từ cửa sổ riêng của đĩa nghe (1.3.808) nên không
    /// dựa `scenePhase` (không chắc lan tới cây SwiftUI của cửa sổ UIKit riêng — cùng lý do `AudioPlayerScreen`, 1.3.797).
    @State private var isAppActive = UIApplication.shared.applicationState != .background
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var info = TTSWidgetBarInfoReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()
    @State private var showingTimerSheet = false
    @State private var timerSheetTab = 0
    @State private var showingSettings = false

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                isAppActive = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                isAppActive = false
            }
            .environment(\.colorScheme, .dark)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(HeightKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - height) > 0.5 else { return }
                height = newHeight
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .appAccentTint()
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
            .presentationBackground { DrawerGlassSheetBackground() }
            .sheet(isPresented: $showingTimerSheet) {
                TTSQuickTimerSheet(initialTab: timerSheetTab)
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
            .onAppear { refreshCover() }
            .onChange(of: ttsState.snapshot.playingBookId) { _, _ in refreshCover() }
            .onChange(of: ttsState.snapshot.playingCoverUrl) { _, _ in refreshCover() }
    }

    /// Một nấc cao đúng nội dung (`.medium` trong lúc chờ đo lần đầu, tránh nháy cao 0).
    private var detents: Set<PresentationDetent> {
        height > 0 ? [.height(height)] : [.medium]
    }

    private var content: some View {
        VStack(spacing: 0) {
            headerRow
            NowReadingBlock()
                .padding(.top, 14)
            transportRow
                .padding(.top, 10)
            actionRow
                .padding(.top, 12)
        }
    }

    // MARK: - Hàng đầu

    /// Khối bìa + tên là một nút: chạm ⇒ mở chương đang đọc.
    private var headerRow: some View {
        HStack(spacing: 12) {
            Button(action: onOpenReader) {
                HStack(spacing: 12) {
                    TTSCoverView(
                        image: coverLoader.image,
                        size: 52,
                        rotationState: TTSWidgetCoverRotation.shared.state,
                        isRotating: ttsState.snapshot.isPlaying && isAppActive
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.bookTitle.isEmpty ? "Đang đọc truyện" : info.bookTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(info.chapterLine.isEmpty ? " " : info.chapterLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Mở chương đang đọc")
            HStack(spacing: 4) {
                timerButton
                if isTimerOn {
                    cancelTimerButton
                }
            }
        }
    }

    private var isTimerOn: Bool { ttsState.snapshot.timerMode != .off }

    /// ⏱: chưa hẹn ⇒ chỉ icon; đang hẹn ⇒ icon + thời gian còn lại màu nhấn (cùng chữ với viên hẹn giờ của thanh TTS).
    private var timerButton: some View {
        Button {
            openTimerSheet(tab: 0)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .semibold))
                if isTimerOn {
                    Text(ttsState.snapshot.sleepTimerBadgeText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(isTimerOn ? Color.accentColor : Color.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isTimerOn ? "Hẹn giờ tắt: còn \(ttsState.snapshot.sleepTimerBadgeText)" : "Hẹn giờ tắt")
    }

    /// "Hủy" ngay cạnh ⏱ khi đang hẹn (1.3.816, anh Bửu) — huỷ hẹn giờ tắt mà không phải mở sheet Hẹn giờ; cùng kiểu viên
    /// "Hủy" của `TTSQuickTimerHeader`.
    private var cancelTimerButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                TTSManager.shared.cancelSleepTimer()
            }
        } label: {
            Text("Hủy")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red.opacity(0.12)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hủy hẹn giờ tắt")
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Điều khiển

    /// Chương trước · đoạn trước · ⏯ · đoạn kế · chương kế (2026-11-11, anh Bửu duyệt mockup): hai nút chương ở hai đầu
    /// ngoài cùng, icon có vạch (`backward.end.fill` / `forward.end.fill`, như "bài trước / sau" của sheet nhạc) để khác nút
    /// đoạn; chia đều hàng bằng `Spacer` như `AudioTransportControls(.full)`. Không có chương đó trong hàng đợi ⇒ mờ, tắt.
    private var transportRow: some View {
        HStack(spacing: 0) {
            chapterButton(
                systemImage: "backward.end.fill",
                label: "Chương trước",
                isEnabled: info.hasPreviousChapter
            ) {
                TTSManager.shared.jumpToAdjacentChapter(forward: false)
            }
            Spacer(minLength: 0)
            transportButton(systemImage: "backward.fill", label: "Đoạn trước") {
                TTSManager.shared.skipBackward()
            }
            Spacer(minLength: 0)
            Button(action: togglePlayback) {
                Image(systemName: ttsState.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.white))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ttsState.snapshot.isPlaying ? "Tạm dừng" : "Phát tiếp")
            Spacer(minLength: 0)
            transportButton(systemImage: "forward.fill", label: "Đoạn kế") {
                TTSManager.shared.skipForward()
            }
            Spacer(minLength: 0)
            chapterButton(
                systemImage: "forward.end.fill",
                label: "Chương kế",
                isEnabled: info.hasNextChapter
            ) {
                TTSManager.shared.jumpToAdjacentChapter(forward: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Nút chương: icon 20 pt (nhỏ hơn nút đoạn 22 pt), trắng 85%, khung 44 pt.
    private func chapterButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func transportButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func togglePlayback() {
        let manager = TTSManager.shared
        if manager.isPlaying {
            manager.pause()
        } else {
            manager.resume()
        }
    }

    // MARK: - Hàng dưới

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(title: "Mục lục", systemImage: "list.bullet", tint: .primary) { openTimerSheet(tab: 1) }
            actionButton(title: "Giọng đọc", systemImage: "waveform", tint: .primary) { showingSettings = true }
            actionButton(title: "Dừng", systemImage: "stop.circle", tint: Color.red) { onStop() }
        }
        .buttonStyle(.plain)
    }

    /// Viên thuốc cao 38 pt (chuẩn nút capsule cùng hàng), nền mờ theo màu chữ — không tô nền đặc màu nhấn.
    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.primary.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
    }

    private func openTimerSheet(tab: Int) {
        timerSheetTab = tab
        showingTimerSheet = true
    }

    @ViewBuilder
    private var settingsSheet: some View {
        if let container = MediaDiscWindowManager.shared.modelContainer {
            TTSSettingsSheet()
                .modelContainer(container)
        } else {
            TTSSettingsSheet()
        }
    }

    private func refreshCover() {
        coverLoader.load(
            bookId: ttsState.snapshot.playingBookId,
            coverURL: ttsState.snapshot.playingCoverUrl
        )
    }

    // MARK: - Lồng (một type chính mỗi file)

    /// Câu đang đọc + vạch tiến độ chương. View riêng giữ `TTSQuickControlNowReading` để chỉ khối này vẽ lại theo đoạn.
    private struct NowReadingBlock: View {
        @StateObject private var reader = TTSQuickControlNowReading()

        var body: some View {
            let snapshot = reader.snapshot
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.sentence.isEmpty ? " " : "“\(snapshot.sentence)”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView(value: snapshot.fraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text(" ")
                    Spacer(minLength: 8)
                    Text(snapshot.total > 0 && snapshot.position > 0 ? "\(snapshot.position)/\(snapshot.total)" : " ")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}
