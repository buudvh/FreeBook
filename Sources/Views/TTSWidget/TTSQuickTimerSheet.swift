import SwiftUI
import UIKit

/// Bottom Sheet hiện đại điều khiển Hẹn giờ tắt và Danh sách chương cho TTS Widget.
struct TTSQuickTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ttsManager = TTSManager.shared
    @StateObject private var coverLoader = TTSCoverImageLoader()
    @State private var selectedTab: Int = 0 // 0: Hẹn giờ tắt, 1: Danh sách chương
    @State private var customMinutes: Double = 90.0
    private let presetMinutes = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                playingBookHeaderCard
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
                playingChapterMarqueeRow
                    .padding(.horizontal, 16).padding(.bottom, 10)
                subTabsBar
                    .padding(.horizontal, 16).padding(.bottom, 10)
                TabView(selection: $selectedTab) {
                    timerTabContent
                        .tag(0)
                    chapterListTabContent
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            ttsManager.showingSettingsSheet = true
                        }
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Cài đặt giọng đọc và tốc độ")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if case .minutes(let mins) = ttsManager.timerMode { customMinutes = Double(mins) }
            coverLoader.load(bookId: ttsManager.playingBookId, coverURL: ttsManager.playingCoverUrl)
        }
        .onChange(of: ttsManager.playingBookId) { _, newBookId in
            coverLoader.load(bookId: newBookId, coverURL: ttsManager.playingCoverUrl)
        }
    }

    // MARK: - Subviews

    /// Card thông tin truyện đang phát
    private var playingBookHeaderCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: {
                dismiss()
                NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
            }) {
                Group {
                    if let img = coverLoader.image {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color.gray.opacity(0.5), Color.black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "book.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white.opacity(0.88))
                        }
                    }
                }
                .frame(width: 58, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ttsManager.displayedBookTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !ttsManager.chaptersQueue.isEmpty {
                        Text("\(ttsManager.chaptersQueue.count) chương")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    if !ttsManager.displayedAuthor.isEmpty {
                        Text(ttsManager.displayedAuthor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                timerSlotRow
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
    }

    /// Slot bộ đếm giờ cố định 22pt để tránh giật/nhảy layout
    private var timerSlotRow: some View {
        HStack(spacing: 8) {
            if ttsManager.timerMode != .off {
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    if case .endOfChapter = ttsManager.timerMode {
                        Text("Hết chương").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text(ttsManager.sleepTimerBadgeText.isEmpty ? "\(Int(customMinutes))m" : ttsManager.sleepTimerBadgeText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color(white: 0.22)))

                Button(action: {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { ttsManager.cancelSleepTimer() }
                }) {
                    Text("Hủy").font(.system(size: 11, weight: .bold)).foregroundStyle(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.red.opacity(0.12)))
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "moon.stars").font(.system(size: 11))
                    Text("Chưa hẹn giờ tắt").font(.system(size: 11))
                }
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    /// Hàng tên chương đang phát với hiệu ứng Marquee
    private var playingChapterMarqueeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tint)
            MarqueeText(text: ttsManager.displayedChapterTitle)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.7)))
    }

    /// Thanh 2 Tab con chuẩn 1 hàng
    private var subTabsBar: some View {
        HStack(spacing: 8) {
            subTabButton(title: "Hẹn giờ tắt", icon: "timer", index: 0)
            subTabButton(title: "Danh sách chương", icon: "list.bullet", index: 1)
        }
    }

    private func subTabButton(title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            triggerHaptic()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { selectedTab = index }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: isSelected ? .bold : .medium))
                Text(title).font(.system(size: 13, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Color.white.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isSelected ? Color.white.opacity(0.32) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                Image(systemName: icon).font(.system(size: 16, weight: isSelected ? .bold : .regular)).foregroundStyle(isSelected ? Color.white : Color.secondary)
                Text(title).font(.subheadline).fontWeight(isSelected ? .bold : .medium).foregroundStyle(isSelected ? Color.white : Color.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? Color.white.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? Color.white.opacity(0.35) : Color.clear, lineWidth: 1.5))
            .shadow(color: isSelected ? Color.white.opacity(0.1) : Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
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

                Slider(value: $customMinutes, in: 1...180, step: 1).tint(Color.white)

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

    // MARK: - Tab 2: Danh sách chương

    private var chapterListTabContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(ttsManager.chaptersQueue, id: \.index) { chapter in
                        chapterRow(chapter: chapter, isPlaying: chapter.index == ttsManager.playingChapterIndex)
                            .id(chapter.index)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .onAppear {
                if ttsManager.playingChapterIndex >= 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(ttsManager.playingChapterIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func chapterRow(chapter: TTSChapterInfo, isPlaying: Bool) -> some View {
        Button(action: {
            triggerHaptic()
            ttsManager.jumpToChapter(at: chapter.index)
        }) {
            HStack(spacing: 12) {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.tint).frame(width: 20)
                } else {
                    Text("\(chapter.index + 1)").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 20)
                }
                Text(displayTitle(for: chapter))
                    .font(.system(size: 14, weight: isPlaying ? .bold : .regular)).foregroundStyle(isPlaying ? Color.primary : Color.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if isPlaying {
                    Text("Đang phát").font(.system(size: 11, weight: .bold)).foregroundStyle(.tint)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isPlaying ? Color.white.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isPlaying ? Color.white.opacity(0.28) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func displayTitle(for chapter: TTSChapterInfo) -> String {
        ttsManager.displayTitle(for: chapter)
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
