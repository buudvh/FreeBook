import SwiftUI

/// Nút header của hai màn kiểm tra nguồn (Legado, tiện ích JS): **⌄ thu nhỏ** (chỉ khi lượt đang chạy, 1.3.697) và chia
/// sẻ báo cáo. Hai nút đứng sát nhau trong **một** `ToolbarItem` theo `HeaderButtonMetrics`; còn một nút thì khung 36.
/// Glyph ⌄ cùng nút thu nhỏ của trình phát video. Màn là **trang con trong sheet hub** (`sheetPageBack` có giá trị, 1.3.872)
/// ⇒ không vẽ ⌄: nút ‹ của trang đã giao lượt cho hub rồi về trang chính.
struct SourceCheckHeaderButtons: View {
    let showsMinimize: Bool
    let isShareDisabled: Bool
    let onMinimize: () -> Void
    let onShare: () -> Void

    @Environment(\.sheetPageBack) private var sheetPageBack

    var body: some View {
        HStack(spacing: HeaderButtonMetrics.pairSpacing) {
            if drawsMinimize {
                Button(action: onMinimize) {
                    icon("chevron.down")
                }
                .accessibilityLabel("Thu nhỏ, lượt kiểm tra chạy tiếp ở nền")
            }
            Button(action: onShare) {
                icon("square.and.arrow.up")
            }
            .disabled(isShareDisabled)
            .accessibilityLabel("Chia sẻ báo cáo kiểm tra")
        }
    }

    private var drawsMinimize: Bool {
        showsMinimize && sheetPageBack == nil
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: drawsMinimize ? HeaderButtonMetrics.pairIconWidth : 36, height: 36)
            .contentShape(Rectangle())
    }
}
