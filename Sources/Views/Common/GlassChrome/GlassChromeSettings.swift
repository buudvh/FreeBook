import Foundation

/// Khoá `UserDefaults` + mặc định của Cài đặt › Chung › Giao diện (1.3.636): độ trong suốt / độ đục của **nút nổi**
/// (tai nghe Reader, nút "+" của màn danh sách) và **ngăn kéo menu ba chấm**.
///
/// - "Độ trong suốt" (0…1): lớp màu nền — 1 = không có lớp màu, 0 = nền đặc.
/// - "Độ đục" (0…1): 6 nấc kính iOS (`GlassFrostLevel`, bước 0,2) cho **cả** nút nổi lẫn ngăn kéo (1.3.645 nút nổi,
///   1.3.647 ngăn kéo), luôn vẽ ở độ hiện 100%. Trước đó (1.3.640) là `.opacity(độ đục)` trên material — sai: kính iOS
///   chỉ nhoè khi hiện đủ 100%, nên 0–95% thực ra không nhoè, chỉ 100% mới nhoè.
///
/// Mặc định của ngăn kéo giữ đúng "kính đục vừa" đã duyệt ở 1.3.633 (lớp tối 55% ⇒ trong suốt 45%, nhoè 60%); nút nổi
/// mặc định "kính rất nhạt" (lớp màu 10%, không nhoè) theo mockup đã duyệt.
///
/// Khoá **không được có dấu chấm** (1.3.637): `@AppStorage` nghe thay đổi qua KVO của `UserDefaults`, mà KVO đọc dấu
/// chấm là key path lồng nhau ⇒ thanh kéo ghi được nhưng các view khác (nút nổi, ngăn kéo, ô xem trước) không được báo.
enum GlassChromeSettings {
    static let floatingTransparencyKey = "glassChromeFloatingTransparency"
    static let floatingFrostKey = "glassChromeFloatingFrost"
    static let drawerTransparencyKey = "glassChromeDrawerTransparency"
    static let drawerFrostKey = "glassChromeDrawerFrost"

    static let defaultFloatingTransparency = 0.9
    static let defaultFloatingFrost = 0.0
    static let defaultDrawerTransparency = 0.45
    static let defaultDrawerFrost = 0.6
}
