import Foundation
import UIKit

/// Trạng thái kéo/thả, dán mép, bung/thu và menu của **nút hub nổi** (1.3.524).
///
/// Chuyển từ view model của widget thông báo nổi cũ (xoá ở 1.3.524). **Cố ý là lớp riêng**,
/// không tái dùng `FloatingWidgetViewModel` của widget TTS: lớp đó hard-code key
/// `ttsWidgetVerticalRatio`/`ttsWidgetEdge` (`FloatingWidgetViewModel.swift:20-21`), nên dùng chung là hai
/// widget **ghi đè vị trí của nhau** — kéo hub là nút nghe truyện nhảy theo. Phần hình học vẫn dùng chung
/// `FloatingWidgetGeometry`.
///
/// Nút có **một cỡ duy nhất** (36px): `.peeking` và `.revealed` chỉ khác **vị trí** (ngậm vào mép hay nằm
/// trong màn) và **kiểu chỉ báo** (chấm hay số) — hai thứ do container và View quyết định.
///
/// ## Luôn xuất hiện ở dạng nép mép
/// Hub **không bao giờ** tự bung, kể cả khi có thông báo mới (người dùng chốt). `prepareForAppearance()` là
/// chỗ thực thi luật này, gọi mỗi lần hub hiện lại sau khi bị ẩn.
@MainActor
final class FloatingHubViewModel: ObservableObject {
    @Published var verticalRatio: CGFloat
    @Published var edgeDirection: EdgeDirection
    @Published var mode: WidgetMode
    @Published var isDragging = false
    @Published var disableAutoHide: Bool = false {
        didSet {
            if disableAutoHide {
                autoHideTask?.cancel()
            }
        }
    }
    /// Menu đang mở. Khi `true`, cửa sổ hub nhận **mọi** chạm (lớp nền trong suốt đóng menu) — nên cờ này phải
    /// được hạ ở mọi đường: ẩn hub, bắt đầu kéo, mở sheet, mở một mục, đổi scene. Xem `rules.md` mục 1.3.524.
    @Published private(set) var isMenuOpen = false

    /// Tự thu về `.peeking` sau 3 giây — cùng nhịp với widget TTS, để hai widget cư xử nhất quán.
    static let autoHideNanoseconds: UInt64 = 3_000_000_000

    static let storedRatioKey = "floatingHubVerticalRatio"
    static let storedEdgeKey = "floatingHubEdge"
    /// Key của widget thông báo nổi cũ — chỉ đọc **một lần** khi migration, không xoá (revert vẫn còn vị trí).
    private static let legacyRatioKey = "notificationWidgetVerticalRatio"
    private static let legacyEdgeKey = "notificationWidgetEdge"
    /// Mặc định hơi cao hơn giữa màn (0,42) để không đè lên thanh tab ở đáy.
    private static let defaultRatio: CGFloat = 0.42

    private var autoHideTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        FloatingHubViewModel.migrateLegacyPositionIfNeeded(defaults)

        let storedRatio = defaults.double(forKey: FloatingHubViewModel.storedRatioKey)
        let storedEdge = defaults.string(forKey: FloatingHubViewModel.storedEdgeKey)
        self.verticalRatio = storedRatio > 0 ? CGFloat(storedRatio) : FloatingHubViewModel.defaultRatio
        self.edgeDirection = (storedEdge == "left") ? .left : .right
        self.mode = .peeking
    }

    /// Lần đầu chạy bản có hub: lấy vị trí từ widget thông báo cũ nếu người dùng từng kéo nó, không thì mặc
    /// định 0,42 mép phải. **Ghi ngay** hai key mới để lần sau không chạy lại.
    ///
    /// Phải dùng `object(forKey:)` để biết key có tồn tại hay không: `double(forKey:)` trả 0 cho key chưa có.
    private static func migrateLegacyPositionIfNeeded(_ defaults: UserDefaults) {
        guard defaults.object(forKey: storedRatioKey) == nil else { return }

        let legacyRatio = defaults.double(forKey: legacyRatioKey)
        let ratio = legacyRatio > 0 ? legacyRatio : Double(defaultRatio)
        let edge = defaults.string(forKey: legacyEdgeKey) == "left" ? "left" : "right"

        defaults.set(ratio, forKey: storedRatioKey)
        defaults.set(edge, forKey: storedEdgeKey)
    }

    func reveal() {
        autoHideTask?.cancel()
        mode = .revealed
        if !disableAutoHide {
            startAutoHideTimer()
        }
    }

    func hide() {
        autoHideTask?.cancel()
        mode = .peeking
    }

    /// Mở/đóng menu. Mở thì tắt tự thu; đóng thì bật lại và hẹn 3 s nếu hub vẫn đang bung. Idempotent.
    func setMenuOpen(_ open: Bool) {
        guard isMenuOpen != open else { return }
        isMenuOpen = open
        if open {
            disableAutoHide = true
        } else {
            disableAutoHide = false
            if mode == .revealed {
                startAutoHideTimer()
            }
        }
    }

    /// Đưa hub về trạng thái xuất hiện chuẩn: menu đóng, tự thu bật lại, dạng nép mép.
    func prepareForAppearance() {
        isMenuOpen = false
        disableAutoHide = false
        hide()
    }

    func handleDragStart() {
        autoHideTask?.cancel()
        isDragging = true
    }

    /// Chốt vị trí sau khi nhả tay: snap về cạnh gần nhất, kẹp Y trong vùng hợp lệ, quyết định bung hay thu,
    /// rồi lưu tỉ lệ/cạnh để không reset khi view dựng lại.
    func handleDragEnd(
        finalPosition: CGPoint,
        widgetSize: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        topMargin: CGFloat,
        bottomMargin: CGFloat,
        edgeSnapDistance: CGFloat
    ) {
        autoHideTask?.cancel()
        guard screenWidth > 0, screenHeight > 0 else {
            isDragging = false
            return
        }

        let targetEdge = FloatingWidgetGeometry.nearestEdge(
            centerX: finalPosition.x,
            screenWidth: screenWidth
        )
        let targetY = FloatingWidgetGeometry.clampedCenterY(
            finalPosition.y,
            widgetHeight: widgetSize,
            screenHeight: screenHeight,
            topMargin: topMargin,
            bottomMargin: bottomMargin
        )

        verticalRatio = targetY / screenHeight
        edgeDirection = targetEdge

        // Thả sát mép thì thu, thả giữa màn thì giữ bung — cùng ngưỡng với widget TTS.
        let edgeDistance = min(finalPosition.x, screenWidth - finalPosition.x)
        mode = edgeDistance <= edgeSnapDistance ? .peeking : .revealed
        isDragging = false

        persistPosition()

        if mode == .revealed && !disableAutoHide {
            startAutoHideTimer()
        }
    }

    /// Ghi chỗ đặt do `FloatingWidgetLayoutCoordinator` chọn (né widget nổi khác) — lưu y như khi kéo tay.
    /// Không đụng `mode`.
    func applyResolvedPlacement(edge: EdgeDirection, centerY: CGFloat, screenHeight: CGFloat) {
        guard screenHeight > 0 else { return }
        verticalRatio = centerY / screenHeight
        edgeDirection = edge
        persistPosition()
    }

    private func persistPosition() {
        UserDefaults.standard.set(Double(verticalRatio), forKey: Self.storedRatioKey)
        UserDefaults.standard.set(edgeDirection == .left ? "left" : "right", forKey: Self.storedEdgeKey)
    }

    func startAutoHideTimer() {
        autoHideTask?.cancel()
        guard !isDragging, !disableAutoHide else { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoHideNanoseconds)
            guard !Task.isCancelled else { return }
            guard mode == .revealed, !isDragging, !disableAutoHide else { return }
            mode = .peeking
        }
    }

    func cancelTasks() {
        autoHideTask?.cancel()
    }
}
