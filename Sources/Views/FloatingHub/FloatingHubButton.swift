import SwiftUI

/// Nút hub nổi — **nửa viên thuốc nhỏ cao 36 dính mép** (anh Bửu duyệt mockup 2026-11-11, thay nút tròn 36px nép
/// mép của 1.3.524): cùng khuôn `EdgePillShape` với đĩa nghe và nút trình duyệt thu nhỏ. Độ nhô, **Độ trong suốt** và
/// **Độ đục** là cài đặt **riêng của hub** (Giao diện › Viên thuốc nổi, `EdgePillSettings`; mặc định 38 pt, 90%, không
/// nhoè); icon 17 pt trắng đồng tâm đầu bo (gắn bằng `overlay` ⇒ hub hẹp tới bán nguyệt thì icon lọt ra ngoài mép), **mờ
/// đúng số** theo độ trong suốt của hub (`1 − trong suốt`, không sàn). Đang kéo (`edge == nil`) ⇒ hình tròn.
///
/// Từ 1.3.533 hub **luôn hiện** (trừ lúc cổng từ điển chưa mở, sheet của hub đang mở, hoặc trình phát video
/// đang toàn màn), kể cả khi không có tiến trình nào.
///
/// ## Icon và nháy theo số tiến trình (người dùng chốt 2026-10-22)
/// "Tiến trình" = AI đang chạy, video thu nhỏ, tác vụ nền (tải/xuất/nhập truyện, sao lưu, tải model), lượt kiểm tra nguồn
/// thu nhỏ — xem `FloatingHubPresentationReader.ButtonState.runningKinds`. Tin chưa đọc **không** tính.
/// - 0 tiến trình: `bell` (viền), không nháy.
/// - Chỉ còn kết quả AI / kiểm tra nguồn chưa xem: tính là tiến trình nhưng nằm trong `quietKinds` nên **không** nháy.
/// - 1 tiến trình: icon của chính mục đó (`sparkles` / `play.rectangle` / `checkmark.seal`; tác vụ nền ⇒ `bell`), nháy.
/// - Từ 2 tiến trình: `square.stack.3d.up`, nháy.
///
/// Bảng icon trên chỉ áp cho lựa chọn **Mở thẳng khi chỉ có 1 tác vụ** của cài đặt "Khi chạm hub"
/// (`FloatingHubTapBehavior`). Lựa chọn **Luôn hiện tất cả mục** (mặc định; người dùng chốt 2026-11-06): icon **luôn**
/// là `square.stack.3d.up`. Nháy như nhau ở cả hai lựa chọn. Nút **không bao giờ** dùng `bell.fill` và không đưa tín hiệu
/// chưa đọc nào lên hình (không badge số, không chấm đỏ); số chưa đọc chỉ ở dòng Thông báo và nhãn VoiceOver.
///
/// ## Nháy
/// `FloatingHubPulseView` đổi **màu** nền đỏ sẫm ↔ đỏ tươi bằng Core Animation, phủ nửa viên (cắt đúng hình nửa viên).
/// Màu nháy có alpha `1 − trong suốt` của hub và nằm **trên** lớp kính (độ đục) của hub ⇒ nháy theo độ trong suốt + độ đục
/// (anh Bửu 2026-11-11; trước đó nền nháy giữ rõ). Lớp nháy luôn nằm trong cây view.
///
/// View này **chỉ vẽ**: vị trí, kéo/thả và chạm do `FloatingHubContainerViewController` (UIKit) xử lý, nhờ vậy
/// ngón tay không trễ theo vòng cập nhật state của SwiftUI. `onActivate` chỉ dùng cho VoiceOver.
struct FloatingHubButton: View {
    /// Đường kính lúc đang kéo (= chiều cao).
    static let dragDiameter: CGFloat = EdgePillSettings.Kind.hub.height
    private static let iconBox: CGFloat = 24

    let state: FloatingHubPresentationReader.ButtonState
    /// Mép đang dính; `nil` ⇒ đang kéo (hình tròn).
    let edge: EdgeDirection?
    /// Hành động chính (cùng đường với chạm) — rẽ theo số tiến trình, hoặc đóng menu.
    let onActivate: () -> Void

    @AppStorage(FloatingHubTapBehavior.storageKey)
    private var tapBehavior: FloatingHubTapBehavior = FloatingHubTapBehavior.defaultValue
    @AppStorage(EdgePillSettings.Kind.hub.transparencyKey)
    private var transparency = EdgePillSettings.defaultTransparency

    var body: some View {
        let shape = EdgePillShape(edge: edge)
        let inset = EdgePillShape.contentInset(height: Self.dragDiameter, content: Self.iconBox)
        return FloatingGlassBackground(shape: AnyShape(shape), pill: .hub)
            .overlay {
                FloatingHubPulseView(isPulsing: state.isPulsing, edge: edge, colorAlpha: iconOpacity)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: EdgePillShape.contentAlignment(for: edge)) {
                Image(systemName: glyphName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .opacity(iconOpacity)
                    .frame(width: Self.iconBox, height: Self.iconBox)
                    .padding(EdgePillShape.contentPadding(for: edge), edge == nil ? 0 : inset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
            // Kích hoạt bằng VoiceOver không chắc đi qua `UITapGestureRecognizer` của container.
            .accessibilityAction {
                onActivate()
            }
    }

    /// Icon (và màu nháy) theo độ trong suốt của hub: 0% ⇒ rõ hẳn, 100% ⇒ trong hẳn (không sàn).
    private var iconOpacity: Double {
        1 - min(1, max(0, transparency))
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
            case .ai, .video, .sourceCheck:
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
