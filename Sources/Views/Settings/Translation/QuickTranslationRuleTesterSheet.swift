import SwiftUI

/// Sheet **"Thử rule"** mở từ hàng pill ở đầu danh sách rule (`QuickTranslationRuleTesterPill`, cả ba phạm vi): tiêu đề
/// trái "Thử rule", ô nhập câu, KẾT QUẢ, RULE ĐÃ KHỚP (dòng · offset · bộ, mẫu, nguồn → kết quả). Ruột chung với trang
/// "Thử nhanh một câu" (`QuickTranslationRuleTesterPanel`), áp bộ rule theo `scope` của danh sách đang mở.
///
/// Chỗ trình bày bọc `Group { … }.appGlassSheet()` (chuẩn sheet kính); detent 60% / lớn + thanh kéo nằm ở đây.
struct QuickTranslationRuleTesterSheet: View {
    let scope: QuickTranslationRuleScope

    var body: some View {
        NavigationStack {
            Form { Group {
                QuickTranslationRuleTesterPanel(scope: scope)
            }.glassSheetRows() }
            .pageTitle("Thử rule")
        }
        .presentationDetents([.fraction(0.6), .large])
        .presentationDragIndicator(.visible)
    }
}
