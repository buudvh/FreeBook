import UIKit

/// Bộ số chung của **mọi header** — thanh điều hướng hệ thống lẫn header tự dựng (1.3.1017, anh Bửu 2026-11-20: "hàng 1
/// và hàng 2 header nhiều chỗ margin không giống nhau", "icon nhiều chỗ nhìn size cũng không giống nhau, title lớn chưa
/// đủ to", "các header custom cho cảm giác logic thiết kế không giống" — duyệt mockup; 1.3.1018 bỏ tiêu đề hàng 2: "đừng
/// hiện tiêu đề 2 hàng nữa, để nó luôn hiển thị cạnh nút trái nếu có nút trái").
///
/// Luật lề: mép **vật nhìn thấy** ngoài cùng (mũi back, icon, vòng tròn có nền, chữ) chạm `horizontalMargin` ở hàng nút,
/// hàng tiêu đề, ô tìm và thẻ danh sách — không phải mép khung chạm. Vì vậy nút **ngoài cùng** canh icon vào lề trong
/// khung của nó (`.frame(width:height:alignment: .trailing)` ở mép phải, `.leading` ở mép trái) thay vì canh giữa.
///
/// Nằm ở `Common` (không phải `Views/Common/PageHeader`) để cả phần UIKit dùng được. Cụm nút đứng liền nhau vẫn theo
/// `HeaderButtonMetrics` (khung 32, cách 2pt).
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
    /// Mũi back **lùi ra ngoài lề** chừng này (1.3.1026): log đo trên máy cho thấy mũi back hệ thống nằm ở `lề − 8`
    /// (x=12 trên máy 414pt lề 20, x=8 trên máy 390pt lề 16) ⇒ mũi back tự dựng (`HeaderBackButton`) lùi theo để mọi
    /// mũi back cùng một chỗ.
    static let backChevronOutdent: CGFloat = 8

    // MARK: - Tiêu đề

    /// Tiêu đề trang — **một cỡ** ở mọi chỗ: tab gốc, gốc sheet, cạnh nút trái (nút back, nút ‹ trang con trong sheet),
    /// tiêu đề sheet / panel tự dựng: 22pt đậm, một dòng, không co chữ (dài thì cắt đuôi).
    static let rowTitleFontSize: CGFloat = 22
    /// Khối tiêu đề hai dòng của màn đọc / xem / nghe (`HeaderTitleBlock`): dòng 1 16pt nửa đậm, dòng 2 13pt màu phụ.
    static let infoTitleFontSize: CGFloat = 16
    static let infoSubtitleFontSize: CGFloat = 13

    /// Trần bề ngang tiêu đề **cạnh nút trái** — chừa chỗ cho nút back (~38pt) + cụm hai nút phải (~82pt) + khe.
    @MainActor static var besideLeftButtonTitleMaxWidth: CGFloat {
        max(180, currentScreenWidth - 150)
    }

    // MARK: - Đo màn

    @MainActor private static var currentScreenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds.width ?? 390
    }
}
