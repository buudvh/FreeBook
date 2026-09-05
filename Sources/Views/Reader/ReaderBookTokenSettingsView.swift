import SwiftUI

/// Công tắc token DSL **riêng của một truyện**, mở từ Cài đặt trình đọc.
///
/// Ba trạng thái mỗi token thay vì bật/tắt: trạng thái *Chung* là kế thừa thật, nên sửa cài đặt
/// chung vẫn lan tới truyện chưa đặt riêng. Nếu chỉ có bật/tắt thì lần đầu mở màn này là truyện đóng
/// băng giá trị chung hiện tại.
struct ReaderBookTokenSettingsView: View {
    typealias Store = QuickTranslationBookEngineConfigStore
    typealias Kind = QuickTranslationRuleTokenSettings.Kind

    let bookId: String

    @State private var overrides: [Kind: Store.TokenOverride]

    /// Nạp state ngay ở `init` chứ không ở `onAppear`: nạp trong `onAppear` là một lần đổi state, và
    /// `onChange` bên dưới sẽ hiểu đó là người dùng vừa sửa cả 10 token rồi ghi đĩa 10 lần.
    init(bookId: String) {
        self.bookId = bookId
        _overrides = State(initialValue: Self.loadOverrides(bookId: bookId))
    }

    private static func loadOverrides(bookId: String) -> [Kind: Store.TokenOverride] {
        var result: [Kind: Store.TokenOverride] = [:]
        for kind in Kind.allCases {
            result[kind] = Store.shared.tokenOverride(for: kind, bookId: bookId)
        }
        return result
    }

    var body: some View {
        Form {
            Section {
                ForEach(Kind.allCases.filter(\.isNumeralGroup), id: \.self, content: row)
            } header: {
                Text("Token số và nhãn")
            }

            Section {
                ForEach(Kind.allCases.filter { !$0.isNumeralGroup }, id: \.self, content: row)
            } header: {
                Text("Token từ điển")
            }

            Section {
                Text("Chung là theo cài đặt chung của app. Tắt riêng làm mọi rule có chứa token đó ngừng chạy CHO TRUYỆN NÀY — kể cả token nằm trong nhóm ( | ) hoặc phần tuỳ chọn ?. File rule không bị sửa và các truyện khác không bị ảnh hưởng.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("Áp cho cả trình đọc và đọc thành tiếng của truyện này.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Token rule của truyện")
        .navigationBarTitleDisplayMode(.inline)
        // Ghi ở `onChange` chứ không trong setter của `Binding`: setter là closure escaping, còn thân
        // modifier chạy cùng ngữ cảnh với `body` nên gọi được `ToastManager` (`@MainActor`).
        .onChange(of: overrides) { previous, current in
            for kind in Kind.allCases where previous[kind] != current[kind] {
                apply(current[kind] ?? .inherit, for: kind)
            }
        }
    }

    private func row(_ kind: Kind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.label)
                .font(.subheadline)

            Picker(kind.label, selection: binding(for: kind)) {
                ForEach(Store.TokenOverride.allCases, id: \.self) { override in
                    Text(override.shortTitle).tag(override)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(effectiveDescription(for: kind))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Setter chỉ đổi state; phần ghi đĩa do `onChange` ở trên lo.
    private func binding(for kind: Kind) -> Binding<Store.TokenOverride> {
        Binding(
            get: { overrides[kind] ?? .inherit },
            set: { overrides[kind] = $0 }
        )
    }

    /// Ghi thất bại thì nạp lại từ đĩa để UI không nói dối. Lần nạp lại đó lại chạy qua `onChange`
    /// một lượt nữa, nhưng lượt đó ghi đúng giá trị đang có trên đĩa nên vòng lặp dừng ngay.
    private func apply(_ override: Store.TokenOverride, for kind: Kind) {
        let outcome = Store.shared.setTokenOverride(override, for: kind, bookId: bookId)
        if case .failure(let message) = outcome {
            ToastManager.shared.show(message: message, type: .error)
            reload()
            return
        }
        // Đúng khuôn hai công tắc dịch theo truyện ở `ReaderView`: một lời gọi, scope `.config` mang
        // `bookId`. `notifyDictionariesDidUpdate` đã tự `TranslateUtils.invalidateCache` bên trong.
        TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil, scope: .config(bookId: bookId))
    }

    /// Nói rõ **trạng thái đang có hiệu lực**, không chỉ trạng thái đã chọn — với `inherit` thì phải
    /// tra cài đặt chung mới biết token đang bật hay tắt.
    private func effectiveDescription(for kind: Kind) -> String {
        switch overrides[kind] ?? .inherit {
        case .inherit:
            return QuickTranslationRuleTokenSettings.isEnabled(kind)
                ? "Theo cài đặt chung — hiện đang bật."
                : "Theo cài đặt chung — hiện đang tắt."
        case .enabled:
            return "Bật cho truyện này, kể cả khi cài đặt chung đang tắt."
        case .disabled:
            return "Tắt cho truyện này: mọi rule có chứa token này không chạy ở truyện này."
        }
    }

    private func reload() {
        overrides = Self.loadOverrides(bookId: bookId)
    }
}
