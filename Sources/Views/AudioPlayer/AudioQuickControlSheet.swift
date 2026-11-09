import SwiftUI

/// Sheet **điều khiển nhanh** của trình nghe âm thanh — mở từ đĩa nghe (góc dưới phải hoặc ô giữa thanh tab, 1.3.808 / 1.3.812 — `MediaDiscSheetHost`),
/// cao vừa nội dung, vuốt xuống để đóng (không nút chỉ để đóng). Nội dung:
/// - Hàng đầu: đĩa bìa tròn xoay (`AudioRotatingCover`, cùng góc `AudioCoverRotation` với đĩa góc dưới / trang Đĩa) · tên bài +
///   "nghệ sĩ · album" · ⏱ hẹn giờ tắt (sheet `MediaSleepTimerSheet` mở **đè lên** sheet này; đang hẹn ⇒ màu nhấn kèm thời
///   gian còn lại). Chạm **khối bìa + tên** ⇒ mở màn nghe đầy đủ ở trang Đĩa (1.3.808 bỏ nút ⤢ trùng việc).
/// - Một dòng lời đang hát (`AudioCurrentLyricLine`, chỉ có chữ khi lời có mốc giờ) hoặc chữ lỗi của bài.
/// - Thanh tua (`AudioPlayerSeekRow`) + cụm nút Xáo · ⏮ · ⏯ · ⏭ · Lặp (`AudioTransportControls(.full)`) của màn nghe.
/// - Hàng dưới: Danh sách / Lời (mở màn nghe ở trang đó) · Tắt nhạc.
///
/// Nền là kính theo Cài đặt › Chung › Giao diện **của ngăn kéo menu** (`DrawerGlassSheetBackground`, `GlassChromeSettings.drawer*` — cùng kiểu ngăn kéo
/// `…` của Reader, luôn tông tối) ⇒ nội dung vẽ ở `colorScheme` tối: chữ `.primary` / `.secondary`, còn thanh tua và cụm nút
/// dùng lại của màn nghe (vốn tông trắng trên nền tối). Điểm nhấn = màu nhấn app (`.appAccentTint()` — sheet nằm ở cửa sổ
/// riêng của đĩa, không trong `MainTabView`).
///
/// Chỉ mở khi có album (`AudioMiniPlayerState.isActive`) ⇒ đọc thẳng `AudioPlaybackSession.shared`. Album 18+ lúc công tắc
/// NSFW tắt ⇒ tên "Đang phát", không bìa, không lời. Mở màn nghe / tắt nhạc do chỗ gọi làm (đóng sheet trước rồi mới trình
/// bày màn nghe — trình bày từ sheet đang đóng thì UIKit đóng luôn màn mới).
struct AudioQuickControlSheet: View {
    /// Chiều cao nội dung đo được — nằm ở **chỗ gọi** (nội dung sheet dựng lại mỗi lần mở, như `FittedSheetDetentModifier`).
    @Binding var height: CGFloat
    /// Mở màn nghe đầy đủ ở trang chỉ định.
    let onOpenScreen: (AudioPlayerPage) -> Void
    /// "Tắt nhạc": dừng hẳn trình nghe.
    let onStop: () -> Void

    /// App đang hoạt động ⇒ đĩa đầu sheet được xoay. Sheet trình bày từ cửa sổ riêng của đĩa nghe (1.3.808) nên không
    /// dựa `scenePhase` (không chắc lan tới cây SwiftUI của cửa sổ UIKit riêng — cùng lý do `AudioPlayerScreen`, 1.3.797).
    @State private var isAppActive = UIApplication.shared.applicationState != .background
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    @State private var showingSleepTimer = false

    private var session: AudioPlaybackSession { .shared }

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
            .sheet(isPresented: $showingSleepTimer) {
                MediaSleepTimerSheet(timer: session.sleepTimer)
            }
    }

    /// Một nấc cao đúng nội dung (`.medium` trong lúc chờ đo lần đầu, tránh nháy cao 0).
    private var detents: Set<PresentationDetent> {
        height > 0 ? [.height(height)] : [.medium]
    }

    private var content: some View {
        VStack(spacing: 0) {
            headerRow
            statusLine
                .padding(.top, 12)
            AudioPlayerSeekRow()
                .padding(.top, 6)
            AudioTransportControls(style: .full)
                .padding(.top, 2)
            actionRow
                .padding(.top, 10)
        }
    }

    // MARK: - Hàng đầu

    private var isConcealed: Bool { session.isNsfw && !includeNsfw }

    private var title: String {
        if isConcealed { return "Đang phát" }
        if let track = session.currentTrack { return track.displayTitle }
        return session.albumTitle.isEmpty ? "Đang tải…" : session.albumTitle
    }

    private var subtitle: String {
        if isConcealed { return session.isPlaying ? "" : "Đã dừng" }
        return [session.currentArtist, session.albumTitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Host của album — `Referer` khi tải bìa (như màn nghe).
    private var referer: String? {
        ExtensionHostResolver.nonEmpty(session.request?.host) ?? ExtensionHostResolver.nonEmpty(session.bookHost)
    }

    /// Khối bìa + tên là một nút: chạm ⇒ màn nghe đầy đủ, trang Đĩa.
    private var headerRow: some View {
        HStack(spacing: 12) {
            Button {
                onOpenScreen(.disc)
            } label: {
                HStack(spacing: 12) {
                    AudioRotatingCover(
                        coverUrl: session.coverUrl,
                        referer: referer,
                        size: 52,
                        isRotating: session.isPlaying && isAppActive,
                        isConcealed: isConcealed
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle.isEmpty ? " " : subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Mở màn nghe")
            sleepTimerButton
        }
    }

    /// ⏱: chưa hẹn ⇒ chỉ icon; đang hẹn ⇒ icon + thời gian còn lại (view lá `MediaSleepTimerCountdownText`) màu nhấn.
    private var sleepTimerButton: some View {
        let timer = session.sleepTimer
        return Button {
            showingSleepTimer = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .semibold))
                if timer.isActive {
                    MediaSleepTimerCountdownText(timer: timer)
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(timer.isActive ? Color.accentColor : Color.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timer.modeSummary.map { "Hẹn giờ tắt: \($0)" } ?? "Hẹn giờ tắt")
    }

    // MARK: - Lời / lỗi

    /// Luôn giữ chỗ một dòng (như trang Đĩa) để chiều cao sheet không nhảy khi lời xuất hiện / biến mất.
    @ViewBuilder
    private var statusLine: some View {
        if case .failed(let message, _) = session.phase {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        } else if isConcealed {
            Text(" ")
                .font(.subheadline.weight(.medium))
                .accessibilityHidden(true)
        } else {
            AudioCurrentLyricLine()
        }
    }

    // MARK: - Hàng dưới

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(title: "Danh sách", systemImage: "list.bullet") { onOpenScreen(.playlist) }
            actionButton(title: "Lời", systemImage: "quote.bubble") { onOpenScreen(.lyrics) }
            actionButton(title: "Tắt nhạc", systemImage: "stop.circle") { onStop() }
        }
        .buttonStyle(.plain)
    }

    /// Viên thuốc cao 38 pt (chuẩn nút capsule cùng hàng), nền mờ theo màu chữ — không tô nền đặc màu nhấn.
    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.primary.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
        }
    }

    // MARK: - Lồng (một type chính mỗi file)

    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}
