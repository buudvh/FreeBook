import SwiftUI

/// Section chọn nhóm nội dung sao lưu / khôi phục, kèm dung lượng ước tính từng nhóm.
///
/// Dung lượng đo bằng cách quét thư mục nên tính **một lần** ngoài main thread rồi giữ trong
/// `@State`. Phép đo gắn vào footer (một view lá) để chắc chắn chạy đúng một lượt — gắn vào
/// `ForEach` thì mỗi hàng sẽ chạy một lần.
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
            Text(header)
        } footer: {
            footer
        }
    }

    private var footer: some View {
        Text(footerText)
            .task {
                guard showsEstimatedSize, sizes.isEmpty else { return }
                sizes = await Self.measure(scopes: availableScopes)
            }
    }

    private var footerText: String {
        guard showsEstimatedSize else {
            return "Nhóm bị tắt sẽ không được ghi vào dữ liệu hiện có."
        }
        let total = selection.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
        guard total > 0 else {
            return "Ảnh bìa không được sao lưu — bìa tải lại được từ liên kết gốc."
        }
        return "Ước tính trước khi nén: \(BackupSizeEstimator.format(total))."
            + " Ảnh bìa không được sao lưu — bìa tải lại được từ liên kết gốc."
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
