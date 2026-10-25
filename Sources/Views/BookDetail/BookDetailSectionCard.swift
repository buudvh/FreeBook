import SwiftUI

/// Thẻ bo góc của tab Chi tiết (Thông tin, Thể loại, Giới thiệu): tiêu đề màu xanh nhạt + nội dung, nền
/// `secondarySystemBackground`, lề ngang theo màn.
struct BookDetailSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

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
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Self.titleColor)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
