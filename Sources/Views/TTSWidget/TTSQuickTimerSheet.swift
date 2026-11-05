import SwiftUI
import UIKit

/// Bottom Sheet hiện đại điều khiển Hẹn giờ tắt và Danh sách chương cho TTS Widget.
///
/// Bố cục (1.3.712): dải thanh kéo có nút ⚙ tròn ở góc phải → header kiểu mục lục Reader (`TTSQuickTimerHeader`,
/// đồng hồ hẹn giờ trên bìa) → hàng tên chương đang phát → tab con kiểu tab Chi tiết truyện (chữ + gạch chân, badge đỏ
/// tổng số chương) → nội dung tab. Không có `NavigationStack`: sheet không đẩy trang nào, toolbar chỉ tốn chỗ.
struct TTSQuickTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var selectedTab: Int = 0 // 0: Hẹn giờ tắt, 1: Danh sách chương
    @State private var customMinutes: Double = 90.0
    private let presetMinutes = [15, 30, 45, 60, 90]

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
        .background(Color(uiColor: .systemGroupedBackground))
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
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                ttsManager.showingSettingsSheet = true
            }
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.7)))
    }

    // MARK: - Tab con (kiểu tab Chi tiết truyện, `BookDetailView.customTabBar`)

    private var subTabsBar: some View {
        let count = ttsManager.chaptersQueue.count
        return HStack(spacing: 0) {
            subTabButton(title: "Hẹn giờ tắt", badgeCount: nil, index: 0)
            subTabButton(title: "Danh sách chương", badgeCount: count > 0 ? count : nil, index: 1)
        }
    }

    /// Tên tab luôn một dòng, chật thì cắt "…"; badge giữ đủ số (`fixedSize` + ưu tiên bố cục cao hơn tên).
    private func subTabButton(title: String, badgeCount: Int?, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            triggerHaptic()
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
        }) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .bold : .medium)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
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

                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tab 1: Hẹn giờ tắt

    private var timerTabContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                presetGridSection
                customDurationSection
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private func isPresetSelected(_ mins: Int) -> Bool {
        if case .minutes(let activeMins) = ttsManager.timerMode { return activeMins == mins }
        return false
    }

    private var isEndOfChapterSelected: Bool {
        if case .endOfChapter = ttsManager.timerMode { return true }
        return false
    }

    private var presetGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chọn nhanh mốc hẹn giờ")
                .font(.footnote).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(presetMinutes, id: \.self) { mins in
                    presetButton(title: "\(mins) phút", icon: "clock.fill", isSelected: isPresetSelected(mins)) {
                        triggerHaptic()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { ttsManager.startSleepTimer(minutes: mins) }
                    }
                }
                presetButton(title: "Hết chương", icon: "bookmark.fill", isSelected: isEndOfChapterSelected) {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { ttsManager.setStopAtEndOfChapter() }
                }
            }
        }
    }

    private func presetButton(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: isSelected ? .bold : .regular)).foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title).font(.subheadline).fontWeight(isSelected ? .bold : .medium).foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .shadow(color: isSelected ? Color.accentColor.opacity(0.1) : Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var customDurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tuỳ chỉnh thời gian")
                .font(.footnote).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)

            VStack(spacing: 14) {
                HStack {
                    Button(action: { triggerHaptic(); customMinutes = max(1, customMinutes - 1) }) {
                        Image(systemName: "minus.circle.fill").font(.system(size: 26)).foregroundStyle(Color.white)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("\(Int(customMinutes))").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Color.primary)
                        Text("phút").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { triggerHaptic(); customMinutes = min(180, customMinutes + 1) }) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundStyle(Color.white)
                    }
                }
                .padding(.horizontal, 8)

                Slider(value: $customMinutes, in: 1...180, step: 1)

                Button(action: {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { ttsManager.startSleepTimer(minutes: Int(customMinutes)) }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.caption.weight(.bold))
                        Text("Hẹn giờ \(Int(customMinutes)) phút").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        }
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
