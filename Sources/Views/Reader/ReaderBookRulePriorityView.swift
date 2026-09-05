import SwiftUI

/// Thứ tự ưu tiên rule **riêng của một truyện**, mở từ Cài đặt trình đọc.
///
/// Áp cho cả trình đọc và đọc thành tiếng của truyện đó, vì cả hai đều đi qua
/// `QuickTranslationRuleEngine.rewrite(_:bookId:)` với cùng `bookId`.
struct ReaderBookRulePriorityView: View {
    let bookId: String

    @State private var isUsingBookConfiguration: Bool
    @State private var configuration: QuickTranslationRulePriorityConfiguration.Configuration

    init(bookId: String) {
        self.bookId = bookId
        let store = QuickTranslationBookEngineConfigStore.shared
        _isUsingBookConfiguration = State(initialValue: store.hasPriorityOverride(bookId: bookId))
        _configuration = State(initialValue: store.priorityConfiguration(bookId: bookId))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Đặt riêng cho truyện này", isOn: $isUsingBookConfiguration)
            } footer: {
                Text(isUsingBookConfiguration
                    ? "Truyện này dùng thứ tự bên dưới cho cả trình đọc và đọc thành tiếng. Sửa cài đặt chung sẽ không còn ảnh hưởng tới nó."
                    : "Truyện này đang theo cài đặt chung. Sửa cài đặt chung sẽ tự động áp vào đây.")
            }

            if isUsingBookConfiguration {
                QuickTranslationRulePriorityListView(configuration: $configuration)
            }
        }
        .navigationTitle("Thứ tự ưu tiên rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if isUsingBookConfiguration { EditButton() } }
        .onChange(of: isUsingBookConfiguration) { _, isOn in
            save(isOn ? configuration : nil)
        }
        .onChange(of: configuration) { _, newValue in
            guard isUsingBookConfiguration else { return }
            save(newValue)
        }
    }

    private func save(_ value: QuickTranslationRulePriorityConfiguration.Configuration?) {
        let outcome = QuickTranslationBookEngineConfigStore.shared.setPriority(value, bookId: bookId)
        if case .failure(let message) = outcome {
            ToastManager.shared.show(message: message, type: .error)
            return
        }
        // Đúng khuôn hai công tắc dịch theo truyện ở `ReaderView`: một lời gọi, scope `.config` mang
        // `bookId`. `notifyDictionariesDidUpdate` đã tự `TranslateUtils.invalidateCache` bên trong.
        TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil, scope: .config(bookId: bookId))
    }
}
