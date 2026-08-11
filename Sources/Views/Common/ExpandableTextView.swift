import SwiftUI

private struct FullHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TruncatedHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct ExpandableTextView: View {
    let text: String
    let lineLimit: Int
    let font: Font
    let foregroundColor: Color
    
    @State private var isExpanded = false
    @State private var isTruncated = false
    @State private var fullHeight: CGFloat = 0
    @State private var truncatedHeight: CGFloat = 0
    
    public init(
        text: String,
        lineLimit: Int,
        font: Font = .body,
        foregroundColor: Color = .secondary
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.font = font
        self.foregroundColor = foregroundColor
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
                .lineLimit(isExpanded ? nil : lineLimit)
                .multilineTextAlignment(.leading)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TruncatedHeightPreferenceKey.self, value: geo.size.height)
                    }
                )
                .background(
                    Text(text)
                        .font(font)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .background(
                            GeometryReader { fullGeo in
                                Color.clear.preference(key: FullHeightPreferenceKey.self, value: fullGeo.size.height)
                            }
                        )
                        .hidden()
                )
                .onPreferenceChange(FullHeightPreferenceKey.self) { newFullHeight in
                    self.fullHeight = newFullHeight
                    checkTruncation()
                }
                .onPreferenceChange(TruncatedHeightPreferenceKey.self) { newTruncatedHeight in
                    self.truncatedHeight = newTruncatedHeight
                    checkTruncation()
                }
            
            if isTruncated {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Thu gọn" : "Xem thêm")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func checkTruncation() {
        if fullHeight > 0 && truncatedHeight > 0 {
            let truncated = fullHeight > truncatedHeight + 2.0
            if isTruncated != truncated {
                isTruncated = truncated
            }
        }
    }
}
