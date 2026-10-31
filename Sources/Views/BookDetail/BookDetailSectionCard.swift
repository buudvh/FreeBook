import SwiftUI

/// Thẻ bo góc của tab Chi tiết (Thông tin, Thể loại, Giới thiệu, đề xuất, bình luận): tiêu đề màu xanh nhạt + nội dung,
/// nền `secondarySystemBackground`, lề ngang theo màn. `trailing` (vd "Xem thêm ›") nằm cùng hàng tiêu đề, bên phải.
struct BookDetailSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let content: Content
    let trailing: Trailing

    init(title: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.content = content()
        self.trailing = trailing()
    }

    /// Xanh nhạt trên nền tối; nền sáng dùng xanh hệ thống cho đủ tương phản.
    private static var titleColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.66, green: 0.78, blue: 0.98, alpha: 1)
                : .systemBlue
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Self.titleColor)
                Spacer(minLength: 0)
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}

extension BookDetailSectionCard where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, trailing: { EmptyView() })
    }
}
