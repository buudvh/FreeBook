import SwiftUI

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct TextMeasurement: Equatable {
    var token: Int = 0
    var height: CGFloat = 0
}

private struct FullHeightPreferenceKey: PreferenceKey {
    static var defaultValue = TextMeasurement()
    static func reduce(value: inout TextMeasurement, nextValue: () -> TextMeasurement) {
        let next = nextValue()
        if next.token > value.token {
            value = next
        } else if next.token == value.token, next.height > value.height {
            value = next
        }
    }
}

private struct CollapsedHeightPreferenceKey: PreferenceKey {
    static var defaultValue = TextMeasurement()
    static func reduce(value: inout TextMeasurement, nextValue: () -> TextMeasurement) {
        let next = nextValue()
        if next.token > value.token {
            value = next
        } else if next.token == value.token, next.height > value.height {
            value = next
        }
    }
}

public final class WrappingLabel: UILabel {
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, preferredMaxLayoutWidth != bounds.width {
            preferredMaxLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
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

    public func makeUIView(context: Context) -> WrappingLabel {
        let label = WrappingLabel()
        label.numberOfLines = lineLimit ?? 0
        label.textAlignment = .justified
        label.lineBreakMode = .byTruncatingTail
        label.font = font
        label.textColor = textColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    public func updateUIView(_ uiView: WrappingLabel, context: Context) {
        uiView.text = text
        uiView.numberOfLines = lineLimit ?? 0
        uiView.textAlignment = .justified
        uiView.font = font
        uiView.textColor = textColor
        if uiView.bounds.width > 0 {
            uiView.preferredMaxLayoutWidth = uiView.bounds.width
        }
        uiView.invalidateIntrinsicContentSize()
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

private extension Font {
    func toUIFont() -> UIFont {
        var queue: [Any] = [self]
        for _ in 0..<4 {
            var next: [Any] = []
            for value in queue {
                if let style = value as? Font.TextStyle {
                    return UIFont.preferredFont(forTextStyle: style.uiTextStyle)
                }
                for child in Mirror(reflecting: value).children {
                    next.append(child.value)
                }
            }
            queue = next
        }
        return UIFont.preferredFont(forTextStyle: .body)
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
    @State private var measurementToken = 0
    @State private var fullMeasurement = TextMeasurement()
    @State private var collapsedMeasurement = TextMeasurement()

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
            if newWidth > 0 && abs(availableWidth - newWidth) > 0.5 {
                availableWidth = newWidth
            }
        }
        .onPreferenceChange(FullHeightPreferenceKey.self) { measurement in
            if measurement.height > 0 {
                fullMeasurement = measurement
                checkTruncation()
            }
        }
        .onPreferenceChange(CollapsedHeightPreferenceKey.self) { measurement in
            if measurement.height > 0 {
                collapsedMeasurement = measurement
                checkTruncation()
            }
        }
        .onChange(of: text) { _, _ in
            isExpanded = false
            isTruncated = false
            measurementToken += 1
        }
    }

    @ViewBuilder
    private var textContent: some View {
        if isJustified {
            JustifiedTextLabel(
                text: text,
                lineLimit: isExpanded ? 0 : lineLimit,
                font: font.toUIFont(),
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
                    font: font.toUIFont(),
                    textColor: .clear
                )
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CollapsedHeightPreferenceKey.self,
                            value: TextMeasurement(token: measurementToken, height: geo.size.height)
                        )
                    }
                )

                JustifiedTextLabel(
                    text: text,
                    lineLimit: 0,
                    font: font.toUIFont(),
                    textColor: .clear
                )
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { fullGeo in
                        Color.clear.preference(
                            key: FullHeightPreferenceKey.self,
                            value: TextMeasurement(token: measurementToken, height: fullGeo.size.height)
                        )
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
                            Color.clear.preference(
                                key: CollapsedHeightPreferenceKey.self,
                                value: TextMeasurement(token: measurementToken, height: geo.size.height)
                            )
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
                            Color.clear.preference(
                                key: FullHeightPreferenceKey.self,
                                value: TextMeasurement(token: measurementToken, height: fullGeo.size.height)
                            )
                        }
                    )
            }
            .opacity(0)
            .allowsHitTesting(false)
            .frame(width: width, height: 0, alignment: .topLeading)
        }
    }

    private func checkTruncation() {
        guard fullMeasurement.token == measurementToken,
              collapsedMeasurement.token == measurementToken,
              fullMeasurement.height > 0,
              collapsedMeasurement.height > 0 else { return }
        let truncated = fullMeasurement.height > collapsedMeasurement.height + 0.5
        if isTruncated != truncated {
            isTruncated = truncated
        }
    }
}