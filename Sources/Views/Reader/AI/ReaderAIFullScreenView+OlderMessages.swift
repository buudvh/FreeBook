import SwiftUI

/// Tự nạp tin nhắn cũ hơn khi người dùng cuộn lên gần đầu — thay nút "Tải thêm tin nhắn cũ hơn".
///
/// Vùng tin nhắn là `VStack` thường (không lazy) nên `onAppear` của một hàng đầu danh sách chạy ngay lúc dựng màn,
/// không theo vị trí cuộn ⇒ đo vị trí thật của hàng mốc trong hệ toạ độ của `ScrollView` (`GeometryReader` +
/// `onChange` của một `Bool`: chỉ ghi state khi đổi trạng thái, không ghi theo từng khung cuộn).
///
/// Ba chốt chặn:
/// - Chỉ chạy sau khi lượt cuộn-xuống-cuối ban đầu của **đúng phiên đang mở** đã xong (`olderMessagesArmedSessionId`):
///   lúc mới mở màn / vừa đổi phiên, hàng mốc có thể thoáng nằm trong vùng nhìn thấy trước khi neo đáy áp vào.
/// - Không nạp chồng khi lượt trước chưa xong (`isLoadingOlderMessages`).
/// - Giữ chỗ đang đọc: ghi id tin đầu đang hiện, nạp thêm, rồi `scrollTo(id cũ, .top)` ở lượt main kế tiếp.
extension ReaderAIFullScreenView {
    /// Hệ toạ độ gắn trên `ScrollView` chat — `minY` của hàng mốc tính từ mép trên vùng cuộn.
    static let chatScrollSpace = "readerAIChatScroll"

    private static let olderMessagesPageSize = 20
    /// Hàng mốc cách mép trên vùng cuộn không quá chừng này (pt) ⇒ coi như đã cuộn tới đầu.
    private static let olderMessagesTriggerMargin: CGFloat = 8
    /// Chờ neo đáy ban đầu / lượt cuộn-xuống-cuối khi đổi phiên (0,08 s + 0,25 s animation) xong mới cho tự nạp.
    private static let olderMessagesArmDelayNanoseconds: UInt64 = 600_000_000
    /// Nhả cờ "đang nạp" sau chừng này giây — đủ để vị trí cuộn mới kịp áp vào hình học của hàng mốc.
    private static let olderMessagesSettleDelay: TimeInterval = 0.25

    /// Hàng mỏng đầu danh sách, chỉ có khi còn tin cũ chưa hiện.
    func olderMessagesSentinel(proxy: ScrollViewProxy) -> some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                GeometryReader { geo in
                    let minY = geo.frame(in: CoordinateSpace.named(Self.chatScrollSpace)).minY
                    Color.clear.onChange(of: minY > -Self.olderMessagesTriggerMargin, initial: true) { _, isNearTop in
                        isOlderMessagesSentinelNearTop = isNearTop
                        if isNearTop { loadOlderMessagesIfNeeded(proxy: proxy) }
                    }
                }
            )
            .onDisappear { isOlderMessagesSentinelNearTop = false }
            .accessibilityLabel("Đang tải tin nhắn cũ hơn")
    }

    /// Gọi từ `.task(id: currentSession.id)` của `ScrollView`: đổi phiên thì task cũ bị huỷ, phiên mới chờ lại từ đầu.
    @MainActor
    func armOlderMessagesAutoLoad(proxy: ScrollViewProxy) async {
        try? await Task.sleep(nanoseconds: Self.olderMessagesArmDelayNanoseconds)
        guard !Task.isCancelled else { return }
        olderMessagesArmedSessionId = currentSession.id
        // Phiên ngắn vừa một màn: hàng mốc đã nằm sẵn trong vùng nhìn thấy, không có lượt cuộn nào để kích ⇒ nạp luôn.
        if isOlderMessagesSentinelNearTop { loadOlderMessagesIfNeeded(proxy: proxy) }
    }

    func loadOlderMessagesIfNeeded(proxy: ScrollViewProxy) {
        guard olderMessagesArmedSessionId == currentSession.id,
              !isLoadingOlderMessages,
              currentSession.messages.count > visibleMessageCount,
              let anchorId = displayedMessages.first?.id else { return }
        isLoadingOlderMessages = true
        // Không `withAnimation`: chèn có animation sẽ giằng co với `scrollTo` giữ chỗ bên dưới.
        visibleMessageCount += Self.olderMessagesPageSize
        DispatchQueue.main.async {
            proxy.scrollTo(anchorId, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.olderMessagesSettleDelay) {
                isLoadingOlderMessages = false
                // Mốc vẫn ở đầu (tin cũ quá ngắn, hoặc người dùng đã cuộn tiếp lên lúc đang nạp) ⇒ nạp tiếp.
                if isOlderMessagesSentinelNearTop { loadOlderMessagesIfNeeded(proxy: proxy) }
            }
        }
    }
}
