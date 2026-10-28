import SwiftUI

/// Thanh chip nghĩa cuộn ngang: viền theo nguồn (Names đỏ, VietPhrase/Xưng hô/Luật nhân xanh, Phiên âm xám), badge
/// R/C ở góc trên phải. Dùng chung cho panel Dịch của Reader và sheet Sửa từ của từ điển VP/Names, nên hai nơi luôn
/// trông giống nhau. Danh sách chip dựng bằng `ReaderView.buildSuggestionChips(for:bookId:)`.
///
/// Nội dung chừa `ChipCornerBadge.inset` ở trên/phải để ScrollView không cắt badge; nơi dùng muốn giữ chiều cao hàng
/// cũ thì tự đặt `.padding(.top, -ChipCornerBadge.inset)` (panel Dịch làm vậy).
struct MeaningSuggestionChipRow: View {
    let chips: [SuggestionChip]
    let onSelect: (SuggestionChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button(action: { onSelect(chip) }) {
                        Text(chip.text)
                            .font(.subheadline)
                            .foregroundColor(chip.category.textColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.12, green: 0.12, blue: 0.15))
                            .cornerRadius(15)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(chip.category.borderColor, lineWidth: 1)
                            )
                            .overlay(alignment: .topTrailing) {
                                if let scope = chip.scope {
                                    ChipCornerBadge(scope: scope)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.accessibilityLabel(chip))
                }
            }
            .padding(.top, ChipCornerBadge.inset)
            .padding(.trailing, ChipCornerBadge.inset)
        }
    }

    private static func accessibilityLabel(_ chip: SuggestionChip) -> String {
        switch chip.scope {
        case .book: return "\(chip.text), từ điển riêng"
        case .global: return "\(chip.text), từ điển chung"
        case nil: return chip.text
        }
    }
}
