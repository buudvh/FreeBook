import SwiftUI
import UIKit

/// Bộ nút nhỏ cạnh một ô nhập **một dòng**: (↺ khôi phục mặc định) · xoá · sao chép · dán.
///
/// Cùng dáng với `clipboardToolbar` ở `DictEntrySheet` / `AISettingsView+Actions` (ô 28×26, nút dán tô màu nhấn,
/// icon sao chép/dán là `AppGlyph`), nhưng **dán thay cả giá trị** thay vì nối thêm dòng — ô ở đây là URL, khoá,
/// tên… chỉ có một giá trị. Dùng ở màn Cấu hình tiện ích (biến cấu hình) và màn "Thông tin plugin.json".
///
/// `.buttonStyle(.borderless)` là bắt buộc: trong một dòng của `Form`, nút kiểu mặc định làm chạm bất kỳ đâu trên
/// dòng là bấm **mọi** nút của dòng đó.
struct TextFieldClipboardButtons: View {
    @Binding var text: String
    /// Giá trị mặc định của ô; khác rỗng thì có nút ↺ (chỉ hiện khi giá trị đang khác mặc định).
    var defaultValue: String? = nil

    private var canRestoreDefault: Bool {
        guard let defaultValue, !defaultValue.isEmpty else { return false }
        return text != defaultValue
    }

    var body: some View {
        HStack(spacing: 6) {
            if canRestoreDefault, let defaultValue {
                button(accessibility: "Khôi phục mặc định", action: { text = defaultValue }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
            }

            button(accessibility: "Xoá", tone: .destructive, isEnabled: !text.isEmpty, action: { text = "" }) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .disabled(text.isEmpty)

            button(accessibility: "Sao chép", action: { ClipboardCopier.copy(text) }) {
                AppGlyph.copy.image(size: 13)
            }
            .disabled(text.isEmpty)

            button(accessibility: "Dán", tone: .accent, action: pasteReplacing) {
                AppGlyph.paste.image(size: 13)
            }
        }
    }

    private func pasteReplacing() {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else { return }
        text = clip
    }

    /// Màu ô nút: thường (xám), nhấn (dán), đỏ (xoá chữ).
    private enum Tone {
        case normal, accent, destructive

        var foreground: Color {
            switch self {
            case .normal: return .secondary
            case .accent: return .accentColor
            case .destructive: return .red
            }
        }

        var background: Color {
            switch self {
            case .normal: return Color.secondary.opacity(0.12)
            case .accent: return Color.accentColor.opacity(0.15)
            case .destructive: return Color.red.opacity(0.15)
            }
        }
    }

    /// `isEnabled` chỉ để làm mờ ô đỏ (màu tường minh không tự mờ khi `disabled`); `.disabled` vẫn gắn ở chỗ gọi.
    private func button<Content: View>(
        accessibility: String,
        tone: Tone = .normal,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: 28, height: 26)
                .foregroundColor(tone.foreground)
                .background(tone.background)
                .cornerRadius(5)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibility)
    }
}
