import SwiftUI

/// Nhóm 5 nút định dạng chữ hoa/thường `aa · Aa¹ · Aa² · Aa · AA` đặt **cạnh một ô nhập**, cùng cỡ 26pt với bộ nút
/// xoá · sao chép · dán cạnh ô (`TextFieldClipboardButtons`, `clipboardToolbar` của `DictEntrySheet`).
///
/// Luật đổi chữ ở `TextCaseFormatter`; nơi dùng tự quyết đổi phần nào qua `onApply` (vd ô Thêm từ chỉ đổi phần nghĩa
/// sau dấu `=`). Dùng ở Thêm/Sửa từ của từ điển dịch và ô Bản dịch của màn Thêm/Sửa rule.
///
/// `.buttonStyle(.borderless)` là bắt buộc: trong một dòng của `Form`, nút kiểu mặc định làm chạm bất kỳ đâu trên
/// dòng là bấm **mọi** nút của dòng đó.
struct TextCaseButtonGroup: View {
    var isDisabled: Bool = false
    let onApply: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(TextCaseFormatter.styles.enumerated()), id: \.offset) { index, style in
                if index > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 0.5, height: 14)
                }
                Button {
                    onApply(style)
                } label: {
                    Text(style)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 7)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Định dạng chữ \(style)")
            }
        }
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(5)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
