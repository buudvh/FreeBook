import SwiftUI

/// Trang "Hướng dẫn viết rule" (1.3.692): mỗi mục của `QuickTranslationRuleGuide` một `Section`, mỗi ý một hàng —
/// chữ `.subheadline`, ví dụ (nếu có) chữ đều `.footnote` màu phụ ngay dưới.
///
/// Hai lối vào: Quản lý rule dịch › Công cụ (hàng đầu) và hàng "Hướng dẫn đầy đủ" dưới bảng token của màn
/// thêm/sửa rule (đẩy trong `NavigationStack` của sheet). Nội dung không viết ở đây — sửa ở
/// `QuickTranslationRuleGuide` để các nút "?" cùng đổi theo.
struct QuickTranslationRuleGuideView: View {
    var body: some View {
        List {
            ForEach(QuickTranslationRuleGuide.topics) { topic in
                Section {
                    ForEach(Array(topic.points.enumerated()), id: \.offset) { _, point in
                        row(point)
                    }
                } header: {
                    Text(verbatim: topic.title)
                }
            }
        }
        .backPageTitle("Hướng dẫn viết rule")
    }

    private func row(_ point: QuickTranslationRuleGuide.Point) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: point.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            if let example = point.example {
                Text(verbatim: example)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // Ví dụ hay được chép sang ô Mẫu: cho bôi đen chép được.
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
