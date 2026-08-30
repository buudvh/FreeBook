import SwiftUI

/// Dải nút chèn token cho ô **Mẫu** của màn thêm/sửa rule: bấm là chèn, không phải gõ tay từng
/// `<`, `:`, `-`, `>`.
///
/// Danh sách dựng từ `QuickTranslationRuleTokenSettings.Kind.allCases` nên thêm token mới ở engine là
/// tự có nút, không phải sửa hai chỗ. Nút chỉ chèn token **trần** (`<n>`); khoảng độ dài và dấu `?`
/// do `QuickTranslationRuleTokenLengthBar` chỉnh trên token đang chọn.
///
/// Bẫy layout phải giữ: dùng `HStack` trong `ScrollView`, **không** `LazyHStack` — lazy container nằm
/// trong một hàng `List`/`Form` làm layout tự vô hiệu giữa lượt cập nhật cell và trap `EXC_BREAKPOINT`
/// (đã crash thật ở 1.3.269).
struct QuickTranslationRuleTokenPaletteView: View {
    /// Chuỗi cần chèn tại con trỏ / thay cho vùng đang chọn.
    let onInsert: (String) -> Void

    /// Cú pháp nhóm: `(a|b)` và `(a|b)?`. Nhóm không được đánh số nên không có `{i}` cho nó.
    private static let groupSyntax = ["(", "|", ")", ")?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickTranslationRuleTokenSettings.Kind.allCases, id: \.self) { kind in
                        tokenButton(kind)
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.groupSyntax, id: \.self) { syntax in
                        plainButton(syntax, caption: caption(forGroup: syntax)) {
                            onInsert(syntax)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if hasDisabledToken {
                Text("Token mờ đang **tắt** ở Cấu hình token rule: rule chứa nó vẫn lưu được nhưng sẽ không chạy.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var hasDisabledToken: Bool {
        QuickTranslationRuleTokenSettings.Kind.allCases.contains {
            !QuickTranslationRuleTokenSettings.isEnabled($0)
        }
    }

    private func tokenButton(_ kind: QuickTranslationRuleTokenSettings.Kind) -> some View {
        let isEnabled = QuickTranslationRuleTokenSettings.isEnabled(kind)
        return plainButton(kind.syntax, caption: Self.caption(for: kind), isDimmed: !isEnabled) {
            onInsert(kind.syntax)
        }
        .accessibilityLabel("Chèn token \(kind.syntax) — \(Self.caption(for: kind))")
    }

    private func plainButton(
        _ syntax: String,
        caption: String,
        isDimmed: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(syntax)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(isDimmed ? 0.05 : 0.14))
            .cornerRadius(8)
            .opacity(isDimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    /// Nhãn ngắn lấy đúng chữ của màn Cấu hình token rule để hai chỗ không nói khác nhau.
    private static func caption(for kind: QuickTranslationRuleTokenSettings.Kind) -> String {
        switch kind {
        case .numeral: return "số"
        case .digitwise: return "từng chữ số"
        case .hanDigits: return "chữ số Hán"
        case .asciiDigits: return "chữ số 0-9"
        case .chapterLabel: return "nhãn chương"
        case .name: return "tên riêng"
        case .pronoun: return "đại từ"
        case .vietPhrase: return "VietPhrase"
        case .hanViet: return "một chữ HV"
        case .word: return "cụm từ điển"
        }
    }

    private func caption(forGroup syntax: String) -> String {
        switch syntax {
        case "(": return "mở nhóm"
        case "|": return "hoặc"
        case ")": return "đóng nhóm"
        default: return "nhóm tùy chọn"
        }
    }
}
