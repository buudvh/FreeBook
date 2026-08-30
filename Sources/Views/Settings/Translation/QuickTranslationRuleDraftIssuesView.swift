import SwiftUI

/// Section "Kiểm tra" của màn thêm/sửa rule: hiện **mọi** lỗi/cảnh báo của bản nháp ngay khi gõ.
///
/// Trước 1.3.288 người dùng chỉ thấy đúng **một** issue và chỉ sau khi bấm Lưu bị từ chối. Verdict ở
/// đây do `QuickTranslationRuleDraftAnalyzer` cấp, tức chạy đúng `parse` → `compile` trên đúng dòng mà
/// store sẽ ghi, nên không có chuyện "ở đây xanh mà lưu vẫn đỏ".
///
/// `DUPLICATE_PATTERN` là ngoại lệ đã biết: nó chỉ phát hiện được khi so với cả file, còn ở đây chỉ có
/// một dòng — nên trùng mẫu vẫn chỉ báo lúc lưu (và ngữ nghĩa lúc đó là đè vế phải, không phải lỗi).
struct QuickTranslationRuleDraftIssuesView: View {
    let analysis: QuickTranslationRuleDraftAnalyzer.Analysis
    /// Lỗi do store trả về lúc lưu — vẫn giữ vì nó nói được những chuyện file mà bản nháp không biết.
    let storeError: String?

    var body: some View {
        // Đọc một lần: `hardIssues`/`warnings` là computed property lọc lại mảng mỗi lần truy cập.
        let hard = analysis.hardIssues
        let soft = analysis.warnings

        return VStack(alignment: .leading, spacing: 8) {
            // `id: \.self` trên chỉ số chứ không phải `QuickTranslationRuleIssue.id`: id đó là một
            // `UUID` mới mỗi lượt compile, mà bản nháp compile lại **mỗi keystroke** — dùng nó làm
            // identity thì `ForEach` remove/insert toàn bộ hàng cho từng ký tự gõ vào.
            ForEach(hard.indices, id: \.self) { index in
                row(hard[index].code.rawValue, hard[index].message, color: .red, icon: "xmark.octagon.fill")
            }

            ForEach(soft.indices, id: \.self) { index in
                row(soft[index].code.rawValue, soft[index].message, color: .orange, icon: "exclamationmark.triangle.fill")
            }

            if let storeError, !storeError.isEmpty {
                row("LƯU THẤT BẠI", storeError, color: .red, icon: "externaldrive.badge.xmark")
            }

            if hard.isEmpty && soft.isEmpty && (storeError ?? "").isEmpty {
                row("HỢP LỆ", "Rule đủ điều kiện lưu.", color: .green, icon: "checkmark.seal.fill")
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
