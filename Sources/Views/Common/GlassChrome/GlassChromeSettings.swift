import Foundation

/// Khoá `UserDefaults` + mặc định của Cài đặt › Chung › Giao diện (1.3.636): độ trong suốt / độ đục của **nút nổi**
/// (tai nghe Reader, nút "+" của màn danh sách) và **ngăn kéo menu ba chấm**.
///
/// - "Độ trong suốt" (0…1): lớp màu nền — 1 = không có lớp màu, 0 = nền đặc.
/// - "Độ đục" (0…1): phần hiệu ứng nhoè kính (`SideDrawerPartialBlurView`) — 0 = trong veo, 1 = kính mờ hẳn.
///
/// Mặc định của ngăn kéo giữ đúng "kính đục vừa" đã duyệt ở 1.3.633 (lớp tối 55% ⇒ trong suốt 45%, nhoè 60%); nút nổi
/// mặc định "kính rất nhạt" (lớp màu 10%, không nhoè) theo mockup đã duyệt.
enum GlassChromeSettings {
    static let floatingTransparencyKey = "glassChrome.floatingButton.transparency"
    static let floatingFrostKey = "glassChrome.floatingButton.frost"
    static let drawerTransparencyKey = "glassChrome.sideDrawer.transparency"
    static let drawerFrostKey = "glassChrome.sideDrawer.frost"

    static let defaultFloatingTransparency = 0.9
    static let defaultFloatingFrost = 0.0
    static let defaultDrawerTransparency = 0.45
    static let defaultDrawerFrost = 0.6
}
