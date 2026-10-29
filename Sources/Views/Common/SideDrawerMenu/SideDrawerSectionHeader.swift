import SwiftUI

/// Tiêu đề nhóm nhỏ trong ngăn kéo (vd "Hiển thị", "Thao tác").
struct SideDrawerSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.6))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
