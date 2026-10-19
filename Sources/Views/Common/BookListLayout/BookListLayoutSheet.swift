import SwiftUI

/// Sheet nhỏ đổi kiểu hiển thị cho **một** scope: mở từ menu "…" của Kệ sách, nút tròn trên header Khám phá,
/// thanh điều hướng màn Thể loại và menu của Bộ sưu tập. Ghi thẳng vào `BookListLayoutPreferences`, nên danh
/// sách phía sau (vẫn thấy được vì sheet thấp) đổi ngay khi bấm.
struct BookListLayoutSheet: View {
    let scope: BookListLayoutScope

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kiểu hiển thị")
                        .font(.headline)
                    Text("Áp cho: \(scope.label)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Xong") { dismiss() }
                    .fontWeight(.semibold)
            }

            BookListLayoutControls(scope: scope)

            if scope == .video {
                Text("Loại Video có bìa ngang 16:9.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
    }
}
