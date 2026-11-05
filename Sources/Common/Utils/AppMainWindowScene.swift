import UIKit

/// Cửa sổ lớp phủ của app (hub nổi, widget TTS, widget trình duyệt, toast, ngăn kéo `…`): không bao giờ là cửa sổ chính,
/// nên không được dùng làm bằng chứng "scene này chứa giao diện của app".
protocol AppOverlayWindow: UIWindow {}

/// Chọn `UIWindowScene` chứa **giao diện chính** của app.
///
/// ## Vì sao không lấy "scene active đầu tiên"
/// Khi bật Hình trong hình, iOS (trong LiveContainer) có thể nối thêm một `UIWindowScene` khác cũng báo
/// `didActivate`. `connectedScenes` là `Set` không thứ tự, nên "scene active đầu tiên" có lúc là scene đó: cửa sổ
/// nổi bị chuyển sang scene của PiP (hiện trong khung PiP), tắt PiP thì scene mất và cửa sổ nổi biến theo tới khi
/// mở lại app. Mọi chỗ cần "scene của app" (cửa sổ nổi, toast, VC trên cùng, xoay màn) đi qua đây.
///
/// ## Thứ hạng
/// 1. Scene có key window không phải lớp phủ, ở level `.normal` — cửa sổ chính của app (lớp phủ không bao giờ key).
/// 2. Scene có cửa sổ `.normal` đang hiện không phải lớp phủ.
/// 3. Cách chọn cũ (active → inactive → bất kỳ), để không bao giờ trả `nil` khi còn scene.
/// Trong cùng hạng, scene `foregroundActive` thắng `foregroundInactive`, rồi tới scene bất kỳ.
@MainActor
enum AppMainWindowScene {
    /// Scene tốt nhất hiện có; `excluding` bỏ một scene đang bị ngắt (lúc `didDisconnect` nó có thể còn trong danh sách).
    static func current(excluding excluded: UIScene? = nil) -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0 !== excluded }
        return preferred(scenes.filter(hasMainKeyWindow))
            ?? preferred(scenes.filter(hasVisibleMainWindow))
            ?? preferred(scenes)
    }

    /// Scene có phải scene chính hiện tại (`current()`) không — guard cho `UIScene.didActivateNotification`: scene
    /// khác (vd scene của PiP) thì cửa sổ nổi không được chuyển sang. So với `current()` thay vì chỉ xét "có cửa sổ
    /// `.normal`": cửa sổ của PiP là lớp riêng của hệ thống, có thể cũng ở level `.normal`.
    static func isMainInterface(_ scene: UIWindowScene) -> Bool {
        scene === current()
    }

    /// Mô tả ngắn cho log chẩn đoán: vai trò, trạng thái, các cửa sổ (lớp + level) và số scene đang nối.
    static func describe(_ scene: UIScene?) -> String {
        guard let scene else { return "scene=nil" }
        let total = UIApplication.shared.connectedScenes.count
        var parts = ["role=\(scene.session.role.rawValue)", "state=\(stateName(scene.activationState))", "scenes=\(total)"]
        if let windowScene = scene as? UIWindowScene {
            let windows = windowScene.windows.map { window in
                "\(type(of: window))@\(Int(window.windowLevel.rawValue))\(window.isKeyWindow ? "*" : "")\(window.isHidden ? "-" : "")"
            }
            parts.append("windows=[\(windows.joined(separator: ","))]")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Nội bộ

    private static func preferred(_ scenes: [UIWindowScene]) -> UIWindowScene? {
        scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    private static func hasMainKeyWindow(_ scene: UIWindowScene) -> Bool {
        scene.windows.contains { window in
            window.isKeyWindow && isMainWindowCandidate(window)
        }
    }

    private static func hasVisibleMainWindow(_ scene: UIWindowScene) -> Bool {
        scene.windows.contains { window in
            !window.isHidden && isMainWindowCandidate(window)
        }
    }

    private static func isMainWindowCandidate(_ window: UIWindow) -> Bool {
        !(window is AppOverlayWindow) && window.windowLevel == .normal
    }

    private static func stateName(_ state: UIScene.ActivationState) -> String {
        switch state {
        case .foregroundActive: return "active"
        case .foregroundInactive: return "inactive"
        case .background: return "background"
        case .unattached: return "unattached"
        @unknown default: return "unknown"
        }
    }
}
