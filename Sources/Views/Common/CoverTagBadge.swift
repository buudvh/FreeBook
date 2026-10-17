import SwiftUI

/// Nhãn `tag` của item ("Hoàn thành", "Hot", "Full HD"…) đặt ở góc ảnh bìa: chip nhỏ chữ 11pt trên nền tối
/// mờ để đọc được trên mọi bìa. Tag rỗng ⇒ không vẽ gì. Nhãn chung của Tìm kiếm, Gợi ý và các danh sách Khám phá.
///
/// Dùng qua `.overlay(alignment: .bottomLeading) { CoverTagBadge(tag: …) }` — overlay nhận đúng bề ngang bìa nên chữ
/// dài tự cắt "…" thay vì tràn khỏi bìa. Chuỗi phải được dịch sẵn (badge không dịch).
/// - `fontSize`: bìa nhỏ/lớn đổi cỡ chữ; đệm trong co giãn theo cỡ chữ (11pt ⇒ đệm 5×2 như cũ).
/// - `inset`: khoảng cách tới mép bìa; `0` khi badge nằm trong một khối đã có lề riêng (banner).
struct CoverTagBadge: View {
    let tag: String
    var fontSize: CGFloat = 11
    var inset: CGFloat = 3

    var body: some View {
        let text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, fontSize * 5 / 11)
                .padding(.vertical, fontSize * 2 / 11)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(inset)
                .accessibilityLabel("Nhãn: \(text)")
        }
    }
}
