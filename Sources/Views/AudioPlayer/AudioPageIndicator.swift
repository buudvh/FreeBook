import SwiftUI

/// Chấm chỉ trang của màn nghe: trang đang chọn là viên dài màu nhấn, trang khác là chấm trắng mờ. Chạm chấm ⇒ sang trang
/// đó.
struct AudioPageIndicator: View {
    @Binding var selection: AudioPlayerPage

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AudioPlayerPage.allCases, id: \.self) { page in
                let isSelected = page == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selection = page
                    }
                } label: {
                    Capsule()
                        .fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.35)))
                        .frame(width: isSelected ? 18 : 6, height: 6)
                        .padding(.horizontal, 4)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
    }
}
