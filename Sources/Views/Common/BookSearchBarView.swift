import SwiftUI

/// Thanh tìm kiếm sách dùng chung: tách nguyên mẫu từ `ShelfSearchView.searchBarView`
/// để màn Kệ sách/Lịch sử và sheet chọn truyện đích dùng cùng một UI, cùng hành vi
/// (nút xóa nhanh, tắt autocorrect/autocapitalize, lọc realtime theo từng ký tự).
struct BookSearchBarView: View {
    @Binding var text: String
    var placeholder: String = "Tìm truyện hoặc tác giả..."
    var onCommit: (() -> Void)? = nil
    @AppStorage(EInkModeSettings.Key.enabled) private var isEInkEnabled = false
    @AppStorage(EInkModeSettings.Key.paperColor) private var paperColorRaw = EInkModeSettings.EInkPaperColor.gray.rawValue
    private var paper: Color {
        EInkPalette.paperColor(for: EInkModeSettings.EInkPaperColor(rawValue: paperColorRaw) ?? .gray)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(placeholder, text: $text, onCommit: {
                    onCommit?()
                })
                .autocorrectionDisabled()
                .textInputAutocapitalization(.none)

                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Xóa từ khóa tìm kiếm")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isEInkEnabled ? paper : Color(.secondarySystemBackground))
            .cornerRadius(10)
            .overlay {
                if isEInkEnabled {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(EInkPalette.ink, lineWidth: EInkPalette.borderWidth)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .einkBackground(Color(.systemBackground))
    }
}
