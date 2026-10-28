import SwiftUI

/// Kết quả từng script của **một** tiện ích: bốn ô Đạt / Lỗi / Bỏ qua / Chỉ tĩnh, rồi các nhóm Lối vào · Truyện thử ·
/// Giọng đọc · Khoá app chưa gọi (`ExtensionCheckScriptRow`). Dùng ở màn kiểm một tiện ích (`ExtensionCheckView`) và
/// màn xem một tiện ích của lượt hàng loạt (`ExtensionCheckResultScreen`).
struct ExtensionCheckDetailContent: View {
    let result: ExtensionCheckReport.ExtensionResult?
    @Binding var openingLink: SourceErrorLink?

    var body: some View {
        if let result {
            List {
                Section {
                    tiles(result)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    if let issue = result.manifestIssue {
                        Text(issue)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
                ForEach(ExtensionCheckReport.Group.allCases, id: \.self) { group in
                    let rows = result.scripts.filter { $0.group == group }
                    if !rows.isEmpty {
                        Section(header: Text(sectionTitle(group, result: result))) {
                            ForEach(rows) { row in
                                ExtensionCheckScriptRow(row: row, openingLink: $openingLink)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        } else {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text("Đang chuẩn bị…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tiles(_ result: ExtensionCheckReport.ExtensionResult) -> some View {
        HStack(spacing: 8) {
            tile("Đạt", value: result.count(.passed), color: .green)
            tile("Lỗi", value: result.count(.failed), color: .red)
            tile("Bỏ qua", value: result.count(.skipped), color: .secondary)
            tile("Chỉ tĩnh", value: result.count(.staticOnly), color: .secondary)
        }
    }

    private func tile(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ group: ExtensionCheckReport.Group, result: ExtensionCheckReport.ExtensionResult) -> String {
        switch group {
        case .entry:
            return "Lối vào"
        case .book:
            guard let name = result.bookName else { return "Truyện thử" }
            let source = result.bookSource.map { " (từ \($0))" } ?? ""
            return "Truyện thử: \(name)\(source)"
        case .voice:
            return "Giọng đọc"
        case .other:
            return "Khoá app chưa gọi"
        }
    }
}
