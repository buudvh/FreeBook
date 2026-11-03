import SwiftUI

/// Viên thuốc "NSFW" ở đầu phải dòng tiêu đề ngăn kéo chọn nguồn; bật thì tô màu nhấn như chip đang chọn của
/// `ExtensionKindFilterBar`. Công tắc **toàn app** (chung khoá với Cài đặt và bộ lọc Kho): danh sách nguồn do
/// `DiscoveryView` lọc theo cùng khoá nên bấm là đổi ngay; tắt khi đang xem nguồn NSFW thì Khám phá tự chuyển nguồn.
///
/// Viên thuốc nhỏ (cao 26pt, chữ 12pt) theo yêu cầu người dùng — nhỏ hơn chuẩn nút header 38pt; vùng chạm vẫn cao 38pt
/// nhờ khung trong suốt bọc ngoài. Tự đọc `@AppStorage` nên vẽ lại được trong cửa sổ ngăn kéo.
struct ExtensionNsfwToggle: View {
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    var body: some View {
        Button(action: { includeNsfw.toggle() }) {
            HStack(spacing: 3) {
                Image(systemName: includeNsfw ? "eye" : "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text("NSFW")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .foregroundColor(includeNsfw ? .accentColor : .secondary)
            .background(includeNsfw ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(includeNsfw ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .frame(minWidth: 36, minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hiện nội dung nhạy cảm (NSFW)")
        .accessibilityAddTraits(includeNsfw ? .isSelected : [])
    }
}
