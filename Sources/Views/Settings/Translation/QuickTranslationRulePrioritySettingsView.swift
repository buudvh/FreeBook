import SwiftUI

/// Thứ tự ưu tiên rule ở **phạm vi chung** — áp cho mọi truyện chưa đặt riêng.
///
/// Không sửa file rule: chỉ đổi cách chọn giữa hai rule cùng khớp và chồng lên nhau.
struct QuickTranslationRulePrioritySettingsView: View {
    @State private var configuration = QuickTranslationRulePriorityConfiguration.globalConfiguration()

    var body: some View {
        Form {
            QuickTranslationRulePriorityListView(configuration: $configuration)

            Section {
                Text("Cấu hình này áp cho mọi truyện. Muốn một truyện dùng thứ tự khác thì mở truyện đó, vào Cài đặt trình đọc và chọn Thứ tự ưu tiên rule.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Đổi thứ tự không sửa file rule và không tắt rule nào. Nó chỉ đổi việc rule nào được áp khi hai rule tranh nhau cùng một chỗ trong câu.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Thứ tự ưu tiên rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onChange(of: configuration) { _, newValue in
            QuickTranslationRulePriorityConfiguration.storeGlobal(newValue)
            // Đúng khuôn `QuickTranslationRuleTokenSettingsView`: dọn cache dịch rồi phát **một**
            // thông báo để Reader/TTS dựng lại, không tạo đường refresh thứ hai.
            TranslateUtils.clearCache()
            TranslationManager.shared.notifyDictionariesDidUpdate()
        }
    }
}
