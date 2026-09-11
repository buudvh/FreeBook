import SwiftUI
import UIKit

/// Ép panel e-ink vẽ lại **toàn bộ** màn hình để xoá ghosting — vệt mờ còn đọng lại của nội dung cũ.
///
/// Cách làm: phủ một cửa sổ riêng toàn màn hình, nháy **đen rồi trắng** rồi tự gỡ. Panel e-ink chỉ làm
/// mới vùng thay đổi, nên một khối lớn đổi màu hai lần liên tiếp là cách duy nhất buộc nó quét lại cả
/// màn từ trong app.
///
/// **Đây không phải điều khiển waveform thật.** iOS không có SDK e-ink (Boox/Dasung chỉ mở API trên
/// Android), nên hiệu quả phụ thuộc phần cứng và cách thiết bị diễn giải thay đổi lớn. Đừng hứa hơn thế
/// trong UI.
///
/// Dùng lại đúng khuôn `ToastManager`: cửa sổ riêng ở `windowLevel = .alert`, và `hitTest` trả `nil` để
/// **không nuốt chạm** trong lúc nháy.
@MainActor
public final class EInkRefreshOverlay {
    public static let shared = EInkRefreshOverlay()

    /// Mỗi pha đen/trắng. Ngắn hơn thì panel không kịp quét hết; dài hơn thì người dùng thấy như treo.
    private static let phaseNanoseconds: UInt64 = 250_000_000

    private var window: PassThroughWindow?
    private var isFlashing = false

    private init() {}

    /// Nháy một lượt. Gọi lại trong lúc đang nháy thì bỏ qua — chồng hai cửa sổ sẽ nháy hai lần liên
    /// tiếp và trông như app bị giật.
    public func flash() {
        guard !isFlashing, let scene = Self.activeWindowScene else { return }
        isFlashing = true

        let win = PassThroughWindow(windowScene: scene)
        win.windowLevel = .alert
        win.backgroundColor = .clear

        let hosting = UIHostingController(rootView: FlashView())
        hosting.view.backgroundColor = .clear
        win.rootViewController = hosting

        window = win
        win.isHidden = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.phaseNanoseconds * 2)
            self.window?.isHidden = true
            self.window = nil
            self.isFlashing = false
        }
    }

    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    /// Cửa sổ chỉ để vẽ: mọi cú chạm đi xuyên qua, không chặn UI thật phía dưới.
    private final class PassThroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    private struct FlashView: View {
        @State private var isWhite = false

        var body: some View {
            (isWhite ? EInkPalette.paper : EInkPalette.ink)
                .ignoresSafeArea()
                .task {
                    try? await Task.sleep(nanoseconds: EInkRefreshOverlay.phaseNanoseconds)
                    isWhite = true
                }
        }
    }
}
