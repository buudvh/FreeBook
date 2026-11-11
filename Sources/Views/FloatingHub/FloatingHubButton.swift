import SwiftUI

/// Nút hub nổi — **nửa viên thuốc nhỏ 38 × 36 dính mép** (anh Bửu duyệt mockup 2026-11-11, thay nút tròn 36px nép
/// mép của 1.3.524): cùng khuôn `EdgePillShape` với đĩa nghe và nút trình duyệt thu nhỏ. Nền kính
/// `FloatingGlassBackground` theo **Độ trong suốt** + **Độ đục** của nút nổi; icon 17 pt trắng đồng tâm đầu bo, **mờ đúng
/// số** theo Độ trong suốt (`1 − độ trong suốt`, không sàn — như bìa đĩa nghe). Đang kéo (`edge == nil`) ⇒ hình tròn.
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
/// `FloatingHubPulseView` đổi **màu** nền đỏ sẫm ↔ đỏ tươi bằng Core Animation, phủ nửa viên (bo đúng hai góc phía đầu bo).
/// Nền nháy giữ rõ, không mờ theo Độ trong suốt — nó là thứ báo có việc đang chạy. Lớp nháy luôn nằm trong cây view.
///
/// View này **chỉ vẽ**: vị trí, kéo/thả và chạm do `FloatingHubContainerViewController` (UIKit) xử lý, nhờ vậy
/// ngón tay không trễ theo vòng cập nhật state của SwiftUI. `onActivate` chỉ dùng cho VoiceOver.
struct FloatingHubButton: View {
    /// Cỡ nửa viên lúc dính mép.
    static let size = EdgePillShape.smallSize
    /// Đường kính lúc đang kéo.
    static let dragDiameter: CGFloat = EdgePillShape.smallSize.height
    private static let iconBox: CGFloat = 24

    let state: FloatingHubPresentationReader.ButtonState
    /// Mép đang dính; `nil` ⇒ đang kéo (hình tròn).
    let edge: EdgeDirection?
    /// Hành động chính (cùng đường với chạm) — rẽ theo số tiến trình, hoặc đóng menu.
    let onActivate: () -> Void

    @AppStorage(FloatingHubTapBehavior.storageKey)
    private var tapBehavior: FloatingHubTapBehavior = FloatingHubTapBehavior.defaultValue
    @AppStorage(GlassChromeSettings.floatingTransparencyKey)
    private var transparency = GlassChromeSettings.defaultFloatingTransparency

    var body: some View {
        let shape = EdgePillShape(edge: edge)
        let inset = EdgePillShape.contentInset(
            for: CGSize(width: Self.dragDiameter, height: Self.dragDiameter),
            content: Self.iconBox
        )
        return ZStack(alignment: EdgePillShape.contentAlignment(for: edge)) {
            FloatingGlassBackground(shape: AnyShape(shape))
            FloatingHubPulseView(isPulsing: state.isPulsing, edge: edge)
                .allowsHitTesting(false)
            Image(systemName: glyphName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .opacity(iconOpacity)
                .frame(width: Self.iconBox, height: Self.iconBox)
                .padding(edge == .right ? Edge.Set.leading : Edge.Set.trailing, edge == nil ? 0 : inset)
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

    /// Icon theo đúng lớp màu của nút nổi: trong suốt 0% ⇒ rõ hẳn, 100% ⇒ trong hẳn (không sàn).
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
