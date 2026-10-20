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

            button(accessibility: "Xoá", action: { text = "" }) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .disabled(text.isEmpty)

            button(accessibility: "Sao chép", action: { UIPasteboard.general.string = text }) {
                AppGlyph.copy.image(size: 13)
            }
            .disabled(text.isEmpty)

            button(accessibility: "Dán", isAccent: true, action: pasteReplacing) {
                AppGlyph.paste.image(size: 13)
            }
        }
    }

    private func pasteReplacing() {
        guard let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else { return }
        text = clip
    }

    private func button<Content: View>(
        accessibility: String,
        isAccent: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: 28, height: 26)
                .foregroundColor(isAccent ? .accentColor : .secondary)
                .background(isAccent ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                .cornerRadius(5)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibility)
    }
}
