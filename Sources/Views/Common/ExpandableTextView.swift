import SwiftUI

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct FullHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct CollapsedHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

public struct JustifiedTextLabel: UIViewRepresentable {
    public let text: String
    public let lineLimit: Int?
    public let font: UIFont
    public let textColor: UIColor

    public init(
        text: String,
        lineLimit: Int? = nil,
        font: UIFont = .preferredFont(forTextStyle: .subheadline),
        textColor: UIColor = .secondaryLabel
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.font = font
        self.textColor = textColor
    }

    public func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = lineLimit ?? 0
        label.textAlignment = .justified
        label.lineBreakMode = .byTruncatingTail
        label.font = font
        label.textColor = textColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    public func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.text = text
        uiView.numberOfLines = lineLimit ?? 0
        uiView.textAlignment = .justified
        uiView.font = font
        uiView.textColor = textColor
        uiView.invalidateIntrinsicContentSize()
    }
}

public struct ExpandableTextView: View {
    let text: String
    let lineLimit: Int
    let font: Font
    let foregroundColor: Color
    let isJustified: Bool

    @State private var isExpanded = false
    @State private var isTruncated = false
    @State private var availableWidth: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    public init(
        text: String,
        lineLimit: Int,
        font: Font = .body,
        foregroundColor: Color = .secondary,
        isJustified: Bool = false
    ) {
        self.text = text
        self.lineLimit = lineLimit
        self.font = font
        self.foregroundColor = foregroundColor
        self.isJustified = isJustified
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            textContent
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
                    }
                )

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
        .overlay(alignment: .topLeading) {
            if availableWidth > 0 {
                measurementSubtree(for: availableWidth)
            }
        }
        .onPreferenceChange(WidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && abs(self.availableWidth - newWidth) > 0.5 {
                self.availableWidth = newWidth
            }
        }
        .onPreferenceChange(FullHeightPreferenceKey.self) { newFullHeight in
            if newFullHeight > 0 {
                self.fullHeight = newFullHeight
                checkTruncation()
            }
        }
        .onPreferenceChange(CollapsedHeightPreferenceKey.self) { newCollapsedHeight in
            if newCollapsedHeight > 0 {
                self.collapsedHeight = newCollapsedHeight
                checkTruncation()
            }
        }
        .onChange(of: text) { _, _ in
            self.isExpanded = false
            self.fullHeight = 0
            self.collapsedHeight = 0
            self.isTruncated = false
        }
    }

    @ViewBuilder
    private var textContent: some View {
        if isJustified {
            JustifiedTextLabel(
                text: text,
                lineLimit: isExpanded ? 0 : lineLimit,
                font: .preferredFont(forTextStyle: .subheadline),
                textColor: UIColor(foregroundColor)
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
                .lineLimit(isExpanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func measurementSubtree(for width: CGFloat) -> some View {
        if isJustified {
            ZStack(alignment: .topLeading) {
                JustifiedTextLabel(
                    text: text,
                    lineLimit: lineLimit,
                    font: .preferredFont(forTextStyle: .subheadline),
                    textColor: .clear
                )
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: CollapsedHeightPreferenceKey.self, value: geo.size.height)
                    }
                )

                JustifiedTextLabel(
                    text: text,
                    lineLimit: 0,
                    font: .preferredFont(forTextStyle: .subheadline),
                    textColor: .clear
                )
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { fullGeo in
                        Color.clear.preference(key: FullHeightPreferenceKey.self, value: fullGeo.size.height)
                    }
                )
            }
            .opacity(0)
            .allowsHitTesting(false)
            .frame(width: width, height: 0, alignment: .topLeading)
        } else {
            ZStack(alignment: .topLeading) {
                Text(text)
                    .font(font)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: CollapsedHeightPreferenceKey.self, value: geo.size.height)
                        }
                    )

                Text(text)
                    .font(font)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { fullGeo in
                            Color.clear.preference(key: FullHeightPreferenceKey.self, value: fullGeo.size.height)
                        }
                    )
            }
            .opacity(0)
            .allowsHitTesting(false)
            .frame(width: width, height: 0, alignment: .topLeading)
        }
    }

    private func checkTruncation() {
        if fullHeight > 0 && collapsedHeight > 0 {
            let truncated = fullHeight > collapsedHeight + 0.5
            if isTruncated != truncated {
                isTruncated = truncated
            }
        }
    }
}
