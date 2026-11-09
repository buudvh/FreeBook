import SwiftUI

/// Nút tròn 36px của hub nổi (1.3.524) — cùng khuôn nút trình duyệt thu nhỏ: nền `.ultraThinMaterial`,
/// viền trắng 20 %, bóng đen 24 %.
///
/// Từ 1.3.533 hub **luôn hiện** (trừ lúc cổng từ điển chưa mở, sheet của hub đang mở, hoặc trình phát video
/// đang toàn màn), kể cả khi không có tiến trình nào.
///
/// ## Icon và nháy theo số tiến trình (người dùng chốt 2026-10-22)
/// "Tiến trình" = AI đang chạy, video thu nhỏ, album đang mở ở trình nghe, tác vụ nền (tải/xuất/nhập truyện, sao lưu,
/// tải model) — xem `FloatingHubPresentationReader.ButtonState.runningKinds`. Tin chưa đọc **không** tính.
/// - 0 tiến trình: `bell` (viền), màu chữ hệ thống, không nháy.
/// - Chỉ còn kết quả AI chưa xem (1.3.630): tính là một mục `.ai` (`sparkles`, chạm mở trang "Tác vụ AI") nhưng nằm
///   trong `quietKinds` nên **không** nháy, icon màu chữ hệ thống.
/// - 1 tiến trình: icon của chính mục đó (`sparkles` / `play.rectangle` / `music.note` / `checkmark.seal`; tác vụ nền ⇒
///   `bell`), nháy.
///   Lượt kiểm tra nguồn thu nhỏ đã xong, chưa xem (1.3.697) không nháy, như kết quả AI chưa xem.
/// - Từ 2 tiến trình: `square.stack.3d.up`, nháy.
///
/// Bảng icon trên chỉ áp cho lựa chọn **Mở thẳng khi chỉ có 1 tác vụ** của cài đặt "Khi chạm hub"
/// (`FloatingHubTapBehavior`). Lựa chọn **Luôn hiện tất cả mục** (mặc định; người dùng chốt 2026-11-06): icon **luôn**
/// là `square.stack.3d.up`, kể cả lúc 0 tiến trình — chạm luôn mở menu nên icon không báo mục nào. Nháy như nhau ở cả
/// hai lựa chọn. Cài đặt đọc bằng `@AppStorage` ngay trong view ⇒ đổi là icon đổi ngay; nút chỉ vẽ lại thêm khi đổi
/// cài đặt (hiếm), `ButtonState` không mang cài đặt này.
///
/// Nút **không bao giờ** dùng `bell.fill` và không đưa tín hiệu chưa đọc nào lên hình: không badge số, không chấm
/// đỏ, không viền tím. Số chưa đọc chỉ còn ở badge của dòng Thông báo trong menu và ở nhãn VoiceOver.
///
/// ## Nháy
/// `FloatingHubPulseView` đổi **màu** nền tròn đỏ sẫm ↔ đỏ tươi bằng Core Animation (cùng hằng màu/nhịp với nút
/// trình duyệt thu nhỏ); icon trắng khi đang nháy. Lớp nháy luôn nằm trong cây view (không bọc `if`) để vẽ lại
/// nút không huỷ/tạo lại animation. Không dùng `repeatForever` của SwiftUI: chạy theo từng frame, tốn năng lượng.
///
/// View này **chỉ vẽ**: vị trí, kéo/thả và chạm do `FloatingHubContainerViewController` (UIKit) xử lý, nhờ vậy
/// ngón tay không trễ theo vòng cập nhật state của SwiftUI. `onActivate` chỉ dùng cho VoiceOver.
struct FloatingHubButton: View {
    /// Cỡ nút, dùng chung cho cả hai trạng thái.
    static let size: CGFloat = 36

    let state: FloatingHubPresentationReader.ButtonState
    /// Hành động chính (cùng đường với chạm) — rẽ theo số tiến trình, hoặc đóng menu.
    let onActivate: () -> Void

    @AppStorage(FloatingHubTapBehavior.storageKey)
    private var tapBehavior: FloatingHubTapBehavior = FloatingHubTapBehavior.defaultValue

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    FloatingHubPulseView(isPulsing: state.isPulsing)
                        .allowsHitTesting(false)
                }
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            Image(systemName: glyphName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(state.isPulsing ? Color.white : Color.primary)
                .frame(width: Self.size, height: Self.size)
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        // Kích hoạt bằng VoiceOver không chắc đi qua `UITapGestureRecognizer` của container.
        .accessibilityAction {
            onActivate()
        }
    }

    // MARK: - Glyph

    private var glyphName: String {
        // "Luôn hiện tất cả mục": một icon cố định, không đổi theo số tiến trình (chỉ nháy mới báo đang chạy).
        if tapBehavior == .alwaysMenu {
            return "square.stack.3d.up"
        }
        switch state.runningCount {
        case 0:
            return "bell"
        case 1:
            switch state.runningKinds[0] {
            case .notifications:
                // Tác vụ nền: chuông viền như lúc rảnh, chỉ khác ở chỗ nháy.
                return "bell"
            case .ai, .video, .audio, .sourceCheck:
                return state.runningKinds[0].systemImage(unreadCount: 0)
            }
        default:
            return "square.stack.3d.up"
        }
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var text: String
        if state.runningKinds.isEmpty {
            text = "Lối tắt nổi: \(FloatingHubItem.Kind.notifications.title)"
        } else {
            let names = state.runningKinds
                .map { state.quietKinds.contains($0) ? "\($0.title) đã xong, chưa xem" : $0.title }
                .joined(separator: ", ")
            text = "Lối tắt nổi: \(names)"
        }
        if state.unreadCount > 0 {
            text += ", \(state.unreadCount) thông báo chưa đọc"
        }
        return text
    }
}
