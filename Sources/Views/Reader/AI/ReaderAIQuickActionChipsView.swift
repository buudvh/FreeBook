import SwiftUI

/// Thanh cuộn ngang chứa các chip hành động nhanh cho Reader AI.
public struct ReaderAIQuickActionChipsView: View {
    public let onSelectAction: (ActionType) -> Void

    public enum ActionType: Sendable {
        case summarizeChapter
        case extractNamesCurrentChapter
        case extractNamesAllDownloaded
        case explainContextAndCharacters
        case translateSmoothly
    }

    public init(onSelectAction: @escaping (ActionType) -> Void) {
        self.onSelectAction = onSelectAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(icon: "doc.text.magnifyingglass", title: "Tóm tắt chương", type: .summarizeChapter)
                chipButton(icon: "tag", title: "Lọc name chương này", type: .extractNamesCurrentChapter)
                chipButton(icon: "books.vertical.fill", title: "Lọc name cả bộ tải", type: .extractNamesAllDownloaded, isSpecial: true)
                chipButton(icon: "person.2", title: "Nhân vật & Bối cảnh", type: .explainContextAndCharacters)
                chipButton(icon: "character.book.closed", title: "Dịch mượt raw", type: .translateSmoothly)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func chipButton(icon: String, title: String, type: ActionType, isSpecial: Bool = false) -> some View {
        Button(action: { onSelectAction(type) }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSpecial ? Color.purple.opacity(0.15) : Color(UIColor.secondarySystemBackground))
            .foregroundColor(isSpecial ? .purple : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSpecial ? Color.purple.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}
