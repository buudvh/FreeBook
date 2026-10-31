import SwiftUI

/// Nội dung bảng chọn nguồn import (popover của `BrowserImportButton`, mockup 2026-10-30 màn "Mới 1b") — thay hộp thoại
/// "Chọn nguồn import" cũ. Tiêu đề nhỏ "Import bằng nguồn"; mỗi hàng: icon 36, tên đậm, dòng phụ "loại nội dung · dùng
/// <thời gian tương đối>" (theo `Extension.lastUsedAt` nếu có), chevron.
struct BrowserImportSourcePicker: View {
    let matches: [ExtensionUrlMatcher.Match]
    let onSelect: (ExtensionUrlMatcher.Match) -> Void

    /// Quá số hàng này thì cuộn trong khung cố định (popover tự co theo nội dung nên không đặt `ScrollView` khi ít hàng).
    private static let maxVisibleRows = 6
    private static let rowHeight: CGFloat = 54

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Import bằng nguồn")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.36))
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

            if matches.count > Self.maxVisibleRows {
                ScrollView {
                    rows
                }
                .frame(height: CGFloat(Self.maxVisibleRows) * Self.rowHeight)
            } else {
                rows
            }
        }
        .padding(8)
        .frame(width: 258)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(matches) { match in
                Button {
                    onSelect(match)
                } label: {
                    row(for: match.ext)
                }
                .buttonStyle(RowButtonStyle())
            }
        }
    }

    private func row(for ext: Extension) -> some View {
        HStack(spacing: 11) {
            ExtensionIconView(localPath: ext.localPath, iconUrl: ext.iconUrl, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle(for: ext))
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
        }
        .padding(8)
        .frame(minHeight: 52)
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }

    private func subtitle(for ext: Extension) -> String {
        let kind = ExtensionContentKind(typeString: ext.type).label
        guard let lastUsed = ext.lastUsedAt else { return kind }
        let relative = Self.relativeFormatter.localizedString(for: lastUsed, relativeTo: Date())
        return "\(kind) · dùng \(relative)"
    }

    /// Hàng nhấn thì sáng nền nhẹ như hàng menu hệ thống.
    private struct RowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0))
                )
        }
    }
}
