import SwiftUI

/// Màn con **"Thông tin plugin.json"** (nhóm Nâng cao của màn Cấu hình tiện ích): bọc `ExtensionMetadataSection`
/// nguyên trạng — 6 trường sửa được tự lưu, 3 trường chỉ đọc. Thẻ đầu của màn cấu hình chỉ để xem; sửa ở đây.
///
/// Được đẩy trong `NavigationStack` của `ExtensionConfigView` nên không tự bọc stack.
struct ExtensionMetadataScreen: View {
    let ext: Extension

    var body: some View {
        Form {
            ExtensionMetadataSection(ext: ext)
        }
        .scrollDismissesKeyboard(.interactively)
        .backPageTitle("Thông tin plugin.json")
    }
}
