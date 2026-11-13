import SwiftUI

/// Hàng "Dọn rác" ngay dưới "Tự động dọn" ở màn Dung lượng: lối vào `JunkCleanupView`, ghi dung lượng rác của lần đo
/// gần nhất (màu cam; không có rác ⇒ "Không có"; bản đo cũ chưa có số ⇒ để trống).
struct JunkCleanupRow: View {
    let junkBytes: Int64?

    var body: some View {
        NavigationLink(destination: JunkCleanupView()) {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                Text("Dọn rác")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let junkBytes {
                    Text(junkBytes > 0 ? StorageUsageSnapshot.format(junkBytes) : "Không có")
                        .font(.subheadline)
                        .foregroundStyle(junkBytes > 0 ? Color.orange : Color.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }
}
