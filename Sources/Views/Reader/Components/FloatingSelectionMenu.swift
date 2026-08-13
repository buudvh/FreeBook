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

    private let menuWidth: CGFloat = 370
    private let gap: CGFloat = 36

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
        onDeleteJunk: @escaping () -> Void
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
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: onTranslate) {
                VStack(spacing: 3) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Dịch")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onSpeak) {
                VStack(spacing: 3) {
                    Image(systemName: "headphones")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Nghe")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onPhoneme) {
                VStack(spacing: 3) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Phiên âm")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onCopy) {
                VStack(spacing: 3) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Copy")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onReadSelected) {
                VStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Đọc")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 48)
            }

            Divider()
                .frame(height: 24)
                .background(Color.white.opacity(0.15))

            Button(action: onDeleteJunk) {
                VStack(spacing: 3) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Xoá")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.red)
                .frame(width: 60, height: 48)
            }
        }
        .padding(.horizontal, 4)
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
}
