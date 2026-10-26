import SwiftUI

/// Thanh cuộn ngang chứa các chip hành động nhanh cho Reader AI.
public struct ReaderAIQuickActionChipsView: View {
    /// Có lệnh AI đang chạy (chat hoặc quét, của bất kỳ truyện nào): cả hàng chip mờ và không bấm được (1.3.524).
    /// Vẫn hiện để bố cục không giật khi lệnh bắt đầu/kết thúc; hàng chip vẫn cuộn ngang được.
    public let isDisabled: Bool
    /// Chip không dùng được với provider đang chọn (1.3.609: "Dịch mượt raw" với Chế độ AI của Google): mờ, icon ổ khoá,
    /// không bấm được.
    public let disabledActions: Set<ActionType>
    public let onSelectAction: (ActionType) -> Void

    public enum ActionType: Hashable, Sendable {
        case summarizeChapter
        case extractNamesCurrentChapter
        case extractNamesAllDownloaded
        case explainContextAndCharacters
        case translateSmoothly
    }

    public init(
        isDisabled: Bool = false,
        disabledActions: Set<ActionType> = [],
        onSelectAction: @escaping (ActionType) -> Void
    ) {
        self.isDisabled = isDisabled
        self.disabledActions = disabledActions
        self.onSelectAction = onSelectAction
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(icon: "doc.text.magnifyingglass", title: "Tóm tắt chương", type: .summarizeChapter)
                chipButton(icon: "tag", title: "Lọc name chương này", type: .extractNamesCurrentChapter)
                chipButton(icon: "books.vertical.fill", title: "Lọc name nhiều chương", type: .extractNamesAllDownloaded, isSpecial: true)
                chipButton(icon: "person.2", title: "Nhân vật & Bối cảnh", type: .explainContextAndCharacters)
                chipButton(icon: "character.book.closed", title: "Dịch mượt raw", type: .translateSmoothly)
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.4 : 1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func chipButton(icon: String, title: String, type: ActionType, isSpecial: Bool = false) -> some View {
        let isLocked = disabledActions.contains(type)
        return Button(action: { onSelectAction(type) }) {
            HStack(spacing: 5) {
                Image(systemName: isLocked ? "lock.fill" : icon)
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
        .disabled(isLocked)
        .opacity(isLocked ? 0.45 : 1)
        .accessibilityHint(isLocked ? "Không dùng được với provider AI đang chọn" : "")
    }
}
