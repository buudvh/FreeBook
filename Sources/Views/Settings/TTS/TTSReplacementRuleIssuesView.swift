import SwiftUI

/// Mục "Kiểm tra" của sheet thêm / sửa luật thay thế TTS (Cài đặt và Reader) — hiện ngay khi gõ (1.3.920).
///
/// Khuôn của `QuickTranslationRuleDraftIssuesView`: đỏ = lỗi (chặn Lưu), cam = cảnh báo, xanh = hợp lệ kèm loại
/// luật. Verdict lấy từ `TTSReplacementRuleValidator` — cùng bộ tách token với lúc đọc.
struct TTSReplacementRuleIssuesView: View {
    let pattern: String
    let issues: [TTSReplacementRuleValidator.Issue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // `id: \.self` trên chỉ số: danh sách tính lại mỗi phím gõ, không có identity ổn định nào tốt hơn.
            ForEach(issues.indices, id: \.self) { index in
                let issue = issues[index]
                row(
                    issue.code.label,
                    issue.message,
                    color: issue.severity == .error ? .red : .orange,
                    icon: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                )
            }

            if !issues.contains(where: { $0.severity == .error }),
               let description = TTSReplacementRuleValidator.validDescription(for: pattern) {
                row("HỢP LỆ", description, color: .green, icon: "checkmark.seal.fill")
            }
        }
    }

    private func row(_ code: String, _ message: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(code)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
