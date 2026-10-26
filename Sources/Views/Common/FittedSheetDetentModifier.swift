import SwiftUI

/// Sheet gốc mở ở nấc **cao đúng bằng nội dung**, vuốt lên được tới nấc toàn màn (1.3.608 — trước đó chỉ có
/// một nấc nên không kéo lên được) — dùng cho ba panel bôi đen của Reader.
///
/// Ba điểm dễ làm sai:
/// 1. Nội dung phải `.fixedSize(horizontal: false, vertical: true)` **trước** khi đo. Không làm vậy thì
///    `GeometryReader` báo đúng chiều cao sheet đang đề xuất (giá trị tạm), và nấc kẹt luôn ở đó.
/// 2. Deployment iOS 17 nên đo bằng `GeometryReader` ở `background` + `PreferenceKey`
///    (`onGeometryChange` chỉ có từ iOS 18).
/// 3. Chiều cao đo được nằm ở **người gọi** (`Binding`), không ở `@State` của modifier: nội dung sheet
///    được dựng lại mỗi lần mở nên state ở đây về 0 và lần nào cũng nháy giá trị tạm. Chỉ lần mở đầu
///    tiên mới dùng `.medium` trong lúc chờ đo.
struct FittedSheetDetentModifier: ViewModifier {
    @Binding var height: CGFloat
    let background: Color

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(HeightKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - height) > 0.5 else { return }
                height = newHeight
            }
            // Sheet cao hơn nội dung (giá trị tạm, bàn phím…) thì nội dung bám mép trên, không trôi giữa.
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
            .presentationBackground(background)
    }

    /// Nấc vừa nội dung (hoặc `.medium` khi chưa đo, tránh nháy cao 0) + nấc toàn màn. Sheet mở ở nấc nhỏ hơn.
    private var detents: Set<PresentationDetent> {
        height > 0 ? [.height(height), .large] : [.medium, .large]
    }

    /// Lồng trong modifier để file chỉ có một type chính ở top level.
    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

extension View {
    /// Sheet một nấc cao đúng bằng nội dung, có thanh kéo hệ thống — xem `FittedSheetDetentModifier`.
    func fittedSheetDetent(height: Binding<CGFloat>, background: Color) -> some View {
        modifier(FittedSheetDetentModifier(height: height, background: background))
    }
}
