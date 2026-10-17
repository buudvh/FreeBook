import SwiftUI

/// Nhãn `tag` của item ("Hoàn thành", "Tập 12", "FHD"…) đặt đè lên góc ảnh bìa ở các danh sách Khám phá.
/// Nền tối bán trong suốt để đọc được trên mọi ảnh; một dòng, quá dài thì cắt "…".
struct DiscoveryCoverTag: View {
    let text: String
    var fontSize: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(.white)
            .padding(.horizontal, max(3, fontSize * 0.45))
            .padding(.vertical, max(1, fontSize * 0.2))
            .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
