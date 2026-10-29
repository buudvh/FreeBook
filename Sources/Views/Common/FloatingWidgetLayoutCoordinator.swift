import UIKit

/// Giữ chỗ theo mép cho các widget nổi (widget TTS, nút hub, nút mở lại trình duyệt) để chúng **không đè lên
/// nhau** khi cùng nằm một cạnh.
///
/// ## Cùng một hệ toạ độ
/// Ba widget sống ở ba `UIWindow` riêng, nhưng cửa sổ nào cũng tạo bằng `UIWindow(windowScene:)` (phủ toàn
/// scene) và container là root view controller — nên `view.bounds` của ba container trùng nhau, so trực tiếp
/// được, không cần đổi toạ độ.
///
/// ## Giữ chỗ
/// Widget đang hiện **đăng ký** khoảng dọc đứng yên của nó (cạnh + đoạn [trên, dưới]); ẩn đi thì **gỡ**. Container
/// báo lại khung mỗi lượt layout (`refresh`: xoay màn, đổi vùng an toàn, bật/tắt hẹn giờ) nhưng **không** xếp
/// lại ở đó.
///
/// ## Xếp lại
/// Chỉ ở hai thời điểm: thả tay sau khi kéo và lúc widget vừa hiện ra (`resolve`). Widget đó là bên **nhường**;
/// widget đang đứng yên không bao giờ bị đẩy. Chỉ xét widget **cùng cạnh** — hai cạnh khác nhau không chạm
/// được (widget TTS mở rộng chỉ rộng 212pt). Menu bung của hub chưa được tính.
@MainActor
final class FloatingWidgetLayoutCoordinator {
    static let shared = FloatingWidgetLayoutCoordinator()

    enum WidgetID: String {
        case tts
        case hub
        case browser
    }

    /// Chỗ đặt do `resolve` chọn: cạnh + tâm Y theo toạ độ `view` của container.
    struct Placement {
        let edge: EdgeDirection
        let centerY: CGFloat

        /// Khác chỗ đề xuất ⇒ phải lưu lại và dời khung; trùng (sai số dưới `tolerance`) thì giữ nguyên tỉ lệ đã
        /// lưu — tránh ghi đè tỉ lệ người dùng chọn (ví dụ 1,0 = sát đáy) bằng giá trị đã kẹp.
        func isMoved(from edge: EdgeDirection, centerY: CGFloat) -> Bool {
            self.edge != edge || abs(self.centerY - centerY) > FloatingWidgetLayoutCoordinator.tolerance
        }
    }

    /// Khe tối thiểu giữa hai widget cùng cạnh.
    nonisolated static let spacing: CGFloat = 8
    /// Sai số làm tròn khi so toạ độ: tâm nằm đúng mép khoảng cấm vẫn tính là trống.
    nonisolated static let tolerance: CGFloat = 0.5

    private struct Slot {
        let edge: EdgeDirection
        let top: CGFloat
        let bottom: CGFloat

        init(edge: EdgeDirection, centerY: CGFloat, height: CGFloat) {
            self.edge = edge
            self.top = centerY - height / 2
            self.bottom = centerY + height / 2
        }
    }

    private var slots: [WidgetID: Slot] = [:]

    private init() {}

    /// Chọn chỗ cho widget `id` (vừa thả tay hoặc vừa hiện) rồi **giữ chỗ luôn** cho nó.
    ///
    /// Thứ tự thử: cạnh đề xuất → cạnh kia (cùng tâm Y đề xuất) → hết chỗ cả hai thì giữ nguyên đề xuất và ghi
    /// log. Trên mỗi cạnh lấy tâm Y **trống gần đề xuất nhất** trong `[minY, maxY]`.
    func resolve(
        id: WidgetID,
        edge: EdgeDirection,
        proposedCenterY: CGFloat,
        height: CGFloat,
        minY: CGFloat,
        maxY: CGFloat
    ) -> Placement {
        let range = min(minY, maxY)...max(minY, maxY)
        let proposed = min(max(proposedCenterY, range.lowerBound), range.upperBound)
        let otherEdge: EdgeDirection = edge == .left ? .right : .left

        let placement: Placement
        if let y = nearestFreeCenterY(on: edge, excluding: id, proposed: proposed, height: height, range: range) {
            placement = Placement(edge: edge, centerY: y)
        } else if let y = nearestFreeCenterY(
            on: otherEdge,
            excluding: id,
            proposed: proposed,
            height: height,
            range: range
        ) {
            placement = Placement(edge: otherEdge, centerY: y)
        } else {
            AppLogger.shared.log(
                "[FloatingLayout] Hết chỗ ở cả hai mép cho widget \(id.rawValue) — giữ nguyên vị trí đề xuất"
            )
            placement = Placement(edge: edge, centerY: proposed)
        }

        slots[id] = Slot(edge: placement.edge, centerY: placement.centerY, height: height)
        return placement
    }

    /// Báo lại khung đã giữ chỗ (layout lại, xoay màn, đổi vùng an toàn, đổi chiều cao) — **không** xếp lại.
    /// Widget chưa giữ chỗ (đang ẩn) thì bỏ qua: chỉ `resolve` mới mở chỗ.
    func refresh(id: WidgetID, edge: EdgeDirection, centerY: CGFloat, height: CGFloat) {
        guard slots[id] != nil else { return }
        slots[id] = Slot(edge: edge, centerY: centerY, height: height)
    }

    /// Gỡ chỗ khi widget ẩn (cả cửa sổ hoặc chỉ nút). Idempotent.
    func unregister(_ id: WidgetID) {
        slots[id] = nil
    }

    /// Tâm Y trống gần `proposed` nhất trên một cạnh, hoặc `nil` nếu cạnh đó hết chỗ.
    ///
    /// Mỗi widget khác cùng cạnh cấm một khoảng **mở** cho tâm của widget đang xếp:
    /// `(trên − khe − h/2, dưới + khe + h/2)`. Tập trống là `range` trừ hợp các khoảng đó, nên điểm trống gần
    /// nhất hoặc là chính đề xuất, hoặc là một đầu mút của khoảng cấm — tương đương "dời lên/xuống sát vật cản,
    /// lặp tới khi hết chạm" nhưng không bao giờ dao động giữa hai vật cản.
    private func nearestFreeCenterY(
        on edge: EdgeDirection,
        excluding id: WidgetID,
        proposed: CGFloat,
        height: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        let blocked: [(lower: CGFloat, upper: CGFloat)] = slots.compactMap { key, slot in
            guard key != id, slot.edge == edge else { return nil }
            return (lower: slot.top - Self.spacing - height / 2, upper: slot.bottom + Self.spacing + height / 2)
        }

        func isFree(_ y: CGFloat) -> Bool {
            guard y >= range.lowerBound - Self.tolerance, y <= range.upperBound + Self.tolerance else { return false }
            return !blocked.contains { y > $0.lower + Self.tolerance && y < $0.upper - Self.tolerance }
        }

        if isFree(proposed) { return proposed }

        let candidates = blocked
            .flatMap { [$0.lower, $0.upper] }
            .filter(isFree)
            .map { min(max($0, range.lowerBound), range.upperBound) }
        return candidates.min { abs($0 - proposed) < abs($1 - proposed) }
    }
}
