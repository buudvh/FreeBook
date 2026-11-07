import SwiftUI

/// Đọc "trang này có nút Home không" cho view bên trong, kiểu `GeometryReader`: gắn `FloatingHomeProbe` làm nền 0×0 rồi
/// đưa `FloatingHomePlacement` (`nil` khi chưa đọc xong) cho `content`; `placement?.homeAction` = hành động Home, `nil`
/// = không hiện. `role` là vai trò đăng ký với `FloatingHomeRegistry` (nút "+" / FAB riêng dùng `.addButton`).
///
/// `content` phải luôn dựng ra view thật (không rỗng): nền của một view rỗng không được dựng ⇒ đầu dò không bao giờ chạy.
struct FloatingHomeReader<Content: View>: View {
    let role: FloatingHomeRegistry.Role
    @ViewBuilder let content: (FloatingHomePlacement?) -> Content

    @State private var token = UUID()
    @State private var placement: FloatingHomePlacement?

    var body: some View {
        content(placement)
            .background {
                FloatingHomeProbe(token: token, role: role) { placement = $0 }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
    }
}
