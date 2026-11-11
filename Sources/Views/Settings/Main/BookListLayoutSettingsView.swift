import SwiftUI

/// Cài đặt → Chung → Giao diện → **Kiểu hiển thị danh sách**: chỉnh cả 5 scope ở một chỗ, kèm cỡ từng bố cục trang
/// Khám phá cho truyện chữ / truyện tranh / video / âm thanh. Sheet nhanh trên từng màn chỉ chỉnh scope đang xem; màn
/// này để xem/đặt lại toàn bộ.
struct BookListLayoutSettingsView: View {
    var body: some View {
        Form { Group {
            ForEach(BookListLayoutScope.allCases) { scope in
                Section {
                    BookListLayoutControls(scope: scope)
                } header: {
                    if scope == .video {
                        SectionHelpHeader(scope.settingsTitle, paragraphs: ["Bìa phim/video luôn ngang 16:9."])
                    } else if scope == .audio {
                        SectionHelpHeader(scope.settingsTitle, paragraphs: ["Bìa album âm thanh luôn vuông 1:1."])
                    } else {
                        Text(scope.settingsTitle)
                    }
                }

                if ExploreLayoutSizePreferences.scopes.contains(scope) {
                    Section {
                        ExploreLayoutSizeControls(scope: scope)
                    } header: {
                        SectionHelpHeader(
                            "\(scope.label) · Trang Khám phá",
                            paragraphs: [
                                "Cỡ thẻ ở tab Trang chủ của nguồn có trang Khám phá. Nấc 4 là mặc định.",
                                "Lưới: to hơn thì ít cột hơn. Banner: to hơn thì cao hơn. Hàng chip không đổi cỡ."
                            ]
                        )
                    }
                }
            }

            Section {
                Button("Đặt lại mặc định") {
                    BookListLayoutPreferences.shared.resetAll()
                    ExploreLayoutSizePreferences.shared.resetAll()
                }
                .frame(maxWidth: .infinity)
            } header: {
                SectionHelpHeader("Phạm vi áp dụng", paragraphs: ["Dùng chung cho Kệ và Khám phá. \"Tất cả\" dùng bìa đứng cho mọi truyện để các hàng lưới cao bằng nhau."])
            }
        }.glassSheetRows() }
        .backPageTitle("Kiểu hiển thị danh sách")
    }
}
