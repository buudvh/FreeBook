import SwiftUI

public struct FloatingSelectionMenu: View {
    public let selectionMinY: CGFloat
    public let selectionMaxY: CGFloat
    public let geometryOriginY: CGFloat
    public let screenWidth: CGFloat
    public let screenHeight: CGFloat
    public let onTranslate: () -> Void
    public let onSpeak: () -> Void
    public let onPhoneme: () -> Void
    public let onCopy: () -> Void
    public let onReadSelected: () -> Void
    public let onDeleteJunk: () -> Void
    public let onAddToTTSReplacement: () -> Void

    private let menuWidth: CGFloat = 199
    private let gap: CGFloat = 24
    private let ngheWidth: CGFloat = 56
    private let buttonWidth: CGFloat = 46
    private let row1Height: CGFloat = 46
    private let row2Height: CGFloat = 46
    private let menuHeight: CGFloat = 46 + 1 + 46
    private let margin: CGFloat = 16

    public init(
        selectionMinY: CGFloat,
        selectionMaxY: CGFloat,
        geometryOriginY: CGFloat,
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        onTranslate: @escaping () -> Void,
        onSpeak: @escaping () -> Void,
        onPhoneme: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onReadSelected: @escaping () -> Void,
        onDeleteJunk: @escaping () -> Void,
        onAddToTTSReplacement: @escaping () -> Void
    ) {
        self.selectionMinY = selectionMinY
        self.selectionMaxY = selectionMaxY
        self.geometryOriginY = geometryOriginY
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.onTranslate = onTranslate
        self.onSpeak = onSpeak
        self.onPhoneme = onPhoneme
        self.onCopy = onCopy
        self.onReadSelected = onReadSelected
        self.onDeleteJunk = onDeleteJunk
        self.onAddToTTSReplacement = onAddToTTSReplacement
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Cột 1: Nghe merge 2 hàng (chiều cao full menu)
            Button(action: onSpeak) {
                menuItemContent(icon: "headphones", label: "Nghe")
            }
            .frame(width: ngheWidth, height: menuHeight)

            verticalDivider(height: menuHeight)

            // Cột 2-4: 2 hàng, divider ngang chỉ nằm trong khối này
            VStack(spacing: 0) {
                // Hàng 1: Phiên âm, Copy, Đọc
                HStack(spacing: 0) {
                    Button(action: onPhoneme) {
                        menuItemContent(icon: "music.note", label: "Phiên âm")
                    }
                    .frame(width: buttonWidth, height: row1Height)

                    Button(action: onCopy) {
                        menuItemContent(icon: "doc.on.doc.fill", label: "Copy")
                    }
                    .frame(width: buttonWidth, height: row1Height)

                    Button(action: onReadSelected) {
                        menuItemContent(icon: "speaker.wave.2.fill", label: "Đọc")
                    }
                    .frame(width: buttonWidth, height: row1Height)
                }
                .frame(height: row1Height)

                // Divider ngang giữa 2 hàng (không chạy qua cột Nghe)
                Divider()
                    .background(Color.white.opacity(0.15))

                // Hàng 2: Dịch, Thay thế, Xoá
                HStack(spacing: 0) {
                    Button(action: onTranslate) {
                        menuItemContent(icon: "character.book.closed.fill", label: "Dịch")
                    }
                    .frame(width: buttonWidth, height: row2Height)

                    Button(action: onAddToTTSReplacement) {
                        menuItemContent(icon: "textformat.alt", label: "Thay thế")
                    }
                    .frame(width: buttonWidth, height: row2Height)

                    Button(action: onDeleteJunk) {
                        menuItemContent(icon: "trash.fill", label: "Xoá")
                            .foregroundColor(.red)
                    }
                    .frame(width: buttonWidth, height: row2Height)
                }
                .frame(height: row2Height)
            }
        }
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.92))
                .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .fixedSize()
        .position(
            x: min(max(screenWidth / 2, menuWidth / 2 + margin), screenWidth - menuWidth / 2 - margin),
            y: {
                let localMinY = selectionMinY - geometryOriginY
                let localMaxY = selectionMaxY - geometryOriginY
                let topLimit = margin + menuHeight / 2
                let bottomLimit = screenHeight - margin - menuHeight / 2

                let aboveY = localMinY - gap - menuHeight / 2
                let belowY = localMaxY + gap + menuHeight / 2

                if aboveY >= topLimit {
                    return aboveY
                } else if belowY <= bottomLimit {
                    return belowY
                } else {
                    return min(max(aboveY, topLimit), bottomLimit)
                }
            }()
        )
    }

    private func menuItemContent(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(height: 15)

            Text(label)
                .font(.system(size: 7, weight: .bold))
                .lineLimit(1)
                .frame(height: 15, alignment: .center)
                .frame(maxWidth: .infinity)
        }
        .foregroundColor(.white)
    }

    private func verticalDivider(height: CGFloat) -> some View {
        Divider()
            .frame(height: height)
            .background(Color.white.opacity(0.15))
    }
}