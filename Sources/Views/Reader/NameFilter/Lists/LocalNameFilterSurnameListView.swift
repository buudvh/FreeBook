import SwiftUI

/// Màn **Họ** của Lọc name local (L13, plan 2026-11-27-phan-loai-name — anh Bửu: "Màn quản lý họ riêng cho lọc luôn"):
/// danh sách họ riêng của bộ lọc (`QuickTranslationSurnameStore.nameFilter`, file gốc `NameFilterSurnames.txt` = 683 họ của
/// `<ho>` + 洛 Lạc, 玉 Ngọc), độc lập với Danh sách họ của token `<ho>`. Dùng lại nguyên màn
/// `QuickTranslationSurnameListView` (Sửa từ, nhập file 3 cách, xuất file, khôi phục mặc định, tắt / bật, xoá) — chỉ đổi
/// store + chữ qua `Context`.
///
/// `init()` không tham số, dùng `.backPageTitle` như `LocalNameFilterSuffixListView` ⇒ đẩy vào `NavigationStack` của sheet
/// Lọc name local bằng `NavigationLink`. Số họ cho hàng ở sheet: `QuickTranslationSurnameStore.nameFilter.summary()`, đọc lại
/// ở `onAppear` khi quay về (store không phát thay đổi).
struct LocalNameFilterSurnameListView: View {
    var body: some View {
        QuickTranslationSurnameListView(context: Self.context)
    }

    private static var context: QuickTranslationSurnameListView.Context {
        QuickTranslationSurnameListView.Context(
            store: .nameFilter,
            title: "Họ",
            exportFileName: "NameFilterSurnames.txt",
            helpTexts: [
                Text("Lọc name local dùng danh sách này để nhận ra **tên người** (họ + tên: 陈平安, 欧阳锋) và lấy **âm họ** khi ghép nghĩa (欧阳锋 → Âu Dương Phong)."),
                // `verbatim`: chữ `<ho>` không được đi qua bộ đọc markdown.
                Text(verbatim: "Danh sách riêng của bộ lọc, độc lập với Danh sách họ của token <ho> trong rule dịch nhanh: sửa ở đây không đổi bản dịch, sửa ở đó không đổi kết quả lọc. Lần đầu dùng, các họ đã thêm, sửa, xoá hoặc tắt ở Danh sách họ được chép sang một lần."),
                Text("Họ đang tắt vẫn nằm trong danh sách nhưng bộ lọc không dùng; họ có chữ là hư từ (于, 和…) bộ lọc tự bỏ qua."),
                Text("Mỗi họ 1 hoặc 2 chữ Hán, âm viết hoa sẵn (陈 = Trần). Nhập file dạng 王=Vương, mỗi dòng một họ; xuất file bỏ họ đang tắt. \"Khôi phục mặc định\" ở menu … bỏ mọi thay đổi."),
                Text("Sửa danh sách có hiệu lực từ lần bấm \"Bắt đầu lọc\" sau.")
            ],
            emptyListText: "Danh sách họ đang trống: bộ lọc sẽ không nhận ra tên người theo họ. Bấm + để thêm."
        )
    }
}
