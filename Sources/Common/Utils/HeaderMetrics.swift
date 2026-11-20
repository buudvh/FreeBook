import UIKit

/// Bộ số chung của **mọi header** — thanh điều hướng hệ thống lẫn header tự dựng (1.3.1017, anh Bửu 2026-11-20: "hàng 1
/// và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau, title lớn chưa
/// đủ to", "các header custom cho cảm giác logic thiết kế không giống" — duyệt mockup, tiêu đề hàng 2 cỡ 28).
///
/// Luật lề: mép **vật nhìn thấy** ngoài cùng (mũi back, icon, vòng tròn có nền, chữ) chạm `horizontalMargin` ở hàng nút,
/// hàng tiêu đề, ô tìm và thẻ danh sách — không phải mép khung chạm. Vì vậy nút **ngoài cùng** canh icon vào lề trong
/// khung của nó (`.frame(width:height:alignment: .trailing)` ở mép phải, `.leading` ở mép trái) thay vì canh giữa.
///
/// Nằm ở `Common` (không phải `Views/Common/PageHeader`) vì `NavigationBarAppearance` (UIKit, tầng `Common`) đọc cỡ tiêu
/// đề lớn từ đây. Cụm nút đứng liền nhau vẫn theo `HeaderButtonMetrics` (khung 32, cách 2pt).
enum HeaderMetrics {
    // MARK: - Lề, hàng

    /// Lề ngang = lề của thanh điều hướng hệ thống: 16pt; máy rộng ≥ 414pt (Plus / Pro Max, hoặc màn nằm ngang) 20pt.
    @MainActor static var horizontalMargin: CGFloat {
        currentScreenWidth >= 414 ? 20 : 16
    }

    /// Chiều cao hàng nút của header tự dựng (bằng thanh điều hướng hệ thống khi đẩy trang).
    static let rowHeight: CGFloat = 44

    // MARK: - Icon

    /// Icon SF Symbols trên header: 17pt nửa đậm (chuẩn cũ, giữ nguyên).
    static let iconFontSize: CGFloat = 17
    /// Icon tài sản `AppGlyph` (Lucide, lưới 24 nét 2) trên header: vẽ 20pt mới bằng mắt SF 17pt nửa đậm — ở 17pt trông
    /// nhỏ và mảnh hơn hẳn (trước đây 17 / 19 / 20 tuỳ chỗ).
    static let assetIconSize: CGFloat = 20
    /// Khung chạm nút lẻ.
    static let iconFrameWidth: CGFloat = 36
    static let iconFrameHeight: CGFloat = 38
    /// Khung chạm nút back.
    static let backFrameWidth: CGFloat = 38
    static let backFrameHeight: CGFloat = 44

    // MARK: - Tiêu đề

    /// Tiêu đề **hàng 1** (tab gốc, gốc sheet; tiêu đề sheet / panel tự dựng đứng riêng một hàng): 22pt đậm, không co chữ.
    static let rowTitleFontSize: CGFloat = 22
    /// Tiêu đề lớn **hàng 2** (trang có nút back, `NavigationBarAppearance.largeTitleTextAttributes`): 28pt đậm.
    static let largeTitleFontSize: CGFloat = 28
    /// Tiêu đề **cạnh nút back** (tiêu đề hàng 2 đã thu, trang con trong sheet): 17pt nửa đậm.
    static let inlineTitleFontSize: CGFloat = 17
    /// Khối tiêu đề hai dòng của màn đọc / xem / nghe (`HeaderTitleBlock`): dòng 1 16pt nửa đậm, dòng 2 13pt màu phụ.
    static let infoTitleFontSize: CGFloat = 16
    static let infoSubtitleFontSize: CGFloat = 13

    // MARK: - Đo màn

    @MainActor private static var currentScreenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.width ?? 390
    }
}
