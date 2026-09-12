import SwiftUI

/// Thanh tìm kiếm sách dùng chung: tách nguyên mẫu từ `ShelfSearchView.searchBarView`
/// để màn Kệ sách/Lịch sử và sheet chọn truyện đích dùng cùng một UI, cùng hành vi
/// (nút xóa nhanh, tắt autocorrect/autocapitalize, lọc realtime theo từng ký tự).
struct BookSearchBarView: View {
    @Binding var text: String
    var placeholder: String = "Tìm truyện hoặc tác giả..."
    var onCommit: (() -> Void)? = nil

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
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
