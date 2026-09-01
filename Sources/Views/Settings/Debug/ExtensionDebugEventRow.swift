import SwiftUI

/// Một dòng trace. Chỉ hiển thị những gì `ExtensionDebugEvent` đã mang sẵn — view **không** được tự
/// lấy thêm dữ liệu thô (body, header, nội dung chương): redaction thuộc tầng Services và phải đã xong
/// trước khi event tới đây.
struct ExtensionDebugEventRow: View {
    let event: ExtensionDebugEvent

    private var tint: Color {
        switch event.level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(event.categoryLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(minWidth: 48, alignment: .leading)

                Text(event.message)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let location = event.location {
                Text(location.displayText + " @" + location.revision)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !event.details.isEmpty {
                Text(event.sortedDetails.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let stack = event.location?.stack, !stack.isEmpty, event.level == .error {
                Text(stack)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
