import SwiftUI

/// Section chọn nhóm nội dung sao lưu / khôi phục, kèm dung lượng ước tính từng nhóm.
///
/// Dung lượng đo bằng cách quét thư mục nên tính **một lần** ngoài main thread rồi giữ trong
/// `@State`. Phép đo gắn vào header (một view lá, luôn có) để chắc chắn chạy đúng một lượt — gắn vào
/// `ForEach` thì mỗi hàng sẽ chạy một lần. Giải thích nằm ở nút "?" của header; footer chỉ còn con số ước tính.
struct BackupScopeToggleList: View {
    @Binding var selection: Set<BackupScope>
    var header: String = "Nội dung sao lưu"
    /// Chỉ hiện các nhóm này — màn Khôi phục chỉ hiện nhóm có thật trong file sao lưu.
    var availableScopes: [BackupScope] = BackupScope.displayOrder
    /// Tắt khi con số dung lượng của máy hiện tại không nói gì về file sao lưu (màn Khôi phục).
    var showsEstimatedSize = true

    @State private var sizes: [BackupScope: Int64] = [:]

    var body: some View {
        Section {
            ForEach(availableScopes) { scope in
                row(for: scope)
            }
        } header: {
            SectionHelpHeader(header, texts: [Text(helpText)])
                .task {
                    guard showsEstimatedSize, sizes.isEmpty else { return }
                    sizes = await Self.measure(scopes: availableScopes)
                }
        } footer: {
            if let estimateText {
                Text(estimateText)
            }
        }
    }

    private var helpText: String {
        showsEstimatedSize
            ? "Ảnh bìa không được sao lưu — bìa tải lại được từ liên kết gốc."
            : "Nhóm bị tắt sẽ không được ghi vào dữ liệu hiện có."
    }

    /// Con số ước tính (trạng thái) — giữ ở footer; `nil` khi chưa đo xong hoặc không chọn nhóm nào.
    private var estimateText: String? {
        guard showsEstimatedSize else { return nil }
        let total = selection.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
        guard total > 0 else { return nil }
        return "Ước tính trước khi nén: \(BackupSizeEstimator.format(total))."
    }

    private func row(for scope: BackupScope) -> some View {
        Toggle(isOn: binding(for: scope)) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(scope.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if showsEstimatedSize, let size = sizes[scope], size > 0 {
                        Text(BackupSizeEstimator.format(size))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Text(scope.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(white: 0.35)))
        .disabled(scope.isMandatory)
    }

    private func binding(for scope: BackupScope) -> Binding<Bool> {
        Binding(
            get: { selection.contains(scope) },
            set: { isOn in
                guard !scope.isMandatory else { return }
                if isOn {
                    selection.insert(scope)
                } else {
                    selection.remove(scope)
                }
            }
        )
    }

    private static func measure(scopes: [BackupScope]) async -> [BackupScope: Int64] {
        await Task.detached(priority: .utility) { () -> [BackupScope: Int64] in
            var result: [BackupScope: Int64] = [:]
            for scope in scopes {
                result[scope] = BackupSizeEstimator.estimatedBytes(for: scope)
            }
            return result
        }.value
    }
}
