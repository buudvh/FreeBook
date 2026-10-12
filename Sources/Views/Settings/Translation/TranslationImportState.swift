import Foundation

/// Các loại từ điển đang nhập / đang làm mới của màn "Cài đặt dịch thuật".
///
/// Trước 1.3.520 tập này là `@State` của `SettingsView` — gốc tab, sống suốt phiên — nên khoá
/// `.disabled(...)` và chữ "Đang import..." giữ nguyên cả khi đổi tab. Màn dịch giờ là màn con được push:
/// `@State` của nó mất khi bấm Back hay chạm lại tab, trong lúc `Task` nhập vẫn chạy ⇒ mở lại màn là bấm nhập
/// chồng được. Giữ tập ở đây (singleton) để trạng thái sống đúng như cũ.
@MainActor
final class TranslationImportState: ObservableObject {
    static let shared = TranslationImportState()

    @Published var importingTypes: Set<String> = []

    private init() {}
}
