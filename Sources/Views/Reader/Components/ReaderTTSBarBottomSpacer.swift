import SwiftUI

/// Khoảng đáy của vùng chữ Reader (1.3.806). Bình thường cao `baseHeight` (chỗ của dải chân trang). Thanh TTS kiểu "Thanh
/// nghe nhạc" đang **bung** trong Reader (nằm sát đáy, cửa sổ nổi riêng) ⇒ cao đúng chiều cao thanh + khe
/// (`TTSWidgetBarPresence.readerBottomInset`): chữ truyện dừng ngay trên thanh, cuộn tới cuối vẫn đọc hết, nút tai nghe
/// (đứng ở góc dưới vùng chữ) đẩy lên trên thanh.
///
/// View riêng observe cầu nối ⇒ chỉ khoảng này đổi chiều cao, thân `ReaderView` không đánh giá lại.
struct ReaderTTSBarBottomSpacer: View {
    let baseHeight: CGFloat

    @ObservedObject private var presence = TTSWidgetBarPresence.shared

    var body: some View {
        Color.clear
            .frame(height: max(baseHeight, presence.readerBottomInset))
            .animation(.easeInOut(duration: 0.25), value: presence.readerBottomInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
