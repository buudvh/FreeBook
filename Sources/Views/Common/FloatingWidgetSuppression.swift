import Foundation
import Combine

/// Cờ toàn cục **ẩn mọi widget nổi** (hub, widget TTS, widget trình duyệt) — bật khi trình phát video vào toàn
/// màn hình / xoay ngang / khoá màn, tắt khi thoát. Widget đọc cờ này rồi tự ẩn/hiện; chỉ trình phát được ghi.
@MainActor
final class FloatingWidgetSuppression: ObservableObject {
    static let shared = FloatingWidgetSuppression()

    @Published var isSuppressed = false

    private init() {}
}
