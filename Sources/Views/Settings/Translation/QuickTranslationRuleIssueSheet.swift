import SwiftUI

/// Danh sách lỗi / cảnh báo theo dòng của bộ rule dịch.
///
/// Chính sách strict ở tầng compile (một hard error là **không** swap snapshot) chỉ công bằng khi UI
/// chỉ đúng dòng lỗi, nên sheet này liệt kê `dòng — mã — thông báo — nguyên văn` và cho copy tất cả
/// để người dùng sửa file ngoài app.
struct QuickTranslationRuleIssueSheet: View {
    let issues: [QuickTranslationRuleIssue]

    @Environment(\.dismiss) private var dismiss

    private var hardIssues: [QuickTranslationRuleIssue] { issues.filter { $0.severity == .hard } }
    private var disablingIssues: [QuickTranslationRuleIssue] { issues.filter { $0.severity == .disabling } }
    private var warningIssues: [QuickTranslationRuleIssue] { issues.filter { $0.severity == .warning } }

    var body: some View {
        NavigationStack {
            List {
                if !hardIssues.isEmpty {
                    section(
                        title: "Lỗi nặng — chặn nạp cả file (\(hardIssues.count))",
                        color: .red,
                        issues: hardIssues
                    )
                }
                if !disablingIssues.isEmpty {
                    section(
                        title: "Thiếu từ điển — rule bị vô hiệu (\(disablingIssues.count))",
                        color: .orange,
                        issues: disablingIssues
                    )
                }
                if !warningIssues.isEmpty {
                    section(
                        title: "Cảnh báo — vẫn nạp (\(warningIssues.count))",
                        color: .yellow,
                        issues: warningIssues
                    )
                }
                if issues.isEmpty {
                    Text("Không có lỗi hay cảnh báo nào.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Lỗi & cảnh báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = clipboardText()
                        ToastManager.shared.show(message: "Đã copy danh sách lỗi.", type: .info)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(issues.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, color: Color, issues: [QuickTranslationRuleIssue]) -> some View {
        Section(header: Text(title).foregroundColor(color)) {
            ForEach(issues) { issue in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("dòng \(issue.sourceLine)")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(issue.code.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.15))
                            .foregroundColor(color)
                            .cornerRadius(4)
                    }
                    Text(issue.message)
                        .font(.footnote)
                    Text(issue.rawLine)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func clipboardText() -> String {
        issues
            .map { "\($0.sourceLine)\t\($0.code.rawValue)\t\($0.message)\t\($0.rawLine)" }
            .joined(separator: "\n")
    }
}
