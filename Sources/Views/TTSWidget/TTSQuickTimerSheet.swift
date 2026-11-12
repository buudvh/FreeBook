import SwiftUI
import UIKit

/// Bottom Sheet hiện đại điều khiển Hẹn giờ tắt và Danh sách chương cho TTS Widget.
///
/// Bố cục (1.3.712): dải thanh kéo có nút ⚙ tròn ở góc phải → header kiểu mục lục Reader (`TTSQuickTimerHeader`,
/// đồng hồ hẹn giờ trên bìa) → hàng tên chương đang phát → tab con ô viên thuốc có icon (kiểu cũ, 1.3.713; badge đỏ
/// tổng số chương trong ô sau chữ) → nội dung tab. Không có `NavigationStack`: sheet không đẩy trang nào. Nút ⚙ mở
/// Cài đặt TTS đè lên sheet này (`TTSSettingsSheetHost`).
struct TTSQuickTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var selectedTab: Int // 0: Hẹn giờ tắt, 1: Danh sách chương
    @State private var customMinutes: Double = 90.0

    /// `initialTab` 1 ⇒ mở thẳng tab Danh sách chương (nút "Mục lục" của `TTSQuickControlSheet`, 1.3.806).
    init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: initialTab)
    }

    /// Dải trên cùng: thanh kéo của sheet hệ thống + nút ⚙ (vòng 28pt, vùng chạm 38×38) — header bắt đầu ngay dưới
    /// nên nút không lấn bề ngang của tên truyện.
    private static let topBandHeight: CGFloat = 36

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, Self.topBandHeight)
            playingChapterMarqueeRow
                .padding(.horizontal, 16).padding(.bottom, 10)
            subTabsBar
                .padding(.bottom, 10)
            TabView(selection: $selectedTab) {
                timerTabContent
                    .tag(0)
                TTSQuickTimerChapterList(ttsManager: ttsManager)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Không có nút ✕ (1.3.641): vuốt xuống để đóng. ⚙ là nút duy nhất, ở góc phải dải thanh kéo.
        .overlay(alignment: .topTrailing) { settingsButton }
        // Cài đặt TTS mở **đè lên** sheet này (1.3.713): một lần trượt lên, không chờ sheet Hẹn giờ đóng; vuốt đóng
        // Cài đặt là về lại Hẹn giờ. Trước đây: `dismiss()` → chờ cứng 0,3 s → mở từ widget ⇒ chậm thấy rõ.
        .modifier(TTSSettingsSheetHost())
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
        // Sheet của widget TTS (cửa sổ riêng): gắn lại màu nhấn người dùng chọn cho nút / thanh / ô đang chọn.
        .appAccentTint()
        .onAppear {
            if case .minutes(let mins) = ttsManager.timerMode { customMinutes = Double(mins) }
        }
    }

    // MARK: - Header

    private var header: some View {
        let packageId = ttsManager.extensionInfo?.packageId ?? ""
        // Viên nguồn như header Reader: tên + icon của tiện ích đã cài; tiện ích đã gỡ ⇒ tên nguồn đã lưu của phiên TTS.
        let ext: Extension? = packageId.isEmpty
            ? nil
            : ExtensionLibraryRepository.shared.installed.first(where: { $0.packageId == packageId })
        let extName = ext?.name ?? ""
        return TTSQuickTimerHeader(
            bookId: ttsManager.playingBookId,
            coverUrl: ttsManager.playingCoverUrl,
            extensionPackageId: packageId,
            title: ttsManager.displayedBookTitle,
            author: ttsManager.displayedAuthor,
            sourceName: extName.isEmpty ? ttsManager.playingBookSourceName : extName,
            sourceLocalPath: ext?.localPath ?? "",
            sourceIconUrl: ext?.iconUrl,
            timerMode: ttsManager.timerMode,
            timerBadgeText: ttsManager.sleepTimerBadgeText,
            onOpenReader: {
                dismiss()
                NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
            },
            onCancelTimer: {
                triggerHaptic()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { ttsManager.cancelSleepTimer() }
            }
        )
    }

    /// Nút ⚙ dạng chấm tròn (như badge) ở góc phải dải thanh kéo; icon 17pt nửa đậm như mọi icon header.
    private var settingsButton: some View {
        Button(action: {
            ttsManager.showingSettingsSheet = true
        }) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(uiColor: .tertiarySystemFill)))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cài đặt giọng đọc và tốc độ")
        .padding(.trailing, 10)
    }

    /// Hàng tên chương đang phát với hiệu ứng Marquee
    private var playingChapterMarqueeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tint)
            MarqueeText(text: ttsManager.displayedChapterTitle)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppGlassSheetModifier.rowFill))
    }

    // MARK: - Tab con (ô viên thuốc có icon như trước 1.3.712)

    private var subTabsBar: some View {
        let count = ttsManager.chaptersQueue.count
        return HStack(spacing: 8) {
            subTabButton(title: "Hẹn giờ tắt", icon: "timer", badgeCount: nil, index: 0)
            subTabButton(title: "Danh sách chương", icon: "list.bullet", badgeCount: count > 0 ? count : nil, index: 1)
        }
        .padding(.horizontal, 16)
    }

    /// Tên tab luôn một dòng, chật thì cắt "…"; badge đỏ tổng số chương nằm trong ô ngay sau chữ, giữ đủ số
    /// (`fixedSize` + ưu tiên bố cục cao hơn tên).
    private func subTabButton(title: String, icon: String, badgeCount: Int?, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            triggerHaptic()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { selectedTab = index }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: isSelected ? .bold : .medium))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let badgeCount {
                    Text(verbatim: String(badgeCount))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Hẹn giờ tắt

    /// Lưới mốc + tuỳ chỉnh dùng chung với hẹn giờ của phim / nhạc (`SleepTimerOptionsView`); TTS giữ ô "Hết chương".
    private var timerTabContent: some View {
        SleepTimerOptionsView(
            selectedMinutes: selectedPresetMinutes,
            endOfItemTitle: "Hết chương",
            endOfItemIcon: "bookmark.fill",
            isEndOfItemSelected: isEndOfChapterSelected,
            customMinutes: $customMinutes,
            onSelectMinutes: { ttsManager.startSleepTimer(minutes: $0) },
            onSelectEndOfItem: { ttsManager.setStopAtEndOfChapter() }
        )
    }

    private var selectedPresetMinutes: Int? {
        if case .minutes(let activeMins) = ttsManager.timerMode { return activeMins }
        return nil
    }

    private var isEndOfChapterSelected: Bool {
        if case .endOfChapter = ttsManager.timerMode { return true }
        return false
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Marquee Helper

    struct MarqueeText: View {
        let text: String

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(height: 18)
        }
    }
}
