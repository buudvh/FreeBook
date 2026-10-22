import SwiftUI

/// Menu điều khiển cấu hình dịch thuật 3 mức: Truyện này > Nguồn này > Toàn cục.
/// Nút + chấm chỉ báo ở đây; Popover nhỏ gọn (Toggle Bật/Tắt + Dropdown chọn phạm vi + Nút Lưu lại) là
/// `TranslationScopePopupView`, dùng chung với menu header Khám phá.
public struct ReaderTranslationScopeMenuView: View {
    /// Phạm vi của bảng dịch; `TranslationScopePopupView` dùng, giữ chỗ cũ vì là API public của nút.
    public enum TranslationPopupScope: String, CaseIterable, Identifiable {
        case book = "Truyện này"
        case source = "Nguồn này"
        case global = "Tất cả"

        public var id: String { rawValue }
    }

    public let bookId: String
    public let packageId: String
    public let sourceName: String
    public let textColor: Color?
    public let showBackground: Bool
    public let isChineseSourceHint: Bool?
    public let iconSize: CGFloat
    public let frameWidth: CGFloat?
    public let frameHeight: CGFloat?

    @State private var status: TranslationConfigStore.ResolvedStatus
    @State private var showingPopup = false

    public init(
        bookId: String,
        packageId: String = "",
        sourceName: String = "",
        textColor: Color? = nil,
        showBackground: Bool = true,
        isChineseSourceHint: Bool? = nil,
        iconSize: CGFloat = 19,
        frameWidth: CGFloat? = nil,
        frameHeight: CGFloat? = nil
    ) {
        self.bookId = bookId
        self.packageId = packageId
        self.sourceName = sourceName
        self.textColor = textColor
        self.showBackground = showBackground
        self.isChineseSourceHint = isChineseSourceHint
        self.iconSize = iconSize
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        _status = State(initialValue: TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint))
    }

    private var resolvedWidth: CGFloat {
        if let frameWidth = frameWidth { return frameWidth }
        if !showBackground && iconSize <= 14 { return 32 }
        return 44
    }

    private var resolvedHeight: CGFloat {
        if let frameHeight = frameHeight { return frameHeight }
        if !showBackground && iconSize <= 14 { return 32 }
        return showBackground ? 52 : 36
    }

    private var dotIndicator: some View {
        Circle()
            .fill(status.bookOverride == .enabled ? Color.green : Color.red)
            .frame(
                width: showBackground ? 7 : (iconSize <= 14 ? 4.5 : 6),
                height: showBackground ? 7 : (iconSize <= 14 ? 4.5 : 6)
            )
    }

    public var body: some View {
        Button(action: {
            refreshStatus()
            showingPopup = true
        }) {
            if showBackground {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: status.isEnabled ? "character.bubble.fill" : "character.bubble")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundColor(status.isEnabled ? .white : (textColor?.opacity(0.45) ?? .secondary.opacity(0.6)))
                        .frame(width: resolvedWidth, height: resolvedHeight)
                        .background(
                            textColor?.opacity(0.08) ?? Color(UIColor.systemGray6),
                            in: RoundedRectangle(cornerRadius: 6)
                        )

                    // Dấu chấm nhỏ chỉ thị truyện này đang có cấu hình riêng biệt
                    if status.bookOverride != .inherited {
                        dotIndicator
                            .padding(.top, 8)
                            .padding(.trailing, 4)
                    }
                }
            } else {
                Image(systemName: status.isEnabled ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(status.isEnabled ? .white : (textColor?.opacity(0.45) ?? .secondary.opacity(0.6)))
                    .overlay(alignment: .topTrailing) {
                        if status.bookOverride != .inherited {
                            dotIndicator
                                .offset(x: iconSize <= 14 ? 3 : 4, y: iconSize <= 14 ? -2 : -3)
                        }
                    }
                    .frame(width: resolvedWidth, height: resolvedHeight)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status.isEnabled ? "Đang bật dịch" : "Đang tắt dịch")
        .popover(isPresented: $showingPopup, arrowEdge: .top) {
            // Trạng thái bảng (công tắc, phạm vi) khởi tạo trong `TranslationScopePopupView` mỗi lần mở.
            TranslationScopePopupView(
                bookId: bookId,
                packageId: packageId,
                sourceName: sourceName,
                isChineseSourceHint: isChineseSourceHint,
                onDone: {
                    refreshStatus()
                    showingPopup = false
                }
            )
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.dark)
        }
        .onAppear {
            refreshStatus()
        }
        .onChange(of: packageId) { _, _ in
            refreshStatus()
        }
        .onChange(of: bookId) { _, _ in
            refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: TranslationConfigStore.didChangeNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        status = TranslationConfigStore.shared.resolveStatus(bookId: bookId, packageId: packageId, isChineseSourceHint: isChineseSourceHint)
    }
}
