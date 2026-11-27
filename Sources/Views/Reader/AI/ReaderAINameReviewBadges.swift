import SwiftUI

/// Cụm badge sau chữ Hán của một hàng thẻ duyệt (`ReaderAINameReviewCardView`): badge loại, NE (đã có trong Name riêng /
/// chung), VP (đã có trong VietPhrase), "N lần". Tách khỏi thẻ để thẻ giữ dưới 400 dòng.
///
/// `colorsCategory` (chỉ luồng "Lọc name local"): badge loại có màu theo nhóm (`LocalNameFilterCategoryBadge`) với bốn
/// nhãn Nhân danh / Địa danh / Tổ chức / Thuật ngữ, nhãn khác giữ xám. Luồng AI (`false`): badge xám như cũ — nhãn AI có
/// thể trùng chữ ("Địa danh") nhưng không đổi màu.
struct ReaderAINameReviewBadges: View {
    let item: AIExtractedName
    let colorsCategory: Bool

    var body: some View {
        if colorsCategory {
            LocalNameFilterCategoryBadge(label: item.category)
        } else {
            Text(item.category)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(white: 0.25))
                .foregroundColor(.white)
                .cornerRadius(4)
                .fixedSize(horizontal: true, vertical: false)
        }

        if item.hasInBookNames {
            Text("NE")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.red.opacity(0.25))
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.red.opacity(0.8), lineWidth: 0.8)
                )
                .cornerRadius(4)
                .fixedSize(horizontal: true, vertical: false)
        }

        if item.hasInBookVP {
            Text("VP")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color(red: 0.3, green: 0.6, blue: 0.9).opacity(0.25))
                .foregroundColor(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.8), lineWidth: 0.8)
                )
                .cornerRadius(4)
                .fixedSize(horizontal: true, vertical: false)
        }

        if item.occurrenceCount > 1 {
            Text("\(item.occurrenceCount) lần")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
