import SwiftUI

/// Nhóm "Chung" đầu tab Cài đặt: cài đặt dùng cho cả app, không thuộc Đọc & Nghe hay Thư Viện. Như mọi nhóm của tab
/// này, chỉ chứa dòng điều hướng sang màn con.
struct GeneralSettingsSection: View {
    var body: some View {
        Section(header: Text("Chung")) {
            NavigationLink(destination: KeyboardSettingsView()) {
                Label("Bàn phím & ô nhập", systemImage: "keyboard")
            }
        }
    }
}
