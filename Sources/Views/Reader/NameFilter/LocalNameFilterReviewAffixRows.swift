import SwiftUI

/// Khối **hàng phụ** của màn Sửa từ khi mở từ màn duyệt Lọc name local (`DictEntryEditSheet.accessoryRows`, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2 / N6): "Phân loại" (`LocalNameFilterReviewCategoryRow`) trên
/// cùng, "Nới đoán tên Latin" (`LocalNameFilterReviewLooseRow`, chỉ khi truyện bật "Ưu tiên tên Latin"), rồi "Tiền tố" (có
/// nút ⚙ cuối dòng nhãn) và "Hậu tố" (`LocalNameFilterSuffixQuickRow`). Mọi name trừ họ tộc.
///
/// Giữ màn **Quản lý tiền tố, hậu tố** (`LocalNameFilterAffixManagerView`) — trình bày ở đây (trong cây view của sheet Sửa
/// từ), không ở màn duyệt: màn duyệt đang trình bày sheet Sửa từ nên không mở thêm sheet được. Mỗi lần một hàng / màn quản
/// lý ghi danh sách ⇒ tăng `revision` để cả hai hàng đọc lại (hàng không tự biết hàng kia hay màn quản lý vừa ghi; `onAppear`
/// không chạy lại khi sheet phủ lên đóng) rồi báo màn duyệt (`onAffixChanged` ⇒ ghép lại nghĩa + toast).
///
/// Nằm trọn trong `accessoryRows` nên nấc vừa khít của màn Sửa từ tự tính cả hàng Phân loại và hàng Nới (ghi chú
/// `loc-review-ui-a`): hàng Nới hiện / ẩn quyết định một lần lúc dựng sheet (đồng bộ, không chờ gì), có ngay từ lần đo đầu.
struct LocalNameFilterReviewAffixRows: View {
    typealias Flavor = LocalNameFilterAffixListFlavor

    let name: String
    let bookId: String
    /// Loại gợi ý cho mục mới = nhóm hiện tại của name.
    let kind: LocalNameFilter.SuffixKind
    /// Nhóm đang hiện ở badge.
    let category: LocalNameFilter.Category?
    /// Nhóm lúc lọc nếu lượt duyệt còn nhớ (`LocalNameFilterReviewSuffixContext.originalCategory`).
    let originalCategory: LocalNameFilter.Category?
    let onCategoryChange: (LocalNameFilter.Category) -> Void
    /// Công tắc "Nới đoán tên Latin" của riêng name này (giá trị mở đầu); `nil` = không có hàng (truyện tắt "Ưu tiên tên
    /// Latin", gói cũ chưa có nghĩa máy ghép). Cố định khi sheet mở ⇒ nấc vừa khít đo đúng ngay lần đầu.
    let loosensLatin: Bool?
    let onLooseChange: (Bool) -> Void
    /// Một mục vừa thêm / sửa / xoá: danh sách, khoá, khoá cũ khi đổi chữ, động từ của toast.
    let onAffixChanged: (_ flavor: Flavor, _ key: String, _ replaced: String?, _ verb: String) -> Void

    @State private var revision = 0
    @State private var showingManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LocalNameFilterReviewCategoryRow(selection: category, original: originalCategory, onSelect: onCategoryChange)
            if let loosensLatin {
                LocalNameFilterReviewLooseRow(isOn: loosensLatin, onChange: onLooseChange)
            }
            LocalNameFilterSuffixQuickRow(
                flavor: .prefix, name: name, bookId: bookId, kind: kind, revision: revision,
                onManage: { showingManager = true },
                onSaved: { key, replaced, isNew in
                    changed(.prefix, key: key, replaced: replaced, verb: isNew ? "Đã thêm" : "Đã lưu")
                }
            )
            LocalNameFilterSuffixQuickRow(
                flavor: .suffix, name: name, bookId: bookId, kind: kind, revision: revision,
                onSaved: { key, replaced, isNew in
                    changed(.suffix, key: key, replaced: replaced, verb: isNew ? "Đã thêm" : "Đã lưu")
                }
            )
        }
        .sheet(isPresented: $showingManager, onDismiss: { revision += 1 }) {
            Group {
                LocalNameFilterAffixManagerView(name: name, bookId: bookId, kind: kind) { flavor, key, replaced, verb in
                    changed(flavor, key: key, replaced: replaced, verb: verb)
                }
            }
            .appGlassSheet()
        }
    }

    private func changed(_ flavor: Flavor, key: String, replaced: String?, verb: String) {
        revision += 1
        onAffixChanged(flavor, key, replaced, verb)
    }
}
