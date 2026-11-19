import SwiftUI

/// Trang "Thử nhanh một câu" (Công cụ của màn Quản lý rule dịch): dán một câu Trung → xem text sau rewrite và **rule
/// nào khớp ở offset nào**. Công cụ debug chính khi rule không nổ như mong đợi.
///
/// Ruột dùng chung với sheet "Thử rule" ở đầu danh sách rule (`QuickTranslationRuleTesterPanel`); trang này thêm phần
/// chọn chế độ token (theo cấu hình hiện hành hoặc tạm coi mọi token là bật). Mở từ Cài đặt nên không có truyện nào
/// đang mở ⇒ mặc định chỉ áp bộ rule chung.
struct QuickTranslationRuleTesterView: View {
    var scope: QuickTranslationRuleScope = .global

    var body: some View {
        Form { Group {
            QuickTranslationRuleTesterPanel(scope: scope, showsTokenModePicker: true)
        }.glassSheetRows() }
        .backPageTitle("Thử nhanh rule")
    }
}
