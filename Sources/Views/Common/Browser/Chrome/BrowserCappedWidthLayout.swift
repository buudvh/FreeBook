import SwiftUI

/// Bố cục một con, giới hạn chiều rộng **tường minh**: luôn đề xuất cho con `min(đề xuất, maxWidth)` và nhận đúng cỡ con
/// trả về. Dùng cho tiêu đề tab trong dải cuộn ngang: `ScrollView(.horizontal)` đề xuất chiều rộng `nil`, khi đó
/// `.frame(maxWidth:)` vẫn để `Text` lấy cỡ lý tưởng một dòng rồi tràn khung thay vì cắt "…". Ở đây con luôn nhận một
/// chiều rộng cụ thể nên `Text` một dòng tự cắt đuôi, còn tiêu đề ngắn vẫn gọn theo chữ.
struct BrowserCappedWidthLayout: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
