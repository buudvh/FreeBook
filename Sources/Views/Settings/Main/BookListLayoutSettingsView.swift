import SwiftUI

/// Cài đặt → Chung → Giao diện → **Kiểu hiển thị danh sách**: chỉnh cả 4 scope ở một chỗ. Sheet nhanh trên từng màn chỉ
/// chỉnh scope đang xem; màn này để xem/đặt lại toàn bộ.
struct BookListLayoutSettingsView: View {
    var body: some View {
        Form {
            ForEach(BookListLayoutScope.allCases) { scope in
                Section {
                    BookListLayoutControls(scope: scope)
                } header: {
                    if scope == .video {
                        SectionHelpHeader(scope.settingsTitle, paragraphs: ["Bìa phim/video luôn ngang 16:9."])
                    } else {
                        Text(scope.settingsTitle)
                    }
                }
            }

            Section {
                Button("Đặt lại mặc định") {
                    BookListLayoutPreferences.shared.resetAll()
                }
                .frame(maxWidth: .infinity)
            } header: {
                SectionHelpHeader("Phạm vi áp dụng", paragraphs: ["Dùng chung cho Kệ và Khám phá. \"Tất cả\" dùng bìa đứng cho mọi truyện để các hàng lưới cao bằng nhau."])
            }
        }
        .backPageTitle("Kiểu hiển thị danh sách")
    }
}
