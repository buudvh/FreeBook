import SwiftUI

/// Sheet nhỏ đổi kiểu hiển thị cho **một** scope: mở từ menu "…" của Kệ sách, nút tròn trên header Khám phá,
/// thanh điều hướng màn Thể loại và menu của Bộ sưu tập. Ghi thẳng vào `BookListLayoutPreferences`, nên danh
/// sách phía sau (vẫn thấy được vì sheet thấp) đổi ngay khi bấm.
///
/// Khám phá truyền `showsExploreSizes: true` ⇒ thêm nhóm "Trang Khám phá" (cỡ từng bố cục, `ExploreLayoutSizeControls`):
/// sheet cao nửa màn, kéo lên được, nội dung cuộn — nửa trên vẫn thấy trang để xem cỡ đổi ngay.
struct BookListLayoutSheet: View {
    let scope: BookListLayoutScope
    var showsExploreSizes: Bool = false

    var body: some View {
        if showsExploreSizes {
            ScrollView {
                content
                    .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .presentationDetents([.medium, .large])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
        } else {
            content
                .padding(20)
                // Đủ chỗ cho thanh "Cỡ dòng" (cao hơn bước "Số cột") cộng dòng ghi chú của Video.
                .presentationDetents([.height(268)])
                .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
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
            }

            BookListLayoutControls(scope: scope)

            if scope == .video {
                Text("Loại Video có bìa ngang 16:9.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if showsExploreSizes {
                exploreSizes
            }

            Spacer(minLength: 0)
        }
    }

    private var exploreSizes: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            Text("Trang Khám phá")
                .font(.headline)
            ExploreLayoutSizeControls(scope: scope)
        }
    }
}
