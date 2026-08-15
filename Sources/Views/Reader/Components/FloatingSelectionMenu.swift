import SwiftUI

public struct FloatingSelectionMenu: View {
    public let selectionMinY: CGFloat
    public let selectionMaxY: CGFloat
    public let geometryOriginY: CGFloat
    public let screenWidth: CGFloat
    public let onTranslate: () -> Void
    public let onSpeak: () -> Void
    public let onPhoneme: () -> Void
    public let onCopy: () -> Void
    public let onReadSelected: () -> Void
    public let onDeleteJunk: () -> Void
    public let onAddToTTSReplacement: () -> Void

    private let menuWidth: CGFloat = 215
    private let gap: CGFloat = 36
    private let buttonWidth: CGFloat = 52

    public init(
        selectionMinY: CGFloat,
        selectionMaxY: CGFloat,
        geometryOriginY: CGFloat,
        screenWidth: CGFloat,
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
        self.onTranslate = onTranslate
        self.onSpeak = onSpeak
        self.onPhoneme = onPhoneme
        self.onCopy = onCopy
        self.onReadSelected = onReadSelected
        self.onDeleteJunk = onDeleteJunk
        self.onAddToTTSReplacement = onAddToTTSReplacement
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Hàng 1: Nghe merge 2 hàng (96pt) + Phiên âm, Copy, Đọc
            HStack(spacing: 0) {
                Button(action: onSpeak) {
                    menuItemContent(icon: "headphones", label: "Nghe")
                }
                .frame(width: buttonWidth, height: 96)

                verticalDivider(height: 96)

                Button(action: onPhoneme) {
                    menuItemContent(icon: "music.note", label: "Phiên âm")
                }
                .frame(width: buttonWidth, height: 96)

                verticalDivider(height: 96)

                Button(action: onCopy) {
                    menuItemContent(icon: "doc.on.doc.fill", label: "Copy")
                }
                .frame(width: buttonWidth, height: 96)

                verticalDivider(height: 96)

                Button(action: onReadSelected) {
                    menuItemContent(icon: "speaker.wave.2.fill", label: "Đọc")
                }
                .frame(width: buttonWidth, height: 96)
            }
            .frame(height: 96)

            // Divider ngang giữa 2 hàng
            Divider()
                .background(Color.white.opacity(0.15))

            // Hàng 2: spacer cho cột Nghe + Thay thế, Xoá, Dịch
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: buttonWidth, height: 48)

                verticalDivider(height: 48)

                Button(action: onAddToTTSReplacement) {
                    menuItemContent(icon: "textformat.alt", label: "Thay thế")
                }
                .frame(width: buttonWidth, height: 48)

                verticalDivider(height: 48)

                Button(action: onDeleteJunk) {
                    menuItemContent(icon: "trash.fill", label: "Xoá")
                        .foregroundColor(.red)
                }
                .frame(width: buttonWidth, height: 48)

                verticalDivider(height: 48)

                Button(action: onTranslate) {
                    menuItemContent(icon: "character.book.closed.fill", label: "Dịch")
                }
                .frame(width: buttonWidth, height: 48)
            }
            .frame(height: 48)
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
            x: min(max(screenWidth / 2, menuWidth / 2 + 16), screenWidth - menuWidth / 2 - 16),
            y: {
                let localMinY = selectionMinY - geometryOriginY
                let localMaxY = selectionMaxY - geometryOriginY
                return localMinY > 80 ? localMinY - gap : localMaxY + gap
            }()
        )
    }

    private func menuItemContent(icon: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.white)
    }

    private func verticalDivider(height: CGFloat) -> some View {
        Divider()
            .frame(height: height)
            .background(Color.white.opacity(0.15))
    }
}