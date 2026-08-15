import SwiftUI

struct MarqueeText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight

    @State private var contentWidth: CGFloat = 0
    @State private var animate = false

    private let speed: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let shouldScroll = contentWidth > containerWidth
            let duration = shouldScroll ? Double(contentWidth) / Double(speed) : 0

            ZStack {
                if shouldScroll {
                    HStack(spacing: 0) {
                        Text(text)
                            .font(.system(size: fontSize, weight: weight))
                            .fixedSize()
                        Text(text)
                            .font(.system(size: fontSize, weight: weight))
                            .fixedSize()
                    }
                    .offset(x: animate ? -contentWidth : 0)
                    .onAppear {
                        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                            animate = true
                        }
                    }
                    .onDisappear {
                        animate = false
                    }
                } else {
                    Text(text)
                        .font(.system(size: fontSize, weight: weight))
                        .lineLimit(1)
                }
            }
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: fontSize + 4)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            contentWidth = (text as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: uiFontWeight(weight))
            ]).width
        }
    }

    private func uiFontWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .regular: return .regular
        default: return .bold
        }
    }
}