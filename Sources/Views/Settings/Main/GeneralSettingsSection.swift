import SwiftUI

/// Nhóm "Chung" đầu tab Cài đặt: cài đặt dùng cho cả app, không thuộc Đọc & Nghe hay Thư Viện. Như mọi nhóm của tab
/// này, chỉ chứa dòng điều hướng sang màn con. Từ 1.3.636 "Bàn phím & ô nhập", "Kiểu hiển thị danh sách" và "Nội dung
/// nhạy cảm (NSFW)" nằm trong màn **Giao diện** (`AppearanceSettingsView`), không còn dòng riêng ở ngoài.
struct GeneralSettingsSection: View {
    var body: some View {
        Section(header: Text("Chung")) {
            NavigationLink(destination: AppearanceSettingsView()) {
                Label("Giao diện", systemImage: "paintpalette")
            }
        }
    }
}
