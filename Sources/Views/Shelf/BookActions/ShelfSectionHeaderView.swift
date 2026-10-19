import SwiftUI

/// Tiêu đề một nhóm truyện phía kệ: "Đang ghim" / "Truyện khác" (Kệ sách, Bộ sưu tập) và từng ngày của tab Lịch sử.
///
/// Trước đây `ShelfView.shelfSectionHeader` và `CollectionDetailView.sectionHeader` là hai bản chép y hệt nhau; giờ
/// cả hai kiểu hiển thị (danh sách lẫn lưới) của `ShelfBooksLayoutView` dùng chung một bản.
///
/// `textCase(nil)` để tiêu đề giữ nguyên chữ thường — mặc định của `List` là in hoa hết.
struct ShelfSectionHeaderView: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: Capsule())
            Spacer()
        }
        .textCase(nil)
    }
}
