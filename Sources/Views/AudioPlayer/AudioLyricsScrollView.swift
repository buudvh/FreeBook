import SwiftUI

/// Lời bài hát đã nạp của trang Lời.
/// - Có mốc giờ: dòng đang hát (`currentLyricLineIndex`, offset trong `lines`) to hơn + màu nhấn, dòng đã qua mờ; tự cuộn
///   giữ dòng đang hát ở giữa — người dùng vừa cuộn tay thì ngưng tự cuộn `manualScrollPause` giây. Chạm một dòng ⇒ tua
///   tới mốc của dòng đó.
/// - Không mốc giờ: chữ thường, cuộn tay.
struct AudioLyricsScrollView: View {
    let lyrics: AudioLyrics
    let isVisible: Bool

    /// Lần cuộn tay gần nhất — lớp thường (không `@Observable`) ⇒ ghi mỗi nhịp kéo không làm view vẽ lại.
    final class ManualScrollClock {
        var lastScroll = Date.distantPast
    }

    @State private var clock = ManualScrollClock()

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
        if lyrics.isSynced {
            let isCurrent = offset == current
            let isPast = current.map { offset < $0 } ?? false
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(isCurrent ? .title3.weight(.bold) : .body.weight(.semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(isPast ? 0.4 : 0.75)))
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
            Text(line.text)
                .font(.body)
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
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
