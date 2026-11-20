import SwiftUI

/// Nút header của hai màn kiểm tra nguồn (Legado, tiện ích JS): **⌄ thu nhỏ** (chỉ khi lượt đang chạy, 1.3.697) và chia
/// sẻ báo cáo. Hai nút đứng sát nhau trong **một** `ToolbarItem` theo `HeaderButtonMetrics`; còn một nút thì khung 36.
/// Glyph ⌄ cùng nút thu nhỏ của trình phát video. Màn là **trang con trong sheet hub** (`sheetPageBack` có giá trị, 1.3.872)
/// ⇒ không vẽ ⌄: nút ‹ của trang đã giao lượt cho hub rồi về trang chính. Màn mở **dạng sheet** (1.3.1021, anh Bửu: "Kiểm
/// tra tiện ích / Kiểm tra nguồn, khi mở dạng sheet … dời ⌄") ⇒ ⌄ đứng **trước tiêu đề** (`leadingMinimize`), cụm phải chỉ
/// còn chia sẻ. Nút ngoài cùng (chia sẻ) canh icon vào lề phải (lưới header chung 1.3.1017).
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
                icon("square.and.arrow.up", alignment: .trailing)
            }
            .disabled(isShareDisabled)
            .accessibilityLabel("Chia sẻ báo cáo kiểm tra")
        }
    }

    private var drawsMinimize: Bool {
        showsMinimize && sheetPageBack == nil
    }

    /// ⌄ thu nhỏ đứng trước tiêu đề khi màn mở dạng sheet và lượt đang chạy; còn lại `nil` (⌄ nằm ở cụm phải / không có).
    static func leadingMinimize(isSheet: Bool, isRunning: Bool, action: @escaping () -> Void) -> HeaderLeadingIconButton? {
        guard isSheet, isRunning else { return nil }
        return HeaderLeadingIconButton(
            systemName: "chevron.down",
            accessibilityLabel: "Thu nhỏ, lượt kiểm tra chạy tiếp ở nền",
            action: action
        )
    }

    private func icon(_ systemName: String, alignment: Alignment = .center) -> some View {
        Image(systemName: systemName)
            .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
            .frame(
                width: drawsMinimize ? HeaderButtonMetrics.pairIconWidth : HeaderMetrics.iconFrameWidth,
                height: 36,
                alignment: alignment
            )
            .contentShape(Rectangle())
    }
}
