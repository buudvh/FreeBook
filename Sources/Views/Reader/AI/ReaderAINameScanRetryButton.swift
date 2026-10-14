import SwiftUI

/// Nút "Thử lại k lượt lỗi" ngay dưới tin kết quả quét tên riêng nhiều chương (1.3.527).
///
/// Chỉ hiện khi coordinator còn giữ lượt **vẫn** lỗi sau vòng tự thử lại cho đúng tin đó, và không có lệnh AI nào đang
/// chạy (màn AI quyết định). Tông tím giống chip "Lọc name nhiều chương"; viên thuốc cao 28 pt nhưng vùng chạm 36 pt.
public struct ReaderAINameScanRetryButton: View {
    public let failedCount: Int
    public let onRetry: () -> Void

    public init(failedCount: Int, onRetry: @escaping () -> Void) {
        self.failedCount = failedCount
        self.onRetry = onRetry
    }

    public var body: some View {
        Button(action: onRetry) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                Text("Thử lại \(failedCount) lượt lỗi")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundColor(.purple)
            .background(Capsule().fill(Color.purple.opacity(0.15)))
            .overlay(Capsule().stroke(Color.purple.opacity(0.3), lineWidth: 1))
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thử lại \(failedCount) lượt quét tên riêng bị lỗi")
    }
}
