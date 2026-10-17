import SwiftUI

/// Nhãn `tag` của item ("Hoàn thành", "Hot", "Full HD"…) đặt ở góc dưới ảnh bìa: chip nhỏ chữ 11pt trên nền tối
/// mờ để đọc được trên mọi bìa. Tag rỗng ⇒ không vẽ gì.
///
/// Dùng qua `.overlay(alignment: .bottomLeading) { CoverTagBadge(tag: …) }` — overlay nhận đúng bề ngang bìa nên chữ
/// dài tự cắt "…" thay vì tràn khỏi bìa.
struct CoverTagBadge: View {
    let tag: String

    var body: some View {
        let text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(3)
                .accessibilityLabel("Nhãn: \(text)")
        }
    }
}
