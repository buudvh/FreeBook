import SwiftUI

/// Lời bài hát đã nạp của trang Lời.
/// - Có mốc giờ: dòng đang hát (`currentLyricLineIndex`, offset trong `lines`) to hơn + màu nhấn, dòng đã qua mờ; tự cuộn
///   giữ dòng đang hát ở giữa — người dùng vừa cuộn tay thì ngưng tự cuộn `manualScrollPause` giây. Chạm một dòng ⇒ tua
///   tới mốc của dòng đó.
/// - Không mốc giờ: chữ thường, cuộn tay.
/// - Dòng có bản dịch: theo kiểu hiện lời (`MediaCaptionDisplayMode`) — Gốc / Bản dịch / Song ngữ (bản dịch dưới dòng gốc).
struct AudioLyricsScrollView: View {
    let lyrics: AudioLyrics
    let isVisible: Bool

    /// Lần cuộn tay gần nhất — lớp thường (không `@Observable`) ⇒ ghi mỗi nhịp kéo không làm view vẽ lại.
    final class ManualScrollClock {
        var lastScroll = Date.distantPast
    }

    @State private var clock = ManualScrollClock()
    /// Kiểu hiện lời có bản dịch — chọn ở ngăn kéo `…` (mục "Lời bài hát").
    @AppStorage(MediaCaptionDisplayMode.audioDefaultsKey) private var displayMode = MediaCaptionDisplayMode.defaultValue

    private static let manualScrollPause: TimeInterval = 3

    private var session: AudioPlaybackSession { .shared }

    var body: some View {
        let current = lyrics.isSynced ? session.currentLyricLineIndex : nil
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: lyrics.isSynced ? 16 : 6) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { offset, line in
                        lineView(offset: offset, line: line, current: current)
                            .id(offset)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { _ in clock.lastScroll = Date() }
            )
            .onAppear {
                scroll(proxy, to: current, animated: false, force: true)
            }
            .onChange(of: current) { _, newValue in
                scroll(proxy, to: newValue, animated: true, force: false)
            }
            .onChange(of: isVisible) { _, visible in
                if visible { scroll(proxy, to: current, animated: false, force: true) }
            }
        }
    }

    @ViewBuilder
    private func lineView(offset: Int, line: AudioLyricLine, current: Int?) -> some View {
        let shown = shownText(of: line)
        if lyrics.isSynced {
            let isCurrent = offset == current
            let isPast = current.map { offset < $0 } ?? false
            VStack(alignment: .leading, spacing: 4) {
                Text(shown.primary.isEmpty ? "♪" : shown.primary)
                    .font(isCurrent ? .title3.weight(.bold) : .body.weight(.semibold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(isPast ? 0.4 : 0.75)))
                if let below = shown.below {
                    Text(below)
                        .font(isCurrent ? .body.weight(.semibold) : .subheadline)
                        .foregroundStyle(Color.white.opacity(isCurrent ? 0.85 : (isPast ? 0.3 : 0.55)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let time = line.time else { return }
                clock.lastScroll = .distantPast
                session.seek(to: time)
            }
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
        } else if line.text.isEmpty {
            Color.clear.frame(height: 10)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(shown.primary)
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.85))
                if let below = shown.below {
                    Text(below)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Dòng chính + dòng phụ bên dưới theo kiểu hiện lời. Song ngữ ở trang Lời: dòng **gốc** giữ chỗ cũ, bản dịch nằm dưới
    /// (khác phụ đề phim — dòng dịch to ở trên). Dòng chưa / không có bản dịch ⇒ chỉ chữ gốc. "Chữ gốc" = `displayText`
    /// (đã chuyển phồn → giản nếu bật, cả khi tắt dịch).
    private func shownText(of line: AudioLyricLine) -> (primary: String, below: String?) {
        let original = line.displayText
        guard let translation = line.translation, !translation.isEmpty else { return (original, nil) }
        switch displayMode {
        case .original: return (original, nil)
        case .translated: return (translation, nil)
        case .bilingual: return (original, translation)
        }
    }

    /// `force` = trang vừa hiện: cuộn luôn, không xét lần cuộn tay.
    private func scroll(_ proxy: ScrollViewProxy, to index: Int?, animated: Bool, force: Bool) {
        guard isVisible, let index else { return }
        if !force, Date().timeIntervalSince(clock.lastScroll) < Self.manualScrollPause { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
